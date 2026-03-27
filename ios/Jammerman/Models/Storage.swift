// Jammerman — Storage (UserDefaults persistence)
// Mirrors web's storage.js — saves/loads all settings

import Foundation

enum JammermanStorage {
    private static let key = "jammerman-settings-v1"

    static func save(state: JammermanState, engine: AudioEngine) {
        var dict: [String: Any] = [:]

        // State
        dict["rootOffset"] = state.rootOffset
        dict["presetIdx"] = state.presetIdx
        dict["extraScaleMode"] = state.extraScaleMode as Any
        dict["modeFrozen"] = state.modeFrozen

        // Transport
        dict["bpm"] = engine.bpm
        dict["swing"] = engine.swing

        // Arp settings
        dict["arpPattern"] = engine.arpPattern
        dict["arpNoteValue"] = engine.arpNoteValue
        dict["arp2Pattern"] = engine.arp2Pattern
        dict["arp2NoteValue"] = engine.arp2NoteValue

        // Channel volumes
        dict["channelVolumes"] = engine.channelVolumes

        // Mute states
        dict["padMuted"] = engine.padMuted
        dict["arpMuted"] = engine.arpMuted
        dict["arp2Muted"] = engine.arp2Muted
        dict["melodyMuted"] = engine.melodyMuted
        dict["beatMuted"] = engine.beatMuted
        dict["binauralActive"] = engine.binauralActive

        // Binaural
        dict["binauralBeatHz"] = engine.binauralBeatHz
        dict["binauralFollowChord"] = engine.binauralFollowChord

        // Synth params
        dict["padHarmonicity"] = engine.padOsc.harmonicity
        dict["padModIndex"] = engine.padOsc.modulationIndex
        dict["arpAttack"] = engine.arpOsc.attack
        dict["arpDecay"] = engine.arpOsc.decay
        dict["arpSustain"] = engine.arpOsc.sustain
        dict["arpRelease"] = engine.arpOsc.releaseTime
        dict["melAttack"] = engine.melodyOsc.attack
        dict["melDecay"] = engine.melodyOsc.decay
        dict["melSustain"] = engine.melodyOsc.sustain
        dict["melRelease"] = engine.melodyOsc.releaseTime
        dict["melVibrato"] = engine.melodyOsc.vibratoAmount
        dict["portamento"] = engine.melodyOsc.portamentoEnabled

        // Drum pattern
        dict["drumPattern"] = engine.drumPattern

        UserDefaults.standard.set(dict, forKey: key)
    }

    static func load(state: JammermanState, engine: AudioEngine) {
        guard let dict = UserDefaults.standard.dictionary(forKey: key) else { return }

        // State
        if let v = dict["rootOffset"] as? Int { state.rootOffset = v }
        if let v = dict["presetIdx"] as? Int { state.presetIdx = v }
        if let v = dict["extraScaleMode"] as? String { state.extraScaleMode = v }
        if let v = dict["modeFrozen"] as? Bool { state.modeFrozen = v }

        // Transport
        if let v = dict["bpm"] as? Double { engine.setBPM(v) }
        if let v = dict["swing"] as? Int { engine.swing = v }

        // Arp
        if let v = dict["arpPattern"] as? String { engine.setArpPattern(v) }
        if let v = dict["arpNoteValue"] as? String { engine.setArpNoteValue(v) }
        if let v = dict["arp2Pattern"] as? String { engine.setArp2Pattern(v) }
        if let v = dict["arp2NoteValue"] as? String { engine.setArp2NoteValue(v) }

        // Volumes
        if let vols = dict["channelVolumes"] as? [String: Float] {
            for (ch, db) in vols { engine.setChannelVolume(ch, db: db) }
        }

        // Mutes
        if let v = dict["padMuted"] as? Bool { engine.padMuted = v }
        if let v = dict["arpMuted"] as? Bool { engine.arpMuted = v }
        if let v = dict["arp2Muted"] as? Bool { engine.arp2Muted = v }
        if let v = dict["melodyMuted"] as? Bool { engine.melodyMuted = v }
        if let v = dict["beatMuted"] as? Bool { engine.beatMuted = v }
        if let v = dict["binauralActive"] as? Bool { engine.binauralActive = v }

        // Binaural
        if let v = dict["binauralBeatHz"] as? Float { engine.setBinauralBeatHz(v) }
        if let v = dict["binauralFollowChord"] as? Bool { engine.binauralFollowChord = v }

        // Synth params
        if let v = dict["padHarmonicity"] as? Double { engine.padOsc.harmonicity = v }
        if let v = dict["padModIndex"] as? Double { engine.padOsc.modulationIndex = v }
        if let v = dict["arpAttack"] as? Float { engine.arpOsc.attack = v }
        if let v = dict["arpDecay"] as? Float { engine.arpOsc.decay = v }
        if let v = dict["arpSustain"] as? Float { engine.arpOsc.sustain = v }
        if let v = dict["arpRelease"] as? Float { engine.arpOsc.releaseTime = v }
        if let v = dict["melAttack"] as? Float { engine.melodyOsc.attack = v }
        if let v = dict["melDecay"] as? Float { engine.melodyOsc.decay = v }
        if let v = dict["melSustain"] as? Float { engine.melodyOsc.sustain = v }
        if let v = dict["melRelease"] as? Float { engine.melodyOsc.releaseTime = v }
        if let v = dict["melVibrato"] as? Float { engine.melodyOsc.vibratoAmount = v }
        if let v = dict["portamento"] as? Bool { engine.melodyOsc.portamentoEnabled = v }

        // Drum pattern
        if let v = dict["drumPattern"] as? [[Int]] { engine.setDrumPattern(v) }
    }
}
