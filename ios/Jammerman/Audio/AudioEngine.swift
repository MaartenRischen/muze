// Jammerman — Audio Engine
// AVAudioEngine with send/return bus topology mirroring web's architecture
// Synths: Pad (FM + sub), Arp1, Arp2, Melody, Drums (kick/snare/hat), Binaural

import AVFoundation
import Accelerate

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

    // Channel mixers
    private var padMixer: AVAudioMixerNode!
    private var arpMixer: AVAudioMixerNode!
    private var arp2Mixer: AVAudioMixerNode!
    private var melodyMixer: AVAudioMixerNode!
    private var kickMixer: AVAudioMixerNode!
    private var snareMixer: AVAudioMixerNode!
    private var hatMixer: AVAudioMixerNode!
    private var binauralMixer: AVAudioMixerNode!

    // Effects
    private var reverbNode: AVAudioUnitReverb!
    private var delayNode: AVAudioUnitDelay!
    private var masterEQ: AVAudioUnitEQ!

    // Master
    private var masterMixer: AVAudioMixerNode!

    // Synth oscillators
    var padOsc = PadOscillator()
    private var arpOsc = ArpOscillator()
    private var arp2Osc = ArpOscillator()
    var melodyOsc = MelodyOscillator()
    private var kickOsc = DrumOscillator(type: .kick)
    private var snareOsc = DrumOscillator(type: .snare)
    private var hatOsc = DrumOscillator(type: .hat)
    private var binauralOsc = BinauralOscillator()

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

    // Channel volumes (dB)
    var channelVolumes: [String: Float] = [
        "pad": -14, "arp": -8, "arp2": -10, "melody": -6,
        "kick": -6, "snare": -10, "hat": -16, "binaural": -20
    ]

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

        // Mixers
        padMixer = AVAudioMixerNode()
        arpMixer = AVAudioMixerNode()
        arp2Mixer = AVAudioMixerNode()
        melodyMixer = AVAudioMixerNode()
        kickMixer = AVAudioMixerNode()
        snareMixer = AVAudioMixerNode()
        hatMixer = AVAudioMixerNode()
        binauralMixer = AVAudioMixerNode()
        masterMixer = AVAudioMixerNode()

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

        // Attach all
        let allNodes: [AVAudioNode] = [
            padNode, arpNode, arp2Node, melodyNode,
            kickNode, snareNode, hatNode, binauralNode,
            padMixer, arpMixer, arp2Mixer, melodyMixer,
            kickMixer, snareMixer, hatMixer, binauralMixer,
            masterMixer, reverbNode, delayNode, masterEQ
        ]
        for node in allNodes { engine.attach(node) }

        // Wire: synths → channel mixers
        engine.connect(padNode, to: padMixer, format: format)
        engine.connect(arpNode, to: arpMixer, format: format)
        engine.connect(arp2Node, to: arp2Mixer, format: format)
        engine.connect(melodyNode, to: melodyMixer, format: format)
        engine.connect(kickNode, to: kickMixer, format: format)
        engine.connect(snareNode, to: snareMixer, format: format)
        engine.connect(hatNode, to: hatMixer, format: format)
        engine.connect(binauralNode, to: binauralMixer, format: format)

        // Wire: channel mixers → master (dry) + effects sends
        let channels: [AVAudioMixerNode] = [padMixer, arpMixer, arp2Mixer, melodyMixer, kickMixer, snareMixer, hatMixer, binauralMixer]
        for ch in channels {
            engine.connect(ch, to: masterMixer, format: format)
        }

        // Send: pad, arp, arp2 → reverb
        engine.connect(padMixer, to: reverbNode, format: format)
        engine.connect(arpMixer, to: reverbNode, format: format)
        engine.connect(arp2Mixer, to: reverbNode, format: format)
        engine.connect(reverbNode, to: masterMixer, format: format)

        // Send: arp, arp2 → delay
        engine.connect(arpMixer, to: delayNode, format: format)
        engine.connect(arp2Mixer, to: delayNode, format: format)
        engine.connect(delayNode, to: masterMixer, format: format)

        // Master → EQ → output
        engine.connect(masterMixer, to: masterEQ, format: format)
        engine.connect(masterEQ, to: engine.mainMixerNode, format: format)

        applyChannelVolumes()
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
        engine.stop()
        isPlaying = false
    }

    // MARK: - Pad

    func triggerPad(notes: [String]) {
        let midiNotes = notes.compactMap { noteNameToMidi($0) }
        padOsc.triggerNotes(midiNotes)
        // Update binaural if following chord
        if binauralFollowChord, let first = midiNotes.first {
            let baseFreq = 440.0 * pow(2.0, Double(first - 69) / 12.0)
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

    private func advanceDrum() {
        guard !beatMuted, drumPattern.count >= 3 else { return }
        let step = drumStep % drumPattern[0].count

        if drumPattern[0][step] == 1 {
            let vel = drumVelocity.count > 0 && step < drumVelocity[0].count ? drumVelocity[0][step] : 0.8
            kickOsc.trigger(velocity: vel)
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

        // Master EQ high shelf: head pitch controls brightness
        let pitchN = 1 - max(0, min(1, (state.headPitch + 0.4) / 0.8))
        masterEQ.bands[2].gain = Float((pitchN - 0.5) * 12) // -6 to +6 dB
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

    func applyPreset(_ preset: [String: Any]) {
        if let b = preset["bpm"] as? Double { setBPM(b) }
        if let r = preset["rootOffset"] as? Int { /* handled by coordinator */ }
        if let p = preset["arpPattern"] as? String { setArpPattern(p) }
        if let pv = preset["padVolume"] as? Float { setChannelVolume("pad", db: pv) }
        if let av = preset["arpVolume"] as? Float { setChannelVolume("arp", db: av) }
        if let mv = preset["melodyVolume"] as? Float { setChannelVolume("melody", db: mv) }
        if let kv = preset["kickVolume"] as? Float { setChannelVolume("kick", db: kv) }
        if let sv = preset["snareVolume"] as? Float { setChannelVolume("snare", db: sv) }
        if let hv = preset["hatVolume"] as? Float { setChannelVolume("hat", db: hv) }
        if let sw = preset["swing"] as? Int { swing = sw }

        // Synth params
        if let padAttack = preset["padAttack"] as? Double { padOsc.attackRate = 1.0 / (padAttack * sampleRate) }
        if let padRelease = preset["padRelease"] as? Double { padOsc.releaseRate = 1.0 / (padRelease * sampleRate) }
        if let arpAttack = preset["arpAttack"] as? Double { arpOsc.attackTime = arpAttack }
        if let arpDecay = preset["arpDecay"] as? Double { arpOsc.decayTime = arpDecay }
        if let rd = preset["reverbDecay"] as? Float { /* reverb decay not directly settable on AVAudioUnitReverb */ }
        if let df = preset["delayFeedback"] as? Float { delayNode.feedback = df * 100 }
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

// MARK: - Pad Oscillator (FM + Sub)

class PadOscillator {
    private var phases: [Double] = []
    private var subPhases: [Double] = []
    private var frequencies: [Double] = []
    private var envelope: Double = 0
    private var targetEnvelope: Double = 0
    var attackRate: Double = 0.001
    var releaseRate: Double = 0.0003
    var harmonicity: Double = 1.5
    var modulationIndex: Double = 2.5

    func triggerNotes(_ midiNotes: [Int]) {
        frequencies = midiNotes.map { 440.0 * pow(2.0, Double($0 - 69) / 12.0) }
        while phases.count < frequencies.count { phases.append(Double.random(in: 0...1)) }
        while subPhases.count < frequencies.count { subPhases.append(0) }
        targetEnvelope = 1.0
    }

    func release() { targetEnvelope = 0.0 }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            if envelope < targetEnvelope { envelope = min(envelope + attackRate, targetEnvelope) }
            else { envelope = max(envelope - releaseRate, targetEnvelope) }

            var sampleL: Float = 0, sampleR: Float = 0
            if !muted && envelope > 0.001 {
                for i in 0..<frequencies.count where i < phases.count {
                    let freq = frequencies[i]
                    // FM synthesis
                    let modSignal = sin(phases[i] * harmonicity * 2.0 * .pi) * modulationIndex
                    let carrier = sin((phases[i] + modSignal / (2.0 * .pi)) * 2.0 * .pi)
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
    var attackTime: Double = 0.005
    var decayTime: Double = 0.25
    private var decayRate: Double = 0.9997
    private var filterDecayRate: Double = 0.999
    // Simple 1-pole lowpass state
    private var lpState: Float = 0
    private var lpCutoff: Float = 0.3

    func triggerNote(_ midi: Int) {
        frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        envelope = 1.0
        filterEnv = 1.0
    }

    func render(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, sampleRate: Double, muted: Bool) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let L = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let R = abl[1].mData!.assumingMemoryBound(to: Float.self)

        for frame in 0..<Int(frameCount) {
            envelope *= decayRate
            filterEnv *= filterDecayRate

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                // Band-limited sawtooth (2 harmonics for less aliasing)
                let saw = Float(2.0 * phase - 1.0)
                // 1-pole lowpass filter
                lpCutoff = Float(0.05 + filterEnv * 0.45)
                lpState += lpCutoff * (saw - lpState)
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
    private let vibratoRate: Double = 5.0
    private let vibratoDepth: Double = 0.003 // ±3 cents equiv
    // Filter
    private var filterEnv: Double = 0
    private var lpState: Float = 0

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

        for frame in 0..<Int(frameCount) {
            frequency += (targetFrequency - frequency) * glideRate
            if envelope < targetEnvelope { envelope = min(envelope + 0.008, targetEnvelope) }
            else { envelope = max(envelope - 0.002, targetEnvelope) }
            filterEnv *= 0.9995

            var sample: Float = 0
            if !muted && envelope > 0.001 {
                // Vibrato
                vibratoPhase += vibratoRate / sampleRate
                let vibrato = 1.0 + sin(vibratoPhase * 2.0 * .pi) * vibratoDepth
                let freq = frequency * vibrato

                let saw = Float(2.0 * phase - 1.0)
                // Filter
                let cutoff = Float(0.1 + filterEnv * 0.4)
                lpState += cutoff * (saw - lpState)
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
