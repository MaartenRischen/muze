// Jammerman — ARKit Face Tracker
// Uses ARSession with ARFaceTrackingConfiguration for high-quality face tracking
// Falls back to Vision-based tracking if ARKit face tracking is not supported
// All ARKit code guarded with #if !targetEnvironment(simulator)

import Foundation
import Vision
import CoreMedia
import simd

#if !targetEnvironment(simulator)
import ARKit
#endif

// MARK: - Delegate Protocol

protocol ARKitTrackerDelegate: AnyObject {
    func arKitTracker(_ tracker: ARKitTracker, didUpdateFace features: FaceFeatures,
                      vertices: [simd_float3]?, triangleIndices: [Int16]?)
    func arKitTracker(_ tracker: ARKitTracker, didUpdateHand hand: HandFeatures)
    func arKitTracker(_ tracker: ARKitTracker, didLoseFace: Bool)
    func arKitTracker(_ tracker: ARKitTracker, didUpdateSegmentation buffer: CVPixelBuffer?)
}

// MARK: - ARKit Tracker

class ARKitTracker: NSObject {
    weak var delegate: ARKitTrackerDelegate?

    #if !targetEnvironment(simulator)
    private var arSession: ARSession?
    #endif

    // Hand tracking via Vision on ARFrame images
    private let handRequest = VNDetectHumanHandPoseRequest()
    private var handFrameCount = 0
    private var lastHandOpen: Bool?

    /// Whether ARKit face tracking is available on this device
    static var isSupported: Bool {
        #if !targetEnvironment(simulator)
        return ARFaceTrackingConfiguration.isSupported
        #else
        return false
        #endif
    }

    override init() {
        handRequest.maximumHandCount = 1
        super.init()
    }

    func start() {
        #if !targetEnvironment(simulator)
        guard ARKitTracker.isSupported else { return }

        let session = ARSession()
        session.delegate = self
        self.arSession = session

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1

        // Enable person segmentation with depth if available
        if ARFaceTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        } else if ARFaceTrackingConfiguration.supportsFrameSemantics(.personSegmentation) {
            config.frameSemantics.insert(.personSegmentation)
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        arSession?.pause()
        arSession = nil
        #endif
    }

    #if !targetEnvironment(simulator)
    /// The AR session (exposed for ARSCNView)
    var session: ARSession? { arSession }
    #endif

    // MARK: - Blend Shape Extraction

    #if !targetEnvironment(simulator)
    private func extractFaceFeatures(from anchor: ARFaceAnchor) -> FaceFeatures {
        let blendShapes = anchor.blendShapes

        // Mouth openness: jawOpen is direct 0..1
        let jawOpen = (blendShapes[.jawOpen]?.floatValue) ?? 0
        let mouthOpenness = clamp01(jawOpen)

        // Lip corner (smile): average of left+right smile, remap from 0..~0.7 to -1..1
        // Neutral smile is around 0.15
        let smileL = (blendShapes[.mouthSmileLeft]?.floatValue) ?? 0
        let smileR = (blendShapes[.mouthSmileRight]?.floatValue) ?? 0
        let avgSmile = (smileL + smileR) / 2
        // Remap: 0.15 = neutral (0), 0 = -1 (frown), 0.7 = +1 (smile)
        let lipCorner: Float
        if avgSmile < 0.15 {
            lipCorner = clamp((avgSmile - 0.15) / 0.15, lo: -1, hi: 0) // frown range
        } else {
            lipCorner = clamp((avgSmile - 0.15) / 0.55, lo: 0, hi: 1) // smile range
        }

        // Brow height: browInnerUp 0..1
        let browInnerUp = (blendShapes[.browInnerUp]?.floatValue) ?? 0
        let browHeight = clamp01(browInnerUp)

        // Eye openness: invert blink (1 = open, 0 = closed)
        let blinkL = (blendShapes[.eyeBlinkLeft]?.floatValue) ?? 0
        let blinkR = (blendShapes[.eyeBlinkRight]?.floatValue) ?? 0
        let eyeOpenness = clamp01(1 - (blinkL + blinkR) / 2)

        // Mouth width: invert pucker (pucker = narrow, so invert for width)
        let pucker = (blendShapes[.mouthPucker]?.floatValue) ?? 0
        let mouthWidth = clamp01(1 - pucker)

        // Head pose from transform matrix
        let transform = anchor.transform
        // Pitch: rotation around X axis — asin of column 2 row 1 (m21)
        let pitch = asin(-transform.columns.2.y)
        // Yaw: rotation around Y axis — atan2 of column 2 elements
        let yaw = atan2(transform.columns.2.x, transform.columns.2.z)
        // Roll: rotation around Z axis — atan2 of column 0 and 1 Y components
        let roll = atan2(transform.columns.0.y, transform.columns.1.y)

        // Face center from transform translation (in camera/AR coordinates)
        // ARKit provides position in meters relative to camera
        // Convert to normalized 0..1 screen coordinates
        let tx = transform.columns.3.x
        let ty = transform.columns.3.y
        // ARKit X: left=-,right=+ ; Y: down=-,up=+
        // Map to normalized: center is 0.5, typical range ~-0.15..0.15 meters
        let faceCenterX = clamp01(0.5 + tx * 2.5) // scale meters to 0..1
        let faceCenterY = clamp01(0.5 - ty * 2.5) // flip Y, scale

        return FaceFeatures(
            mouthOpenness: mouthOpenness,
            lipCorner: lipCorner,
            browHeight: browHeight,
            eyeOpenness: eyeOpenness,
            mouthWidth: mouthWidth,
            headPitch: pitch,
            headYaw: yaw,
            headRoll: roll,
            faceCenterX: faceCenterX,
            faceCenterY: faceCenterY
        )
    }
    #endif

    // MARK: - Hand Detection on ARFrame

    #if !targetEnvironment(simulator)
    private func detectHand(in frame: ARFrame) {
        handFrameCount += 1
        guard handFrameCount % 2 == 1 else { return } // stagger: odd frames

        let pixelBuffer = frame.capturedImage
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)

        do {
            try handler.perform([handRequest])
        } catch {
            return
        }

        guard let handObs = handRequest.results?.first else {
            delegate?.arKitTracker(self, didUpdateHand: HandFeatures(
                handPresent: false, handX: 0.5, handY: 0.5, handOpen: true))
            return
        }

        if let features = extractHandFeatures(from: handObs) {
            delegate?.arKitTracker(self, didUpdateHand: features)
        }
    }

    private func extractHandFeatures(from observation: VNHumanHandPoseObservation) -> HandFeatures? {
        guard let wrist = try? observation.recognizedPoint(.wrist),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let middleMCP = try? observation.recognizedPoint(.middleMCP),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let littleTip = try? observation.recognizedPoint(.littleTip) else {
            return nil
        }

        guard wrist.confidence > 0.3, middleMCP.confidence > 0.3 else { return nil }

        // Hand position — mirrored for front camera
        let handX = Float((wrist.location.x + middleMCP.location.x) / 2)
        let handY = Float((wrist.location.y + middleMCP.location.y) / 2)

        let palmSize = dist(wrist.location, middleMCP.location)
        guard palmSize > 0.01 else { return nil }

        let avgFingerDist = (
            dist(indexTip.location, wrist.location) +
            dist(middleTip.location, wrist.location) +
            dist(ringTip.location, wrist.location) +
            dist(littleTip.location, wrist.location)
        ) / 4

        let ratio = avgFingerDist / palmSize

        // Hysteresis
        let open: Bool
        if let prev = lastHandOpen {
            open = prev ? (ratio > 1.55) : (ratio > 1.85)
        } else {
            open = ratio > 1.7
        }
        lastHandOpen = open

        return HandFeatures(
            handPresent: true,
            handX: handX,
            handY: 1 - handY, // flip Y
            handOpen: open
        )
    }
    #endif

    // MARK: - Helpers

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Float {
        Float(sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)))
    }

    private func clamp01(_ v: Float) -> Float {
        Swift.max(0, Swift.min(1, v))
    }

    private func clamp(_ v: Float, lo: Float, hi: Float) -> Float {
        Swift.max(lo, Swift.min(hi, v))
    }
}

// MARK: - ARSessionDelegate

#if !targetEnvironment(simulator)
extension ARKitTracker: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Hand detection on every frame (internally staggered)
        detectHand(in: frame)

        // Forward segmentation buffer if available
        if let segBuffer = frame.segmentationBuffer {
            delegate?.arKitTracker(self, didUpdateSegmentation: segBuffer)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            return
        }

        let features = extractFaceFeatures(from: faceAnchor)

        // Extract 3D vertices from face geometry
        let geometry = faceAnchor.geometry
        let vertexCount = geometry.vertices.count
        var vertices: [simd_float3] = []
        vertices.reserveCapacity(vertexCount)
        for i in 0..<vertexCount {
            vertices.append(geometry.vertices[i])
        }

        let indexCount = geometry.triangleCount * 3
        var triangleIndices: [Int16] = []
        triangleIndices.reserveCapacity(indexCount)
        for i in 0..<indexCount {
            triangleIndices.append(geometry.triangleIndices[i])
        }

        delegate?.arKitTracker(self, didUpdateFace: features, vertices: vertices.isEmpty ? nil : vertices, triangleIndices: triangleIndices.isEmpty ? nil : triangleIndices)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        if anchors.contains(where: { $0 is ARFaceAnchor }) {
            delegate?.arKitTracker(self, didLoseFace: true)
        }
    }
}
#endif
