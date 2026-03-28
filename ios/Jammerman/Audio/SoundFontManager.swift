// Jammerman — SoundFont Manager
// Loads instruments from MuseScore General SF2 via AVAudioUnitSampler
// MIT Licensed — https://musescore.org/en/handbook/2/soundfonts-and-sfz-files

import AVFoundation

class SoundFontManager {
    private let engine: AVAudioEngine

    // Samplers for each instrument role
    var padSampler: AVAudioUnitSampler?
    var leadSampler: AVAudioUnitSampler?
    var arpSampler: AVAudioUnitSampler?
    var arp2Sampler: AVAudioUnitSampler?
    var drumSampler: AVAudioUnitSampler?
    var bassSampler: AVAudioUnitSampler?

    // GM percussion note mapping
    static let gmKick: UInt8 = 36
    static let gmSnare: UInt8 = 38
    static let gmClosedHat: UInt8 = 42
    static let gmOpenHat: UInt8 = 46

    // Available instrument presets
    // AVAudioUnitSampler uses GM convention: bankMSB 0x79 (121) for melodic, 0x78 (120) for drums
    struct Preset {
        let name: String
        let program: UInt8
        let bankMSB: UInt8
        let bankLSB: UInt8
    }

    static let padPresets: [Preset] = [
        Preset(name: "Warm Pad", program: 89, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Synth Strings", program: 50, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Halo Pad", program: 94, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Atmosphere", program: 99, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Sweep Pad", program: 95, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Choir Aahs", program: 52, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Strings Slow", program: 49, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Polysynth", program: 90, bankMSB: 0x79, bankLSB: 0),
    ]

    static let leadPresets: [Preset] = [
        Preset(name: "Saw Lead", program: 81, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Square Lead", program: 80, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Calliope Lead", program: 82, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Chiffer Lead", program: 83, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Charang", program: 84, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "FM Piano", program: 5, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Music Box", program: 10, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Vibraphone", program: 11, bankMSB: 0x79, bankLSB: 0),
    ]

    static let arpPresets: [Preset] = [
        Preset(name: "FM Piano", program: 5, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Vibraphone", program: 11, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Music Box", program: 10, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Tine EP", program: 4, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Celesta", program: 8, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Marimba", program: 12, bankMSB: 0x79, bankLSB: 0),
    ]

    static let drumPresets: [Preset] = [
        Preset(name: "Standard Kit", program: 0, bankMSB: 0x78, bankLSB: 0),
        Preset(name: "Room Kit", program: 8, bankMSB: 0x78, bankLSB: 0),
        Preset(name: "Power Kit", program: 16, bankMSB: 0x78, bankLSB: 0),
        Preset(name: "Electronic Kit", program: 24, bankMSB: 0x78, bankLSB: 0),
        Preset(name: "TR-808 Kit", program: 25, bankMSB: 0x78, bankLSB: 0),
        Preset(name: "Jazz Kit", program: 32, bankMSB: 0x78, bankLSB: 0),
    ]

    static let bassPresets: [Preset] = [
        Preset(name: "Synth Bass 1", program: 38, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Synth Bass 2", program: 39, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Fingered Bass", program: 33, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Picked Bass", program: 34, bankMSB: 0x79, bankLSB: 0),
        Preset(name: "Acoustic Bass", program: 32, bankMSB: 0x79, bankLSB: 0),
    ]

    private var soundFontURL: URL?

    init(engine: AVAudioEngine) {
        self.engine = engine
        soundFontURL = Bundle.main.url(forResource: "MuseScore_General", withExtension: "sf2")
        if soundFontURL != nil {
            print("[SFManager] Found SF2 at: \(soundFontURL!)")
        } else {
            // Try alternate locations
            let resourcesFolder = Bundle.main.url(forResource: "Resources", withExtension: nil)
            print("[SFManager] SF2 NOT found via forResource. Resources folder: \(resourcesFolder?.path ?? "nil")")
            // List bundle contents for debugging
            if let bundlePath = Bundle.main.resourcePath {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: bundlePath)) ?? []
                let sf2Files = files.filter { $0.hasSuffix(".sf2") }
                print("[SFManager] SF2 files in bundle: \(sf2Files)")
                // Check in Resources subfolder
                let resPath = bundlePath + "/Resources"
                let resFiles = (try? FileManager.default.contentsOfDirectory(atPath: resPath)) ?? []
                print("[SFManager] Files in Resources/: \(resFiles)")
            }
        }
    }

    /// Route each sampler through its channel mixer so pan/volume/EQ apply
    func setupSamplers(
        padMixer: AVAudioMixerNode,
        arpMixer: AVAudioMixerNode,
        arp2Mixer: AVAudioMixerNode,
        melodyMixer: AVAudioMixerNode,
        drumMixer: AVAudioMixerNode,
        format: AVAudioFormat
    ) {
        guard soundFontURL != nil else {
            print("[SFManager] Cannot setup — SoundFont file not found")
            return
        }

        padSampler = AVAudioUnitSampler()
        leadSampler = AVAudioUnitSampler()
        arpSampler = AVAudioUnitSampler()
        arp2Sampler = AVAudioUnitSampler()
        drumSampler = AVAudioUnitSampler()
        bassSampler = AVAudioUnitSampler()

        // Attach all
        let samplers: [AVAudioUnitSampler] = [padSampler!, leadSampler!, arpSampler!, arp2Sampler!, drumSampler!, bassSampler!]
        for s in samplers { engine.attach(s) }

        // Route through channel mixers (inherits pan, volume, EQ, sends)
        engine.connect(padSampler!, to: padMixer, format: format)
        engine.connect(leadSampler!, to: melodyMixer, format: format)
        engine.connect(arpSampler!, to: arpMixer, format: format)
        engine.connect(arp2Sampler!, to: arp2Mixer, format: format)
        engine.connect(drumSampler!, to: drumMixer, format: format)
        engine.connect(bassSampler!, to: padMixer, format: format) // bass through pad mixer for now

        // Load default instruments
        loadPadPreset(0)
        loadLeadPreset(0)
        loadArpPreset(0, sampler: arpSampler)
        loadArpPreset(2, sampler: arp2Sampler)
        loadDrumPreset(0)
        loadBassPreset(0)

        // Warm up all samplers by triggering a silent note — forces SF2 sample
        // data to be paged into memory so first real note doesn't cause a CPU spike
        warmUpSamplers()
    }

    private func warmUpSamplers() {
        let samplers: [(AVAudioUnitSampler?, UInt8, UInt8)] = [
            (padSampler, 60, 0),      // C4 on channel 0
            (leadSampler, 60, 0),
            (arpSampler, 60, 0),
            (arp2Sampler, 60, 0),
            (bassSampler, 36, 0),     // C2
            (drumSampler, Self.gmKick, 9),
        ]
        // Trigger at velocity 1 (barely audible), stop after 50ms
        for (sampler, note, ch) in samplers {
            sampler?.startNote(note, withVelocity: 1, onChannel: ch)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for (sampler, note, ch) in samplers {
                sampler?.stopNote(note, onChannel: ch)
            }
        }
    }

    func loadPadPreset(_ index: Int) {
        let presets = Self.padPresets
        guard index < presets.count, let sampler = padSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bankMSB, bankLSB: p.bankLSB)
            print("[SFManager] Pad loaded: \(p.name) (program \(p.program), bankMSB \(p.bankMSB))")
        } catch {
            print("[SFManager] Pad load error: \(error)")
        }
    }

    func loadLeadPreset(_ index: Int) {
        let presets = Self.leadPresets
        guard index < presets.count, let sampler = leadSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bankMSB, bankLSB: p.bankLSB)
            print("[SFManager] Lead loaded: \(p.name) (program \(p.program), bankMSB \(p.bankMSB))")
        } catch {
            print("[SFManager] Lead load error: \(error)")
        }
    }

    func loadArpPreset(_ index: Int, sampler: AVAudioUnitSampler?) {
        let presets = Self.arpPresets
        guard index < presets.count, let sampler = sampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bankMSB, bankLSB: p.bankLSB)
            print("[SFManager] Arp loaded: \(p.name)")
        } catch {
            print("[SFManager] Arp load error: \(error)")
        }
    }

    func loadDrumPreset(_ index: Int) {
        let presets = Self.drumPresets
        guard index < presets.count, let sampler = drumSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bankMSB, bankLSB: p.bankLSB)
            print("[SFManager] Drums loaded: \(p.name)")
        } catch {
            print("[SFManager] Drums load error: \(error)")
        }
    }

    func loadBassPreset(_ index: Int) {
        let presets = Self.bassPresets
        guard index < presets.count, let sampler = bassSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bankMSB, bankLSB: p.bankLSB)
            print("[SFManager] Bass loaded: \(p.name)")
        } catch {
            print("[SFManager] Bass load error: \(error)")
        }
    }

    // Play a note on a sampler
    func playNote(_ midi: UInt8, velocity: UInt8 = 90, on sampler: AVAudioUnitSampler?) {
        sampler?.startNote(midi, withVelocity: velocity, onChannel: 0)
    }

    func stopNote(_ midi: UInt8, on sampler: AVAudioUnitSampler?) {
        sampler?.stopNote(midi, onChannel: 0)
    }

    // Play chord (multiple notes)
    func playChord(_ midiNotes: [UInt8], velocity: UInt8 = 80, on sampler: AVAudioUnitSampler?) {
        guard let s = sampler else { print("[SFManager] playChord: sampler is nil"); return }
        print("[SFManager] playChord: \(midiNotes) vel=\(velocity)")
        for note in midiNotes {
            s.startNote(note, withVelocity: velocity, onChannel: 0)
        }
    }

    func stopChord(_ midiNotes: [UInt8], on sampler: AVAudioUnitSampler?) {
        for note in midiNotes {
            sampler?.stopNote(note, onChannel: 0)
        }
    }
}
