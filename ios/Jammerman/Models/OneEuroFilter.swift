// Jammerman — 1-Euro Adaptive Smoothing Filter
// Ported from web/js/config.js per shared/SPEC.md

import Foundation

class OneEuroFilter {
    private let freq: Double
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double

    private var x: Double?
    private var dx: Double = 0
    private var lastTime: Double?

    init(freq: Double = 60, minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0) {
        self.freq = freq
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    func filter(_ input: Double, timestamp: Double) -> Double {
        guard let prevX = x, let prevTime = lastTime else {
            x = input
            lastTime = timestamp
            return input
        }

        var dt = (timestamp - prevTime) / 1000.0
        if dt <= 0 { dt = 1.0 / freq }
        lastTime = timestamp

        let dxRaw = (input - prevX) / dt
        let edx = alpha(dt: dt, cutoff: dCutoff) * dxRaw + (1 - alpha(dt: dt, cutoff: dCutoff)) * dx
        self.dx = edx

        let cutoff = minCutoff + beta * abs(edx)
        let filtered = alpha(dt: dt, cutoff: cutoff) * input + (1 - alpha(dt: dt, cutoff: cutoff)) * prevX
        self.x = filtered

        return filtered
    }

    func reset() {
        x = nil
        dx = 0
        lastTime = nil
    }

    private func alpha(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}
