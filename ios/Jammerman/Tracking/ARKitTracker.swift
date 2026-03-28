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
    func arKitTracker(_ tracker: ARKitTracker, didUpdateVisionLandmarks landmarks: VNFaceLandmarks2D, boundingBox: CGRect)
}

// MARK: - ARKit Tracker

class ARKitTracker: NSObject {
    weak var delegate: ARKitTrackerDelegate?

    // Tunable valence parameters (exposed for UI calibration)
    // Calibrated valence parameters
    var valenceNeutral: Float = 0.23
    var valenceScale: Float = 1.21
    var valenceOffset: Float = 0.5
    var frownWeight: Float = 2.0

    #if !targetEnvironment(simulator)
    private var arSession: ARSession?
    #endif

    // Hand tracking via Vision on ARFrame images
    private let handRequest = VNDetectHumanHandPoseRequest()
    private var handFrameCount = 0
    private var lastHandOpen: Bool?

    // Vision face landmarks for precise contour rendering (runs on ARFrame)
    #if !targetEnvironment(simulator)
    private let visionFaceRequest = VNDetectFaceLandmarksRequest()
    private var visionFrameCount = 0
    #endif

    // No frame retention — use arSession?.currentFrame when needed

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
        #if !targetEnvironment(simulator)
        // Create session in init so ARSCNView can bind to it immediately
        if ARKitTracker.isSupported {
            let s = ARSession()
            self.arSession = s
        }
        #endif
        super.init()
    }

    func start() {
        #if !targetEnvironment(simulator)
        guard let session = arSession else { return }
        session.delegate = self

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1

        if ARFaceTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        } else if ARFaceTrackingConfiguration.supportsFrameSemantics(.personSegmentation) {
            config.frameSemantics.insert(.personSegmentation)
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        print("[ARKit] Session started with face tracking")
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

        // Lip corner (smile): ARKit mouthSmile blend shapes
        // ARKit: 0 = neutral/resting, 0.3+ = smiling, 0.6+ = big smile
        // There's no negative — frowning barely changes mouthSmile
        // Also use mouthFrownLeft/Right for the negative side
        let smileL = (blendShapes[.mouthSmileLeft]?.floatValue) ?? 0
        let smileR = (blendShapes[.mouthSmileRight]?.floatValue) ?? 0
        let frownL = (blendShapes[.mouthFrownLeft]?.floatValue) ?? 0
        let frownR = (blendShapes[.mouthFrownRight]?.floatValue) ?? 0
        let avgSmile = (smileL + smileR) / 2
        let avgFrown = (frownL + frownR) / 2
        // Combine smile and frown using tunable parameters
        let rawValence = avgSmile - avgFrown * frownWeight
        let lipCorner = clamp((rawValence - valenceNeutral) * valenceScale + valenceOffset, lo: -0.1, hi: 1.1)

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

        // Face center: use ARFrame camera to project 3D nose position to screen
        var faceCenterX: Float = 0.5
        var faceCenterY: Float = 0.4
        #if !targetEnvironment(simulator)
        if let frame = arSession?.currentFrame {
            // Get the 3D world position of the face (nose tip = origin of face anchor)
            let worldPos = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            // Project to 2D using ARCamera
            let screenSize = UIScreen.main.bounds.size
            let projected = frame.camera.projectPoint(
                simd_float3(worldPos.x, worldPos.y, worldPos.z),
                orientation: .portrait,
                viewportSize: screenSize
            )
            // Convert to normalized 0..1
            faceCenterX = Float(projected.x / screenSize.width)
            faceCenterY = Float(projected.y / screenSize.height)
        }
        #endif

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
    // Vision face detection on ARFrame for precise contour landmarks
    private var isDetectingVisionFace = false
    private let visionQueue = DispatchQueue(label: "com.jammerman.visionface", qos: .userInitiated)

    private func detectVisionFace(in frame: ARFrame) {
        guard !isDetectingVisionFace else { return }
        isDetectingVisionFace = true

        // Copy pixel buffer to avoid retaining ARFrame
        let pixelBuffer = frame.capturedImage

        visionQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isDetectingVisionFace = false }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            let faceRequest = VNDetectFaceLandmarksRequest()
            try? handler.perform([faceRequest])

            guard let faceObs = faceRequest.results?.first,
                  let landmarks = faceObs.landmarks else { return }

            let bb = faceObs.boundingBox
            self.delegate?.arKitTracker(self, didUpdateVisionLandmarks: landmarks, boundingBox: bb)
        }
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

        // Vision face landmarks for precise contour rendering (every 3rd frame)
        visionFrameCount += 1
        if visionFrameCount % 3 == 0 {
            detectVisionFace(in: frame)
        }

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
