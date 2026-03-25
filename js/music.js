/* ============================================================
   MUZE — Music Theory & Sample Library
   ============================================================ */

MUZE.Music = {
  NOTE_NAMES: ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'],

  selectScale(lipCorner) {
    const C = MUZE.Config;
    if (lipCorner > 0.80) return C.SCALE_LYDIAN;
    if (lipCorner > 0.60) return C.SCALE_IONIAN;
    if (lipCorner > 0.40) return C.SCALE_MIXOLYDIAN;
    if (lipCorner > 0.20) return C.SCALE_DORIAN;
    if (lipCorner > 0.00) return C.SCALE_AEOLIAN;
    return C.SCALE_PHRYGIAN;
  },

  quantize(value, scale, root, octaveRange) {
    const total = scale.length * octaveRange;
    const idx = Math.max(0, Math.min(total - 1, Math.round(value * (total - 1))));
    return root + Math.floor(idx / scale.length) * 12 + scale[idx % scale.length];
  },

  midiToNote(midi) {
    return this.NOTE_NAMES[midi % 12] + (Math.floor(midi / 12) - 1);
  },

  getPadVoicing(root, scale, degree) {
    const d = degree % scale.length;
    return [
      root + scale[d] - 12,
      root + scale[(d + 4) % scale.length],
      root + scale[(d + 2) % scale.length] + 12
    ].map(n => this.midiToNote(n));
  },

  getScaleName(scale) {
    const C = MUZE.Config;
    if (!scale) return '-';
    if (scale === C.SCALE_LYDIAN) return 'lydian';
    if (scale === C.SCALE_IONIAN) return 'ionian';
    if (scale === C.SCALE_MIXOLYDIAN) return 'mixolydian';
    if (scale === C.SCALE_DORIAN) return 'dorian';
    if (scale === C.SCALE_AEOLIAN) return 'aeolian';
    if (scale === C.SCALE_PHRYGIAN) return 'phrygian';
    return '?';
  }
};

// ---- Sample Library ----
MUZE.SampleLib = {
  _buffers: {},
  _custom: [],

  async loadAll() {
    const promises = MUZE.Config.SAMPLES.map(async (s) => {
      try {
        const buf = new Tone.ToneAudioBuffer();
        await buf.load(s.url);
        this._buffers[s.id] = buf;
      } catch (e) {
        console.warn('Failed to load sample:', s.id, e);
      }
    });
    await Promise.all(promises);
  },

  get(id) { return this._buffers[id] || null; },

  addCustom(name, buffer) {
    const id = 'custom-' + Date.now();
    this._buffers[id] = buffer;
    this._custom.push({ id, name });
    return id;
  },

  getAllSamples() {
    return [...MUZE.Config.SAMPLES, ...this._custom];
  }
};
