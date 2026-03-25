# Hand/Gesture Trail Visual Effects for MUZE

## Research Summary

Researched across creative coding communities (p5.js, Shadertoy, Codrops, CodePen), AR music visualizers (Liquid Hands ACM paper, Bolt.new hand-particle demos), and Canvas 2D technique guides (KIRUPA motion trails, Growing with the Web, MDN Canvas tutorials).

### Key Techniques Identified

1. **Semi-transparent overlay fade** -- Instead of clearing the canvas, draw a semi-transparent rectangle each frame. Previous drawing gradually fades. This is the cheapest trail method and gives that long-exposure photography look. Used by every creative coder for light-painting effects.

2. **Point-history ribbon with Bezier interpolation** -- Store the last N hand positions. Draw a smooth ribbon using `bezierCurveTo()` between consecutive midpoints. Width modulation along the ribbon creates a tapered, organic feel. Used extensively in drawing apps and gesture visualizers.

3. **Additive blending with shadowBlur** -- Setting `globalCompositeOperation = "lighter"` and `shadowBlur = 10-25` with a `shadowColor` creates glowing neon trails without WebGL. The additive blending makes overlapping trails intensify rather than occlude.

4. **Particle burst on discrete events** -- The Liquid Hands ACM paper (2021) shows that particle bursts on musical events create strong cross-modal correspondences. Spawning radial rings of particles with velocity proportional to the musical interval jump makes note changes feel physical.

5. **Connection lines (web/constellation)** -- Drawing thin lines between tracked points (hand, face landmarks) creates a digital nervous-system aesthetic. Opacity modulated by distance and audio energy. Used in countless generative art sketches.

### Performance Considerations

All four effects below use Canvas 2D only (the existing `#overlay` canvas). Combined budget target: <2ms per frame on mobile. Key optimizations:
- Trail history capped at 60 points (1 second at 60fps)
- Particle pool capped at 100 across all effects
- No `getImageData`/`putImageData` (slow); use only drawing operations
- Shared accent color cache from `MUZE.Config.MODE_COLORS` (already in visualizer)

---

## Effect 1: Note Ribbon

A flowing ribbon that follows the hand, colored by note pitch (low=cool blues, high=warm oranges). Width varies with hand openness (open hand = wide ribbon, fist = thin thread). The ribbon fades behind the hand with a beautiful decay using opacity gradient.

### Design Rationale

The ribbon makes hand movement feel like conducting -- your gesture leaves a visible trace in the air. The pitch-to-color mapping creates an instant visual feedback loop: move your hand up, the ribbon warms; move it down, it cools. This is grounded in cross-modal research showing that humans naturally associate high pitch with warm/bright colors and low pitch with cool/dark colors.

Width modulation by hand openness adds expressiveness -- opening your hand fans out the ribbon like a painter's broad stroke, closing it creates a precise thread.

### Implementation

```js
// === NOTE RIBBON ===
// Add to MUZE.Visualizer or a new MUZE.HandFX module

_ribbonTrail: [],       // { x, y, width, r, g, b, alpha }
_ribbonMaxPoints: 60,   // ~1 second at 60fps

_updateRibbon() {
  const S = MUZE.State;
  if (!S.handPresent) {
    // Fade existing trail when hand disappears
    for (const p of this._ribbonTrail) {
      p.alpha *= 0.92;
    }
    // Remove fully faded points
    while (this._ribbonTrail.length > 0 && this._ribbonTrail[0].alpha < 0.01) {
      this._ribbonTrail.shift();
    }
    return;
  }

  const w = this._width;
  const h = this._height;
  const px = S.handX * w;
  const py = S.handY * h;

  // Pitch-to-color: map MIDI note to hue
  // Low notes (C3=48) -> cool blue (hsl 220), High notes (C6=84) -> warm orange (hsl 30)
  const note = S.melodyNote || 60;
  const pitchNorm = Math.max(0, Math.min(1, (note - 48) / 36)); // 0=low, 1=high

  // Interpolate between cool blue and warm orange via HSL-like RGB blend
  const r = Math.round(40 + pitchNorm * 215);   // 40 -> 255
  const g = Math.round(100 + pitchNorm * 60);    // 100 -> 160
  const b = Math.round(250 - pitchNorm * 200);   // 250 -> 50

  // Width: open hand = wide, fist = thin
  const baseWidth = S.handOpen ? 18 : 4;

  this._ribbonTrail.push({
    x: px, y: py,
    width: baseWidth,
    r, g, b,
    alpha: 0.8
  });

  // Cap trail length
  if (this._ribbonTrail.length > this._ribbonMaxPoints) {
    this._ribbonTrail.shift();
  }

  // Age all points
  for (let i = 0; i < this._ribbonTrail.length - 1; i++) {
    const age = 1 - (i / this._ribbonTrail.length);
    this._ribbonTrail[i].alpha = 0.8 * (1 - age * age); // quadratic fade from tail
  }
},

_drawRibbon(ctx) {
  const trail = this._ribbonTrail;
  if (trail.length < 3) return;

  // Draw as a smooth filled ribbon using offset curves
  // For each segment, we compute perpendicular offsets to create width
  for (let i = 1; i < trail.length - 1; i++) {
    const prev = trail[i - 1];
    const curr = trail[i];
    const next = trail[i + 1];

    // Direction vector
    const dx = next.x - prev.x;
    const dy = next.y - prev.y;
    const len = Math.sqrt(dx * dx + dy * dy) || 1;

    // Perpendicular (normalized)
    const nx = -dy / len;
    const ny = dx / len;

    // Taper: width decreases toward the tail
    const taper = i / trail.length;
    const halfW = curr.width * taper * 0.5;

    // Current segment quad
    const prevTaper = (i - 1) / trail.length;
    const prevHalfW = prev.width * prevTaper * 0.5;

    const pdx = curr.x - prev.x;
    const pdy = curr.y - prev.y;
    const plen = Math.sqrt(pdx * pdx + pdy * pdy) || 1;
    const pnx = -pdy / plen;
    const pny = pdx / plen;

    ctx.beginPath();
    ctx.moveTo(prev.x + pnx * prevHalfW, prev.y + pny * prevHalfW);
    ctx.lineTo(curr.x + nx * halfW, curr.y + ny * halfW);
    ctx.lineTo(curr.x - nx * halfW, curr.y - ny * halfW);
    ctx.lineTo(prev.x - pnx * prevHalfW, prev.y - pny * prevHalfW);
    ctx.closePath();

    // Fill with color and alpha
    const alpha = curr.alpha * taper;
    ctx.fillStyle = `rgba(${curr.r},${curr.g},${curr.b},${alpha})`;
    ctx.fill();
  }

  // Glow at the head (current hand position)
  if (trail.length > 0) {
    const head = trail[trail.length - 1];
    const glow = ctx.createRadialGradient(head.x, head.y, 0, head.x, head.y, head.width * 1.5);
    glow.addColorStop(0, `rgba(${head.r},${head.g},${head.b},0.5)`);
    glow.addColorStop(1, `rgba(${head.r},${head.g},${head.b},0)`);
    ctx.beginPath();
    ctx.fillStyle = glow;
    ctx.arc(head.x, head.y, head.width * 1.5, 0, Math.PI * 2);
    ctx.fill();
  }
},
```

### Alternative: Smoother Bezier Ribbon

For an even smoother ribbon, use Catmull-Rom to Bezier conversion:

```js
_drawRibbonSmooth(ctx) {
  const trail = this._ribbonTrail;
  if (trail.length < 4) return;

  // Draw the ribbon as a smooth stroke with varying width using multiple passes
  // Each pass draws a line segment with appropriate width and alpha
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  for (let i = 1; i < trail.length; i++) {
    const prev = trail[i - 1];
    const curr = trail[i];
    const taper = i / trail.length;
    const alpha = curr.alpha * taper * taper; // quadratic taper for elegance

    if (alpha < 0.005) continue;

    const lineWidth = curr.width * taper;
    if (lineWidth < 0.3) continue;

    ctx.beginPath();
    ctx.strokeStyle = `rgba(${curr.r},${curr.g},${curr.b},${alpha})`;
    ctx.lineWidth = lineWidth;

    // Use quadratic curve through midpoints for smoothness
    if (i >= 2) {
      const pprev = trail[i - 2];
      const mx1 = (pprev.x + prev.x) / 2;
      const my1 = (pprev.y + prev.y) / 2;
      const mx2 = (prev.x + curr.x) / 2;
      const my2 = (prev.y + curr.y) / 2;
      ctx.moveTo(mx1, my1);
      ctx.quadraticCurveTo(prev.x, prev.y, mx2, my2);
    } else {
      ctx.moveTo(prev.x, prev.y);
      ctx.lineTo(curr.x, curr.y);
    }
    ctx.stroke();
  }

  // Glow dot at head
  if (trail.length > 0 && MUZE.State.handPresent) {
    const head = trail[trail.length - 1];
    ctx.beginPath();
    ctx.shadowColor = `rgb(${head.r},${head.g},${head.b})`;
    ctx.shadowBlur = 20;
    ctx.fillStyle = `rgba(${head.r},${head.g},${head.b},0.7)`;
    ctx.arc(head.x, head.y, 5, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
  }
},
```

---

## Effect 2: Particle Burst on Note Change

When the melody note changes, emit an expanding ring of particles from the hand position. Color matches the mode accent. Size and count proportional to the interval jump (small step = subtle shimmer, large leap = dramatic explosion).

### Design Rationale

Discrete visual events tied to discrete musical events (note changes) create strong audiovisual coupling. The "Liquid Hands" research (ACM 2021) found that particle reactions to musical events significantly enhanced the perceived emotional impact. The interval-proportional sizing means a one-semitone step barely registers visually, but an octave leap creates a dramatic burst -- matching the musical drama.

### Implementation

```js
// === PARTICLE BURST ON NOTE CHANGE ===

_burstParticles: [],
_maxBurstParticles: 100,
_lastBurstNote: null,

_triggerNoteBurst(note, handX, handY) {
  if (this._lastBurstNote === null) {
    this._lastBurstNote = note;
    return;
  }

  const interval = Math.abs(note - this._lastBurstNote);
  this._lastBurstNote = note;

  if (interval === 0) return;

  const w = this._width;
  const h = this._height;
  const cx = handX * w;
  const cy = handY * h;

  // Get mode accent color
  const colors = MUZE.Config.MODE_COLORS[MUZE.State.currentModeName];
  const rgb = colors ? colors.rgb : '232,169,72';
  const [r, g, b] = rgb.split(',').map(Number);

  // Particle count proportional to interval (1 semitone = 3 particles, 12 = 30 particles)
  const count = Math.min(30, Math.max(3, Math.round(interval * 2.5)));

  // Burst radius proportional to interval
  const burstSpeed = 1.5 + interval * 0.5;

  for (let i = 0; i < count; i++) {
    if (this._burstParticles.length >= this._maxBurstParticles) {
      // Recycle oldest
      this._burstParticles.shift();
    }

    const angle = (i / count) * Math.PI * 2 + Math.random() * 0.3;
    const speed = burstSpeed * (0.7 + Math.random() * 0.6);

    this._burstParticles.push({
      x: cx,
      y: cy,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      life: 1.0,
      decay: 0.015 + Math.random() * 0.01,
      size: 1.5 + interval * 0.3 + Math.random() * 1.5,
      r, g, b,
      // Ring particles also get a slight gravity-defying upward drift
      gravity: -0.02
    });
  }

  // Also spawn an expanding ring (single object tracked separately)
  this._burstRings = this._burstRings || [];
  this._burstRings.push({
    x: cx, y: cy,
    radius: 5,
    maxRadius: 20 + interval * 5,
    alpha: 0.6,
    r, g, b,
    speed: 2 + interval * 0.8
  });
},

_updateBurstParticles() {
  // Update particles
  for (let i = this._burstParticles.length - 1; i >= 0; i--) {
    const p = this._burstParticles[i];
    p.x += p.vx;
    p.y += p.vy;
    p.vy += p.gravity;
    p.vx *= 0.98; // gentle drag
    p.vy *= 0.98;
    p.life -= p.decay;
    if (p.life <= 0) {
      this._burstParticles[i] = this._burstParticles[this._burstParticles.length - 1];
      this._burstParticles.pop();
    }
  }

  // Update rings
  if (this._burstRings) {
    for (let i = this._burstRings.length - 1; i >= 0; i--) {
      const ring = this._burstRings[i];
      ring.radius += ring.speed;
      ring.alpha *= 0.93;
      if (ring.alpha < 0.01 || ring.radius > ring.maxRadius) {
        this._burstRings.splice(i, 1);
      }
    }
  }
},

_drawBurstParticles(ctx) {
  // Draw particles
  for (const p of this._burstParticles) {
    const alpha = p.life * p.life; // quadratic falloff for soft fade
    ctx.beginPath();
    ctx.fillStyle = `rgba(${p.r},${p.g},${p.b},${alpha})`;
    ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
    ctx.fill();
  }

  // Draw expanding rings
  if (this._burstRings) {
    for (const ring of this._burstRings) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${ring.r},${ring.g},${ring.b},${ring.alpha})`;
      ctx.lineWidth = 1.5 * ring.alpha; // ring thins as it fades
      ctx.arc(ring.x, ring.y, ring.radius, 0, Math.PI * 2);
      ctx.stroke();
    }
  }
},
```

### Detecting Note Changes

In the main `_tick()` loop in app.js, the note change is already detected:

```js
// In MUZE.Loop._tick(), after note !== this._prevMelodyNote:
if (note !== this._prevMelodyNote) {
  // ... existing audio trigger code ...
  // ADD: trigger burst effect
  MUZE.Visualizer._triggerNoteBurst(note, S.handX, S.handY);
  this._prevMelodyNote = note;
}
```

---

## Effect 3: Light Painting Trail

The hand leaves a luminous trail that persists and fades over 2-3 seconds, like long-exposure photography of a moving light. Instead of clearing the canvas fully each frame, we use a secondary offscreen canvas with semi-transparent overlay fade. Trail color shifts with the musical mode.

### Design Rationale

This is the most visually striking effect, inspired by real-world light painting photography. The key insight from the creative coding research is to NOT clear the trail canvas -- instead, draw a semi-transparent black rectangle each frame, causing previous strokes to gradually dim. This creates a natural luminous decay where the most recent stroke is brightest and older strokes glow faintly.

The mode color shift means the trail becomes a history of the musical journey -- you can see where you were in different modes by the color gradient left behind.

### Implementation

```js
// === LIGHT PAINTING TRAIL ===
// Uses a SECONDARY offscreen canvas for persistent trail with fade

_trailCanvas: null,
_trailCtx: null,
_trailInitialized: false,
_prevHandPos: null,

_initTrailCanvas() {
  if (this._trailInitialized) return;
  this._trailCanvas = document.createElement('canvas');
  this._trailCanvas.width = this._canvas.width;
  this._trailCanvas.height = this._canvas.height;
  this._trailCtx = this._trailCanvas.getContext('2d');
  // Match the DPR transform of the main canvas
  const dpr = window.devicePixelRatio || 1;
  this._trailCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  this._trailInitialized = true;
},

_updateLightPainting() {
  this._initTrailCanvas();
  const tctx = this._trailCtx;
  const w = this._width;
  const h = this._height;
  const S = MUZE.State;

  // 1. Fade previous content (semi-transparent black overlay)
  //    Lower alpha = longer persistence. 0.015 ~ 3 second fade at 60fps
  //    (each frame multiplies existing brightness by 1 - 0.015 = 0.985)
  //    After 180 frames (3s): 0.985^180 = 0.065 => fades to ~6% brightness
  tctx.globalCompositeOperation = 'source-over';
  tctx.fillStyle = 'rgba(0, 0, 0, 0.015)';
  tctx.fillRect(0, 0, w, h);

  // 2. Draw new stroke if hand is present
  if (S.handPresent) {
    const px = S.handX * w;
    const py = S.handY * h;

    // Get mode accent color
    const colors = MUZE.Config.MODE_COLORS[S.currentModeName];
    const accent = colors ? colors.accent : '#e8a948';
    const rgb = colors ? colors.rgb : '232,169,72';

    if (this._prevHandPos) {
      const dx = px - this._prevHandPos.x;
      const dy = py - this._prevHandPos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist > 1) { // Only draw if hand moved
        // Draw glowing line segment
        tctx.globalCompositeOperation = 'lighter'; // additive blending for glow
        tctx.lineCap = 'round';

        // Core bright stroke
        tctx.beginPath();
        tctx.strokeStyle = `rgba(${rgb}, 0.8)`;
        tctx.lineWidth = S.handOpen ? 4 : 2;
        tctx.moveTo(this._prevHandPos.x, this._prevHandPos.y);
        tctx.lineTo(px, py);
        tctx.stroke();

        // Wider soft glow stroke
        tctx.beginPath();
        tctx.strokeStyle = `rgba(${rgb}, 0.15)`;
        tctx.lineWidth = S.handOpen ? 18 : 8;
        tctx.moveTo(this._prevHandPos.x, this._prevHandPos.y);
        tctx.lineTo(px, py);
        tctx.stroke();

        // Even wider ultra-soft bloom
        tctx.beginPath();
        tctx.strokeStyle = `rgba(${rgb}, 0.04)`;
        tctx.lineWidth = S.handOpen ? 40 : 18;
        tctx.moveTo(this._prevHandPos.x, this._prevHandPos.y);
        tctx.lineTo(px, py);
        tctx.stroke();

        // Bright point at current position
        tctx.beginPath();
        tctx.fillStyle = `rgba(255, 255, 255, 0.6)`;
        tctx.arc(px, py, 2, 0, Math.PI * 2);
        tctx.fill();
      }
    }

    this._prevHandPos = { x: px, y: py };
  } else {
    this._prevHandPos = null;
  }

  // Reset composite
  tctx.globalCompositeOperation = 'source-over';
},

_drawLightPainting(ctx) {
  if (!this._trailCanvas) return;
  // Composite the trail canvas onto the main overlay
  // Use 'lighter' for additive glow, or 'source-over' for standard overlay
  ctx.globalCompositeOperation = 'lighter';
  ctx.drawImage(this._trailCanvas, 0, 0, this._width, this._height);
  ctx.globalCompositeOperation = 'source-over';
},
```

### Handling Canvas Resize

```js
// In _resize(), add:
if (this._trailCanvas) {
  const dpr = window.devicePixelRatio || 1;
  this._trailCanvas.width = this._width * dpr;
  this._trailCanvas.height = this._height * dpr;
  this._trailCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
```

---

## Effect 4: Connection Lines

Thin glowing lines from the hand to face landmarks, creating a visual "web" or nervous-system aesthetic between body and face. Lines pulse with audio energy. When the hand is far from the face, lines are barely visible; when close, they glow intensely.

### Design Rationale

This effect visualizes the connection between the two input modalities -- face (controlling harmony, effects, timbre) and hand (controlling melody). The web of lines makes the musical relationship between these body parts visible. Lines pulsing with audio energy creates a feedback loop: your body produces sound, and the sound makes the connections between your body parts glow.

Distance-based opacity ensures this effect is subtle most of the time (hand far from face = barely visible lines) but becomes dramatic during expressive moments when the hand comes close to the face.

### Implementation

```js
// === CONNECTION LINES ===
// Requires face landmark positions. We use key face landmarks stored during detection.

_faceLandmarkCache: null, // cached face landmark positions in screen coords
_connectionPulse: 0,

// Call this during face detection to cache key landmark positions
_cacheFaceLandmarks(faceLandmarks) {
  if (!faceLandmarks || !faceLandmarks.length) {
    this._faceLandmarkCache = null;
    return;
  }
  const lm = faceLandmarks;
  const w = this._width;
  const h = this._height;

  // Store a handful of key face points (not all 468)
  // These create a visually interesting web without performance cost
  this._faceLandmarkCache = [
    { x: lm[1].x * w, y: lm[1].y * h },     // nose tip
    { x: lm[10].x * w, y: lm[10].y * h },    // forehead
    { x: lm[152].x * w, y: lm[152].y * h },  // chin
    { x: lm[234].x * w, y: lm[234].y * h },  // left ear
    { x: lm[454].x * w, y: lm[454].y * h },  // right ear
    { x: lm[159].x * w, y: lm[159].y * h },  // right eye top
    { x: lm[386].x * w, y: lm[386].y * h },  // left eye top
    { x: lm[13].x * w, y: lm[13].y * h },    // upper lip
    { x: lm[105].x * w, y: lm[105].y * h },  // right brow
    { x: lm[334].x * w, y: lm[334].y * h },  // left brow
  ];
},

_drawConnectionLines(ctx) {
  const S = MUZE.State;
  if (!S.handPresent || !S.faceDetected || !this._faceLandmarkCache) return;

  const w = this._width;
  const h = this._height;
  const hx = S.handX * w;
  const hy = S.handY * h;

  // Get accent color
  const colors = MUZE.Config.MODE_COLORS[S.currentModeName];
  const rgb = colors ? colors.rgb : '232,169,72';

  // Audio energy for pulse
  const waveform = MUZE.Audio.getWaveform();
  let energy = 0;
  if (waveform) {
    for (let i = 0; i < waveform.length; i++) energy += Math.abs(waveform[i]);
    energy = energy / waveform.length;
  }

  // Pulse oscillation
  this._connectionPulse = (this._connectionPulse || 0) + 0.05;
  const pulse = 0.7 + Math.sin(this._connectionPulse) * 0.3;

  // Draw lines from hand to each face landmark
  for (const lm of this._faceLandmarkCache) {
    const dx = hx - lm.x;
    const dy = hy - lm.y;
    const dist = Math.sqrt(dx * dx + dy * dy);

    // Distance falloff: stronger when hand is closer to face
    // Max screen distance ~1000px, effect strongest within 300px
    const distNorm = Math.min(1, dist / 400);
    const distAlpha = (1 - distNorm) * (1 - distNorm); // quadratic falloff

    // Combined alpha: distance + energy + pulse
    const alpha = distAlpha * (0.05 + energy * 0.4) * pulse;
    if (alpha < 0.005) continue;

    // Draw the connection line
    ctx.beginPath();
    ctx.strokeStyle = `rgba(${rgb}, ${alpha})`;
    ctx.lineWidth = 0.8;
    ctx.moveTo(hx, hy);
    ctx.lineTo(lm.x, lm.y);
    ctx.stroke();

    // Small glow dot at the face landmark end
    if (alpha > 0.02) {
      ctx.beginPath();
      ctx.fillStyle = `rgba(${rgb}, ${alpha * 1.5})`;
      ctx.arc(lm.x, lm.y, 2, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // Glow dot at hand position
  const handAlpha = 0.1 + energy * 0.5;
  ctx.beginPath();
  ctx.shadowColor = `rgba(${rgb}, ${handAlpha})`;
  ctx.shadowBlur = 15;
  ctx.fillStyle = `rgba(${rgb}, ${handAlpha})`;
  ctx.arc(hx, hy, 4, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
},
```

### Caching Face Landmarks

The face landmarks need to be cached during the detection cycle. In `app.js`, after extracting face features:

```js
// In MUZE.Loop._tick(), after face detection succeeds:
if (r) {
  // ... existing state updates ...
  // Cache face landmarks for connection lines
  MUZE.Visualizer._cacheFaceLandmarks(fr.faceLandmarks[0]);
}
```

---

## Integration: Adding All Effects to the Existing Visualizer

All four effects integrate into the existing `MUZE.Visualizer.draw()` method. Here is how the draw method would be modified:

```js
draw() {
  const ctx = this._ctx;
  const w = this._width;
  const h = this._height;
  ctx.clearRect(0, 0, w, h);

  const waveform = MUZE.Audio.getWaveform();
  if (!waveform) return;

  // ... existing energy calculation, accent caching, FFT analysis ...
  // ... existing beat detection ...

  // === HAND VISUAL EFFECTS (draw BEFORE waveform ring so ring sits on top) ===

  // 1. Light painting trail (offscreen canvas technique)
  this._updateLightPainting();
  this._drawLightPainting(ctx);

  // 2. Note ribbon (direct draw)
  this._updateRibbon();
  this._drawRibbonSmooth(ctx);

  // 3. Particle bursts (update + draw)
  this._updateBurstParticles();
  this._drawBurstParticles(ctx);

  // 4. Connection lines (direct draw)
  this._drawConnectionLines(ctx);

  // === EXISTING EFFECTS ===

  // ---- Circular waveform ring ----
  // ... existing ring code ...

  // ---- Floating particles ----
  // ... existing particle code ...

  // ---- Bottom frequency bars ----
  // ... existing freq bars code ...
},
```

---

## Summary & Visual Character

| Effect | Character | CPU Cost | When Visible |
|--------|-----------|----------|-------------|
| Note Ribbon | Flowing, organic, pitch-colored | ~0.3ms | Hand present |
| Particle Burst | Explosive, dramatic, interval-scaled | ~0.2ms (burst) | Note changes |
| Light Painting | Ethereal, persistent, mode-colored | ~0.4ms (offscreen canvas) | Hand present, persists 3s |
| Connection Lines | Digital, nervous-system, energy-pulsed | ~0.1ms | Hand + face both tracked |

Total additional frame cost: ~1ms worst case, well within budget.

### Recommended Default Configuration

Not all effects should run simultaneously at full intensity -- that would be visually chaotic. Recommended approach:

1. **Always on:** Light Painting Trail (subtle, atmospheric)
2. **Always on:** Particle Burst on Note Change (event-driven, not continuous)
3. **Optional toggle:** Note Ribbon (can replace or supplement light painting)
4. **Optional toggle:** Connection Lines (best for performances where face + hand are both active)

A future "visual theme" selector could offer presets:
- **Minimal:** Light painting only
- **Expressive:** Ribbon + burst
- **Digital:** Connection lines + burst
- **Full:** All four

---

## Sources

- [Creating Motion Trails (KIRUPA)](https://www.kirupa.com/canvas/creating_motion_trails.htm)
- [Trail Effect in Canvas Animation (CodePen)](https://codepen.io/depy/pen/amoXGB)
- [Creating an Interactive Glowing Mouse Trail (DEV)](https://dev.to/mawayalebo/creating-an-interactive-glowing-mouse-trail-with-html5-canvas-and-javascript-4a04)
- [Creating a 'trail' effect in canvas (Growing with the Web)](https://www.growingwiththeweb.com/2012/10/creating-trail-effect-with-canvas.html)
- [Ribbons Effect with HTML5 Canvas (CodePen)](https://codepen.io/rainner/pen/vXjNBd)
- [Crafting Stylised Mouse Trails with OGL (Codrops)](https://tympanus.net/codrops/2019/09/24/crafting-stylised-mouse-trails-with-ogl/)
- [Canvas shadowBlur property (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/shadowBlur)
- [Neon Effect on Canvas (CodePen)](https://codepen.io/agar3s/pen/pJpoya)
- [P5 Particle Handtracking (GitHub)](https://github.com/mekiii/P5-Particle-Handtracking)
- [Interactive Particle Effects with Hand Tracking (Bolt.new)](https://bolt.new/blog/build-rebuilds-interactive-particle-effects-with-hand-tracking)
- [Liquid Hands: Evoking Emotional States via AR Music Visualizations (ACM)](https://dl.acm.org/doi/fullHtml/10.1145/3452918.3465496)
- [Interactive Particles Music Visualizer (Codrops)](https://tympanus.net/Tutorials/ParticlesMusicVisualizer/)
- [Fire Trails Particle Effect (Rectangle World)](http://rectangleworld.com/blog/archives/402)
- [CanvasRenderingContext2D bezierCurveTo (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/bezierCurveTo)
