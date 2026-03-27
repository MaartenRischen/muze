// Jammerman — Face & Hand Feature Extraction
// Ported from web/js/tracking.js per shared/SPEC.md
//
// This file contains the pure math for extracting musical features
// from face/hand landmarks. The landmark source (MediaPipe vs Apple Vision)
// is abstracted — callers provide normalized {x, y, z} landmark arrays.

import Foundation

struct Landmark {
    let x: Float
    let y: Float
    let z: Float
}

struct FaceFeatures {
    let mouthOpenness: Float   // 0..1
    let lipCorner: Float       // -1..1
    let browHeight: Float      // 0..1
    let eyeOpenness: Float     // 0..1
    let mouthWidth: Float      // 0..1
    let headPitch: Float       // radians
    let headYaw: Float         // radians
    let headRoll: Float        // radians
}

struct HandFeatures {
    let handPresent: Bool
    let handX: Float           // 0..1 (mirrored)
    let handY: Float           // 0..1
    let handOpen: Bool
}

// MARK: - Face Feature Extraction

enum FaceExtractor {
    // MediaPipe landmark indices (see SPEC.md §10)
    // iOS Vision framework will need a mapping layer
    enum LM {
        static let upperLip = 13
        static let lowerLip = 14
        static let leftMouth = 61
        static let rightMouth = 291
        static let rEyeTop = 159
        static let rEyeBot = 145
        static let lEyeTop = 386
        static let lEyeBot = 374
        static let rBrow = 105
        static let lBrow = 334
        static let noseTip = 1
        static let forehead = 10
        static let chin = 152
        static let lEar = 234
        static let rEar = 454
    }

    static func extract(landmarks: [Landmark]) -> FaceFeatures? {
        let C = JammermanConfig.self
        let faceHeight = dist3d(landmarks[LM.forehead], landmarks[LM.chin])
        guard faceHeight > 0.001 else { return nil }

        // Mouth openness
        let mouthOpen = clamp01(remap(
            dist3d(landmarks[LM.upperLip], landmarks[LM.lowerLip]) / faceHeight,
            min: C.mouthOpenMin, max: C.mouthOpenMax
        ))

        // Lip corner (smile/frown)
        let midMouthY = (landmarks[LM.upperLip].y + landmarks[LM.lowerLip].y) / 2
        let lipCorner = clamp(remap(
            ((midMouthY - landmarks[LM.leftMouth].y) + (midMouthY - landmarks[LM.rightMouth].y)) / 2 / faceHeight,
            min: C.lipSmileMin, max: C.lipSmileMax
        ), lo: -1, hi: 1)

        // Brow height
        let browNorm = (
            abs(landmarks[LM.rBrow].y - landmarks[LM.rEyeTop].y) +
            abs(landmarks[LM.lBrow].y - landmarks[LM.lEyeTop].y)
        ) / 2 / faceHeight
        let browHeight = clamp01(remap(browNorm, min: C.browMin, max: C.browMax))

        // Eye openness
        let eyeOpenness = clamp01(remap(
            (dist3d(landmarks[LM.rEyeTop], landmarks[LM.rEyeBot]) +
             dist3d(landmarks[LM.lEyeTop], landmarks[LM.lEyeBot])) / 2 / faceHeight,
            min: C.eyeOpenMin, max: C.eyeOpenMax
        ))

        // Mouth width
        let mouthWidth = clamp01(remap(
            dist2d(landmarks[LM.leftMouth], landmarks[LM.rightMouth]) / faceHeight,
            min: C.mouthWidthMin, max: C.mouthWidthMax
        ))

        // Head rotation
        let headYaw = atan2(
            dist2d(landmarks[LM.noseTip], landmarks[LM.lEar]) -
            dist2d(landmarks[LM.noseTip], landmarks[LM.rEar]),
            faceHeight
        )
        let headPitch = (landmarks[LM.noseTip].y -
            (landmarks[LM.forehead].y + landmarks[LM.chin].y) / 2) / faceHeight * .pi * 0.5
        let headRoll = atan2(
            landmarks[LM.lEar].y - landmarks[LM.rEar].y,
            landmarks[LM.lEar].x - landmarks[LM.rEar].x
        )

        return FaceFeatures(
            mouthOpenness: mouthOpen, lipCorner: lipCorner,
            browHeight: browHeight, eyeOpenness: eyeOpenness,
            mouthWidth: mouthWidth, headPitch: headPitch,
            headYaw: headYaw, headRoll: headRoll
        )
    }
}

// MARK: - Hand Feature Extraction

class HandExtractor {
    private var lastOpen: Bool?

    func extract(landmarks: [[Landmark]]) -> HandFeatures {
        guard let lm = landmarks.first, !lm.isEmpty else {
            return HandFeatures(handPresent: false, handX: 0.5, handY: 0.5, handOpen: true)
        }

        let handX = 1 - (lm[0].x + lm[9].x) / 2
        let handY = (lm[0].y + lm[9].y) / 2
        let palmSize = dist3d(lm[0], lm[9])

        let avgFingerDist = (
            dist3d(lm[8], lm[0]) + dist3d(lm[12], lm[0]) +
            dist3d(lm[16], lm[0]) + dist3d(lm[20], lm[0])
        ) / 4

        let ratio = avgFingerDist / palmSize

        // Hysteresis
        let open: Bool
        if let prev = lastOpen {
            open = prev ? (ratio > 1.55) : (ratio > 1.85)
        } else {
            open = ratio > 1.7
        }
        lastOpen = open

        return HandFeatures(handPresent: true, handX: handX, handY: handY, handOpen: open)
    }
}

// MARK: - Math helpers

private func dist3d(_ a: Landmark, _ b: Landmark) -> Float {
    sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2) + pow(a.z - b.z, 2))
}

private func dist2d(_ a: Landmark, _ b: Landmark) -> Float {
    sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
}

private func remap(_ v: Float, min: Float, max: Float) -> Float {
    (v - min) / (max - min)
}

private func clamp01(_ v: Float) -> Float {
    Swift.max(0, Swift.min(1, v))
}

private func clamp(_ v: Float, lo: Float, hi: Float) -> Float {
    Swift.max(lo, Swift.min(hi, v))
}
