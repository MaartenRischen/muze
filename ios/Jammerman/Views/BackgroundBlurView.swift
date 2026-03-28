// Jammerman — Background Blur
// Uses Vision PersonSegmentationRequest to darken non-person areas
// Processing on background thread

import SwiftUI
import Vision
import CoreImage

class PersonSegmenter: ObservableObject {
    private let request = VNGeneratePersonSegmentationRequest()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let processingQueue = DispatchQueue(label: "com.jammerman.segmentation", qos: .userInitiated)
    private var isProcessing = false

    @Published var maskImage: UIImage?
    var isEnabled = true

    init() {
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isEnabled, !isProcessing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right) // .right for front camera in portrait
            try? handler.perform([self.request])

            guard let result = self.request.results?.first else { return }
            let maskBuffer = result.pixelBuffer

            // Convert mask to UIImage with dark tint for background
            let maskCI = CIImage(cvPixelBuffer: maskBuffer)

            // Invert mask (person = black/transparent, background = white/dark)
            let inverted = maskCI.applyingFilter("CIColorInvert")

            // Tint to dark semi-transparent
            let darkTint = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55))
                .cropped(to: maskCI.extent)

            // Multiply inverted mask with dark tint
            let darkBg = inverted.applyingFilter("CIMultiplyCompositing", parameters: [
                "inputBackgroundImage": darkTint
            ])

            // Soften edges
            let softened = darkBg
                .applyingGaussianBlur(sigma: 3)
                .cropped(to: maskCI.extent)

            if let cgImage = self.ciContext.createCGImage(softened, from: maskCI.extent) {
                let img = UIImage(cgImage: cgImage, scale: 1, orientation: .upMirrored)
                DispatchQueue.main.async {
                    self.maskImage = img
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
