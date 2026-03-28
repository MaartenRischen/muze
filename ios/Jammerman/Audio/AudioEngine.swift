// Jammerman — Audio Engine
// AVAudioEngine with send/return bus topology mirroring web's architecture
// Synths: Pad (FM + sub), Arp1, Arp2, Melody, Drums (kick/snare/hat), Binaural, Riser

import AVFoundation
import Accelerate

// MARK: - Waveform Type

enum WaveformType: String, CaseIterable {
    case sine
    case triangle
    case sawtooth
    case square

    var next: WaveformType {
        let all = WaveformType.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

class AudioEngine: ObservableObject {
    let engine = AVAudioEngine()

    // Source nodes
    private var padNode: AVAudioSourceNode!
    private var arpNode: AVAudioSourceNode!
    private var arp2Node: AVAudioSourceNode!
    private var melodyNode: AVAudioSourceNode!
    private var kickNode: AVAudioSourceNode!
    private var snareNode: AVAudioSourceNode!
    private var hatNode: AVAudioSourceNode!
    private var binauralNode: AVAudioSourceNode!
    private var riserNode: AVAudioSourceNode!

    // Channel mixers
    private var padMixer: AVAudioMixerNode!
    private var arpMixer: AVAudioMixerNode!
    private var arp2Mixer: AVAudioMixerNode!
    private var melodyMixer: AVAudioMixerNode!
    private var kickMixer: AVAudioMixerNode!
    private var snareMixer: AVAudioMixerNode!
    private var hatMixer: AVAudioMixerNode!
    private var binauralMixer: AVAudioMixerNode!
    private var riserMixer: AVAudioMixerNode!

    // Per-channel reverb send mixers
    private var padReverbSendMixer: AVAudioMixerNode!
    private var arpReverbSendMixer: AVAudioMixerNode!
    private var arp2ReverbSendMixer: AVAudioMixerNode!
    private var melodyReverbSendMixer: AVAudioMixerNode!

    // Per-channel delay send mixers
    private var arpDelaySendMixer: AVAudioMixerNode!
    private var arp2DelaySendMixer: AVAudioMixerNode!

    // Per-channel EQs
    private var channelEQs: [String: AVAudioUnitEQ] = [:]

    // Effects
    private var reverbNode: AVAudioUnitReverb!
    private var delayNode: AVAudioUnitDelay!
    private var masterEQ: AVAudioUnitEQ!

    // Master
    private var masterMixer: AVAudioMixerNode!

    // Synth oscillators
    var padOsc = PadOscillator()
    var arpOsc = ArpOscillator()
    var arp2Osc = ArpOscillator()
    var melodyOsc = MelodyOscillator()
    private var kickOsc = DrumOscillator(type: .kick)
    private var snareOsc = DrumOscillator(type: .snare)
    private var hatOsc = DrumOscillator(type: .hat)
    private var binauralOsc = BinauralOscillator()
    var riserOsc = RiserOscillator()

    // Arp 1 sequencer
    private var arpTimer: Timer?
    private var arpNotes: [Int] = []
    private var arpIndex = 0
    @Published var arpPattern: String = "up-down"
    @Published var arpNoteValue: String = "8n"
    private var arpDirection: Int = 1

    // Arp 2 sequencer
    private var arp2Timer: Timer?
    private var arp2Notes: [Int] = []
    private var arp2Index = 0
    @Published var arp2Pattern: String = "down"
    @Published var arp2NoteValue: String = "16n"
    private var arp2Direction: Int = 1

    // Drum sequencer
    private var drumTimer: Timer?
    @Published var drumStep = 0
    var drumPattern: [[Int]] = []
    var drumVelocity: [[Float]] = [] // per-step velocity

    // Transport
    @Published var bpm: Double = 85
    @Published var swing: Int = 0
    private var isPlaying = false

    // Channel mute state
    @Published var padMuted = true
    @Published var arpMuted = true
    @Published var arp2Muted = true
    @Published var melodyMuted = true
    @Published var beatMuted = true
    @Published var binauralActive = false

    // Riser state
    @Published var riserActive = false
    private var riserTimer: Timer?
    private var preRiserGains: [String: Float] = [:]

    // Chord auto-advance
    @Published var chordAutoAdvance = false

    // Sample-accurate clock
    private var globalSampleCount: UInt64 = 0
    private var lastArpStep: Int = -1
    private var lastArp2Step: Int = -1
    private var lastDrumStep: Int = -1
    private var chordAdvanceTimer: Timer?
    private var chordAdvanceStep = 0

    // Solo state
    @Published var soloChannel: String? = nil

    // Channel volumes (dB)
    // Matches web mixer.js defaults
    var channelVolumes: [String: Float] = [
        "pad": -10, "arp": -12, "arp2": -14, "melody": -8,
        "kick": -6, "snare": -10, "hat": -16, "binaural": -24
    ]

    // Per-channel pan (-1 to +1) — matches web mixer.js defaults
    var channelPans: [String: Float] = [
        "pad": 0, "arp": 0.3, "arp2": -0.3, "melody": -0.3,
        "kick": 0, "snare": 0, "hat": 0.2, "binaural": 0
    ]

    // Per-channel reverb send (0 to 1) — matches web mixer.js defaults
    var channelReverbSends: [String: Float] = [
        "pad": 0.35, "arp": 0.35, "arp2": 0.30, "melody": 0.30,
        "kick": 0, "snare": 0.15, "hat": 0.05, "binaural": 0
    ]

    // Per-channel delay send (0 to 1)
    var channelDelaySends: [String: Float] = [
        "pad": 0.25, "arp": 0.25, "arp2": 0.20, "melody": 0.20,
        "kick": 0, "snare": 0, "hat": 0, "binaural": 0
    ]

    // Sidechain removed — was causing pad to go silent

    // Thread-safe drum step for UI (written from audio thread, read from main)
    private var _pendingDrumStep: Int = -1

    // Arp note-off tracking (avoid DispatchQueue.main.asyncAfter from audio thread)
    private var arpPendingNoteOff: UInt8? = nil
    private var arp2PendingNoteOff: UInt8? = nil

    // Reverb parameters
    @Published var reverbWetDry: Float = 35        // 0-100%
    @Published var reverbPreset: Int = 0           // AVAudioUnitReverb preset index

    // Delay parameters
    @Published var delayTime: Float = 375          // ms
    @Published var delayFeedback: Float = 30       // 0-100%
    @Published var delayWetDry: Float = 25         // 0-100%
    @Published var delayCutoff: Float = 8000       // lowpass Hz

    // Per-channel EQ gains (low, mid, high)
    var channelEQGains: [String: [Float]] = [
        "pad": [0, 0, 0], "arp": [0, 0, 0], "arp2": [0, 0, 0], "melody": [0, 0, 0],
        "kick": [0, 0, 0], "snare": [0, 0, 0], "hat": [0, 0, 0], "binaural": [0, 0, 0]
    ]

    // Tap tempo
    private var tapTimes: [Date] = []
    @Published var lastTapBPM: Double = 0

    // Binaural
    @Published var binauralBeatHz: Float = 2.5
    @Published var binauralFollowChord = true

    // SoundFont sampler
    var soundFontManager: SoundFontManager?
    @Published var useSoundFont = true // default to sampled instruments
    private var currentPadMidiNotes: [UInt8] = []
    private var padCrossfadeWorkItem: DispatchWorkItem?
    private var currentMelodyMidiNote: UInt8? = nil

    // Master filter cutoff (face-driven)
    private var masterFilterFreq: Float = 10000

    private let sampleRate: Double = 44100

    init() {
        setupAudioSession()
        buildGraph()
        setupDefaultDrumPattern()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(sampleRate)
            // 12ms buffer — safe for complex graph (27+ nodes + SoundFont samplers + ARKit)
            // 5ms was causing glitches on startup when CPU is loaded
            try session.setPreferredIOBufferDuration(0.012)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Build Audio Graph

    private func buildGraph() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            print("AudioEngine: failed to create AVAudioFormat")
            return
        }

        padNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.padOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.padMuted)
        }
        arpNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.arpOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.arpMuted)
        }
        arp2Node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.arp2Osc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.arp2Muted)
        }
        melodyNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.melodyOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.melodyMuted)
        }
        // Kick is the MASTER CLOCK — triggers all sequenced events at sample-accurate timing
        kickNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }

            // --- Snapshot all @Published / main-thread values BEFORE the per-sample loop ---
            let sr = self.sampleRate
            let currentBpm = self.bpm
            let localBeatMuted = self.beatMuted
            let localArpMuted = self.arpMuted
            let localArp2Muted = self.arp2Muted
            let localPadMuted = self.padMuted
            let localMelodyMuted = self.melodyMuted
            let localUseSoundFont = self.useSoundFont
            let localArpNotes = self.arpNotes       // copy array
            let localArp2Notes = self.arp2Notes     // copy array
            let localArpPattern = self.arpPattern
            let localArp2Pattern = self.arp2Pattern
            let localArpNoteValue = self.arpNoteValue
            let localArp2NoteValue = self.arp2NoteValue
            let localDrumPattern = self.drumPattern // copy array of arrays
            let localDrumVelocity = self.drumVelocity

            let samplesPerBeat = sr * 60.0 / currentBpm
            let samplesPerSixteenth = samplesPerBeat / 4.0

            // Stop any pending arp note-offs from the previous step
            if let pendingOff = self.arpPendingNoteOff {
                self.soundFontManager?.arpSampler?.stopNote(pendingOff, onChannel: 0)
                self.arpPendingNoteOff = nil
            }
            if let pendingOff = self.arp2PendingNoteOff {
                self.soundFontManager?.arp2Sampler?.stopNote(pendingOff, onChannel: 0)
                self.arp2PendingNoteOff = nil
            }

            for i in 0..<Int(frameCount) {
                let pos = self.globalSampleCount + UInt64(i)
                let sixteenthStep = Int(Double(pos) / samplesPerSixteenth) % 16

                // Drum sequencer — on new 16th note step
                if sixteenthStep != self.lastDrumStep {
                    self.lastDrumStep = sixteenthStep
                    if !localBeatMuted && localDrumPattern.count >= 3 {
                        // Bounds-safe step index
                        guard localDrumPattern[0].count > 0 else { continue }
                        let step = sixteenthStep % localDrumPattern[0].count

                        // Kick
                        if step < localDrumPattern[0].count && localDrumPattern[0][step] == 1 {
                            let vel: Float = (localDrumVelocity.count > 0 && step < localDrumVelocity[0].count) ? localDrumVelocity[0][step] : 0.8
                            self.kickOsc.trigger(velocity: vel)
                            self.soundFontManager?.drumSampler?.startNote(SoundFontManager.gmKick, withVelocity: UInt8(vel * 127), onChannel: 9)
                        }
                        // Snare
                        if localDrumPattern[1].count > 0 {
                            let snareStep = step % localDrumPattern[1].count
                            if localDrumPattern[1][snareStep] == 1 {
                                let vel: Float = (localDrumVelocity.count > 1 && snareStep < localDrumVelocity[1].count) ? localDrumVelocity[1][snareStep] : 0.7
                                self.snareOsc.trigger(velocity: vel)
                                self.soundFontManager?.drumSampler?.startNote(SoundFontManager.gmSnare, withVelocity: UInt8(vel * 127), onChannel: 9)
                            }
                        }
                        // Hat
                        if localDrumPattern[2].count > 0 {
                            let hatStep = step % localDrumPattern[2].count
                            if localDrumPattern[2][hatStep] == 1 {
                                let vel: Float = (localDrumVelocity.count > 2 && hatStep < localDrumVelocity[2].count) ? localDrumVelocity[2][hatStep] : 0.5
                                self.hatOsc.trigger(velocity: vel)
                                self.soundFontManager?.drumSampler?.startNote(SoundFontManager.gmClosedHat, withVelocity: UInt8(vel * 127), onChannel: 9)
                            }
                        }
                        // Update UI drum step (weak self, only if changed)
                        let pendingStep = sixteenthStep
                        if self._pendingDrumStep != pendingStep {
                            self._pendingDrumStep = pendingStep
                            DispatchQueue.main.async { [weak self] in
                                self?.drumStep = pendingStep
                            }
                        }
                    }
                }

                // Arp 1 sequencer
                let arpDivisor = self.noteValueDivisor(localArpNoteValue)
                let samplesPerArpStep = samplesPerBeat / Double(arpDivisor)
                let arpStep = Int(Double(pos) / samplesPerArpStep)
                if arpStep != self.lastArpStep {
                    self.lastArpStep = arpStep
                    if !localArpNotes.isEmpty && !localArpMuted {
                        // Stop previous note before starting new one
                        if localUseSoundFont, let prevNote = self.arpPendingNoteOff {
                            self.soundFontManager?.arpSampler?.stopNote(prevNote, onChannel: 0)
                            self.arpPendingNoteOff = nil
                        }
                        let note = self.getNextArpNote(notes: localArpNotes, index: &self.arpIndex, direction: &self.arpDirection, pattern: localArpPattern)
                        if localUseSoundFont {
                            let midiNote = UInt8(note)
                            self.soundFontManager?.arpSampler?.startNote(midiNote, withVelocity: 85, onChannel: 0)
                            // Track for note-off at next step change
                            self.arpPendingNoteOff = midiNote
                        } else {
                            self.arpOsc.triggerNote(note)
                        }
                    }
                }

                // Arp 2 sequencer
                let arp2Divisor = self.noteValueDivisor(localArp2NoteValue)
                let samplesPerArp2Step = samplesPerBeat / Double(arp2Divisor)
                let arp2Step = Int(Double(pos) / samplesPerArp2Step)
                if arp2Step != self.lastArp2Step {
                    self.lastArp2Step = arp2Step
                    if !localArp2Notes.isEmpty && !localArp2Muted {
                        // Stop previous note before starting new one
                        if localUseSoundFont, let prevNote = self.arp2PendingNoteOff {
                            self.soundFontManager?.arp2Sampler?.stopNote(prevNote, onChannel: 0)
                            self.arp2PendingNoteOff = nil
                        }
                        let note = self.getNextArpNote(notes: localArp2Notes, index: &self.arp2Index, direction: &self.arp2Direction, pattern: localArp2Pattern)
                        if localUseSoundFont {
                            let midiNote = UInt8(note)
                            self.soundFontManager?.arp2Sampler?.startNote(midiNote, withVelocity: 80, onChannel: 0)
                            // Track for note-off at next step change
                            self.arp2PendingNoteOff = midiNote
                        } else {
                            self.arp2Osc.triggerNote(note)
                        }
                    }
                }
            }
            self.globalSampleCount += UInt64(frameCount)

            return self.kickOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: sr, muted: localBeatMuted)
        }
        snareNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.snareOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.beatMuted)
        }
        hatNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.hatOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.beatMuted)
        }
        binauralNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.binauralOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: !self.binauralActive)
        }
        riserNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.riserOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: !self.riserActive)
        }

        // Mixers
        padMixer = AVAudioMixerNode()
        arpMixer = AVAudioMixerNode()
        arp2Mixer = AVAudioMixerNode()
        melodyMixer = AVAudioMixerNode()
        kickMixer = AVAudioMixerNode()
        snareMixer = AVAudioMixerNode()
        hatMixer = AVAudioMixerNode()
        binauralMixer = AVAudioMixerNode()
        riserMixer = AVAudioMixerNode()
        masterMixer = AVAudioMixerNode()

        // Per-channel reverb send mixers
        padReverbSendMixer = AVAudioMixerNode()
        arpReverbSendMixer = AVAudioMixerNode()
        arp2ReverbSendMixer = AVAudioMixerNode()
        melodyReverbSendMixer = AVAudioMixerNode()

        // Per-channel delay send mixers
        arpDelaySendMixer = AVAudioMixerNode()
        arp2DelaySendMixer = AVAudioMixerNode()

        // Per-channel EQs (3-band each)
        let channelNames = ["pad", "arp", "arp2", "melody", "kick", "snare", "hat", "binaural"]
        for name in channelNames {
            let eq = AVAudioUnitEQ(numberOfBands: 3)
            eq.bands[0].filterType = .lowShelf
            eq.bands[0].frequency = 200
            eq.bands[0].gain = 0
            eq.bands[0].bypass = false
            eq.bands[1].filterType = .parametric
            eq.bands[1].frequency = 2000
            eq.bands[1].gain = 0
            eq.bands[1].bypass = false
            eq.bands[2].filterType = .highShelf
            eq.bands[2].frequency = 8000
            eq.bands[2].gain = 0
            eq.bands[2].bypass = false
            channelEQs[name] = eq
        }

        // Effects
        reverbNode = AVAudioUnitReverb()
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 35

        delayNode = AVAudioUnitDelay()
        delayNode.delayTime = 0.375
        delayNode.feedback = 30
        delayNode.wetDryMix = 25

        // Master EQ (3-band: low shelf, parametric mid, high shelf)
        masterEQ = AVAudioUnitEQ(numberOfBands: 3)
        masterEQ.bands[0].filterType = .lowShelf
        masterEQ.bands[0].frequency = 200
        masterEQ.bands[0].gain = 0
        masterEQ.bands[0].bypass = false
        masterEQ.bands[1].filterType = .parametric
        masterEQ.bands[1].frequency = 2000
        masterEQ.bands[1].gain = 0
        masterEQ.bands[1].bypass = false
        masterEQ.bands[2].filterType = .highShelf
        masterEQ.bands[2].frequency = 8000
        masterEQ.bands[2].gain = 0
        masterEQ.bands[2].bypass = false

        // Attach all nodes
        var allNodes: [AVAudioNode] = [
            padNode, arpNode, arp2Node, melodyNode,
            kickNode, snareNode, hatNode, binauralNode, riserNode,
            padMixer, arpMixer, arp2Mixer, melodyMixer,
            kickMixer, snareMixer, hatMixer, binauralMixer, riserMixer,
            masterMixer, reverbNode, delayNode, masterEQ,
            padReverbSendMixer, arpReverbSendMixer, arp2ReverbSendMixer, melodyReverbSendMixer,
            arpDelaySendMixer, arp2DelaySendMixer
        ]
        // Attach per-channel EQs
        for eq in channelEQs.values { allNodes.append(eq) }
        for node in allNodes { engine.attach(node) }

        // Signal chain: sourceNode → channelMixer → channelEQ → (fan-out)
        // EQ is AFTER mixer so it applies to both oscillator AND SoundFont sampler
        engine.connect(padNode, to: padMixer, format: format)
        engine.connect(arpNode, to: arpMixer, format: format)
        engine.connect(arp2Node, to: arp2Mixer, format: format)
        engine.connect(melodyNode, to: melodyMixer, format: format)
        engine.connect(kickNode, to: kickMixer, format: format)
        engine.connect(snareNode, to: snareMixer, format: format)
        engine.connect(hatNode, to: hatMixer, format: format)
        engine.connect(binauralNode, to: binauralMixer, format: format)

        // Riser has no per-channel EQ
        engine.connect(riserNode, to: riserMixer, format: format)

        // Wire: channelMixer → channelEQ → fan-out (dry + sends)
        // EQ sits after the mixer so it applies to both oscillators AND SoundFont samplers
        let mainNode = engine.mainMixerNode

        // Helper to get EQ output node for a channel (falls back to mixer if no EQ)
        func eqOut(_ name: String, mixer: AVAudioMixerNode) -> AVAudioNode {
            if let eq = channelEQs[name] {
                engine.connect(mixer, to: eq, format: format)
                return eq
            }
            return mixer
        }

        let padOut = eqOut("pad", mixer: padMixer)
        let arpOut = eqOut("arp", mixer: arpMixer)
        let arp2Out = eqOut("arp2", mixer: arp2Mixer)
        let melodyOut = eqOut("melody", mixer: melodyMixer)
        let kickOut = eqOut("kick", mixer: kickMixer)
        let snareOut = eqOut("snare", mixer: snareMixer)
        let hatOut = eqOut("hat", mixer: hatMixer)
        let binauralOut = eqOut("binaural", mixer: binauralMixer)

        // Pad: dry + reverb send
        engine.connect(padOut, to: [
            AVAudioConnectionPoint(node: mainNode, bus: mainNode.nextAvailableInputBus),
            AVAudioConnectionPoint(node: padReverbSendMixer, bus: 0)
        ], fromBus: 0, format: format)

        // Arp: dry + reverb + delay sends
        engine.connect(arpOut, to: [
            AVAudioConnectionPoint(node: mainNode, bus: mainNode.nextAvailableInputBus),
            AVAudioConnectionPoint(node: arpReverbSendMixer, bus: 0),
            AVAudioConnectionPoint(node: arpDelaySendMixer, bus: 0)
        ], fromBus: 0, format: format)

        // Arp2: dry + reverb + delay sends
        engine.connect(arp2Out, to: [
            AVAudioConnectionPoint(node: mainNode, bus: mainNode.nextAvailableInputBus),
            AVAudioConnectionPoint(node: arp2ReverbSendMixer, bus: 0),
            AVAudioConnectionPoint(node: arp2DelaySendMixer, bus: 0)
        ], fromBus: 0, format: format)

        // Melody: dry + reverb send
        engine.connect(melodyOut, to: [
            AVAudioConnectionPoint(node: mainNode, bus: mainNode.nextAvailableInputBus),
            AVAudioConnectionPoint(node: melodyReverbSendMixer, bus: 0)
        ], fromBus: 0, format: format)

        // Drums, binaural, riser: dry only (through EQ)
        engine.connect(kickOut, to: mainNode, format: format)
        engine.connect(snareOut, to: mainNode, format: format)
        engine.connect(hatOut, to: mainNode, format: format)
        engine.connect(binauralOut, to: mainNode, format: format)
        engine.connect(riserMixer, to: mainNode, format: format)

        // Send mixers → effects → output
        engine.connect(padReverbSendMixer, to: reverbNode, format: format)
        engine.connect(arpReverbSendMixer, to: reverbNode, format: format)
        engine.connect(arp2ReverbSendMixer, to: reverbNode, format: format)
        engine.connect(melodyReverbSendMixer, to: reverbNode, format: format)
        engine.connect(reverbNode, to: mainNode, format: format)

        engine.connect(arpDelaySendMixer, to: delayNode, format: format)
        engine.connect(arp2DelaySendMixer, to: delayNode, format: format)
        engine.connect(delayNode, to: mainNode, format: format)

        applyChannelVolumes()
        applyChannelPans()
        applyReverbSends()
        applyDelaySends()

        // Setup SoundFont samplers — route through channel mixers for pan/volume
        soundFontManager = SoundFontManager(engine: engine)
        soundFontManager?.setupSamplers(
            padMixer: padMixer,
            arpMixer: arpMixer,
            arp2Mixer: arp2Mixer,
            melodyMixer: melodyMixer,
            drumMixer: kickMixer, // drums go through kick mixer (shares beat mute)
            format: format
        )
    }

    private func applyChannelVolumes() {
        padMixer.outputVolume = dbToGain(channelVolumes["pad"] ?? -14)
        arpMixer.outputVolume = dbToGain(channelVolumes["arp"] ?? -8)
        arp2Mixer.outputVolume = dbToGain(channelVolumes["arp2"] ?? -10)
        melodyMixer.outputVolume = dbToGain(channelVolumes["melody"] ?? -6)
        kickMixer.outputVolume = dbToGain(channelVolumes["kick"] ?? -6)
        snareMixer.outputVolume = dbToGain(channelVolumes["snare"] ?? -10)
        hatMixer.outputVolume = dbToGain(channelVolumes["hat"] ?? -16)
        binauralMixer.outputVolume = dbToGain(channelVolumes["binaural"] ?? -20)
    }

    private func applyChannelPans() {
        padMixer.pan = channelPans["pad"] ?? 0
        arpMixer.pan = channelPans["arp"] ?? 0
        arp2Mixer.pan = channelPans["arp2"] ?? 0
        melodyMixer.pan = channelPans["melody"] ?? 0
        kickMixer.pan = channelPans["kick"] ?? 0
        snareMixer.pan = channelPans["snare"] ?? 0
        hatMixer.pan = channelPans["hat"] ?? 0
        binauralMixer.pan = channelPans["binaural"] ?? 0
    }

    private func applyReverbSends() {
        padReverbSendMixer.outputVolume = channelReverbSends["pad"] ?? 0.3
        arpReverbSendMixer.outputVolume = channelReverbSends["arp"] ?? 0.2
        arp2ReverbSendMixer.outputVolume = channelReverbSends["arp2"] ?? 0.2
        melodyReverbSendMixer.outputVolume = channelReverbSends["melody"] ?? 0.15
    }

    private func applyDelaySends() {
        arpDelaySendMixer.outputVolume = channelDelaySends["arp"] ?? 0.25
        arp2DelaySendMixer.outputVolume = channelDelaySends["arp2"] ?? 0.2
    }

    private func dbToGain(_ db: Float) -> Float {
        pow(10, db / 20)
    }

    private func setupDefaultDrumPattern() {
        let kick:  [Int] = [1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0]
        let snare: [Int] = [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0]
        let hat:   [Int] = [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]
        drumPattern = [kick, snare, hat]
        drumVelocity = drumPattern.map { $0.map { Float($0) * 0.7 } }
    }

    // MARK: - Start / Stop

    func start() {
        do {
            try engine.start()
            isPlaying = true
            // Arp/drum sequencing now handled in kick render callback (sample-accurate)
            // No more Timer-based sequencing
        } catch {
            print("Engine start error: \(error)")
        }
    }

    func stop() {
        chordAdvanceTimer?.invalidate()
        riserTimer?.invalidate()
        engine.stop()
        isPlaying = false
    }

    // Convert note value string to beat divisor (e.g. "8n" = 2 per beat)
    private func noteValueDivisor(_ value: String) -> Int {
        switch value {
        case "4n": return 1
        case "8n": return 2
        case "8n.": return 2 // dotted 8th ≈ treat as 8th for step grid
        case "16n": return 4
        case "16n.": return 4
        case "32n": return 8
        case "8t": return 3
        default: return 2
        }
    }

    // MARK: - Riser Synth

    func startRiser() {
        riserActive = true
        riserOsc.startSweep()

        // Duck pad + drums over 4 seconds
        for ch in ["pad", "kick", "snare", "hat"] {
            preRiserGains[ch] = channelVolumes[ch] ?? -10
        }

        // Gradual duck over 4 seconds using timer
        let steps = 20
        let stepInterval = 4.0 / Double(steps)
        var currentStep = 0
        riserTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            let duckFactor = 1.0 - progress * 0.9  // duck to 10%

            for ch in ["pad", "kick", "snare", "hat"] {
                let baseGain = self.dbToGain(self.preRiserGains[ch] ?? -10)
                self.mixerForChannel(ch)?.outputVolume = baseGain * duckFactor
            }

            if currentStep >= steps {
                timer.invalidate()
                // Auto-drop after 4 seconds
                self.dropRiser()
            }
        }
    }

    func dropRiser() {
        riserActive = false
        riserOsc.stopSweep()
        riserTimer?.invalidate()

        // Big kick hit
        kickOsc.trigger(velocity: 1.0)

        // Restore ducked volumes
        for ch in ["pad", "kick", "snare", "hat"] {
            let vol = preRiserGains[ch] ?? channelVolumes[ch] ?? -10
            mixerForChannel(ch)?.outputVolume = dbToGain(vol)
        }
        preRiserGains = [:]
    }

    func cancelRiser() {
        riserActive = false
        riserOsc.stopSweep()
        riserTimer?.invalidate()

        for ch in ["pad", "kick", "snare", "hat"] {
            let vol = preRiserGains[ch] ?? channelVolumes[ch] ?? -10
            mixerForChannel(ch)?.outputVolume = dbToGain(vol)
        }
        preRiserGains = [:]
    }

    // MARK: - Tap Tempo

    func tapTempo() {
        let now = Date()
        tapTimes.append(now)

        // Keep only taps within 3 seconds
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) < 3.0 }

        guard tapTimes.count >= 2 else { return }

        // Calculate average interval between taps
        var intervals: [Double] = []
        for i in 1..<tapTimes.count {
            intervals.append(tapTimes[i].timeIntervalSince(tapTimes[i-1]))
        }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let newBPM = 60.0 / avgInterval
        lastTapBPM = newBPM
        setBPM(max(40, min(200, newBPM)))
    }

    // MARK: - Chord Auto-Advance

    func toggleChordAutoAdvance(state: JammermanState) {
        chordAutoAdvance.toggle()
        if chordAutoAdvance {
            startChordAdvance(state: state)
        } else {
            stopChordAdvance()
        }
    }

    private func startChordAdvance(state: JammermanState) {
        chordAdvanceStep = state.chordIndex
        let barDuration = (60.0 / bpm) * 4.0 // 4 beats per bar
        chordAdvanceTimer = Timer.scheduledTimer(withTimeInterval: barDuration, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.chordAdvanceStep = (self.chordAdvanceStep + 1) % 6
            DispatchQueue.main.async {
                state.chordIndex = self.chordAdvanceStep
            }
        }
    }

    private func stopChordAdvance() {
        chordAdvanceTimer?.invalidate()
        chordAdvanceTimer = nil
    }

    // MARK: - Per-channel Pan Control

    func setChannelPan(_ channel: String, pan: Float) {
        channelPans[channel] = max(-1, min(1, pan))
        mixerForChannel(channel)?.pan = channelPans[channel] ?? 0
    }

    // MARK: - Per-channel Reverb Send

    func setChannelReverbSend(_ channel: String, amount: Float) {
        channelReverbSends[channel] = max(0, min(1, amount))
        switch channel {
        case "pad": padReverbSendMixer?.outputVolume = amount
        case "arp": arpReverbSendMixer?.outputVolume = amount
        case "arp2": arp2ReverbSendMixer?.outputVolume = amount
        case "melody": melodyReverbSendMixer?.outputVolume = amount
        default: break
        }
    }

    // MARK: - Per-channel Delay Send

    func setChannelDelaySend(_ channel: String, amount: Float) {
        channelDelaySends[channel] = max(0, min(1, amount))
        switch channel {
        case "arp": arpDelaySendMixer?.outputVolume = amount
        case "arp2": arp2DelaySendMixer?.outputVolume = amount
        default: break
        }
    }

    // MARK: - Per-channel EQ

    func setChannelEQ(_ channel: String, band: Int, gain: Float) {
        guard band >= 0, band < 3 else { return }
        var gains = channelEQGains[channel] ?? [0, 0, 0]
        gains[band] = max(-12, min(12, gain))
        channelEQGains[channel] = gains
        channelEQs[channel]?.bands[band].gain = gains[band]
    }

    // MARK: - Sidechain Send

    // MARK: - FX Parameters

    func setReverbParams(wetDry: Float? = nil, preset: Int? = nil) {
        if let wd = wetDry { reverbWetDry = wd; reverbNode.wetDryMix = wd }
        if let p = preset {
            reverbPreset = p
            let presets: [AVAudioUnitReverbPreset] = [.mediumHall, .largeHall, .cathedral, .plate, .smallRoom, .mediumRoom, .largeRoom]
            if p < presets.count { reverbNode.loadFactoryPreset(presets[p]) }
        }
    }

    func setDelayParams(time: Float? = nil, feedback: Float? = nil, wetDry: Float? = nil, cutoff: Float? = nil) {
        if let t = time { delayTime = t; delayNode.delayTime = TimeInterval(t / 1000.0) }
        if let f = feedback { delayFeedback = f; delayNode.feedback = f }
        if let wd = wetDry { delayWetDry = wd; delayNode.wetDryMix = wd }
        if let c = cutoff { delayCutoff = c; delayNode.lowPassCutoff = c }
    }

    // MARK: - Solo

    func toggleSolo(_ channel: String) {
        if soloChannel == channel {
            soloChannel = nil
        } else {
            soloChannel = channel
        }
        // Update all channel volumes based on solo state (mirrors web _updateSoloState)
        let channels = ["pad", "arp", "arp2", "melody", "kick", "snare", "hat", "binaural"]
        for ch in channels {
            let mixer = mixerForChannel(ch)
            if isMuted(ch) {
                mixer?.outputVolume = 0
            } else if soloChannel != nil && soloChannel != ch {
                mixer?.outputVolume = 0 // mute non-solo'd channels
            } else {
                mixer?.outputVolume = dbToGain(channelVolumes[ch] ?? -10)
            }
        }
    }

    // MARK: - Hat Trigger (for count-in clicks)

    func triggerHat(velocity: Float = 0.5) {
        hatOsc.trigger(velocity: velocity)
    }

    // MARK: - Mixer Helper

    private func mixerForChannel(_ channel: String) -> AVAudioMixerNode? {
        switch channel {
        case "pad": return padMixer
        case "arp": return arpMixer
        case "arp2": return arp2Mixer
        case "melody": return melodyMixer
        case "kick": return kickMixer
        case "snare": return snareMixer
        case "hat": return hatMixer
        case "binaural": return binauralMixer
        default: return nil
        }
    }

    // MARK: - Pad

    func triggerPad(notes: [String]) {
        let midiNotes = notes.compactMap { noteNameToMidi($0) }

        // Use either synth oscillator or SoundFont sampler, not both
        if useSoundFont, let sfm = soundFontManager {
            let newNotes = midiNotes.map { UInt8($0) }
            let oldNotes = currentPadMidiNotes
            currentPadMidiNotes = newNotes

            // Cancel any pending crossfade stop from a previous chord change
            padCrossfadeWorkItem?.cancel()

            // Crossfade: start new chord FIRST, then stop ALL old notes after brief overlap
            if !padMuted {
                sfm.playChord(newNotes, velocity: 90, on: sfm.padSampler)
            }
            if !oldNotes.isEmpty {
                let work = DispatchWorkItem { [weak sfm] in
                    sfm?.stopChord(oldNotes, on: sfm?.padSampler)
                }
                padCrossfadeWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
            }
        } else {
            padOsc.triggerNotes(midiNotes)
        }
        // Update binaural if following chord
        if binauralFollowChord, let first = midiNotes.first {
            // Divide by 2 to keep binaural in low range (~A2 = 110Hz), matching web
            let baseFreq = 440.0 * pow(2.0, Double(first - 69) / 12.0) / 2.0
            binauralOsc.setBaseFrequency(Float(baseFreq))
        }
    }

    func releasePad() {
        padOsc.release()
        if let sfm = soundFontManager {
            sfm.stopChord(currentPadMidiNotes, on: sfm.padSampler)
        }
    }

    // MARK: - Melody

    func startMelody(_ note: Int) {
        if useSoundFont, let sfm = soundFontManager {
            if let prev = currentMelodyMidiNote { sfm.stopNote(prev, on: sfm.leadSampler) }
            if !melodyMuted {
                currentMelodyMidiNote = UInt8(note)
                sfm.playNote(UInt8(note), velocity: 100, on: sfm.leadSampler)
            }
        } else {
            melodyOsc.triggerNote(note)
        }
    }

    func updateMelody(_ note: Int) {
        if useSoundFont, let sfm = soundFontManager {
            if let prev = currentMelodyMidiNote { sfm.stopNote(prev, on: sfm.leadSampler) }
            if !melodyMuted {
                currentMelodyMidiNote = UInt8(note)
                sfm.playNote(UInt8(note), velocity: 90, on: sfm.leadSampler)
            }
        } else {
            melodyOsc.glideToNote(note)
        }
    }

    func stopMelody() {
        melodyOsc.release()
        if let sfm = soundFontManager, let note = currentMelodyMidiNote {
            sfm.stopNote(note, on: sfm.leadSampler)
            currentMelodyMidiNote = nil
        }
    }

    func setPortamento(_ on: Bool) { melodyOsc.portamentoEnabled = on }

    // MARK: - Arp 1

    func updateArpNotes(_ notes: [String]) {
        arpNotes = notes.compactMap { noteNameToMidi($0) }
    }

    func setArpPattern(_ pattern: String) {
        arpPattern = pattern
        arpIndex = 0
        arpDirection = 1
    }

    func setArpNoteValue(_ value: String) {
        arpNoteValue = value
    }

    // Old Timer-based sequencers removed — now sample-accurate in kick render callback

    // MARK: - Arp 2

    func updateArp2Notes(_ notes: [String]) {
        arp2Notes = notes.compactMap { noteNameToMidi($0) }
    }

    func setArp2Pattern(_ pattern: String) {
        arp2Pattern = pattern
        arp2Index = 0
        arp2Direction = 1
    }

    func setArp2NoteValue(_ value: String) {
        arp2NoteValue = value
    }

    // MARK: - Shared Arp Logic

    private func getNextArpNote(notes: [Int], index: inout Int, direction: inout Int, pattern: String) -> Int {
        let count = notes.count
        let note: Int
        switch pattern {
        case "up":
            note = notes[index % count]
            index += 1
        case "down":
            note = notes[count - 1 - (index % count)]
            index += 1
        case "random":
            note = notes[Int.random(in: 0..<count)]
        case "up-down":
            note = notes[index % count]
            index += direction
            if index >= count - 1 { direction = -1; index = count - 1 }
            if index <= 0 { direction = 1; index = 0 }
        case "up-up-down":
            // Two up, one down
            let cycle = index % 3
            if cycle < 2 { index += 1 } else { index -= 1 }
            note = notes[max(0, min(count - 1, index % count))]
        default:
            note = notes[index % count]
            index += 1
        }
        return note
    }

    // MARK: - Drums

    func setBPM(_ newBPM: Double) {
        bpm = max(40, min(200, newBPM))
        // No Timer restart needed — sample-accurate clock adapts automatically
    }

    func setDrumPattern(_ pattern: [[Int]]) {
        drumPattern = pattern
        drumVelocity = pattern.map { $0.map { Float($0) * 0.7 } }
        drumStep = 0
    }

    func setDrumStep(drum: Int, step: Int, active: Bool, velocity: Float = 0.7) {
        guard drum < drumPattern.count, step < drumPattern[drum].count else { return }
        drumPattern[drum][step] = active ? 1 : 0
        if drum < drumVelocity.count, step < drumVelocity[drum].count {
            drumVelocity[drum][step] = velocity
        }
    }

    // Old Timer-based drum sequencer removed — now in kick render callback

    // MARK: - Binaural

    func setBinauralBeatHz(_ hz: Float) {
        binauralBeatHz = hz
        binauralOsc.setBeatHz(hz)
    }

    func toggleBinaural() {
        binauralActive.toggle()
    }

    // MARK: - Parameter Updates (face-driven)

    func updateParams(state: JammermanState) {
        // Reverb wet: eye openness
        reverbNode.wetDryMix = state.eyeOpenness * 60

        // Delay feedback: mouth width
        delayNode.feedback = Float(state.mouthWidth) * 50

        // Master filter: head pitch controls brightness via EQ
        // Pitch down = dark (cut highs), pitch up = bright (boost highs)
        let pitchN = 1 - max(0, min(1, (state.headPitch + 0.4) / 0.8))

        // Low shelf: boost bass when head down
        masterEQ.bands[0].gain = Float((1 - pitchN) * 4) // 0 to +4 dB

        // High shelf: full range sweep -12 to +6 dB based on pitch
        masterEQ.bands[2].gain = Float((pitchN - 0.3) * 18) // -5.4 to +12.6 dB
        // Set frequency to simulate lowpass sweep
        masterEQ.bands[2].frequency = 800 + pitchN * 9200 // 800 Hz to 10000 Hz

        // Chorus depth from head roll (tilt = more chorus)
        // (Would need chorus node — approximated via slight detune/stereo effect in future)
    }

    // MARK: - Toggle Mute

    func toggleMute(channel: String) {
        switch channel {
        case "pad": padMuted.toggle()
        case "arp": arpMuted.toggle()
        case "arp2": arp2Muted.toggle()
        case "melody": melodyMuted.toggle()
        case "beat": beatMuted.toggle()
        case "binaural": binauralActive.toggle()
        default: break
        }

        // Handle SoundFont sampler note-off on mute
        if let sfm = soundFontManager {
            switch channel {
            case "pad":
                if padMuted { sfm.stopChord(currentPadMidiNotes, on: sfm.padSampler) }
            case "melody":
                if melodyMuted, let note = currentMelodyMidiNote {
                    sfm.stopNote(note, on: sfm.leadSampler)
                    currentMelodyMidiNote = nil
                }
            default: break
            }
            // Volume/mute is handled by the channel mixer that the sampler routes through
        }
    }

    func isMuted(_ channel: String) -> Bool {
        switch channel {
        case "pad": return padMuted
        case "arp": return arpMuted
        case "arp2": return arp2Muted
        case "melody": return melodyMuted
        case "beat": return beatMuted
        case "binaural": return !binauralActive
        default: return true
        }
    }

    // MARK: - Volume Control

    func setChannelVolume(_ channel: String, db: Float) {
        channelVolumes[channel] = db
        let gain = dbToGain(db)
        switch channel {
        case "pad": padMixer.outputVolume = gain
        case "arp": arpMixer.outputVolume = gain
        case "arp2": arp2Mixer.outputVolume = gain
        case "melody": melodyMixer.outputVolume = gain
        case "kick": kickMixer.outputVolume = gain
        case "snare": snareMixer.outputVolume = gain
        case "hat": hatMixer.outputVolume = gain
        case "binaural": binauralMixer.outputVolume = gain
        default: break
        }
    }

    // MARK: - Presets

    func applyPreset(_ preset: JammermanPreset, state: JammermanState) {
        setBPM(preset.bpm)
        state.rootOffset = preset.rootOffset
        setArpPattern(preset.arpPattern)
        swing = preset.swing

        // Channel volumes
        setChannelVolume("pad", db: preset.padVolume)
        setChannelVolume("arp", db: preset.arpVolume)
        setChannelVolume("melody", db: preset.melodyVolume)
        setChannelVolume("kick", db: preset.kickVolume)
        setChannelVolume("snare", db: preset.snareVolume)
        setChannelVolume("hat", db: preset.hatVolume)

        // Pad synth
        padOsc.harmonicity = preset.padHarmonicity
        padOsc.modulationIndex = preset.padModIndex
        padOsc.attackRate = 1.0 / (preset.padAttack * sampleRate)
        padOsc.releaseRate = 1.0 / (preset.padRelease * sampleRate)

        // Arp synth
        arpOsc.attack = preset.arpAttack
        arpOsc.decay = preset.arpDecay
        arpOsc.sustain = preset.arpSustain
        arpOsc.releaseTime = preset.arpRelease

        // Melody synth
        melodyOsc.attack = preset.melAttack
        melodyOsc.decay = preset.melDecay
        melodyOsc.sustain = preset.melSustain
        melodyOsc.releaseTime = preset.melRelease
    }

    // MARK: - Helpers

    private func noteValueToSeconds(_ value: String) -> Double {
        let beatDuration = 60.0 / bpm
        switch value {
        case "4n": return beatDuration
        case "8n": return beatDuration / 2
        case "8n.": return beatDuration * 3 / 4
        case "16n": return beatDuration / 4
        case "16n.": return beatDuration * 3 / 8
        case "32n": return beatDuration / 8
        case "8t": return beatDuration / 3
        default: return beatDuration / 2
        }
    }

    func noteNameToMidi(_ name: String) -> Int? {
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

// MARK: - PolyBLEP Anti-Aliased Waveforms
// Eliminates digital harshness from naive waveforms

@inline(__always)
func polyBLEP(_ t: Double, _ dt: Double) -> Double {
    // t = phase (0..1), dt = freq/sampleRate (phase increment)
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1.0
    } else if t > 1.0 - dt {
        let x = (t - 1.0) / dt
        return x * x + x + x + 1.0
    }
    return 0
}

func waveformSample(phase: Double, type: WaveformType) -> Double {
    switch type {
    case .sine:
        return sin(phase * 2.0 * .pi)
    case .triangle:
        let t = phase - floor(phase)
        return t < 0.5 ? (4.0 * t - 1.0) : (3.0 - 4.0 * t)
    case .sawtooth:
        return 2.0 * (phase - floor(phase)) - 1.0
    case .square:
        return (phase - floor(phase)) < 0.5 ? 1.0 : -1.0
    }
}

// Band-limited sawtooth (polyBLEP)
@inline(__always)
func sawBLEP(phase: Double, dt: Double) -> Double {
    var saw = 2.0 * phase - 1.0
    saw -= polyBLEP(phase, dt)
    return saw
}

// Band-limited square (polyBLEP)
@inline(__always)
func squareBLEP(phase: Double, dt: Double) -> Double {
    var sq = phase < 0.5 ? 1.0 : -1.0
    sq += polyBLEP(phase, dt)
    sq -= polyBLEP(fmod(phase + 0.5, 1.0), dt)
    return sq
}

// Resonant 2-pole State Variable Filter (SVF)
struct SVFilter {
    var low: Double = 0
    var band: Double = 0
    var high: Double = 0
    var notch: Double = 0

    mutating func process(_ input: Double, cutoff: Double, resonance: Double, sampleRate: Double) -> Double {
        let f = 2.0 * sin(.pi * min(cutoff, sampleRate * 0.45) / sampleRate)
        let q = max(0.5, 1.0 - resonance)
        high = input - low - q * band
        band += f * high
        low += f * band
        notch = high + low
        return low
    }
}

// Soft clipper for analog warmth
@inline(__always)
func softClip(_ x: Double, drive: Double = 1.0) -> Double {
    let d = x * drive
    return d / (1.0 + abs(d))
}

// MARK: - Pad Oscillator (FM + Sub)

class PadOscillator {
    private var phases: [Double] = []
    private var subPhases: [Double] = []
    private var detunePhases: [Double] = [] // stereo detune layer
    private var frequencies: [Double] = []
    private var envelope: Double = 0
    private var targetEnvelope: Double = 0
    var attackRate: Double = 0.001
    var releaseRate: Double = 0.0003
    var harmonicity: Double = 1.5
    var modulationIndex: Double = 2.5
    var waveformType: WaveformType = .sine
    // Chorus LFO
    private var chorusPhase: Double = 0
    private let chorusRate: Double = 1.2
    private let chorusDepth: Double = 0.003 // ±3ms detune

    func triggerNotes(_ midiNotes: [Int]) {
        let newFreqs = midiNotes.map { 440.0 * pow(2.0, Double($0 - 69) / 12.0) }
        while phases.count < newFreqs.count { phases.append(Double.random(in: 0...1)) }
        while subPhases.count < newFreqs.count { subPhases.append(0) }
        while detunePhases.count < newFreqs.count { detunePhases.append(Double.random(in: 0...1)) }
        frequencies = newFreqs
        targetEnvelope = 1.0
    }

    func release() { targetEnvelope = 0.0 }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let freqs = frequencies
        let numFreqs = min(freqs.count, phases.count)

        for frame in 0..<Int(frameCount) {
            if envelope < targetEnvelope { envelope = min(envelope + attackRate, targetEnvelope) }
            else { envelope = max(envelope - releaseRate, targetEnvelope) }

            // Chorus LFO for stereo width
            chorusPhase += chorusRate / sampleRate
            if chorusPhase > 1 { chorusPhase -= 1 }
            let chorusMod = sin(chorusPhase * 2.0 * .pi) * chorusDepth

            var sampleL: Float = 0, sampleR: Float = 0
            if !muted && envelope > 0.001 && numFreqs > 0 {
                for i in 0..<numFreqs {
                    let freq = freqs[i]
                    let dt = freq / sampleRate
                    // FM synthesis
                    let modSignal = sin(phases[i] * harmonicity * 2.0 * .pi) * modulationIndex
                    let carrier = waveformSample(phase: phases[i] + modSignal / (2.0 * .pi), type: waveformType)
                    // Sub oscillator (one octave down, pure sine)
                    let sub = sin(subPhases[i] * 2.0 * .pi) * 0.45
                    // Detuned layer for stereo (±5 cents + chorus)
                    let detuneL = sin(detunePhases[i] * 0.997 * 2.0 * .pi) * 0.3
                    let detuneR = sin(detunePhases[i] * 1.003 * 2.0 * .pi) * 0.3

                    let dry = carrier + sub
                    let amp = Float(softClip(envelope * 0.8, drive: 1.2)) * 0.12
                    sampleL += Float(dry + detuneL * (1.0 + chorusMod)) * amp
                    sampleR += Float(dry + detuneR * (1.0 - chorusMod)) * amp

                    phases[i] += dt
                    subPhases[i] += dt * 0.5
                    detunePhases[i] += dt
                    if phases[i] > 1 { phases[i] -= 1 }
                    if subPhases[i] > 1 { subPhases[i] -= 1 }
                    if detunePhases[i] > 1 { detunePhases[i] -= 1 }
                }
            }
            L[frame] = sampleL; R[frame] = sampleR
        }
        return noErr
    }
}

// MARK: - Arp Oscillator (Filtered Sawtooth)

class ArpOscillator {
    private var phase: Double = 0
    private var frequency: Double = 440
    private var envelope: Double = 0
    private var filterEnv: Double = 0
    var attack: Float = 0.005
    var decay: Float = 0.25
    var sustain: Float = 0.15
    var releaseTime: Float = 0.25
    var attackTime: Double = 0.005
    var decayTime: Double = 0.25
    private var envStage: Int = 0
    private var svf = SVFilter()
    var waveformType: WaveformType = .sawtooth

    func triggerNote(_ midi: Int) {
        frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        envelope = 1.0
        filterEnv = 1.0
        envStage = 2
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let decayRate = 1.0 - 1.0 / (Double(decay) * sampleRate + 1)
        let filterDecayRate = 1.0 - 1.0 / (Double(decay) * sampleRate * 0.8 + 1)
        let dt = frequency / sampleRate

        for frame in 0..<Int(frameCount) {
            envelope *= decayRate
            let sustainLevel = Double(sustain)
            if envelope < sustainLevel * 0.5 { envelope *= 0.999 } // slow sustain tail
            filterEnv *= filterDecayRate

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                // Band-limited oscillator
                let raw: Double
                switch waveformType {
                case .sawtooth: raw = sawBLEP(phase: phase, dt: dt)
                case .square: raw = squareBLEP(phase: phase, dt: dt)
                default: raw = waveformSample(phase: phase, type: waveformType)
                }

                // Resonant SVF filter with envelope
                let cutoff = 200.0 + filterEnv * 4800.0 // 200-5000Hz sweep
                let filtered = svf.process(raw, cutoff: cutoff, resonance: 0.3, sampleRate: sampleRate)
                sample = Float(softClip(filtered * envelope, drive: 1.1)) * 0.3

                phase += dt
                if phase > 1.0 { phase -= 1.0 }
            }
            L[frame] = sample; R[frame] = sample
        }
        return noErr
    }
}

// MARK: - Melody Oscillator (Mono Saw + Portamento + Vibrato)

class MelodyOscillator {
    private var phase: Double = 0
    private var frequency: Double = 440
    private var targetFrequency: Double = 440
    private var envelope: Double = 0
    private var targetEnvelope: Double = 0
    var portamentoEnabled: Bool = true
    private let glideRate: Double = 0.003
    private var vibratoPhase: Double = 0
    var vibratoAmount: Float = 0.0 // 0..1
    private let vibratoRate: Double = 5.0
    // Exposed ADSR
    var attack: Float = 0.05
    var decay: Float = 0.20
    var sustain: Float = 0.70
    var releaseTime: Float = 0.40
    // Filter
    private var filterEnv: Double = 0
    private var svf = SVFilter()
    var waveformType: WaveformType = .sawtooth

    func triggerNote(_ midi: Int) {
        targetFrequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        if !portamentoEnabled { frequency = targetFrequency }
        targetEnvelope = 1.0
        filterEnv = 1.0
    }

    func glideToNote(_ midi: Int) {
        targetFrequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        targetEnvelope = 1.0
    }

    func release() { targetEnvelope = 0.0 }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let attackRate = 1.0 / (max(Double(attack), 0.001) * sampleRate)
        let releaseRate = 1.0 / (max(Double(self.releaseTime), 0.001) * sampleRate)
        let vibDepth = Double(vibratoAmount) * 0.006

        for frame in 0..<Int(frameCount) {
            frequency += (targetFrequency - frequency) * glideRate
            if envelope < targetEnvelope { envelope = min(envelope + attackRate, targetEnvelope) }
            else { envelope = max(envelope - releaseRate, targetEnvelope) }
            filterEnv *= 0.9995

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                vibratoPhase += vibratoRate / sampleRate
                let vibrato = 1.0 + sin(vibratoPhase * 2.0 * .pi) * vibDepth
                let freq = frequency * vibrato
                let dt = freq / sampleRate

                // Band-limited oscillator
                let raw: Double
                switch waveformType {
                case .sawtooth: raw = sawBLEP(phase: phase, dt: dt)
                case .square: raw = squareBLEP(phase: phase, dt: dt)
                default: raw = waveformSample(phase: phase, type: waveformType)
                }

                // Resonant SVF filter with envelope
                let cutoff = 300.0 + filterEnv * 5000.0
                let filtered = svf.process(raw, cutoff: cutoff, resonance: 0.25, sampleRate: sampleRate)
                sample = Float(softClip(filtered * envelope, drive: 1.0)) * 0.35

                phase += dt
                if phase > 1.0 { phase -= 1.0 }
            }
            L[frame] = sample; R[frame] = sample
        }
        return noErr
    }
}

// MARK: - Drum Oscillator

class DrumOscillator {
    enum DrumType { case kick, snare, hat }
    let type: DrumType
    private var phase: Double = 0
    private var phase2: Double = 0 // second oscillator for metallic hat
    private var envelope: Double = 0
    private var clickEnv: Double = 0 // transient click layer
    private var pitchEnv: Double = 0
    private var noiseState: UInt32 = 12345
    private var hpState: Double = 0 // highpass for hat
    private var prevSample: Double = 0

    init(type: DrumType) { self.type = type }

    func trigger(velocity: Float = 0.8) {
        envelope = Double(velocity)
        clickEnv = Double(velocity) * 1.2
        pitchEnv = 1.0
        phase = 0
        phase2 = 0
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            var sample: Float = 0
            if !muted && envelope > 0.001 {
                switch type {
                case .kick:
                    // Body: sine with pitch sweep 150→45Hz
                    let freq = 45.0 + pitchEnv * 105.0
                    let body = sin(phase * 2.0 * .pi) * envelope
                    // Sub thump: pure low sine
                    let sub = sin(phase * 0.5 * 2.0 * .pi) * envelope * 0.5
                    // Click transient: short noise burst
                    let click = Double(nextNoise()) * clickEnv * 0.4
                    sample = Float(softClip(body + sub + click, drive: 1.3)) * 0.65
                    phase += freq / sampleRate
                    if phase > 1.0 { phase -= 1.0 }
                    envelope *= 0.9991
                    pitchEnv *= 0.995
                    clickEnv *= 0.97 // click dies fast

                case .snare:
                    // Noise through bandpass
                    let noise = Double(nextNoise())
                    // Tonal body (~180Hz)
                    let body = sin(phase * 2.0 * .pi) * min(envelope * 2, 1) * 0.3
                    phase += 180.0 / sampleRate
                    if phase > 1.0 { phase -= 1.0 }
                    // Click snap
                    let snap = Double(nextNoise()) * clickEnv * 0.3
                    // Mix: noise dominant, body for punch, snap for attack
                    sample = Float(softClip((noise * envelope * 0.35 + body + snap) * 0.6, drive: 1.1))
                    envelope *= 0.9980
                    clickEnv *= 0.96

                case .hat:
                    // Metallic: two detuned square waves for ring
                    let sq1 = phase < 0.5 ? 1.0 : -1.0
                    let sq2 = phase2 < 0.5 ? 1.0 : -1.0
                    let metallic = (sq1 + sq2 * 0.7) * 0.15
                    // Noise through highpass
                    let noise = Double(nextNoise())
                    let hp = noise - prevSample
                    prevSample = noise * 0.95
                    // Mix
                    sample = Float((hp * 0.5 + metallic) * envelope) * 0.25
                    phase += 587.0 / sampleRate // inharmonic freq 1
                    phase2 += 843.0 / sampleRate // inharmonic freq 2
                    if phase > 1.0 { phase -= 1.0 }
                    if phase2 > 1.0 { phase2 -= 1.0 }
                    envelope *= 0.9970
                }
            }
            L[frame] = sample; R[frame] = sample
        }
        return noErr
    }

    private func nextNoise() -> Float {
        noiseState = noiseState &* 1103515245 &+ 12345
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }
}

// MARK: - Binaural Oscillator

class BinauralOscillator {
    private var phaseL: Double = 0
    private var phaseR: Double = 0
    private var baseFreq: Float = 110
    private var beatHz: Float = 2.5

    func setBaseFrequency(_ freq: Float) { baseFreq = freq }
    func setBeatHz(_ hz: Float) { beatHz = hz }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let freqL = Double(baseFreq - beatHz / 2)
        let freqR = Double(baseFreq + beatHz / 2)

        for frame in 0..<Int(frameCount) {
            if muted {
                L[frame] = 0; R[frame] = 0
            } else {
                L[frame] = Float(sin(phaseL * 2.0 * .pi)) * 0.15
                R[frame] = Float(sin(phaseR * 2.0 * .pi)) * 0.15
                phaseL += freqL / sampleRate
                phaseR += freqR / sampleRate
                if phaseL > 1.0 { phaseL -= 1.0 }
                if phaseR > 1.0 { phaseR -= 1.0 }
            }
        }
        return noErr
    }
}

// MARK: - Riser Oscillator (Filtered Noise Sweep)

class RiserOscillator {
    private var noiseState: UInt32 = 54321
    private var gain: Double = 0
    private var targetGain: Double = 0
    private var filterFreq: Double = 200
    private var targetFilterFreq: Double = 200
    private var sweeping = false
    // Simple 1-pole bandpass state
    private var bpState: Float = 0

    func startSweep() {
        sweeping = true
        targetGain = 0.3
        targetFilterFreq = 4000
    }

    func stopSweep() {
        sweeping = false
        targetGain = 0
        targetFilterFreq = 200
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let gainRate = sweeping ? 0.0001 : 0.001  // slow ramp up, fast ramp down
        let filterRate = sweeping ? 0.0002 : 0.002

        for frame in 0..<Int(frameCount) {
            // Smooth gain and filter
            gain += (targetGain - gain) * gainRate
            filterFreq += (targetFilterFreq - filterFreq) * filterRate

            var sample: Float = 0
            if !muted && gain > 0.001 {
                // Pink-ish noise
                noiseState = noiseState &* 1103515245 &+ 12345
                let noise = Float(Int32(bitPattern: noiseState)) / Float(Int32.max)

                // Simple bandpass: 1-pole lowpass as approximation
                let cutoff = Float(min(0.9, filterFreq / sampleRate * 2.0))
                bpState += cutoff * (noise - bpState)
                sample = bpState * Float(gain)
            }
            L[frame] = sample; R[frame] = sample
        }
        return noErr
    }
}
