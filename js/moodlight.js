/* ============================================================
   MUZE — Mood Lighting System
   Ambient atmosphere: edge glow, mode-reactive gradient,
   energy breathing. Pure CSS custom property updates — near
   zero performance cost (no canvas, no repaints).

   Architecture:
   - 3 DOM elements (mood-gradient-overlay, mood-edge-glow,
     mood-breath-bar) sit between bg-canvas and overlay canvas
   - All animation driven by CSS custom properties:
     --mood-rgb (color), --mood-breath (0-1 oscillation)
   - update() called from main loop — no extra rAF chain
   ============================================================ */

MUZE.MoodLight = {
  _root: null,
  _gradientEl: null,
  _prevModeName: '',
  _breathPhase: 0,
  _smoothEnergy: 0,

  // Mode warmth classification for gradient style
  // warm = center-out radial (Lydian amber glow from center)
  // cool = corner-in (Phrygian indigo from corners)
  // neutral = balanced spread
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
  },

  /**
   * Called every frame from MUZE.Loop._tick().
   * Only touches CSS custom properties — no DOM layout, no reflow.
   */
  update() {
    // 1. Mode color sync — piggyback on existing mode detection
    const modeName = MUZE.State.currentModeName;
    if (modeName !== this._prevModeName) {
      this._prevModeName = modeName;
      const colors = MUZE.Config.MODE_COLORS[modeName];
      if (colors) {
        this._root.style.setProperty('--mood-rgb', colors.rgb);
      }
      // Update gradient warmth class (1.5s CSS transition handles smoothness)
      if (this._gradientEl) {
        const warmth = this._modeWarmth[modeName] || 'neutral';
        this._gradientEl.classList.remove('warm', 'cool', 'neutral');
        this._gradientEl.classList.add(warmth);
      }
    }

    // 2. Breathing oscillator — slow sine wave (~4s period)
    //    Modulated by audio energy for organic, living feel
    this._breathPhase += 0.025; // ~4.2s full cycle at 60fps
    if (this._breathPhase > Math.PI * 2) this._breathPhase -= Math.PI * 2;

    // Base sine breath: 0 to 1
    const sinBreath = (Math.sin(this._breathPhase) + 1) * 0.5;

    // Get audio energy (smooth heavily for organic breathing, not flashing)
    let energy = 0;
    const waveform = MUZE.Audio.getWaveform ? MUZE.Audio.getWaveform() : null;
    if (waveform) {
      let rawEnergy = 0;
      for (let i = 0; i < waveform.length; i++) {
        rawEnergy += Math.abs(waveform[i]);
      }
      rawEnergy = rawEnergy / waveform.length;
      // Heavy smoothing (alpha = 0.05) — no flashing, just organic swell
      this._smoothEnergy = 0.05 * rawEnergy + 0.95 * this._smoothEnergy;
      energy = this._smoothEnergy;
    }

    // Combine breath + energy:
    // Quiet: gentle breathing at ~30% amplitude
    // Loud: breathing intensifies up to 100%
    const energyScale = Math.min(1, 0.3 + energy * 8);
    const breath = sinBreath * energyScale;

    // 3. Update CSS custom properties (single batch, GPU-composited)
    this._root.style.setProperty('--mood-breath', breath.toFixed(3));
  }
};
