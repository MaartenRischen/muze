/* ============================================================
   MUZE — Audio-Reactive Visualizer
   ============================================================ */

MUZE.Visualizer = {
  _canvas: null,
  _ctx: null,
  _width: 0,
  _height: 0,
  _particles: [],
  _maxParticles: 40,

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

    // Get current accent color
    const style = getComputedStyle(document.documentElement);
    const accent = style.getPropertyValue('--muze-accent').trim() || '#e8a948';
    const accentRgb = style.getPropertyValue('--muze-accent-rgb').trim() || '232,169,72';

    // ---- Circular waveform ring ----
    const cx = w / 2;
    const cy = h * 0.38;
    const baseRadius = Math.min(w, h) * 0.18;
    const radius = baseRadius + energy * 80;

    ctx.beginPath();
    ctx.strokeStyle = `rgba(${accentRgb}, ${0.15 + energy * 0.4})`;
    ctx.lineWidth = 1.5;

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

    // Glow ring
    if (energy > 0.02) {
      ctx.beginPath();
      ctx.strokeStyle = `rgba(${accentRgb}, ${energy * 0.15})`;
      ctx.lineWidth = 8;
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.stroke();
    }

    // ---- Floating particles ----
    this._updateParticles(energy, accentRgb, cx, cy, radius);
    this._drawParticles(ctx, accentRgb);

    // ---- Bottom frequency bars (subtle) ----
    this._drawFreqBars(ctx, waveform, w, h, accentRgb, energy);
  },

  _updateParticles(energy, accentRgb, cx, cy, radius) {
    // Spawn particles based on energy
    if (energy > 0.03 && this._particles.length < this._maxParticles && Math.random() < energy * 3) {
      const angle = Math.random() * Math.PI * 2;
      this._particles.push({
        x: cx + Math.cos(angle) * radius,
        y: cy + Math.sin(angle) * radius,
        vx: (Math.random() - 0.5) * 1.5,
        vy: -Math.random() * 2 - 0.5,
        life: 1,
        decay: 0.008 + Math.random() * 0.012,
        size: 1 + Math.random() * 2
      });
    }

    // Update existing
    for (let i = this._particles.length - 1; i >= 0; i--) {
      const p = this._particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy -= 0.01; // gentle upward drift
      p.life -= p.decay;
      if (p.life <= 0) this._particles.splice(i, 1);
    }
  },

  _drawParticles(ctx, accentRgb) {
    for (const p of this._particles) {
      ctx.beginPath();
      ctx.fillStyle = `rgba(${accentRgb}, ${p.life * 0.5})`;
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
  },

  _drawFreqBars(ctx, waveform, w, h, accentRgb, energy) {
    if (energy < 0.01) return;
    const barCount = 32;
    const barWidth = w / barCount;
    const step = Math.floor(waveform.length / barCount);

    for (let i = 0; i < barCount; i++) {
      const val = Math.abs(waveform[i * step]) * 60;
      const barHeight = Math.max(1, val);
      const alpha = 0.04 + (val / 60) * 0.08;
      ctx.fillStyle = `rgba(${accentRgb}, ${alpha})`;
      ctx.fillRect(
        i * barWidth + 1,
        h - barHeight - 53,
        barWidth - 2,
        barHeight
      );
    }
  }
};
