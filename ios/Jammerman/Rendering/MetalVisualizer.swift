// Muze — Metal Visualizer
// GPU-accelerated rendering of all visual effects via MTKView
// Replaces CoreGraphics VisualizerView for dramatically better performance

import MetalKit
import simd

// MARK: - Uniform Buffer (matches Shaders.metal VisualizerUniforms)

struct VisualizerUniforms {
    var screenSize: SIMD2<Float> = .zero
    var time: Float = 0
    var beatPulse: Float = 0
    var energy: Float = 0
    var accentColor: SIMD3<Float> = SIMD3(0.13, 0.83, 0.93)
    var faceCenter: SIMD2<Float> = SIMD2(0.5, 0.4)
    var bloomRadius: Float = 0
    var haloGlow: Float = 0
    var haloFlash: Float = 0
}

// MARK: - GPU Instance Types (match Shaders.metal)

struct GPUParticle {
    var position: SIMD2<Float>
    var size: Float
    var life: Float
    var color: SIMD4<Float>
}

struct GPUEllipse {
    var center: SIMD2<Float>
    var radii: SIMD2<Float>
    var lineWidth: Float
    var color: SIMD4<Float>
}

struct GPUGradientParams {
    var center: SIMD2<Float>
    var innerRadius: Float
    var outerRadius: Float
    var innerColor: SIMD4<Float>
    var outerColor: SIMD4<Float>
}

// MARK: - CPU-side Particle Types (physics, spawn, decay on CPU)

struct MetalParticle {
    var x: Float, y: Float, vx: Float, vy: Float
    var life: Float, decay: Float, size: Float
    var r: Float, g: Float, b: Float
}

struct MetalHaloRay {
    var angle: Float, length: Float, width: Float
    var life: Float, decay: Float, speed: Float
}

struct MetalRing {
    var radius: Float, alpha: Float, speed: Float, width: Float
    var cx: Float, cy: Float  // center
    var rx: Float, ry: Float  // radii ratio (1,1 for circle, 1,0.35 for halo ellipse)
}

struct MetalConstellationNote {
    var x: Float, y: Float, life: Float, decay: Float, size: Float, brightness: Float
}

// MARK: - Metal Visualizer

class MetalVisualizer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var coordinator: TrackingCoordinator?

    // Pipeline states
    private var particlePipeline: MTLRenderPipelineState!
    private var linePipeline: MTLRenderPipelineState!
    private var gradientPipeline: MTLRenderPipelineState!
    private var vignettePipeline: MTLRenderPipelineState!
    private var beatFlashPipeline: MTLRenderPipelineState!
    private var ellipsePipeline: MTLRenderPipelineState!

    // Triple-buffered uniforms
    private var uniformBuffers: [MTLBuffer] = []
    private var currentBuffer = 0
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    // Animation state
    private var uniforms = VisualizerUniforms()
    private var startTime = CACurrentMediaTime()
    private var beatPulse: Float = 0
    private var beatBloomRadius: Float = 0
    private var beatBloomVelocity: Float = 0
    private var beatBloomTarget: Float = 0
    private var lastDrumStep: Int = -1
    private var haloGlow: Float = 0
    private var haloFlash: Float = 0
    private var geoPhase: Float = 0
    private var ringRotation: Float = 0
    private var lastBass: Float = 0
    private var faceCx: Float = 0
    private var faceCy: Float = 0

    // Particle arrays (CPU-side, packed to GPU each frame)
    private var particles: [MetalParticle] = []
    private var faceParticles: [MetalParticle] = []
    private var burstParticles: [MetalParticle] = []
    private var constellationNotes: [MetalConstellationNote] = []
    private var haloRays: [MetalHaloRay] = []
    private var rings: [MetalRing] = []  // shockwaves + halo rings combined
    private var lastMelodyNote: Int?

    // Accent color
    private var accentR: Float = 0.13, accentG: Float = 0.83, accentB: Float = 0.93
    private var cachedMode = ""

    // Max particle counts
    private let maxParticles = 50
    private let maxFaceParticles = 60
    private let maxBurstParticles = 80

    init(device: MTLDevice, coordinator: TrackingCoordinator) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.coordinator = coordinator
        super.init()
        buildPipelines()
        buildBuffers()
    }

    // MARK: - Pipeline Setup

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("[Metal] Failed to create default library")
            return
        }

        // Additive blend descriptor (for particles, glows, etc.)
        func additivePipeline(vertex: String, fragment: String) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .one
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        // Alpha blend descriptor (for vignette, darkening)
        func alphaPipeline(vertex: String, fragment: String) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        particlePipeline = additivePipeline(vertex: "particleVertex", fragment: "particleFragment")
        ellipsePipeline = additivePipeline(vertex: "ellipseVertex", fragment: "ellipseFragment")
        gradientPipeline = additivePipeline(vertex: "fullscreenQuadVertex", fragment: "radialGradientFragment")
        vignettePipeline = alphaPipeline(vertex: "fullscreenQuadVertex", fragment: "vignetteFragment")
        beatFlashPipeline = additivePipeline(vertex: "fullscreenQuadVertex", fragment: "beatFlashFragment")
    }

    private func buildBuffers() {
        // Triple-buffered uniform buffers
        for _ in 0..<3 {
            let buf = device.makeBuffer(length: MemoryLayout<VisualizerUniforms>.stride, options: .storageModeShared)!
            uniformBuffers.append(buf)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let coord = coordinator else { return }
        inflightSemaphore.wait()

        let w = Float(view.drawableSize.width)
        let h = Float(view.drawableSize.height)
        guard w > 0, h > 0 else { inflightSemaphore.signal(); return }

        let state = coord.state
        let engine = coord.audioEngine

        // Update animation state
        updateAnimationState(state: state, engine: engine, w: w, h: h)

        // Update uniforms
        uniforms.screenSize = SIMD2(w, h)
        uniforms.time = Float(CACurrentMediaTime() - startTime)
        uniforms.beatPulse = beatPulse
        uniforms.energy = state.faceDetected ? 0.1 + state.mouthOpenness * 0.4 : 0
        uniforms.accentColor = SIMD3(accentR, accentG, accentB)
        uniforms.faceCenter = SIMD2(faceCx / w, faceCy / h)
        uniforms.bloomRadius = beatBloomRadius
        uniforms.haloGlow = haloGlow
        uniforms.haloFlash = haloFlash

        // Write to current uniform buffer
        let uniformBuf = uniformBuffers[currentBuffer]
        uniformBuf.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<VisualizerUniforms>.stride)

        guard let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        // Clear to transparent
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        passDesc.colorAttachments[0].loadAction = .clear

        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            inflightSemaphore.signal()
            return
        }

        // === RENDER ALL EFFECTS ===

        // 1. Rings (shockwaves, halo rings)
        drawRings(encoder: encoder, uniformBuf: uniformBuf)

        // 2. Particles (all types packed into one buffer)
        drawParticles(encoder: encoder, uniformBuf: uniformBuf)

        // 3. Halo gradient glows
        drawHaloGradients(encoder: encoder, uniformBuf: uniformBuf, w: w, h: h)

        // 4. Iris glow (if face detected)
        if state.faceDetected {
            drawIrisGlow(encoder: encoder, uniformBuf: uniformBuf, state: state, w: w, h: h)
        }

        // 5. Beat flash
        if beatPulse > 0.4 {
            encoder.setRenderPipelineState(beatFlashPipeline)
            encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // 6. Vignette (always last)
        encoder.setRenderPipelineState(vignettePipeline)
        encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()

        cmdBuf.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }
        cmdBuf.present(drawable)
        cmdBuf.commit()

        currentBuffer = (currentBuffer + 1) % 3
    }

    // MARK: - Animation State Update (CPU-side)

    private func updateAnimationState(state: JammermanState, engine: AudioEngine, w: Float, h: Float) {
        let energy: Float = state.faceDetected ? 0.1 + state.mouthOpenness * 0.4 : 0
        let bass: Float = state.faceDetected ? 0.05 + state.mouthOpenness * 0.3 : 0

        // Beat detection
        let drumStep = engine.drumStep
        let beatNotMuted = !engine.beatMuted
        let isKickStep = (drumStep % 4 == 0)
        let stepChanged = drumStep != lastDrumStep
        lastDrumStep = drumStep

        if stepChanged && isKickStep && beatNotMuted {
            beatPulse = 1.0
            beatBloomTarget = 1.0
            beatBloomVelocity = 0.25
            // Spawn shockwave
            if rings.count < 20 {
                let cx = faceCx, cy = faceCy - min(w, h) * 0.14 * 0.5
                let r = min(w, h) * 0.54 + energy * 80
                rings.append(MetalRing(radius: 0, alpha: 0.4, speed: 4 + bass * 6, width: 2,
                                  cx: cx, cy: cy, rx: r, ry: r))
            }
        }
        if bass > lastBass * 1.4 && bass > 0.1 && beatPulse < 0.3 {
            beatPulse = max(beatPulse, 0.7)
        }
        lastBass = bass
        beatPulse *= 0.90

        // Beat bloom
        beatBloomRadius += beatBloomVelocity
        beatBloomVelocity += (beatBloomTarget - beatBloomRadius) * 0.15
        beatBloomVelocity *= 0.78
        beatBloomTarget *= 0.94

        // Halo
        haloGlow += (energy * 0.8 + beatPulse * 1.0 - haloGlow) * 0.15
        if beatPulse > 0.7 { haloFlash = 1.0 }
        haloFlash *= 0.82

        // Halo rays → rings for now (simplified)
        if beatPulse > 0.8 && rings.count < 20 {
            let headTopY = faceCy - h * 0.14
            let haloCy = headTopY - min(w, h) * 0.16 * 0.3
            let haloR = min(w, h) * 0.16
            rings.append(MetalRing(radius: haloR + 5, alpha: 0.7 + bass * 0.3,
                              speed: 3.5 + bass * 6, width: 2 + bass * 4,
                              cx: faceCx, cy: haloCy, rx: 1, ry: 0.35))
        }

        geoPhase += 0.003
        ringRotation += 0.5

        // Face position
        if state.faceDetected {
            let tx = state.faceCenterX * w
            let ty = state.faceCenterY * h
            faceCx += (tx - faceCx) * 0.5
            faceCy += (ty - faceCy) * 0.5
        } else if faceCx == 0 {
            faceCx = w / 2
            faceCy = h * 0.35
        }

        // Accent color
        if state.currentModeName != cachedMode {
            cachedMode = state.currentModeName
            updateAccentColor()
        }

        // Update particles
        updateParticles(energy: energy, w: w, h: h)
        updateFaceParticles(state: state, energy: energy, w: w, h: h)
        updateConstellation(state: state, w: w, h: h)
        updateRings()
    }

    // MARK: - Particle Updates

    private func updateParticles(energy: Float, w: Float, h: Float) {
        let baseR = min(w, h) * 0.54
        let radius = baseR + energy * 80 + beatPulse * 30
        let cx = faceCx
        let cy = faceCy - min(w, h) * 0.14 * 0.5

        let spawnCount = energy > 0.02 ? min(5, Int(energy * 12 + beatPulse * 4)) : 0
        for _ in 0..<spawnCount {
            guard particles.count < maxParticles else { break }
            let angle = Float.random(in: 0...(Float.pi * 2))
            particles.append(MetalParticle(
                x: cx + cos(angle) * radius, y: cy + sin(angle) * radius,
                vx: Float.random(in: -0.6...0.6), vy: -Float.random(in: 0.3...1.5),
                life: 1, decay: 0.006 + Float.random(in: 0...0.010),
                size: 1 + Float.random(in: 0...2),
                r: accentR, g: accentG, b: accentB))
        }

        var i = 0
        while i < particles.count {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vy -= 0.01
            particles[i].life -= particles[i].decay
            if particles[i].life <= 0 {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
            } else { i += 1 }
        }
    }

    private func updateFaceParticles(state: JammermanState, energy: Float, w: Float, h: Float) {
        guard state.faceDetected else { return }
        let mouthOpen = state.mouthOpenness
        if mouthOpen > 0.15 {
            let mx = faceCx
            let faceH = h * 0.28
            let my = faceCy + faceH * 0.25
            let count = min(4, Int(mouthOpen * 6 + beatPulse * 3))
            for _ in 0..<count {
                guard faceParticles.count < maxFaceParticles else { break }
                faceParticles.append(MetalParticle(
                    x: mx + Float.random(in: -6...6), y: my,
                    vx: Float.random(in: -1.25...1.25), vy: -Float.random(in: 0.8...3.3),
                    life: 1, decay: 0.015 + Float.random(in: 0...0.015),
                    size: 1 + Float.random(in: 0...2),
                    r: accentR, g: accentG, b: accentB))
            }
        }

        let eyeOpen = state.eyeOpenness
        if eyeOpen > 0.7 {
            let faceW = w * 0.38
            let faceH = h * 0.28
            let eyeY = faceCy - faceH * 0.12
            let spacing = faceW * 0.22
            for eyeX in [faceCx - spacing, faceCx + spacing] {
                guard faceParticles.count < maxFaceParticles else { break }
                let angle = Float.random(in: 0...(Float.pi * 2))
                faceParticles.append(MetalParticle(
                    x: eyeX + Float.random(in: -3...3), y: eyeY + Float.random(in: -3...3),
                    vx: cos(angle) * Float.random(in: 0.5...2), vy: sin(angle) * Float.random(in: 0.5...2) - 0.3,
                    life: 1, decay: 0.02 + Float.random(in: 0...0.015),
                    size: 0.6 + Float.random(in: 0...1.2),
                    r: 1, g: 1, b: 1))
            }
        }

        var i = 0
        while i < faceParticles.count {
            faceParticles[i].x += faceParticles[i].vx
            faceParticles[i].y += faceParticles[i].vy
            faceParticles[i].vy -= 0.03
            faceParticles[i].vx *= 0.98
            faceParticles[i].vy *= 0.98
            faceParticles[i].life -= faceParticles[i].decay
            if faceParticles[i].life <= 0 {
                faceParticles.swapAt(i, faceParticles.count - 1)
                faceParticles.removeLast()
            } else { i += 1 }
        }
    }

    private func updateConstellation(state: JammermanState, w: Float, h: Float) {
        if let note = state.melodyNote, note != lastMelodyNote {
            lastMelodyNote = note
            let root = state.effectiveRoot
            let interval = ((note - root) % 12 + 12) % 12
            let octave = (note - root) / 12
            let angle = Float(interval) / 12.0 * Float.pi * 2 - Float.pi / 2
            let baseDist = min(w, h) * 0.12
            let dist = baseDist + Float(octave) * 25
            let cx = w / 2, cy = h * 0.38
            constellationNotes.append(MetalConstellationNote(
                x: cx + cos(angle) * dist, y: cy + sin(angle) * dist,
                life: 1, decay: 0.003 + Float.random(in: 0...0.002),
                size: 2.5 + Float.random(in: 0...1.5), brightness: 1))
            if constellationNotes.count > 48 { constellationNotes.removeFirst() }
        }
        if state.melodyNote == nil { lastMelodyNote = nil }

        var i = 0
        while i < constellationNotes.count {
            constellationNotes[i].life -= constellationNotes[i].decay
            constellationNotes[i].brightness *= 0.997
            if constellationNotes[i].life <= 0 {
                constellationNotes.swapAt(i, constellationNotes.count - 1)
                constellationNotes.removeLast()
            } else { i += 1 }
        }
    }

    private func updateRings() {
        var i = 0
        while i < rings.count {
            rings[i].radius += rings[i].speed
            rings[i].alpha *= 0.94
            rings[i].speed *= 0.98
            if rings[i].alpha < 0.005 {
                rings.swapAt(i, rings.count - 1)
                rings.removeLast()
            } else { i += 1 }
        }
    }

    // MARK: - GPU Drawing

    private func drawParticles(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer) {
        // Pack all particle types into one GPU buffer
        var gpuParticles: [GPUParticle] = []
        gpuParticles.reserveCapacity(particles.count + faceParticles.count + constellationNotes.count + burstParticles.count)

        for p in particles {
            let a = p.life * p.life * 0.5
            gpuParticles.append(GPUParticle(
                position: SIMD2(p.x, p.y), size: max(p.size * 3, 2),
                life: p.life, color: SIMD4(p.r, p.g, p.b, a)))
        }
        for p in faceParticles {
            let a = p.life * p.life * 0.6
            gpuParticles.append(GPUParticle(
                position: SIMD2(p.x, p.y), size: max(p.size * 2.5, 1.5),
                life: p.life, color: SIMD4(p.r, p.g, p.b, a)))
        }
        for n in constellationNotes {
            let a = n.life * n.life * 0.6
            gpuParticles.append(GPUParticle(
                position: SIMD2(n.x, n.y), size: n.size * (2 + n.brightness),
                life: n.life, color: SIMD4(accentR, accentG, accentB, a)))
        }
        for p in burstParticles {
            let a = p.life * p.life * 0.5
            gpuParticles.append(GPUParticle(
                position: SIMD2(p.x, p.y), size: max(p.size * 2, 1),
                life: p.life, color: SIMD4(p.r, p.g, p.b, a)))
        }

        guard !gpuParticles.isEmpty else { return }

        let bufSize = MemoryLayout<GPUParticle>.stride * gpuParticles.count
        guard let particleBuf = device.makeBuffer(bytes: &gpuParticles, length: bufSize, options: .storageModeShared) else { return }

        encoder.setRenderPipelineState(particlePipeline)
        encoder.setVertexBuffer(particleBuf, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuf, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: gpuParticles.count)
    }

    private func drawRings(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer) {
        guard !rings.isEmpty else { return }

        var gpuEllipses: [GPUEllipse] = []
        for ring in rings {
            let r = ring.radius
            let rxScale: Float = ring.rx > 0.01 ? ring.rx : 1
            let ryScale: Float = ring.ry > 0.01 ? ring.ry : 1
            gpuEllipses.append(GPUEllipse(
                center: SIMD2(ring.cx, ring.cy),
                radii: SIMD2(r * rxScale, r * ryScale),
                lineWidth: ring.width * ring.alpha + 0.5,
                color: SIMD4(accentR, accentG, accentB, ring.alpha)))
        }

        let bufSize = MemoryLayout<GPUEllipse>.stride * gpuEllipses.count
        guard let ellipseBuf = device.makeBuffer(bytes: &gpuEllipses, length: bufSize, options: .storageModeShared) else { return }

        encoder.setRenderPipelineState(ellipsePipeline)
        encoder.setVertexBuffer(ellipseBuf, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuf, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: gpuEllipses.count)
    }

    private func drawHaloGradients(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, w: Float, h: Float) {
        guard haloGlow > 0.01 else { return }

        let headTopY = faceCy - h * 0.14
        let haloCy = headTopY - min(w, h) * 0.16 * 0.3
        let haloR = min(w, h) * 0.16

        // Ambient glow
        var params = GPUGradientParams(
            center: SIMD2(faceCx, haloCy),
            innerRadius: 0,
            outerRadius: haloR * 3.5 + haloGlow * 120,
            innerColor: SIMD4(accentR, accentG, accentB, min(0.4, haloGlow * 0.35 + haloFlash * 0.15)),
            outerColor: SIMD4(accentR, accentG, accentB, 0))

        encoder.setRenderPipelineState(gradientPipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<GPUGradientParams>.stride, index: 0)
        encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Flash burst
        if haloFlash > 0.1 {
            params.outerRadius = haloR * 2.5 + haloFlash * 60
            params.innerColor = SIMD4(1, 1, 1, haloFlash * 0.35)
            params.outerColor = SIMD4(1, 1, 1, 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout<GPUGradientParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    private func drawIrisGlow(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, state: JammermanState, w: Float, h: Float) {
        let faceW = w * 0.38
        let faceH = h * 0.28
        let eyeY = faceCy - faceH * 0.12
        let spacing = faceW * 0.22
        let pulseScale: Float = 1.0 + uniforms.energy * 1.2 + beatPulse * 1.8
        let r = 10 * pulseScale
        let baseAlpha = min(1.0, 0.35 + uniforms.energy * 0.5 + beatPulse * 0.4)

        for eyeX in [faceCx - spacing, faceCx + spacing] {
            var params = GPUGradientParams(
                center: SIMD2(eyeX, eyeY),
                innerRadius: 0,
                outerRadius: r * 4,
                innerColor: SIMD4(1, 1, 1, baseAlpha * 0.85),
                outerColor: SIMD4(accentR, accentG, accentB, 0))

            encoder.setRenderPipelineState(gradientPipeline)
            encoder.setFragmentBytes(&params, length: MemoryLayout<GPUGradientParams>.stride, index: 0)
            encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    // MARK: - Accent Color

    private func updateAccentColor() {
        let map: [String: (Float, Float, Float)] = [
            "lydian": (0.973, 0.573, 0.235),
            "ionian": (0.984, 0.749, 0.141),
            "mixolydian": (0.204, 0.827, 0.600),
            "dorian": (0.133, 0.827, 0.933),
            "aeolian": (0.506, 0.549, 0.973),
            "phrygian": (0.655, 0.545, 0.984),
        ]
        if let c = map[cachedMode] {
            accentR = c.0; accentG = c.1; accentB = c.2
        } else {
            accentR = 0.133; accentG = 0.827; accentB = 0.933
        }
    }
}
