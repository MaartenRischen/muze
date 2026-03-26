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
    const eq = (a, b) => a === b || (a.length === b.length && a.every((v, i) => v === b[i]));
    if (eq(scale, C.SCALE_LYDIAN)) return 'lydian';
    if (eq(scale, C.SCALE_IONIAN)) return 'ionian';
    if (eq(scale, C.SCALE_MIXOLYDIAN)) return 'mixolydian';
    if (eq(scale, C.SCALE_DORIAN)) return 'dorian';
    if (eq(scale, C.SCALE_AEOLIAN)) return 'aeolian';
    if (eq(scale, C.SCALE_PHRYGIAN)) return 'phrygian';
    for (const [name, intervals] of Object.entries(this.EXTRA_SCALES)) {
      if (eq(scale, intervals)) return name;
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
  },

  // ============================================================
  // ARP CHORD TONES — play 1st, 3rd, 5th, 7th of current chord
  // instead of the full scale. Returns note names across octaves.
  // ============================================================
  getArpNotes(scale, root, degree, octaveRange) {
    const d = degree % scale.length;
    const chordTones = [
      scale[d],
      scale[(d + 2) % scale.length],
      scale[(d + 4) % scale.length],
      scale[(d + 6) % scale.length]
    ];
    const notes = [];
    for (let oct = 0; oct < octaveRange; oct++) {
      for (const interval of chordTones) {
        notes.push(this.midiToNote(root + oct * 12 + interval));
      }
    }
    return notes;
  },

  // ============================================================
  // EUCLIDEAN RHYTHM GENERATOR — Bjorklund's algorithm
  // Distributes `pulses` hits evenly across `steps` slots.
  // ============================================================
  euclidean(pulses, steps) {
    if (pulses >= steps) return Array(steps).fill(1);
    if (pulses <= 0) return Array(steps).fill(0);
    let counts = Array(pulses).fill(null).map(() => [1]);
    let remainders = Array(steps - pulses).fill(null).map(() => [0]);
    while (remainders.length > 1) {
      const newCounts = [];
      const newRemainders = [];
      const min = Math.min(counts.length, remainders.length);
      for (let i = 0; i < min; i++) {
        newCounts.push([...counts[i], ...remainders[i]]);
      }
      if (counts.length > min) newRemainders.push(...counts.slice(min));
      if (remainders.length > min) newRemainders.push(...remainders.slice(min));
      counts = newCounts;
      remainders = newRemainders;
    }
    return [...counts, ...remainders].flat();
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

// ============================================================
// EXTENDED PRESET PARAMETERS
// Config.js is frozen, so we layer extra per-preset parameters
// here. Keyed by preset name for forward-compatibility.
// New dimensions: arpRate, padChorusDepth, delayTime, reverbDecay
// ============================================================
MUZE.PresetExtensions = {
  'Default':       { arpRate: '8n',  padChorusDepth: 0.3, delayTime: '8n.',  reverbDecay: 2.5 },
  'Ambient Dream': { arpRate: '4n',  padChorusDepth: 0.7, delayTime: '4n.',  reverbDecay: 5.0 },
  'Dark Techno':   { arpRate: '16n', padChorusDepth: 0,   delayTime: '16n',  reverbDecay: 1.5 },
  'Lo-Fi Chill':   { arpRate: '8t',  padChorusDepth: 0.4, delayTime: '8n.',  reverbDecay: 3.0 },
  'Bright Pop':    { arpRate: '8n',  padChorusDepth: 0.3, delayTime: '8n.',  reverbDecay: 2.0 },
  'Deep Space':    { arpRate: '4n',  padChorusDepth: 0.6, delayTime: '4n.',  reverbDecay: 8.0 },
  'Minimal':       { arpRate: '16n', padChorusDepth: 0.1, delayTime: '16n',  reverbDecay: 2.0 },
  'Future Bass':   { arpRate: '8n',  padChorusDepth: 0.5, delayTime: '8n.',  reverbDecay: 1.8 },

  /**
   * Apply extended parameters for a given preset.
   * Call this after MUZE.Audio.applyPreset() to layer on the extra dimensions.
   */
  apply(presetName) {
    const ext = this[presetName];
    if (!ext) return;

    // Store in state so storage can persist them
    MUZE.State.arpRate = ext.arpRate;
    MUZE.State.padChorusDepth = ext.padChorusDepth;
    MUZE.State.delayTime = ext.delayTime;
    MUZE.State.reverbDecay = ext.reverbDecay;

    const FADE = 2; // match audio.js crossfade time

    // Arp rate: change the arp loop interval if the sequence exists
    if (MUZE.Audio._arpSeq) {
      MUZE.Audio._arpSeq.interval = ext.arpRate;
    }

    // Pad chorus depth: adjust chorus if available
    if (MUZE.Audio._chorusBus) {
      MUZE.Audio._chorusBus.depth = ext.padChorusDepth;
    } else if (MUZE.Audio._chorus) {
      MUZE.Audio._chorus.depth = ext.padChorusDepth;
    }

    // Delay time: adjust delay bus
    if (MUZE.Audio._delayBus) {
      try {
        MUZE.Audio._delayBus.delayTime.rampTo(ext.delayTime === '16n' ? 0.125 :
          ext.delayTime === '8n.' ? 0.375 : ext.delayTime === '4n.' ? 0.75 : 0.25, FADE);
      } catch(e) {
        // delayTime may accept notation directly
        try { MUZE.Audio._delayBus.delayTime.value = ext.delayTime; } catch(e2) {}
      }
    }

    // Reverb decay: update reverb bus
    if (MUZE.Audio._reverbBus) {
      try { MUZE.Audio._reverbBus.decay = ext.reverbDecay; } catch(e) {}
    }
  },

  /**
   * Restore extended parameters from saved state values.
   */
  restoreFromState() {
    const FADE = 1;
    if (MUZE.State.arpRate && MUZE.Audio._arpSeq) {
      MUZE.Audio._arpSeq.interval = MUZE.State.arpRate;
    }
    if (MUZE.State.padChorusDepth !== undefined) {
      if (MUZE.Audio._chorusBus) MUZE.Audio._chorusBus.depth = MUZE.State.padChorusDepth;
      else if (MUZE.Audio._chorus) MUZE.Audio._chorus.depth = MUZE.State.padChorusDepth;
    }
    if (MUZE.State.delayTime && MUZE.Audio._delayBus) {
      try {
        const dt = MUZE.State.delayTime;
        MUZE.Audio._delayBus.delayTime.rampTo(dt === '16n' ? 0.125 :
          dt === '8n.' ? 0.375 : dt === '4n.' ? 0.75 : 0.25, FADE);
      } catch(e) {
        try { MUZE.Audio._delayBus.delayTime.value = MUZE.State.delayTime; } catch(e2) {}
      }
    }
    if (MUZE.State.reverbDecay && MUZE.Audio._reverbBus) {
      try { MUZE.Audio._reverbBus.decay = MUZE.State.reverbDecay; } catch(e) {}
    }
  }
};

// ============================================================
// EUCLIDEAN RHYTHM PATTERNS
// Pre-computed patterns using Bjorklund's algorithm.
// Each is 32 steps (2 bars of 16th notes) to match RHYTHM_PATTERNS format.
// Injected into MUZE.Config.RHYTHM_PATTERNS at runtime (Config is frozen,
// so we push to the existing array if it's not frozen, otherwise we
// store them here for manual access).
// ============================================================
MUZE.EuclideanPatterns = (function() {
  const E = MUZE.Music.euclidean.bind(MUZE.Music);
  const patterns = [
    {
      name: 'Eucl 3/8',
      kick:  E(3, 16).concat(E(3, 16)),
      snare: E(2, 16).concat(E(2, 16)),
      hat:   E(5, 16).concat(E(5, 16))
    },
    {
      name: 'Eucl 5/16',
      kick:  E(5, 16).concat(E(5, 16)),
      snare: E(3, 16).concat(E(3, 16)),
      hat:   E(7, 16).concat(E(7, 16))
    },
    {
      name: 'Eucl 7/16',
      kick:  E(4, 16).concat(E(4, 16)),
      snare: E(2, 16).concat(E(2, 16)),
      hat:   E(9, 16).concat(E(9, 16))
    }
  ];

  // Attempt to append to RHYTHM_PATTERNS if the array is mutable
  try {
    for (const p of patterns) {
      // Check if pattern already added (idempotent)
      const exists = MUZE.Config.RHYTHM_PATTERNS.some(rp => rp.name === p.name);
      if (!exists) {
        MUZE.Config.RHYTHM_PATTERNS.push(p);
      }
    }
  } catch (e) {
    // Config is frozen — store patterns here for manual access
    console.info('Config is frozen; Euclidean patterns available via MUZE.EuclideanPatterns.list');
  }

  return { list: patterns };
})();
