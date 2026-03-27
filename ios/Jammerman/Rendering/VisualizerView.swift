// Jammerman — Audio-Reactive Visualizer
// Ported from web's visualizer.js — Core Graphics on CADisplayLink
// Effects: waveform ring, beat halo, face mesh, particles, frequency arc,
// hand trail, note constellation, mode geometry, arp viz

import SwiftUI
import UIKit

// MARK: - SwiftUI Wrapper

struct VisualizerOverlay: UIViewRepresentable {
    @ObservedObject var coordinator: TrackingCoordinator

    func makeUIView(context: Context) -> VisualizerUIView {
        let view = VisualizerUIView()
        view.coordinator = coordinator
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: VisualizerUIView, context: Context) {}
}

// MARK: - Core Graphics Visualizer

class VisualizerUIView: UIView {
    weak var coordinator: TrackingCoordinator?
    private var displayLink: CADisplayLink?

    // State
    private var beatPulse: CGFloat = 0
    private var lastBass: CGFloat = 0
    private var beatBloomRadius: CGFloat = 0
    private var beatBloomVelocity: CGFloat = 0
    private var beatBloomTarget: CGFloat = 0
    private var ringRotation: CGFloat = 0
    private var geoPhase: CGFloat = 0
    private var haloGlow: CGFloat = 0
    private var haloFlash: CGFloat = 0
    private var faceCx: CGFloat = 0
    private var faceCy: CGFloat = 0

    // Particles
    private var particles: [Particle] = []
    private let maxParticles = 25
    private var faceParticles: [Particle] = []
    private let maxFaceParticles = 30
    private var burstParticles: [Particle] = []

    // Halo
    private var haloRays: [HaloRay] = []
    private var haloRings: [HaloRing] = []
    private var shockwaves: [Shockwave] = []

    // Constellation
    private var constellationNotes: [ConstellationNote] = []
    private var lastMelodyNote: Int?

    // Color cache
    private var accentColor: UIColor = UIColor(red: 0.91, green: 0.66, blue: 0.28, alpha: 1)
    private var accentR: CGFloat = 0.91
    private var accentG: CGFloat = 0.66
    private var accentB: CGFloat = 0.28
    private var cachedMode: String = ""

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            displayLink?.add(to: .main, forMode: .common)
        } else {
            displayLink?.invalidate()
        }
    }

    @objc private func tick() {
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let coord = coordinator else { return }

        let w = rect.width
        let h = rect.height
        let state = coord.state

        // Update accent color on mode change
        if state.currentModeName != cachedMode {
            cachedMode = state.currentModeName
            updateAccentColor(mode: cachedMode)
        }

        // Compute energy from audio state (simplified — no FFT on iOS yet)
        let energy: CGFloat = state.faceDetected ? CGFloat(0.1 + state.mouthOpenness * 0.4) : 0
        let bass: CGFloat = state.faceDetected ? CGFloat(0.05 + state.mouthOpenness * 0.3) : 0

        // Beat detection
        if bass > lastBass * 1.4 && bass > 0.1 {
            beatPulse = 1.0
            beatBloomTarget = 1.0
            beatBloomVelocity = 0.2
            if shockwaves.count < 5 {
                shockwaves.append(Shockwave(radius: 0, alpha: 0.4, speed: 3 + bass * 5))
            }
        }
        lastBass = bass
        beatPulse *= 0.9

        // Bloom animation
        beatBloomRadius += beatBloomVelocity
        let bloomDiff = beatBloomTarget - beatBloomRadius
        beatBloomVelocity += bloomDiff * 0.15
        beatBloomVelocity *= 0.78
        beatBloomTarget *= 0.94

        ringRotation += 0.008
        geoPhase += 0.003

        // Face position
        if state.faceDetected {
            // Approximate face center (Vision coords → screen)
            let targetX = w * 0.5 // centered (camera is mirrored)
            let targetY = h * 0.35
            faceCx += (targetX - faceCx) * 0.1
            faceCy += (targetY - faceCy) * 0.1
        } else if faceCx == 0 {
            faceCx = w / 2
            faceCy = h * 0.35
        }

        let headR = min(w, h) * 0.14
        let cx = faceCx
        let cy = faceCy - headR * 0.5
        let baseRadius = min(w, h) * 0.54
        let beatExpand = beatPulse * 30
        let bloomExpand = beatBloomRadius * baseRadius * 0.18
        let radius = baseRadius + energy * 80 + beatExpand + bloomExpand

        // === DRAW LAYERS ===

        // 1. Mode geometry
        drawModeGeometry(ctx: ctx, w: w, h: h, energy: energy)

        // 2. Note constellation
        updateConstellation(state: state, w: w, h: h)
        drawConstellation(ctx: ctx, w: w, h: h)

        // 3. Waveform ring
        drawWaveformRing(ctx: ctx, cx: cx, cy: cy, radius: radius, energy: energy)

        // 4. Beat halo (rays, rings, glow)
        drawBeatHalo(ctx: ctx, cx: cx, cy: cy, headR: headR * 3, bass: bass, energy: energy)

        // 5. Shockwaves
        drawShockwaves(ctx: ctx, cx: cx, cy: cy)

        // 6. Particles
        updateParticles(energy: energy, cx: cx, cy: cy, radius: radius)
        drawParticles(ctx: ctx)

        // 7. Face mesh (if face detected and we have Vision landmarks)
        if state.faceDetected {
            drawFaceMesh(ctx: ctx, w: w, h: h, state: state, energy: energy)
        }

        // 8. Hand trail
        if state.handPresent {
            drawHandGlow(ctx: ctx, w: w, h: h, state: state, energy: energy)
        }

        // 9. Arp visualization
        drawArpViz(ctx: ctx, cx: cx, cy: cy, radius: radius, energy: energy)
    }

    // MARK: - Mode Geometry (faint rotating background shapes)

    private func drawModeGeometry(ctx: CGContext, w: CGFloat, h: CGFloat, energy: CGFloat) {
        let cx = w / 2, cy = h / 2
        let sides = modeSides()
        let r = min(w, h) * 0.35

        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.04 + energy * 0.03).cgColor)
        ctx.setLineWidth(1)

        for ring in 0..<3 {
            let ringR = r * (0.6 + CGFloat(ring) * 0.2)
            let phase = geoPhase + CGFloat(ring) * 0.3
            ctx.beginPath()
            for i in 0...sides {
                let angle = CGFloat(i) / CGFloat(sides) * .pi * 2 + phase
                let px = cx + cos(angle) * ringR
                let py = cy + sin(angle) * ringR
                if i == 0 { ctx.move(to: CGPoint(x: px, y: py)) }
                else { ctx.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.closePath()
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private func modeSides() -> Int {
        switch cachedMode {
        case "lydian": return 7
        case "ionian": return 6
        case "mixolydian": return 5
        case "dorian": return 8
        case "aeolian": return 5
        case "phrygian": return 4
        default: return 6
        }
    }

    // MARK: - Note Constellation

    private func updateConstellation(state: JammermanState, w: CGFloat, h: CGFloat) {
        if let note = state.melodyNote, note != lastMelodyNote {
            lastMelodyNote = note
            let x = CGFloat.random(in: w * 0.1...w * 0.9)
            let y = CGFloat.random(in: h * 0.1...h * 0.7)
            let hue = CGFloat(note % 12) / 12
            constellationNotes.append(ConstellationNote(x: x, y: y, life: 1, size: 2 + CGFloat.random(in: 0...3), hue: hue))
            if constellationNotes.count > 48 { constellationNotes.removeFirst() }
        }
        constellationNotes = constellationNotes.compactMap { var n = $0; n.life -= 0.005; return n.life > 0 ? n : nil }
    }

    private func drawConstellation(ctx: CGContext, w: CGFloat, h: CGFloat) {
        for note in constellationNotes {
            let alpha = note.life * 0.6
            ctx.saveGState()
            ctx.setFillColor(UIColor(hue: note.hue, saturation: 0.6, brightness: 1, alpha: alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: note.x - note.size / 2, y: note.y - note.size / 2, width: note.size, height: note.size))
            // Glow
            ctx.setShadow(offset: .zero, blur: 6, color: UIColor(hue: note.hue, saturation: 0.6, brightness: 1, alpha: alpha * 0.5).cgColor)
            ctx.fillEllipse(in: CGRect(x: note.x - 1, y: note.y - 1, width: 2, height: 2))
            ctx.restoreGState()
        }
    }

    // MARK: - Waveform Ring

    private func drawWaveformRing(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, energy: CGFloat) {
        let segments = 128
        let alpha = 0.15 + energy * 0.3

        // Outer glow pass
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.3).cgColor)
        ctx.setLineWidth(6)
        drawRingPath(ctx: ctx, cx: cx, cy: cy, radius: radius, segments: segments, amplitude: 20 * (1 + energy))
        ctx.strokePath()

        // Main ring
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
        ctx.setLineWidth(1.5)
        drawRingPath(ctx: ctx, cx: cx, cy: cy, radius: radius, segments: segments, amplitude: 20 * (1 + energy))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawRingPath(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, segments: Int, amplitude: CGFloat) {
        ctx.beginPath()
        for i in 0...segments {
            let angle = CGFloat(i) / CGFloat(segments) * .pi * 2 - .pi / 2 + ringRotation
            // Organic wobble using sin harmonics
            let wobble = sin(angle * 3 + geoPhase * 2) * amplitude * 0.3 + sin(angle * 7 + geoPhase * 5) * amplitude * 0.15
            let r = radius + wobble
            let px = cx + cos(angle) * r
            let py = cy + sin(angle) * r
            if i == 0 { ctx.move(to: CGPoint(x: px, y: py)) }
            else { ctx.addLine(to: CGPoint(x: px, y: py)) }
        }
        ctx.closePath()
    }

    // MARK: - Beat Halo (rays, rings, glow)

    private func drawBeatHalo(ctx: CGContext, cx: CGFloat, cy: CGFloat, headR: CGFloat, bass: CGFloat, energy: CGFloat) {
        haloGlow += (energy * 0.6 + beatPulse * 0.8 - haloGlow) * 0.12
        if beatPulse > 0.8 { haloFlash = 1.0 }
        haloFlash *= 0.85

        // Spawn rays on beat
        if beatPulse > 0.9 && haloRays.count < 24 {
            let count = 8 + Int(bass * 8)
            for i in 0..<count {
                let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.15...0.15)
                haloRays.append(HaloRay(
                    angle: angle,
                    length: headR + 20 + CGFloat.random(in: 0...80) + bass * 100,
                    width: 1.5 + CGFloat.random(in: 0...3),
                    life: 1.0,
                    decay: 0.015 + CGFloat.random(in: 0...0.015),
                    speed: 2 + CGFloat.random(in: 0...4)
                ))
            }
        }

        // Spawn rings on beat
        if beatPulse > 0.85 && haloRings.count < 6 {
            haloRings.append(HaloRing(radius: headR + 5, alpha: 0.6 + bass * 0.3, speed: 3 + bass * 5, width: 2 + bass * 3))
        }

        guard haloGlow > 0.01 || !haloRays.isEmpty || !haloRings.isEmpty else { return }

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        // Outer glow
        let outerR = headR + 80 + haloGlow * 200
        let glowAlpha = haloGlow * 0.2 + haloFlash * 0.15
        if glowAlpha > 0.01 {
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor,
                         UIColor(red: accentR, green: accentG, blue: accentB, alpha: glowAlpha).cgColor,
                         UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor] as CFArray,
                locations: [0, 0.3, 1])!
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: headR,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: outerR, options: [])
        }

        // Rays
        haloRays = haloRays.compactMap { var ray = $0
            ray.life -= ray.decay
            ray.length += ray.speed
            guard ray.life > 0 else { return nil }

            let alpha = ray.life * 0.5
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
            ctx.setLineWidth(ray.width * ray.life)
            ctx.beginPath()
            let startR = headR
            ctx.move(to: CGPoint(x: cx + cos(ray.angle) * startR, y: cy + sin(ray.angle) * startR))
            ctx.addLine(to: CGPoint(x: cx + cos(ray.angle) * ray.length, y: cy + sin(ray.angle) * ray.length))
            ctx.strokePath()
            return ray
        }

        // Expanding rings
        haloRings = haloRings.compactMap { var ring = $0
            ring.radius += ring.speed
            ring.alpha -= 0.015
            guard ring.alpha > 0 else { return nil }

            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: ring.alpha * 0.4).cgColor)
            ctx.setLineWidth(ring.width)
            ctx.strokeEllipse(in: CGRect(x: cx - ring.radius, y: cy - ring.radius, width: ring.radius * 2, height: ring.radius * 2))
            return ring
        }

        ctx.restoreGState()
    }

    // MARK: - Shockwaves

    private func drawShockwaves(ctx: CGContext, cx: CGFloat, cy: CGFloat) {
        shockwaves = shockwaves.compactMap { var sw = $0
            sw.radius += sw.speed
            sw.alpha -= 0.012
            guard sw.alpha > 0 else { return nil }

            ctx.saveGState()
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: sw.alpha * 0.3).cgColor)
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: cx - sw.radius, y: cy - sw.radius, width: sw.radius * 2, height: sw.radius * 2))
            ctx.restoreGState()
            return sw
        }
    }

    // MARK: - Particles

    private func updateParticles(energy: CGFloat, cx: CGFloat, cy: CGFloat, radius: CGFloat) {
        // Spawn particles based on energy
        if energy > 0.05 && particles.count < maxParticles {
            let angle = CGFloat.random(in: 0...(.pi * 2))
            let r = radius + CGFloat.random(in: -20...20)
            particles.append(Particle(
                x: cx + cos(angle) * r,
                y: cy + sin(angle) * r,
                vx: cos(angle) * CGFloat.random(in: 0.5...2),
                vy: sin(angle) * CGFloat.random(in: 0.5...2) - 0.3,
                life: 1, size: 1.5 + CGFloat.random(in: 0...2)
            ))
        }

        particles = particles.compactMap { var p = $0
            p.x += p.vx; p.y += p.vy; p.vy += 0.02; p.life -= 0.015
            return p.life > 0 ? p : nil
        }
    }

    private func drawParticles(ctx: CGContext) {
        for p in particles {
            ctx.saveGState()
            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: p.life * 0.6).cgColor)
            ctx.setShadow(offset: .zero, blur: 4, color: UIColor(red: accentR, green: accentG, blue: accentB, alpha: p.life * 0.3).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - p.size / 2, y: p.y - p.size / 2, width: p.size, height: p.size))
            ctx.restoreGState()
        }
    }

    // MARK: - Face Mesh (contour outline, eyes, brows, lips)

    private func drawFaceMesh(ctx: CGContext, w: CGFloat, h: CGFloat, state: JammermanState, energy: CGFloat) {
        // Use Vision face landmarks to draw contour
        // Since we don't have raw landmark points in the state, we approximate
        // using the detected face center and known proportions

        let cx = w * 0.5
        let cy = h * 0.38
        let faceW = w * 0.28
        let faceH = h * 0.22
        let alpha = 0.4 + energy * 0.3

        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
        ctx.setLineWidth(1.2)

        // Face oval
        ctx.strokeEllipse(in: CGRect(x: cx - faceW, y: cy - faceH, width: faceW * 2, height: faceH * 2))

        // Eyes (simplified)
        let eyeW: CGFloat = faceW * 0.35
        let eyeH: CGFloat = faceH * 0.12
        let eyeY = cy - faceH * 0.15
        // Left eye
        ctx.strokeEllipse(in: CGRect(x: cx - faceW * 0.45 - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH))
        // Right eye
        ctx.strokeEllipse(in: CGRect(x: cx + faceW * 0.45 - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH))

        // Eyebrows
        let browY = eyeY - faceH * 0.18 - CGFloat(state.browHeight) * 8
        ctx.setLineWidth(1.5)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx - faceW * 0.55, y: browY + 3))
        ctx.addQuadCurve(to: CGPoint(x: cx - faceW * 0.15, y: browY + 3), control: CGPoint(x: cx - faceW * 0.35, y: browY))
        ctx.strokePath()
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx + faceW * 0.15, y: browY + 3))
        ctx.addQuadCurve(to: CGPoint(x: cx + faceW * 0.55, y: browY + 3), control: CGPoint(x: cx + faceW * 0.35, y: browY))
        ctx.strokePath()

        // Nose bridge
        ctx.setLineWidth(0.8)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx, y: cy - faceH * 0.1))
        ctx.addLine(to: CGPoint(x: cx, y: cy + faceH * 0.15))
        ctx.strokePath()

        // Lips
        let lipY = cy + faceH * 0.35
        let lipW = faceW * 0.4
        let mouthOpen = CGFloat(state.mouthOpenness) * 8
        ctx.setLineWidth(1.2)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx - lipW, y: lipY))
        ctx.addQuadCurve(to: CGPoint(x: cx + lipW, y: lipY), control: CGPoint(x: cx, y: lipY - 4))
        ctx.strokePath()
        if mouthOpen > 1 {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx - lipW, y: lipY))
            ctx.addQuadCurve(to: CGPoint(x: cx + lipW, y: lipY), control: CGPoint(x: cx, y: lipY + mouthOpen))
            ctx.strokePath()
        }

        // Iris glow dots
        let irisR: CGFloat = 2
        ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.7 + beatPulse * 0.3).cgColor)
        ctx.setShadow(offset: .zero, blur: 6, color: accentColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - faceW * 0.45 - irisR, y: eyeY - irisR, width: irisR * 2, height: irisR * 2))
        ctx.fillEllipse(in: CGRect(x: cx + faceW * 0.45 - irisR, y: eyeY - irisR, width: irisR * 2, height: irisR * 2))

        ctx.restoreGState()
    }

    // MARK: - Hand Glow

    private func drawHandGlow(ctx: CGContext, w: CGFloat, h: CGFloat, state: JammermanState, energy: CGFloat) {
        let hx = CGFloat(state.handX) * w
        let hy = CGFloat(state.handY) * h
        let r: CGFloat = state.handOpen ? 20 : 12

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.5).cgColor,
                     UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: hx, y: hy), startRadius: 0,
                               endCenter: CGPoint(x: hx, y: hy), endRadius: r + energy * 30, options: [])
        ctx.restoreGState()
    }

    // MARK: - Arp Visualization (vertical columns)

    private func drawArpViz(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, energy: CGFloat) {
        guard let coord = coordinator else { return }
        let engine = coord.audioEngine

        // Left column for arp1, right for arp2
        if !engine.arpMuted {
            drawArpColumn(ctx: ctx, x: cx - radius * 0.6, h: bounds.height, energy: energy, side: -1)
        }
        if !engine.arp2Muted {
            drawArpColumn(ctx: ctx, x: cx + radius * 0.6, h: bounds.height, energy: energy, side: 1)
        }
    }

    private func drawArpColumn(ctx: CGContext, x: CGFloat, h: CGFloat, energy: CGFloat, side: CGFloat) {
        let barCount = 8
        let barH: CGFloat = 4
        let spacing: CGFloat = h * 0.05
        let startY = h * 0.3

        for i in 0..<barCount {
            let y = startY + CGFloat(i) * spacing
            let alpha = 0.1 + energy * 0.2
            let barW: CGFloat = 3 + CGFloat.random(in: 0...8) * energy

            ctx.saveGState()
            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
            ctx.setShadow(offset: .zero, blur: 4, color: UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.5).cgColor)
            ctx.fill(CGRect(x: x - barW / 2, y: y, width: barW, height: barH))
            ctx.restoreGState()
        }
    }

    // MARK: - Accent Color

    private func updateAccentColor(mode: String) {
        let colors: [String: (CGFloat, CGFloat, CGFloat)] = [
            "lydian": (0.98, 0.57, 0.24),
            "ionian": (0.98, 0.75, 0.14),
            "mixolydian": (0.20, 0.83, 0.60),
            "dorian": (0.13, 0.83, 0.93),
            "aeolian": (0.51, 0.55, 0.97),
            "phrygian": (0.65, 0.55, 0.98),
        ]
        if let c = colors[mode] {
            accentR = c.0; accentG = c.1; accentB = c.2
        }
        accentColor = UIColor(red: accentR, green: accentG, blue: accentB, alpha: 1)
    }
}

// MARK: - Data Types

struct Particle {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, life: CGFloat, size: CGFloat
}

struct HaloRay {
    var angle: CGFloat, length: CGFloat, width: CGFloat, life: CGFloat, decay: CGFloat, speed: CGFloat
}

struct HaloRing {
    var radius: CGFloat, alpha: CGFloat, speed: CGFloat, width: CGFloat
}

struct Shockwave {
    var radius: CGFloat, alpha: CGFloat, speed: CGFloat
}

struct ConstellationNote {
    var x: CGFloat, y: CGFloat, life: CGFloat, size: CGFloat, hue: CGFloat
}
