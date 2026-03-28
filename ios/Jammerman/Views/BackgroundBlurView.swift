// Jammerman — Background Blur
// Uses Vision PersonSegmentationRequest to blur non-person areas
// Processing happens on background thread to avoid blocking main

import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

class PersonSegmenter {
    private let request = VNGeneratePersonSegmentationRequest()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let processingQueue = DispatchQueue(label: "com.jammerman.segmentation", qos: .userInitiated)

    @Published var blurredImage: UIImage?
    var isEnabled = true

    init() {
        request.qualityLevel = .balanced // fast enough for real-time
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isEnabled else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        processingQueue.async { [weak self] in
            guard let self else { return }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try? handler.perform([self.request])

            guard let result = self.request.results?.first else { return }
            let maskBuffer = result.pixelBuffer

            // Create dark overlay blended with mask
            let maskImage = CIImage(cvPixelBuffer: maskBuffer)
            let cameraImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Scale mask to match camera
            let scaleX = cameraImage.extent.width / maskImage.extent.width
            let scaleY = cameraImage.extent.height / maskImage.extent.height
            let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            // Blur the mask edges for smooth transition
            let softMask = scaledMask
                .applyingGaussianBlur(sigma: 8)
                .cropped(to: cameraImage.extent)

            // Dark semi-transparent overlay for background
            let darkOverlay = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.5))
                .cropped(to: cameraImage.extent)

            // Clear for person area
            let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: cameraImage.extent)

            // Blend: person = clear, background = dark
            let blended = clear.applyingFilter("CIBlendWithMask", parameters: [
                "inputBackgroundImage": darkOverlay,
                "inputMaskImage": softMask
            ])

            if let cgImage = self.ciContext.createCGImage(blended, from: cameraImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self.blurredImage = uiImage
                }
            }
        }
    }
}

struct BackgroundBlurOverlay: View {
    let image: UIImage?

    var body: some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
