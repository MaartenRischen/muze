// Jammerman — Audio-Reactive Visualizer (v3 — faithful port of web visualizer.js)
// Core Graphics on CADisplayLink at 60fps
// Effects: waveform ring, beat halo, face mesh (3-pass neon glow on real Vision contours),
// iris glow, landmark lights, expression particles, energy aura, ghost trails,
// hand light painting trail, connection web, note constellation, mode geometry,
// arp viz, frequency arc, burst/explosion particles.

import SwiftUI
import UIKit
import Vision
import simd

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

    // ---- Beat detection ----
    private var beatPulse: CGFloat = 0
    private var lastBass: CGFloat = 0
    private var beatBloomRadius: CGFloat = 0
    private var beatBloomVelocity: CGFloat = 0
    private var beatBloomTarget: CGFloat = 0

    // ---- Ring rotation (frame counter) ----
    private var ringRotationFrame: Int = 0

    // ---- Geometry phase ----
    private var geoPhase: CGFloat = 0

    // ---- Face position (smoothed) ----
    private var faceCx: CGFloat = 0
    private var faceCy: CGFloat = 0

    // ---- Halo state ----
    private var haloGlow: CGFloat = 0
    private var haloFlash: CGFloat = 0
    private var haloRays: [HaloRay] = []
    private var haloRings: [HaloRing] = []
    private var shockwaves: [Shockwave] = []

    // ---- Particles ----
    private var particles: [VizParticle] = []
    private let maxParticles = 25
    private var faceParticles: [VizParticle] = []
    private let maxFaceParticles = 40
    private var burstParticles: [BurstParticle] = []
    private let maxBurstParticles = 50
    private var burstRings: [BurstRing] = []
    private var lastBurstNote: Int?
    private var explosionParticles: [ExplosionParticle] = []
    private var explosionGlowLife: CGFloat = 0
    private var explosionGlowX: CGFloat = 0
    private var explosionGlowY: CGFloat = 0

    // ---- Constellation ----
    private var constellationNotes: [ConstellationNote] = []
    private var lastMelodyNote: Int?

    // ---- Hand light painting trail (offscreen bitmap) ----
    private var trailImage: CGImage?
    private var trailContext: CGContext?
    private var prevTrailPos: CGPoint?
    private var handGlowRadius: CGFloat = 8
    private var handGlowTarget: CGFloat = 8
    private var handBloomRadius: CGFloat = 30
    private var handBloomTarget: CGFloat = 30
    private var trailW: Int = 0
    private var trailH: Int = 0

    // ---- Connection web ----
    private var connectionPulse: CGFloat = 0

    // ---- Ghost trails ----
    private var contourSnapshots: [ContourSnapshot] = []
    private let maxSnapshots = 4
    private var lastHeadYaw: CGFloat = 0
    private var lastHeadRoll: CGFloat = 0

    // ---- Arp viz ----
    private var arp1LastIdx: Int = -1
    private var arp1Flash: CGFloat = 0
    private var arp1Sparks: [ArpSpark] = []
    private var arp2LastIdx: Int = -1
    private var arp2Flash: CGFloat = 0
    private var arp2Sparks: [ArpSpark] = []

    // ---- Color cache ----
    private var accentR: CGFloat = 0.13
    private var accentG: CGFloat = 0.83
    private var accentB: CGFloat = 0.93
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

    // MARK: - Main Draw

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

        // Compute energy (simplified — no raw waveform on iOS yet)
        let energy: CGFloat = state.faceDetected ? CGFloat(0.1 + state.mouthOpenness * 0.4) : 0
        let bass: CGFloat = state.faceDetected ? CGFloat(0.05 + state.mouthOpenness * 0.3) : 0

        // ---- Beat detection ----
        if bass > lastBass * 1.4 && bass > 0.1 {
            beatPulse = 1.0
            beatBloomTarget = 1.0
            beatBloomVelocity = 0.25
            if shockwaves.count < 5 {
                shockwaves.append(Shockwave(radius: 0, alpha: 0.4, speed: 4 + bass * 6))
            }
        }
        lastBass = bass
        beatPulse *= 0.90

        // Animate beat bloom (elastic out, slow settle)
        beatBloomRadius += beatBloomVelocity
        let bloomDiff = beatBloomTarget - beatBloomRadius
        beatBloomVelocity += bloomDiff * 0.15
        beatBloomVelocity *= 0.78
        beatBloomTarget *= 0.94

        // Advance ring rotation
        ringRotationFrame += 1

        // Advance geometry phase
        geoPhase += 0.003

        // Face position from tracking (normalized 0..1 -> screen coords)
        // Fast tracking (0.5 alpha) so visuals follow face tightly
        if state.faceDetected {
            let targetX = CGFloat(state.faceCenterX) * w
            let targetY = CGFloat(state.faceCenterY) * h
            faceCx += (targetX - faceCx) * 0.5
            faceCy += (targetY - faceCy) * 0.5
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

        // === DRAW LAYERS (back to front) ===

        // 1. Mode geometry (very faint background texture)
        drawModeGeometry(ctx: ctx, w: w, h: h, energy: energy)

        // 2. Note constellation
        updateConstellation(state: state, w: w, h: h)
        drawConstellation(ctx: ctx, w: w, h: h)

        // 3. Waveform ring (3-pass: outer glow, core, hot core + radial fill + shockwaves)
        drawWaveformRing(ctx: ctx, cx: cx, cy: cy, radius: radius, energy: energy)

        // 4. Beat halo (rays, rings, glow)
        drawBeatHalo(ctx: ctx, w: w, h: h, bass: bass, energy: energy)

        // 5. Particles
        let particleEnergy = energy
        updateParticles(energy: particleEnergy, cx: cx, cy: cy, radius: radius)
        drawParticles(ctx: ctx)

        // 5b. Arp visualization
        drawArpViz(ctx: ctx, cx: cx, cy: cy, radius: radius, energy: energy)

        // 6. Frequency arc
        drawFrequencyArc(ctx: ctx, w: w, h: h, energy: energy)

        // 7. Hand light painting trail
        updateLightPainting(state: state, w: w, h: h)
        drawLightPainting(ctx: ctx, w: w, h: h)

        // 7b. Connection web (hand-to-face)
        drawConnectionWeb(ctx: ctx, w: w, h: h, state: state, energy: energy)

        // 8. Note burst particles
        updateBurstParticles()
        drawBurstParticles(ctx: ctx)

        // 9. Face mesh AR effects
        if state.faceDetected {
            if let vertices = state.faceVertices, let indices = state.faceTriangleIndices, state.usingARKit {
                // ARKit mode: draw 3D wireframe mesh projected to 2D
                drawARKitFaceMesh(ctx: ctx, vertices: vertices, indices: indices,
                                  faceCenterX: CGFloat(state.faceCenterX),
                                  faceCenterY: CGFloat(state.faceCenterY),
                                  w: w, h: h, energy: energy)
            }

            // Vision mode OR ARKit mode: draw contour effects if Vision landmarks available
            if let landmarks = state.rawLandmarks {
                let bb = state.faceBoundingBox
                let groups = extractContourGroups(landmarks: landmarks, bb: bb, w: w, h: h)

                // 9a. Ghost trails (drawn first, behind everything)
                updateContourSnapshots(groups: groups, state: state)
                drawContourTrails(ctx: ctx)

                // 9b. Energy aura
                drawEnergyAura(ctx: ctx, groups: groups, energy: energy)

                // 9c. Glowing face contour (the signature Tron look — 3-pass neon glow)
                drawContourGlow(ctx: ctx, groups: groups, energy: energy)

                // 9d. Iris glow (pulsing with audio)
                drawIrisGlow(ctx: ctx, groups: groups, energy: energy)

                // 9e. Landmark light points
                drawLandmarkLights(ctx: ctx, groups: groups, energy: energy)

                // 9f. Expression particles (mouth + eye sparkles)
                updateFaceParticles(groups: groups, state: state, energy: energy)
                drawFaceParticles(ctx: ctx)
            }
        }

        // 10. Explosion particles
        updateAndDrawExplosion(ctx: ctx, w: w, h: h)
    }

    // MARK: - ARKit 3D Face Mesh Wireframe

    /// Projects ARKit 3D face vertices to 2D screen coordinates and draws a wireframe mesh
    private func drawARKitFaceMesh(ctx: CGContext, vertices: [simd_float3], indices: [Int16],
                                   faceCenterX: CGFloat, faceCenterY: CGFloat,
                                   w: CGFloat, h: CGFloat, energy: CGFloat) {
        guard !vertices.isEmpty, indices.count >= 3 else { return }

        // Project 3D vertices (ARKit face-local coords, in meters) to 2D screen points
        // ARKit face vertices: X = right, Y = up, Z = towards camera
        // Face center in screen coords
        let cx = faceCenterX * w
        let cy = faceCenterY * h

        // Scale factor: ARKit face vertices are in meters, face is ~0.15m wide
        // We want the mesh to be about 40% of the screen width
        let scale = w * 2.8

        // Project each vertex to 2D
        let projected: [CGPoint] = vertices.map { v in
            // Simple orthographic projection (face is close to camera, perspective minimal)
            let px = cx + CGFloat(v.x) * scale
            let py = cy - CGFloat(v.y) * scale // flip Y
            return CGPoint(x: px, y: py)
        }

        // Draw wireframe triangles with neon glow
        let alpha = 0.15 + energy * 0.15
        let color = UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(0.5)

        // Draw every 3rd triangle to keep it lightweight (1220 vertices = ~2300 triangles)
        let triCount = indices.count / 3
        for t in stride(from: 0, to: triCount, by: 3) {
            let i0 = Int(indices[t * 3])
            let i1 = Int(indices[t * 3 + 1])
            let i2 = Int(indices[t * 3 + 2])

            guard i0 < projected.count, i1 < projected.count, i2 < projected.count else { continue }

            let p0 = projected[i0]
            let p1 = projected[i1]
            let p2 = projected[i2]

            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.strokePath()
        }

        // Outer glow pass (wider, dimmer) for neon effect
        let glowAlpha = 0.06 + energy * 0.06
        let glowColor = UIColor(red: accentR, green: accentG, blue: accentB, alpha: glowAlpha)
        ctx.setStrokeColor(glowColor.cgColor)
        ctx.setLineWidth(2.0)

        for t in stride(from: 0, to: triCount, by: 9) {
            let i0 = Int(indices[t * 3])
            let i1 = Int(indices[t * 3 + 1])
            let i2 = Int(indices[t * 3 + 2])

            guard i0 < projected.count, i1 < projected.count, i2 < projected.count else { continue }

            let p0 = projected[i0]
            let p1 = projected[i1]
            let p2 = projected[i2]

            ctx.beginPath()
            ctx.move(to: p0)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.strokePath()
        }
    }

    // MARK: - Face Contour Extraction (Vision landmarks -> screen points)

    /// Extracted contour groups in screen coordinates
    struct ContourGroups {
        var faceOval: [CGPoint] = []
        var leftEye: [CGPoint] = []
        var rightEye: [CGPoint] = []
        var outerLips: [CGPoint] = []
        var leftBrow: [CGPoint] = []
        var rightBrow: [CGPoint] = []
        var noseBridge: [CGPoint] = []
        // Key landmarks for iris, particles etc
        var leftEyeCenter: CGPoint = .zero
        var rightEyeCenter: CGPoint = .zero
        var mouthCenter: CGPoint = .zero
        var noseTip: CGPoint = .zero
        var faceCenter: CGPoint = .zero
        // All contours as a flat array for iteration
        var allContours: [[CGPoint]] = []
    }

    private func extractContourGroups(landmarks: VNFaceLandmarks2D, bb: CGRect, w: CGFloat, h: CGFloat) -> ContourGroups {
        var groups = ContourGroups()

        // Vision normalized points are relative to bounding box, with Y bottom-up
        // Camera preview already mirrors X, so don't mirror again here
        func toScreen(_ points: [CGPoint]) -> [CGPoint] {
            points.map { pt in
                let nx = bb.origin.x + pt.x * bb.width
                let ny = bb.origin.y + pt.y * bb.height
                // No X mirror (camera preview handles it), flip Y to top-left origin
                return CGPoint(x: nx * w, y: (1 - ny) * h)
            }
        }

        func centerOf(_ pts: [CGPoint]) -> CGPoint {
            guard !pts.isEmpty else { return .zero }
            let sx = pts.reduce(0.0) { $0 + $1.x }
            let sy = pts.reduce(0.0) { $0 + $1.y }
            return CGPoint(x: sx / CGFloat(pts.count), y: sy / CGFloat(pts.count))
        }

        if let fc = landmarks.faceContour {
            groups.faceOval = toScreen(fc.normalizedPoints.map { $0 })
        }
        if let le = landmarks.leftEye {
            groups.leftEye = toScreen(le.normalizedPoints.map { $0 })
            groups.leftEyeCenter = centerOf(groups.leftEye)
        }
        if let re = landmarks.rightEye {
            groups.rightEye = toScreen(re.normalizedPoints.map { $0 })
            groups.rightEyeCenter = centerOf(groups.rightEye)
        }
        if let ol = landmarks.outerLips {
            groups.outerLips = toScreen(ol.normalizedPoints.map { $0 })
            groups.mouthCenter = centerOf(groups.outerLips)
        }
        if let lb = landmarks.leftEyebrow {
            groups.leftBrow = toScreen(lb.normalizedPoints.map { $0 })
        }
        if let rb = landmarks.rightEyebrow {
            groups.rightBrow = toScreen(rb.normalizedPoints.map { $0 })
        }
        if let nc = landmarks.noseCrest {
            groups.noseBridge = toScreen(nc.normalizedPoints.map { $0 })
            if !groups.noseBridge.isEmpty {
                groups.noseTip = groups.noseBridge[groups.noseBridge.count / 2]
            }
        } else if let n = landmarks.nose {
            groups.noseBridge = toScreen(n.normalizedPoints.map { $0 })
            if !groups.noseBridge.isEmpty {
                groups.noseTip = groups.noseBridge[0]
            }
        }

        groups.faceCenter = centerOf(groups.faceOval.isEmpty ? [groups.noseTip] : groups.faceOval)

        groups.allContours = [
            groups.faceOval, groups.leftEye, groups.rightEye,
            groups.outerLips, groups.leftBrow, groups.rightBrow, groups.noseBridge
        ]

        return groups
    }

    // MARK: - 1. Waveform Ring (3-pass + radial fill + shockwaves + beat glow)

    private func drawWaveformRing(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, energy: CGFloat) {
        let segments = 128
        let rotationRad = CGFloat(ringRotationFrame) * 0.5 * .pi / 180

        // Compute ring points with organic wobble (simulates waveform since we have no raw samples)
        var points: [CGPoint] = []
        for i in 0...segments {
            let angle = CGFloat(i) / CGFloat(segments) * .pi * 2 - .pi / 2 + rotationRad
            let wobble = sin(angle * 3 + geoPhase * 2) * 15 * (1 + energy)
                       + sin(angle * 7 + geoPhase * 5) * 8 * (1 + energy)
            let r = radius + wobble
            points.append(CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r))
        }

        // Helper: build smooth Bezier ring path
        func buildRingPath() {
            ctx.beginPath()
            let last = points[points.count - 2]
            let first = points[0]
            ctx.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
            for i in 0..<(points.count - 1) {
                let curr = points[i]
                let next = points[(i + 1) % (points.count - 1)]
                ctx.addQuadCurve(to: CGPoint(x: (curr.x + next.x) / 2, y: (curr.y + next.y) / 2),
                                 control: curr)
            }
            ctx.closePath()
        }

        // ---- Shockwave rings ----
        ctx.saveGState()
        var i = shockwaves.count - 1
        while i >= 0 {
            shockwaves[i].radius += shockwaves[i].speed
            shockwaves[i].alpha *= 0.94
            shockwaves[i].speed *= 0.98
            if shockwaves[i].alpha < 0.005 {
                shockwaves.remove(at: i)
                i -= 1
                continue
            }
            let shockR = radius + shockwaves[i].radius
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: shockwaves[i].alpha).cgColor)
            ctx.setLineWidth(2 * shockwaves[i].alpha + 0.5)
            ctx.strokeEllipse(in: CGRect(x: cx - shockR, y: cy - shockR, width: shockR * 2, height: shockR * 2))
            i -= 1
        }
        ctx.restoreGState()

        // ---- Radial gradient fill inside ring ----
        let fillBase = 0.02 + energy * 0.06 + beatPulse * 0.04
        let fillAlpha = min(0.10, fillBase)
        if fillAlpha > 0.005 {
            ctx.saveGState()
            buildRingPath()
            ctx.clip()
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: fillAlpha * 0.7).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: fillAlpha * 0.3).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: fillAlpha * 0.6).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.5, 0.85, 1])!
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: radius, options: [])
            ctx.restoreGState()
        }

        // ---- PASS 1: Outer glow (wide, faint) ----
        let glowIntensify: CGFloat = beatPulse > 0.3 ? 2.0 : 1.0
        ctx.saveGState()
        buildRingPath()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.06 * glowIntensify).cgColor)
        ctx.setLineWidth(12)
        ctx.strokePath()
        ctx.restoreGState()

        // ---- PASS 2: Core ring (medium) ----
        ctx.saveGState()
        buildRingPath()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: min(1, 0.35 + energy * 0.4 + beatPulse * 0.25)).cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
        ctx.restoreGState()

        // ---- PASS 3: Hot core (thin, white) ----
        ctx.saveGState()
        buildRingPath()
        ctx.setStrokeColor(UIColor(white: 1, alpha: min(1, 0.5 + energy * 0.5 + beatPulse * 0.3)).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokePath()
        ctx.restoreGState()

        // ---- Beat glow bloom ----
        if beatPulse > 0.05 {
            let glowRadius = radius + beatPulse * 40
            let glowAlpha = beatPulse * 0.2
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: glowAlpha).cgColor)
            ctx.setLineWidth(20 + beatPulse * 30)
            ctx.strokeEllipse(in: CGRect(x: cx - glowRadius, y: cy - glowRadius, width: glowRadius * 2, height: glowRadius * 2))
            ctx.restoreGState()
        }

        // ---- Inner thin reference circle ----
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.04).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: CGRect(x: cx - radius * 0.85, y: cy - radius * 0.85, width: radius * 1.7, height: radius * 1.7))
        ctx.restoreGState()
    }

    // MARK: - 2. Beat Halo (dramatic pulsing around head)

    private func drawBeatHalo(ctx: CGContext, w: CGFloat, h: CGFloat, bass: CGFloat, energy: CGFloat) {
        let headR = min(w, h) * 0.42
        let cx = faceCx
        let cy = faceCy - headR * 0.25
        let bp = beatPulse
        let bloom = beatBloomRadius

        haloGlow += (energy * 0.6 + bp * 0.8 - haloGlow) * 0.12
        if bp > 0.8 { haloFlash = 1.0 }
        haloFlash *= 0.85

        // Spawn rays on beat
        if bp > 0.9 && haloRays.count < 24 {
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

        // Spawn expanding rings on beat
        if bp > 0.85 && haloRings.count < 6 {
            haloRings.append(HaloRing(radius: headR + 5, alpha: 0.6 + bass * 0.3, speed: 3 + bass * 5, width: 2 + bass * 3))
        }

        let glow = haloGlow
        guard glow > 0.01 || !haloRays.isEmpty || !haloRings.isEmpty else { return }

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let flash = haloFlash

        // === PASS 1: Outer glow ===
        let outerR = headR + 80 + glow * 200 + bloom * 60
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor,
                UIColor(red: accentR, green: accentG, blue: accentB, alpha: min(1, glow * 0.3 + flash * 0.2)).cgColor,
                UIColor(red: accentR, green: accentG, blue: accentB, alpha: min(1, glow * 0.12)).cgColor,
                UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
            ] as CFArray,
            locations: [0, 0.02, 0.4, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: headR,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: outerR, options: [])
        }

        // === PASS 2: Bright rim at head edge ===
        let rimR = headR + 25 + glow * 40 + bp * 20
        let cR = min(1.0, accentR + flash * 0.6)
        let cG = min(1.0, accentG + flash * 0.6)
        let cB = min(1.0, accentB + flash * 0.6)
        if let rimGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(red: cR, green: cG, blue: cB, alpha: 0).cgColor,
                UIColor(red: cR, green: cG, blue: cB, alpha: min(1, 0.2 + glow * 0.3 + flash * 0.4)).cgColor,
                UIColor(red: accentR, green: accentG, blue: accentB, alpha: min(1, glow * 0.1)).cgColor,
                UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
            ] as CFArray,
            locations: [0, 0.02, 0.5, 1]) {
            ctx.drawRadialGradient(rimGrad, startCenter: CGPoint(x: cx, y: cy), startRadius: headR - 2,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: rimR, options: [])
        }

        // === PASS 3: White-hot flash ring ===
        if flash > 0.05 {
            let flashR = headR + 50 + flash * 50
            if let flashGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: min(1, flash * 0.4)).cgColor,
                    UIColor(white: 1, alpha: min(1, flash * 0.1)).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.02, 0.4, 1]) {
                ctx.drawRadialGradient(flashGrad, startCenter: CGPoint(x: cx, y: cy), startRadius: headR,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: flashR, options: [])
            }
        }

        // === PASS 4: Light rays ===
        var rayIdx = haloRays.count - 1
        while rayIdx >= 0 {
            haloRays[rayIdx].length += haloRays[rayIdx].speed
            haloRays[rayIdx].life -= haloRays[rayIdx].decay
            if haloRays[rayIdx].life <= 0 {
                haloRays.remove(at: rayIdx)
                rayIdx -= 1
                continue
            }
            let ray = haloRays[rayIdx]
            let a = ray.life * ray.life
            let x1 = cx + cos(ray.angle) * headR
            let y1 = cy + sin(ray.angle) * headR
            let x2 = cx + cos(ray.angle) * ray.length
            let y2 = cy + sin(ray.angle) * ray.length

            // Linear gradient along ray
            if let rayGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: a * 0.4).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: a * 0.15).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.3, 1]) {
                // Draw as a thick line with gradient (approximate with solid color since CG doesn't support gradient stroke easily)
                ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: a * 0.4).cgColor)
                ctx.setLineWidth(ray.width * ray.life)
                ctx.setLineCap(.round)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x1, y: y1))
                ctx.addLine(to: CGPoint(x: x2, y: y2))
                ctx.strokePath()
            }
            rayIdx -= 1
        }

        // === PASS 5: Expanding halo rings ===
        var ringIdx = haloRings.count - 1
        while ringIdx >= 0 {
            haloRings[ringIdx].radius += haloRings[ringIdx].speed
            haloRings[ringIdx].alpha *= 0.96
            if haloRings[ringIdx].alpha < 0.01 {
                haloRings.remove(at: ringIdx)
                ringIdx -= 1
                continue
            }
            let ring = haloRings[ringIdx]
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: ring.alpha).cgColor)
            ctx.setLineWidth(ring.width)
            ctx.strokeEllipse(in: CGRect(x: cx - ring.radius, y: cy - ring.radius, width: ring.radius * 2, height: ring.radius * 2))
            ringIdx -= 1
        }

        ctx.restoreGState()
    }

    // MARK: - 3. Mode Geometry

    private func drawModeGeometry(ctx: CGContext, w: CGFloat, h: CGFloat, energy: CGFloat) {
        let alpha = 0.015 + energy * 0.02
        guard alpha > 0.005 else { return }

        let cx = w / 2
        let cy = h * 0.38
        let modeIdx = getModeIndex()

        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
        ctx.setLineWidth(0.5)

        if modeIdx <= 1 {
            drawAngularShards(ctx: ctx, cx: cx, cy: cy, w: w, h: h, phase: geoPhase, alpha: alpha)
        } else if modeIdx <= 3 {
            drawHexLattice(ctx: ctx, cx: cx, cy: cy, w: w, h: h, phase: geoPhase, alpha: alpha)
        } else {
            drawFlowingCurves(ctx: ctx, cx: cx, cy: cy, w: w, h: h, phase: geoPhase, alpha: alpha)
        }

        ctx.restoreGState()
    }

    private func getModeIndex() -> Int {
        let map: [String: Int] = [
            "phrygian": 0, "phrygian dom": 0,
            "aeolian": 1, "harm. minor": 1, "pent. minor": 1, "blues": 1,
            "dorian": 2, "melodic minor": 2,
            "mixolydian": 3, "hirajoshi": 3,
            "ionian": 4, "pent. major": 4, "whole tone": 4,
            "lydian": 5,
        ]
        return map[cachedMode] ?? 2
    }

    private func drawAngularShards(ctx: CGContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, phase: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.8).cgColor)
        let count = 6
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + phase * 0.7
            let len = min(w, h) * (0.25 + 0.1 * sin(phase * 2 + CGFloat(i)))
            let innerLen = len * 0.4

            let x1 = cx + cos(angle) * innerLen
            let y1 = cy + sin(angle) * innerLen
            let midAngle = angle + 0.15 * sin(phase + CGFloat(i) * 1.3)
            let mx = cx + cos(midAngle) * len * 0.7
            let my = cy + sin(midAngle) * len * 0.7
            let x2 = cx + cos(angle) * len
            let y2 = cy + sin(angle) * len

            ctx.beginPath()
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: mx, y: my))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
            ctx.strokePath()
        }

        // Small triangular fragments
        for i in 0..<3 {
            let a = phase * 0.5 + CGFloat(i) * 2.09
            let dist = min(w, h) * 0.22
            let tx = cx + cos(a) * dist
            let ty = cy + sin(a) * dist
            let size = 15 + 5 * sin(phase * 1.5 + CGFloat(i))

            ctx.beginPath()
            for j in 0..<3 {
                let ta = a + CGFloat(j) / 3 * .pi * 2 + phase * 0.3
                let px = tx + cos(ta) * size
                let py = ty + sin(ta) * size
                if j == 0 { ctx.move(to: CGPoint(x: px, y: py)) }
                else { ctx.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.closePath()
            ctx.strokePath()
        }
    }

    private func drawHexLattice(ctx: CGContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, phase: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.6).cgColor)
        let hexSize: CGFloat = 40
        let rings = 3

        let dirs: [(CGFloat, CGFloat)] = [
            (1, 0), (0.5, 0.866), (-0.5, 0.866),
            (-1, 0), (-0.5, -0.866), (0.5, -0.866)
        ]

        for ring in 1...rings {
            for i in 0..<(6 * ring) {
                let side = i / ring
                let pos = i % ring

                let startDir = dirs[side]
                let nextDir = dirs[(side + 1) % 6]
                let hx = startDir.0 * CGFloat(ring) + (nextDir.0 - startDir.0) * (CGFloat(pos) / CGFloat(ring))
                let hy = startDir.1 * CGFloat(ring) + (nextDir.1 - startDir.1) * (CGFloat(pos) / CGFloat(ring))

                let px = cx + hx * hexSize
                let py = cy + hy * hexSize

                guard px > -20 && px < w + 20 && py > -20 && py < h + 20 else { continue }

                let rot = phase * 0.5 + CGFloat(ring) * 0.3
                let s = 4 + sin(phase + CGFloat(ring) + CGFloat(i) * 0.2) * 2

                ctx.beginPath()
                for v in 0..<6 {
                    let a = rot + CGFloat(v) / 6 * .pi * 2
                    let vx = px + cos(a) * s
                    let vy = py + sin(a) * s
                    if v == 0 { ctx.move(to: CGPoint(x: vx, y: vy)) }
                    else { ctx.addLine(to: CGPoint(x: vx, y: vy)) }
                }
                ctx.closePath()
                ctx.strokePath()
            }
        }
    }

    private func drawFlowingCurves(ctx: CGContext, cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, phase: CGFloat, alpha: CGFloat) {
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.7).cgColor)
        let baseR = min(w, h) * 0.2

        // Orbital rings with varying eccentricity
        for i in 0..<4 {
            let r = baseR * (0.6 + CGFloat(i) * 0.25)
            let ecc = 0.15 + 0.05 * sin(phase + CGFloat(i))
            let rot = phase * (0.3 + CGFloat(i) * 0.1)

            ctx.beginPath()
            var firstPoint = true
            var a: CGFloat = 0
            while a <= .pi * 2 {
                let rx = r * (1 + ecc * cos(a * 2 + phase))
                let ry = r * (1 - ecc * cos(a * 3))
                let px = cx + cos(a + rot) * rx
                let py = cy + sin(a + rot) * ry
                if firstPoint { ctx.move(to: CGPoint(x: px, y: py)); firstPoint = false }
                else { ctx.addLine(to: CGPoint(x: px, y: py)) }
                a += 0.08
            }
            ctx.strokePath()
        }

        // Small floating arcs
        for i in 0..<5 {
            let arcAngle = phase * 0.6 + CGFloat(i) * 1.257
            let dist = baseR * (0.8 + 0.3 * sin(phase * 0.8 + CGFloat(i)))
            let ax = cx + cos(arcAngle) * dist
            let ay = cy + sin(arcAngle) * dist
            let arcR = 8 + 6 * sin(phase * 1.2 + CGFloat(i) * 0.9)
            let startA = arcAngle + phase
            let sweep = CGFloat.pi * (0.5 + 0.3 * sin(phase + CGFloat(i)))

            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: ax, y: ay), radius: arcR, startAngle: startA, endAngle: startA + sweep, clockwise: false)
            ctx.strokePath()
        }
    }

    // MARK: - 4. Note Constellation

    private func updateConstellation(state: JammermanState, w: CGFloat, h: CGFloat) {
        if let note = state.melodyNote, note != lastMelodyNote {
            lastMelodyNote = note

            // Position based on musical interval (clock face arrangement)
            let root = state.effectiveRoot
            let interval = ((note - root) % 12 + 12) % 12
            let octave = (note - root) / 12

            let angle = CGFloat(interval) / 12.0 * .pi * 2 - .pi / 2
            let baseDist = min(w, h) * 0.12
            let dist = baseDist + CGFloat(octave) * 25

            let cx = w / 2
            let cy = h * 0.38

            constellationNotes.append(ConstellationNote(
                x: cx + cos(angle) * dist,
                y: cy + sin(angle) * dist,
                life: 1,
                decay: 0.003 + CGFloat.random(in: 0...0.002),
                size: 2.5 + CGFloat.random(in: 0...1.5),
                brightness: 1.0
            ))

            if constellationNotes.count > 48 { constellationNotes.removeFirst() }

            // Trigger note burst
            triggerNoteBurst(note: note, handX: CGFloat(state.handX), handY: 1 - CGFloat(state.handY), w: w, h: h)
        }

        if state.melodyNote == nil { lastMelodyNote = nil }

        // Decay
        var i = constellationNotes.count - 1
        while i >= 0 {
            constellationNotes[i].life -= constellationNotes[i].decay
            constellationNotes[i].brightness *= 0.997
            if constellationNotes[i].life <= 0 {
                constellationNotes.remove(at: i)
            }
            i -= 1
        }
    }

    private func drawConstellation(ctx: CGContext, w: CGFloat, h: CGFloat) {
        guard !constellationNotes.isEmpty else { return }

        // Connection lines between consecutive notes
        if constellationNotes.count > 1 {
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.04).cgColor)
            ctx.setLineWidth(0.5)
            ctx.beginPath()
            for i in 1..<constellationNotes.count {
                let a = constellationNotes[i - 1]
                let b = constellationNotes[i]
                if a.life > 0.2 && b.life > 0.2 {
                    ctx.move(to: CGPoint(x: a.x, y: a.y))
                    ctx.addLine(to: CGPoint(x: b.x, y: b.y))
                }
            }
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Draw dots
        for n in constellationNotes {
            let alpha = n.life * n.life * 0.6
            guard alpha > 0.01 else { continue }

            // Outer glow
            let glowSize = n.size * (2 + n.brightness)
            ctx.saveGState()
            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.15).cgColor)
            ctx.fillEllipse(in: CGRect(x: n.x - glowSize, y: n.y - glowSize, width: glowSize * 2, height: glowSize * 2))

            // Core dot
            let coreSize = n.size * n.life
            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: n.x - coreSize, y: n.y - coreSize, width: coreSize * 2, height: coreSize * 2))

            // Bright center on fresh notes
            if n.brightness > 0.5 {
                let centerSize = n.size * 0.4
                ctx.setFillColor(UIColor(white: 1, alpha: alpha * n.brightness * 0.5).cgColor)
                ctx.fillEllipse(in: CGRect(x: n.x - centerSize, y: n.y - centerSize, width: centerSize * 2, height: centerSize * 2))
            }
            ctx.restoreGState()
        }

        // Faint interval reference circle
        if constellationNotes.count > 2 {
            let cx = w / 2, cy = h * 0.38
            let refR = min(w, h) * 0.12
            ctx.saveGState()
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.02).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: CGRect(x: cx - refR, y: cy - refR, width: refR * 2, height: refR * 2))
            ctx.restoreGState()
        }
    }

    // MARK: - 5. Particles

    private func updateParticles(energy: CGFloat, cx: CGFloat, cy: CGFloat, radius: CGFloat) {
        let spawnCount = energy > 0.03 ? min(3, Int(energy * 8)) : 0
        for _ in 0..<spawnCount {
            guard particles.count < maxParticles else { break }
            let angle = CGFloat.random(in: 0...(.pi * 2))
            particles.append(VizParticle(
                x: cx + cos(angle) * radius,
                y: cy + sin(angle) * radius,
                vx: (CGFloat.random(in: 0...1) - 0.5) * 1.2,
                vy: -CGFloat.random(in: 0...1.5) - 0.3,
                life: 1, decay: 0.006 + CGFloat.random(in: 0...0.010),
                size: 0.5 + CGFloat.random(in: 0...1.2),
                type: 0
            ))
        }

        var i = particles.count - 1
        while i >= 0 {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vy -= 0.01
            particles[i].life -= particles[i].decay
            if particles[i].life <= 0 { particles.remove(at: i) }
            i -= 1
        }
    }

    private func drawParticles(ctx: CGContext) {
        for p in particles {
            let alpha = min(1, p.life * p.life * 0.4)
            guard alpha > 0.01 else { continue }
            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - p.size, y: p.y - p.size, width: p.size * 2, height: p.size * 2))
        }
    }

    // MARK: - 6. Face Mesh: Contour Glow (3-pass neon, the "signature Tron look")

    private func drawContourGlow(ctx: CGContext, groups: ContourGroups, energy: CGFloat) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // 3-pass neon glow: wide dim -> medium -> thin bright core
        let passes: [(width: CGFloat, alpha: CGFloat)] = [
            (8, 0.06),
            (4, 0.12),
            (1.5, 0.3),
        ]

        for pass in passes {
            ctx.setLineWidth(pass.width)
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: min(1, pass.alpha)).cgColor)

            // Batch all contours into a single path per pass
            ctx.beginPath()
            for contour in groups.allContours {
                guard contour.count >= 2 else { continue }
                ctx.move(to: contour[0])
                for i in 1..<contour.count {
                    ctx.addLine(to: contour[i])
                }
            }
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - 7. Iris Glow (pulsing radial glow at eye centers)

    private func drawIrisGlow(ctx: CGContext, groups: ContourGroups, energy: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        let pulseScale = 1.0 + energy * 0.8 + beatPulse * 1.2
        let baseRadius = 6 * pulseScale
        let baseAlpha = min(1, 0.2 + energy * 0.4 + beatPulse * 0.3)

        let irisPoints = [groups.leftEyeCenter, groups.rightEyeCenter]

        for iris in irisPoints {
            guard iris != .zero else { continue }
            let r = baseRadius

            // Outer soft glow
            if let outerGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: baseAlpha * 0.6).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: baseAlpha * 0.25).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.3, 1]) {
                ctx.drawRadialGradient(outerGrad, startCenter: iris, startRadius: 0,
                                       endCenter: iris, endRadius: r * 3, options: [])
            }

            // Inner bright core (white center fading to accent)
            if let coreGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(white: 1, alpha: baseAlpha * 0.7).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: baseAlpha * 0.5).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.4, 1]) {
                ctx.drawRadialGradient(coreGrad, startCenter: iris, startRadius: 0,
                                       endCenter: iris, endRadius: r, options: [])
            }
        }

        ctx.restoreGState()
    }

    // MARK: - 8. Landmark Light Points

    private func drawLandmarkLights(ctx: CGContext, groups: ContourGroups, energy: CGFloat) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        // Key landmark positions: nose tip, eye centers, mouth center, brow midpoints
        var keyPoints: [CGPoint] = []
        if groups.noseTip != .zero { keyPoints.append(groups.noseTip) }
        if groups.leftEyeCenter != .zero { keyPoints.append(groups.leftEyeCenter) }
        if groups.rightEyeCenter != .zero { keyPoints.append(groups.rightEyeCenter) }
        if groups.mouthCenter != .zero { keyPoints.append(groups.mouthCenter) }
        if !groups.leftBrow.isEmpty { keyPoints.append(groups.leftBrow[groups.leftBrow.count / 2]) }
        if !groups.rightBrow.isEmpty { keyPoints.append(groups.rightBrow[groups.rightBrow.count / 2]) }
        // Face oval top and bottom
        if groups.faceOval.count > 4 {
            keyPoints.append(groups.faceOval[0])
            keyPoints.append(groups.faceOval[groups.faceOval.count / 2])
        }

        for pt in keyPoints {
            let baseR: CGFloat = 3
            let r = baseR + energy * 8 + beatPulse * 12
            let alpha = min(1, 0.15 + energy * 0.3 + beatPulse * 0.4)

            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.4).cgColor,
                    UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.4, 1]) {
                ctx.drawRadialGradient(grad, startCenter: pt, startRadius: 0,
                                       endCenter: pt, endRadius: r, options: [])
            }
        }

        ctx.restoreGState()
    }

    // MARK: - 9. Energy Aura (soft breathing glow around face contour)

    private func drawEnergyAura(ctx: CGContext, groups: ContourGroups, energy: CGFloat) {
        guard energy > 0.02 || beatPulse > 0.1 else { return }
        guard !groups.faceOval.isEmpty else { return }

        let fcx = groups.faceCenter.x
        let fcy = groups.faceCenter.y
        let expand = 15 + beatPulse * 10
        let auraAlpha = 0.03 + energy * 0.06 + beatPulse * 0.05

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let auraPasses: [(width: CGFloat, alpha: CGFloat)] = [
            (30, auraAlpha * 0.4),
            (15, auraAlpha * 0.7),
        ]

        for pass in auraPasses {
            ctx.setLineWidth(pass.width)
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: min(0.15, pass.alpha)).cgColor)

            ctx.beginPath()
            for (i, pt) in groups.faceOval.enumerated() {
                let dx = pt.x - fcx
                let dy = pt.y - fcy
                let dist = sqrt(dx * dx + dy * dy)
                let nd = max(dist, 1)
                let ex = pt.x + (dx / nd) * expand
                let ey = pt.y + (dy / nd) * expand
                if i == 0 { ctx.move(to: CGPoint(x: ex, y: ey)) }
                else { ctx.addLine(to: CGPoint(x: ex, y: ey)) }
            }
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - 10. Head Rotation Ghost Trails

    private func updateContourSnapshots(groups: ContourGroups, state: JammermanState) {
        let yaw = CGFloat(state.headYaw)
        let roll = CGFloat(state.headRoll)

        let yawDelta = abs(yaw - lastHeadYaw)
        let rollDelta = abs(roll - lastHeadRoll)
        let moving = yawDelta > 0.012 || rollDelta > 0.012

        lastHeadYaw = yaw
        lastHeadRoll = roll

        if moving && !groups.faceOval.isEmpty {
            contourSnapshots.append(ContourSnapshot(points: groups.faceOval, opacity: 0.3))
            while contourSnapshots.count > maxSnapshots {
                contourSnapshots.removeFirst()
            }
        }

        var i = contourSnapshots.count - 1
        while i >= 0 {
            contourSnapshots[i].opacity *= 0.88
            if contourSnapshots[i].opacity < 0.01 {
                contourSnapshots.remove(at: i)
            }
            i -= 1
        }
    }

    private func drawContourTrails(ctx: CGContext) {
        guard !contourSnapshots.isEmpty else { return }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for snap in contourSnapshots {
            guard snap.opacity > 0.005, snap.points.count >= 2 else { continue }

            // Thin bright line
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: snap.opacity * 0.5).cgColor)
            ctx.beginPath()
            ctx.move(to: snap.points[0])
            for i in 1..<snap.points.count {
                ctx.addLine(to: snap.points[i])
            }
            ctx.strokePath()

            // Wide dim glow
            ctx.setLineWidth(5)
            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: snap.opacity * 0.15).cgColor)
            ctx.beginPath()
            ctx.move(to: snap.points[0])
            for i in 1..<snap.points.count {
                ctx.addLine(to: snap.points[i])
            }
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - 11. Expression Particles (mouth + eye sparkles)

    private func updateFaceParticles(groups: ContourGroups, state: JammermanState, energy: CGFloat) {
        // Mouth particles: emit when mouth is open
        let mouthOpen = CGFloat(state.mouthOpenness)
        if mouthOpen > 0.15 {
            let mc = groups.mouthCenter
            let spawnCount = min(4, Int(mouthOpen * 6 + beatPulse * 3))
            for _ in 0..<spawnCount {
                guard faceParticles.count < maxFaceParticles else { break }
                faceParticles.append(VizParticle(
                    x: mc.x + CGFloat.random(in: -6...6),
                    y: mc.y,
                    vx: CGFloat.random(in: -1.25...1.25),
                    vy: -CGFloat.random(in: 0.8...3.3),
                    life: 1, decay: 0.015 + CGFloat.random(in: 0...0.015),
                    size: 1 + CGFloat.random(in: 0...2),
                    type: 1 // mouth
                ))
            }
        }

        // Eye sparkle particles: wide eyes = sparkle
        let eyeOpen = CGFloat(state.eyeOpenness)
        if eyeOpen > 0.7 {
            let sparkleIntensity = (eyeOpen - 0.7) / 0.3
            let spawnCount = min(2, Int(sparkleIntensity * 3))
            let eyeCenters = [groups.leftEyeCenter, groups.rightEyeCenter]

            for eye in eyeCenters {
                guard eye != .zero else { continue }
                for _ in 0..<spawnCount {
                    guard faceParticles.count < maxFaceParticles else { break }
                    let angle = CGFloat.random(in: 0...(.pi * 2))
                    faceParticles.append(VizParticle(
                        x: eye.x + CGFloat.random(in: -3...3),
                        y: eye.y + CGFloat.random(in: -3...3),
                        vx: cos(angle) * (0.5 + CGFloat.random(in: 0...1.5)),
                        vy: sin(angle) * (0.5 + CGFloat.random(in: 0...1.5)) - 0.3,
                        life: 1, decay: 0.02 + CGFloat.random(in: 0...0.015),
                        size: 0.6 + CGFloat.random(in: 0...1.2),
                        type: 2 // eye
                    ))
                }
            }
        }

        // Update all face particles
        var i = faceParticles.count - 1
        while i >= 0 {
            faceParticles[i].x += faceParticles[i].vx
            faceParticles[i].y += faceParticles[i].vy
            if faceParticles[i].type == 1 { faceParticles[i].vy -= 0.03 } // mouth: drift up
            faceParticles[i].vx *= 0.98
            faceParticles[i].vy *= 0.98
            faceParticles[i].life -= faceParticles[i].decay
            if faceParticles[i].life <= 0 { faceParticles.remove(at: i) }
            i -= 1
        }
    }

    private func drawFaceParticles(ctx: CGContext) {
        guard !faceParticles.isEmpty else { return }

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        for p in faceParticles {
            let alpha = p.life * p.life * 0.6
            guard alpha > 0.01 else { continue }

            // Eye sparkles get white highlight
            if p.type == 2 {
                ctx.setFillColor(UIColor(white: 1, alpha: alpha * 0.7).cgColor)
                let sz = p.size * p.life * 0.7
                ctx.fillEllipse(in: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2))
            }

            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha).cgColor)
            let sz = p.size * p.life
            ctx.fillEllipse(in: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2))
        }

        ctx.restoreGState()
    }

    // MARK: - 12. Hand Light Painting Trail

    private func updateLightPainting(state: JammermanState, w: CGFloat, h: CGFloat) {
        let iw = Int(w)
        let ih = Int(h)
        guard iw > 0 && ih > 0 else { return }

        // Recreate trail context if size changed
        if trailW != iw || trailH != ih {
            trailW = iw; trailH = ih
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            trailContext = CGContext(data: nil, width: iw, height: ih,
                                    bitsPerComponent: 8, bytesPerRow: iw * 4,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            trailContext?.translateBy(x: 0, y: CGFloat(ih))
            trailContext?.scaleBy(x: 1, y: -1)
            prevTrailPos = nil
            trailImage = nil
        }

        guard let tctx = trailContext else { return }

        // Fade previous content using destination-out
        tctx.saveGState()
        tctx.setBlendMode(.destinationOut)
        tctx.setFillColor(UIColor(white: 0, alpha: 0.02).cgColor)
        tctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        tctx.restoreGState()

        // Lerp glow sizes
        if state.handPresent {
            handGlowTarget = state.handOpen ? 20 : 8
            handBloomTarget = state.handOpen ? 45 : 18
        }
        handGlowRadius += (handGlowTarget - handGlowRadius) * 0.3
        handBloomRadius += (handBloomTarget - handBloomRadius) * 0.3

        if state.handPresent {
            let px = CGFloat(state.handX) * w
            let py = (1 - CGFloat(state.handY)) * h
            let glow = handGlowRadius
            let bloom = handBloomRadius
            let core: CGFloat = state.handOpen ? 4 : 2

            let (tr, tg, tb) = noteToTrailRGB(note: state.melodyNote ?? 60)

            if let prev = prevTrailPos {
                let dx = px - prev.x
                let dy = py - prev.y
                if dx * dx + dy * dy > 0.25 {
                    tctx.saveGState()
                    tctx.setLineCap(.round)
                    tctx.setBlendMode(.plusLighter)

                    // Outer bloom
                    tctx.setAlpha(0.08)
                    tctx.setStrokeColor(UIColor(red: tr, green: tg, blue: tb, alpha: 1).cgColor)
                    tctx.setLineWidth(bloom)
                    tctx.beginPath()
                    tctx.move(to: prev)
                    tctx.addLine(to: CGPoint(x: px, y: py))
                    tctx.strokePath()

                    // Inner glow
                    tctx.setAlpha(0.35)
                    tctx.setLineWidth(glow)
                    tctx.beginPath()
                    tctx.move(to: prev)
                    tctx.addLine(to: CGPoint(x: px, y: py))
                    tctx.strokePath()

                    // Core white
                    tctx.setAlpha(0.9)
                    tctx.setStrokeColor(UIColor.white.cgColor)
                    tctx.setLineWidth(core)
                    tctx.beginPath()
                    tctx.move(to: prev)
                    tctx.addLine(to: CGPoint(x: px, y: py))
                    tctx.strokePath()

                    tctx.restoreGState()
                }
            }

            // 3-layer radial glow dot
            tctx.saveGState()
            tctx.setBlendMode(.plusLighter)

            tctx.setAlpha(0.15)
            tctx.setFillColor(UIColor(red: tr, green: tg, blue: tb, alpha: 1).cgColor)
            tctx.fillEllipse(in: CGRect(x: px - bloom * 0.7, y: py - bloom * 0.7, width: bloom * 1.4, height: bloom * 1.4))

            tctx.setAlpha(0.6)
            tctx.fillEllipse(in: CGRect(x: px - glow * 0.6, y: py - glow * 0.6, width: glow * 1.2, height: glow * 1.2))

            tctx.setAlpha(1.0)
            tctx.setFillColor(UIColor.white.cgColor)
            tctx.fillEllipse(in: CGRect(x: px - core * 0.75, y: py - core * 0.75, width: core * 1.5, height: core * 1.5))

            tctx.restoreGState()

            prevTrailPos = CGPoint(x: px, y: py)
        } else {
            prevTrailPos = nil
        }

        trailImage = tctx.makeImage()
    }

    private func drawLightPainting(ctx: CGContext, w: CGFloat, h: CGFloat) {
        guard let img = trailImage else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    private func noteToTrailRGB(note: Int) -> (CGFloat, CGFloat, CGFloat) {
        let nrm = max(0, min(1, CGFloat(note - 36) / 36))
        var r: CGFloat, g: CGFloat, b: CGFloat
        if nrm < 0.33 {
            let t = nrm / 0.33
            r = (60 + t * 40) / 255; g = (100 + t * 80) / 255; b = (200 + t * 55) / 255
        } else if nrm < 0.66 {
            let t = (nrm - 0.33) / 0.33
            r = (100 + t * 130) / 255; g = (180 + t * 20) / 255; b = (255 - t * 180) / 255
        } else {
            let t = (nrm - 0.66) / 0.34
            r = (230 + t * 25) / 255; g = (200 - t * 60) / 255; b = (75 - t * 40) / 255
        }
        return (r, g, b)
    }

    // MARK: - 13. Connection Web (hand-to-face threads)

    private func drawConnectionWeb(ctx: CGContext, w: CGFloat, h: CGFloat, state: JammermanState, energy: CGFloat) {
        guard state.handPresent, state.faceDetected else { return }

        let hx = CGFloat(state.handX) * w
        let hy = (1 - CGFloat(state.handY)) * h

        // Target points on face
        var targets: [CGPoint] = []
        if let lm = state.rawLandmarks {
            let bb = state.faceBoundingBox
            let groups = extractContourGroups(landmarks: lm, bb: bb, w: w, h: h)
            targets.append(groups.noseTip)
            targets.append(groups.mouthCenter)
            targets.append(groups.faceCenter)
            if !groups.leftBrow.isEmpty { targets.append(groups.leftBrow[groups.leftBrow.count / 2]) }
            if !groups.rightBrow.isEmpty { targets.append(groups.rightBrow[groups.rightBrow.count / 2]) }
        } else {
            targets.append(CGPoint(x: faceCx, y: faceCy))
        }
        targets = targets.filter { $0 != .zero }
        guard !targets.isEmpty else { return }

        connectionPulse += 0.04
        let pulse = 0.7 + sin(connectionPulse) * 0.3
        let baseAlpha = (0.02 + min(0.06, energy * 0.4)) * pulse

        ctx.saveGState()
        ctx.setLineWidth(0.8)
        ctx.setLineCap(.round)

        for t in targets {
            let mx = (hx + t.x) / 2, my = (hy + t.y) / 2
            let dx = t.x - hx, dy = t.y - hy
            let len = sqrt(dx * dx + dy * dy)
            let nl = max(len, 1)
            let bow = nl * 0.08
            let cpx = mx + (-dy / nl) * bow
            let cpy = my + (dx / nl) * bow

            ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: baseAlpha).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: hx, y: hy))
            ctx.addQuadCurve(to: t, control: CGPoint(x: cpx, y: cpy))
            ctx.strokePath()

            if baseAlpha > 0.015 {
                ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: baseAlpha * 1.5).cgColor)
                ctx.fillEllipse(in: CGRect(x: t.x - 1.5, y: t.y - 1.5, width: 3, height: 3))
            }
        }

        ctx.restoreGState()
    }

    // MARK: - 14. Note Burst Particles

    private func triggerNoteBurst(note: Int, handX: CGFloat, handY: CGFloat, w: CGFloat, h: CGFloat) {
        guard let lastNote = lastBurstNote else {
            lastBurstNote = note
            return
        }
        let interval = abs(note - lastNote)
        lastBurstNote = note
        guard interval > 0 else { return }

        let cx = handX * w
        let cy = handY * h
        let (r, g, b) = noteToTrailRGB(note: note)

        let count = min(20, max(5, Int(CGFloat(interval) * 1.7)))
        let burstSpeed = 1.5 + CGFloat(interval) * 0.5

        for i in 0..<count {
            if burstParticles.count >= maxBurstParticles {
                burstParticles.removeFirst()
            }
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: 0...0.4)
            let speed = burstSpeed * (0.6 + CGFloat.random(in: 0...0.8))
            burstParticles.append(BurstParticle(
                x: cx, y: cy,
                vx: cos(angle) * speed, vy: sin(angle) * speed,
                life: 1, decay: 0.014 + CGFloat.random(in: 0...0.012),
                size: 1.5 + CGFloat(interval) * 0.35 + CGFloat.random(in: 0...1.5),
                r: r, g: g, b: b, gravity: -0.02
            ))
        }

        // Expanding ring
        let ringMax = min(60, 15 + CGFloat(interval) * 5)
        burstRings.append(BurstRing(
            x: cx, y: cy, radius: 0, maxRadius: ringMax, alpha: 0.6,
            r: r, g: g, b: b, speed: ringMax / 24
        ))
    }

    private func updateBurstParticles() {
        var i = burstParticles.count - 1
        while i >= 0 {
            burstParticles[i].x += burstParticles[i].vx
            burstParticles[i].y += burstParticles[i].vy
            burstParticles[i].vy += burstParticles[i].gravity
            burstParticles[i].vx *= 0.97
            burstParticles[i].vy *= 0.97
            burstParticles[i].life -= burstParticles[i].decay
            if burstParticles[i].life <= 0 { burstParticles.remove(at: i) }
            i -= 1
        }

        i = burstRings.count - 1
        while i >= 0 {
            burstRings[i].radius += burstRings[i].speed
            burstRings[i].alpha *= 0.94
            if burstRings[i].alpha < 0.01 || burstRings[i].radius > burstRings[i].maxRadius {
                burstRings.remove(at: i)
            }
            i -= 1
        }
    }

    private func drawBurstParticles(ctx: CGContext) {
        for p in burstParticles {
            let alpha = p.life * p.life
            guard alpha > 0.01 else { continue }
            let sz = p.size * p.life

            // Additive outer glow
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setFillColor(UIColor(red: p.r, green: p.g, blue: p.b, alpha: alpha * 0.3).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - sz * 2, y: p.y - sz * 2, width: sz * 4, height: sz * 4))
            ctx.restoreGState()

            // Core
            ctx.setFillColor(UIColor(red: p.r, green: p.g, blue: p.b, alpha: alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2))
        }

        for ring in burstRings {
            guard ring.alpha > 0.01 else { continue }
            ctx.saveGState()
            ctx.setBlendMode(.plusLighter)
            ctx.setStrokeColor(UIColor(red: ring.r, green: ring.g, blue: ring.b, alpha: ring.alpha).cgColor)
            ctx.setLineWidth(2 * ring.alpha + 0.5)
            ctx.strokeEllipse(in: CGRect(x: ring.x - ring.radius, y: ring.y - ring.radius, width: ring.radius * 2, height: ring.radius * 2))
            ctx.restoreGState()
        }
    }

    // MARK: - 15. Frequency Arc (bottom arc with bars)

    private func drawFrequencyArc(ctx: CGContext, w: CGFloat, h: CGFloat, energy: CGFloat) {
        guard energy > 0.008 else { return }

        let arcBins = 32
        let arcCx = w / 2
        let arcCy = h + h * 0.35
        let arcRadius = min(w * 0.6, h * 0.55)
        let arcSpan = CGFloat.pi * 0.50
        let startAngle = CGFloat.pi + (.pi - arcSpan) / 2
        let segAngle = arcSpan / CGFloat(arcBins)
        let maxBarH: CGFloat = 55

        ctx.saveGState()
        ctx.setLineCap(.round)

        // Generate pseudo-frequency data from energy + wobble
        for pass in 0..<2 {
            let isMirror = pass == 0
            let passAlpha: CGFloat = isMirror ? 0.15 : 1.0

            for i in 0..<arcBins {
                // Synthesize frequency bin value
                let freqRatio = CGFloat(i) / CGFloat(arcBins)
                let val = energy * (0.3 + 0.7 * sin(freqRatio * .pi + geoPhase * 3))
                    * (1 + beatPulse * 0.5)
                    * (1 - freqRatio * 0.5) // bass heavy
                guard val > 0.03 || isMirror else { continue }

                let angle = startAngle + (CGFloat(i) + 0.5) * segAngle
                let barH = val * maxBarH + 1
                let baseX = arcCx + cos(angle) * arcRadius
                let baseY = arcCy + sin(angle) * arcRadius

                // Color gradient: bass=accent, treble=brighter
                let r = accentR + (1 - accentR) * freqRatio * 0.5
                let g = accentG + (1 - accentG) * freqRatio * 0.4
                let b = accentB + (1 - accentB) * freqRatio * 0.3
                let alpha = (0.15 + val * 0.55) * passAlpha

                ctx.saveGState()
                ctx.translateBy(x: baseX, y: baseY)
                ctx.rotate(by: angle + .pi / 2)

                if isMirror {
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.translateBy(x: 0, y: -1)
                }

                let barWidth: CGFloat = 5
                ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor)
                let borderR = min(2, barWidth / 2, barH / 2)
                let barRect = CGRect(x: -barWidth / 2, y: -barH, width: barWidth, height: barH)
                let path = UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: borderR, height: borderR))
                ctx.addPath(path.cgPath)
                ctx.fillPath()

                // Glow on energetic bars
                if !isMirror && val > 0.4 {
                    ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: (val - 0.4) * 0.15).cgColor)
                    ctx.fill(CGRect(x: -barWidth / 2 - 2, y: -barH - 2, width: barWidth + 4, height: barH + 4))
                }

                ctx.restoreGState()
            }
        }

        // Thin arc baseline
        ctx.setStrokeColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0.06).cgColor)
        ctx.setLineWidth(0.5)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: arcCx, y: arcCy), radius: arcRadius, startAngle: startAngle, endAngle: startAngle + arcSpan, clockwise: false)
        ctx.strokePath()

        ctx.restoreGState()
    }

    // MARK: - 16. Arp Visualization (dual columns)

    private func drawArpViz(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, energy: CGFloat) {
        guard let coord = coordinator else { return }
        let engine = coord.audioEngine

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        let colOffset = radius + 50
        let vH = min(280, cy * 0.65)
        let topY = cy - vH / 2
        let botY = cy + vH / 2

        if !engine.arpMuted {
            drawArpColumn(ctx: ctx, colX: cx - colOffset, topY: topY, botY: botY, vH: vH,
                          energy: energy, side: -1,
                          lastIdx: &arp1LastIdx, flash: &arp1Flash, sparks: &arp1Sparks,
                          colorR: 74.0/255, colorG: 222.0/255, colorB: 128.0/255)
        }
        if !engine.arp2Muted {
            drawArpColumn(ctx: ctx, colX: cx + colOffset, topY: topY, botY: botY, vH: vH,
                          energy: energy, side: 1,
                          lastIdx: &arp2LastIdx, flash: &arp2Flash, sparks: &arp2Sparks,
                          colorR: 52.0/255, colorG: 211.0/255, colorB: 153.0/255)
        }

        ctx.restoreGState()
    }

    private func drawArpColumn(ctx: CGContext, colX: CGFloat, topY: CGFloat, botY: CGFloat, vH: CGFloat,
                               energy: CGFloat, side: CGFloat,
                               lastIdx: inout Int, flash: inout CGFloat, sparks: inout [ArpSpark],
                               colorR: CGFloat, colorG: CGFloat, colorB: CGFloat) {
        // Use accent color for the notes since we don't have direct arp note access
        let n = 8 // approximate note count
        let currentIdx = Int(geoPhase * 4) % n // animate through positions

        // Detect note change -> flash + sparks
        if currentIdx != lastIdx {
            flash = 1.0
            lastIdx = currentIdx
            let sy = botY - (CGFloat(currentIdx) / CGFloat(n - 1)) * vH
            for _ in 0..<5 {
                let angle = CGFloat.random(in: 0...(.pi * 2))
                let speed = 1 + CGFloat.random(in: 0...2.5)
                sparks.append(ArpSpark(
                    x: colX, y: sy,
                    vx: cos(angle) * speed, vy: sin(angle) * speed - 1,
                    life: 1, decay: 0.025 + CGFloat.random(in: 0...0.02),
                    r: colorR, g: colorG, b: colorB
                ))
            }
        }
        flash *= 0.88

        // Faint vertical guide
        ctx.setStrokeColor(UIColor(red: colorR, green: colorG, blue: colorB, alpha: 0.06).cgColor)
        ctx.setLineWidth(1)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: colX, y: topY))
        ctx.addLine(to: CGPoint(x: colX, y: botY))
        ctx.strokePath()

        // Draw note dots
        for i in 0..<n {
            let y = botY - (CGFloat(i) / CGFloat(n - 1)) * vH
            let (r, g, b) = noteToTrailRGB(note: 48 + i * 3)
            let isActive = (i == currentIdx)

            if isActive {
                let glowSize = 10 + flash * 16 + energy * 6

                // Outer glow
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        UIColor(red: r, green: g, blue: b, alpha: 0.8 + flash * 0.2).cgColor,
                        UIColor(red: r, green: g, blue: b, alpha: 0.25 + flash * 0.3).cgColor,
                        UIColor(red: r, green: g, blue: b, alpha: 0).cgColor
                    ] as CFArray,
                    locations: [0, 0.35, 1]) {
                    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: colX, y: y), startRadius: 0,
                                           endCenter: CGPoint(x: colX, y: y), endRadius: glowSize, options: [])
                }

                // White-hot core
                ctx.setFillColor(UIColor(white: 1, alpha: 0.7 + flash * 0.3).cgColor)
                ctx.fillEllipse(in: CGRect(x: colX - 3 - flash * 3, y: y - 3 - flash * 3, width: 6 + flash * 6, height: 6 + flash * 6))

                // Horizontal bar pulse
                ctx.setStrokeColor(UIColor(red: r, green: g, blue: b, alpha: 0.3 + flash * 0.4).cgColor)
                ctx.setLineWidth(2)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: colX - 12 - flash * 8, y: y))
                ctx.addLine(to: CGPoint(x: colX + 12 + flash * 8, y: y))
                ctx.strokePath()
            } else {
                let dist = min(abs(i - currentIdx), abs(i - currentIdx + n), abs(i - currentIdx - n))
                let prox = max(0, 1 - CGFloat(dist) / (CGFloat(n) * 0.4))
                let a = 0.12 + prox * 0.2
                let sz = 1.5 + prox * 1.5

                // Outer glow
                ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: a * 0.25).cgColor)
                ctx.fillEllipse(in: CGRect(x: colX - sz - 3, y: y - sz - 3, width: (sz + 3) * 2, height: (sz + 3) * 2))

                // Core
                ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: a).cgColor)
                ctx.fillEllipse(in: CGRect(x: colX - sz, y: y - sz, width: sz * 2, height: sz * 2))
            }
        }

        // Update and draw sparks
        var si = sparks.count - 1
        while si >= 0 {
            sparks[si].x += sparks[si].vx
            sparks[si].y += sparks[si].vy
            sparks[si].vx *= 0.95
            sparks[si].vy *= 0.95
            sparks[si].life -= sparks[si].decay
            if sparks[si].life <= 0 {
                sparks.remove(at: si)
                si -= 1
                continue
            }
            let s = sparks[si]
            ctx.setFillColor(UIColor(red: s.r, green: s.g, blue: s.b, alpha: s.life * s.life).cgColor)
            ctx.fillEllipse(in: CGRect(x: s.x - 1.5 * s.life, y: s.y - 1.5 * s.life, width: 3 * s.life, height: 3 * s.life))
            si -= 1
        }
        if sparks.count > 60 { sparks.removeAll(keepingCapacity: true) }
    }

    // MARK: - 17. Explosion Particles (riser drop)

    private func updateAndDrawExplosion(ctx: CGContext, w: CGFloat, h: CGFloat) {
        // Screen-wide glow
        if explosionGlowLife > 0 {
            explosionGlowLife -= 0.033
            if explosionGlowLife > 0 {
                let glowRadius = min(w, h) * 0.4
                let glowAlpha = explosionGlowLife * explosionGlowLife * 0.15
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [
                        UIColor(red: accentR, green: accentG, blue: accentB, alpha: glowAlpha).cgColor,
                        UIColor(red: accentR, green: accentG, blue: accentB, alpha: 0).cgColor
                    ] as CFArray,
                    locations: [0, 1]) {
                    ctx.drawRadialGradient(grad,
                        startCenter: CGPoint(x: explosionGlowX, y: explosionGlowY), startRadius: 0,
                        endCenter: CGPoint(x: explosionGlowX, y: explosionGlowY), endRadius: glowRadius, options: [])
                }
            }
        }

        // Particles
        var i = explosionParticles.count - 1
        while i >= 0 {
            explosionParticles[i].x += explosionParticles[i].vx
            explosionParticles[i].y += explosionParticles[i].vy
            explosionParticles[i].vx *= explosionParticles[i].drag
            explosionParticles[i].vy *= explosionParticles[i].drag
            explosionParticles[i].vy += explosionParticles[i].gravity
            explosionParticles[i].life -= explosionParticles[i].decay

            if explosionParticles[i].life <= 0 {
                explosionParticles.remove(at: i)
                i -= 1
                continue
            }

            let p = explosionParticles[i]
            let alpha = p.life * p.life
            ctx.setFillColor(UIColor(red: accentR, green: accentG, blue: accentB, alpha: alpha * 0.7).cgColor)
            let sz = p.size * p.life
            ctx.fillEllipse(in: CGRect(x: p.x - sz, y: p.y - sz, width: sz * 2, height: sz * 2))
            i -= 1
        }
    }

    // MARK: - Accent Color (matching web MODE_COLORS exactly)

    private func updateAccentColor(mode: String) {
        let colors: [String: (CGFloat, CGFloat, CGFloat)] = [
            "phrygian":      (167.0/255, 139.0/255, 250.0/255),
            "aeolian":       (129.0/255, 140.0/255, 248.0/255),
            "dorian":        (34.0/255,  211.0/255, 238.0/255),
            "mixolydian":    (52.0/255,  211.0/255, 153.0/255),
            "ionian":        (251.0/255, 191.0/255, 36.0/255),
            "lydian":        (251.0/255, 146.0/255, 60.0/255),
            "pent. major":   (249.0/255, 168.0/255, 212.0/255),
            "pent. minor":   (192.0/255, 132.0/255, 252.0/255),
            "harm. minor":   (244.0/255, 114.0/255, 182.0/255),
            "whole tone":    (163.0/255, 230.0/255, 53.0/255),
            "blues":         (56.0/255,  189.0/255, 248.0/255),
            "melodic minor": (167.0/255, 139.0/255, 250.0/255),
            "phrygian dom":  (249.0/255, 115.0/255, 22.0/255),
            "hirajoshi":     (236.0/255, 72.0/255,  153.0/255),
        ]
        if let c = colors[mode] {
            accentR = c.0; accentG = c.1; accentB = c.2
        }
    }
}

// MARK: - Data Types

private struct VizParticle {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
    var life: CGFloat, decay: CGFloat, size: CGFloat
    var type: Int // 0=general, 1=mouth, 2=eye
}

private struct HaloRay {
    var angle: CGFloat, length: CGFloat, width: CGFloat
    var life: CGFloat, decay: CGFloat, speed: CGFloat
}

private struct HaloRing {
    var radius: CGFloat, alpha: CGFloat, speed: CGFloat, width: CGFloat
}

private struct Shockwave {
    var radius: CGFloat, alpha: CGFloat, speed: CGFloat
}

private struct ConstellationNote {
    var x: CGFloat, y: CGFloat, life: CGFloat, decay: CGFloat, size: CGFloat, brightness: CGFloat
}

private struct ContourSnapshot {
    var points: [CGPoint]
    var opacity: CGFloat
}

private struct BurstParticle {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
    var life: CGFloat, decay: CGFloat, size: CGFloat
    var r: CGFloat, g: CGFloat, b: CGFloat, gravity: CGFloat
}

private struct BurstRing {
    var x: CGFloat, y: CGFloat, radius: CGFloat, maxRadius: CGFloat, alpha: CGFloat
    var r: CGFloat, g: CGFloat, b: CGFloat, speed: CGFloat
}

private struct ExplosionParticle {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
    var life: CGFloat, decay: CGFloat, size: CGFloat
    var gravity: CGFloat, drag: CGFloat
}

private struct ArpSpark {
    var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
    var life: CGFloat, decay: CGFloat
    var r: CGFloat, g: CGFloat, b: CGFloat
}
