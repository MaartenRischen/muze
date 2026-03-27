/* ============================================================
   MUZE — Audio-Reactive Visualizer (v3)
   Concert-grade: multi-layer waveform ring with beat bloom &
   shockwaves, premium frequency arc with mirror reflection &
   peak hold, mode geometry, note constellation, particles.
   Canvas 2D only — optimized for 60fps on mobile.
   ============================================================ */

MUZE.Visualizer = {
  _canvas: null,
  _ctx: null,
  _width: 0,
  _height: 0,

  // ---- Particles ----
  _particles: [],
  _maxParticles: 25,

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
  _FACE_OVAL: [10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109,10],
  _LEFT_EYE: [33,246,161,160,159,158,157,173,133,155,154,153,145,144,163,7,33],
  _RIGHT_EYE: [263,466,388,387,386,385,384,398,362,382,381,380,374,373,390,249,263],
  _LIPS_OUTER: [61,146,91,181,84,17,314,405,321,375,291,409,270,269,267,0,37,39,40,185,61],
  _LEFT_BROW: [70,63,105,66,107,55,65,52,53,46],
  _RIGHT_BROW: [300,293,334,296,336,285,295,282,283,276],
  _NOSE_BRIDGE: [168,6,197,195,5,4,1],
  _GLOW_LANDMARKS: [1, 33, 133, 362, 263, 61, 291, 105, 334, 10],

  // ---- Face effect: expression particles ----
  _faceParticles: [],
  _maxFaceParticles: 40,

  // ---- Face effect: head rotation ghost trails ----
  _contourSnapshots: [],  // [{points: Float32Array, time: number, opacity: number}]
  _maxSnapshots: 4,
  _lastHeadYaw: 0,
  _lastHeadRoll: 0,

  // ---- Face effect: pre-computed mirrored landmarks per frame ----
  _mirroredLandmarks: null,

  // ---- Hand light painting trail (offscreen canvas) ----
  _trailCanvas: null,
  _trailCtx: null,
  _prevTrailPos: null,
  _handGlowRadius: 8,       // current glow radius (lerps open/closed)
  _handGlowTarget: 8,       // target glow radius
  _handBloomRadius: 30,     // current bloom radius
  _handBloomTarget: 30,     // target bloom radius

  // ---- Note burst particles ----
  _burstParticles: [],
  _maxBurstParticles: 50,
  _lastBurstNote: null,
  _burstRings: [],

  // ---- Connection web (hand-to-face) ----
  _connectionPulse: 0,

  // ---- Explosion particles (riser drop) ----
  _explosionParticles: [],

  // ---- Beat flash / bass warp ----
  _beatFlashEl: null,
  _beatFlashTimeout: null,
  _lastBassWarpTime: 0,

  // ---- Ring rotation (frame counter based) ----
  _ringRotationFrame: 0,

  // ---- Beat bloom animation ----
  _beatBloomRadius: 0,     // current bloom expansion (0 = none)
  _beatBloomTarget: 0,     // target bloom (set on beat, decays)
  _beatBloomVelocity: 0,   // for elastic snap
  _shockwaves: [],         // [{radius, alpha, speed}]

  // ---- Frequency arc peak hold ----
  _peakHoldBins: null,     // peak values per bin
  _peakHoldDecay: null,    // decay velocity per bin
  _bassWarping: false,

  // ---- Mode color grading ----
  _cachedGradeMode: '',

  // ---- Vignette throttle ----
  _lastVignetteOpacity: 0,

  // ---- Explosion screen glow ----
  _explosionGlow: null,  // { x, y, life, startTime }

  // ---- Behind-canvas (waveform ring + halo rendered behind user) ----
  _behindCanvas: null, _behindCtx: null,
  _haloRays: [],
  _haloRings: [],
  _haloGlow: 0,
  _haloFlash: 0,
  _faceCx: 0, _faceCy: 0,

  // ---- Arpeggio visualization (vertical, dual) ----
  _arp1LastIdx: -1, _arp1Flash: 0, _arp1Sparks: [],
  _arp2LastIdx: -1, _arp2Flash: 0, _arp2Sparks: [],

  init() {
    this._canvas = document.getElementById('overlay');
    this._ctx = this._canvas.getContext('2d');
    this._behindCanvas = document.getElementById('behind-canvas');
    if (this._behindCanvas) this._behindCtx = this._behindCanvas.getContext('2d');
    // Create offscreen trail canvas for light painting persistence
    this._trailCanvas = document.createElement('canvas');
    this._trailCtx = this._trailCanvas.getContext('2d');
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
    if (this._behindCanvas) {
      this._behindCanvas.width = this._width * dpr;
      this._behindCanvas.height = this._height * dpr;
      this._behindCanvas.style.width = this._width + 'px';
      this._behindCanvas.style.height = this._height + 'px';
      this._behindCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    // Reset smooth buffers on resize
    this._smoothFFTBins = null;
    this._smoothWaveform = null;
    // Resize offscreen trail canvas (match DPR)
    if (this._trailCanvas) {
      this._trailCanvas.width = this._width * dpr;
      this._trailCanvas.height = this._height * dpr;
      this._trailCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this._prevTrailPos = null;
    }
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
      // Trigger beat bloom — elastic snap outward
      this._beatBloomTarget = 1.0;
      this._beatBloomVelocity = 0.25;
      // Emit shockwave ring
      this._shockwaves.push({ radius: 0, alpha: 0.4, speed: 4 + bass * 6 });
      if (this._shockwaves.length > 5) this._shockwaves.shift();
    }
    this._lastBass = bass;
    this._beatPulse *= 0.90; // slightly slower decay for more dramatic pulse

    // ---- Animate beat bloom (elastic out, slow settle) ----
    this._beatBloomRadius += this._beatBloomVelocity;
    const bloomDiff = this._beatBloomTarget - this._beatBloomRadius;
    this._beatBloomVelocity += bloomDiff * 0.15;
    this._beatBloomVelocity *= 0.78;
    this._beatBloomTarget *= 0.94;

    // ---- Advance ring rotation (frame counter) ----
    this._ringRotationFrame++;

    // ---- Beat flash + bass warp (CSS overlay, zero canvas cost) ----
    if (this._beatPulse >= 0.95) {
      const flashEl = this._beatFlashEl || (this._beatFlashEl = document.getElementById('beat-flash-overlay'));
      if (flashEl) {
        flashEl.classList.add('flash');
        clearTimeout(this._beatFlashTimeout);
        this._beatFlashTimeout = setTimeout(() => flashEl.classList.remove('flash'), 50);
      }
      // Bass warp: scale pulse on strong kicks (bg-canvas)
      if (bass > 0.25) {
        const now = performance.now();
        if (now - this._lastBassWarpTime > 300) {
          this._lastBassWarpTime = now;
          const bgCanvas = document.getElementById('bg-canvas');
          if (bgCanvas) {
            bgCanvas.classList.remove('bass-warping');
            // Use rAF to re-trigger animation without forced reflow
            requestAnimationFrame(() => {
              bgCanvas.classList.add('bass-warping');
              setTimeout(() => bgCanvas.classList.remove('bass-warping'), 250);
            });
          }
        }
      }
    }

    // ---- Bass warp on #cam (CSS transform, preserves mirror) ----
    if (bass > 0.25 && !this._bassWarping) {
      this._bassWarping = true;
      document.getElementById('cam').classList.add('bass-warp');
      setTimeout(() => { document.getElementById('cam').classList.remove('bass-warp'); this._bassWarping = false; }, 150);
    }

    // Mode color grading REMOVED — was overwriting bgblur's filter on #cam,
    // causing the background blur to disappear and the camera to darken.
    // Vignette writes REMOVED — vignette is display:none.

    // ---- Advance geometry phase ----
    this._geoPhase += 0.003;

    // ---- Draw layers (back to front) ----
    // 1. Mode geometry (very faint background texture)
    this._drawModeGeometry(ctx, w, h, energy, accentRgb);

    // 2. Note constellation
    this._updateConstellation();
    this._drawConstellation(ctx, w, h, accentRgb);

    // Pre-compute face position early so all layers can use it
    const landmarks = MUZE.State._rawLandmarks;
    const hasFace = landmarks && MUZE.State.faceDetected;
    if (hasFace) {
      this._computeMirroredLandmarks(landmarks, w, h);
      // Track face center from nose tip
      const ml = this._mirroredLandmarks;
      if (ml && ml[1]) {
        this._faceCx += (ml[1].x - this._faceCx) * 0.2;
        this._faceCy += (ml[1].y - this._faceCy) * 0.2;
      }
    } else if (this._faceCx === 0) {
      this._faceCx = w / 2;
      this._faceCy = h * 0.35;
    }

    // 3. Waveform ring + beat halo → drawn on behind-canvas (behind user)
    //    Follow the face so it sits like a halo behind the head
    const cx = this._faceCx;
    const headR = Math.min(w, h) * 0.14;
    const cy = this._faceCy - headR * 0.5; // offset up half a head
    const baseRadius = Math.min(w, h) * 0.54;
    const beatExpand = this._beatPulse * 30;
    const bloomExpand = this._beatBloomRadius * baseRadius * 0.18;
    const radius = baseRadius + energy * 80 + beatExpand + bloomExpand;

    if (this._behindCtx) {
      this._behindCtx.clearRect(0, 0, w, h);
      this._drawWaveformRing(this._behindCtx, waveform, cx, cy, radius, energy, accentRgb);
      this._drawBeatHalo(this._behindCtx, w, h, bass, energy, accentRgb);
    } else {
      // Fallback if behind-canvas not available
      this._drawWaveformRing(ctx, waveform, cx, cy, radius, energy, accentRgb);
    }

    // 4. Particles
    const particleEnergy = fft ? Math.max(energy, mid * 2) : energy;
    this._updateParticles(particleEnergy, accentRgb, cx, cy, radius);
    this._drawParticles(ctx, accentRgb, high);

    // 4b. Arpeggio orbital visualization
    this._updateAndDrawArpViz(ctx, cx, cy, radius, energy, accentRgb);

    // 5. Frequency arc (elegant bottom arc)
    this._drawFrequencyArc(ctx, fft, w, h, accentRgb, energy);

    // 6. Hand light painting trail (offscreen canvas composite)
    this._updateLightPainting();
    this._drawLightPainting(ctx);

    // 6b. Connection web (hand-to-face threads)
    this._drawConnectionWeb(ctx, energy);

    // 7. Note burst particles
    this._updateBurstParticles();
    this._drawBurstParticles(ctx);

    // 8. Face mesh AR effects (contour glow, iris, particles, aura, trails)
    if (hasFace) {
      const ml = this._mirroredLandmarks;

      // 8a. Head rotation ghost trails (drawn first, behind everything)
      this._updateContourSnapshots(ml);
      this._drawContourTrails(ctx, w, h, accentRgb);

      // 8b. Energy aura (soft outer glow, behind contour)
      this._drawEnergyAura(ctx, ml, w, h, accentRgb, energy, this._beatPulse);

      // 8c. Glowing face contour (the signature Tron look)
      this._drawContourGlow(ctx, ml, w, h, accentRgb, energy, this._beatPulse);

      // 8d. Iris glow (pulsing with audio)
      this._drawIrisGlow(ctx, landmarks, ml, w, h, accentRgb, energy, this._beatPulse);

      // 8e. Landmark light points
      this._drawLandmarkLights(ctx, ml, w, h, accentRgb, energy, this._beatPulse);

      // 8f. Expression particles (mouth + eye sparkles)
      this._updateFaceParticles(ml, w, h, energy, this._beatPulse, accentRgb);
      this._drawFaceParticles(ctx, accentRgb);
    }

    // 9. Riser drop explosion particles
    this._updateAndDrawExplosion(ctx);
  },

  // ============================================================
  // 1. CONCERT-GRADE WAVEFORM RING
  //    - Smooth Bezier curves (quadraticCurveTo)
  //    - 3-pass multi-layer: outer glow, core ring, hot core
  //    - Radial gradient fill that pulses with energy
  //    - Beat bloom with elastic snap + shockwave rings
  //    - Slow rotation via frame counter
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

    // Ring rotation: 0.5 degrees per frame (~30 deg/sec at 60fps)
    const rotationRad = (this._ringRotationFrame * 0.5) * (Math.PI / 180);

    // Pre-compute points on the ring (with rotation applied)
    const points = new Array(len);
    for (let i = 0; i < len; i++) {
      const angle = (i / len) * Math.PI * 2 - Math.PI / 2 + rotationRad;
      const amp = sw[i] * 40;
      const r = radius + amp;
      points[i] = {
        x: cx + Math.cos(angle) * r,
        y: cy + Math.sin(angle) * r
      };
    }

    // Helper: build smooth Bezier ring path from points array
    const buildRingPath = () => {
      ctx.beginPath();
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
    };

    // ---- Shockwave rings (expanding outward from beat) ----
    for (let i = this._shockwaves.length - 1; i >= 0; i--) {
      const sw2 = this._shockwaves[i];
      sw2.radius += sw2.speed;
      sw2.alpha *= 0.94;
      sw2.speed *= 0.98;
      if (sw2.alpha < 0.005) {
        // PERF: swap-and-pop O(1) removal
        this._shockwaves[i] = this._shockwaves[this._shockwaves.length - 1];
        this._shockwaves.pop();
        continue;
      }
      const shockR = radius + sw2.radius;
      ctx.beginPath();
      ctx.arc(cx, cy, shockR, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, ${sw2.alpha})`;
      ctx.lineWidth = 2 * sw2.alpha + 0.5;
      ctx.stroke();
    }

    // ---- Radial gradient fill INSIDE the ring (pulses with energy) ----
    const fillBase = 0.02 + energy * 0.06 + this._beatPulse * 0.04;
    const fillAlpha = Math.min(0.10, fillBase);
    if (fillAlpha > 0.005) {
      const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
      grad.addColorStop(0, `rgba(${accentRgb}, ${fillAlpha * 0.7})`);
      grad.addColorStop(0.5, `rgba(${accentRgb}, ${fillAlpha * 0.3})`);
      grad.addColorStop(0.85, `rgba(${accentRgb}, ${fillAlpha * 0.6})`);
      grad.addColorStop(1, `rgba(${accentRgb}, 0)`);
      buildRingPath();
      ctx.fillStyle = grad;
      ctx.fill();
    }

    // ---- PASS 1: Outer glow (wide, faint, accent color) ----
    const glowIntensify = this._beatPulse > 0.3 ? 2.0 : 1.0; // double alpha during bloom
    buildRingPath();
    ctx.strokeStyle = `rgba(${accentRgb}, ${0.06 * glowIntensify})`;
    ctx.lineWidth = 12;
    ctx.stroke();

    // ---- PASS 2: Core ring (medium, accent color) ----
    buildRingPath();
    ctx.strokeStyle = `rgba(${accentRgb}, ${0.35 + energy * 0.4 + this._beatPulse * 0.25})`;
    ctx.lineWidth = 2;
    ctx.stroke();

    // ---- PASS 3: Hot core (thin, white, bright center line) ----
    buildRingPath();
    ctx.strokeStyle = `rgba(255, 255, 255, ${0.5 + energy * 0.5 + this._beatPulse * 0.3})`;
    ctx.lineWidth = 0.5;
    ctx.stroke();

    // ---- Beat glow bloom (dramatic wide glow during beat) ----
    if (this._beatPulse > 0.05) {
      const glowRadius = radius + this._beatPulse * 40;
      const glowAlpha = this._beatPulse * 0.2;
      ctx.beginPath();
      ctx.arc(cx, cy, glowRadius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, ${glowAlpha})`;
      ctx.lineWidth = 20 + this._beatPulse * 30;
      ctx.stroke();
    }

    // ---- Inner thin reference circle ----
    ctx.beginPath();
    ctx.arc(cx, cy, radius * 0.85, 0, Math.PI * 2);
    ctx.strokeStyle = `rgba(${accentRgb}, 0.04)`;
    ctx.lineWidth = 0.5;
    ctx.stroke();
  },

  // ============================================================
  // 1b. ARPEGGIO VERTICAL VISUALIZATION (dual columns)
  //     High notes = top, low notes = bottom.
  //     Arp1 on the left, Arp2 on the right of the waveform ring.
  //     Active note blazes with glow + sparks.
  // ============================================================
  _noteNameToMidi(name) {
    if (typeof name === 'number') return name;
    const match = String(name).match(/^([A-Ga-g]#?)(-?\d+)$/);
    if (!match) return 60;
    const noteMap = { C:0,'C#':1,D:2,'D#':3,E:4,F:5,'F#':6,G:7,'G#':8,A:9,'A#':10,B:11 };
    return (noteMap[match[1].toUpperCase()] || 0) + (parseInt(match[2]) + 1) * 12;
  },

  _updateAndDrawArpViz(ctx, cx, cy, ringRadius, energy, accentRgb) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';

    const colOffset = ringRadius + 50;
    const vH = Math.min(280, cy * 0.65);
    const topY = cy - vH / 2;
    const botY = cy + vH / 2;

    // Draw arp1 (left) and arp2 (right)
    this._drawArpColumn(ctx, cx - colOffset, topY, botY, vH,
      MUZE.Audio._arpNotes, MUZE.Audio._arpIdx,
      '_arp1LastIdx', '_arp1Flash', '_arp1Sparks',
      energy, accentRgb, '#4ade80', '74,222,128');
    this._drawArpColumn(ctx, cx + colOffset, topY, botY, vH,
      MUZE.Audio._arp2Notes, MUZE.Audio._arp2Idx,
      '_arp2LastIdx', '_arp2Flash', '_arp2Sparks',
      energy, accentRgb, '#34d399', '52,211,153');

    ctx.restore();
  },

  _drawArpColumn(ctx, colX, topY, botY, vH, notes, rawIdx, lastIdxKey, flashKey, sparksKey, energy, accentRgb, color, colorRgb) {
    if (!notes || notes.length === 0) return;

    const n = notes.length;
    const currentIdx = rawIdx % n;

    // Convert to MIDI for pitch mapping
    const midis = notes.map(n => this._noteNameToMidi(n));
    const minM = Math.min(...midis);
    const maxM = Math.max(...midis);
    const range = Math.max(maxM - minM, 1);

    // Map MIDI → Y (high = top, low = bottom)
    const midiToY = (m) => botY - ((m - minM) / range) * vH;

    // Detect note change → flash + sparks
    if (currentIdx !== this[lastIdxKey]) {
      this[flashKey] = 1.0;
      this[lastIdxKey] = currentIdx;

      const sy = midiToY(midis[currentIdx]);
      const { r, g, b } = this._noteToRgb(midis[currentIdx]);
      for (let s = 0; s < 5; s++) {
        const angle = Math.random() * Math.PI * 2;
        const speed = 1 + Math.random() * 2.5;
        this[sparksKey].push({
          x: colX, y: sy,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed - 1,
          life: 1.0, decay: 0.025 + Math.random() * 0.02,
          r, g, b,
        });
      }
    }
    this[flashKey] *= 0.88;
    const flash = this[flashKey];

    // --- Faint vertical guide ---
    ctx.beginPath();
    ctx.moveTo(colX, topY);
    ctx.lineTo(colX, botY);
    ctx.strokeStyle = `rgba(${colorRgb}, 0.06)`;
    ctx.lineWidth = 1;
    ctx.stroke();

    // --- Draw sequence path (connect notes in pattern order) ---
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const y = midiToY(midis[i]);
      const x = colX + (i / (n - 1 || 1) - 0.5) * 16; // slight horizontal spread for pattern shape
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.strokeStyle = `rgba(${colorRgb}, 0.08)`;
    ctx.lineWidth = 1;
    ctx.stroke();

    // --- Draw note dots ---
    for (let i = 0; i < n; i++) {
      const y = midiToY(midis[i]);
      const x = colX;
      const { r, g, b } = this._noteToRgb(midis[i]);
      const isActive = (i === currentIdx);

      if (isActive) {
        const glowSize = 10 + flash * 16 + energy * 6;

        // Outer glow
        const grad = ctx.createRadialGradient(x, y, 0, x, y, glowSize);
        grad.addColorStop(0, `rgba(${r},${g},${b},${(0.8 + flash * 0.2).toFixed(2)})`);
        grad.addColorStop(0.35, `rgba(${r},${g},${b},${(0.25 + flash * 0.3).toFixed(2)})`);
        grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
        ctx.beginPath();
        ctx.arc(x, y, glowSize, 0, Math.PI * 2);
        ctx.fillStyle = grad;
        ctx.fill();

        // White-hot core
        ctx.beginPath();
        ctx.arc(x, y, 3 + flash * 3, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255,255,255,${(0.7 + flash * 0.3).toFixed(2)})`;
        ctx.fill();

        // Horizontal bar pulse
        ctx.beginPath();
        ctx.moveTo(x - 12 - flash * 8, y);
        ctx.lineTo(x + 12 + flash * 8, y);
        ctx.strokeStyle = `rgba(${r},${g},${b},${(0.3 + flash * 0.4).toFixed(2)})`;
        ctx.lineWidth = 2;
        ctx.stroke();
      } else {
        const dist = Math.min(Math.abs(i - currentIdx), Math.abs(i - currentIdx + n), Math.abs(i - currentIdx - n));
        const prox = Math.max(0, 1 - dist / (n * 0.4));
        const a = 0.12 + prox * 0.2;
        const sz = 1.5 + prox * 1.5;

        ctx.beginPath();
        ctx.arc(x, y, sz + 3, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(${r},${g},${b},${(a * 0.25).toFixed(2)})`;
        ctx.fill();

        ctx.beginPath();
        ctx.arc(x, y, sz, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(${r},${g},${b},${a.toFixed(2)})`;
        ctx.fill();
      }
    }

    // --- Update and draw sparks ---
    const sparks = this[sparksKey];
    for (let i = sparks.length - 1; i >= 0; i--) {
      const s = sparks[i];
      s.x += s.vx; s.y += s.vy;
      s.vx *= 0.95; s.vy *= 0.95;
      s.life -= s.decay;
      if (s.life <= 0) { sparks[i] = sparks[sparks.length - 1]; sparks.pop(); continue; }
      ctx.beginPath();
      ctx.arc(s.x, s.y, 1.5 * s.life, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${s.r},${s.g},${s.b},${(s.life * s.life).toFixed(2)})`;
      ctx.fill();
    }
    if (sparks.length > 60) sparks.length = 60;
  },

  // ============================================================
  // BEAT HALO — dramatic pulsing light AROUND user's head
  // Gradients start from head radius outward — nothing draws over the face
  // ============================================================
  _drawBeatHalo(ctx, w, h, bass, energy, accentRgb) {
    const headR = Math.min(w, h) * 0.42; // 3x original
    const cx = this._faceCx;
    const cy = this._faceCy - headR * 0.25; // offset up half a head
    const bp = this._beatPulse;
    const bloom = this._beatBloomRadius;

    // Update halo state
    this._haloGlow += (energy * 0.6 + bp * 0.8 - this._haloGlow) * 0.12;
    if (bp > 0.8) this._haloFlash = 1.0;
    this._haloFlash *= 0.85;

    // Spawn rays on beat
    if (bp > 0.9 && this._haloRays.length < 24) {
      const count = 8 + Math.floor(bass * 8);
      for (let i = 0; i < count; i++) {
        const angle = (i / count) * Math.PI * 2 + (Math.random() - 0.5) * 0.3;
        this._haloRays.push({
          angle,
          length: headR + 20 + Math.random() * 80 + bass * 100,
          width: 1.5 + Math.random() * 3,
          life: 1.0,
          decay: 0.015 + Math.random() * 0.015,
          speed: 2 + Math.random() * 4,
        });
      }
    }

    // Spawn expanding rings on beat
    if (bp > 0.85 && this._haloRings.length < 6) {
      this._haloRings.push({
        radius: headR + 5,
        alpha: 0.6 + bass * 0.3,
        speed: 3 + bass * 5,
        width: 2 + bass * 3,
      });
    }

    const glow = this._haloGlow;
    if (glow < 0.01 && this._haloRays.length === 0 && this._haloRings.length === 0) return;

    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    const flash = this._haloFlash;

    // === PASS 1: Outer glow (starts from head edge, expands outward) ===
    const outerR = headR + 80 + glow * 200 + bloom * 60;
    const outerGrad = ctx.createRadialGradient(cx, cy, headR, cx, cy, outerR);
    outerGrad.addColorStop(0, `rgba(${accentRgb}, 0)`);
    outerGrad.addColorStop(0.02, `rgba(${accentRgb}, ${(glow * 0.3 + flash * 0.2).toFixed(2)})`);
    outerGrad.addColorStop(0.4, `rgba(${accentRgb}, ${(glow * 0.12).toFixed(2)})`);
    outerGrad.addColorStop(1, `rgba(${accentRgb}, 0)`);
    ctx.beginPath();
    ctx.arc(cx, cy, outerR, 0, Math.PI * 2);
    ctx.fillStyle = outerGrad;
    ctx.fill();

    // === PASS 2: Bright rim at head edge ===
    const rimR = headR + 25 + glow * 40 + bp * 20;
    const rimGrad = ctx.createRadialGradient(cx, cy, headR - 2, cx, cy, rimR);
    const cR = Math.min(255, parseInt(accentRgb.split(',')[0]) + flash * 150);
    const cG = Math.min(255, parseInt(accentRgb.split(',')[1]) + flash * 150);
    const cB = Math.min(255, parseInt(accentRgb.split(',')[2]) + flash * 150);
    rimGrad.addColorStop(0, `rgba(${Math.round(cR)},${Math.round(cG)},${Math.round(cB)}, 0)`);
    rimGrad.addColorStop(0.02, `rgba(${Math.round(cR)},${Math.round(cG)},${Math.round(cB)},${(0.2 + glow * 0.3 + flash * 0.4).toFixed(2)})`);
    rimGrad.addColorStop(0.5, `rgba(${accentRgb}, ${(glow * 0.1).toFixed(2)})`);
    rimGrad.addColorStop(1, `rgba(${accentRgb}, 0)`);
    ctx.beginPath();
    ctx.arc(cx, cy, rimR, 0, Math.PI * 2);
    ctx.fillStyle = rimGrad;
    ctx.fill();

    // === PASS 3: White-hot flash ring on strong beats ===
    if (flash > 0.05) {
      const flashR = headR + 50 + flash * 50;
      const flashGrad = ctx.createRadialGradient(cx, cy, headR, cx, cy, flashR);
      flashGrad.addColorStop(0, 'rgba(255,255,255,0)');
      flashGrad.addColorStop(0.02, `rgba(255,255,255,${(flash * 0.4).toFixed(2)})`);
      flashGrad.addColorStop(0.4, `rgba(255,255,255,${(flash * 0.1).toFixed(2)})`);
      flashGrad.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.beginPath();
      ctx.arc(cx, cy, flashR, 0, Math.PI * 2);
      ctx.fillStyle = flashGrad;
      ctx.fill();
    }

    // === PASS 4: Radiant light rays (start from head edge) ===
    for (let i = this._haloRays.length - 1; i >= 0; i--) {
      const ray = this._haloRays[i];
      ray.length += ray.speed;
      ray.life -= ray.decay;
      if (ray.life <= 0) { this._haloRays[i] = this._haloRays[this._haloRays.length - 1]; this._haloRays.pop(); continue; }

      const a = ray.life * ray.life;
      const x1 = cx + Math.cos(ray.angle) * headR;
      const y1 = cy + Math.sin(ray.angle) * headR;
      const x2 = cx + Math.cos(ray.angle) * ray.length;
      const y2 = cy + Math.sin(ray.angle) * ray.length;

      const rayGrad = ctx.createLinearGradient(x1, y1, x2, y2);
      rayGrad.addColorStop(0, `rgba(${accentRgb}, ${(a * 0.4).toFixed(2)})`);
      rayGrad.addColorStop(0.3, `rgba(${accentRgb}, ${(a * 0.15).toFixed(2)})`);
      rayGrad.addColorStop(1, `rgba(${accentRgb}, 0)`);

      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.strokeStyle = rayGrad;
      ctx.lineWidth = ray.width * ray.life;
      ctx.stroke();
    }

    // === PASS 5: Expanding shockwave rings (start from head edge) ===
    for (let i = this._haloRings.length - 1; i >= 0; i--) {
      const ring = this._haloRings[i];
      ring.radius += ring.speed;
      ring.alpha *= 0.96;
      if (ring.alpha < 0.01) { this._haloRings[i] = this._haloRings[this._haloRings.length - 1]; this._haloRings.pop(); continue; }

      ctx.beginPath();
      ctx.arc(cx, cy, ring.radius, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(${accentRgb}, ${ring.alpha.toFixed(2)})`;
      ctx.lineWidth = ring.width;
      ctx.stroke();
    }

    ctx.restore();
  },

  // ============================================================
  // 2. PREMIUM FREQUENCY ARC
  //    - Rounded rectangle bars along a gentle curved arc
  //    - Gradient from accent (bass) to brighter (treble)
  //    - Temporal smoothing for silky motion
  //    - Mirror reflection below (alpha 0.3, flipped)
  //    - Peak hold dots with gravity decay
  // ============================================================
  _drawFrequencyArc(ctx, fft, w, h, accentRgb, energy) {
    if (!fft || energy < 0.008) return;

    const arcBins = 64; // more bins for finer resolution
    const step = Math.max(1, Math.floor(fft.length / arcBins));

    // Initialize smoothed bins + peak hold
    if (!this._smoothFFTBins || this._smoothFFTBins.length !== arcBins) {
      this._smoothFFTBins = new Float32Array(arcBins);
      this._peakHoldBins = new Float32Array(arcBins);
      this._peakHoldDecay = new Float32Array(arcBins);
    }

    // Smooth FFT data (temporal lerp to prevent jitter)
    for (let i = 0; i < arcBins; i++) {
      const db = fft[Math.min(i * step, fft.length - 1)];
      const linear = Math.max(0, (db + 100) / 100); // 0..1
      this._smoothFFTBins[i] = this._smoothFFTBins[i] * 0.72 + linear * 0.28;

      // Peak hold: jump up instantly, fall with gravity
      if (this._smoothFFTBins[i] > this._peakHoldBins[i]) {
        this._peakHoldBins[i] = this._smoothFFTBins[i];
        this._peakHoldDecay[i] = 0; // reset velocity
      } else {
        this._peakHoldDecay[i] += 0.0008; // gravity acceleration
        this._peakHoldBins[i] -= this._peakHoldDecay[i];
        if (this._peakHoldBins[i] < 0) this._peakHoldBins[i] = 0;
      }
    }

    // Arc geometry — gentle curve above the chord bar
    const arcCx = w / 2;
    const arcCy = h + h * 0.35; // center well below screen for gentle upward curve
    const arcRadius = Math.min(w * 0.6, h * 0.55);
    const arcSpan = Math.PI * 0.50; // ~90 degrees of arc
    const startAngle = Math.PI + (Math.PI - arcSpan) / 2;

    // Bar sizing
    const barWidth = 5;  // 5px wide bars
    const barGap = 2;    // 2px gap
    const totalBarSpace = barWidth + barGap;

    // Parse accent color for gradient
    const rgb = accentRgb.split(',').map(Number);

    ctx.save();
    ctx.lineCap = 'round';

    // Compute bar positions along the arc
    const segAngle = arcSpan / arcBins;
    const maxBarH = 55; // maximum bar height in pixels

    for (let pass = 0; pass < 2; pass++) {
      // pass 0 = mirror reflection (drawn first, behind)
      // pass 1 = main bars
      const isMirror = pass === 0;
      const passAlpha = isMirror ? 0.15 : 1.0;

      for (let i = 0; i < arcBins; i++) {
        const val = this._smoothFFTBins[i];
        if (val < 0.03 && !isMirror) continue;

        const angle = startAngle + (i + 0.5) * segAngle;
        const barH = val * maxBarH + 1;

        // Position on the arc: the base of the bar sits on the arc
        const baseX = arcCx + Math.cos(angle) * arcRadius;
        const baseY = arcCy + Math.sin(angle) * arcRadius;

        // Direction vector pointing inward (toward center) for bar growth
        const dx = Math.cos(angle);
        const dy = Math.sin(angle);

        // Color gradient: bass = accent, treble = brighter/whiter
        const freqRatio = i / arcBins;
        const r = Math.round(rgb[0] + (255 - rgb[0]) * freqRatio * 0.5);
        const g = Math.round(rgb[1] + (255 - rgb[1]) * freqRatio * 0.4);
        const b = Math.round(rgb[2] + (255 - rgb[2]) * freqRatio * 0.3);

        const alpha = (0.15 + val * 0.55) * passAlpha;

        ctx.save();
        ctx.translate(baseX, baseY);
        // Rotate so the bar grows radially inward (toward center)
        ctx.rotate(angle + Math.PI / 2);

        if (isMirror) {
          // Mirror: flip vertically, draw below the arc baseline
          ctx.scale(1, -1);
          ctx.translate(0, -1); // slight offset down
        }

        // Draw rounded rectangle bar
        const bw = barWidth;
        const bh = barH;
        const borderR = Math.min(2, bw / 2, bh / 2); // rounded top
        ctx.beginPath();
        ctx.moveTo(-bw / 2, 0);
        ctx.lineTo(-bw / 2, -bh + borderR);
        ctx.quadraticCurveTo(-bw / 2, -bh, -bw / 2 + borderR, -bh);
        ctx.lineTo(bw / 2 - borderR, -bh);
        ctx.quadraticCurveTo(bw / 2, -bh, bw / 2, -bh + borderR);
        ctx.lineTo(bw / 2, 0);
        ctx.closePath();
        ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`;
        ctx.fill();

        // On main pass, add subtle glow on energetic bars
        if (!isMirror && val > 0.4) {
          ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${(val - 0.4) * 0.15})`;
          const glowBw = bw + 4;
          ctx.beginPath();
          ctx.moveTo(-glowBw / 2, 2);
          ctx.lineTo(-glowBw / 2, -bh - 2);
          ctx.lineTo(glowBw / 2, -bh - 2);
          ctx.lineTo(glowBw / 2, 2);
          ctx.closePath();
          ctx.fill();
        }

        ctx.restore();

        // Peak hold dot (main pass only)
        if (!isMirror) {
          const peakVal = this._peakHoldBins[i];
          if (peakVal > 0.05) {
            const peakH = peakVal * maxBarH + 3;
            // Position the dot at the peak height along the radial direction
            const dotX = baseX - dx * peakH;
            const dotY = baseY - dy * peakH;
            ctx.beginPath();
            ctx.arc(dotX, dotY, 1.5, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(255, 255, 255, ${0.4 + peakVal * 0.3})`;
            ctx.fill();
          }
        }
      }
    }

    // Thin arc baseline for elegance
    ctx.beginPath();
    ctx.arc(arcCx, arcCy, arcRadius, startAngle, startAngle + arcSpan);
    ctx.strokeStyle = `rgba(${accentRgb}, 0.06)`;
    ctx.lineWidth = 0.5;
    ctx.stroke();

    ctx.restore();
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
        // PERF: swap-and-pop O(1) removal
        this._constellationNotes[i] = this._constellationNotes[this._constellationNotes.length - 1];
        this._constellationNotes.pop();
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
  // PRE-COMPUTE MIRRORED LANDMARKS (once per frame)
  // ============================================================
  _computeMirroredLandmarks(landmarks, w, h) {
    const count = landmarks.length;
    if (!this._mirroredLandmarks || this._mirroredLandmarks.length !== count) {
      this._mirroredLandmarks = new Array(count);
      for (let i = 0; i < count; i++) this._mirroredLandmarks[i] = { x: 0, y: 0 };
    }
    const ml = this._mirroredLandmarks;
    for (let i = 0; i < count; i++) {
      const lm = landmarks[i];
      ml[i].x = (1 - lm.x) * w;
      ml[i].y = lm.y * h;
    }
  },

  // ============================================================
  // GLOWING FACE CONTOUR — Multi-pass neon outline (Tron/cyberpunk)
  // ============================================================
  _drawContourGlow(ctx, ml, w, h, accentRgb, energy, beatPulse) {
    const contours = [
      this._FACE_OVAL, this._LEFT_EYE, this._RIGHT_EYE,
      this._LIPS_OUTER, this._LEFT_BROW, this._RIGHT_BROW, this._NOSE_BRIDGE
    ];

    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // 3-pass neon glow: wide dim -> medium -> thin bright core
    // Subtle enhancement — not overwhelming (max alpha: 0.06 / 0.12 / 0.3)
    const passes = [
      { width: 8,   alpha: 0.06 },
      { width: 4,   alpha: 0.12 },
      { width: 1.5, alpha: 0.3 },
    ];

    for (const pass of passes) {
      ctx.lineWidth = pass.width;
      ctx.strokeStyle = `rgba(${accentRgb}, ${Math.min(1, pass.alpha)})`;

      // Batch all contours into a single beginPath/stroke per pass
      ctx.beginPath();
      for (let c = 0; c < contours.length; c++) {
        const indices = contours[c];
        for (let i = 0; i < indices.length; i++) {
          const pt = ml[indices[i]];
          if (!pt) continue;
          if (i === 0) ctx.moveTo(pt.x, pt.y);
          else ctx.lineTo(pt.x, pt.y);
        }
      }
      ctx.stroke();
    }

    ctx.restore();
  },

  // ============================================================
  // IRIS GLOW — Pulsing radial glow at iris centers
  // ============================================================
  _drawIrisGlow(ctx, rawLandmarks, ml, w, h, accentRgb, energy, beatPulse) {
    let irisPoints;
    if (rawLandmarks.length > 473) {
      irisPoints = [
        { x: (1 - rawLandmarks[468].x) * w, y: rawLandmarks[468].y * h },
        { x: (1 - rawLandmarks[473].x) * w, y: rawLandmarks[473].y * h }
      ];
    } else {
      const approxCenter = (indices) => {
        let sx = 0, sy = 0;
        for (const idx of indices) { sx += ml[idx].x; sy += ml[idx].y; }
        return { x: sx / indices.length, y: sy / indices.length };
      };
      irisPoints = [
        approxCenter([33, 133, 159, 145]),
        approxCenter([263, 362, 386, 374])
      ];
    }

    ctx.save();
    ctx.globalCompositeOperation = 'lighter';

    const pulseScale = 1.0 + energy * 0.8 + beatPulse * 1.2;
    const baseRadius = 6 * pulseScale;
    const baseAlpha = 0.2 + energy * 0.4 + beatPulse * 0.3;

    for (const iris of irisPoints) {
      const r = baseRadius;

      // Outer soft glow
      const outerGrad = ctx.createRadialGradient(iris.x, iris.y, 0, iris.x, iris.y, r * 3);
      outerGrad.addColorStop(0, `rgba(${accentRgb}, ${Math.min(1, baseAlpha * 0.6)})`);
      outerGrad.addColorStop(0.3, `rgba(${accentRgb}, ${baseAlpha * 0.25})`);
      outerGrad.addColorStop(1, `rgba(${accentRgb}, 0)`);
      ctx.fillStyle = outerGrad;
      ctx.beginPath();
      ctx.arc(iris.x, iris.y, r * 3, 0, Math.PI * 2);
      ctx.fill();

      // Inner bright core (white center fading to accent)
      const coreGrad = ctx.createRadialGradient(iris.x, iris.y, 0, iris.x, iris.y, r);
      coreGrad.addColorStop(0, `rgba(255, 255, 255, ${Math.min(1, baseAlpha * 0.7)})`);
      coreGrad.addColorStop(0.4, `rgba(${accentRgb}, ${Math.min(1, baseAlpha * 0.5)})`);
      coreGrad.addColorStop(1, `rgba(${accentRgb}, 0)`);
      ctx.fillStyle = coreGrad;
      ctx.beginPath();
      ctx.arc(iris.x, iris.y, r, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.restore();
  },

  // ============================================================
  // EXPRESSION PARTICLES — Mouth emission + eye sparkle
  // ============================================================
  _updateFaceParticles(ml, w, h, energy, beatPulse, accentRgb) {
    const S = MUZE.State;

    // Mouth particles: emit when mouth is open (singing)
    const mouthOpen = S.mouthOpenness || 0;
    if (mouthOpen > 0.15) {
      const mouthCx = (ml[0].x + ml[17].x) * 0.5;
      const mouthCy = (ml[0].y + ml[17].y) * 0.5;
      const spawnCount = Math.min(4, Math.floor(mouthOpen * 6 + beatPulse * 3));

      for (let s = 0; s < spawnCount; s++) {
        if (this._faceParticles.length >= this._maxFaceParticles) break;
        this._faceParticles.push({
          x: mouthCx + (Math.random() - 0.5) * 12,
          y: mouthCy,
          vx: (Math.random() - 0.5) * 2.5,
          vy: -Math.random() * 2.5 - 0.8,
          life: 1.0,
          decay: 0.015 + Math.random() * 0.015,
          size: 1.0 + Math.random() * 2.0,
          type: 'mouth'
        });
      }
    }

    // Eye sparkle particles: wide eyes = reverb = sparkle
    const eyeOpen = S.eyeOpenness || 0;
    if (eyeOpen > 0.7) {
      const sparkleIntensity = (eyeOpen - 0.7) / 0.3;
      const spawnCount = Math.min(2, Math.floor(sparkleIntensity * 3));

      const eyeCenters = [
        { x: (ml[33].x + ml[133].x) * 0.5, y: (ml[33].y + ml[133].y) * 0.5 },
        { x: (ml[263].x + ml[362].x) * 0.5, y: (ml[263].y + ml[362].y) * 0.5 }
      ];

      for (const eye of eyeCenters) {
        for (let s = 0; s < spawnCount; s++) {
          if (this._faceParticles.length >= this._maxFaceParticles) break;
          const angle = Math.random() * Math.PI * 2;
          this._faceParticles.push({
            x: eye.x + (Math.random() - 0.5) * 6,
            y: eye.y + (Math.random() - 0.5) * 6,
            vx: Math.cos(angle) * (0.5 + Math.random() * 1.5),
            vy: Math.sin(angle) * (0.5 + Math.random() * 1.5) - 0.3,
            life: 1.0,
            decay: 0.02 + Math.random() * 0.015,
            size: 0.6 + Math.random() * 1.2,
            type: 'eye'
          });
        }
      }
    }

    // Update all face particles
    for (let i = this._faceParticles.length - 1; i >= 0; i--) {
      const p = this._faceParticles[i];
      p.x += p.vx;
      p.y += p.vy;
      if (p.type === 'mouth') p.vy -= 0.03;
      p.vx *= 0.98;
      p.vy *= 0.98;
      p.life -= p.decay;
      if (p.life <= 0) {
        this._faceParticles[i] = this._faceParticles[this._faceParticles.length - 1];
        this._faceParticles.pop();
      }
    }
  },

  _drawFaceParticles(ctx, accentRgb) {
    if (this._faceParticles.length === 0) return;

    ctx.save();
    ctx.globalCompositeOperation = 'lighter';

    for (const p of this._faceParticles) {
      const alpha = p.life * p.life * 0.6;
      if (alpha < 0.01) continue;

      if (p.type === 'eye') {
        ctx.fillStyle = `rgba(255, 255, 255, ${alpha * 0.7})`;
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size * p.life * 0.7, 0, Math.PI * 2);
        ctx.fill();
      }

      ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size * p.life, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.restore();
  },

  // ============================================================
  // ENERGY AURA — Soft breathing glow around face contour
  // ============================================================
  _drawEnergyAura(ctx, ml, w, h, accentRgb, energy, beatPulse) {
    if (energy < 0.02 && beatPulse < 0.1) return;

    const ovalIndices = this._FACE_OVAL;
    if (!ovalIndices || ovalIndices.length === 0) return;

    let fcx = 0, fcy = 0;
    for (let i = 0; i < ovalIndices.length; i++) {
      const pt = ml[ovalIndices[i]];
      fcx += pt.x; fcy += pt.y;
    }
    fcx /= ovalIndices.length;
    fcy /= ovalIndices.length;

    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    const expand = 15 + beatPulse * 10;
    const auraAlpha = 0.03 + energy * 0.06 + beatPulse * 0.05;

    const auraPasses = [
      { width: 30, alpha: auraAlpha * 0.4 },
      { width: 15, alpha: auraAlpha * 0.7 },
    ];

    for (const pass of auraPasses) {
      ctx.lineWidth = pass.width;
      ctx.strokeStyle = `rgba(${accentRgb}, ${Math.min(0.15, pass.alpha)})`;

      ctx.beginPath();
      for (let i = 0; i < ovalIndices.length; i++) {
        const pt = ml[ovalIndices[i]];
        const dx = pt.x - fcx;
        const dy = pt.y - fcy;
        const dist = Math.sqrt(dx * dx + dy * dy) || 1;
        const ex = pt.x + (dx / dist) * expand;
        const ey = pt.y + (dy / dist) * expand;
        if (i === 0) ctx.moveTo(ex, ey);
        else ctx.lineTo(ex, ey);
      }
      ctx.stroke();
    }

    ctx.restore();
  },

  // ============================================================
  // HEAD ROTATION TRAILS — Ghost traces at previous positions
  // ============================================================
  _updateContourSnapshots(ml) {
    const S = MUZE.State;
    const yaw = S.headYaw || 0;
    const roll = S.headRoll || 0;

    const yawDelta = Math.abs(yaw - this._lastHeadYaw);
    const rollDelta = Math.abs(roll - this._lastHeadRoll);
    const moving = yawDelta > 0.012 || rollDelta > 0.012;

    this._lastHeadYaw = yaw;
    this._lastHeadRoll = roll;

    if (moving) {
      const ovalIndices = this._FACE_OVAL;
      const snapshot = new Float32Array(ovalIndices.length * 2);
      for (let i = 0; i < ovalIndices.length; i++) {
        const pt = ml[ovalIndices[i]];
        snapshot[i * 2] = pt.x;
        snapshot[i * 2 + 1] = pt.y;
      }
      this._contourSnapshots.push({ points: snapshot, opacity: 0.3 });

      while (this._contourSnapshots.length > this._maxSnapshots) {
        this._contourSnapshots.shift();
      }
    }

    for (let i = this._contourSnapshots.length - 1; i >= 0; i--) {
      this._contourSnapshots[i].opacity *= 0.88;
      if (this._contourSnapshots[i].opacity < 0.01) {
        // PERF: swap-and-pop O(1) removal
        this._contourSnapshots[i] = this._contourSnapshots[this._contourSnapshots.length - 1];
        this._contourSnapshots.pop();
      }
    }
  },

  _drawContourTrails(ctx, w, h, accentRgb) {
    if (this._contourSnapshots.length === 0) return;

    ctx.save();
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    const ovalLen = this._FACE_OVAL.length;

    for (const snap of this._contourSnapshots) {
      const a = snap.opacity;
      if (a < 0.005) continue;

      ctx.lineWidth = 1.5;
      ctx.strokeStyle = `rgba(${accentRgb}, ${a * 0.5})`;
      ctx.beginPath();
      for (let i = 0; i < ovalLen; i++) {
        const px = snap.points[i * 2];
        const py = snap.points[i * 2 + 1];
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.stroke();

      ctx.lineWidth = 5;
      ctx.strokeStyle = `rgba(${accentRgb}, ${a * 0.15})`;
      ctx.beginPath();
      for (let i = 0; i < ovalLen; i++) {
        const px = snap.points[i * 2];
        const py = snap.points[i * 2 + 1];
        if (i === 0) ctx.moveTo(px, py);
        else ctx.lineTo(px, py);
      }
      ctx.stroke();
    }

    ctx.restore();
  },

  // ============================================================
  // LANDMARK LIGHT POINTS — Glowing dots at key facial landmarks
  // ============================================================
  _drawLandmarkLights(ctx, ml, w, h, accentRgb, energy, beatPulse) {
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';

    for (const idx of this._GLOW_LANDMARKS) {
      const pt = ml[idx];
      if (!pt) continue;

      const baseRadius = 3;
      const radius = baseRadius + energy * 8 + beatPulse * 12;
      const alpha = 0.15 + energy * 0.3 + beatPulse * 0.4;

      const grad = ctx.createRadialGradient(pt.x, pt.y, 0, pt.x, pt.y, radius);
      grad.addColorStop(0, `rgba(${accentRgb}, ${Math.min(1, alpha)})`);
      grad.addColorStop(0.4, `rgba(${accentRgb}, ${alpha * 0.4})`);
      grad.addColorStop(1, `rgba(${accentRgb}, 0)`);

      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, radius, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.restore();
  },

  // ============================================================
  // HAND LIGHT PAINTING — Offscreen canvas with persistence fade
  // Long-exposure photography effect. 3-layer glow. Pitch color.
  // ============================================================

  _noteToTrailColor(note) {
    if (note == null) note = 60;
    const n = Math.max(36, Math.min(72, note));
    let h, s, l;
    if (n <= 48) {
      const t = (n - 36) / 12;
      h = 220 + (170 - 220) * t; s = 80; l = 60;
    } else if (n <= 60) {
      const t = (n - 48) / 12;
      h = 170 + (35 - 170) * t;
      s = 80 + (90 - 80) * t; l = 60 + (65 - 60) * t;
    } else {
      const t = Math.min(1, (n - 60) / 12);
      h = 35 - t * 10; s = 90; l = 65 + t * 5;
    }
    return `hsl(${Math.round(h)}, ${Math.round(s)}%, ${Math.round(l)}%)`;
  },

  _noteToRgb(note) {
    if (note == null) note = 60;
    const nrm = Math.max(0, Math.min(1, (note - 36) / 36));
    let r, g, b;
    if (nrm < 0.33) {
      const t = nrm / 0.33;
      r = Math.round(60 + t * 40); g = Math.round(100 + t * 80); b = Math.round(200 + t * 55);
    } else if (nrm < 0.66) {
      const t = (nrm - 0.33) / 0.33;
      r = Math.round(100 + t * 130); g = Math.round(180 + t * 20); b = Math.round(255 - t * 180);
    } else {
      const t = (nrm - 0.66) / 0.34;
      r = Math.round(230 + t * 25); g = Math.round(200 - t * 60); b = Math.round(75 - t * 40);
    }
    return { r, g, b };
  },

  _updateLightPainting() {
    if (!this._trailCanvas) return;
    const tctx = this._trailCtx;
    const w = this._width, h = this._height;
    const S = MUZE.State;

    // Fade previous content by erasing (not painting black!)
    // Using destination-out so the trail canvas stays transparent, not dark
    tctx.globalCompositeOperation = 'destination-out';
    tctx.fillStyle = 'rgba(0, 0, 0, 0.02)';
    tctx.fillRect(0, 0, w, h);
    tctx.globalCompositeOperation = 'source-over';

    // Finger spread: lerp glow sizes (~100ms)
    if (S.handPresent) {
      this._handGlowTarget = S.handOpen ? 20 : 8;
      this._handBloomTarget = S.handOpen ? 45 : 18;
    }
    this._handGlowRadius += (this._handGlowTarget - this._handGlowRadius) * 0.3;
    this._handBloomRadius += (this._handBloomTarget - this._handBloomRadius) * 0.3;

    if (S.handPresent) {
      const px = S.handX * w, py = S.handY * h;
      const color = this._noteToTrailColor(S.melodyNote);
      const glow = this._handGlowRadius;
      const bloom = this._handBloomRadius;
      const core = S.handOpen ? 4 : 2;

      if (this._prevTrailPos) {
        const dx = px - this._prevTrailPos.x;
        const dy = py - this._prevTrailPos.y;
        if (dx * dx + dy * dy > 0.25) {
          tctx.lineCap = 'round';
          tctx.globalCompositeOperation = 'lighter';

          // Outer bloom
          tctx.beginPath(); tctx.strokeStyle = color;
          tctx.globalAlpha = 0.08; tctx.lineWidth = bloom;
          tctx.moveTo(this._prevTrailPos.x, this._prevTrailPos.y);
          tctx.lineTo(px, py); tctx.stroke();

          // Inner glow
          tctx.beginPath(); tctx.strokeStyle = color;
          tctx.globalAlpha = 0.35; tctx.lineWidth = glow;
          tctx.moveTo(this._prevTrailPos.x, this._prevTrailPos.y);
          tctx.lineTo(px, py); tctx.stroke();

          // Core white
          tctx.beginPath(); tctx.strokeStyle = '#ffffff';
          tctx.globalAlpha = 0.9; tctx.lineWidth = core;
          tctx.moveTo(this._prevTrailPos.x, this._prevTrailPos.y);
          tctx.lineTo(px, py); tctx.stroke();
          tctx.globalAlpha = 1.0;
        }
      }

      // 3-layer radial glow dot at hand position
      tctx.globalCompositeOperation = 'lighter';
      tctx.beginPath(); tctx.globalAlpha = 0.15;
      tctx.fillStyle = color;
      tctx.arc(px, py, bloom * 0.7, 0, Math.PI * 2); tctx.fill();

      tctx.beginPath(); tctx.globalAlpha = 0.6;
      tctx.fillStyle = color;
      tctx.arc(px, py, glow * 0.6, 0, Math.PI * 2); tctx.fill();

      tctx.beginPath(); tctx.globalAlpha = 1.0;
      tctx.fillStyle = '#ffffff';
      tctx.arc(px, py, core * 0.75, 0, Math.PI * 2); tctx.fill();
      tctx.globalAlpha = 1.0;

      this._prevTrailPos = { x: px, y: py };
    } else {
      this._prevTrailPos = null;
    }
    tctx.globalCompositeOperation = 'source-over';
  },

  _drawLightPainting(ctx) {
    if (!this._trailCanvas) return;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.drawImage(this._trailCanvas, 0, 0, this._width, this._height);
    ctx.restore();
  },

  // ============================================================
  // CONNECTION WEB — Curved glowing threads between hand and face
  // ============================================================
  _drawConnectionWeb(ctx, energy) {
    const S = MUZE.State;
    if (!S.handPresent || !S.faceDetected) return;
    const landmarks = S._rawLandmarks;
    if (!landmarks) return;
    const w = this._width, h = this._height;
    const hx = S.handX * w, hy = S.handY * h;
    const accentRgb = this._cachedAccentRgb;

    const idxs = [1, 152, 10, 105, 334]; // nose, chin, forehead, brows
    const targets = [];
    for (const idx of idxs) {
      const lm = landmarks[idx];
      if (lm) targets.push({ x: (1 - lm.x) * w, y: lm.y * h });
    }
    if (targets.length === 0) return;

    this._connectionPulse += 0.04;
    const pulse = 0.7 + Math.sin(this._connectionPulse) * 0.3;
    const baseAlpha = (0.02 + Math.min(0.06, energy * 0.4)) * pulse;

    ctx.save(); ctx.lineWidth = 0.8; ctx.lineCap = 'round';
    for (const t of targets) {
      const mx = (hx + t.x) / 2, my = (hy + t.y) / 2;
      const dx = t.x - hx, dy = t.y - hy;
      const len = Math.sqrt(dx * dx + dy * dy) || 1;
      const bow = len * 0.08;
      const cpx = mx + (-dy / len) * bow;
      const cpy = my + (dx / len) * bow;

      ctx.beginPath();
      ctx.strokeStyle = `rgba(${accentRgb}, ${baseAlpha})`;
      ctx.moveTo(hx, hy);
      ctx.quadraticCurveTo(cpx, cpy, t.x, t.y);
      ctx.stroke();

      if (baseAlpha > 0.015) {
        ctx.beginPath();
        ctx.fillStyle = `rgba(${accentRgb}, ${baseAlpha * 1.5})`;
        ctx.arc(t.x, t.y, 1.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.restore();
  },

  // ============================================================
  // NOTE BURST — Expanding ring + radial particles, pitch-colored
  // ============================================================
  _triggerNoteBurst(note, handX, handY) {
    if (this._lastBurstNote === null) {
      this._lastBurstNote = note;
      return;
    }
    const interval = Math.abs(note - this._lastBurstNote);
    this._lastBurstNote = note;
    if (interval === 0) return;

    const cx = handX * this._width;
    const cy = handY * this._height;
    const { r, g, b } = this._noteToRgb(note);

    const count = Math.min(20, Math.max(5, Math.round(interval * 1.7)));
    const burstSpeed = 1.5 + interval * 0.5;

    for (let i = 0; i < count; i++) {
      if (this._burstParticles.length >= this._maxBurstParticles) {
        // PERF: swap oldest (index 0) with last, then pop — avoids O(n) shift
        this._burstParticles[0] = this._burstParticles[this._burstParticles.length - 1];
        this._burstParticles.pop();
      }
      const angle = (i / count) * Math.PI * 2 + Math.random() * 0.4;
      const speed = burstSpeed * (0.6 + Math.random() * 0.8);
      this._burstParticles.push({
        x: cx, y: cy,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life: 1.0,
        decay: 0.014 + Math.random() * 0.012,
        size: 1.5 + interval * 0.35 + Math.random() * 1.5,
        r, g, b,
        gravity: -0.02
      });
    }
    // Expanding ring (0 -> max over ~400ms)
    const ringMax = Math.min(60, 15 + interval * 5);
    this._burstRings.push({
      x: cx, y: cy, radius: 0,
      maxRadius: ringMax, alpha: 0.6,
      r, g, b, speed: ringMax / 24
    });
  },

  _updateBurstParticles() {
    for (let i = this._burstParticles.length - 1; i >= 0; i--) {
      const p = this._burstParticles[i];
      p.x += p.vx; p.y += p.vy;
      p.vy += p.gravity;
      p.vx *= 0.97; p.vy *= 0.97;
      p.life -= p.decay;
      if (p.life <= 0) {
        this._burstParticles[i] = this._burstParticles[this._burstParticles.length - 1];
        this._burstParticles.pop();
      }
    }
    for (let i = this._burstRings.length - 1; i >= 0; i--) {
      const ring = this._burstRings[i];
      ring.radius += ring.speed;
      ring.alpha *= 0.94;
      if (ring.alpha < 0.01 || ring.radius > ring.maxRadius) {
        // PERF: swap-and-pop O(1) removal
        this._burstRings[i] = this._burstRings[this._burstRings.length - 1];
        this._burstRings.pop();
      }
    }
  },

  _drawBurstParticles(ctx) {
    for (const p of this._burstParticles) {
      const alpha = p.life * p.life;
      if (alpha < 0.01) continue;
      const sz = p.size * p.life;
      // Additive outer glow
      ctx.globalCompositeOperation = 'lighter';
      ctx.beginPath();
      ctx.fillStyle = `rgba(${p.r},${p.g},${p.b},${alpha * 0.3})`;
      ctx.arc(p.x, p.y, sz * 2, 0, Math.PI * 2);
      ctx.fill();
      // Core
      ctx.globalCompositeOperation = 'source-over';
      ctx.beginPath();
      ctx.fillStyle = `rgba(${p.r},${p.g},${p.b},${alpha})`;
      ctx.arc(p.x, p.y, sz, 0, Math.PI * 2);
      ctx.fill();
    }
    for (const ring of this._burstRings) {
      if (ring.alpha < 0.01) continue;
      ctx.globalCompositeOperation = 'lighter';
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${ring.r},${ring.g},${ring.b},${ring.alpha})`;
      ctx.lineWidth = 2 * ring.alpha + 0.5;
      ctx.arc(ring.x, ring.y, ring.radius, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalCompositeOperation = 'source-over';
  },

  // ============================================================
  // RISER DROP EXPLOSION — Particle burst from center on drop
  // ============================================================
  triggerExplosion(x, y, count) {
    x = x || this._width / 2;
    y = y || this._height * 0.4;
    count = count || 120;
    const rgb = this._cachedAccentRgb;

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 2 + Math.random() * 8;
      const size = 2 + Math.random() * 4; // 2-6px particles
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
    // Screen-wide glow at explosion center (fades over 500ms)
    this._explosionGlow = { x: x, y: y, life: 1.0 };
  },

  _updateAndDrawExplosion(ctx) {
    // Screen-wide glow (large soft circle at explosion center, fades over ~500ms)
    if (this._explosionGlow && this._explosionGlow.life > 0) {
      const g = this._explosionGlow;
      g.life -= 0.033; // ~30 frames = 500ms at 60fps
      if (g.life > 0) {
        const glowRadius = Math.min(this._width, this._height) * 0.4;
        const glowAlpha = g.life * g.life * 0.15;
        const rgb = this._cachedAccentRgb;
        const grad = ctx.createRadialGradient(g.x, g.y, 0, g.x, g.y, glowRadius);
        grad.addColorStop(0, `rgba(${rgb}, ${glowAlpha})`);
        grad.addColorStop(1, `rgba(${rgb}, 0)`);
        ctx.fillStyle = grad;
        ctx.fillRect(g.x - glowRadius, g.y - glowRadius, glowRadius * 2, glowRadius * 2);
      } else {
        this._explosionGlow = null;
      }
    }

    // Particles
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
