// Jammerman — Audio Engine
// AVAudioEngine with send/return bus topology mirroring web's architecture
// Synths: Pad (FM + sub), Arp (filtered saw), Melody (mono saw), Drums (kick/snare/hat)

import AVFoundation
import Accelerate

class AudioEngine: ObservableObject {
    let engine = AVAudioEngine()

    // Synth oscillators
    private var padNode: AVAudioSourceNode!
    private var arpNode: AVAudioSourceNode!
    private var melodyNode: AVAudioSourceNode!
    private var kickNode: AVAudioSourceNode!
    private var snareNode: AVAudioSourceNode!
    private var hatNode: AVAudioSourceNode!

    // Mixer nodes (channel strips)
    private var padMixer: AVAudioMixerNode!
    private var arpMixer: AVAudioMixerNode!
    private var melodyMixer: AVAudioMixerNode!
    private var drumMixer: AVAudioMixerNode!

    // Effects
    private var reverbNode: AVAudioUnitReverb!
    private var delayNode: AVAudioUnitDelay!

    // Master
    private var masterMixer: AVAudioMixerNode!

    // Synth state
    private var padOsc = PadOscillator()
    private var arpOsc = ArpOscillator()
    private var melodyOsc = MelodyOscillator()
    private var kickOsc = DrumOscillator(type: .kick)
    private var snareOsc = DrumOscillator(type: .snare)
    private var hatOsc = DrumOscillator(type: .hat)

    // Arp sequencer
    private var arpTimer: Timer?
    private var arpNotes: [Int] = []
    private var arpIndex = 0
    private var arpPattern: String = "up-down"
    private var arpDirection: Int = 1

    // Drum sequencer
    private var drumTimer: Timer?
    private var drumStep = 0
    private var drumPattern: [[Int]] = [] // [kick, snare, hat] patterns

    // Transport
    private(set) var bpm: Double = 85
    private var isPlaying = false

    // Channel mute state
    var padMuted = true
    var arpMuted = true
    var melodyMuted = true
    var drumsMuted = true

    private let sampleRate: Double = 44100

    init() {
        setupAudioSession()
        buildGraph()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.005) // 5ms buffer
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Build Audio Graph

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        // Create source nodes for each synth
        padNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.padOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.padMuted)
        }

        arpNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.arpOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.arpMuted)
        }

        melodyNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.melodyOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.melodyMuted)
        }

        kickNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.kickOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.drumsMuted)
        }

        snareNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.snareOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.drumsMuted)
        }

        hatNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.hatOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.drumsMuted)
        }

        // Mixers
        padMixer = AVAudioMixerNode()
        arpMixer = AVAudioMixerNode()
        melodyMixer = AVAudioMixerNode()
        drumMixer = AVAudioMixerNode()
        masterMixer = AVAudioMixerNode()

        // Effects
        reverbNode = AVAudioUnitReverb()
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 35

        delayNode = AVAudioUnitDelay()
        delayNode.delayTime = 0.375 // 8n. at 85bpm ≈ 375ms
        delayNode.feedback = 30
        delayNode.wetDryMix = 25

        // Attach all nodes
        let nodes: [AVAudioNode] = [
            padNode, arpNode, melodyNode, kickNode, snareNode, hatNode,
            padMixer, arpMixer, melodyMixer, drumMixer,
            masterMixer, reverbNode, delayNode
        ]
        for node in nodes {
            engine.attach(node)
        }

        // Wire synths → channel mixers
        engine.connect(padNode, to: padMixer, format: format)
        engine.connect(arpNode, to: arpMixer, format: format)
        engine.connect(melodyNode, to: melodyMixer, format: format)
        engine.connect(kickNode, to: drumMixer, format: format)
        engine.connect(snareNode, to: drumMixer, format: format)
        engine.connect(hatNode, to: drumMixer, format: format)

        // Channel mixers → master mixer (dry path)
        engine.connect(padMixer, to: masterMixer, format: format)
        engine.connect(arpMixer, to: masterMixer, format: format)
        engine.connect(melodyMixer, to: masterMixer, format: format)
        engine.connect(drumMixer, to: masterMixer, format: format)

        // Send buses: channel mixers → reverb/delay → master
        engine.connect(padMixer, to: reverbNode, format: format)
        engine.connect(arpMixer, to: reverbNode, format: format)
        engine.connect(reverbNode, to: masterMixer, format: format)

        engine.connect(arpMixer, to: delayNode, format: format)
        engine.connect(delayNode, to: masterMixer, format: format)

        // Master → output
        engine.connect(masterMixer, to: engine.mainMixerNode, format: format)

        // Set initial volumes
        padMixer.outputVolume = 0.5
        arpMixer.outputVolume = 0.4
        melodyMixer.outputVolume = 0.6
        drumMixer.outputVolume = 0.5
    }

    // MARK: - Start / Stop

    func start() {
        do {
            try engine.start()
            isPlaying = true
            startArpSequencer()
            startDrumSequencer()
        } catch {
            print("Engine start error: \(error)")
        }
    }

    func stop() {
        arpTimer?.invalidate()
        drumTimer?.invalidate()
        engine.stop()
        isPlaying = false
    }

    // MARK: - Pad

    func triggerPad(notes: [String]) {
        let midiNotes = notes.compactMap { noteNameToMidi($0) }
        padOsc.triggerNotes(midiNotes)
    }

    func releasePad() {
        padOsc.release()
    }

    // MARK: - Melody

    func startMelody(_ note: Int) {
        melodyOsc.triggerNote(note)
    }

    func updateMelody(_ note: Int) {
        melodyOsc.glideToNote(note)
    }

    func stopMelody() {
        melodyOsc.release()
    }

    // MARK: - Arp

    func updateArpNotes(_ notes: [String]) {
        arpNotes = notes.compactMap { noteNameToMidi($0) }
    }

    private func startArpSequencer() {
        arpTimer?.invalidate()
        let interval = 60.0 / bpm / 2.0 // 8th notes
        arpTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceArp()
        }
    }

    private func advanceArp() {
        guard !arpNotes.isEmpty, !arpMuted else { return }

        let note: Int
        switch arpPattern {
        case "up":
            note = arpNotes[arpIndex % arpNotes.count]
            arpIndex += 1
        case "down":
            let idx = arpNotes.count - 1 - (arpIndex % arpNotes.count)
            note = arpNotes[idx]
            arpIndex += 1
        case "random":
            note = arpNotes[Int.random(in: 0..<arpNotes.count)]
        case "up-down":
            note = arpNotes[arpIndex % arpNotes.count]
            arpIndex += arpDirection
            if arpIndex >= arpNotes.count - 1 { arpDirection = -1; arpIndex = arpNotes.count - 1 }
            if arpIndex <= 0 { arpDirection = 1; arpIndex = 0 }
        default:
            note = arpNotes[arpIndex % arpNotes.count]
            arpIndex += 1
        }

        arpOsc.triggerNote(note)
    }

    // MARK: - Drums

    func setBPM(_ newBPM: Double) {
        bpm = max(40, min(200, newBPM))
        if isPlaying {
            startArpSequencer()
            startDrumSequencer()
        }
    }

    func setDrumPattern(_ pattern: [[Int]]) {
        drumPattern = pattern
        drumStep = 0
    }

    private func startDrumSequencer() {
        drumTimer?.invalidate()
        let interval = 60.0 / bpm / 4.0 // 16th notes
        drumTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceDrum()
        }
    }

    private func advanceDrum() {
        guard !drumsMuted, drumPattern.count >= 3 else { return }
        let step = drumStep % drumPattern[0].count

        if drumPattern[0][step] == 1 { kickOsc.trigger(velocity: 0.8) }
        if drumPattern[1][step] == 1 { snareOsc.trigger(velocity: 0.7) }
        if drumPattern[2][step] == 1 { hatOsc.trigger(velocity: 0.5) }

        drumStep += 1
    }

    // MARK: - Parameter Updates (face-driven)

    func updateParams(state: JammermanState) {
        // Master filter: head pitch controls cutoff (not available on AVAudioEngine directly,
        // we'll use EQ instead — boost/cut highs based on pitch)

        // Reverb wet: eye openness
        reverbNode.wetDryMix = state.eyeOpenness * 60 // 0-60%

        // Delay feedback: mouth width
        delayNode.feedback = Float(state.mouthWidth) * 50 // 0-50%
    }

    // MARK: - Toggle Mute

    func toggleMute(channel: String) {
        switch channel {
        case "pad": padMuted.toggle()
        case "arp": arpMuted.toggle()
        case "melody": melodyMuted.toggle()
        case "beat": drumsMuted.toggle()
        default: break
        }
    }

    // MARK: - Helpers

    private func noteNameToMidi(_ name: String) -> Int? {
        let noteMap: [String: Int] = [
            "C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
            "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11
        ]
        var notePart = ""
        var octPart = ""
        for char in name {
            if char.isNumber || char == "-" { octPart.append(char) }
            else { notePart.append(char) }
        }
        guard let semitone = noteMap[notePart], let octave = Int(octPart) else { return nil }
        return (octave + 1) * 12 + semitone
    }
}

// MARK: - Oscillator Types

/// FM Pad oscillator — produces warm FM synthesis tones
class PadOscillator {
    private var phases: [Double] = []
    private var frequencies: [Double] = []
    private var envelope: Double = 0
    private var targetEnvelope: Double = 0
    private let attackRate: Double = 0.001  // slow attack
    private let releaseRate: Double = 0.0003

    func triggerNotes(_ midiNotes: [Int]) {
        frequencies = midiNotes.map { 440.0 * pow(2.0, Double($0 - 69) / 12.0) }
        while phases.count < frequencies.count { phases.append(0) }
        targetEnvelope = 1.0
    }

    func release() {
        targetEnvelope = 0.0
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        let leftBuffer = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
        let rightBuffer = ablPointer[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            // Envelope smoothing
            if envelope < targetEnvelope {
                envelope = min(envelope + attackRate, targetEnvelope)
            } else {
                envelope = max(envelope - releaseRate, targetEnvelope)
            }

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                for i in 0..<frequencies.count {
                    if i < phases.count {
                        let freq = frequencies[i]
                        let modFreq = freq * 1.5 // harmonicity ratio
                        let modPhase = phases[i] * 1.5
                        let modSignal = sin(modPhase * 2.0 * .pi) * 2.5 // modulation index
                        let carrier = sin((phases[i] + modSignal / (2.0 * .pi)) * 2.0 * .pi)
                        sample += Float(carrier * envelope) * 0.15
                        phases[i] += freq / sampleRate
                        if phases[i] > 1.0 { phases[i] -= 1.0 }
                    }
                }
            }

            leftBuffer[frame] = sample
            rightBuffer[frame] = sample
        }
        return noErr
    }
}

/// Arp oscillator — sawtooth with filter pluck envelope
class ArpOscillator {
    private var phase: Double = 0
    private var frequency: Double = 440
    private var envelope: Double = 0
    private var filterEnv: Double = 0

    func triggerNote(_ midi: Int) {
        frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        envelope = 1.0
        filterEnv = 1.0
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        let leftBuffer = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
        let rightBuffer = ablPointer[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            envelope *= 0.9997 // decay
            filterEnv *= 0.999  // filter envelope decay

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                // Sawtooth
                let saw = Float(2.0 * phase - 1.0)
                // Simple lowpass approximation using filter envelope
                let brightness = Float(0.2 + filterEnv * 0.8)
                sample = saw * brightness * Float(envelope) * 0.25

                phase += frequency / sampleRate
                if phase > 1.0 { phase -= 1.0 }
            }

            leftBuffer[frame] = sample
            rightBuffer[frame] = sample
        }
        return noErr
    }
}

/// Melody oscillator — mono sawtooth with portamento
class MelodyOscillator {
    private var phase: Double = 0
    private var frequency: Double = 440
    private var targetFrequency: Double = 440
    private var envelope: Double = 0
    private var targetEnvelope: Double = 0
    private let glideRate: Double = 0.002

    func triggerNote(_ midi: Int) {
        targetFrequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        frequency = targetFrequency
        targetEnvelope = 1.0
    }

    func glideToNote(_ midi: Int) {
        targetFrequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        targetEnvelope = 1.0
    }

    func release() {
        targetEnvelope = 0.0
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        let leftBuffer = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
        let rightBuffer = ablPointer[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            // Portamento
            frequency += (targetFrequency - frequency) * glideRate

            // Envelope
            if envelope < targetEnvelope {
                envelope = min(envelope + 0.005, targetEnvelope)
            } else {
                envelope = max(envelope - 0.001, targetEnvelope)
            }

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                let saw = Float(2.0 * phase - 1.0)
                sample = saw * Float(envelope) * 0.3

                phase += frequency / sampleRate
                if phase > 1.0 { phase -= 1.0 }
            }

            leftBuffer[frame] = sample
            rightBuffer[frame] = sample
        }
        return noErr
    }
}

/// Drum oscillator — kick (sine pitch sweep), snare (noise + tone), hat (filtered noise)
class DrumOscillator {
    enum DrumType { case kick, snare, hat }

    let type: DrumType
    private var phase: Double = 0
    private var envelope: Double = 0
    private var pitchEnv: Double = 0
    private var noiseState: UInt32 = 12345 // for white noise

    init(type: DrumType) {
        self.type = type
    }

    func trigger(velocity: Float = 0.8) {
        envelope = Double(velocity)
        pitchEnv = 1.0
        phase = 0
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
        let leftBuffer = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
        let rightBuffer = ablPointer[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            var sample: Float = 0

            if !muted && envelope > 0.001 {
                switch type {
                case .kick:
                    // Sine with pitch sweep from ~150Hz down to ~50Hz
                    let freq = 50.0 + pitchEnv * 100.0
                    sample = Float(sin(phase * 2.0 * .pi) * envelope) * 0.6
                    phase += freq / sampleRate
                    if phase > 1.0 { phase -= 1.0 }
                    envelope *= 0.9993
                    pitchEnv *= 0.997

                case .snare:
                    // Noise + short tonal body
                    let noise = nextNoise()
                    let tone = Float(sin(phase * 2.0 * .pi) * envelope * 0.3)
                    phase += 200.0 / sampleRate
                    if phase > 1.0 { phase -= 1.0 }
                    sample = (noise * Float(envelope) * 0.3 + tone) * 0.5
                    envelope *= 0.9985

                case .hat:
                    // Filtered noise (highpass character)
                    let noise = nextNoise()
                    sample = noise * Float(envelope) * 0.2
                    envelope *= 0.998
                }
            }

            leftBuffer[frame] = sample
            rightBuffer[frame] = sample
        }
        return noErr
    }

    private func nextNoise() -> Float {
        // Simple white noise via linear congruential generator
        noiseState = noiseState &* 1103515245 &+ 12345
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }
}
