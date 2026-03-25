/* ============================================================
   MUZE — Mood Lighting System v2
   Premium ambient atmosphere: Philips Ambilight-style edge glow,
   mode-reactive gradient overlays, organic energy breathing,
   and beat-synced accent pulsing.

   Architecture:
   - 4 DOM layers between bg-canvas and overlay canvas:
     1. mood-gradient-overlay  — full-screen mode-colored wash
     2. mood-edge-glow         — Ambilight edge diffusion (bottom + sides)
     3. mood-edge-glow-inner   — brighter inner edge layer (depth illusion)
     4. mood-breath-bar        — bottom energy bar with subtle scale
   - All animation driven by 4 CSS custom properties:
     --mood-rgb    (R,G,B)  mode accent color
     --mood-breath (0-1)    organic sine oscillator
     --mood-energy (0-1)    smoothed audio energy
     --mood-beat   (0-1)    spike on bass transients, fast decay
   - update() called once per frame from main loop — no extra rAF
   - Zero DOM layout / reflow — only CSS custom property writes
   ============================================================ */

MUZE.MoodLight = {
  _root: null,
  _gradientEl: null,
  _edgeEl: null,
  _edgeInnerEl: null,
  _breathBarEl: null,
  _prevModeName: '',
  _breathPhase: 0,
  _smoothEnergy: 0,
  _beatDecay: 0,
  _prevBassEnergy: 0,
  _bassSmooth: 0,

  // Crossfade state
  _crossfading: false,
  _crossfadeStart: 0,
  _crossfadeDuration: 1500,  // ms
  _oldRgb: null,
  _newRgb: null,

  // Mode warmth classification for gradient style
  _modeWarmth: {
    lydian:           'warm',
    ionian:           'warm',
    mixolydian:       'warm',
    dorian:           'neutral',
    aeolian:          'cool',
    phrygian:         'cool',
    'pent. major':    'warm',
    'pent. minor':    'cool',
    'harm. minor':    'cool',
    'whole tone':     'neutral',
    'blues':          'neutral',
    'melodic minor':  'neutral',
    'phrygian dom':   'cool',
    'hirajoshi':      'cool',
  },

  init() {
    this._root = document.documentElement;
    this._gradientEl = document.getElementById('mood-gradient-overlay');
    this._edgeEl = document.getElementById('mood-edge-glow');
    this._edgeInnerEl = document.getElementById('mood-edge-glow-inner');
    this._breathBarEl = document.getElementById('mood-breath-bar');

    // Create inner edge glow element if it doesn't exist
    if (!this._edgeInnerEl) {
      this._edgeInnerEl = document.createElement('div');
      this._edgeInnerEl.id = 'mood-edge-glow-inner';
      // Insert after edge glow
      if (this._edgeEl && this._edgeEl.parentNode) {
        this._edgeEl.parentNode.insertBefore(
          this._edgeInnerEl,
          this._edgeEl.nextSibling
        );
      }
    }

    // Initialize CSS custom properties
    this._root.style.setProperty('--mood-breath', '0.3');
    this._root.style.setProperty('--mood-energy', '0');
    this._root.style.setProperty('--mood-beat', '0');
  },

  /**
   * Called every frame from MUZE.Loop._tick().
   * Only touches CSS custom properties — no DOM layout, no reflow.
   */
  update() {
    const now = performance.now();

    // ================================================================
    // 1. MODE COLOR SYNC + CROSSFADE TRANSITION
    // ================================================================
    const modeName = MUZE.State.currentModeName;
    if (modeName !== this._prevModeName) {
      const colors = MUZE.Config.MODE_COLORS[modeName];
      if (colors) {
        // Start crossfade: capture old color, set new target
        const oldColors = MUZE.Config.MODE_COLORS[this._prevModeName];
        if (oldColors && this._prevModeName !== '') {
          this._oldRgb = oldColors.rgb.split(',').map(Number);
          this._newRgb = colors.rgb.split(',').map(Number);
          this._crossfading = true;
          this._crossfadeStart = now;
        } else {
          // First mode set — no crossfade, just apply
          this._root.style.setProperty('--mood-rgb', colors.rgb);
        }
      }

      // Update gradient warmth class
      if (this._gradientEl) {
        const warmth = this._modeWarmth[modeName] || 'neutral';
        this._gradientEl.classList.remove('warm', 'cool', 'neutral');
        this._gradientEl.classList.add(warmth);
      }

      this._prevModeName = modeName;
    }

    // Process crossfade interpolation
    if (this._crossfading && this._oldRgb && this._newRgb) {
      const elapsed = now - this._crossfadeStart;
      const t = Math.min(1, elapsed / this._crossfadeDuration);
      // Smooth ease-in-out curve
      const ease = t < 0.5
        ? 2 * t * t
        : 1 - Math.pow(-2 * t + 2, 2) / 2;

      const r = Math.round(this._oldRgb[0] + (this._newRgb[0] - this._oldRgb[0]) * ease);
      const g = Math.round(this._oldRgb[1] + (this._newRgb[1] - this._oldRgb[1]) * ease);
      const b = Math.round(this._oldRgb[2] + (this._newRgb[2] - this._oldRgb[2]) * ease);
      this._root.style.setProperty('--mood-rgb', `${r},${g},${b}`);

      if (t >= 1) {
        this._crossfading = false;
        this._oldRgb = null;
        this._newRgb = null;
      }
    }

    // ================================================================
    // 2. AUDIO ENERGY ANALYSIS
    // ================================================================
    let rawEnergy = 0;
    let bassEnergy = 0;

    // Waveform-based overall energy
    const waveform = MUZE.Audio.getWaveform ? MUZE.Audio.getWaveform() : null;
    if (waveform) {
      let sum = 0;
      for (let i = 0; i < waveform.length; i++) {
        sum += Math.abs(waveform[i]);
      }
      rawEnergy = sum / waveform.length;
    }

    // FFT-based bass energy (bins 1-6 ≈ 0-250Hz for kick detection)
    const fft = MUZE.Audio.getFFT ? MUZE.Audio.getFFT() : null;
    if (fft) {
      // FFT values are in dB (negative). Convert to linear 0-1.
      let bassSum = 0;
      const bassEnd = Math.min(8, fft.length);
      for (let i = 1; i < bassEnd; i++) {
        // dB to linear: typical range -100 to 0 dB
        const db = fft[i];
        const lin = Math.pow(10, db / 20);
        bassSum += lin;
      }
      bassEnergy = bassSum / (bassEnd - 1);
    }

    // Smooth overall energy (heavy smoothing for organic feel)
    this._smoothEnergy = 0.06 * rawEnergy + 0.94 * this._smoothEnergy;
    const energy = Math.min(1, this._smoothEnergy * 6);

    // ================================================================
    // 3. BEAT DETECTION (bass transient spike)
    // ================================================================
    // Smooth bass for comparison baseline
    this._bassSmooth = 0.15 * bassEnergy + 0.85 * this._bassSmooth;

    // Detect beat: current bass significantly above smoothed baseline
    const bassSpike = bassEnergy - this._bassSmooth;
    const beatThreshold = 0.015;
    if (bassSpike > beatThreshold && this._beatDecay < 0.1) {
      // Beat hit! Spike to 1.0
      this._beatDecay = 1.0;
    }

    // Decay the beat value: fast attack already done, now exponential decay
    // 80ms to peak, then 200ms settle → decay factor ~0.92 at 60fps
    if (this._beatDecay > 0.001) {
      this._beatDecay *= 0.92;
    } else {
      this._beatDecay = 0;
    }

    this._prevBassEnergy = bassEnergy;

    // ================================================================
    // 4. BREATHING OSCILLATOR
    // ================================================================
    // Sine wave at ~0.25Hz (4 second period)
    // At 60fps: 2π / (60 * 4) ≈ 0.02618
    this._breathPhase += 0.02618;
    if (this._breathPhase > Math.PI * 2) this._breathPhase -= Math.PI * 2;

    // Base sine: oscillates 0 to 1
    const sinRaw = (Math.sin(this._breathPhase) + 1) * 0.5;

    // Amplitude modulation by audio energy:
    // Quiet → gentle 30% swing around 0.35 base
    // Loud  → full 100% swing around 0.5 base
    const ampMin = 0.30;
    const ampMax = 1.0;
    const amplitude = ampMin + (ampMax - ampMin) * energy;
    const breathBase = 0.2 + energy * 0.3; // base level rises with energy
    const breath = Math.min(1, breathBase + sinRaw * amplitude * 0.5);

    // ================================================================
    // 5. UPDATE CSS CUSTOM PROPERTIES (single batch, GPU-composited)
    // ================================================================
    this._root.style.setProperty('--mood-breath', breath.toFixed(3));
    this._root.style.setProperty('--mood-energy', energy.toFixed(3));
    this._root.style.setProperty('--mood-beat', this._beatDecay.toFixed(3));
  }
};
