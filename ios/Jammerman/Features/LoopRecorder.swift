// Jammerman — Loop Recorder
// Records melody notes as timed MIDI events, supports multi-layer overdubbing
// Mirrors web's MUZE.LoopRecorder (features.js)

import Foundation
import Combine

struct LoopEvent {
    let time: Double      // seconds from loop start
    let midiNote: Int
    let duration: Double  // seconds
}

enum LoopRecorderState: String {
    case empty
    case counting
    case recording
    case playing
    case overdubbing
}

class LoopRecorder: ObservableObject {
    @Published var state: LoopRecorderState = .empty
    @Published var progress: Double = 0
    @Published var barCount: Int = 4
    @Published var layerCount: Int = 0

    private var layers: [[LoopEvent]] = []
    private var loopDuration: Double = 0  // seconds
    private var startTime: Date = Date()
    private var currentNote: Int? = nil
    private var noteStartTime: Date = Date()
    private var autoStopTimer: Timer?
    private var countInTimer: Timer?
    private var progressTimer: Timer?
    private var playbackTimers: [Timer] = []

    let barOptions = [1, 2, 4, 8]

    weak var audioEngine: AudioEngine?

    // MARK: - Bar Count

    func cycleBarCount() {
        guard state == .empty else { return }
        let idx = barOptions.firstIndex(of: barCount) ?? 0
        barCount = barOptions[(idx + 1) % barOptions.count]
    }

    // MARK: - Loop Duration

    private func getLoopDuration() -> Double {
        guard let engine = audioEngine else { return 8.0 }
        let beatDuration = 60.0 / engine.bpm
        return beatDuration * 4.0 * Double(barCount)
    }

    // MARK: - Record Note

    func recordNote(_ midiNote: Int?) {
        guard state == .recording || state == .overdubbing else { return }
        guard !layers.isEmpty else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(startTime)

        // Close previous note
        if currentNote != nil {
            let layerIdx = layers.count - 1
            if layerIdx >= 0, !layers[layerIdx].isEmpty {
                var layer = layers[layerIdx]
                var last = layer[layer.count - 1]
                if last.duration == 0 {
                    let duration = max(0.05, elapsed - last.time)
                    last = LoopEvent(time: last.time, midiNote: last.midiNote, duration: duration)
                    layer[layer.count - 1] = last
                    layers[layerIdx] = layer
                }
            }
        }

        if let note = midiNote {
            let layerIdx = layers.count - 1
            layers[layerIdx].append(LoopEvent(time: elapsed, midiNote: note, duration: 0))
        }
        currentNote = midiNote
        noteStartTime = now
    }

    func recordNoteOff() {
        guard state == .recording || state == .overdubbing else { return }
        guard !layers.isEmpty else { return }

        let layerIdx = layers.count - 1
        if layerIdx >= 0, !layers[layerIdx].isEmpty {
            var layer = layers[layerIdx]
            var last = layer[layer.count - 1]
            if last.duration == 0 {
                let duration = max(0.05, Date().timeIntervalSince(noteStartTime))
                last = LoopEvent(time: last.time, midiNote: last.midiNote, duration: duration)
                layer[layer.count - 1] = last
                layers[layerIdx] = layer
            }
        }
        currentNote = nil
    }

    // MARK: - Button Actions

    func onRecButton() {
        switch state {
        case .empty: startRecording()
        case .recording: stopRecording()
        case .playing: startOverdub()
        case .overdubbing: stopOverdub()
        case .counting: break
        }
    }

    func onOverdubButton() {
        if state == .playing { startOverdub() }
        else if state == .overdubbing { stopOverdub() }
    }

    func undoLayer() {
        guard !layers.isEmpty, state != .recording, state != .overdubbing else { return }
        layers.removeLast()
        layerCount = layers.count
        if layers.isEmpty {
            clearAll()
            return
        }
        buildPlayback()
    }

    func clearAll() {
        stopAllPlayback()
        autoStopTimer?.invalidate()
        countInTimer?.invalidate()
        layers = []
        layerCount = 0
        state = .empty
        currentNote = nil
        stopProgress()
    }

    // MARK: - Recording

    private func startRecording() {
        state = .counting
        guard let engine = audioEngine else { return }
        let beatMs = 60.0 / engine.bpm

        // Count-in: 4 clicks
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * beatMs) { [weak self] in
                self?.audioEngine?.triggerHat(velocity: 0.3)
            }
        }

        // Start recording after count-in
        let countInDuration = 4.0 * beatMs
        countInTimer = Timer.scheduledTimer(withTimeInterval: countInDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.state = .recording
            self.loopDuration = self.getLoopDuration()
            self.startTime = Date()
            self.layers = [[]]
            self.currentNote = nil
            self.layerCount = 1
            self.startProgress()

            self.autoStopTimer = Timer.scheduledTimer(withTimeInterval: self.loopDuration, repeats: false) { [weak self] _ in
                if self?.state == .recording {
                    self?.stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        autoStopTimer?.invalidate()
        recordNoteOff()

        if layers.first?.isEmpty ?? true {
            layers = []
            layerCount = 0
            state = .empty
            stopProgress()
            return
        }
        state = .playing
        layerCount = layers.count
        buildPlayback()
    }

    // MARK: - Overdubbing

    private func startOverdub() {
        state = .overdubbing
        layers.append([])
        startTime = Date()
        currentNote = nil
        layerCount = layers.count

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: loopDuration, repeats: false) { [weak self] _ in
            if self?.state == .overdubbing {
                self?.stopOverdub()
            }
        }
    }

    private func stopOverdub() {
        autoStopTimer?.invalidate()
        recordNoteOff()

        if layers.last?.isEmpty ?? true {
            layers.removeLast()
        }
        state = .playing
        layerCount = layers.count
        buildPlayback()
    }

    // MARK: - Playback

    private func buildPlayback() {
        stopAllPlayback()

        // Merge all layers into one event list
        var events: [LoopEvent] = []
        for layer in layers {
            for evt in layer {
                events.append(evt)
            }
        }
        events.sort { $0.time < $1.time }

        // Schedule playback loop
        startPlaybackLoop(events: events)
        startProgress()
    }

    private func startPlaybackLoop(events: [LoopEvent]) {
        guard loopDuration > 0 else { return }
        schedulePlaybackLoop(events: events)
    }

    private func schedulePlaybackLoop(events: [LoopEvent]) {
        let loopStart = Date()
        self.startTime = loopStart

        for event in events {
            let timer = Timer.scheduledTimer(withTimeInterval: event.time, repeats: false) { [weak self] _ in
                guard let self, self.state == .playing || self.state == .overdubbing else { return }
                self.audioEngine?.melodyOsc.triggerNote(event.midiNote)
            }
            playbackTimers.append(timer)
        }

        // Schedule next loop iteration
        let loopTimer = Timer.scheduledTimer(withTimeInterval: loopDuration, repeats: false) { [weak self] _ in
            guard let self, self.state == .playing || self.state == .overdubbing else { return }
            self.stopAllPlayback()
            self.schedulePlaybackLoop(events: events)
        }
        playbackTimers.append(loopTimer)
    }

    private func stopAllPlayback() {
        for timer in playbackTimers { timer.invalidate() }
        playbackTimers.removeAll()
    }

    // MARK: - Progress

    private func startProgress() {
        stopProgress()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self, self.state != .empty, self.loopDuration > 0 else { return }
            let elapsed = Date().timeIntervalSince(self.startTime)
            self.progress = elapsed.truncatingRemainder(dividingBy: self.loopDuration) / self.loopDuration
        }
    }

    private func stopProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        progress = 0
    }

    // MARK: - UI Labels

    var recButtonLabel: String {
        switch state {
        case .counting: return "COUNT"
        case .recording, .overdubbing: return "STOP"
        case .playing: return "OVR"
        case .empty: return "REC"
        }
    }

    var recButtonColor: String {
        switch state {
        case .counting: return "facc15"
        case .recording: return "ef4444"
        case .overdubbing: return "f59e0b"
        default: return "ef4444"
        }
    }

    var canUndo: Bool { !layers.isEmpty && state != .recording && state != .overdubbing }
    var canClear: Bool { !layers.isEmpty && state != .recording && state != .overdubbing }
    var canOverdub: Bool { state == .playing }
}
