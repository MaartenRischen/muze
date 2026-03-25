# Face Mesh AR Effects for Muze — Research & Implementation Guide

## Context

Muze uses MediaPipe Face Landmarker outputting 468 `{x, y, z}` landmarks (normalized 0–1) via `fr.faceLandmarks[0]`. The overlay canvas is `window.innerWidth × window.innerHeight`, camera is mirrored (`scaleX(-1)` on the video). The visualizer already draws to a Canvas 2D context on `#overlay`. Audio data (waveform, FFT, bass/mid/high energy, beat pulse) is already computed per frame in `MUZE.Visualizer.draw()`.

---

## Landmark Index Reference (Key Points)

These are the indices into the 468-point array for the features we care about:

```js
// Face oval (contour) — 36 sequential pairs trace the jawline + forehead
const FACE_OVAL = [
  10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
  397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
  172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109
];

// Eyes
const RIGHT_EYE = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246];
const LEFT_EYE = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398];
const RIGHT_IRIS = [468, 469, 470, 471, 472]; // needs refine_landmarks=true (478-point model)
const LEFT_IRIS = [473, 474, 475, 476, 477];

// Lips (outer)
const LIPS_OUTER = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185];
// Lips (inner)
const LIPS_INNER = [78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 415, 310, 311, 312, 13, 82, 81, 80, 191];

// Eyebrows
const RIGHT_EYEBROW = [46, 53, 52, 65, 55, 70, 63, 105, 66, 107];
const LEFT_EYEBROW = [276, 283, 282, 295, 285, 300, 293, 334, 296, 336];

// Nose
const NOSE_BRIDGE = [168, 6, 197, 195, 5];
const NOSE_TIP = 1;

// Single key landmarks for glow points
const KEY_POINTS = {
  noseTip: 1,
  foreHead: 10,
  chin: 152,
  leftMouthCorner: 61,
  rightMouthCorner: 291,
  leftEyeOuter: 263,
  rightEyeOuter: 33,
  leftEyeInner: 362,
  rightEyeInner: 133,
  leftBrowPeak: 334,
  rightBrowPeak: 105,
  leftCheek: 234,
  rightCheek: 454,
};
```

### Coordinate Transform (normalized → canvas pixels, mirrored)

```js
function lmToCanvas(lm, w, h) {
  return {
    x: (1 - lm.x) * w,  // mirror horizontally
    y: lm.y * h,
    z: lm.z
  };
}
```

---

## Effect 1: Glowing Wireframe Tessellation Mesh

### What It Looks Like
A semi-transparent triangulated wireframe covering the entire face, like a futuristic sci-fi HUD. The wireframe pulses brighter on audio beats and shifts color with the current mode. Think Tron-style face mapping — thin cyan/gold lines tracing every facial contour, with a soft glow bloom.

### Implementation

The tessellation uses ~920 triangles from MediaPipe's `FACEMESH_TESSELATION` constant (a flat array of triangle vertex indices). Since we cannot easily import the full 2760-element array from the minified MediaPipe package at runtime, the approach is to draw **connected line segments between adjacent landmarks** instead of full tessellation, or to embed the tessellation array.

```js
// Simplified tessellation: connect nearby landmarks with lines
// Full tessellation array has 2760 entries (920 triangles × 3 vertices)
// Can be extracted from @mediapipe/drawing_utils source

function drawFaceMesh(ctx, landmarks, w, h, accentRgb, energy, beatPulse) {
  const alpha = 0.08 + energy * 0.15 + beatPulse * 0.2;
  const glowAlpha = energy * 0.04 + beatPulse * 0.1;

  ctx.save();

  // Outer glow layer (wider, more transparent)
  if (glowAlpha > 0.01) {
    ctx.strokeStyle = `rgba(${accentRgb}, ${glowAlpha})`;
    ctx.lineWidth = 3;
    drawTessellation(ctx, landmarks, w, h);
  }

  // Core wireframe layer (thin, brighter)
  ctx.strokeStyle = `rgba(${accentRgb}, ${alpha})`;
  ctx.lineWidth = 0.5;
  drawTessellation(ctx, landmarks, w, h);

  ctx.restore();
}

function drawTessellation(ctx, landmarks, w, h) {
  // FACEMESH_TESSELATION: flat array, every 3 values = one triangle
  for (let i = 0; i < FACEMESH_TESSELATION.length; i += 3) {
    const a = landmarks[FACEMESH_TESSELATION[i]];
    const b = landmarks[FACEMESH_TESSELATION[i + 1]];
    const c = landmarks[FACEMESH_TESSELATION[i + 2]];

    const ax = (1 - a.x) * w, ay = a.y * h;
    const bx = (1 - b.x) * w, by = b.y * h;
    const cx = (1 - c.x) * w, cy = c.y * h;

    ctx.beginPath();
    ctx.moveTo(ax, ay);
    ctx.lineTo(bx, by);
    ctx.lineTo(cx, cy);
    ctx.closePath();
    ctx.stroke();
  }
}
```

### Performance Cost
- **920 triangles × stroke** = ~920 `beginPath/moveTo/lineTo/closePath/stroke` calls per frame
- With glow layer: **~1840 draw calls**
- **Cost: MEDIUM-HIGH** (~2-4ms on modern mobile GPU)
- **Optimization**: Batch into a single `beginPath()` — draw all `moveTo/lineTo` calls, then one final `stroke()`:

```js
function drawTessellationBatched(ctx, landmarks, w, h) {
  ctx.beginPath();
  for (let i = 0; i < FACEMESH_TESSELATION.length; i += 3) {
    const a = landmarks[FACEMESH_TESSELATION[i]];
    const b = landmarks[FACEMESH_TESSELATION[i + 1]];
    const c = landmarks[FACEMESH_TESSELATION[i + 2]];

    const ax = (1 - a.x) * w, ay = a.y * h;
    const bx = (1 - b.x) * w, by = b.y * h;
    const cx = (1 - c.x) * w, cy = c.y * h;

    ctx.moveTo(ax, ay);
    ctx.lineTo(bx, by);
    ctx.lineTo(cx, cy);
    ctx.lineTo(ax, ay); // close triangle manually
  }
  ctx.stroke(); // ONE stroke call for all 920 triangles
}
```

This batched version drops cost to **~0.5-1ms**. Massive difference.

---

## Effect 2: Face Contour Glow Outline

### What It Looks Like
A smooth, shimmering outline tracing just the face oval (jawline + forehead), eyes, eyebrows, lips, and nose bridge. Each feature is a separate glowing line in the mode's accent color. Resembles neon face paint or the outlines in "A Scanner Darkly." The glow pulses with audio energy — brighter on beats, subtly shimmering at rest.

### Implementation

```js
const FACE_OVAL = [10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109];
const RIGHT_EYE = [33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246];
const LEFT_EYE = [362,382,381,380,374,373,390,249,263,466,388,387,386,385,384,398];
const LIPS_OUTER = [61,146,91,181,84,17,314,405,321,375,291,409,270,269,267,0,37,39,40,185];
const RIGHT_BROW = [46,53,52,65,55,70,63,105,66,107];
const LEFT_BROW = [276,283,282,295,285,300,293,334,296,336];
const NOSE_BRIDGE = [168,6,197,195,5,4,1]; // extended to nose tip

function drawContourGlow(ctx, landmarks, w, h, accentRgb, energy, beatPulse) {
  const contours = [FACE_OVAL, RIGHT_EYE, LEFT_EYE, LIPS_OUTER, RIGHT_BROW, LEFT_BROW, NOSE_BRIDGE];
  const closed =   [true,      true,      true,     true,       false,      false,      false];

  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // Multi-pass glow technique (3 passes: wide dim → medium → thin bright)
  const passes = [
    { width: 8,   alpha: 0.03 + beatPulse * 0.06 },
    { width: 3,   alpha: 0.08 + energy * 0.1 + beatPulse * 0.12 },
    { width: 1,   alpha: 0.2 + energy * 0.25 + beatPulse * 0.3 },
  ];

  for (const pass of passes) {
    ctx.lineWidth = pass.width;
    ctx.strokeStyle = `rgba(${accentRgb}, ${Math.min(1, pass.alpha)})`;

    for (let c = 0; c < contours.length; c++) {
      const indices = contours[c];
      ctx.beginPath();
      for (let i = 0; i < indices.length; i++) {
        const lm = landmarks[indices[i]];
        const x = (1 - lm.x) * w;
        const y = lm.y * h;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      if (closed[c]) ctx.closePath();
      ctx.stroke();
    }
  }

  ctx.restore();
}
```

### Alternative: shadowBlur Glow (simpler but more expensive)

```js
ctx.save();
ctx.shadowColor = `rgba(${accentRgb}, 0.8)`;
ctx.shadowBlur = 12 + beatPulse * 20;
ctx.strokeStyle = `rgba(${accentRgb}, 0.4 + energy * 0.3)`;
ctx.lineWidth = 1.5;
// draw contour paths...
ctx.stroke();
ctx.restore();
```

`shadowBlur` is GPU-accelerated on most browsers but is significantly more expensive than the multi-pass approach — avoid on low-end mobile.

### Performance Cost
- **7 contours × 3 passes = 21 stroke calls** per frame
- **Cost: LOW** (~0.3-0.8ms)
- The multi-pass layering technique (wide-dim to thin-bright) creates a convincing glow without any `shadowBlur` cost

---

## Effect 3: Landmark Light Points (Key Feature Glow Dots)

### What It Looks Like
Soft, pulsing light orbs at key facial landmarks: corners of the eyes, tip of the nose, mouth corners, brow peaks. Each dot has a radial gradient fade creating a "floating light" effect. Dots grow/shrink with audio energy. On beats, all dots flash bright then decay. Think constellation dots on the face — minimal but magical.

### Implementation

```js
const GLOW_LANDMARKS = [
  1,    // nose tip
  33,   // right eye outer
  133,  // right eye inner
  362,  // left eye inner
  263,  // left eye outer
  61,   // right mouth corner
  291,  // left mouth corner
  105,  // right brow peak
  334,  // left brow peak
  10,   // forehead center
  152,  // chin
];

function drawLandmarkLights(ctx, landmarks, w, h, accentRgb, energy, beatPulse) {
  for (const idx of GLOW_LANDMARKS) {
    const lm = landmarks[idx];
    const x = (1 - lm.x) * w;
    const y = lm.y * h;

    const baseRadius = 3;
    const radius = baseRadius + energy * 8 + beatPulse * 12;
    const alpha = 0.15 + energy * 0.3 + beatPulse * 0.4;

    // Radial gradient for soft glow
    const grad = ctx.createRadialGradient(x, y, 0, x, y, radius);
    grad.addColorStop(0, `rgba(${accentRgb}, ${Math.min(1, alpha)})`);
    grad.addColorStop(0.4, `rgba(${accentRgb}, ${alpha * 0.4})`);
    grad.addColorStop(1, `rgba(${accentRgb}, 0)`);

    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fill();
  }
}
```

### Performance-Optimized Version (pre-drawn offscreen dot)

Creating radial gradients per frame per point is expensive. Better: pre-render a single glow dot to an offscreen canvas, then `drawImage` it at each landmark:

```js
// One-time setup:
const _glowDot = document.createElement('canvas');
const _glowDotSize = 64; // px
_glowDot.width = _glowDot.height = _glowDotSize;
const _gdCtx = _glowDot.getContext('2d');

function prepareGlowDot(r, g, b) {
  const c = _glowDotSize / 2;
  _gdCtx.clearRect(0, 0, _glowDotSize, _glowDotSize);
  const grad = _gdCtx.createRadialGradient(c, c, 0, c, c, c);
  grad.addColorStop(0, `rgba(${r},${g},${b}, 1)`);
  grad.addColorStop(0.3, `rgba(${r},${g},${b}, 0.4)`);
  grad.addColorStop(1, `rgba(${r},${g},${b}, 0)`);
  _gdCtx.fillStyle = grad;
  _gdCtx.fillRect(0, 0, _glowDotSize, _glowDotSize);
}

// Per-frame draw (FAST — just drawImage calls):
function drawLandmarkLightsFast(ctx, landmarks, w, h, energy, beatPulse) {
  const scale = 0.3 + energy * 0.5 + beatPulse * 0.8;
  const size = _glowDotSize * scale;
  const halfSize = size / 2;

  ctx.save();
  ctx.globalAlpha = 0.2 + energy * 0.3 + beatPulse * 0.4;
  ctx.globalCompositeOperation = 'lighter'; // additive blending!

  for (const idx of GLOW_LANDMARKS) {
    const lm = landmarks[idx];
    const x = (1 - lm.x) * w;
    const y = lm.y * h;
    ctx.drawImage(_glowDot, x - halfSize, y - halfSize, size, size);
  }

  ctx.restore();
}
```

### Performance Cost
- **Gradient version**: 11 `createRadialGradient` + `arc` + `fill` = ~1-2ms
- **Offscreen dot version**: 11 `drawImage` calls = **~0.1-0.3ms** (extremely fast)
- `globalCompositeOperation = 'lighter'` makes overlapping dots bloom — additive blending for free
- **Cost: VERY LOW** with the offscreen approach

---

## Effect 4: Geometric Sacred Patterns Following Face Rotation

### What It Looks Like
Rotating geometric shapes (hexagons, sacred geometry triangles, concentric rings) centered on the face that rotate with head yaw/pitch/roll. The geometry is drawn around the nose tip, sized to the face, and tilts as the head tilts. Patterns pulse outward on beats. Think mystical/cyberpunk face overlay — a hexagonal mandala hovering over your face that responds to head movement.

### Implementation

```js
function drawFaceGeometry(ctx, landmarks, w, h, accentRgb, energy, beatPulse, headRoll, headYaw) {
  const nose = landmarks[1];
  const forehead = landmarks[10];
  const chin = landmarks[152];

  const cx = (1 - nose.x) * w;
  const cy = nose.y * h;
  const faceSize = Math.sqrt(
    ((1 - forehead.x) * w - (1 - chin.x) * w) ** 2 +
    (forehead.y * h - chin.y * h) ** 2
  );
  const baseRadius = faceSize * 0.35;

  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(-headRoll); // rotate with head tilt
  // Optional: slight scale based on yaw for 3D feel
  ctx.scale(1 - Math.abs(headYaw) * 0.15, 1);

  const alpha = 0.06 + energy * 0.12 + beatPulse * 0.2;
  ctx.strokeStyle = `rgba(${accentRgb}, ${Math.min(0.5, alpha)})`;
  ctx.lineWidth = 0.8;
  ctx.lineCap = 'round';

  // Concentric hexagons
  const rings = 3;
  for (let r = 1; r <= rings; r++) {
    const radius = baseRadius * (0.5 + r * 0.25) + beatPulse * r * 8;
    const sides = 6;
    ctx.beginPath();
    for (let s = 0; s <= sides; s++) {
      const angle = (s / sides) * Math.PI * 2 - Math.PI / 2;
      const x = Math.cos(angle) * radius;
      const y = Math.sin(angle) * radius;
      if (s === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.stroke();
  }

  // Inner star/triangle
  const starRadius = baseRadius * 0.4 + energy * 15;
  ctx.beginPath();
  for (let s = 0; s < 6; s++) {
    const angle = (s / 6) * Math.PI * 2 - Math.PI / 2;
    const r = s % 2 === 0 ? starRadius : starRadius * 0.5;
    const x = Math.cos(angle) * r;
    const y = Math.sin(angle) * r;
    if (s === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.stroke();

  // Radial lines from center
  for (let s = 0; s < 6; s++) {
    const angle = (s / 6) * Math.PI * 2;
    const outerR = baseRadius * (1.0 + beatPulse * 0.3);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(Math.cos(angle) * outerR, Math.sin(angle) * outerR);
    ctx.stroke();
  }

  ctx.restore();
}
```

### Performance Cost
- **~12 stroke calls** (3 hexagons + 1 star + 6 lines + 2 circles)
- **Cost: VERY LOW** (~0.1-0.3ms)
- This is the cheapest effect and one of the most visually striking

---

## Effect 5: Particle Trails from Facial Features

### What It Looks Like
Tiny glowing particles continuously emit from key landmarks (eyes, mouth corners, nose) and drift outward/upward with velocity. Particles have a short lifespan and fade out, creating ethereal trailing streams. On beats, particle emission rate spikes. Think: magical face with luminous trails streaming from the eyes and mouth, like face-emitting fireflies.

### Implementation

```js
const EMITTER_LANDMARKS = [1, 33, 263, 61, 291]; // nose, eye corners, mouth corners
const MAX_FACE_PARTICLES = 60; // budget

const _faceParticles = [];

function updateFaceParticles(landmarks, w, h, energy, beatPulse) {
  // Spawn
  const spawnRate = Math.floor(energy * 4 + beatPulse * 8);
  for (let s = 0; s < Math.min(spawnRate, 5); s++) {
    if (_faceParticles.length >= MAX_FACE_PARTICLES) break;
    const emitterIdx = EMITTER_LANDMARKS[Math.floor(Math.random() * EMITTER_LANDMARKS.length)];
    const lm = landmarks[emitterIdx];
    const x = (1 - lm.x) * w;
    const y = lm.y * h;

    _faceParticles.push({
      x, y,
      vx: (Math.random() - 0.5) * 2,
      vy: -Math.random() * 2 - 0.5,
      life: 1,
      decay: 0.01 + Math.random() * 0.02,
      size: 0.8 + Math.random() * 1.5
    });
  }

  // Update
  for (let i = _faceParticles.length - 1; i >= 0; i--) {
    const p = _faceParticles[i];
    p.x += p.vx;
    p.y += p.vy;
    p.vy -= 0.02; // upward drift
    p.life -= p.decay;
    if (p.life <= 0) {
      _faceParticles[i] = _faceParticles[_faceParticles.length - 1];
      _faceParticles.pop();
    }
  }
}

function drawFaceParticles(ctx, accentRgb) {
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  for (const p of _faceParticles) {
    const alpha = p.life * p.life * 0.6;
    ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}
```

### Performance Cost
- **60 particles × `arc` + `fill`** per frame
- **Cost: LOW** (~0.3-0.5ms)
- `swap-and-pop` removal keeps the array management O(1) per removal
- `globalCompositeOperation = 'lighter'` is free on GPU-composited canvases

---

## Effect 6: Depth-Based Z-Shimmer

### What It Looks Like
Landmarks closer to the camera (smaller z values) glow brighter; landmarks further away dim. Creates a 3D depth illusion where the nose tip blazes bright and the ears/jaw edges fade. Combined with subtle random shimmer, it looks like the face is covered in luminescent paint that catches light differently at each depth.

### Implementation

```js
function drawDepthShimmer(ctx, landmarks, w, h, accentRgb, energy, time) {
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';

  // Find z range for normalization
  let zMin = Infinity, zMax = -Infinity;
  for (const lm of landmarks) {
    if (lm.z < zMin) zMin = lm.z;
    if (lm.z > zMax) zMax = lm.z;
  }
  const zRange = zMax - zMin || 1;

  // Draw every Nth landmark as a depth-aware dot
  // (drawing all 468 is too many — sample every 4th)
  const step = 4;
  for (let i = 0; i < landmarks.length; i += step) {
    const lm = landmarks[i];
    const x = (1 - lm.x) * w;
    const y = lm.y * h;

    // Depth factor: 1.0 = closest to camera, 0.0 = furthest
    const depthFactor = 1 - (lm.z - zMin) / zRange;

    // Shimmer: subtle sine wave based on time + landmark index
    const shimmer = 0.5 + 0.5 * Math.sin(time * 0.003 + i * 0.7);

    const alpha = depthFactor * (0.05 + energy * 0.15 + shimmer * 0.05);
    const radius = 1 + depthFactor * 2 + energy * 2;

    ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}
```

### Performance Cost
- **~117 dots** (468/4) with simple `arc` + `fill`
- **Cost: LOW** (~0.3-0.5ms)
- The `Math.sin` shimmer is extremely cheap
- Skip `createRadialGradient` — simple filled circles at this scale look fine

---

## Effect 7: Eye Laser Lines / Gaze Beams

### What It Looks Like
Two thin laser-like lines extending from the irises downward or forward, like cyberpunk eye beams. The beams pulse with audio energy and change length with volume. On beats, they flash bright. Optional: the beams converge at a point based on where the user is looking (if iris tracking is enabled).

### Implementation

```js
function drawEyeBeams(ctx, landmarks, w, h, accentRgb, energy, beatPulse) {
  const eyes = [
    { center: 468, fallback: 159 }, // right iris center (or eye top)
    { center: 473, fallback: 386 }, // left iris center (or eye top)
  ];

  ctx.save();
  ctx.lineCap = 'round';

  for (const eye of eyes) {
    const idx = landmarks.length > 468 ? eye.center : eye.fallback;
    const lm = landmarks[idx];
    const x = (1 - lm.x) * w;
    const y = lm.y * h;

    const beamLength = 30 + energy * 80 + beatPulse * 60;
    const endY = y + beamLength;

    // Multi-pass glow beam
    const passes = [
      { width: 6, alpha: 0.02 + beatPulse * 0.05 },
      { width: 2, alpha: 0.06 + energy * 0.1 + beatPulse * 0.15 },
      { width: 0.5, alpha: 0.15 + energy * 0.2 + beatPulse * 0.3 },
    ];

    for (const pass of passes) {
      const grad = ctx.createLinearGradient(x, y, x, endY);
      grad.addColorStop(0, `rgba(${accentRgb}, ${pass.alpha})`);
      grad.addColorStop(1, `rgba(${accentRgb}, 0)`);
      ctx.strokeStyle = grad;
      ctx.lineWidth = pass.width;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x, endY);
      ctx.stroke();
    }
  }

  ctx.restore();
}
```

### Performance Cost
- **2 eyes × 3 passes × 1 gradient + stroke** = 6 draw calls + 6 gradient creates
- **Cost: VERY LOW** (~0.1-0.2ms)
- Linear gradients are cheaper than radial gradients

---

## Integration Architecture

### Where to Hook In

The raw landmarks need to be stored on `MUZE.State` so the Visualizer can access them:

In `app.js` `_tick()` (around line 54):
```js
if (fr && fr.faceLandmarks && fr.faceLandmarks.length > 0) {
  S._rawLandmarks = fr.faceLandmarks[0]; // Store raw 468 landmarks
  const r = MUZE.FaceFeatures.extract(fr.faceLandmarks[0]);
  // ... existing code ...
}
```

In `visualizer.js` `draw()`, after the existing visualizer code:
```js
// Face mesh effects
const landmarks = MUZE.State._rawLandmarks;
if (landmarks && MUZE.State.faceDetected) {
  const w = this._width;
  const h = this._height;

  // Pick which effects to draw (could be user-configurable)
  drawContourGlow(ctx, landmarks, w, h, accentRgb, energy, this._beatPulse);
  drawLandmarkLightsFast(ctx, landmarks, w, h, energy, this._beatPulse);
  // drawFaceGeometry(ctx, landmarks, w, h, accentRgb, energy, this._beatPulse,
  //                  MUZE.State.headRoll, MUZE.State.headYaw);
}
```

### Performance Budget Summary

| Effect | Cost per Frame | Draw Calls | Recommendation |
|--------|---------------|------------|----------------|
| Full Wireframe Mesh (batched) | 0.5–1ms | 1–2 | Heavy but iconic; use on desktop |
| Contour Glow Outline | 0.3–0.8ms | ~21 | Best bang for buck |
| Landmark Light Points (offscreen) | 0.1–0.3ms | ~11 | Nearly free, looks great |
| Sacred Geometry Patterns | 0.1–0.3ms | ~12 | Cheapest, very striking |
| Particle Trails | 0.3–0.5ms | ~60 | Good value, adds life |
| Depth Z-Shimmer | 0.3–0.5ms | ~117 | Subtle but magical |
| Eye Beams | 0.1–0.2ms | 6 | Accent only, very cheap |

**Total budget for mobile 60fps**: aim for < 3ms combined for face effects.

**Recommended default combo**: Contour Glow + Landmark Lights + Particles = ~0.7–1.6ms total. Stunning and performant.

**Premium/desktop combo**: Full Mesh + Contour Glow + Landmark Lights + Geometry + Particles = ~1.3–2.9ms.

---

## Key Techniques Summary

### Multi-Pass Glow (no shadowBlur needed)
Draw the same path 3 times with decreasing lineWidth and increasing alpha:
1. Wide + dim (bloom halo)
2. Medium + medium (body glow)
3. Thin + bright (core line)

This is **5-10x cheaper** than `shadowBlur` and looks just as good.

### Additive Blending
`ctx.globalCompositeOperation = 'lighter'` makes overlapping glows bloom naturally. Essential for the light-point and particle effects.

### Offscreen Canvas for Repeated Shapes
Pre-render a radial-gradient glow dot to an offscreen canvas once, then use `drawImage` to stamp it at each landmark. Avoids creating gradients per frame.

### Batched Path Drawing
Combine all triangles/lines into a single `beginPath()` ... `stroke()` call. Canvas batches these into one GPU draw call internally.

### Landmark Interpolation for Smoothness
Since face detection runs at ~15fps (alternating with hand tracking), interpolate landmarks between detection frames using lerp:

```js
// In _tick(), store previous and current landmarks with timestamps
if (S._rawLandmarks) {
  S._prevLandmarks = S._rawLandmarks;
  S._landmarkTime = now;
}

// In visualizer, interpolate:
const t = Math.min(1, (now - S._landmarkTime) / DETECT_INTERVAL);
const interp = [];
for (let i = 0; i < 468; i++) {
  interp[i] = {
    x: S._prevLandmarks[i].x + (S._rawLandmarks[i].x - S._prevLandmarks[i].x) * t,
    y: S._prevLandmarks[i].y + (S._rawLandmarks[i].y - S._prevLandmarks[i].y) * t,
    z: S._prevLandmarks[i].z + (S._rawLandmarks[i].z - S._prevLandmarks[i].z) * t,
  };
}
```

This eliminates the "steppy" 15fps landmark jitter and makes effects butter-smooth at 60fps.

---

## Sources

- [MediaPipe Face Landmarker Guide](https://developers.google.com/mediapipe/solutions/vision/face_landmarker)
- [MediaPipe Face Mesh Documentation](https://github.com/google-ai-edge/mediapipe/blob/master/docs/solutions/face_mesh.md)
- [Face Mesh Triangles in TensorFlow.js](https://selvamsubbiah.com/mediapipe-facemesh-triangles-in-tensorflow-js-part-2/)
- [Understanding MediaPipe FaceMesh Output](https://github.com/lschmelzeisen/understanding-mediapipe-facemesh-output)
- [MediaPipe Landmark Index Definitions](https://github.com/google-ai-edge/mediapipe/issues/1615)
- [Canvas Animated Glowing Lines Technique](https://www.ashleysheridan.co.uk/blog/Animated+Glowing+Lines+in+Canvas)
- [Per-Pixel Canvas Glow Library](https://github.com/mode-13/html5-canvas-glow)
- [Canvas Neon Effect: globalCompositeOperation + shadowBlur](https://codepen.io/agar3s/pen/pJpoya)
- [JeelizFaceFilter — WebGL Face Tracking with Canvas2D](https://github.com/jeeliz/jeelizFaceFilter)
- [WebAR.rocks.face — Lightweight Face Tracking](https://github.com/WebAR-rocks/WebAR.rocks.face)
- [MusiPhi — Audio-Reactive Sacred Geometry Visualizer](https://musiphi.app/)
- [Geometric Reactive Audio Visualizations in the Browser](https://cdm.link/geometric-reactive-audio-visualizations-now-live-in-the-browser-how-it-was-done/)
- [Mugeetion: Musical Interface Using Facial Gesture](https://arxiv.org/pdf/1809.05502)
- [Canvas Motion Trails Technique](https://www.kirupa.com/canvas/creating_motion_trails.htm)
- [Canvas Particle Effects on DOM Elements](https://css-tricks.com/adding-particle-effects-to-dom-elements-with-canvas/)
- [MDN: CanvasRenderingContext2D.shadowBlur](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/shadowBlur)
- [Spark AR Face Assets](https://github.com/RobbieConceptuel/Spark-AR-Face-Assets)
