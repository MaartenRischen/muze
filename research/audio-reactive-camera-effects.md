# Audio-Reactive Camera Effects for Muze

## Architecture Overview

Muze's rendering stack (bottom to top):
1. `<video id="cam">` -- camera feed, CSS `transform: scaleX(-1)`, z-index 0
2. `<canvas id="bg-canvas">` -- segmented foreground (BgBlur), z-index 1
3. `<canvas id="overlay">` -- Canvas 2D visualizer ring + particles, z-index 1
4. DOM overlays -- `#riser-overlay`, `#beat-repeat-overlay`, HUD, toolbar

**Key constraint:** The camera feed is a `<video>` element under a `<canvas>`. We cannot use `getImageData/putImageData` on the video at 60fps on mobile -- that path costs 15-30ms per frame on iPhone due to GPU-to-CPU readback and alpha premultiplication. Instead, all effects must use one of:
- **CSS filters** on the `<video>` or `<canvas>` elements (GPU-accelerated, zero JS cost)
- **CSS overlays** with pointer-events:none (composited by the GPU)
- **Canvas 2D drawing** on the existing overlay canvas (already in the render loop)
- **CSS transforms** on wrapper elements (GPU-composited, no layout reflow)

**Never do:** `getImageData()` per frame, WebGL readback of video pixels, or per-pixel R/G/B channel manipulation on full-frame ImageData.

---

## Available Audio Data (Already Implemented)

From `visualizer.js` draw() method, these are computed every frame:

```
bass     -- float, 0-1, average of FFT bins 0-10%
mid      -- float, 0-1, average of FFT bins 10-40%
high     -- float, 0-1, average of FFT bins 40-100%
energy   -- float, 0-1, average absolute waveform value
_beatPulse -- float, 0-1, decays at 0.92/frame, set to 1.0 on detected beat
```

Beat detection already exists:
```js
if (fft && bass > this._lastBass * 1.5 && bass > 0.15) {
  this._beatPulse = 1.0;
}
```

Riser state available from: `MUZE.State.riserActive` (boolean)
Drop event: `MUZE.Audio.dropRiser()` is called from `ui.js` line 61

Mode name: `MUZE.State.currentModeName` (string, e.g. 'phrygian', 'lydian')
Mode colors: `MUZE.Config.MODE_COLORS[modeName].accent` and `.rgb`

---

## Effect 1: Beat Flash

**What:** On kick hits, the entire screen briefly flashes white at 5% opacity for ~50ms.

**Implementation: CSS overlay (zero Canvas cost)**

This should NOT be done on the overlay canvas because clearing and redrawing a full-screen rect every frame wastes fill rate. Instead, use a dedicated CSS overlay element.

### HTML (add to index.html)
```html
<div id="beat-flash-overlay"></div>
```

### CSS (add to style.css)
```css
#beat-flash-overlay {
  position: fixed;
  top: 0; left: 0; width: 100%; height: 100%;
  z-index: 2;
  pointer-events: none;
  background: white;
  opacity: 0;
  will-change: opacity;
  transition: opacity 0.02s linear;
}
#beat-flash-overlay.flash {
  opacity: 0.05;
}
```

### JS (add to visualizer.js, inside draw())
```js
// After beat detection block
if (this._beatPulse >= 0.95) {
  // Trigger CSS flash
  const flashEl = this._beatFlashEl || (this._beatFlashEl = document.getElementById('beat-flash-overlay'));
  if (flashEl) {
    flashEl.classList.add('flash');
    clearTimeout(this._beatFlashTimeout);
    this._beatFlashTimeout = setTimeout(() => flashEl.classList.remove('flash'), 50);
  }
}
```

### Performance
- **Cost:** 0ms JS. The browser composites the overlay with GPU. `will-change: opacity` ensures it's on its own compositor layer.
- **Mobile:** No measurable impact. CSS opacity transitions are GPU-composited on all iOS/Android devices.
- **Battery:** Negligible -- the layer is transparent 99% of the time and the compositor skips it.

### Tuning
- Change `0.05` opacity for intensity (0.03 = barely perceptible, 0.08 = noticeable)
- Change `50` ms timeout for duration (30ms = snappier, 80ms = more visible)
- For accent-colored flash instead of white: `background: rgba(var(--muze-accent-rgb), 0.08)`

---

## Effect 2: Edge Glow / Vignette Pulse

**What:** A vignette darkens the edges of the screen. It pulses with bass energy -- darker on quiet, lighter on loud. The vignette color tints toward the current mode accent.

**Implementation: CSS radial-gradient overlay + JS style update**

### HTML
```html
<div id="vignette-overlay"></div>
```

### CSS
```css
#vignette-overlay {
  position: fixed;
  top: 0; left: 0; width: 100%; height: 100%;
  z-index: 2;
  pointer-events: none;
  will-change: opacity;
  /* Default vignette -- overridden by JS */
  background: radial-gradient(
    ellipse at 50% 50%,
    transparent 40%,
    rgba(0, 0, 0, 0.6) 100%
  );
}
```

### JS (in visualizer.js, add to draw())
```js
// Vignette pulse -- update every frame (cheap: just sets one CSS property)
if (!this._vignetteEl) this._vignetteEl = document.getElementById('vignette-overlay');
if (this._vignetteEl) {
  // Bass drives vignette intensity: quiet = dark edges, loud = lighter edges
  const vignetteOpacity = 0.7 - bass * 0.4; // range: 0.7 (quiet) to 0.3 (loud bass)
  // Accent tint at edges
  const tintAlpha = 0.05 + bass * 0.1; // subtle accent bleed
  this._vignetteEl.style.background = `radial-gradient(
    ellipse at 50% 50%,
    transparent 40%,
    rgba(${accentRgb}, ${tintAlpha}) 70%,
    rgba(0, 0, 0, ${vignetteOpacity}) 100%
  )`;
}
```

### Performance
- **Cost:** ~0.1ms. Setting `style.background` triggers a repaint but NOT a reflow (no geometry change). The gradient is rasterized by the GPU.
- **Optimization:** Throttle to every 2nd or 3rd frame if needed:
  ```js
  if (this._vignetteFrame++ % 2 === 0) { /* update */ }
  ```
- **Mobile:** Radial gradients are hardware-accelerated on iOS Safari and Chrome. No issues at 60fps.

### Tuning
- `transparent 40%` controls how far the clear center extends (30% = more vignette, 50% = less)
- The `vignetteOpacity` range (0.7 to 0.3) controls dynamic range
- `tintAlpha` (0.05 to 0.15) controls accent bleed -- keep subtle

---

## Effect 3: Chromatic Aberration on Drop

**What:** When the riser drops, briefly shift R/G/B channels apart for a glitch effect. 3-5px offset for 200ms, then settle back.

**Implementation: CSS filter + transform on separate layers (NOT pixel manipulation)**

The critical insight: per-pixel channel shifting via `getImageData` is far too expensive at 60fps on mobile (15-30ms). Instead, we use a clever CSS trick: stack 3 copies of the content with color channel isolation using `mix-blend-mode` and offset them with `transform: translate`.

However, that's complex for a camera feed. The **simplest performant approach** is using CSS `filter` on the bg-canvas element, combined with an SVG filter for channel separation.

### Approach A: SVG Filter (Best Quality)

Add an inline SVG filter to index.html:
```html
<svg style="position:absolute;width:0;height:0">
  <defs>
    <filter id="chromatic-aberration">
      <feOffset in="SourceGraphic" dx="0" dy="0" result="red">
        <animate attributeName="dx" values="0;4;0" dur="0.2s" begin="indefinite" id="ca-anim" fill="freeze"/>
      </feOffset>
      <feOffset in="SourceGraphic" dx="0" dy="0" result="blue">
        <animate attributeName="dx" values="0;-4;0" dur="0.2s" begin="indefinite" id="ca-anim-b" fill="freeze"/>
      </feOffset>
      <!-- ... complex, not recommended for mobile -->
    </filter>
  </defs>
</svg>
```

This is complex. Better approach:

### Approach B: Triple-Layer CSS Trick (Recommended)

Create 3 overlay divs that show the same content with color channel isolation via CSS `mix-blend-mode`, offset on drop.

**Actually, the simplest and most performant approach for Muze:**

### Approach C: CSS filter: blur + hue-rotate flash (Pragmatic)

On drop, apply a brief CSS filter to the `#bg-canvas` element that mimics chromatic aberration:

```css
#bg-canvas.chromatic-glitch {
  filter: blur(1px) contrast(1.2);
  animation: chromatic-shift 200ms ease-out forwards;
}

@keyframes chromatic-shift {
  0% {
    filter: blur(2px) contrast(1.5) saturate(2);
    transform: scaleX(-1) scale(1.02);
  }
  30% {
    filter: blur(1px) contrast(1.3) saturate(1.5);
    transform: scaleX(-1) scale(1.01);
  }
  100% {
    filter: none;
    transform: scaleX(-1) scale(1);
  }
}
```

### Approach D: Canvas 2D Overlay Simulation (Best Visual Fidelity)

Draw colored offset rectangles on the overlay canvas with `globalCompositeOperation`:

```js
// In visualizer.js -- only active for ~200ms after drop
_chromaticTimer: 0,

triggerChromaticAberration() {
  this._chromaticTimer = 200; // ms
},

// Inside draw(), after clearing:
if (this._chromaticTimer > 0) {
  const dt = 16; // approximate frame time
  this._chromaticTimer -= dt;
  const intensity = this._chromaticTimer / 200; // 1.0 -> 0.0
  const offset = Math.round(intensity * 5); // 5px -> 0px

  ctx.save();
  ctx.globalCompositeOperation = 'screen';

  // Red channel shift (left)
  ctx.fillStyle = `rgba(255, 0, 0, ${0.03 * intensity})`;
  ctx.fillRect(-offset, 0, w, h);

  // Blue channel shift (right)
  ctx.fillStyle = `rgba(0, 0, 255, ${0.03 * intensity})`;
  ctx.fillRect(offset, 0, w, h);

  ctx.restore();
}
```

### Hook into dropRiser

In `audio.js` `dropRiser()` or in `ui.js` where `MUZE.Audio.dropRiser()` is called, add:
```js
MUZE.Visualizer.triggerChromaticAberration();
```

### Performance
- Approach C (CSS): 0ms JS cost. GPU-composited animation. Best for mobile.
- Approach D (Canvas): <0.5ms. Two `fillRect` calls with `screen` blend. Very cheap.
- Both approaches avoid `getImageData` entirely.

### Recommendation
Use **Approach C (CSS animation on #bg-canvas)** for the camera feed glitch, PLUS **Approach D (Canvas overlay)** for the colored fringing on top. Together they create a convincing chromatic aberration without any pixel manipulation.

---

## Effect 4: Camera Color Grade by Mode

**What:** Shift the camera feed's hue/saturation based on the current musical mode. Phrygian = cool blue tint, Lydian = warm gold tint. Very subtle.

**Implementation: CSS filter on #bg-canvas (GPU-accelerated)**

### Mode-to-Filter Mapping

| Mode | Hue Shift | Saturation | Brightness | Vibe |
|------|-----------|------------|------------|------|
| phrygian | -20deg | 85% | 90% | Cool, mysterious blue-violet |
| aeolian | -12deg | 90% | 92% | Slightly cool, melancholic |
| dorian | 0deg | 100% | 95% | Neutral, natural |
| mixolydian | 8deg | 105% | 98% | Slightly warm |
| ionian | 15deg | 110% | 100% | Warm, bright |
| lydian | 25deg | 115% | 102% | Warm gold, dreamy |

### JS Implementation

```js
// In config.js, add to MODE_COLORS:
MODE_COLOR_GRADES: {
  phrygian:    { hue: -20, sat: 85,  bright: 90 },
  aeolian:     { hue: -12, sat: 90,  bright: 92 },
  dorian:      { hue: 0,   sat: 100, bright: 95 },
  mixolydian:  { hue: 8,   sat: 105, bright: 98 },
  ionian:      { hue: 15,  sat: 110, bright: 100 },
  lydian:      { hue: 25,  sat: 115, bright: 102 },
  // Extra scales
  'pent. major':   { hue: 10,  sat: 108, bright: 100 },
  'pent. minor':   { hue: -15, sat: 88,  bright: 92 },
  'harm. minor':   { hue: -18, sat: 82,  bright: 88 },
  'whole tone':    { hue: 20,  sat: 120, bright: 105 },
  'blues':         { hue: -8,  sat: 95,  bright: 94 },
  'melodic minor': { hue: -10, sat: 92,  bright: 93 },
  'phrygian dom':  { hue: 18,  sat: 105, bright: 96 },
  'hirajoshi':     { hue: -25, sat: 80,  bright: 88 },
},
```

### Apply in Visualizer

```js
// Cache the filter string and only update on mode change (not every frame)
_cachedColorGrade: '',
_cachedGradeMode: '',

// Inside draw(), after mode color caching:
if (currentMode !== this._cachedGradeMode) {
  this._cachedGradeMode = currentMode;
  const grade = MUZE.Config.MODE_COLOR_GRADES[currentMode];
  if (grade) {
    this._cachedColorGrade = `hue-rotate(${grade.hue}deg) saturate(${grade.sat}%) brightness(${grade.bright}%)`;
  } else {
    this._cachedColorGrade = '';
  }
  // Apply to bg-canvas (the segmented foreground)
  const bgCanvas = document.getElementById('bg-canvas');
  if (bgCanvas) bgCanvas.style.filter = this._cachedColorGrade;
}
```

### Performance
- **Cost:** 0ms per frame (only updates on mode change, not every frame).
- **GPU:** CSS `filter` with `hue-rotate`, `saturate`, and `brightness` are all GPU-composited on iOS Safari. They do NOT trigger layout or paint -- only composite.
- **Subtlety:** The values above are deliberately subtle. A 20-degree hue shift is barely perceptible but creates an unconscious mood shift. Users will "feel" the difference without consciously seeing a color change.

### Important Note on #bg-canvas
The `#bg-canvas` already has `transform: scaleX(-1)` for mirror mode. CSS filters compose with transforms without conflict. The filter is applied during the composite stage, after the transform.

If BgBlur is not active (no segmentation), apply the same filter to `#cam` instead:
```js
const target = (MUZE.BgBlur && MUZE.BgBlur._ready)
  ? document.getElementById('bg-canvas')
  : document.getElementById('cam');
target.style.filter = this._cachedColorGrade;
```

---

## Effect 5: Bass Warp (Radial Lens Pulse)

**What:** On strong bass hits, apply a subtle radial distortion -- the center of the screen briefly "breathes" outward like a lens pulse.

**Implementation: CSS transform scale pulse on the camera layer**

Per-pixel radial distortion (like a barrel/pincushion warp) requires either WebGL or `getImageData` -- both too expensive on mobile for a single transient effect. The performant alternative: a CSS `scale()` transform that briefly enlarges the center of the camera feed by 2-3%, then settles back. This creates a convincing "lens pulse" because:
1. The scale originates from center (default `transform-origin: 50% 50%`)
2. At 2% scale, only the edges of the frame are visibly clipped
3. The elastic ease-out gives an organic "breathing" feel

### CSS
```css
#bg-canvas {
  /* existing */
  transition: transform 0.15s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

@keyframes bass-warp {
  0% { transform: scaleX(-1) scale(1.025); }
  40% { transform: scaleX(-1) scale(1.008); }
  100% { transform: scaleX(-1) scale(1); }
}

#bg-canvas.bass-warping {
  animation: bass-warp 250ms ease-out forwards;
}
```

### JS (in visualizer.js)
```js
_lastBassWarpTime: 0,

// Inside draw(), after beat detection:
if (this._beatPulse >= 0.95 && bass > 0.25) {
  const now = performance.now();
  if (now - this._lastBassWarpTime > 300) { // cooldown: max 3 warps/sec
    this._lastBassWarpTime = now;
    const bgCanvas = document.getElementById('bg-canvas');
    bgCanvas.classList.remove('bass-warping');
    // Force reflow to restart animation
    void bgCanvas.offsetWidth;
    bgCanvas.classList.add('bass-warping');
    setTimeout(() => bgCanvas.classList.remove('bass-warping'), 250);
  }
}
```

### Performance
- **Cost:** 0ms JS per frame. The CSS animation runs on the compositor thread.
- **Mobile:** CSS transform animations with `will-change: transform` are composited on the GPU on all modern mobile browsers. Zero main-thread cost.
- **Note:** The `scaleX(-1)` must be preserved in the animation because it provides the mirror effect. All keyframes must include it.

### Alternative: Canvas Overlay Approach
If you want a more dramatic "lens" look without affecting the camera:

```js
// Draw a brief radial "shock ring" on the overlay canvas
if (this._bassWarpTimer > 0) {
  this._bassWarpTimer -= 16;
  const progress = 1 - this._bassWarpTimer / 200;
  const ringRadius = progress * Math.min(w, h) * 0.5;
  const ringAlpha = (1 - progress) * 0.08;

  ctx.beginPath();
  ctx.strokeStyle = `rgba(255, 255, 255, ${ringAlpha})`;
  ctx.lineWidth = 20 * (1 - progress);
  ctx.arc(w / 2, h / 2, ringRadius, 0, Math.PI * 2);
  ctx.stroke();
}
```

This draws an expanding ring from the center that fades out -- looks like a sonar/shockwave pulse.

### Recommendation
Use BOTH: the CSS scale pulse on #bg-canvas for the "lens breathe" feel, and the Canvas ring for a visible shockwave. Together they cost <0.5ms total.

---

## Effect 6: Particle Explosion on Riser Drop

**What:** When the riser drops (hold + swipe up), emit 100+ particles from center in all directions, fading over 1 second.

**Implementation: Canvas 2D particles (extend existing particle system)**

The existing `_particles` array in visualizer.js already handles spawning, updating, and drawing particles. We add a separate `_explosionParticles` array for burst events to avoid conflicting with the ambient particle system. This keeps the ambient particle cap at 40 while allowing up to 150 explosion particles that self-destruct in ~1 second.

### JS Implementation

```js
// Add to MUZE.Visualizer:
_explosionParticles: [],

triggerExplosion(x, y, count, accentRgb) {
  // x, y: center point (default: screen center)
  // count: number of particles (default: 120)
  x = x || this._width / 2;
  y = y || this._height * 0.4;
  count = count || 120;
  const rgb = accentRgb || this._cachedAccentRgb;

  for (let i = 0; i < count; i++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = 2 + Math.random() * 8; // varied speeds for natural look
    const size = 1 + Math.random() * 3;
    this._explosionParticles.push({
      x: x,
      y: y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed - 1, // slight upward bias
      life: 1.0,
      decay: 0.012 + Math.random() * 0.008, // die in 50-80 frames (~1s)
      size: size,
      rgb: rgb,
      gravity: 0.04 + Math.random() * 0.02, // slight gravity pull
      drag: 0.98, // air resistance
    });
  }
},

// Inside draw(), after main particle drawing:
_updateAndDrawExplosion(ctx) {
  for (let i = this._explosionParticles.length - 1; i >= 0; i--) {
    const p = this._explosionParticles[i];

    // Physics
    p.x += p.vx;
    p.y += p.vy;
    p.vx *= p.drag;
    p.vy *= p.drag;
    p.vy += p.gravity; // gravity
    p.life -= p.decay;

    if (p.life <= 0) {
      // O(1) removal
      this._explosionParticles[i] = this._explosionParticles[this._explosionParticles.length - 1];
      this._explosionParticles.pop();
      continue;
    }

    // Draw
    const alpha = p.life * p.life; // quadratic falloff
    ctx.beginPath();
    ctx.fillStyle = `rgba(${p.rgb}, ${alpha * 0.7})`;
    ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
    ctx.fill();
  }
},
```

### Hook into draw()

```js
// At end of draw() method, before closing brace:
this._updateAndDrawExplosion(ctx);
```

### Hook into dropRiser

In `ui.js`, inside the `_onEnd` method where `MUZE.Audio.dropRiser()` is called:
```js
if (dy < -MUZE.Config.SWIPE_THRESHOLD) {
  MUZE.Audio.dropRiser();
  MUZE.Visualizer.triggerExplosion(); // <-- add this
  MUZE.Visualizer.triggerChromaticAberration(); // <-- and this
}
```

### Performance Analysis

| Particles | Draw calls | Estimated cost (iPhone 13) |
|-----------|-----------|---------------------------|
| 50 | 50 arc() + fill() | ~0.3ms |
| 100 | 100 arc() + fill() | ~0.6ms |
| 150 | 150 arc() + fill() | ~0.8ms |
| 200 | 200 arc() + fill() | ~1.1ms |

120 particles is the sweet spot: visually impressive, costs <0.7ms, and only for ~1 second.

### Optimization: Batch Drawing

For even better performance, batch particles by color and draw as a single path:
```js
ctx.beginPath();
ctx.fillStyle = `rgba(${rgb}, 0.5)`;
for (const p of this._explosionParticles) {
  if (p.life <= 0) continue;
  ctx.moveTo(p.x + p.size * p.life, p.y);
  ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
}
ctx.fill(); // single fill call for all particles
```

This reduces from 120 draw calls to 1, saving ~40% overhead.

### Visual Enhancement: Trail Effect

For a more dramatic explosion, add brief trails:
```js
// Before drawing particles, draw a low-opacity version of last frame
// by NOT clearing that region (partial clear)
// Or: draw each particle with a "tail" line from previous position
ctx.beginPath();
ctx.strokeStyle = `rgba(${p.rgb}, ${alpha * 0.3})`;
ctx.lineWidth = p.size * p.life * 0.5;
ctx.moveTo(p.x - p.vx * 2, p.y - p.vy * 2);
ctx.lineTo(p.x, p.y);
ctx.stroke();
```

---

## Combined Integration Plan

### New HTML Elements (add to index.html, after existing overlays)

```html
<!-- Audio-reactive visual effects -->
<div id="beat-flash-overlay"></div>
<div id="vignette-overlay"></div>
```

### New CSS (add to style.css)

```css
/* ---- Beat Flash ---- */
#beat-flash-overlay {
  position: fixed;
  top: 0; left: 0; width: 100%; height: 100%;
  z-index: 2;
  pointer-events: none;
  background: white;
  opacity: 0;
  will-change: opacity;
}

/* ---- Vignette Pulse ---- */
#vignette-overlay {
  position: fixed;
  top: 0; left: 0; width: 100%; height: 100%;
  z-index: 2;
  pointer-events: none;
  will-change: opacity;
  background: radial-gradient(
    ellipse at 50% 50%,
    transparent 40%,
    rgba(0, 0, 0, 0.6) 100%
  );
}

/* ---- Bass Warp ---- */
@keyframes bass-warp {
  0% { transform: scaleX(-1) scale(1.025); }
  40% { transform: scaleX(-1) scale(1.008); }
  100% { transform: scaleX(-1) scale(1); }
}
#bg-canvas.bass-warping {
  animation: bass-warp 250ms ease-out forwards;
}

/* ---- Chromatic Aberration ---- */
@keyframes chromatic-shift {
  0% {
    filter: blur(2px) contrast(1.5) saturate(2);
    transform: scaleX(-1) scale(1.02);
  }
  30% {
    filter: blur(1px) contrast(1.3) saturate(1.5);
    transform: scaleX(-1) scale(1.01);
  }
  100% {
    filter: none;
    transform: scaleX(-1) scale(1);
  }
}
#bg-canvas.chromatic-glitch {
  animation: chromatic-shift 200ms ease-out forwards;
}
```

### Visualizer.js Additions

New properties:
```js
_beatFlashEl: null,
_beatFlashTimeout: null,
_vignetteEl: null,
_vignetteFrame: 0,
_explosionParticles: [],
_chromaticTimer: 0,
_lastBassWarpTime: 0,
_cachedGradeMode: '',
_cachedColorGrade: '',
```

New methods:
```js
triggerExplosion(x, y, count) { /* as above */ },
triggerChromaticAberration() { /* as above */ },
_updateAndDrawExplosion(ctx) { /* as above */ },
```

Additions to draw():
```js
// After beat detection block (~line 89):
// 1. Beat flash
if (this._beatPulse >= 0.95) { /* beat flash logic */ }

// 2. Bass warp
if (this._beatPulse >= 0.95 && bass > 0.25) { /* bass warp logic */ }

// 3. Vignette pulse (every 2nd frame)
if (this._vignetteFrame++ % 2 === 0) { /* vignette logic */ }

// 4. Color grade (only on mode change)
if (currentMode !== this._cachedGradeMode) { /* color grade logic */ }

// 5. Chromatic aberration overlay (Canvas)
if (this._chromaticTimer > 0) { /* chromatic overlay logic */ }

// At end of draw():
// 6. Explosion particles
this._updateAndDrawExplosion(ctx);
```

### UI.js Hook (dropRiser)

```js
// In _onEnd, where dropRiser is called:
if (dy < -MUZE.Config.SWIPE_THRESHOLD) {
  MUZE.Audio.dropRiser();
  if (MUZE.Visualizer.triggerExplosion) MUZE.Visualizer.triggerExplosion();
  if (MUZE.Visualizer.triggerChromaticAberration) MUZE.Visualizer.triggerChromaticAberration();
}
```

---

## Performance Budget Summary

| Effect | Technique | Per-frame cost | Frequency |
|--------|-----------|---------------|-----------|
| Beat flash | CSS opacity toggle | 0ms | On beat (~2-4/sec) |
| Vignette pulse | CSS gradient update | ~0.1ms | Every 2nd frame |
| Chromatic aberration | CSS animation + Canvas overlay | 0ms CSS + 0.2ms Canvas | On drop only (~1/min) |
| Color grade | CSS filter (once per mode change) | 0ms | On mode change |
| Bass warp | CSS transform animation | 0ms | On strong beats (~1-2/sec) |
| Particle explosion | Canvas 2D arc + fill | ~0.7ms | On drop only (~1/min), decays to 0 in 1s |
| **Total worst case** | | **~1.0ms** | |

Current visualizer draw() costs ~1-2ms. Adding all six effects brings worst case to ~3ms, well within the 16.6ms frame budget.

---

## Sources

- [CanvasRenderingContext2D: filter property (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/filter)
- [Canvas Chromatic Aberration (GitHub)](https://github.com/TomasHubelbauer/canvas-chromatic-aberration)
- [Chromatic Aberration Algorithm (GitHub Gist)](https://gist.github.com/lqt0223/8a258b68ae1c032fa1fb1e26c4965e8d)
- [hue-rotate() CSS function (MDN)](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/filter-function/hue-rotate)
- [Improving HTML5 Canvas Performance (web.dev)](https://web.dev/canvas-performance/)
- [globalCompositeOperation (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/globalCompositeOperation)
- [CRT Scanlines Effect with CSS](https://aleclownes.com/2017/02/01/crt-display.html)
- [CSS Shake Animation (CSS-Tricks)](https://css-tricks.com/snippets/css/shake-css-keyframe-animation/)
- [fisheye.js - Radial Lens Distortion (GitHub)](https://github.com/ericleong/fisheye.js/tree/master)
- [Explosion Animation in Canvas (GeeksforGeeks)](https://www.geeksforgeeks.org/explosion-animation-in-canvas/)
- [Drawing Pixels is Hard - Canvas Performance (PhobosLab)](https://phoboslab.org/log/2012/09/drawing-pixels-is-hard)
- [Audio-Reactive Camera Filter (GitHub - ts-camera-filter)](https://github.com/defcronyke/ts-camera-filter)
- [Webcam Audio Visualizer with Three.js (Codrops)](https://tympanus.net/codrops/2019/09/06/how-to-create-a-webcam-audio-visualizer-with-three-js/)
