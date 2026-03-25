/* ============================================================
   MUZE — Music Theory & Sample Library
   ============================================================ */

MUZE.Music = {
  NOTE_NAMES: ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'],

  // Extra scales map (name -> intervals)
  EXTRA_SCALES: {
    'pent. major':  [0,2,4,7,9],
    'pent. minor':  [0,3,5,7,10],
    'harm. minor':  [0,2,3,5,7,8,11],
    'whole tone':   [0,2,4,6,8,10],
    'blues':        [0,3,5,6,7,10],
    'melodic minor': [0,2,3,5,7,9,11],
    'phrygian dom':  [0,1,4,5,7,8,10],
    'hirajoshi':     [0,2,3,7,8],
  },

  selectScale(lipCorner) {
    const C = MUZE.Config;
    // If an extra scale mode is selected, always return that
    if (MUZE.State.extraScaleMode) {
      return this.EXTRA_SCALES[MUZE.State.extraScaleMode] || C.SCALE_DORIAN;
    }
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
    const root_note = root + scale[d];
    const third = root + scale[(d + 2) % scale.length];
    const fifth = root + scale[(d + 4) % scale.length];
    const seventh = root + scale[(d + 6) % scale.length];

    // Open voicing: root down octave, third, fifth, seventh up
    return [
      root_note - 12,
      third,
      fifth,
      seventh
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
    // Check extra scales by comparing interval arrays
    for (const [name, intervals] of Object.entries(this.EXTRA_SCALES)) {
      if (scale.length === intervals.length && scale.every((v, i) => v === intervals[i])) {
        return name;
      }
    }
    return '?';
  },

  snapToScale(midiNote, scale, root) {
    let bestNote = root;
    let bestDist = 999;
    for (let oct = -1; oct <= 8; oct++) {
      for (const interval of scale) {
        const candidate = root + oct * 12 + interval;
        const dist = Math.abs(candidate - midiNote);
        if (dist < bestDist) { bestDist = dist; bestNote = candidate; }
      }
    }
    return bestNote;
  },

  // Get the effective root note (C4 base + offset)
  getEffectiveRoot() {
    return 60 + MUZE.State.rootOffset;
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
