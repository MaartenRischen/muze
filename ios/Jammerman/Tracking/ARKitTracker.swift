// Jammerman — ARKit Face Tracker
// Uses ARSession with ARFaceTrackingConfiguration for high-quality face tracking
// Falls back to Vision-based tracking if ARKit face tracking is not supported
// All ARKit code guarded with #if !targetEnvironment(simulator)

import Foundation
import Vision
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
    func arKitTracker(_ tracker: ARKitTracker, didUpdateSegmentation mask: CGImage)
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
    private var handFrameCount = 0
    private var lastHandOpen: Bool?
    private var isDetectingHand = false
    private let handQueue = DispatchQueue(label: "com.jammerman.hand", qos: .userInitiated)

    // Vision face landmarks for precise contour rendering (runs on ARFrame)
    #if !targetEnvironment(simulator)
    private let visionFaceRequest = VNDetectFaceLandmarksRequest()
    private var visionFrameCount = 0
    #endif

    // Cached camera for face projection (updated each frame, avoids accessing currentFrame)
    #if !targetEnvironment(simulator)
    private var cachedCamera: ARCamera?
    #endif

    // Lightweight person segmentation via Vision (async, as fast as possible)
    private var isSegmenting = false
    private let segQueue = DispatchQueue(label: "com.jammerman.seg", qos: .userInitiated)

    /// Whether ARKit face tracking is available on this device
    static var isSupported: Bool {
        #if !targetEnvironment(simulator)
        return ARFaceTrackingConfiguration.isSupported
        #else
        return false
        #endif
    }

    override init() {
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

        // Person segmentation disabled — even .personSegmentation kills perf on this device

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

        // Face center: project 3D nose position to screen using cached camera
        // (cachedCamera is updated each frame in didUpdate, avoids accessing currentFrame)
        var faceCenterX: Float = 0.5
        var faceCenterY: Float = 0.4
        if let camera = cachedCamera {
            let worldPos = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let screenSize = UIScreen.main.bounds.size
            let projected = camera.projectPoint(
                worldPos,
                orientation: .portrait,
                viewportSize: screenSize
            )
            faceCenterX = Float(projected.x / screenSize.width)
            faceCenterY = Float(projected.y / screenSize.height)
        }

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
        guard handFrameCount % 4 == 0 else { return }  // every 4th frame (15fps, was every 2nd)
        guard !isDetectingHand else { return }
        isDetectingHand = true

        let pixelBuffer = frame.capturedImage

        handQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isDetectingHand = false }

            let request = VNDetectHumanHandPoseRequest()
            request.maximumHandCount = 1
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            do { try handler.perform([request]) } catch { return }

            guard let handObs = request.results?.first else {
                self.delegate?.arKitTracker(self, didUpdateHand: HandFeatures(
                    handPresent: false, handX: 0.5, handY: 0.5, handOpen: true))
                return
            }

            if let features = self.extractHandFeatures(from: handObs) {
                self.delegate?.arKitTracker(self, didUpdateHand: features)
            }
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
    // MARK: - Person Segmentation (Vision, low priority, no pixel buffer copy)

    #if !targetEnvironment(simulator)
    private func detectSegmentation(in frame: ARFrame) {
        guard !isSegmenting else { return }  // process as fast as possible, guard prevents stacking
        isSegmenting = true

        // Pass capturedImage directly — no copy (same approach as hand detection)
        let pixelBuffer = frame.capturedImage

        segQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isSegmenting = false }

            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .fast
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            do { try handler.perform([request]) } catch { return }

            guard let result = request.results?.first else { return }
            let maskBuf = result.pixelBuffer

            // Convert mask to CGImage via byte copy (tiny buffer, ~256x192)
            CVPixelBufferLockBaseAddress(maskBuf, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(maskBuf, .readOnly) }

            let mw = CVPixelBufferGetWidth(maskBuf)
            let mh = CVPixelBufferGetHeight(maskBuf)
            let bpr = CVPixelBufferGetBytesPerRow(maskBuf)
            guard let base = CVPixelBufferGetBaseAddress(maskBuf) else { return }

            let data = Data(bytes: base, count: bpr * mh)
            guard let provider = CGDataProvider(data: data as CFData) else { return }
            let cs = CGColorSpaceCreateDeviceGray()
            guard let img = CGImage(width: mw, height: mh, bitsPerComponent: 8, bitsPerPixel: 8,
                                    bytesPerRow: bpr, space: cs,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: true, intent: .defaultIntent) else { return }

            DispatchQueue.main.async { [weak self] in
                self?.delegate?.arKitTracker(self!, didUpdateSegmentation: img)
            }
        }
    }
    #endif

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
            do {
                try handler.perform([faceRequest])
            } catch {
                // Vision request failed silently
            }

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
        autoreleasepool {
            // Cache camera for face projection
            cachedCamera = frame.camera

            // Hand detection — async, every 4th frame (~15fps)
            detectHand(in: frame)

            // Person segmentation — async, every 15th frame (~2fps), .utility priority
            detectSegmentation(in: frame)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        autoreleasepool {
            guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
                return
            }

            let features = extractFaceFeatures(from: faceAnchor)

            // Extract 3D vertices from face geometry — copy to value types
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
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        if anchors.contains(where: { $0 is ARFaceAnchor }) {
            delegate?.arKitTracker(self, didLoseFace: true)
        }
    }
}
#endif
