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
    private var chordAdvanceTimer: Timer?
    private var chordAdvanceStep = 0

    // Solo state
    @Published var soloChannel: String? = nil

    // Channel volumes (dB)
    var channelVolumes: [String: Float] = [
        "pad": -14, "arp": -8, "arp2": -10, "melody": -6,
        "kick": -6, "snare": -10, "hat": -16, "binaural": -20
    ]

    // Per-channel pan (-1 to +1)
    var channelPans: [String: Float] = [
        "pad": 0, "arp": 0, "arp2": 0, "melody": 0,
        "kick": 0, "snare": 0, "hat": 0, "binaural": 0
    ]

    // Per-channel reverb send (0 to 1)
    var channelReverbSends: [String: Float] = [
        "pad": 0.3, "arp": 0.2, "arp2": 0.2, "melody": 0.15,
        "kick": 0, "snare": 0.05, "hat": 0, "binaural": 0
    ]

    // Per-channel delay send (0 to 1)
    var channelDelaySends: [String: Float] = [
        "pad": 0, "arp": 0.25, "arp2": 0.2, "melody": 0.1,
        "kick": 0, "snare": 0, "hat": 0, "binaural": 0
    ]

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
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Build Audio Graph

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        padNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.padOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.padMuted)
        }
        arpNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.arpOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.arpMuted)
        }
        arp2Node = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.arp2Osc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.arp2Muted)
        }
        melodyNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.melodyOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.melodyMuted)
        }
        kickNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.kickOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.beatMuted)
        }
        snareNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.snareOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.beatMuted)
        }
        hatNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.hatOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: self.beatMuted)
        }
        binauralNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.binauralOsc.render(frameCount: frameCount, bufferList: bufferList, sampleRate: self.sampleRate, muted: !self.binauralActive)
        }
        riserNode = AVAudioSourceNode { [weak self] _, _, frameCount, bufferList -> OSStatus in
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
        for eq in channelEQs.values { allNodes.append(eq) }
        for node in allNodes { engine.attach(node) }

        // Wire: synths → channel EQs → channel mixers
        let sourceToMixer: [(AVAudioSourceNode, String, AVAudioMixerNode)] = [
            (padNode, "pad", padMixer),
            (arpNode, "arp", arpMixer),
            (arp2Node, "arp2", arp2Mixer),
            (melodyNode, "melody", melodyMixer),
            (kickNode, "kick", kickMixer),
            (snareNode, "snare", snareMixer),
            (hatNode, "hat", hatMixer),
            (binauralNode, "binaural", binauralMixer),
        ]
        for (src, name, mixer) in sourceToMixer {
            if let eq = channelEQs[name] {
                engine.connect(src, to: eq, format: format)
                engine.connect(eq, to: mixer, format: format)
            } else {
                engine.connect(src, to: mixer, format: format)
            }
        }

        // Riser has no per-channel EQ
        engine.connect(riserNode, to: riserMixer, format: format)

        // Wire: channel mixers → master (dry)
        let allChannelMixers: [AVAudioMixerNode] = [padMixer, arpMixer, arp2Mixer, melodyMixer, kickMixer, snareMixer, hatMixer, binauralMixer, riserMixer]
        for ch in allChannelMixers {
            engine.connect(ch, to: masterMixer, format: format)
        }

        // Send: reverb sends (pad, arp, arp2, melody → reverb)
        engine.connect(padMixer, to: padReverbSendMixer, format: format)
        engine.connect(arpMixer, to: arpReverbSendMixer, format: format)
        engine.connect(arp2Mixer, to: arp2ReverbSendMixer, format: format)
        engine.connect(melodyMixer, to: melodyReverbSendMixer, format: format)
        engine.connect(padReverbSendMixer, to: reverbNode, format: format)
        engine.connect(arpReverbSendMixer, to: reverbNode, format: format)
        engine.connect(arp2ReverbSendMixer, to: reverbNode, format: format)
        engine.connect(melodyReverbSendMixer, to: reverbNode, format: format)
        engine.connect(reverbNode, to: masterMixer, format: format)

        // Send: delay sends (arp, arp2 → delay)
        engine.connect(arpMixer, to: arpDelaySendMixer, format: format)
        engine.connect(arp2Mixer, to: arp2DelaySendMixer, format: format)
        engine.connect(arpDelaySendMixer, to: delayNode, format: format)
        engine.connect(arp2DelaySendMixer, to: delayNode, format: format)
        engine.connect(delayNode, to: masterMixer, format: format)

        // Master → EQ → output
        engine.connect(masterMixer, to: masterEQ, format: format)
        engine.connect(masterEQ, to: engine.mainMixerNode, format: format)

        applyChannelVolumes()
        applyChannelPans()
        applyReverbSends()
        applyDelaySends()
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
            startArpSequencer()
            startArp2Sequencer()
            startDrumSequencer()
        } catch {
            print("Engine start error: \(error)")
        }
    }

    func stop() {
        arpTimer?.invalidate()
        arp2Timer?.invalidate()
        drumTimer?.invalidate()
        chordAdvanceTimer?.invalidate()
        riserTimer?.invalidate()
        engine.stop()
        isPlaying = false
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

    // MARK: - Solo

    func toggleSolo(_ channel: String) {
        if soloChannel == channel {
            soloChannel = nil
        } else {
            soloChannel = channel
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
        if midiNotes.isEmpty {
            print("[PAD] triggerPad called with EMPTY notes from: \(notes)")
        } else {
            print("[PAD] triggerPad: \(notes) → MIDI \(midiNotes), padMuted=\(padMuted)")
        }
        padOsc.triggerNotes(midiNotes)
        // Update binaural if following chord
        if binauralFollowChord, let first = midiNotes.first {
            // Divide by 2 to keep binaural in low range (~A2 = 110Hz), matching web
            let baseFreq = 440.0 * pow(2.0, Double(first - 69) / 12.0) / 2.0
            binauralOsc.setBaseFrequency(Float(baseFreq))
        }
    }

    func releasePad() { padOsc.release() }

    // MARK: - Melody

    func startMelody(_ note: Int) { melodyOsc.triggerNote(note) }
    func updateMelody(_ note: Int) { melodyOsc.glideToNote(note) }
    func stopMelody() { melodyOsc.release() }
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
        if isPlaying { startArpSequencer() }
    }

    private func startArpSequencer() {
        arpTimer?.invalidate()
        let interval = noteValueToSeconds(arpNoteValue)
        arpTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceArp()
        }
    }

    private func advanceArp() {
        guard !arpNotes.isEmpty, !arpMuted else { return }
        let note = getNextArpNote(notes: arpNotes, index: &arpIndex, direction: &arpDirection, pattern: arpPattern)
        arpOsc.triggerNote(note)
    }

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
        if isPlaying { startArp2Sequencer() }
    }

    private func startArp2Sequencer() {
        arp2Timer?.invalidate()
        let interval = noteValueToSeconds(arp2NoteValue)
        arp2Timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceArp2()
        }
    }

    private func advanceArp2() {
        guard !arp2Notes.isEmpty, !arp2Muted else { return }
        let note = getNextArpNote(notes: arp2Notes, index: &arp2Index, direction: &arp2Direction, pattern: arp2Pattern)
        arp2Osc.triggerNote(note)
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
        if isPlaying {
            startArpSequencer()
            startArp2Sequencer()
            startDrumSequencer()
        }
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

    private func startDrumSequencer() {
        drumTimer?.invalidate()
        let interval = noteValueToSeconds("16n")
        drumTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceDrum()
        }
    }

    // Sidechain ducking state
    private var sidechainGain: Float = 1.0

    private func advanceDrum() {
        guard !beatMuted, drumPattern.count >= 3 else { return }
        let step = drumStep % drumPattern[0].count

        if drumPattern[0][step] == 1 {
            let vel = drumVelocity.count > 0 && step < drumVelocity[0].count ? drumVelocity[0][step] : 0.8
            kickOsc.trigger(velocity: vel)
            // Sidechain duck: reduce pad volume on kick
            if !padMuted {
                sidechainGain = 0.15
                padMixer?.outputVolume = dbToGain(channelVolumes["pad"] ?? -14) * sidechainGain
                // Schedule recovery over ~100ms
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.sidechainGain = 0.5
                    self?.padMixer?.outputVolume = (self?.dbToGain(self?.channelVolumes["pad"] ?? -14) ?? 0.2) * 0.5
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.sidechainGain = 1.0
                    let vol = self?.channelVolumes["pad"] ?? -14
                    self?.padMixer?.outputVolume = self?.dbToGain(vol) ?? 0.2
                }
            }
        }
        if drumPattern[1][step] == 1 {
            let vel = drumVelocity.count > 1 && step < drumVelocity[1].count ? drumVelocity[1][step] : 0.7
            snareOsc.trigger(velocity: vel)
        }
        if drumPattern[2][step] == 1 {
            let vel = drumVelocity.count > 2 && step < drumVelocity[2].count ? drumVelocity[2][step] : 0.5
            hatOsc.trigger(velocity: vel)
        }

        DispatchQueue.main.async { [weak self] in
            self?.drumStep += 1
        }
    }

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

// MARK: - Waveform Helper

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

// MARK: - Pad Oscillator (FM + Sub)

class PadOscillator {
    private var phases: [Double] = []
    private var subPhases: [Double] = []
    private var _frequencies: [Double] = []
    private var renderFreqs: [Double] = [] // thread-safe copy for render
    private var envelope: Double = 0
    private var targetEnvelope: Double = 0
    var attackRate: Double = 0.001
    var releaseRate: Double = 0.0003
    var harmonicity: Double = 1.5
    var modulationIndex: Double = 2.5
    var waveformType: WaveformType = .sine
    private var needsUpdate = false

    func triggerNotes(_ midiNotes: [Int]) {
        _frequencies = midiNotes.map { 440.0 * pow(2.0, Double($0 - 69) / 12.0) }
        while phases.count < _frequencies.count { phases.append(Double.random(in: 0...1)) }
        while subPhases.count < _frequencies.count { subPhases.append(0) }
        targetEnvelope = 1.0
        needsUpdate = true
    }

    func release() { targetEnvelope = 0.0 }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        // Copy frequencies from main thread safely
        if needsUpdate {
            renderFreqs = _frequencies
            needsUpdate = false
        }

        for frame in 0..<Int(frameCount) {
            if envelope < targetEnvelope { envelope = min(envelope + attackRate, targetEnvelope) }
            else { envelope = max(envelope - releaseRate, targetEnvelope) }

            var sampleL: Float = 0, sampleR: Float = 0
            if !muted && envelope > 0.001 {
                for i in 0..<renderFreqs.count where i < phases.count {
                    let freq = renderFreqs[i]
                    // FM synthesis with selectable carrier waveform
                    let modSignal = sin(phases[i] * harmonicity * 2.0 * .pi) * modulationIndex
                    let carrier = waveformSample(phase: phases[i] + modSignal / (2.0 * .pi), type: waveformType)
                    // Sub oscillator (one octave down)
                    let sub = sin(subPhases[i] * 2.0 * .pi) * 0.4
                    // Slight stereo spread via detuning
                    let spread = sin(phases[i] * 1.003 * 2.0 * .pi) * 0.05
                    let amp = Float(envelope) * 0.12
                    sampleL += Float(carrier + sub - spread) * amp
                    sampleR += Float(carrier + sub + spread) * amp
                    phases[i] += freq / sampleRate
                    subPhases[i] += (freq * 0.5) / sampleRate
                    if phases[i] > 1 { phases[i] -= 1 }
                    if subPhases[i] > 1 { subPhases[i] -= 1 }
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
    // Exposed ADSR params
    var attack: Float = 0.005
    var decay: Float = 0.25
    var sustain: Float = 0.15
    var releaseTime: Float = 0.25
    var attackTime: Double = 0.005
    var decayTime: Double = 0.25
    private var envStage: Int = 0 // 0=off, 1=attack, 2=decay, 3=sustain, 4=release
    // Simple 1-pole lowpass state
    private var lpState: Float = 0
    private var lpCutoff: Float = 0.3
    var waveformType: WaveformType = .sawtooth

    func triggerNote(_ midi: Int) {
        frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        envelope = 1.0
        filterEnv = 1.0
        envStage = 2 // skip to decay for pluck character
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        let decayRate = 1.0 - 1.0 / (Double(decay) * sampleRate + 1)
        let filterDecayRate = 1.0 - 1.0 / (Double(decay) * sampleRate * 0.8 + 1)

        for frame in 0..<Int(frameCount) {
            envelope *= decayRate
            if envelope < Double(sustain) { envelope = Double(sustain) * envelope / max(Double(sustain), 0.001) }
            filterEnv *= filterDecayRate

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                let raw = Float(waveformSample(phase: phase, type: waveformType))
                // 1-pole lowpass filter
                lpCutoff = Float(0.05 + filterEnv * 0.45)
                lpState += lpCutoff * (raw - lpState)
                sample = lpState * Float(envelope) * 0.3

                phase += frequency / sampleRate
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
    private var lpState: Float = 0
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
                // Vibrato
                vibratoPhase += vibratoRate / sampleRate
                let vibrato = 1.0 + sin(vibratoPhase * 2.0 * .pi) * vibDepth
                let freq = frequency * vibrato

                let raw = Float(waveformSample(phase: phase, type: waveformType))
                // Filter
                let cutoff = Float(0.1 + filterEnv * 0.4)
                lpState += cutoff * (raw - lpState)
                sample = lpState * Float(envelope) * 0.35

                phase += freq / sampleRate
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
    private var envelope: Double = 0
    private var pitchEnv: Double = 0
    private var noiseState: UInt32 = 12345

    init(type: DrumType) { self.type = type }

    func trigger(velocity: Float = 0.8) {
        envelope = Double(velocity)
        pitchEnv = 1.0
        phase = 0
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
                    let freq = 50.0 + pitchEnv * 120.0
                    sample = Float(sin(phase * 2.0 * .pi) * envelope) * 0.7
                    phase += freq / sampleRate
                    if phase > 1.0 { phase -= 1.0 }
                    envelope *= 0.9992
                    pitchEnv *= 0.996
                case .snare:
                    let noise = nextNoise()
                    let tone = Float(sin(phase * 2.0 * .pi) * min(envelope * 2, 1)) * 0.25
                    phase += 180.0 / sampleRate
                    if phase > 1.0 { phase -= 1.0 }
                    sample = (noise * Float(envelope) * 0.35 + tone) * 0.55
                    envelope *= 0.9982
                case .hat:
                    let noise = nextNoise()
                    // Simulate highpass via differentiation
                    sample = noise * Float(envelope) * 0.22
                    envelope *= 0.9975
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
