// Jammerman — Preset Definitions
// 8 presets matching web app (config.js PRESETS)

import Foundation

struct JammermanPreset {
    let name: String
    let bpm: Double
    let rootOffset: Int
    let padVolume: Float
    let arpVolume: Float
    let melodyVolume: Float
    let kickVolume: Float
    let snareVolume: Float
    let hatVolume: Float
    let arpPattern: String
    let rhythmPattern: Int
    let swing: Int
    let padHarmonicity: Double
    let padModIndex: Double
    let padAttack: Double
    let padRelease: Double
    let arpAttack: Float
    let arpDecay: Float
    let arpSustain: Float
    let arpRelease: Float
    let melAttack: Float
    let melDecay: Float
    let melSustain: Float
    let melRelease: Float
}

let jammermanPresets: [JammermanPreset] = [
    JammermanPreset(name: "Default", bpm: 85, rootOffset: 0,
        padVolume: -14, arpVolume: -8, melodyVolume: -6, kickVolume: -6, snareVolume: -10, hatVolume: -16,
        arpPattern: "up-down", rhythmPattern: 0, swing: 0,
        padHarmonicity: 1.5, padModIndex: 2.5, padAttack: 1.0, padRelease: 2.5,
        arpAttack: 0.005, arpDecay: 0.25, arpSustain: 0.15, arpRelease: 0.25,
        melAttack: 0.05, melDecay: 0.20, melSustain: 0.70, melRelease: 0.40),

    JammermanPreset(name: "Ambient Dream", bpm: 65, rootOffset: 0,
        padVolume: -10, arpVolume: -12, melodyVolume: -8, kickVolume: -60, snareVolume: -60, hatVolume: -60,
        arpPattern: "random", rhythmPattern: 3, swing: 0,
        padHarmonicity: 3.0, padModIndex: 0.8, padAttack: 2.5, padRelease: 5.0,
        arpAttack: 0.3, arpDecay: 1.0, arpSustain: 0.3, arpRelease: 2.0,
        melAttack: 0.4, melDecay: 0.5, melSustain: 0.8, melRelease: 1.5),

    JammermanPreset(name: "Dark Techno", bpm: 128, rootOffset: 0,
        padVolume: -18, arpVolume: -6, melodyVolume: -10, kickVolume: -3, snareVolume: -8, hatVolume: -14,
        arpPattern: "up", rhythmPattern: 1, swing: 0,
        padHarmonicity: 1.0, padModIndex: 4.0, padAttack: 0.3, padRelease: 1.0,
        arpAttack: 0.001, arpDecay: 0.1, arpSustain: 0.2, arpRelease: 0.15,
        melAttack: 0.01, melDecay: 0.1, melSustain: 0.4, melRelease: 0.2),

    JammermanPreset(name: "Lo-Fi Chill", bpm: 72, rootOffset: 5,
        padVolume: -12, arpVolume: -10, melodyVolume: -8, kickVolume: -6, snareVolume: -10, hatVolume: -18,
        arpPattern: "up-down", rhythmPattern: 5, swing: 40,
        padHarmonicity: 2.0, padModIndex: 0.5, padAttack: 1.5, padRelease: 3.0,
        arpAttack: 0.05, arpDecay: 0.5, arpSustain: 0.4, arpRelease: 1.0,
        melAttack: 0.1, melDecay: 0.3, melSustain: 0.6, melRelease: 0.8),

    JammermanPreset(name: "Bright Pop", bpm: 110, rootOffset: 7,
        padVolume: -14, arpVolume: -8, melodyVolume: -6, kickVolume: -4, snareVolume: -8, hatVolume: -14,
        arpPattern: "up-up-down", rhythmPattern: 0, swing: 10,
        padHarmonicity: 2.0, padModIndex: 1.5, padAttack: 0.5, padRelease: 1.5,
        arpAttack: 0.01, arpDecay: 0.2, arpSustain: 0.7, arpRelease: 0.5,
        melAttack: 0.02, melDecay: 0.15, melSustain: 0.6, melRelease: 0.3),

    JammermanPreset(name: "Deep Space", bpm: 55, rootOffset: 3,
        padVolume: -8, arpVolume: -14, melodyVolume: -10, kickVolume: -60, snareVolume: -60, hatVolume: -60,
        arpPattern: "random", rhythmPattern: 3, swing: 0,
        padHarmonicity: 5.0, padModIndex: 2.5, padAttack: 3.0, padRelease: 6.0,
        arpAttack: 0.5, arpDecay: 1.5, arpSustain: 0.2, arpRelease: 3.0,
        melAttack: 0.8, melDecay: 0.5, melSustain: 0.5, melRelease: 2.0),

    JammermanPreset(name: "Minimal", bpm: 120, rootOffset: 2,
        padVolume: -20, arpVolume: -10, melodyVolume: -60, kickVolume: -4, snareVolume: -12, hatVolume: -16,
        arpPattern: "up", rhythmPattern: 3, swing: 0,
        padHarmonicity: 1.0, padModIndex: 0.3, padAttack: 0.8, padRelease: 2.0,
        arpAttack: 0.005, arpDecay: 0.15, arpSustain: 0.1, arpRelease: 0.3,
        melAttack: 0.01, melDecay: 0.1, melSustain: 0.5, melRelease: 0.2),

    JammermanPreset(name: "Future Bass", bpm: 140, rootOffset: 10,
        padVolume: -10, arpVolume: -6, melodyVolume: -6, kickVolume: -4, snareVolume: -6, hatVolume: -14,
        arpPattern: "up-up-down", rhythmPattern: 4, swing: 15,
        padHarmonicity: 2.0, padModIndex: 3.0, padAttack: 0.1, padRelease: 1.0,
        arpAttack: 0.005, arpDecay: 0.15, arpSustain: 0.5, arpRelease: 0.3,
        melAttack: 0.01, melDecay: 0.1, melSustain: 0.5, melRelease: 0.25),
]
