// Jammerman — Music Theory
// Ported from web/js/music.js per shared/SPEC.md

import Foundation

enum MusicTheory {

    /// Select scale based on lip corner (valence) or user-selected extra scale mode.
    static func selectScale(lipCorner: Float, extraScaleMode: String?) -> [Int] {
        if let mode = extraScaleMode {
            return Scale.extra[mode] ?? Scale.dorian
        }
        if lipCorner > 0.80 { return Scale.lydian }
        if lipCorner > 0.60 { return Scale.ionian }
        if lipCorner > 0.40 { return Scale.mixolydian }
        if lipCorner > 0.20 { return Scale.dorian }
        if lipCorner > 0.00 { return Scale.aeolian }
        return Scale.phrygian
    }

    /// Quantize a 0..1 value to a MIDI note within the given scale.
    static func quantize(value: Float, scale: [Int], root: Int, octaveRange: Int) -> Int {
        let total = scale.count * octaveRange
        let idx = max(0, min(total - 1, Int(round(Double(value) * Double(total - 1)))))
        return root + (idx / scale.count) * 12 + scale[idx % scale.count]
    }

    /// Convert MIDI note number to note name string (e.g. 60 -> "C4").
    static func midiToNote(_ midi: Int) -> String {
        let name = JammermanConfig.noteNames[midi % 12]
        let octave = midi / 12 - 1
        return "\(name)\(octave)"
    }

    /// Open 4-note pad voicing for given root, scale, and degree.
    static func getPadVoicing(root: Int, scale: [Int], degree: Int) -> [String] {
        let len = scale.count
        let d = degree % len
        let rootNote = root + scale[d]
        let third    = root + scale[(d + 2) % len]
        let fifth    = root + scale[(d + 4) % len]
        let seventh  = root + scale[(d + 6) % len]

        return [rootNote - 12, third, fifth, seventh].map { midiToNote($0) }
    }

    /// Arp chord tones across octaves.
    static func getArpNotes(scale: [Int], root: Int, degree: Int, octaveRange: Int) -> [String] {
        let len = scale.count
        let d = degree % len
        let chordTones = [
            scale[d],
            scale[(d + 2) % len],
            scale[(d + 4) % len],
            scale[(d + 6) % len]
        ]
        var notes: [String] = []
        for oct in 0..<octaveRange {
            for interval in chordTones {
                notes.append(midiToNote(root + oct * 12 + interval))
            }
        }
        return notes
    }

    /// Snap an arbitrary MIDI note to the closest note in the scale.
    static func snapToScale(midiNote: Int, scale: [Int], root: Int) -> Int {
        var bestNote = root
        var bestDist = 999
        for oct in -1...8 {
            for interval in scale {
                let candidate = root + oct * 12 + interval
                let dist = abs(candidate - midiNote)
                if dist < bestDist {
                    bestDist = dist
                    bestNote = candidate
                }
            }
        }
        return bestNote
    }

    /// Bjorklund's Euclidean rhythm algorithm.
    static func euclidean(pulses: Int, steps: Int) -> [Int] {
        if pulses >= steps { return Array(repeating: 1, count: steps) }
        if pulses <= 0 { return Array(repeating: 0, count: steps) }

        var counts = (0..<pulses).map { _ in [1] }
        var remainders = (0..<(steps - pulses)).map { _ in [0] }

        while remainders.count > 1 {
            var newCounts: [[Int]] = []
            var newRemainders: [[Int]] = []
            let minLen = min(counts.count, remainders.count)

            for i in 0..<minLen {
                newCounts.append(counts[i] + remainders[i])
            }
            if counts.count > minLen {
                newRemainders.append(contentsOf: counts[minLen...])
            }
            if remainders.count > minLen {
                newRemainders.append(contentsOf: remainders[minLen...])
            }
            counts = newCounts
            remainders = newRemainders
        }

        return (counts + remainders).flatMap { $0 }
    }
}
