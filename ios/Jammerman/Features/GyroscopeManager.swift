// Jammerman — Gyroscope Manager
// CoreMotion-based tilt control: left/right -> arp pan, forward/back -> reverb
// Mirrors web's MUZE.Gyroscope (features.js)

import Foundation
import CoreMotion
import Combine

class GyroscopeManager: ObservableObject {
    @Published var active = false
    @Published var panValue: Float = 0      // -1 to +1 (left/right tilt)
    @Published var reverbMod: Float = 0     // 0 to 1 (forward/back tilt)

    private let motionManager = CMMotionManager()
    private var smoothGamma: Double = 0
    private var smoothBeta: Double = 0
    private let smoothingAlpha = 0.15

    weak var audioEngine: AudioEngine?

    func toggle() {
        if active {
            deactivate()
        } else {
            activate()
        }
    }

    func activate() {
        guard motionManager.isDeviceMotionAvailable else { return }

        active = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion else { return }
            self.processMotion(motion)
        }
    }

    func deactivate() {
        active = false
        motionManager.stopDeviceMotionUpdates()
        panValue = 0
        reverbMod = 0
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        let attitude = motion.attitude

        // Roll maps to left/right tilt (gamma in web)
        let gamma = attitude.roll * (180.0 / .pi)
        // Pitch maps to forward/back tilt (beta in web)
        let beta = attitude.pitch * (180.0 / .pi)

        // Smooth the values
        smoothGamma = smoothGamma * (1 - smoothingAlpha) + gamma * smoothingAlpha
        smoothBeta = smoothBeta * (1 - smoothingAlpha) + beta * smoothingAlpha

        // Map gamma (left/right, -45 to +45 usable range) to pan offset
        let gammaClamp = max(-45.0, min(45.0, smoothGamma))
        let pan = Float(gammaClamp / 45.0)

        // Map beta (forward/back, 0-90 range, center at ~45) to reverb modulation
        let betaNorm = Float(max(0, min(1, (smoothBeta - 20) / 50)))

        panValue = pan
        reverbMod = betaNorm

        // Apply to audio engine
        guard let engine = audioEngine else { return }

        // Gamma controls arp panning
        engine.setChannelPan("arp", pan: pan * 0.7)
        // Melody panning (opposite direction for stereo width)
        engine.setChannelPan("melody", pan: -pan * 0.5)

        // Beta controls reverb modulation on pad, arp, melody
        let baseReverbSends: [String: Float] = [
            "pad": engine.channelReverbSends["pad"] ?? 0.3,
            "arp": engine.channelReverbSends["arp"] ?? 0.2,
            "melody": engine.channelReverbSends["melody"] ?? 0.15
        ]
        for (ch, baseReverb) in baseReverbSends {
            let modulated = baseReverb * (0.5 + reverbMod * 1.0)
            engine.setChannelReverbSend(ch, amount: modulated)
        }
    }
}
