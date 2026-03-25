# Muze Visualizer Audit & Upgrade Plan

## Current State Assessment

### What We Have (visualizer.js)
The current visualizer is a **Canvas 2D** implementation with three visual elements:

1. **Circular Waveform Ring** — Time-domain waveform wrapped around a circle at ~38% screen height, with an outer glow ring that appears when energy exceeds a threshold.
2. **Floating Particles** — Up to 40 particles spawned from the ring perimeter based on audio energy, with upward drift and quadratic opacity falloff.
3. **Bottom Frequency Bars** — 32 bars derived from the waveform (not true FFT), drawn at the bottom of the screen in turquoise.

### Audio Data Available
- `Tone.Analyser('waveform', 256)` — time-domain waveform only (256 samples).
- No FFT/frequency analyser node exists. The "frequency bars" are actually time-domain waveform samples reinterpreted as bar heights.
- Single scalar `energy` computed as average absolute waveform value — no separation of bass/mid/high bands.

### Honest Verdict: Basic

The current visualizer is functional but **basic by modern standards**. Here is why:

| Dimension | Current | Industry Standard |
|---|---|---|
| Rendering | Canvas 2D | WebGL / GLSL shaders |
| Audio analysis | Single energy scalar from waveform | Multi-band FFT, onset detection, beat tracking |
| Particle count | 40 (CPU-managed) | 10,000-100,000+ (GPU compute) |
| Visual complexity | 1 ring + bars + dots | Layered shaders, bloom, noise fields, 3D geometry |
| Color mapping | Static mode color (accent RGB) | Dynamic palette from mood/valence/energy |
| Camera integration | None (overlay canvas sits above video) | Face mesh overlays, hand trails, AR effects |
| Frame budget | ~2-4ms on desktop, fine; but no GPU acceleration | <1ms for shader-based approaches |

The waveform ring is aesthetically coherent with the minimal UI, but it does not create the "wow" factor that top music visualizers achieve.

---

## What Makes Visualizers Stunning: Techniques from the Best

### 1. Multi-Band Frequency Analysis (Prerequisite)

Every impressive music visualizer separates audio into frequency bands. This is the single most impactful upgrade.

**Implementation:**
```js
// Add a second analyser for FFT
this._fftAnalyser = new Tone.Analyser('fft', 512);
this._limiter.connect(this._fftAnalyser);

// In visualizer, extract bands:
const fft = MUZE.Audio.getFFT(); // new method
const bass = average(fft, 0, 8);      // 0-200 Hz
const lowMid = average(fft, 8, 24);   // 200-600 Hz
const mid = average(fft, 24, 80);     // 600-2kHz
const highMid = average(fft, 80, 160); // 2-5kHz
const high = average(fft, 160, 256);  // 5-20kHz
```

Each band then drives different visual parameters:
- **Bass** → ring radius pulse, particle burst, camera shake
- **Low-mid** → ring thickness, background color warmth
- **Mid** → waveform amplitude, particle speed
- **High-mid** → particle sparkle, ring glow intensity
- **High** → fine detail, shimmer effects

### 2. Beat Detection and Onset Detection

Rather than smooth energy following, detect discrete events:
- **Beat:** sudden energy spike in bass band (kick drum)
- **Onset:** transient in any band (snare, hat)

```js
// Simple beat detector
const bassNow = getBassEnergy();
const bassAvg = smoothedBassAvg;
if (bassNow > bassAvg * 1.5 && timeSinceLastBeat > 200) {
  onBeat(); // trigger visual event
}
```

**Visual responses to beats:**
- Ring "punch" — sudden 20% radius expansion with elastic decay
- Particle burst — spawn 50-100 particles in a radial explosion
- Background flash — brief white/accent flash (2 frames)
- Camera zoom pulse — subtle 2% scale pulse on the video feed
- Color shift — momentary hue rotation

### 3. GPU-Accelerated Particles via WebGL

The current CPU particle system tops out at 40 particles. GPU particles can handle 50,000+ at 60fps on mobile.

**Approach: Instanced rendering or transform feedback**

Using a simple WebGL2 approach with transform feedback:
- Particle positions/velocities stored in GPU buffers
- Vertex shader updates positions each frame (no CPU round-trip)
- Fragment shader renders with additive blending for glow
- Audio uniforms (bass, mid, high, energy) passed as uniforms

For Muze, the simplest path is **a secondary WebGL canvas layered on top** (or below) the existing 2D canvas, so the HUD and UI remain Canvas 2D.

### 4. GLSL Fragment Shader Backgrounds

Full-screen shader effects running on a quad. These are what make Shadertoy visualizations look magical.

**Specific effects that suit Muze's aesthetic:**
- **Perlin/simplex noise fields** — organic flowing color gradients that respond to energy and valence
- **Voronoi patterns** — cellular structures that pulse with bass
- **Raymarched shapes** — 3D-looking spheres/toruses rendered in a fragment shader
- **Feedback/trail effects** — previous frame blended with current for motion blur

**Audio-to-shader uniform mapping:**
```glsl
uniform float u_bass;      // 0-1
uniform float u_mid;       // 0-1
uniform float u_high;      // 0-1
uniform float u_energy;    // 0-1
uniform float u_valence;   // -1 to 1 (lip corner)
uniform float u_time;      // elapsed seconds
uniform vec3 u_accent;     // mode color as vec3

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  // Noise field warped by bass
  float n = snoise(uv * 3.0 + u_time * 0.1 + u_bass * 0.5);
  // Color from accent + valence shift
  vec3 col = u_accent * (0.3 + n * 0.4 + u_energy * 0.3);
  // Pulse on beat
  col += u_bass * 0.15;
  gl_FragColor = vec4(col, 0.4);
}
```

### 5. Bloom and Glow Post-Processing

A bloom pass makes bright elements "bleed" light, giving everything a premium feel.

**Implementation (WebGL):**
1. Render scene to framebuffer
2. Extract bright pixels (threshold pass)
3. Gaussian blur the bright pixels (2-pass separable)
4. Composite: `finalColor = scene + bloom * bloomStrength`

This single effect transforms flat circles into luminous orbs.

### 6. Color Mapping Based on Musical Context

Muze already has `MODE_COLORS` mapping scales to accent colors. This can be deepened:

**Valence-to-color continuous mapping:**
- Negative valence (phrygian/aeolian) → cool palette: deep purples, blues
- Neutral valence (dorian) → balanced: teals, cyans
- Positive valence (lydian/ionian) → warm palette: golds, oranges

**Energy-to-saturation mapping:**
- Low energy → desaturated, dark
- High energy → vivid, bright

**Research-backed cross-modal correspondences:**
- Low pitch → larger visual elements, darker colors
- High pitch → smaller/finer elements, brighter colors
- Fast tempo → sharp angular shapes
- Slow tempo → smooth flowing forms

**Implementation:** Interpolate between two palettes (cool/warm) based on `lipCorner` valence, then modulate saturation by energy.

---

## Should We Switch to WebGL?

### Recommendation: Hybrid Approach (Keep Canvas 2D + Add WebGL Layer)

**Do NOT rip out Canvas 2D.** Instead, add a WebGL layer behind or alongside it.

**Rationale:**
- Canvas 2D is fine for the HUD overlay, waveform ring, and UI elements (low element count, no performance issue).
- WebGL is needed for: GPU particles (thousands), shader backgrounds, bloom post-processing.
- On mobile, Canvas 2D actually starts up faster (~15ms vs ~40ms for WebGL context) and uses less battery for simple draws.
- The benchmarks show Canvas 2D wins for < 3,000-5,000 elements. The waveform ring (256 points) and 40 particles are well within that.

**Architecture:**
```
Layer stack (bottom to top):
  1. <video> — camera feed (already exists)
  2. <canvas id="bg-canvas"> — segmented foreground (already exists)
  3. <canvas id="gl-canvas"> — NEW: WebGL shader background + GPU particles
  4. <canvas id="overlay"> — EXISTING: Canvas 2D waveform ring + UI overlays
  5. DOM — HUD, buttons, controls
```

The WebGL canvas handles the heavy visual lifting (shader backgrounds, particle systems, bloom), while the existing Canvas 2D handles precise line drawing (waveform ring) and the UI overlay.

### Performance Budget (Mobile)

Target: **60fps on iPhone 12+ / mid-range Android (2022+)**

| Component | Budget |
|---|---|
| MediaPipe face/hand detection | ~10ms (every 33ms) |
| Background segmentation | ~8ms (every 33ms) |
| WebGL shader + particles | ~3ms |
| Canvas 2D overlay | ~1ms |
| Audio processing | ~1ms |
| **Total** | **~23ms** (leaves 10ms headroom in 33ms frame) |

Key: run MediaPipe and shader on different frames (alternate). Reduce particle count on low-end devices. Use `requestAnimationFrame` timing to detect drops and reduce quality dynamically.

---

## Camera Overlay Effects

Muze already has face tracking (MediaPipe Face Landmarker with 468 landmarks) and hand tracking. These are currently used only for audio control. They can also drive visual effects.

### 1. Face Mesh Glow Overlay

Draw the face mesh triangles on the overlay canvas, colored by the current mode accent, with opacity driven by energy.

**Implementation:**
```js
// MediaPipe gives us 468 landmarks
// FACE_MESH_TESSELATION gives us triangle indices
// Draw each triangle with accent color, low alpha
const landmarks = fr.faceLandmarks[0];
ctx.strokeStyle = `rgba(${accentRgb}, ${0.05 + energy * 0.15})`;
ctx.lineWidth = 0.5;
for (const [i, j] of FACE_MESH_CONNECTIONS) {
  ctx.beginPath();
  ctx.moveTo(landmarks[i].x * w, landmarks[i].y * h);
  ctx.lineTo(landmarks[j].x * w, landmarks[j].y * h);
  ctx.stroke();
}
```

This gives a subtle "digital face" overlay that pulses with the music. Currently the face landmarker runs with `outputFaceBlendshapes: false` — we could enable it selectively for richer face overlays.

**Cost:** The landmarks are already computed. Drawing ~900 line segments in Canvas 2D costs <1ms.

### 2. Hand Trail Effects

Track hand position history and draw a trailing ribbon.

**Implementation:**
```js
// Store last N hand positions
this._handTrail.push({ x: handX * w, y: handY * h, t: now });
if (this._handTrail.length > 30) this._handTrail.shift();

// Draw gradient trail
for (let i = 1; i < this._handTrail.length; i++) {
  const age = (now - this._handTrail[i].t) / 1000;
  const alpha = Math.max(0, 0.6 - age * 2);
  const width = (1 - age * 2) * 4;
  ctx.beginPath();
  ctx.strokeStyle = `rgba(${accentRgb}, ${alpha})`;
  ctx.lineWidth = width;
  ctx.moveTo(this._handTrail[i-1].x, this._handTrail[i-1].y);
  ctx.lineTo(this._handTrail[i].x, this._handTrail[i].y);
  ctx.stroke();
}
```

The trail color could reflect the current note being played — higher notes are brighter, lower notes are deeper.

### 3. Energy Aura Around the Person

Use the existing segmentation mask to create a glow halo around the person that pulses with the music.

**Implementation:**
- Take the segmentation mask edge (dilate mask - original mask = edge)
- Draw it as a colored glow ring around the person's silhouette
- Glow intensity = audio energy, color = accent color

This is very achievable since `BgBlur` already computes and processes the segmentation mask every frame.

### 4. Color Grading Based on Mood/Valence

Apply a CSS filter or Canvas globalCompositeOperation to tint the camera feed based on the current musical mood.

**Implementation (simplest — CSS filter on video):**
```js
const hueShift = valence * 30; // -30 to +30 degrees
const saturation = 80 + energy * 40; // 80-120%
const brightness = 85 + energy * 15; // 85-100%
cam.style.filter = `blur(12px) brightness(${brightness}%) saturate(${saturation}%) hue-rotate(${hueShift}deg)`;
```

For the non-blurred foreground (bg-canvas), apply the same tint via Canvas `globalCompositeOperation: 'color'` or a multiply blend with the accent color.

### 5. Note Visualization on Hand Position

When the hand plays a melody note, show a visual "note bubble" at the hand position that expands and fades.

**Implementation:**
```js
// On note trigger
this._noteBubbles.push({
  x: handX * w, y: handY * h,
  radius: 5, maxRadius: 40,
  alpha: 0.8, note: midiNote
});

// Each frame: expand and fade
for (const b of this._noteBubbles) {
  b.radius += 2;
  b.alpha *= 0.94;
  ctx.beginPath();
  ctx.strokeStyle = `rgba(${accentRgb}, ${b.alpha})`;
  ctx.lineWidth = 2;
  ctx.arc(b.x, b.y, b.radius, 0, Math.PI * 2);
  ctx.stroke();
}
```

---

## Prioritized Upgrade Roadmap

### Phase 1: High Impact, Low Risk (Canvas 2D improvements)
1. **Add FFT analyser** — add `Tone.Analyser('fft', 512)` alongside the existing waveform analyser. Extract bass/mid/high bands. This unlocks everything else.
2. **Beat detection** — simple threshold-based onset detector on the bass band.
3. **Ring beat pulse** — on detected beats, apply elastic radius expansion with spring-back.
4. **Hand trails** — draw trailing ribbon behind hand position when playing melody.
5. **Note bubbles** — expanding ring at hand position on note trigger.
6. **Dynamic color grading** — CSS hue-rotate/saturate on the video feed based on valence and energy.
7. **Energy aura** — glow ring around segmented person using edge of existing mask.

*Estimated effort: 2-3 days. Zero new dependencies. Immediate visual improvement.*

### Phase 2: WebGL Layer (Major Visual Upgrade)
1. **Add WebGL canvas** behind the overlay canvas.
2. **GPU particle system** — 5,000-10,000 particles with additive blending, driven by audio bands.
3. **Shader background** — Perlin noise color field with audio-reactive distortion.
4. **Bloom post-processing** — bright-pass + blur + composite.

*Estimated effort: 4-5 days. New dependency: none (raw WebGL2) or Three.js (~150KB).*

### Phase 3: Advanced Camera Effects
1. **Face mesh overlay** — subtle wireframe over face that glows with energy.
2. **Background replacement options** — shader-generated backgrounds instead of blurred camera.
3. **AR lens-style effects** — particle emitters attached to face landmarks (e.g., sparkles from eyes when energy is high).

*Estimated effort: 3-4 days. Leverages existing MediaPipe data.*

### Phase 4: Polish
1. **Adaptive quality** — detect frame drops and reduce particle count / shader complexity.
2. **Transition animations** — smooth visual transitions when changing modes/presets.
3. **User-selectable visual themes** — minimal (current), particle storm, shader dream, AR overlay.

---

## How the Best Map Audio Features to Visual Parameters

Summary table from research across UBERVIZ, Shadertoy, Chrome Experiments, and Codrops:

| Audio Feature | Visual Parameter | Mapping | Example |
|---|---|---|---|
| Bass energy (0-200Hz) | Scale / size / radius | Direct, with smoothing | Ring radius pulses on kick |
| Bass onset | Discrete burst events | Threshold trigger | Particle explosion on kick |
| Mid energy (200Hz-2kHz) | Color warmth / brightness | Linear | Warmer colors at higher mid energy |
| High energy (2kHz+) | Fine detail / sparkle | Exponential | Tiny particle spawns, shimmer |
| Overall RMS energy | Global opacity / intensity | Direct | Everything brighter when loud |
| Spectral centroid | Hue rotation | Linear map to hue wheel | Bright sounds → yellow, dark → blue |
| Valence (mood) | Color palette selection | Interpolation between palettes | Happy → warm palette, sad → cool |
| Tempo / BPM | Animation speed | Direct | Rotation speed matches BPM |
| Waveform shape | Line/ring displacement | Direct sample mapping | Already implemented in ring |
| Note pitch | Vertical position / size | Logarithmic | Higher notes → higher particles |

---

## Sources

- [Coding a 3D Audio Visualizer with Three.js (Codrops 2025)](https://tympanus.net/codrops/2025/06/18/coding-a-3d-audio-visualizer-with-three-js-gsap-web-audio-api/)
- [UBERVIZ — Custom Audio Reactive Visualizers](https://www.uberviz.io/)
- [Audio-Reactive Particles in Three.js (Codrops)](https://tympanus.net/codrops/2023/12/19/creating-audio-reactive-visuals-with-dynamic-particles-in-three-js/)
- [Audio-Reactive Shaders with Three.js and Shader Park (Codrops)](https://tympanus.net/codrops/2023/02/07/audio-reactive-shaders-with-three-js-and-shader-park/)
- [Audio Shader Studio (GitHub)](https://github.com/sandner-art/Audio-Shader-Studio)
- [WebGL Particle Audio Visualizer (Google Experiments)](https://experiments.withgoogle.com/webgl-particle-audio-visualizer)
- [MDN: Visualizations with Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Visualizations_with_Web_Audio_API)
- [Advanced Audio Analysis for Music Visualization (ciphrd)](https://ciphrd.com/2019/09/01/audio-analysis-for-advanced-music-visualization-pt-1/)
- [SVG vs Canvas vs WebGL Benchmarks 2025](https://www.svggenie.com/blog/svg-vs-canvas-vs-webgl-performance-2025)
- [Canvas 2D vs WebGL Performance (semisignal)](https://semisignal.com/a-look-at-2d-vs-webgl-canvas-performance/)
- [Music Emotion Visualization through Colour (IEEE)](https://ieeexplore.ieee.org/document/9369788/)
- [Cross-Modal Mapping Between Music and Color (eScholarship)](https://escholarship.org/uc/item/7px9h0gg)
- [Snap Camera Kit for AR Effects](https://ar.snap.com/camera-kit)
- [Banuba Face Tracking SDK](https://www.banuba.com/technology/face-tracking-software)
- [Apple ARKit Face Tracking](https://developer.apple.com/documentation/ARKit/tracking-and-visualizing-faces)
- [Google ARCore Augmented Faces](https://developers.google.com/ar/develop/augmented-faces)
- [Particle Systems in Audio Reactive Visuals](https://audioreactivevisuals.com/particle-systems.html)
- [How to Write a Web-Based Music Visualizer (WebGL2 Fundamentals)](https://webgl2fundamentals.org/webgl/lessons/webgl-qna-how-to-write-a-web-based-music-visualizer.html)
- [Real-Time Music Visualization Study (Ohio State)](https://accad.osu.edu/sites/accad.osu.edu/files/real-time-music-visualization.pdf)
