// Muze — Metal Visualizer SwiftUI Wrapper
// Transparent MTKView overlay on top of ARSCNView camera feed

import SwiftUI
import MetalKit

struct MetalVisualizerOverlay: UIViewRepresentable {
    let coordinator: TrackingCoordinator

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device")
        }
        print("[Metal] Creating MTKView with device: \(device.name)")

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false

        // Transparent overlay — camera shows through clear areas
        mtkView.isOpaque = false
        mtkView.layer.isOpaque = false
        mtkView.backgroundColor = .clear
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Pass touches through to SwiftUI buttons underneath
        mtkView.isUserInteractionEnabled = false

        // Needed for blending
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false

        // Create the renderer and set as delegate
        let renderer = MetalVisualizer(device: device, coordinator: coordinator)
        mtkView.delegate = renderer

        // Store renderer to prevent deallocation + expose for dev UI
        objc_setAssociatedObject(mtkView, "renderer", renderer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        coordinator.metalRenderer = renderer

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
