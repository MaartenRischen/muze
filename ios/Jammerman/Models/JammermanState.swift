// Jammerman — Observable State
// Mirrors web's MUZE.State per shared/SPEC.md

import SwiftUI
import Vision

@Observable
class JammermanState {
    // Face features
    var mouthOpenness: Float = 0
    var lipCorner: Float = 0
    var browHeight: Float = 0
    var eyeOpenness: Float = 0.5
    var mouthWidth: Float = 0
    var headPitch: Float = 0
    var headYaw: Float = 0
    var headRoll: Float = 0
    var faceDetected: Bool = false

    // Face position (normalized 0..1, for visualizer)
    var faceCenterX: Float = 0.5
    var faceCenterY: Float = 0.35

    // Raw Vision landmarks for visualizer face mesh drawing
    // Stores the VNFaceLandmarks2D and bounding box from the latest detection
    var rawLandmarks: VNFaceLandmarks2D?
    var faceBoundingBox: CGRect = .zero

    // Hand features
    var handPresent: Bool = false
    var handY: Float = 0.5
    var handX: Float = 0.5
    var handOpen: Bool = true

    // Music state
    var currentScale: [Int] = Scale.dorian
    var melodyNote: Int? = nil
    var chordIndex: Int = 0
    var currentModeName: String = "dorian"
    var rootOffset: Int = 0
    var extraScaleMode: String? = nil

    // Transport
    var bpm: Int = 85
    var swing: Int = 0

    // Toggles
    var autoRhythm: Bool = false
    var modeFrozen: Bool = false
    var portamentoMode: Bool = false
    var audioReady: Bool = false

    // Arp settings
    var arpPatternIdx: Int = 0
    var arpNoteValueIdx: Int = 1
    var arp2PatternIdx: Int = 2
    var arp2NoteValueIdx: Int = 3

    // Preset
    var presetIdx: Int = 0
    var latencyMode: String = "balanced"

    // Computed
    var effectiveRoot: Int { JammermanConfig.rootNote + rootOffset }
}
