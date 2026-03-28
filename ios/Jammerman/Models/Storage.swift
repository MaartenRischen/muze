// Jammerman — Storage (UserDefaults persistence)
// Uses JSON encoding to avoid NSUserDefaults plist compatibility issues

import Foundation

enum JammermanStorage {
    private static let key = "jammerman-settings-v2"

    static func save(state: JammermanState, engine: AudioEngine) {
        var dict: [String: String] = [:] // all values as strings for plist safety

        dict["rootOffset"] = "\(state.rootOffset)"
        dict["presetIdx"] = "\(state.presetIdx)"
        dict["extraScaleMode"] = state.extraScaleMode ?? ""
        dict["modeFrozen"] = state.modeFrozen ? "1" : "0"

        dict["bpm"] = "\(engine.bpm)"
        dict["swing"] = "\(engine.swing)"

        dict["arpPattern"] = engine.arpPattern
        dict["arpNoteValue"] = engine.arpNoteValue
        dict["arp2Pattern"] = engine.arp2Pattern
        dict["arp2NoteValue"] = engine.arp2NoteValue

        // Volumes as comma-separated key:value pairs
        dict["volumes"] = engine.channelVolumes.map { "\($0.key):\($0.value)" }.joined(separator: ",")

        dict["padMuted"] = engine.padMuted ? "1" : "0"
        dict["arpMuted"] = engine.arpMuted ? "1" : "0"
        dict["arp2Muted"] = engine.arp2Muted ? "1" : "0"
        dict["melodyMuted"] = engine.melodyMuted ? "1" : "0"
        dict["beatMuted"] = engine.beatMuted ? "1" : "0"
        dict["binauralActive"] = engine.binauralActive ? "1" : "0"

        dict["binauralBeatHz"] = "\(engine.binauralBeatHz)"
        dict["binauralFollowChord"] = engine.binauralFollowChord ? "1" : "0"

        dict["padHarmonicity"] = "\(engine.padOsc.harmonicity)"
        dict["padModIndex"] = "\(engine.padOsc.modulationIndex)"
        dict["arpAttack"] = "\(engine.arpOsc.attack)"
        dict["arpDecay"] = "\(engine.arpOsc.decay)"
        dict["arpSustain"] = "\(engine.arpOsc.sustain)"
        dict["arpRelease"] = "\(engine.arpOsc.releaseTime)"
        dict["melAttack"] = "\(engine.melodyOsc.attack)"
        dict["melDecay"] = "\(engine.melodyOsc.decay)"
        dict["melSustain"] = "\(engine.melodyOsc.sustain)"
        dict["melRelease"] = "\(engine.melodyOsc.releaseTime)"
        dict["melVibrato"] = "\(engine.melodyOsc.vibratoAmount)"
        dict["portamento"] = engine.melodyOsc.portamentoEnabled ? "1" : "0"

        // Drum pattern as semicolon-separated rows of comma-separated values
        dict["drumPattern"] = engine.drumPattern.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";")

        UserDefaults.standard.set(dict, forKey: key)
    }

    static func load(state: JammermanState, engine: AudioEngine) {
        // Clear ALL stale storage from any version
        UserDefaults.standard.removeObject(forKey: "jammerman-settings-v1")
        UserDefaults.standard.removeObject(forKey: "jammerman-settings-v3")
        // Force fresh start every time version changes
        let ver = "v3.6.3"
        if UserDefaults.standard.string(forKey: "jammerman-ver") != ver {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set(ver, forKey: "jammerman-ver")
            return
        }
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return }

        if let v = dict["rootOffset"], let n = Int(v) { state.rootOffset = n }
        if let v = dict["presetIdx"], let n = Int(v) { state.presetIdx = n }
        if let v = dict["extraScaleMode"] { state.extraScaleMode = v.isEmpty ? nil : v }
        if let v = dict["modeFrozen"] { state.modeFrozen = v == "1" }

        if let v = dict["bpm"], let n = Double(v) { engine.setBPM(n) }
        if let v = dict["swing"], let n = Int(v) { engine.swing = n }

        if let v = dict["arpPattern"] { engine.setArpPattern(v) }
        if let v = dict["arpNoteValue"] { engine.setArpNoteValue(v) }
        if let v = dict["arp2Pattern"] { engine.setArp2Pattern(v) }
        if let v = dict["arp2NoteValue"] { engine.setArp2NoteValue(v) }

        if let v = dict["volumes"] {
            for pair in v.split(separator: ",") {
                let parts = pair.split(separator: ":")
                if parts.count == 2, let db = Float(parts[1]) {
                    engine.setChannelVolume(String(parts[0]), db: db)
                }
            }
        }

        if let v = dict["padMuted"] { engine.padMuted = v == "1" }
        if let v = dict["arpMuted"] { engine.arpMuted = v == "1" }
        if let v = dict["arp2Muted"] { engine.arp2Muted = v == "1" }
        if let v = dict["melodyMuted"] { engine.melodyMuted = v == "1" }
        if let v = dict["beatMuted"] { engine.beatMuted = v == "1" }
        if let v = dict["binauralActive"] { engine.binauralActive = v == "1" }

        if let v = dict["binauralBeatHz"], let n = Float(v) { engine.setBinauralBeatHz(n) }
        if let v = dict["binauralFollowChord"] { engine.binauralFollowChord = v == "1" }

        if let v = dict["padHarmonicity"], let n = Double(v) { engine.padOsc.harmonicity = n }
        if let v = dict["padModIndex"], let n = Double(v) { engine.padOsc.modulationIndex = n }
        if let v = dict["arpAttack"], let n = Float(v) { engine.arpOsc.attack = n }
        if let v = dict["arpDecay"], let n = Float(v) { engine.arpOsc.decay = n }
        if let v = dict["arpSustain"], let n = Float(v) { engine.arpOsc.sustain = n }
        if let v = dict["arpRelease"], let n = Float(v) { engine.arpOsc.releaseTime = n }
        if let v = dict["melAttack"], let n = Float(v) { engine.melodyOsc.attack = n }
        if let v = dict["melDecay"], let n = Float(v) { engine.melodyOsc.decay = n }
        if let v = dict["melSustain"], let n = Float(v) { engine.melodyOsc.sustain = n }
        if let v = dict["melRelease"], let n = Float(v) { engine.melodyOsc.releaseTime = n }
        if let v = dict["melVibrato"], let n = Float(v) { engine.melodyOsc.vibratoAmount = n }
        if let v = dict["portamento"] { engine.melodyOsc.portamentoEnabled = v == "1" }

        if let v = dict["drumPattern"] {
            let rows = v.split(separator: ";").map { $0.split(separator: ",").compactMap { Int($0) } }
            if rows.count >= 3 { engine.setDrumPattern(rows) }
        }
    }
}
