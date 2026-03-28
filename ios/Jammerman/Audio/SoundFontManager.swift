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

    // Available instrument presets (Bank 0 = melodic, Bank 128 = drums)
    struct Preset {
        let name: String
        let bank: UInt8  // MSB
        let program: UInt8
    }

    static let padPresets: [Preset] = [
        Preset(name: "Warm Pad", bank: 0, program: 89),
        Preset(name: "Synth Strings", bank: 0, program: 50),
        Preset(name: "Halo Pad", bank: 0, program: 94),
        Preset(name: "Atmosphere", bank: 0, program: 99),
        Preset(name: "Sweep Pad", bank: 0, program: 95),
        Preset(name: "Choir Aahs", bank: 0, program: 52),
        Preset(name: "Strings Slow", bank: 0, program: 49),
        Preset(name: "Polysynth", bank: 0, program: 90),
    ]

    static let leadPresets: [Preset] = [
        Preset(name: "Saw Lead", bank: 0, program: 81),
        Preset(name: "Square Lead", bank: 0, program: 80),
        Preset(name: "Calliope Lead", bank: 0, program: 82),
        Preset(name: "Chiffer Lead", bank: 0, program: 83),
        Preset(name: "Charang", bank: 0, program: 84),
        Preset(name: "FM Piano", bank: 0, program: 5),
        Preset(name: "Music Box", bank: 0, program: 10),
        Preset(name: "Vibraphone", bank: 0, program: 11),
    ]

    static let bassPresets: [Preset] = [
        Preset(name: "Synth Bass 1", bank: 0, program: 38),
        Preset(name: "Synth Bass 2", bank: 0, program: 39),
        Preset(name: "Fingered Bass", bank: 0, program: 33),
        Preset(name: "Picked Bass", bank: 0, program: 34),
        Preset(name: "Acoustic Bass", bank: 0, program: 32),
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
        padSampler?.masterGain = -6 // dB
        leadSampler?.masterGain = -3
        bassSampler?.masterGain = -6
    }

    func loadPadPreset(_ index: Int) {
        let presets = Self.padPresets
        guard index < presets.count, let sampler = padSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bank, bankLSB: 0)
            print("[SFManager] Pad loaded: \(p.name)")
        } catch {
            print("[SFManager] Pad load error: \(error)")
        }
    }

    func loadLeadPreset(_ index: Int) {
        let presets = Self.leadPresets
        guard index < presets.count, let sampler = leadSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bank, bankLSB: 0)
            print("[SFManager] Lead loaded: \(p.name)")
        } catch {
            print("[SFManager] Lead load error: \(error)")
        }
    }

    func loadBassPreset(_ index: Int) {
        let presets = Self.bassPresets
        guard index < presets.count, let sampler = bassSampler, let url = soundFontURL else { return }
        let p = presets[index]
        do {
            try sampler.loadSoundBankInstrument(at: url, program: p.program, bankMSB: p.bank, bankLSB: 0)
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
        for note in midiNotes {
            sampler?.startNote(note, withVelocity: velocity, onChannel: 0)
        }
    }

    func stopChord(_ midiNotes: [UInt8], on sampler: AVAudioUnitSampler?) {
        for note in midiNotes {
            sampler?.stopNote(note, onChannel: 0)
        }
    }
}
