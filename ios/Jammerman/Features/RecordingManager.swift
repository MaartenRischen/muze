// Jammerman — Recording Manager
// Screen + audio capture, save to camera roll
// Uses ReplayKit for screen capture

import Foundation
import ReplayKit
import Photos
import Combine

class RecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordingError: String?

    private let recorder = RPScreenRecorder.shared()

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard recorder.isAvailable else {
            recordingError = "Screen recording not available"
            return
        }

        recorder.isMicrophoneEnabled = false

        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.recordingError = "Failed to start recording: \(error.localizedDescription)"
                    self?.isRecording = false
                } else {
                    self?.isRecording = true
                    self?.recordingError = nil
                }
            }
        }
    }

    func stopRecording() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jammerman_\(Int(Date().timeIntervalSince1970)).mp4")

        recorder.stopRecording(withOutput: outputURL) { [weak self] error in
            DispatchQueue.main.async {
                self?.isRecording = false

                if let error {
                    self?.recordingError = "Failed to stop recording: \(error.localizedDescription)"
                    return
                }

                // Save to camera roll
                self?.saveToCameraRoll(url: outputURL)
            }
        }
    }

    private func saveToCameraRoll(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.recordingError = "Photo library access denied"
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { [weak self] success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.recordingError = nil
                        // Clean up temp file
                        try? FileManager.default.removeItem(at: url)
                    } else {
                        self?.recordingError = "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                    }
                }
            }
        }
    }
}
