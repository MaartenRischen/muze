// Jammerman — Config & Constants
// Ported from web/js/config.js per shared/SPEC.md

import Foundation

enum Scale {
    // Modal scales (face-controlled via valence)
    static let lydian      = [0, 2, 4, 6, 7, 9, 11]
    static let ionian      = [0, 2, 4, 5, 7, 9, 11]
    static let mixolydian  = [0, 2, 4, 5, 7, 9, 10]
    static let dorian      = [0, 2, 3, 5, 7, 9, 10]
    static let aeolian     = [0, 2, 3, 5, 7, 8, 10]
    static let phrygian    = [0, 1, 3, 5, 7, 8, 10]

    // Extended scales (user-selectable)
    static let extra: [String: [Int]] = [
        "pent. major":   [0, 2, 4, 7, 9],
        "pent. minor":   [0, 3, 5, 7, 10],
        "harm. minor":   [0, 2, 3, 5, 7, 8, 11],
        "whole tone":    [0, 2, 4, 6, 8, 10],
        "blues":         [0, 3, 5, 6, 7, 10],
        "melodic minor": [0, 2, 3, 5, 7, 9, 11],
        "phrygian dom":  [0, 1, 4, 5, 7, 8, 10],
        "hirajoshi":     [0, 2, 3, 7, 8],
    ]
}

enum JammermanConfig {
    static let rootNote = 60          // C4
    static let octaveRange = 2
    static let bpmDefault = 85
    static let bpmMin = 40
    static let bpmMax = 200
    static let chordDegrees = [0, 1, 2, 3, 4, 5]
    static let detectIntervalMs = 50  // 20fps detection

    // Face feature normalization ranges
    static let mouthOpenMin: Float = 0.015
    static let mouthOpenMax: Float = 0.09
    static let lipSmileMin: Float = -0.045
    static let lipSmileMax: Float = 0.045
    static let browMin: Float = 0.100
    static let browMax: Float = 0.143
    static let eyeOpenMin: Float = 0.012
    static let eyeOpenMax: Float = 0.055
    static let mouthWidthMin: Float = 0.28
    static let mouthWidthMax: Float = 0.38

    // Audio ranges
    static let filterFreqMin: Float = 800
    static let filterFreqMax: Float = 10000
    static let reverbWetMin: Float = 0.0
    static let reverbWetMax: Float = 0.75
    static let reverbDecay: Float = 2.5

    // Arp patterns & note values
    static let arpPatterns = ["up-down", "up", "down", "random", "up-up-down", "played"]
    static let arpNoteValues = ["4n", "8n", "8n.", "16n", "16n.", "32n"]

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
}
