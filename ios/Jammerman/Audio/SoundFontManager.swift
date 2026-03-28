// Jammerman — SoundFont Manager
// Loads instruments from MuseScore General SF2 via AVAudioUnitSampler
// MIT Licensed — https://musescore.org/en/handbook/2/soundfonts-and-sfz-files

import AVFoundation

class SoundFontManager {
    private let engine: AVAudioEngine

    // Samplers for each instrument role
    var padSampler: AVAudioUnitSampler?
    var leadSampler: AVAudioUnitSampler?
    var bassSampler: AVAudioUnitSampler?

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

    func setupSamplers(mainMixerNode: AVAudioNode, format: AVAudioFormat) {
        guard soundFontURL != nil else {
            print("[SFManager] Cannot setup — SoundFont file not found")
            return
        }

        // Create samplers
        padSampler = AVAudioUnitSampler()
        leadSampler = AVAudioUnitSampler()
        bassSampler = AVAudioUnitSampler()

        // Attach to engine
        engine.attach(padSampler!)
        engine.attach(leadSampler!)
        engine.attach(bassSampler!)

        // Connect to output
        engine.connect(padSampler!, to: mainMixerNode, format: format)
        engine.connect(leadSampler!, to: mainMixerNode, format: format)
        engine.connect(bassSampler!, to: mainMixerNode, format: format)

        // Load default instruments
        loadPadPreset(0)
        loadLeadPreset(0)
        loadBassPreset(0)

        // Set initial volumes
        padSampler?.masterGain = 0 // full volume for testing
        leadSampler?.masterGain = 0
        bassSampler?.masterGain = 0
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

    func loadBassPreset(_ index: Int) {
        let presets = Self.bassPresets
        guard index < presets.count, let sampler = bassSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bankMSB, bankLSB: p.bankLSB)
            print("[SFManager] Bass loaded: \(p.name) (program \(p.program), bankMSB \(p.bankMSB))")
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
