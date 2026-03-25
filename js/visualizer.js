/* ============================================================
   MUZE — Audio-Reactive Visualizer (v2)
   Upgraded: smooth waveform ring, frequency arc, mode geometry,
   note constellation, improved particles, beat detection.
   Canvas 2D only — optimized for 60fps on mobile.
   ============================================================ */

MUZE.Visualizer = {
  _canvas: null,
  _ctx: null,
  _width: 0,
  _height: 0,

  // ---- Particles ----
  _particles: [],
  _maxParticles: 40,

  // ---- Color cache (updated on mode change only) ----
  _cachedAccent: '#e8a948',
  _cachedAccentRgb: '232,169,72',
  _cachedModeName: '',

  // ---- Beat detection ----
  _lastBass: 0,
  _beatPulse: 0,
  _beatCount: 0,

  // ---- Note constellation ----
  _constellationNotes: [],   // { midi, x, y, life, size, hue }
  _maxConstellationNotes: 48,
  _lastMelodyNote: null,

  // ---- Mode geometry ----
  _geoPhase: 0,             // slow-rotating phase for background geometry

  // ---- Smooth frequency arc data ----
  _smoothFFTBins: null,      // smoothed FFT for the arc (avoid flicker)

  // ---- Waveform smoothing ----
  _smoothWaveform: null,

  // ---- Face mesh AR effects ----
  _FACE_OVAL: [10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109],
  _RIGHT_EYE: [33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246],
  _LEFT_EYE: [362,382,381,380,374,373,390,249,263,466,388,387,386,385,384,398],
  _LIPS_OUTER: [61,146,91,181,84,17,314,405,321,375,291,409,270,269,267,0,37,39,40,185],
  _RIGHT_BROW: [46,53,52,65,55,70,63,105,66,107],
  _LEFT_BROW: [276,283,282,295,285,300,293,334,296,336],
  _NOSE_BRIDGE: [168,6,197,195,5,4,1],
  _GLOW_LANDMARKS: [1, 33, 133, 362, 263, 61, 291, 105, 334, 10],

  // ---- Hand light trail ----
  _handTrail: [],
  _handTrailMax: 35,

  // ---- Note burst particles ----
  _burstParticles: [],
  _maxBurstParticles: 100,
  _lastBurstNote: null,
  _burstRings: [],

  // ---- Explosion particles (riser drop) ----
  _explosionParticles: [],

  // ---- Beat flash / bass warp ----
  _beatFlashEl: null,
  _beatFlashTimeout: null,
  _lastBassWarpTime: 0,

  init() {
    this._canvas = document.getElementById('overlay');
    this._ctx = this._canvas.getContext('2d');
    this._resize();
    window.addEventListener('resize', () => this._resize());
  },

  _resize() {
    const dpr = window.devicePixelRatio || 1;
    this._width = window.innerWidth;
    this._height = window.innerHeight;
    this._canvas.width = this._width * dpr;
    this._canvas.height = this._height * dpr;
    this._canvas.style.width = this._width + 'px';
    this._canvas.style.height = this._height + 'px';
    this._ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    // Reset smooth buffers on resize
    this._smoothFFTBins = null;
    this._smoothWaveform = null;
    // Reset hand trail on resize
    this._handTrail = [];
  },

  // ============================================================
  // MAIN DRAW
  // ============================================================
  draw() {
    const ctx = this._ctx;
    const w = this._width;
    const h = this._height;
    ctx.clearRect(0, 0, w, h);

    const waveform = MUZE.Audio.getWaveform();
    if (!waveform) return;

    // ---- Compute overall energy ----
    let energy = 0;
    for (let i = 0; i < waveform.length; i++) {
      energy += Math.abs(waveform[i]);
    }
    energy = energy / waveform.length;

    // ---- Cache accent color (only on mode change) ----
    const currentMode = MUZE.State.currentModeName;
    if (currentMode !== this._cachedModeName) {
      this._cachedModeName = currentMode;
      const colors = MUZE.Config.MODE_COLORS[currentMode];
      if (colors) {
        this._cachedAccent = colors.accent;
        this._cachedAccentRgb = colors.rgb;
      }
    }
    const accent = this._cachedAccent;
    const accentRgb = this._cachedAccentRgb;

    // ---- FFT frequency analysis ----
    const fft = MUZE.Audio.getFFT ? MUZE.Audio.getFFT() : null;
    let bass = 0, mid = 0, high = 0;
    if (fft) {
      const binCount = fft.length;
      for (let i = 0; i < binCount; i++) {
        const db = fft[i];
        const linear = Math.pow(10, db / 20);
        if (i < binCount * 0.1) bass += linear;
        else if (i < binCount * 0.4) mid += linear;
        else high += linear;
      }
      bass /= binCount * 0.1;
      mid /= binCount * 0.3;
      high /= binCount * 0.6;
    }

    // ---- Beat detection ----
    if (fft && bass > this._lastBass * 1.5 && bass > 0.15) {
      this._beatPulse = 1.0;
      this._beatCount++;
    }
    this._lastBass = bass;
    this._beatPulse *= 0.90; // slightly slower decay for more dramatic pulse

    // ---- Beat flash + bass warp (CSS overlay, zero canvas cost) ----
    if (this._beatPulse >= 0.95) {
      const flashEl = this._beatFlashEl || (this._beatFlashEl = document.getElementById('beat-flash-overlay'));
      if (flashEl) {
        flashEl.classList.add('flash');
        clearTimeout(this._beatFlashTimeout);
        this._beatFlashTimeout = setTimeout(() => flashEl.classList.remove('flash'), 50);
      }
      // Bass warp: scale pulse on strong kicks
      if (bass > 0.25) {
        const now = performance.now();
        if (now - this._lastBassWarpTime > 300) {
          this._lastBassWarpTime = now;
          const bgCanvas = document.getElementById('bg-canvas');
          if (bgCanvas) {
            bgCanvas.classList.remove('bass-warping');
            void bgCanvas.offsetWidth;
            bgCanvas.classList.add('bass-warping');
            setTimeout(() => bgCanvas.classList.remove('bass-warping'), 250);
          }
        }
      }
    }

    // ---- Advance geometry phase ----
    this._geoPhase += 0.003;

    // ---- Draw layers (back to front) ----
    // 1. Mode geometry (very faint background texture)
    this._drawModeGeometry(ctx, w, h, energy, accentRgb);

    // 2. Note constellation
    this._updateConstellation();
    this._drawConstellation(ctx, w, h, accentRgb);

    // 3. Circular waveform ring (the centerpiece)
    const cx = w / 2;
    const cy = h * 0.38;
    const baseRadius = Math.min(w, h) * 0.18;
    const beatExpand = this._beatPulse * 30;
    const radius = baseRadius + energy * 80 + beatExpand;

    this._drawWaveformRing(ctx, waveform, cx, cy, radius, energy, accentRgb);

    // 4. Particles
    const particleEnergy = fft ? Math.max(energy, mid * 2) : energy;
    this._updateParticles(particleEnergy, accentRgb, cx, cy, radius);
    this._drawParticles(ctx, accentRgb, high);

    // 5. Frequency arc (elegant bottom arc)
    this._drawFrequencyArc(ctx, fft, w, h, accentRgb, energy);

    // 6. Hand light trail
    this._updateHandTrail();
    this._drawHandTrail(ctx);

    // 7. Note burst particles
    this._updateBurstParticles();
    this._drawBurstParticles(ctx);

    // 8. Face mesh contour glow + landmark lights
    const landmarks = MUZE.State._rawLandmarks;
    if (landmarks && MUZE.State.faceDetected) {
      this._drawContourGlow(ctx, landmarks, w, h, accentRgb, energy, this._beatPulse);
      this._drawLandmarkLights(ctx, landmarks, w, h, accentRgb, energy, this._beatPulse);
    }

    // 9. Riser drop explosion particles
    this._updateAndDrawExplosion(ctx);
  },

  // ============================================================
  // 1. IMPROVED WAVEFORM RING
  //    - Quadratic curves for smoothness
  //    - Subtle radial fill
  //    - Dramatic beat glow
  // ============================================================
  _drawWaveformRing(ctx, waveform, cx, cy, radius, energy, accentRgb) {
    const len = waveform.length;

    // Smooth the waveform to remove jagged edges
    if (!this._smoothWaveform || this._smoothWaveform.length !== len) {
      this._smoothWaveform = new Float32Array(len);
    }
    const sw = this._smoothWaveform;
    const smoothAlpha = 0.4;
    for (let i = 0; i < len; i++) {
      sw[i] = sw[i] * (1 - smoothAlpha) + waveform[i] * smoothAlpha;
    }

    // Pre-compute points on the ring
    const points = new Array(len);
    for (let i = 0; i < len; i++) {
      const angle = (i / len) * Math.PI * 2 - Math.PI / 2;
      const amp = sw[i] * 40;
      const r = radius + amp;
      points[i] = {
        x: cx + Math.cos(angle) * r,
        y: cy + Math.sin(angle) * r
      };
    }

    // ---- Beat glow (dramatic outer bloom) ----
    if (this._beatPulse > 0.05) {
      const glowRadius = radius + this._beatPulse * 40;
      const glowAlpha = this._beatPulse * 0.25;
      ctx.beginPath();
      ctx.arc(cx, cy, glowRadius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, ${glowAlpha})`;
      ctx.lineWidth = 20 + this._beatPulse * 30;
      ctx.stroke();
    }

    // ---- Outer soft glow ring ----
    if (energy > 0.012) {
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, ${energy * 0.06})`;
      ctx.lineWidth = 14;
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, ${energy * 0.10})`;
      ctx.lineWidth = 4;
      ctx.stroke();
    }

    // ---- Build smooth waveform path using quadratic curves ----
    ctx.beginPath();
    // Start at the midpoint between last point and first point
    const startMidX = (points[len - 1].x + points[0].x) / 2;
    const startMidY = (points[len - 1].y + points[0].y) / 2;
    ctx.moveTo(startMidX, startMidY);

    for (let i = 0; i < len; i++) {
      const next = points[(i + 1) % len];
      const midX = (points[i].x + next.x) / 2;
      const midY = (points[i].y + next.y) / 2;
      ctx.quadraticCurveTo(points[i].x, points[i].y, midX, midY);
    }
    ctx.closePath();

    // ---- Subtle radial fill ----
    const fillAlpha = Math.min(0.08, energy * 0.15 + this._beatPulse * 0.06);
    if (fillAlpha > 0.005) {
      const grad = ctx.createRadialGradient(cx, cy, radius * 0.3, cx, cy, radius + 30);
      grad.addColorStop(0, `rgba(${accentRgb}, 0)`);
      grad.addColorStop(0.7, `rgba(${accentRgb}, ${fillAlpha * 0.5})`);
      grad.addColorStop(1, `rgba(${accentRgb}, ${fillAlpha})`);
      ctx.fillStyle = grad;
      ctx.fill();
    }

    // ---- Stroke the smooth waveform ----
    ctx.strokeStyle = `rgba(${accentRgb}, ${0.20 + energy * 0.5 + this._beatPulse * 0.3})`;
    ctx.lineWidth = 1.2 + this._beatPulse * 1.5;
    ctx.stroke();

    // ---- Inner thin reference circle ----
    ctx.beginPath();
    ctx.arc(cx, cy, radius * 0.85, 0, Math.PI * 2);
    ctx.strokeStyle = `rgba(${accentRgb}, 0.04)`;
    ctx.lineWidth = 0.5;
    ctx.stroke();
  },

  // ============================================================
  // 2. FREQUENCY ARC
  //    Elegant curved arc above the chord bar showing real-time
  //    FFT data as colored segments along an arc.
  // ============================================================
  _drawFrequencyArc(ctx, fft, w, h, accentRgb, energy) {
    if (!fft || energy < 0.008) return;

    const arcBins = 48; // number of segments in the arc
    const step = Math.max(1, Math.floor(fft.length / arcBins));

    // Initialize smoothed bins
    if (!this._smoothFFTBins || this._smoothFFTBins.length !== arcBins) {
      this._smoothFFTBins = new Float32Array(arcBins);
    }

    // Smooth FFT data for the arc
    for (let i = 0; i < arcBins; i++) {
      const db = fft[Math.min(i * step, fft.length - 1)];
      const linear = Math.max(0, (db + 100) / 100); // 0..1
      this._smoothFFTBins[i] = this._smoothFFTBins[i] * 0.7 + linear * 0.3;
    }

    // Arc geometry — sits above the chord bar area
    const arcCx = w / 2;
    const arcCy = h + 20; // center below screen bottom for a gentle upward curve
    const arcRadius = Math.min(w * 0.55, h * 0.5);
    const arcSpan = Math.PI * 0.55; // total arc span (roughly 100 degrees)
    const startAngle = Math.PI + (Math.PI - arcSpan) / 2; // centered on the top of the below-screen circle
    const segAngle = arcSpan / arcBins;

    // Parse accent color components for hue shifting
    const rgb = accentRgb.split(',').map(Number);

    for (let i = 0; i < arcBins; i++) {
      const val = this._smoothFFTBins[i];
      if (val < 0.05) continue; // skip silent bins

      const angle = startAngle + i * segAngle;
      const barHeight = val * 35 + 2;

      // Color: shift hue slightly across frequency range
      // Low freq = accent color, high freq = shifted brighter/cooler
      const freqRatio = i / arcBins;
      const r = Math.round(rgb[0] * (1 - freqRatio * 0.3) + 255 * freqRatio * 0.3);
      const g = Math.round(rgb[1] * (1 - freqRatio * 0.2) + 255 * freqRatio * 0.2);
      const b = Math.round(rgb[2] * (1 - freqRatio * 0.1) + 200 * freqRatio * 0.1);

      const alpha = 0.06 + val * 0.12;

      // Draw each segment as a small wedge along the arc
      const innerR = arcRadius - barHeight;
      const outerR = arcRadius;
      const aStart = angle - segAngle * 0.4;
      const aEnd = angle + segAngle * 0.4;

      ctx.beginPath();
      ctx.arc(arcCx, arcCy, outerR, aStart, aEnd);
      ctx.arc(arcCx, arcCy, innerR, aEnd, aStart, true);
      ctx.closePath();
      ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
      ctx.fill();
    }

    // Thin arc outline for elegance
    ctx.beginPath();
    ctx.arc(arcCx, arcCy, arcRadius, startAngle, startAngle + arcSpan);
    ctx.strokeStyle = `rgba(${accentRgb}, 0.04)`;
    ctx.lineWidth = 0.5;
    ctx.stroke();
  },

  // ============================================================
  // 3. MODE GEOMETRY
  //    Subtle geometric patterns in the background matching the
  //    current mode. Dark modes get angular shapes, bright modes
  //    get flowing curves. Very faint — texture only.
  // ============================================================
  _drawModeGeometry(ctx, w, h, energy, accentRgb) {
    const mode = this._cachedModeName;
    const phase = this._geoPhase;
    const alpha = 0.015 + energy * 0.02; // very faint
    if (alpha < 0.005) return;

    ctx.save();
    ctx.strokeStyle = `rgba(${accentRgb}, ${alpha})`;
    ctx.lineWidth = 0.5;

    // Mode character determines geometry type:
    // Darker modes (phrygian, aeolian) = angular, crystalline
    // Middle modes (dorian, mixolydian) = balanced hexagons/circles
    // Bright modes (ionian, lydian) = flowing curves, arcs

    const cx = w / 2;
    const cy = h * 0.38;
    const modeIndex = this._getModeIndex(mode);
    // modeIndex: 0 = darkest (phrygian), 5 = brightest (lydian)

    if (modeIndex <= 1) {
      // DARK: Angular shards — triangular fragments
      this._drawAngularShards(ctx, cx, cy, w, h, phase, alpha, accentRgb);
    } else if (modeIndex <= 3) {
      // MIDDLE: Hexagonal lattice
      this._drawHexLattice(ctx, cx, cy, w, h, phase, alpha, accentRgb);
    } else {
      // BRIGHT: Flowing orbital curves
      this._drawFlowingCurves(ctx, cx, cy, w, h, phase, alpha, accentRgb);
    }

    ctx.restore();
  },

  _getModeIndex(mode) {
    // Map mode names to a darkness-to-brightness scale (0=darkest, 5=brightest)
    const modeMap = {
      'phrygian': 0, 'phrygian dom': 0,
      'aeolian': 1, 'harm. minor': 1, 'pent. minor': 1, 'blues': 1,
      'dorian': 2, 'melodic minor': 2,
      'mixolydian': 3,
      'ionian': 4, 'pent. major': 4, 'whole tone': 4,
      'lydian': 5, 'hirajoshi': 3
    };
    return modeMap[mode] !== undefined ? modeMap[mode] : 2;
  },

  _drawAngularShards(ctx, cx, cy, w, h, phase, alpha, accentRgb) {
    // Sparse angular lines radiating from center, slowly rotating
    const count = 6;
    ctx.strokeStyle = `rgba(${accentRgb}, ${alpha * 0.8})`;
    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2 + phase * 0.7;
      const len = Math.min(w, h) * (0.25 + 0.1 * Math.sin(phase * 2 + i));
      const innerLen = len * 0.4;

      // Sharp zigzag line
      const x1 = cx + Math.cos(angle) * innerLen;
      const y1 = cy + Math.sin(angle) * innerLen;
      const midAngle = angle + 0.15 * Math.sin(phase + i * 1.3);
      const mx = cx + Math.cos(midAngle) * len * 0.7;
      const my = cy + Math.sin(midAngle) * len * 0.7;
      const x2 = cx + Math.cos(angle) * len;
      const y2 = cy + Math.sin(angle) * len;

      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(mx, my);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }

    // Small triangular fragments
    for (let i = 0; i < 3; i++) {
      const a = phase * 0.5 + i * 2.09; // ~120 degrees apart
      const dist = Math.min(w, h) * 0.22;
      const tx = cx + Math.cos(a) * dist;
      const ty = cy + Math.sin(a) * dist;
      const size = 15 + 5 * Math.sin(phase * 1.5 + i);

      ctx.beginPath();
      for (let j = 0; j < 3; j++) {
        const ta = a + (j / 3) * Math.PI * 2 + phase * 0.3;
        const px = tx + Math.cos(ta) * size;
        const py = ty + Math.sin(ta) * size;
        if (j === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.closePath();
      ctx.stroke();
    }
  },

  _drawHexLattice(ctx, cx, cy, w, h, phase, alpha, accentRgb) {
    // Faint hexagonal grid centered on the ring
    ctx.strokeStyle = `rgba(${accentRgb}, ${alpha * 0.6})`;
    const hexSize = 40;
    const rings = 3;

    for (let ring = 1; ring <= rings; ring++) {
      for (let i = 0; i < 6 * ring; i++) {
        // Position on hex ring
        const side = Math.floor(i / ring);
        const pos = i % ring;
        let hx = 0, hy = 0;

        // Hex directions
        const dirs = [
          [1, 0], [0.5, 0.866], [-0.5, 0.866],
          [-1, 0], [-0.5, -0.866], [0.5, -0.866]
        ];

        // Start corner
        const startDir = dirs[side];
        const nextDir = dirs[(side + 1) % 6];
        hx = startDir[0] * ring + (nextDir[0] - startDir[0]) * (pos / ring);
        hy = startDir[1] * ring + (nextDir[1] - startDir[1]) * (pos / ring);

        const px = cx + hx * hexSize;
        const py = cy + hy * hexSize;

        // Only draw if on screen
        if (px < -20 || px > w + 20 || py < -20 || py > h + 20) continue;

        // Small rotating hex at each position
        const rot = phase * 0.5 + ring * 0.3;
        const s = 4 + Math.sin(phase + ring + i * 0.2) * 2;
        ctx.beginPath();
        for (let v = 0; v < 6; v++) {
          const a = rot + (v / 6) * Math.PI * 2;
          const vx = px + Math.cos(a) * s;
          const vy = py + Math.sin(a) * s;
          if (v === 0) ctx.moveTo(vx, vy);
          else ctx.lineTo(vx, vy);
        }
        ctx.closePath();
        ctx.stroke();
      }
    }
  },

  _drawFlowingCurves(ctx, cx, cy, w, h, phase, alpha, accentRgb) {
    // Gentle orbital ellipses and spirals
    ctx.strokeStyle = `rgba(${accentRgb}, ${alpha * 0.7})`;
    const baseR = Math.min(w, h) * 0.2;

    // Orbital rings with varying eccentricity
    for (let i = 0; i < 4; i++) {
      const r = baseR * (0.6 + i * 0.25);
      const ecc = 0.15 + 0.05 * Math.sin(phase + i);
      const rot = phase * (0.3 + i * 0.1);

      ctx.beginPath();
      for (let a = 0; a <= Math.PI * 2; a += 0.08) {
        const rx = r * (1 + ecc * Math.cos(a * 2 + phase));
        const ry = r * (1 - ecc * Math.cos(a * 3));
        const px = cx + Math.cos(a + rot) * rx;
        const py = cy + Math.sin(a + rot) * ry;
        if (a === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.stroke();
    }

    // Small floating arcs
    for (let i = 0; i < 5; i++) {
      const arcAngle = phase * 0.6 + i * 1.257; // ~72 degrees apart
      const dist = baseR * (0.8 + 0.3 * Math.sin(phase * 0.8 + i));
      const ax = cx + Math.cos(arcAngle) * dist;
      const ay = cy + Math.sin(arcAngle) * dist;
      const arcR = 8 + 6 * Math.sin(phase * 1.2 + i * 0.9);
      const startA = arcAngle + phase;
      const sweep = Math.PI * (0.5 + 0.3 * Math.sin(phase + i));

      ctx.beginPath();
      ctx.arc(ax, ay, arcR, startA, startA + sweep);
      ctx.stroke();
    }
  },

  // ============================================================
  // 4. NOTE CONSTELLATION
  //    Glowing dots representing melody notes, positioned by
  //    musical interval. Creates a slowly fading musical memory map.
  // ============================================================
  _updateConstellation() {
    const currentNote = MUZE.State.melodyNote;

    // Add new note if melody note changed
    if (currentNote !== null && currentNote !== this._lastMelodyNote) {
      this._lastMelodyNote = currentNote;

      // Position based on musical interval from root
      const root = MUZE.Music.getEffectiveRoot();
      const interval = ((currentNote - root) % 12 + 12) % 12; // 0-11
      const octave = Math.floor((currentNote - root) / 12);

      // Map interval to position on a circle (like a clock face)
      // This creates a natural circular arrangement of the chromatic scale
      const angle = (interval / 12) * Math.PI * 2 - Math.PI / 2;
      // Distance from center based on octave
      const baseDist = Math.min(this._width, this._height) * 0.12;
      const dist = baseDist + octave * 25;

      const cx = this._width / 2;
      const cy = this._height * 0.38;

      this._constellationNotes.push({
        midi: currentNote,
        interval: interval,
        x: cx + Math.cos(angle) * dist,
        y: cy + Math.sin(angle) * dist,
        life: 1.0,
        decay: 0.003 + Math.random() * 0.002, // ~3-5 seconds visible
        size: 2.5 + Math.random() * 1.5,
        brightness: 1.0,  // starts bright, fades
      });

      // Limit notes
      while (this._constellationNotes.length > this._maxConstellationNotes) {
        this._constellationNotes.shift();
      }
    }

    if (currentNote === null) {
      this._lastMelodyNote = null;
    }

    // Decay all notes
    for (let i = this._constellationNotes.length - 1; i >= 0; i--) {
      const n = this._constellationNotes[i];
      n.life -= n.decay;
      n.brightness *= 0.997; // slow brightness fade
      if (n.life <= 0) {
        this._constellationNotes.splice(i, 1);
      }
    }
  },

  _drawConstellation(ctx, w, h, accentRgb) {
    const notes = this._constellationNotes;
    if (notes.length === 0) return;

    // Draw connection lines between recent consecutive notes
    if (notes.length > 1) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${accentRgb}, 0.04)`;
      ctx.lineWidth = 0.5;
      for (let i = 1; i < notes.length; i++) {
        const a = notes[i - 1];
        const b = notes[i];
        // Only connect notes that are both still fairly visible
        if (a.life > 0.2 && b.life > 0.2) {
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
        }
      }
      ctx.stroke();
    }

    // Draw constellation dots
    for (const n of notes) {
      const alpha = n.life * n.life * 0.6; // quadratic falloff
      if (alpha < 0.01) continue;

      // Outer glow
      const glowSize = n.size * (2 + n.brightness);
      ctx.beginPath();
      ctx.arc(n.x, n.y, glowSize, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${accentRgb}, ${alpha * 0.15})`;
      ctx.fill();

      // Core dot
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.size * n.life, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
      ctx.fill();

      // Bright center on fresh notes
      if (n.brightness > 0.5) {
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.size * 0.4, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255, 255, 255, ${alpha * n.brightness * 0.5})`;
        ctx.fill();
      }
    }

    // Draw faint interval reference circle (like a clock face)
    if (notes.length > 2) {
      const cx = w / 2;
      const cy = h * 0.38;
      const refR = Math.min(w, h) * 0.12;
      ctx.beginPath();
      ctx.arc(cx, cy, refR, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, 0.02)`;
      ctx.lineWidth = 0.5;
      ctx.stroke();
    }
  },

  // ============================================================
  // PARTICLES (existing system, kept intact)
  // ============================================================
  _updateParticles(energy, accentRgb, cx, cy, radius) {
    const spawnCount = energy > 0.03 ? Math.min(3, Math.floor(energy * 8)) : 0;
    for (let s = 0; s < spawnCount; s++) {
      if (this._particles.length >= this._maxParticles) break;
      const angle = Math.random() * Math.PI * 2;
      this._particles.push({
        x: cx + Math.cos(angle) * radius,
        y: cy + Math.sin(angle) * radius,
        vx: (Math.random() - 0.5) * 1.2,
        vy: -Math.random() * 1.5 - 0.3,
        life: 1,
        decay: 0.006 + Math.random() * 0.010,
        size: 0.5 + Math.random() * 1.2
      });
    }

    for (let i = this._particles.length - 1; i >= 0; i--) {
      const p = this._particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy -= 0.01;
      p.life -= p.decay;
      if (p.life <= 0) {
        // PERF: swap-and-pop O(1) removal
        this._particles[i] = this._particles[this._particles.length - 1];
        this._particles.pop();
      }
    }
  },

  _drawParticles(ctx, accentRgb, highEnergy) {
    const sparkle = highEnergy || 0;
    for (const p of this._particles) {
      const alpha = Math.min(1, p.life * p.life * 0.4 + sparkle * 0.3);
      ctx.beginPath();
      ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
  },

  // ============================================================
  // FACE CONTOUR GLOW — Multi-pass neon outline
  // ============================================================
  _drawContourGlow(ctx, landmarks, w, h, accentRgb, energy, beatPulse) {
    const contours = [this._FACE_OVAL, this._RIGHT_EYE, this._LEFT_EYE, this._LIPS_OUTER, this._RIGHT_BROW, this._LEFT_BROW, this._NOSE_BRIDGE];
    const closed =   [true,            true,            true,           true,             false,            false,           false];

    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    const passes = [
      { width: 8,  alpha: 0.03 + beatPulse * 0.06 },
      { width: 3,  alpha: 0.08 + energy * 0.1 + beatPulse * 0.12 },
      { width: 1,  alpha: 0.2 + energy * 0.25 + beatPulse * 0.3 },
    ];

    for (const pass of passes) {
      ctx.lineWidth = pass.width;
      ctx.strokeStyle = `rgba(${accentRgb}, ${Math.min(1, pass.alpha)})`;

      for (let c = 0; c < contours.length; c++) {
        const indices = contours[c];
        ctx.beginPath();
        for (let i = 0; i < indices.length; i++) {
          const lm = landmarks[indices[i]];
          if (!lm) continue;
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
  },

  // ============================================================
  // LANDMARK LIGHT POINTS — Glowing dots at key facial landmarks
  // ============================================================
  _drawLandmarkLights(ctx, landmarks, w, h, accentRgb, energy, beatPulse) {
    for (const idx of this._GLOW_LANDMARKS) {
      const lm = landmarks[idx];
      if (!lm) continue;
      const x = (1 - lm.x) * w;
      const y = lm.y * h;

      const baseRadius = 3;
      const radius = baseRadius + energy * 8 + beatPulse * 12;
      const alpha = 0.15 + energy * 0.3 + beatPulse * 0.4;

      const grad = ctx.createRadialGradient(x, y, 0, x, y, radius);
      grad.addColorStop(0, `rgba(${accentRgb}, ${Math.min(1, alpha)})`);
      grad.addColorStop(0.4, `rgba(${accentRgb}, ${alpha * 0.4})`);
      grad.addColorStop(1, `rgba(${accentRgb}, 0)`);

      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
  },

  // ============================================================
  // HAND LIGHT TRAIL — Fading ribbon following hand position
  // ============================================================
  _updateHandTrail() {
    const S = MUZE.State;
    if (!S.handPresent) {
      // Fade existing trail
      for (const p of this._handTrail) {
        p.alpha *= 0.90;
      }
      while (this._handTrail.length > 0 && this._handTrail[0].alpha < 0.01) {
        this._handTrail.shift();
      }
      return;
    }

    const w = this._width;
    const h = this._height;
    const px = S.handX * w;
    const py = S.handY * h;

    // Pitch-to-color: low=cool blue, high=warm orange
    const note = S.melodyNote || 60;
    const pitchNorm = Math.max(0, Math.min(1, (note - 48) / 36));
    const r = Math.round(40 + pitchNorm * 215);
    const g = Math.round(100 + pitchNorm * 60);
    const b = Math.round(250 - pitchNorm * 200);

    const baseWidth = S.handOpen ? 14 : 4;

    this._handTrail.push({
      x: px, y: py,
      width: baseWidth,
      r, g, b,
      alpha: 0.7
    });

    if (this._handTrail.length > this._handTrailMax) {
      this._handTrail.shift();
    }

    // Age points
    for (let i = 0; i < this._handTrail.length - 1; i++) {
      const age = 1 - (i / this._handTrail.length);
      this._handTrail[i].alpha = 0.7 * (1 - age * age);
    }
  },

  _drawHandTrail(ctx) {
    const trail = this._handTrail;
    if (trail.length < 3) return;

    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    for (let i = 1; i < trail.length; i++) {
      const prev = trail[i - 1];
      const curr = trail[i];
      const taper = i / trail.length;
      const alpha = curr.alpha * taper * taper;

      if (alpha < 0.005) continue;

      const lineWidth = curr.width * taper;
      if (lineWidth < 0.3) continue;

      ctx.beginPath();
      ctx.strokeStyle = `rgba(${curr.r},${curr.g},${curr.b},${alpha})`;
      ctx.lineWidth = lineWidth;

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
      ctx.shadowBlur = 15;
      ctx.fillStyle = `rgba(${head.r},${head.g},${head.b},0.6)`;
      ctx.arc(head.x, head.y, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.shadowBlur = 0;
    }

    ctx.restore();
  },

  // ============================================================
  // NOTE BURST PARTICLES — Expand from hand on note change
  // ============================================================
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

    const colors = MUZE.Config.MODE_COLORS[MUZE.State.currentModeName];
    const rgb = colors ? colors.rgb : '232,169,72';
    const [r, g, b] = rgb.split(',').map(Number);

    const count = Math.min(20, Math.max(3, Math.round(interval * 2)));
    const burstSpeed = 1.5 + interval * 0.4;

    for (let i = 0; i < count; i++) {
      if (this._burstParticles.length >= this._maxBurstParticles) {
        this._burstParticles.shift();
      }

      const angle = (i / count) * Math.PI * 2 + Math.random() * 0.3;
      const speed = burstSpeed * (0.7 + Math.random() * 0.6);

      this._burstParticles.push({
        x: cx, y: cy,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life: 1.0,
        decay: 0.015 + Math.random() * 0.01,
        size: 1.5 + interval * 0.3 + Math.random() * 1.5,
        r, g, b,
        gravity: -0.02
      });
    }

    // Expanding ring
    this._burstRings.push({
      x: cx, y: cy,
      radius: 5,
      maxRadius: 20 + interval * 5,
      alpha: 0.5,
      r, g, b,
      speed: 2 + interval * 0.6
    });
  },

  _updateBurstParticles() {
    for (let i = this._burstParticles.length - 1; i >= 0; i--) {
      const p = this._burstParticles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy += p.gravity;
      p.vx *= 0.98;
      p.vy *= 0.98;
      p.life -= p.decay;
      if (p.life <= 0) {
        this._burstParticles[i] = this._burstParticles[this._burstParticles.length - 1];
        this._burstParticles.pop();
      }
    }

    for (let i = this._burstRings.length - 1; i >= 0; i--) {
      const ring = this._burstRings[i];
      ring.radius += ring.speed;
      ring.alpha *= 0.93;
      if (ring.alpha < 0.01 || ring.radius > ring.maxRadius) {
        this._burstRings.splice(i, 1);
      }
    }
  },

  _drawBurstParticles(ctx) {
    for (const p of this._burstParticles) {
      const alpha = p.life * p.life;
      ctx.beginPath();
      ctx.fillStyle = `rgba(${p.r},${p.g},${p.b},${alpha})`;
      ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
      ctx.fill();
    }

    for (const ring of this._burstRings) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${ring.r},${ring.g},${ring.b},${ring.alpha})`;
      ctx.lineWidth = 1.5 * ring.alpha;
      ctx.arc(ring.x, ring.y, ring.radius, 0, Math.PI * 2);
      ctx.stroke();
    }
  },

  // ============================================================
  // RISER DROP EXPLOSION — Particle burst from center on drop
  // ============================================================
  triggerExplosion(x, y, count) {
    x = x || this._width / 2;
    y = y || this._height * 0.4;
    count = count || 100;
    const rgb = this._cachedAccentRgb;

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 2 + Math.random() * 8;
      const size = 1 + Math.random() * 3;
      this._explosionParticles.push({
        x: x, y: y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 1,
        life: 1.0,
        decay: 0.012 + Math.random() * 0.008,
        size: size,
        rgb: rgb,
        gravity: 0.04 + Math.random() * 0.02,
        drag: 0.98
      });
    }
  },

  _updateAndDrawExplosion(ctx) {
    for (let i = this._explosionParticles.length - 1; i >= 0; i--) {
      const p = this._explosionParticles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vx *= p.drag;
      p.vy *= p.drag;
      p.vy += p.gravity;
      p.life -= p.decay;

      if (p.life <= 0) {
        this._explosionParticles[i] = this._explosionParticles[this._explosionParticles.length - 1];
        this._explosionParticles.pop();
        continue;
      }

      const alpha = p.life * p.life;
      ctx.beginPath();
      ctx.fillStyle = `rgba(${p.rgb}, ${alpha * 0.7})`;
      ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
      ctx.fill();
    }
  }
};
