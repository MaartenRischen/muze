// Jammerman — Face Tracker
// Apple Vision framework face landmark detection
// Maps Vision landmarks → our Landmark struct → FaceFeatures extraction

import Vision
import CoreImage

class FaceTracker {
    private let faceRequest: VNDetectFaceLandmarksRequest
    private let sequenceHandler = VNSequenceRequestHandler()

    // Stagger: only run every other frame
    private var frameCount = 0

    init() {
        faceRequest = VNDetectFaceLandmarksRequest()
        faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
    }

    /// Result of face detection: features + raw data for visualizer
    struct DetectionResult {
        let features: FaceFeatures
        let landmarks: VNFaceLandmarks2D
        let boundingBox: CGRect
    }

    /// Detect face landmarks from a camera frame. Returns DetectionResult or nil.
    func detect(sampleBuffer: CMSampleBuffer) -> DetectionResult? {
        frameCount += 1
        guard frameCount % 2 == 0 else { return nil } // stagger: every other frame

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // Run face detection
        let detectRequest = VNDetectFaceRectanglesRequest()
        try? sequenceHandler.perform([detectRequest, faceRequest], on: pixelBuffer, orientation: .up)

        guard let faceObs = faceRequest.results?.first,
              let landmarks = faceObs.landmarks else {
            return nil
        }

        // Convert Vision landmarks to our normalized Landmark format
        let boundingBox = faceObs.boundingBox
        let allLandmarks = extractLandmarks(from: landmarks, boundingBox: boundingBox)

        guard allLandmarks.count > 0 else { return nil }

        guard let features = extractFeatures(landmarks: landmarks, boundingBox: boundingBox) else {
            return nil
        }

        return DetectionResult(features: features, landmarks: landmarks, boundingBox: boundingBox)
    }

    // MARK: - Feature Extraction (adapted for Apple Vision landmark model)

    private func extractFeatures(landmarks: VNFaceLandmarks2D, boundingBox: CGRect) -> FaceFeatures? {
        // Apple Vision provides landmark groups, not indexed points like MediaPipe
        // We extract the same semantic features using the available groups

        guard let outerLips = landmarks.outerLips,
              let innerLips = landmarks.innerLips,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let leftEyebrow = landmarks.leftEyebrow,
              let rightEyebrow = landmarks.rightEyebrow,
              let nose = landmarks.nose,
              let faceContour = landmarks.faceContour else {
            return nil
        }

        let bw = Float(boundingBox.width)
        let bh = Float(boundingBox.height)

        // Mouth openness: distance between inner lip top and bottom, normalized by face height
        let innerLipPts = innerLips.normalizedPoints
        if innerLipPts.count < 6 { return nil }
        let topLip = innerLipPts[0]     // top center
        let bottomLip = innerLipPts[innerLipPts.count / 2] // bottom center
        let mouthOpenDist = abs(Float(topLip.y - bottomLip.y))
        let mouthOpenness = clamp01(remap(mouthOpenDist, min: 0.02, max: 0.15))

        // Lip corner (smile): outer lip corners relative to center
        let outerPts = outerLips.normalizedPoints
        if outerPts.count < 6 { return nil }
        let leftCorner = outerPts[0]
        let rightCorner = outerPts[outerPts.count / 2]
        let lipCenter = Float(topLip.y + bottomLip.y) / 2
        // Vision Y is bottom-up, so corners ABOVE center = positive Y = smile
        let leftLift = Float(leftCorner.y) - lipCenter
        let rightLift = Float(rightCorner.y) - lipCenter
        let avgLift = (leftLift + rightLift) / 2
        // Frown signal is weaker in Vision — use asymmetric range
        // Very small min = easy to reach negative (frown/phrygian)
        let lipCorner = clamp(remap(avgLift, min: -0.012, max: 0.045), lo: -1, hi: 1)

        // Brow height: distance from eyebrow to eye top
        let leftBrowPts = leftEyebrow.normalizedPoints
        let rightBrowPts = rightEyebrow.normalizedPoints
        let leftEyePts = leftEye.normalizedPoints
        let rightEyePts = rightEye.normalizedPoints

        guard leftBrowPts.count > 2, rightBrowPts.count > 2,
              leftEyePts.count > 2, rightEyePts.count > 2 else { return nil }

        let leftBrowDist = abs(Float(leftBrowPts[leftBrowPts.count / 2].y - leftEyePts[0].y))
        let rightBrowDist = abs(Float(rightBrowPts[rightBrowPts.count / 2].y - rightEyePts[0].y))
        let avgBrowDist = (leftBrowDist + rightBrowDist) / 2
        let browHeight = clamp01(remap(avgBrowDist, min: 0.04, max: 0.12))

        // Eye openness
        let leftEyeHeight = eyeHeight(leftEyePts)
        let rightEyeHeight = eyeHeight(rightEyePts)
        let avgEyeHeight = (leftEyeHeight + rightEyeHeight) / 2
        let eyeOpenness = clamp01(remap(avgEyeHeight, min: 0.015, max: 0.06))

        // Mouth width
        let mouthWidth = abs(Float(leftCorner.x - rightCorner.x))
        let mouthWidthNorm = clamp01(remap(mouthWidth, min: 0.2, max: 0.5))

        // Head rotation — estimated from face geometry
        let contourPts = faceContour.normalizedPoints
        let nosePts = nose.normalizedPoints
        let headYaw: Float
        let headPitch: Float
        let headRoll: Float

        if contourPts.count > 4, nosePts.count > 2 {
            let left = contourPts[0]
            let right = contourPts[contourPts.count - 1]

            // Yaw: nose position relative to face center (left/right asymmetry)
            let faceCenter = Float((left.x + right.x) / 2)
            let noseX = Float(nosePts[nosePts.count / 2].x)
            headYaw = (noseX - faceCenter) * 4.0 // scale to ~radians

            // Pitch: nose tip vertical position relative to face center
            let faceTop = contourPts.map { Float($0.y) }.max() ?? 0.5
            let faceBot = contourPts.map { Float($0.y) }.min() ?? 0.5
            let faceMidY = (faceTop + faceBot) / 2
            let noseY = Float(nosePts[nosePts.count / 2].y)
            headPitch = (noseY - faceMidY) / max(faceTop - faceBot, 0.01) * .pi * 0.3

            // Roll: ear-to-ear tilt
            headRoll = atan2(Float(left.y - right.y), Float(left.x - right.x))
        } else {
            headYaw = 0; headPitch = 0; headRoll = 0
        }

        // Face center from bounding box (Vision coords: origin bottom-left)
        let fcx = Float(boundingBox.midX)
        let fcy = 1 - Float(boundingBox.midY) // flip Y to top-left origin

        return FaceFeatures(
            mouthOpenness: mouthOpenness,
            lipCorner: lipCorner,
            browHeight: browHeight,
            eyeOpenness: eyeOpenness,
            mouthWidth: mouthWidthNorm,
            headPitch: headPitch,
            headYaw: headYaw,
            headRoll: headRoll,
            faceCenterX: fcx,
            faceCenterY: fcy
        )
    }

    private func eyeHeight(_ points: [CGPoint]) -> Float {
        guard points.count >= 4 else { return 0 }
        // Top of eye vs bottom of eye
        let top = points[points.count / 4]
        let bottom = points[3 * points.count / 4]
        return abs(Float(top.y - bottom.y))
    }

    private func extractLandmarks(from landmarks: VNFaceLandmarks2D, boundingBox: CGRect) -> [Landmark] {
        guard let allPoints = landmarks.allPoints else { return [] }
        return allPoints.normalizedPoints.map { pt in
            Landmark(
                x: Float(boundingBox.origin.x + pt.x * boundingBox.width),
                y: Float(boundingBox.origin.y + pt.y * boundingBox.height),
                z: 0
            )
        }
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
}
