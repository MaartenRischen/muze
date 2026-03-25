/* ============================================================
   MUZE — Audio-Reactive Visualizer
   ============================================================ */

MUZE.Visualizer = {
  _canvas: null,
  _ctx: null,
  _width: 0,
  _height: 0,
  _particles: [],
  _maxParticles: 40, // PERF: reduced from 80
  // PERF: Cache CSS variables (only update on mode change)
  _cachedAccent: '#e8a948',
  _cachedAccentRgb: '232,169,72',
  _cachedModeName: '',
  // Beat detection state
  _lastBass: 0,
  _beatPulse: 0,

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
  },

  draw() {
    const ctx = this._ctx;
    const w = this._width;
    const h = this._height;
    ctx.clearRect(0, 0, w, h);

    const waveform = MUZE.Audio.getWaveform();
    if (!waveform) return;

    // Calculate audio energy
    let energy = 0;
    for (let i = 0; i < waveform.length; i++) {
      energy += Math.abs(waveform[i]);
    }
    energy = energy / waveform.length;

    // PERF: Use cached accent color (updated only on mode change, avoids getComputedStyle per frame)
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
        const db = fft[i]; // dB value, typically -100 to 0
        const linear = Math.pow(10, db / 20); // convert to linear
        if (i < binCount * 0.1) bass += linear;      // 0-10% = bass
        else if (i < binCount * 0.4) mid += linear;  // 10-40% = mid
        else high += linear;                          // 40-100% = high
      }
      bass /= binCount * 0.1;
      mid /= binCount * 0.3;
      high /= binCount * 0.6;
    }

    // ---- Beat detection (threshold on bass energy) ----
    if (fft && bass > this._lastBass * 1.5 && bass > 0.15) {
      this._beatPulse = 1.0; // trigger beat pulse
    }
    this._lastBass = bass;
    this._beatPulse *= 0.92; // decay

    // ---- Circular waveform ring ----
    const cx = w / 2;
    const cy = h * 0.38;
    const baseRadius = Math.min(w, h) * 0.18;
    const beatExpand = this._beatPulse * 30;
    const radius = baseRadius + energy * 80 + beatExpand;

    // Outer glow ring (drawn first, behind the waveform)
    if (energy > 0.015) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${accentRgb}, ${energy * 0.08})`;
      ctx.lineWidth = 12;
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.stroke();

      ctx.beginPath();
      ctx.strokeStyle = `rgba(${accentRgb}, ${energy * 0.12})`;
      ctx.lineWidth = 4;
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.stroke();
    }

    // Waveform ring — thin and precise
    ctx.beginPath();
    ctx.strokeStyle = `rgba(${accentRgb}, ${0.18 + energy * 0.5})`;
    ctx.lineWidth = 1;

    for (let i = 0; i < waveform.length; i++) {
      const angle = (i / waveform.length) * Math.PI * 2 - Math.PI / 2;
      const amp = waveform[i] * 40;
      const r = radius + amp;
      const x = cx + Math.cos(angle) * r;
      const y = cy + Math.sin(angle) * r;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.stroke();

    // ---- Floating particles (use mid energy from FFT for spawn rate when available) ----
    const particleEnergy = fft ? Math.max(energy, mid * 2) : energy;
    this._updateParticles(particleEnergy, accentRgb, cx, cy, radius);
    this._drawParticles(ctx, accentRgb, high);

    // ---- Bottom frequency bars (use real FFT data when available) ----
    this._drawFreqBars(ctx, fft || waveform, w, h, accentRgb, energy, !!fft);
  },

  _updateParticles(energy, accentRgb, cx, cy, radius) {
    // Spawn particles based on energy — more numerous, smaller
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

    // Update existing
    for (let i = this._particles.length - 1; i >= 0; i--) {
      const p = this._particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy -= 0.01; // gentle upward drift
      p.life -= p.decay;
      if (p.life <= 0) {
        // PERF: swap-and-pop O(1) removal instead of splice O(n)
        this._particles[i] = this._particles[this._particles.length - 1];
        this._particles.pop();
      }
    }
  },

  _drawParticles(ctx, accentRgb, highEnergy) {
    const sparkle = highEnergy || 0;
    for (const p of this._particles) {
      // Quadratic falloff for softer fade; sparkle from high-freq FFT adds brightness
      const alpha = Math.min(1, p.life * p.life * 0.4 + sparkle * 0.3);
      ctx.beginPath();
      ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
  },

  _drawFreqBars(ctx, data, w, h, accentRgb, energy, isFFT) {
    if (energy < 0.01) return;
    // Use turquoise meter color (matching mixer meters) instead of accent
    const meterRgb = '13, 148, 136';
    const meterBrightRgb = '45, 212, 191';
    const barCount = 32;
    const barWidth = w / barCount;
    const step = Math.floor(data.length / barCount);

    for (let i = 0; i < barCount; i++) {
      let val;
      if (isFFT) {
        // FFT data: dB values (-100 to 0). Normalize to 0-60 visual range.
        const db = data[i * step];
        // Map -100..0 dB to 0..1 linear, then scale to visual height
        val = Math.max(0, (db + 100) / 100) * 60;
      } else {
        // Waveform fallback: time-domain amplitude
        val = Math.abs(data[i * step]) * 60;
      }
      const barHeight = Math.max(1, val);
      const alpha = 0.05 + (val / 60) * 0.10;
      // Blend from turquoise to bright turquoise based on intensity
      const rgb = val > 30 ? meterBrightRgb : meterRgb;
      ctx.fillStyle = `rgba(${rgb}, ${alpha})`;
      ctx.fillRect(
        i * barWidth + 1,
        h - barHeight - 53,
        barWidth - 2,
        barHeight
      );
    }
  }
};
