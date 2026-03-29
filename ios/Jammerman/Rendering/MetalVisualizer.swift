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

struct GPULineVertex {
    var position: SIMD2<Float>
    var normal: SIMD2<Float>
    var alpha: Float
}

struct GPUSegParams {
    var offset: SIMD2<Float> = .zero
    var scale: SIMD2<Float> = SIMD2(0.63, 0.99)
    var edgeLow: Float = 0.25
    var edgeHigh: Float = 0.75
    var darkenAlpha: Float = 0.65
    var maskFlipX: Float = 0
    var feather: Float = -8.0
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
    private var trailFadePipeline: MTLRenderPipelineState!
    private var trailCompositePipeline: MTLRenderPipelineState!
    private var segDarkenPipeline: MTLRenderPipelineState!

    // Trail offscreen textures (ping-pong)
    private var trailTextureA: MTLTexture?
    private var trailTextureB: MTLTexture?
    private var trailUseA = true
    private var prevHandPos: SIMD2<Float>?
    private var handGlowRadius: Float = 8
    private var handGlowTarget: Float = 8

    // Segmentation texture + tunable params (public for dev UI)
    private var segTexture: MTLTexture?
    var segParams = GPUSegParams()

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

    // Waveform ring points (recomputed each frame)
    private var ringPoints: [SIMD2<Float>] = []

    // Display scale (retina multiplier — sizes in points need to be × this)
    private var displayScale: Float = 3.0

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
        print("[Metal] Initializing MetalVisualizer on \(device.name)")
        buildPipelines()
        buildBuffers()
        print("[Metal] Init complete — pipelines: particle=\(particlePipeline != nil) line=\(linePipeline != nil) gradient=\(gradientPipeline != nil) ellipse=\(ellipsePipeline != nil) vignette=\(vignettePipeline != nil) flash=\(beatFlashPipeline != nil)")
    }

    // MARK: - Pipeline Setup

    private var drawCount = 0

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("[Metal] FATAL: Failed to create default library — .metal file not in bundle?")
            return
        }
        print("[Metal] Library loaded with \(library.functionNames)")

        // Log errors instead of silently failing with try?
        func makePipeline(_ desc: MTLRenderPipelineDescriptor, name: String) -> MTLRenderPipelineState? {
            do {
                let state = try device.makeRenderPipelineState(descriptor: desc)
                return state
            } catch {
                print("[Metal] PIPELINE ERROR (\(name)): \(error)")
                return nil
            }
        }

        func makeDesc(vertex: String, fragment: String, additive: Bool) -> MTLRenderPipelineDescriptor {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            if desc.vertexFunction == nil { print("[Metal] MISSING vertex function: \(vertex)") }
            if desc.fragmentFunction == nil { print("[Metal] MISSING fragment function: \(fragment)") }
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            if additive {
                desc.colorAttachments[0].sourceRGBBlendFactor = .one
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                desc.colorAttachments[0].sourceAlphaBlendFactor = .one
                desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            } else {
                desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                desc.colorAttachments[0].sourceAlphaBlendFactor = .one
                desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return desc
        }

        particlePipeline = makePipeline(makeDesc(vertex: "particleVertex", fragment: "particleFragment", additive: true), name: "particle")
        ellipsePipeline = makePipeline(makeDesc(vertex: "ellipseVertex", fragment: "ellipseFragment", additive: true), name: "ellipse")
        gradientPipeline = makePipeline(makeDesc(vertex: "fullscreenQuadVertex", fragment: "radialGradientFragment", additive: true), name: "gradient")
        linePipeline = makePipeline(makeDesc(vertex: "lineVertex", fragment: "lineFragment", additive: true), name: "line")
        vignettePipeline = makePipeline(makeDesc(vertex: "fullscreenQuadVertex", fragment: "vignetteFragment", additive: false), name: "vignette")
        beatFlashPipeline = makePipeline(makeDesc(vertex: "fullscreenQuadVertex", fragment: "beatFlashFragment", additive: true), name: "beatFlash")
        trailCompositePipeline = makePipeline(makeDesc(vertex: "fullscreenQuadVertex", fragment: "trailCompositeFragment", additive: true), name: "trailComposite")
        segDarkenPipeline = makePipeline(makeDesc(vertex: "fullscreenQuadVertex", fragment: "segDarkenFragment", additive: false), name: "segDarken")

        // Trail fade uses standard alpha blend writing to offscreen texture
        let fadePipeDesc = makeDesc(vertex: "fullscreenQuadVertex", fragment: "trailFadeFragment", additive: false)
        trailFadePipeline = makePipeline(fadePipeDesc, name: "trailFade")
    }

    private func buildBuffers() {
        // Triple-buffered uniform buffers
        for _ in 0..<3 {
            let buf = device.makeBuffer(length: MemoryLayout<VisualizerUniforms>.stride, options: .storageModeShared)!
            uniformBuffers.append(buf)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        displayScale = Float(view.contentScaleFactor)
    }

    func draw(in view: MTKView) {
        guard let coord = coordinator else { print("[Metal] draw: no coordinator"); return }
        drawCount += 1
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

        // === PRE-PASSES (before main encoder) ===
        updateTrailTexture(cmdBuf: cmdBuf, uniformBuf: uniformBuf, state: state, w: w, h: h)
        updateSegTexture(state: state)

        // === MAIN RENDER PASS ===
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        passDesc.colorAttachments[0].loadAction = .clear

        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            inflightSemaphore.signal()
            return
        }

        // 0. Background darken via segmentation (if available)
        if let segTex = segTexture {
            encoder.setRenderPipelineState(segDarkenPipeline)
            encoder.setFragmentTexture(segTex, index: 0)
            encoder.setFragmentBytes(&segParams, length: MemoryLayout<GPUSegParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // 1. Mode geometry
        drawModeGeometry(encoder: encoder, uniformBuf: uniformBuf, w: w, h: h)

        // 2. Waveform ring
        drawWaveformRing(encoder: encoder, uniformBuf: uniformBuf, w: w, h: h)

        // 3. Rings (shockwaves, halo rings)
        drawRings(encoder: encoder, uniformBuf: uniformBuf)

        // 4. Halo gradient glows
        drawHaloGradients(encoder: encoder, uniformBuf: uniformBuf, w: w, h: h)

        // 5. Frequency arc
        drawFrequencyArc(encoder: encoder, uniformBuf: uniformBuf, w: w, h: h)

        // 6. Particles
        drawParticles(encoder: encoder, uniformBuf: uniformBuf)

        // 7. Hand trail composite (from offscreen texture)
        if let trailTex = trailUseA ? trailTextureA : trailTextureB {
            encoder.setRenderPipelineState(trailCompositePipeline)
            encoder.setFragmentTexture(trailTex, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // 8. Face effects
        if state.faceDetected {
            drawIrisGlow(encoder: encoder, uniformBuf: uniformBuf, state: state, w: w, h: h)
            drawLandmarkLights(encoder: encoder, uniformBuf: uniformBuf, state: state, w: w, h: h)
        }

        // 9. Connection web
        drawConnectionWeb(encoder: encoder, uniformBuf: uniformBuf, state: state, w: w, h: h)

        // 10. Beat flash
        if beatPulse > 0.4 {
            encoder.setRenderPipelineState(beatFlashPipeline)
            encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // 11. Vignette
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
                position: SIMD2(p.x, p.y), size: max(p.size * 3 * displayScale, 4),
                life: p.life, color: SIMD4(p.r, p.g, p.b, a)))
        }
        for p in faceParticles {
            let a = p.life * p.life * 0.6
            gpuParticles.append(GPUParticle(
                position: SIMD2(p.x, p.y), size: max(p.size * 2.5 * displayScale, 3),
                life: p.life, color: SIMD4(p.r, p.g, p.b, a)))
        }
        for n in constellationNotes {
            let a = n.life * n.life * 0.6
            gpuParticles.append(GPUParticle(
                position: SIMD2(n.x, n.y), size: n.size * (2 + n.brightness) * displayScale,
                life: n.life, color: SIMD4(accentR, accentG, accentB, a)))
        }
        for p in burstParticles {
            let a = p.life * p.life * 0.5
            gpuParticles.append(GPUParticle(
                position: SIMD2(p.x, p.y), size: max(p.size * 2 * displayScale, 3),
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
                lineWidth: (ring.width * ring.alpha + 0.5) * displayScale,
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
            innerColor: SIMD4(accentR, accentG, accentB, min(0.35, haloGlow * 0.25 + haloFlash * 0.15)),
            outerColor: SIMD4(accentR, accentG, accentB, 0))

        encoder.setRenderPipelineState(gradientPipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<GPUGradientParams>.stride, index: 0)
        encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Flash burst
        if haloFlash > 0.1 {
            params.outerRadius = haloR * 2.5 + haloFlash * 60
            params.innerColor = SIMD4(1, 1, 1, haloFlash * 0.3)
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
        let baseAlpha = min(0.5, 0.2 + uniforms.energy * 0.2 + beatPulse * 0.15)

        for eyeX in [faceCx - spacing, faceCx + spacing] {
            var params = GPUGradientParams(
                center: SIMD2(eyeX, eyeY),
                innerRadius: 0,
                outerRadius: r * 3,
                innerColor: SIMD4(1, 1, 1, baseAlpha),
                outerColor: SIMD4(accentR, accentG, accentB, 0))

            encoder.setRenderPipelineState(gradientPipeline)
            encoder.setFragmentBytes(&params, length: MemoryLayout<GPUGradientParams>.stride, index: 0)
            encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    // MARK: - Waveform Ring

    private func computeRingPoints(cx: Float, cy: Float, radius: Float, energy: Float, w: Float, h: Float) {
        ringPoints.removeAll(keepingCapacity: true)
        let segments = 128
        let wobbleAmount = energy * 40 + beatPulse * 25
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let angle = t * Float.pi * 2 + ringRotation * Float.pi / 180
            let wobble = sin(angle * 4 + geoPhase * 8) * wobbleAmount +
                         sin(angle * 7 + geoPhase * 5) * wobbleAmount * 0.5
            let r = radius + wobble
            ringPoints.append(SIMD2(cx + cos(angle) * r, cy + sin(angle) * r))
        }
    }

    private func drawWaveformRing(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, w: Float, h: Float) {
        let energy = uniforms.energy
        let baseR = min(w, h) * 0.18
        let radius = baseR + energy * 80 + beatPulse * 30
        let cx = faceCx
        let cy = faceCy - min(w, h) * 0.14 * 0.5

        computeRingPoints(cx: cx, cy: cy, radius: radius, energy: energy, w: w, h: h)
        guard ringPoints.count > 2 else { return }

        // Multi-pass neon glow
        let passes: [(Float, Float, SIMD4<Float>)] = [
            (14, 0.05 + beatPulse * 0.03,  SIMD4(accentR, accentG, accentB, 1)),
            (6,  0.12 + beatPulse * 0.05,  SIMD4(accentR, accentG, accentB, 1)),
            (2.5, 0.25 + energy * 0.15,    SIMD4(accentR, accentG, accentB, 1)),
            (1,  0.5 + energy * 0.2,       SIMD4(1, 1, 1, 1)),
        ]

        for (lineWidth, alpha, baseColor) in passes {
            let color = SIMD4<Float>(baseColor.x, baseColor.y, baseColor.z, alpha)
            drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: ringPoints,
                         lineWidth: lineWidth, color: color, closed: true)
        }
    }

    // MARK: - Face Contour Glow

    private func drawFaceContours(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, state: JammermanState, w: Float, h: Float) {
        guard state.faceDetected else { return }
        let energy = uniforms.energy

        // Synthesize face contour from face center position
        let faceRx = w * 0.19
        let faceRy = h * 0.14

        // Face oval (32 points)
        var oval: [SIMD2<Float>] = []
        for i in 0..<32 {
            let a = Float(i) / 32.0 * Float.pi * 2
            oval.append(SIMD2(faceCx + cos(a) * faceRx, faceCy + sin(a) * faceRy))
        }

        // Eyes
        let eyeY = faceCy - faceRy * 0.43
        let eyeSpacing = faceRx * 0.58
        let eyeW = faceRx * 0.29
        let eyeH = faceRy * 0.06 + state.eyeOpenness * faceRy * 0.04
        for ecx in [faceCx - eyeSpacing, faceCx + eyeSpacing] {
            var eye: [SIMD2<Float>] = []
            for i in 0..<16 {
                let a = Float(i) / 16.0 * Float.pi * 2
                eye.append(SIMD2(ecx + cos(a) * eyeW, eyeY + sin(a) * eyeH))
            }
            // 3-pass glow for eyes
            drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: eye,
                         lineWidth: 6, color: SIMD4(accentR, accentG, accentB, 0.06 + energy * 0.03), closed: true)
            drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: eye,
                         lineWidth: 2, color: SIMD4(accentR, accentG, accentB, 0.15 + energy * 0.1), closed: true)
            drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: eye,
                         lineWidth: 0.8, color: SIMD4(1, 1, 1, 0.2 + energy * 0.15), closed: true)
        }

        // Mouth
        let lipW = faceRx * 0.58
        let lipY = faceCy + faceRy * 0.54
        let mouthOpen = state.mouthOpenness * faceRy * 0.15
        var mouth: [SIMD2<Float>] = []
        for i in 0..<16 {
            let a = Float(i) / 16.0 * Float.pi * 2
            mouth.append(SIMD2(faceCx + cos(a) * lipW, lipY + sin(a) * (lipW * 0.3 + mouthOpen * 0.5)))
        }

        // Brows
        let browY = eyeY - faceRy * 0.18 - state.browHeight * 10
        let browSpread = faceRx * 0.74
        let leftBrow: [SIMD2<Float>] = [
            SIMD2(faceCx - browSpread, browY + 3),
            SIMD2(faceCx - browSpread * 0.5, browY),
            SIMD2(faceCx - browSpread * 0.15, browY + 3)]
        let rightBrow: [SIMD2<Float>] = [
            SIMD2(faceCx + browSpread * 0.15, browY + 3),
            SIMD2(faceCx + browSpread * 0.5, browY),
            SIMD2(faceCx + browSpread, browY + 3)]

        // 3-pass neon glow for face oval
        let contours: [([SIMD2<Float>], Bool)] = [
            (oval, true), (mouth, true), (leftBrow, false), (rightBrow, false)
        ]
        let glowPasses: [(Float, Float)] = [(10, 0.04 + energy * 0.02), (4, 0.12 + energy * 0.06), (1.2, 0.3 + energy * 0.15)]
        for (points, closed) in contours {
            for (lw, alpha) in glowPasses {
                drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: points,
                             lineWidth: lw, color: SIMD4(accentR, accentG, accentB, alpha), closed: closed)
            }
        }
    }

    // MARK: - Connection Web (hand to face)

    private func drawConnectionWeb(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, state: JammermanState, w: Float, h: Float) {
        guard state.faceDetected, state.handPresent else { return }
        let handScreenX = state.handX * w
        let handScreenY = state.handY * h
        let energy = uniforms.energy

        // Target points on face
        let faceRy = h * 0.14
        let targets: [SIMD2<Float>] = [
            SIMD2(faceCx, faceCy - faceRy * 0.5),   // forehead
            SIMD2(faceCx, faceCy + faceRy * 0.5),   // chin
            SIMD2(faceCx, faceCy),                    // nose
        ]

        let webAlpha: Float = 0.15 + energy * 0.15 + beatPulse * 0.1
        for target in targets {
            let line = [SIMD2(handScreenX, handScreenY), target]
            drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: line,
                         lineWidth: 1.5, color: SIMD4(accentR, accentG, accentB, webAlpha), closed: false)
        }
    }

    // MARK: - Mode Geometry (faint background patterns)

    private func drawModeGeometry(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, w: Float, h: Float) {
        let modeIdx: Int
        switch cachedMode {
        case "phrygian", "aeolian": modeIdx = 0
        case "dorian", "mixolydian": modeIdx = 1
        case "ionian", "lydian": modeIdx = 2
        default: modeIdx = 1
        }

        let alpha: Float = 0.02
        let color = SIMD4<Float>(accentR, accentG, accentB, alpha)
        let cx = w / 2, cy = h * 0.38

        switch modeIdx {
        case 0: // Angular shards — few radiating lines
            for i in 0..<8 {
                let angle = Float(i) / 8.0 * Float.pi * 2 + geoPhase
                let len = min(w, h) * 0.3 + sin(geoPhase * 3 + Float(i)) * 30
                let line = [SIMD2(cx, cy), SIMD2(cx + cos(angle) * len, cy + sin(angle) * len)]
                drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: line,
                             lineWidth: 0.5, color: color, closed: false)
            }
        case 1: // Hex lattice — just a few rings around center (not full grid!)
            for ring in 1...3 {
                for i in 0..<(6 * ring) {
                    let side = i / ring
                    let pos = i % ring
                    let dirs: [(Float, Float)] = [(1,0),(0.5,0.866),(-0.5,0.866),(-1,0),(-0.5,-0.866),(0.5,-0.866)]
                    let d1 = dirs[side % 6]
                    let d2 = dirs[(side + 1) % 6]
                    let t = Float(pos) / Float(ring)
                    let hx = cx + (d1.0 * Float(ring) + (d2.0 - d1.0) * Float(pos)) * 50
                    let hy = cy + (d1.1 * Float(ring) + (d2.1 - d1.1) * Float(pos)) * 50
                    let hexR: Float = 6 + sin(geoPhase * 2 + Float(ring + i) * 0.3) * 2
                    var hex: [SIMD2<Float>] = []
                    for s in 0..<6 {
                        let a = Float(s) / 6.0 * Float.pi * 2 + geoPhase * 0.5
                        hex.append(SIMD2(hx + cos(a) * hexR, hy + sin(a) * hexR))
                    }
                    drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: hex,
                                 lineWidth: 0.3, color: color, closed: true)
                }
            }
        default: // Flowing curves — orbiting ellipses
            for i in 0..<4 {
                let angle = Float(i) / 4.0 * Float.pi * 2 + geoPhase * 0.8
                let dist = min(w, h) * (0.12 + Float(i) * 0.04)
                var curve: [SIMD2<Float>] = []
                for j in 0..<24 {
                    let t = Float(j) / 24.0 * Float.pi * 2
                    let rx = dist * (0.6 + sin(geoPhase + Float(i)) * 0.2)
                    let ry = dist * (0.3 + cos(geoPhase * 0.7 + Float(i)) * 0.15)
                    curve.append(SIMD2(cx + cos(t + angle) * rx, cy + sin(t + angle) * ry))
                }
                drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: curve,
                             lineWidth: 0.4, color: color, closed: true)
            }
        }
    }

    // MARK: - Frequency Arc

    private func drawFrequencyArc(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, w: Float, h: Float) {
        let energy = uniforms.energy
        guard energy > 0.01 else { return }

        let barCount = 32
        let arcCx = w / 2
        let arcCy = h * 0.92
        let arcR = w * 0.4
        let barW: Float = 4
        let maxBarH: Float = 40

        for i in 0..<barCount {
            let t = Float(i) / Float(barCount - 1) - 0.5
            let angle = t * 0.8 - Float.pi / 2
            let val = (sin(Float(i) * 0.4 + geoPhase * 6) * 0.5 + 0.5) * energy * 2
            let barH = val * maxBarH
            guard barH > 1 else { continue }

            let bx = arcCx + cos(angle) * arcR
            let by = arcCy + sin(angle) * arcR

            let line = [SIMD2(bx, by), SIMD2(bx, by - barH)]
            let barAlpha = min(1.0, val * 0.8 + 0.1)
            drawPolyline(encoder: encoder, uniformBuf: uniformBuf, points: line,
                         lineWidth: barW, color: SIMD4(accentR, accentG, accentB, barAlpha), closed: false)
        }
    }

    // MARK: - Landmark Lights

    private func drawLandmarkLights(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer, state: JammermanState, w: Float, h: Float) {
        guard state.faceDetected else { return }
        let energy = uniforms.energy
        let faceRx = w * 0.19
        let faceRy = h * 0.14

        let keyPoints: [SIMD2<Float>] = [
            SIMD2(faceCx, faceCy - faceRy * 0.5),                     // forehead
            SIMD2(faceCx, faceCy + faceRy * 0.5),                     // chin
            SIMD2(faceCx, faceCy + faceRy * 0.2),                     // nose tip
            SIMD2(faceCx - faceRx * 0.58, faceCy - faceRy * 0.43),   // left eye
            SIMD2(faceCx + faceRx * 0.58, faceCy - faceRy * 0.43),   // right eye
            SIMD2(faceCx - faceRx * 0.58, faceCy - faceRy * 0.6),    // left brow
            SIMD2(faceCx + faceRx * 0.58, faceCy - faceRy * 0.6),    // right brow
            SIMD2(faceCx - faceRx * 0.3, faceCy + faceRy * 0.54),    // left mouth
            SIMD2(faceCx + faceRx * 0.3, faceCy + faceRy * 0.54),    // right mouth
        ]

        let r: Float = 5 + energy * 12 + beatPulse * 15
        let alpha = min(0.4, 0.15 + energy * 0.15 + beatPulse * 0.2)

        for pt in keyPoints {
            var params = GPUGradientParams(
                center: pt, innerRadius: 0, outerRadius: r,
                innerColor: SIMD4(accentR, accentG, accentB, alpha),
                outerColor: SIMD4(accentR, accentG, accentB, 0))
            encoder.setRenderPipelineState(gradientPipeline)
            encoder.setFragmentBytes(&params, length: MemoryLayout<GPUGradientParams>.stride, index: 0)
            encoder.setFragmentBuffer(uniformBuf, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    // MARK: - Hand Trail (offscreen texture with persistence)

    private func ensureTrailTextures(w: Int, h: Int) {
        if trailTextureA == nil || trailTextureA!.width != w || trailTextureA!.height != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            trailTextureA = device.makeTexture(descriptor: desc)
            trailTextureB = device.makeTexture(descriptor: desc)
            prevHandPos = nil
        }
    }

    private func updateTrailTexture(cmdBuf: MTLCommandBuffer, uniformBuf: MTLBuffer, state: JammermanState, w: Float, h: Float) {
        let iw = Int(w), ih = Int(h)
        guard iw > 0, ih > 0 else { return }
        ensureTrailTextures(w: iw, h: ih)

        let src = trailUseA ? trailTextureA! : trailTextureB!
        let dst = trailUseA ? trailTextureB! : trailTextureA!

        // Pass 1: Fade — read src, write to dst with alpha decay
        let fadePass = MTLRenderPassDescriptor()
        fadePass.colorAttachments[0].texture = dst
        fadePass.colorAttachments[0].loadAction = .clear
        fadePass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        fadePass.colorAttachments[0].storeAction = .store

        if let fadeEnc = cmdBuf.makeRenderCommandEncoder(descriptor: fadePass) {
            fadeEnc.setRenderPipelineState(trailFadePipeline)
            fadeEnc.setFragmentTexture(src, index: 0)
            fadeEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            // Pass 2: Draw new trail segment (same encoder, additive)
            if state.handPresent {
                let px = state.handX * w
                let py = state.handY * h

                handGlowTarget = state.handOpen ? 20 * displayScale : 8 * displayScale
                handGlowRadius += (handGlowTarget - handGlowRadius) * 0.3

                if let prev = prevHandPos {
                    let dx = px - prev.x, dy = py - prev.y
                    if dx * dx + dy * dy > 1 {
                        // Draw glowing line from prev to current
                        let line = [prev, SIMD2(px, py)]
                        // Core bright line
                        var col = SIMD4<Float>(accentR, accentG, accentB, 0.8)
                        var lw = 3 * displayScale
                        fadeEnc.setRenderPipelineState(linePipeline)

                        // Build line vertices inline
                        var verts = buildLineVertices(points: line, closed: false)
                        let bufSize = MemoryLayout<GPULineVertex>.stride * verts.count
                        if let vBuf = device.makeBuffer(bytes: &verts, length: bufSize, options: .storageModeShared) {
                            fadeEnc.setVertexBuffer(vBuf, offset: 0, index: 0)
                            fadeEnc.setVertexBuffer(uniformBuf, offset: 0, index: 1)
                            fadeEnc.setVertexBytes(&lw, length: 4, index: 2)
                            fadeEnc.setFragmentBytes(&col, length: 16, index: 0)
                            fadeEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: verts.count)
                        }

                        // Wider glow line
                        lw = handGlowRadius
                        col = SIMD4(accentR, accentG, accentB, 0.15)
                        if let vBuf = device.makeBuffer(bytes: &verts, length: bufSize, options: .storageModeShared) {
                            fadeEnc.setVertexBytes(&lw, length: 4, index: 2)
                            fadeEnc.setFragmentBytes(&col, length: 16, index: 0)
                            fadeEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: verts.count)
                        }
                    }
                }
                prevHandPos = SIMD2(px, py)
            } else {
                prevHandPos = nil
            }

            fadeEnc.endEncoding()
        }

        trailUseA.toggle()
    }

    /// Build line vertices without drawing (for offscreen trail pass)
    private func buildLineVertices(points: [SIMD2<Float>], closed: Bool) -> [GPULineVertex] {
        guard points.count >= 2 else { return [] }
        var vertices: [GPULineVertex] = []
        vertices.reserveCapacity(points.count * 2 + (closed ? 2 : 0))
        let count = points.count
        for i in 0..<count {
            let curr = points[i]
            let next = points[(i + 1) % count]
            let prev = points[(i - 1 + count) % count]
            let d1 = simd_normalize(next - curr)
            let d0 = simd_normalize(curr - prev)
            var tangent = simd_normalize(d0 + d1)
            if simd_length(tangent) < 0.001 { tangent = d1 }
            let normal = SIMD2<Float>(-tangent.y, tangent.x)
            vertices.append(GPULineVertex(position: curr, normal: normal, alpha: 1))
            vertices.append(GPULineVertex(position: curr, normal: normal, alpha: 1))
        }
        if closed && vertices.count >= 2 {
            vertices.append(vertices[0])
            vertices.append(vertices[1])
        }
        return vertices
    }

    // MARK: - Person Segmentation (GPU texture from CGImage mask)

    private func updateSegTexture(state: JammermanState) {
        guard let maskCG = state.segmentationMask else {
            segTexture = nil
            return
        }
        // Only recreate if dimensions changed or texture is nil
        let mw = maskCG.width, mh = maskCG.height
        if segTexture == nil || segTexture!.width != mw || segTexture!.height != mh {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: mw, height: mh, mipmapped: false)
            desc.usage = .shaderRead
            segTexture = device.makeTexture(descriptor: desc)
        }
        guard let tex = segTexture,
              let data = maskCG.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return }
        let bytesPerRow = maskCG.bytesPerRow
        tex.replace(region: MTLRegionMake2D(0, 0, mw, mh), mipmapLevel: 0,
                    withBytes: bytes, bytesPerRow: bytesPerRow)
    }

    // MARK: - Line Tessellation Utility

    /// Converts a polyline into GPU LineVertex pairs with extruded normals
    private func drawPolyline(encoder: MTLRenderCommandEncoder, uniformBuf: MTLBuffer,
                              points: [SIMD2<Float>], lineWidth: Float, color: SIMD4<Float>, closed: Bool) {
        guard points.count >= 2 else { return }

        var vertices: [GPULineVertex] = []
        vertices.reserveCapacity(points.count * 2 + (closed ? 2 : 0))

        let count = points.count
        for i in 0..<count {
            let curr = points[i]
            let next = points[(i + 1) % count]
            let prev = points[(i - 1 + count) % count]

            // Average direction for smooth normals at joints
            let d1 = simd_normalize(next - curr)
            let d0 = simd_normalize(curr - prev)
            var tangent = simd_normalize(d0 + d1)
            if simd_length(tangent) < 0.001 { tangent = d1 }
            let normal = SIMD2<Float>(-tangent.y, tangent.x)

            // Two vertices per point (extruded left and right)
            vertices.append(GPULineVertex(position: curr, normal: normal, alpha: 1))
            vertices.append(GPULineVertex(position: curr, normal: normal, alpha: 1))
        }

        // Close the loop
        if closed && vertices.count >= 2 {
            vertices.append(vertices[0])
            vertices.append(vertices[1])
        }

        let bufSize = MemoryLayout<GPULineVertex>.stride * vertices.count
        guard let vertBuf = device.makeBuffer(bytes: &vertices, length: bufSize, options: .storageModeShared) else { return }
        var lw = lineWidth * displayScale
        var col = color

        encoder.setRenderPipelineState(linePipeline)
        encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuf, offset: 0, index: 1)
        encoder.setVertexBytes(&lw, length: MemoryLayout<Float>.stride, index: 2)
        encoder.setFragmentBytes(&col, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
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
