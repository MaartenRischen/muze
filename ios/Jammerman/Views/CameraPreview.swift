// Jammerman — Camera Preview
// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
// Also provides ARSCNView-based preview for ARKit mode

import SwiftUI
import AVFoundation

#if !targetEnvironment(simulator)
import ARKit
#endif

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoRotationAngle = 90
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - ARKit Camera Preview (shows AR camera feed via ARSCNView)

#if !targetEnvironment(simulator)
struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let scnView = ARSCNView()
        scnView.session = session
        scnView.automaticallyUpdatesLighting = false
        // Empty scene — just shows the camera feed
        scnView.scene = SCNScene()
        // Do NOT set scene.background.contents = .clear — that hides the camera!
        return scnView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // No-op: ARSession drives the preview
    }
}
#endif
