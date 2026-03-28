// Jammerman — Hand Tracker
// Apple Vision framework hand pose detection
// Maps Vision hand joints → HandFeatures

import Vision

class HandTracker {
    private let handRequest: VNDetectHumanHandPoseRequest
    private let sequenceHandler = VNSequenceRequestHandler()

    // Stagger: run on odd frames (face runs on even)
    private var frameCount = 0
    private var lastOpen: Bool?

    init() {
        handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 1
    }

    /// Detect hand pose from a camera frame. Returns HandFeatures or nil.
    func detect(sampleBuffer: CMSampleBuffer) -> HandFeatures? {
        frameCount += 1
        guard frameCount % 2 == 1 else { return nil } // stagger: odd frames

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // .leftMirrored for front camera in portrait mode
        try? sequenceHandler.perform([handRequest], on: pixelBuffer, orientation: .leftMirrored)

        guard let handObs = handRequest.results?.first else {
            return HandFeatures(handPresent: false, handX: 0.5, handY: 0.5, handOpen: true)
        }

        return extractFeatures(from: handObs)
    }

    private func extractFeatures(from observation: VNHumanHandPoseObservation) -> HandFeatures? {
        guard let wrist = try? observation.recognizedPoint(.wrist),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let middleMCP = try? observation.recognizedPoint(.middleMCP),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let littleTip = try? observation.recognizedPoint(.littleTip) else {
            return nil
        }

        // Only use high-confidence detections
        guard wrist.confidence > 0.3, middleMCP.confidence > 0.3 else { return nil }

        // Hand position (center between wrist and middle MCP)
        // No mirror — camera isVideoMirrored handles it
        let handX = Float((wrist.location.x + middleMCP.location.x) / 2)
        let handY = Float((wrist.location.y + middleMCP.location.y) / 2)

        // Palm size
        let palmSize = dist(wrist.location, middleMCP.location)
        guard palmSize > 0.01 else { return nil }

        // Average finger distance from wrist
        let avgFingerDist = (
            dist(indexTip.location, wrist.location) +
            dist(middleTip.location, wrist.location) +
            dist(ringTip.location, wrist.location) +
            dist(littleTip.location, wrist.location)
        ) / 4

        let ratio = avgFingerDist / palmSize

        // Hysteresis (same as web version)
        let open: Bool
        if let prev = lastOpen {
            open = prev ? (ratio > 1.55) : (ratio > 1.85)
        } else {
            open = ratio > 1.7
        }
        lastOpen = open

        return HandFeatures(
            handPresent: true,
            handX: handX,
            handY: 1 - handY, // flip Y (Vision has origin at bottom-left)
            handOpen: open
        )
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Float {
        Float(sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)))
    }
}
