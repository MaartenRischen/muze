// Jammerman — Tracking Coordinator
// Connects camera -> face/hand tracking -> state -> audio
// Mirrors web's app.js main loop signal flow

import Foundation
import Combine
import CoreMedia

class TrackingCoordinator: ObservableObject {
    let camera = CameraManager()
    let faceTracker = FaceTracker()
    let handTracker = HandTracker()

    @Published var state = JammermanState()
    let audioEngine = AudioEngine()
    let loopRecorder = LoopRecorder()
    let sceneManager = SceneManager()
    let gyroscopeManager = GyroscopeManager()
    let recordingManager = RecordingManager()

    // 1-Euro filters for smoothing
    private var filters: [String: OneEuroFilter] = [:]

    // Face loss grace period
    private var faceLostTime: Date?
    private let faceLostGraceMs: TimeInterval = 0.4

    // Previous melody state
    private var prevMelodyNote: Int?
    private var prevHandOpen = true
    private var currentPadKey = ""

    init() {
        setupFilters()
        setupCamera()
        setupDefaultDrumPattern()
        loopRecorder.audioEngine = audioEngine
        gyroscopeManager.audioEngine = audioEngine
    }

    private func setupFilters() {
        filters = [
            "mouth":  OneEuroFilter(freq: 30, minCutoff: 1.0, beta: 0.007, dCutoff: 1.0),
            "lip":    OneEuroFilter(freq: 30, minCutoff: 0.5, beta: 0.004, dCutoff: 1.0),
            "brow":   OneEuroFilter(freq: 30, minCutoff: 1.0, beta: 0.007, dCutoff: 1.0),
            "eye":    OneEuroFilter(freq: 30, minCutoff: 1.0, beta: 0.005, dCutoff: 1.0),
            "mouthW": OneEuroFilter(freq: 30, minCutoff: 1.0, beta: 0.005, dCutoff: 1.0),
            "handX":  OneEuroFilter(freq: 30, minCutoff: 1.0, beta: 0.007, dCutoff: 1.0),
            "handY":  OneEuroFilter(freq: 30, minCutoff: 1.0, beta: 0.007, dCutoff: 1.0),
        ]
    }

    private func setupCamera() {
        camera.onFrame = { [weak self] sampleBuffer in
            self?.processFrame(sampleBuffer)
        }
    }

    private func setupDefaultDrumPattern() {
        // Basic pattern: kick on 1,3; snare on 2,4; hat on all 8ths
        let kick:  [Int] = [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0]
        let snare: [Int] = [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]
        let hat:   [Int] = [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]
        audioEngine.setDrumPattern([kick, snare, hat])
    }

    private var saveTimer: Timer?

    func start() {
        // Load saved settings
        JammermanStorage.load(state: state, engine: audioEngine)
        camera.start()
        audioEngine.start()
        // Auto-save every 2 seconds
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            JammermanStorage.save(state: self.state, engine: self.audioEngine)
        }
    }

    func stop() {
        JammermanStorage.save(state: state, engine: audioEngine)
        saveTimer?.invalidate()
        camera.stop()
        audioEngine.stop()
        gyroscopeManager.deactivate()
        loopRecorder.clearAll()
    }

    // MARK: - Frame Processing (runs on camera queue)

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        let timestamp = now.timeIntervalSince1970 * 1000

        // Face detection (runs every other frame via internal stagger)
        if let face = faceTracker.detect(sampleBuffer: sampleBuffer) {
            faceLostTime = nil
            let s = state

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state.mouthOpenness = Float(self.filters["mouth"]!.filter(Double(face.mouthOpenness), timestamp: timestamp))
                self.state.lipCorner = Float(self.filters["lip"]!.filter(Double(face.lipCorner), timestamp: timestamp))
                self.state.browHeight = Float(self.filters["brow"]!.filter(Double(face.browHeight), timestamp: timestamp))
                self.state.eyeOpenness = Float(self.filters["eye"]!.filter(Double(face.eyeOpenness), timestamp: timestamp))
                self.state.mouthWidth = Float(self.filters["mouthW"]!.filter(Double(face.mouthWidth), timestamp: timestamp))
                self.state.headPitch = face.headPitch
                self.state.headYaw = face.headYaw
                self.state.headRoll = face.headRoll
                self.state.faceDetected = true
                self.updateAudio()
            }
        } else {
            // Face loss grace period
            if faceLostTime == nil { faceLostTime = now }
            if let lost = faceLostTime, now.timeIntervalSince(lost) > faceLostGraceMs {
                DispatchQueue.main.async { [weak self] in
                    self?.state.faceDetected = false
                }
            }
        }

        // Hand detection (runs every other frame, staggered with face)
        if let hand = handTracker.detect(sampleBuffer: sampleBuffer) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state.handPresent = hand.handPresent
                if hand.handPresent {
                    self.state.handX = Float(self.filters["handX"]!.filter(Double(hand.handX), timestamp: timestamp))
                    self.state.handY = Float(self.filters["handY"]!.filter(Double(hand.handY), timestamp: timestamp))
                    self.state.handOpen = hand.handOpen
                } else {
                    self.state.handPresent = false
                }
                self.updateMelody()
            }
        }
    }

    // MARK: - Audio Logic (mirrors app.js)

    private func updateAudio() {
        guard state.faceDetected else {
            if !currentPadKey.isEmpty {
                audioEngine.releasePad()
                currentPadKey = ""
            }
            if prevMelodyNote != nil {
                audioEngine.stopMelody()
                prevMelodyNote = nil
            }
            return
        }

        // Update face-driven audio params
        audioEngine.updateParams(state: state)

        // Scale selection from lip corner
        if !state.modeFrozen {
            state.currentScale = MusicTheory.selectScale(lipCorner: state.lipCorner, extraScaleMode: state.extraScaleMode)
            state.currentModeName = MusicTheory.getScaleName(state.currentScale)
        }

        let scale = state.currentScale
        let octShift = Int(floor(state.browHeight * Float(JammermanConfig.octaveRange))) * 12
        let effectiveRoot = state.effectiveRoot + octShift

        // Update arp notes (both arps)
        let degree = JammermanConfig.chordDegrees[state.chordIndex % JammermanConfig.chordDegrees.count]
        let arpNotes = MusicTheory.getArpNotes(scale: scale, root: effectiveRoot, degree: degree, octaveRange: 2)
        audioEngine.updateArpNotes(arpNotes)
        audioEngine.updateArp2Notes(arpNotes)

        // Pad voicing
        let padNotes = MusicTheory.getPadVoicing(root: effectiveRoot, scale: scale, degree: degree)
        let padKey = padNotes.joined(separator: ",")
        if padKey != currentPadKey {
            currentPadKey = padKey
            audioEngine.triggerPad(notes: padNotes)
        }
    }

    private func updateMelody() {
        guard state.faceDetected, state.handPresent else {
            if prevMelodyNote != nil {
                audioEngine.stopMelody()
                prevMelodyNote = nil
                state.melodyNote = nil
                // Record note off if loop recorder is active
                loopRecorder.recordNoteOff()
            }
            return
        }

        let scale = state.currentScale
        let effectiveRoot = state.effectiveRoot
        let note = MusicTheory.quantize(value: 1 - state.handY, scale: scale, root: effectiveRoot, octaveRange: JammermanConfig.octaveRange)
        state.melodyNote = note

        // Record note if loop recorder is active
        if loopRecorder.state == .recording || loopRecorder.state == .overdubbing {
            if note != prevMelodyNote {
                loopRecorder.recordNote(note)
            }
        }

        // Articulation change
        if state.handOpen != prevHandOpen {
            if !state.handOpen, prevMelodyNote != nil {
                audioEngine.stopMelody()
                audioEngine.startMelody(note)
            }
            prevHandOpen = state.handOpen
        }

        if note != prevMelodyNote {
            if state.handOpen || state.portamentoMode {
                audioEngine.updateMelody(note)
            } else {
                audioEngine.stopMelody()
                audioEngine.startMelody(note)
            }
            prevMelodyNote = note
        }
    }

    // MARK: - UI Actions

    func toggleMute(_ channel: String) {
        audioEngine.toggleMute(channel: channel)
    }
}
