// Jammerman — Tracking Coordinator
// Connects camera -> face/hand tracking -> state -> audio
// Mirrors web's app.js main loop signal flow

import Foundation
import Combine
import CoreMedia
import CoreImage
import simd
import Vision

class TrackingCoordinator: ObservableObject {
    let camera = CameraManager()
    let faceTracker = FaceTracker()
    let handTracker = HandTracker()
    let arKitTracker = ARKitTracker()

    @Published var state = JammermanState()
    let audioEngine = AudioEngine()
    let loopRecorder = LoopRecorder()
    let sceneManager = SceneManager()
    let gyroscopeManager = GyroscopeManager()
    let recordingManager = RecordingManager()
    let personSegmenter = PersonSegmenter()

    // Forward audioEngine changes to trigger SwiftUI re-renders
    private var audioEngineCancellable: AnyCancellable?
    private var loopRecorderCancellable: AnyCancellable?
    private var sceneManagerCancellable: AnyCancellable?
    private var recordingCancellable: AnyCancellable?

    // 1-Euro filters for smoothing
    private var filters: [String: OneEuroFilter] = [:]

    // Face loss grace period
    private var faceLostTime: Date?
    private let faceLostGraceMs: TimeInterval = 0.4

    // Previous melody state
    private var prevMelodyNote: Int?
    private var prevHandOpen = true
    private var currentPadKey = ""

    // Segmentation processing (off main thread, never store raw CVPixelBuffer)
    private let segQueue = DispatchQueue(label: "com.jammerman.segmentation", qos: .userInitiated)
    private let segCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var isProcessingSeg = false
    private var segFrameCount = 0

    deinit {
        saveTimer?.invalidate()
    }

    init() {
        setupFilters()
        setupCamera()
        setupDefaultDrumPattern()
        loopRecorder.audioEngine = audioEngine
        arKitTracker.delegate = self

        // Forward child objectWillChange to self so SwiftUI re-renders
        audioEngineCancellable = audioEngine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        loopRecorderCancellable = loopRecorder.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        sceneManagerCancellable = sceneManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        recordingCancellable = recordingManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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

        // Use ARKit if supported, otherwise AVCaptureSession + Vision
        if ARKitTracker.isSupported {
            // ARKit takes over the camera — DON'T start AVCaptureSession
            arKitTracker.start()
            state.usingARKit = true
            print("[ARKit] Face tracking started")
        } else {
            camera.start()
            state.usingARKit = false
            print("[Vision] Fallback face tracking")
        }

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
        if state.usingARKit {
            arKitTracker.stop()
        } else {
            camera.stop()
        }
        audioEngine.stop()
        gyroscopeManager.deactivate()
        loopRecorder.clearAll()
    }

    // MARK: - Frame Processing (runs on camera queue)

    private var segmentFrameCount = 0

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        let timestamp = now.timeIntervalSince1970 * 1000

        // Background segmentation (every 3rd frame to save CPU)
        segmentFrameCount += 1
        if segmentFrameCount % 3 == 0 {
            personSegmenter.processFrame(sampleBuffer)
        }

        // Face detection (runs every other frame via internal stagger)
        if let result = faceTracker.detect(sampleBuffer: sampleBuffer) {
            faceLostTime = nil
            let face = result.features

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let f = self.filters["mouth"] { self.state.mouthOpenness = Float(f.filter(Double(face.mouthOpenness), timestamp: timestamp)) }
                if let f = self.filters["lip"] { self.state.lipCorner = Float(f.filter(Double(face.lipCorner), timestamp: timestamp)) }
                if let f = self.filters["brow"] { self.state.browHeight = Float(f.filter(Double(face.browHeight), timestamp: timestamp)) }
                if let f = self.filters["eye"] { self.state.eyeOpenness = Float(f.filter(Double(face.eyeOpenness), timestamp: timestamp)) }
                if let f = self.filters["mouthW"] { self.state.mouthWidth = Float(f.filter(Double(face.mouthWidth), timestamp: timestamp)) }
                self.state.headPitch = face.headPitch
                self.state.headYaw = face.headYaw
                self.state.headRoll = face.headRoll
                self.state.faceCenterX = face.faceCenterX
                self.state.faceCenterY = face.faceCenterY
                self.state.faceDetected = true
                // Store raw landmarks for visualizer face mesh drawing
                self.state.rawLandmarks = result.landmarks
                self.state.faceBoundingBox = result.boundingBox
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
                    if let f = self.filters["handX"] { self.state.handX = Float(f.filter(Double(hand.handX), timestamp: timestamp)) }
                    if let f = self.filters["handY"] { self.state.handY = Float(f.filter(Double(hand.handY), timestamp: timestamp)) }
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

        // Seed default notes when toggling ON — mirrors web fix (commit 5a3b3b5)
        // Without this, pad/arp have empty note arrays until face detection runs
        let nowUnmuted = !audioEngine.isMuted(channel)
        guard nowUnmuted else { return } // just muted, no seed needed

        let scale = state.currentScale
        let root = state.effectiveRoot
        let degree = JammermanConfig.chordDegrees[state.chordIndex % JammermanConfig.chordDegrees.count]

        print("[SEED] Seeding \(channel) with scale=\(scale), root=\(root), degree=\(degree)")

        switch channel {
        case "pad":
            let padNotes = MusicTheory.getPadVoicing(root: root, scale: scale, degree: degree)
            print("[SEED] pad notes: \(padNotes)")
            audioEngine.triggerPad(notes: padNotes)
            currentPadKey = padNotes.joined(separator: ",")
        case "arp":
            let notes = MusicTheory.getArpNotes(scale: scale, root: root, degree: degree, octaveRange: 2)
            print("[SEED] arp1 notes: \(notes) (\(notes.count) notes)")
            audioEngine.updateArpNotes(notes)
        case "arp2":
            let notes = MusicTheory.getArpNotes(scale: scale, root: root, degree: degree, octaveRange: 2)
            print("[SEED] arp2 notes: \(notes) (\(notes.count) notes)")
            audioEngine.updateArp2Notes(notes)
        default:
            break
        }
    }
}

// MARK: - ARKitTrackerDelegate

extension TrackingCoordinator: ARKitTrackerDelegate {
    func arKitTracker(_ tracker: ARKitTracker, didUpdateFace features: FaceFeatures,
                      vertices: [simd_float3]?, triangleIndices: [Int16]?) {
        let now = Date()
        let timestamp = now.timeIntervalSince1970 * 1000

        faceLostTime = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let f = self.filters["mouth"] { self.state.mouthOpenness = Float(f.filter(Double(features.mouthOpenness), timestamp: timestamp)) }
            if let f = self.filters["lip"] { self.state.lipCorner = Float(f.filter(Double(features.lipCorner), timestamp: timestamp)) }
            if let f = self.filters["brow"] { self.state.browHeight = Float(f.filter(Double(features.browHeight), timestamp: timestamp)) }
            if let f = self.filters["eye"] { self.state.eyeOpenness = Float(f.filter(Double(features.eyeOpenness), timestamp: timestamp)) }
            if let f = self.filters["mouthW"] { self.state.mouthWidth = Float(f.filter(Double(features.mouthWidth), timestamp: timestamp)) }
            self.state.headPitch = features.headPitch
            self.state.headYaw = features.headYaw
            self.state.headRoll = features.headRoll
            self.state.faceCenterX = features.faceCenterX
            self.state.faceCenterY = features.faceCenterY
            self.state.faceDetected = true

            // Store ARKit face mesh data for visualizer
            self.state.faceVertices = vertices
            self.state.faceTriangleIndices = triangleIndices

            self.updateAudio()
        }
    }

    func arKitTracker(_ tracker: ARKitTracker, didUpdateHand hand: HandFeatures) {
        let timestamp = Date().timeIntervalSince1970 * 1000

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.handPresent = hand.handPresent
            if hand.handPresent {
                if let f = self.filters["handX"] { self.state.handX = Float(f.filter(Double(hand.handX), timestamp: timestamp)) }
                if let f = self.filters["handY"] { self.state.handY = Float(f.filter(Double(hand.handY), timestamp: timestamp)) }
                self.state.handOpen = hand.handOpen
            } else {
                self.state.handPresent = false
            }
            self.updateMelody()
        }
    }

    func arKitTracker(_ tracker: ARKitTracker, didLoseFace: Bool) {
        let now = Date()
        if faceLostTime == nil { faceLostTime = now }
        if let lost = faceLostTime, now.timeIntervalSince(lost) > faceLostGraceMs {
            DispatchQueue.main.async { [weak self] in
                self?.state.faceDetected = false
                self?.state.faceVertices = nil
                self?.state.faceTriangleIndices = nil
            }
        }
    }

    func arKitTracker(_ tracker: ARKitTracker, didUpdateSegmentation buffer: CVPixelBuffer?) {
        guard let buffer = buffer else { return }
        // Skip if already processing or throttle to every 5th frame
        segFrameCount += 1
        guard segFrameCount % 5 == 0, !isProcessingSeg else { return }
        isProcessingSeg = true

        // Render the segmentation buffer to a standalone CGImage SYNCHRONOUSLY
        // so the CVPixelBuffer (and thus the ARFrame) is released immediately.
        // The segmentation buffer is small (~256x192) so this is fast.
        let ciRaw = CIImage(cvPixelBuffer: buffer).oriented(.right)
        let extent = ciRaw.extent
        guard let rawCG = segCIContext.createCGImage(ciRaw, from: extent) else {
            isProcessingSeg = false
            return
        }
        // rawCG is now a standalone CGImage — no CVPixelBuffer reference

        // Heavy processing (blur, compositing) on background queue
        segQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessingSeg = false }

            let ciImage = CIImage(cgImage: rawCG)
            let ext = ciImage.extent

            // Darken mask: invert + dark tint + blur
            let inverted = ciImage.applyingFilter("CIColorInvert")
            let darkTint = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55))
                .cropped(to: ext)
            let darkBg = inverted.applyingFilter("CIMultiplyCompositing", parameters: [
                "inputBackgroundImage": darkTint
            ])
            let softenedDark = darkBg.applyingGaussianBlur(sigma: 5).cropped(to: ext)
            let darkenCG = self.segCIContext.createCGImage(softenedDark, from: ext)

            // Cutout mask: person area + blur edges
            let softenedCut = ciImage.applyingGaussianBlur(sigma: 8).cropped(to: ext)
            let cutoutCG = self.segCIContext.createCGImage(softenedCut, from: ext)

            DispatchQueue.main.async { [weak self] in
                self?.state.segDarkenMask = darkenCG
                self?.state.segCutoutMask = cutoutCG
            }
        }
    }

    func arKitTracker(_ tracker: ARKitTracker, didUpdateVisionLandmarks landmarks: VNFaceLandmarks2D, boundingBox: CGRect) {
        // Store Vision landmarks for precise face contour rendering in the visualizer
        DispatchQueue.main.async { [weak self] in
            self?.state.rawLandmarks = landmarks
            self?.state.faceBoundingBox = boundingBox
        }
    }
}
