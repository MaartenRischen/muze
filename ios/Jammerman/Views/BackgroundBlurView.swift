// Jammerman — Background Blur
// Real-time iOS blur behind the person using UIVisualEffectView + segmentation mask
// PersonSegmenter kept for non-ARKit fallback

import SwiftUI
import Vision
import CoreImage
import UIKit

// MARK: - Segmented Blur Overlay (UIVisualEffectView masked by person segmentation)

struct SegmentedBlurOverlay: UIViewRepresentable {
    let blurMask: CGImage?  // pre-computed: background = white, person = black

    func makeUIView(context: Context) -> SegmentedBlurUIView {
        SegmentedBlurUIView()
    }

    func updateUIView(_ uiView: SegmentedBlurUIView, context: Context) {
        uiView.updateMask(blurMask)
    }
}

class SegmentedBlurUIView: UIView {
    private let blurView: UIVisualEffectView
    private let maskLayer = CALayer()

    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        super.init(frame: frame)

        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)

        blurView.layer.mask = maskLayer
        maskLayer.contentsGravity = .resizeAspectFill

        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        maskLayer.frame = bounds
    }

    func updateMask(_ cgImage: CGImage?) {
        guard let img = cgImage else {
            maskLayer.contents = nil
            return
        }
        // Mirror horizontally for front camera selfie view
        maskLayer.transform = CATransform3DMakeScale(-1, 1, 1)
        maskLayer.contents = img
    }
}

// MARK: - Person Segmenter (Vision-based, for non-ARKit fallback)

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

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            try? handler.perform([self.request])

            guard let result = self.request.results?.first else { return }
            let maskBuffer = result.pixelBuffer
            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            let inverted = maskCI.applyingFilter("CIColorInvert")
            let darkTint = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.55))
                .cropped(to: maskCI.extent)
            let darkBg = inverted.applyingFilter("CIMultiplyCompositing", parameters: [
                "inputBackgroundImage": darkTint
            ])
            let softened = darkBg.applyingGaussianBlur(sigma: 3).cropped(to: maskCI.extent)

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
