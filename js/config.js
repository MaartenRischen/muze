/* ============================================================
   MUZE — Config, State, Smoothing
   ============================================================ */

window.MUZE = {};

const SAMPLE_BASE = 'https://ffwbirepsanifejscguz.supabase.co/storage/v1/object/public/Samples/';

MUZE.Config = Object.freeze({
  CAM_WIDTH: 640, CAM_HEIGHT: 480,
  SMOOTH_FAST: 0.35, SMOOTH_SLOW: 0.15, SMOOTH_HAND: 0.30,

  MOUTH_OPEN_MIN: 0.015, MOUTH_OPEN_MAX: 0.09,
  LIP_SMILE_MIN: -0.025, LIP_SMILE_MAX: 0.025,
  BROW_MIN: 0.100, BROW_MAX: 0.143,
  EYE_OPEN_MIN: 0.012, EYE_OPEN_MAX: 0.055,
  MOUTH_WIDTH_MIN: 0.28, MOUTH_WIDTH_MAX: 0.38,

  FILTER_FREQ_MIN: 800, FILTER_FREQ_MAX: 10000,
  REVERB_WET_MIN: 0.0, REVERB_WET_MAX: 0.75, REVERB_DECAY: 2.5,
  DELAY_WET_MIN: 0.0, DELAY_WET_MAX: 0.4,
  CHORUS_DEPTH_MIN: 0.0, CHORUS_DEPTH_MAX: 0.7,

  // Core modal scales (face-controlled via valence)
  SCALE_LYDIAN: [0,2,4,6,7,9,11],
  SCALE_IONIAN: [0,2,4,5,7,9,11],
  SCALE_MIXOLYDIAN: [0,2,4,5,7,9,10],
  SCALE_DORIAN: [0,2,3,5,7,9,10],
  SCALE_AEOLIAN: [0,2,3,5,7,8,10],
  SCALE_PHRYGIAN: [0,1,3,5,7,8,10],

  // Extended scales (selectable via UI)
  SCALE_PENTATONIC_MAJOR: [0,2,4,7,9],
  SCALE_PENTATONIC_MINOR: [0,3,5,7,10],
  SCALE_HARMONIC_MINOR: [0,2,3,5,7,8,11],
  SCALE_WHOLE_TONE: [0,2,4,6,8,10],
  SCALE_BLUES: [0,3,5,6,7,10],

  ROOT_NOTE: 60, OCTAVE_RANGE: 2, BPM_DEFAULT: 85,
  BPM_MIN: 40, BPM_MAX: 200,
  CHORD_DEGREES: [0, 1, 2, 3, 4, 5],
  BROW_SPIKE_THRESHOLD: 0.25, BROW_SPIKE_COOLDOWN: 600,
  DETECT_INTERVAL: 33,
  SWIPE_THRESHOLD: 50, SWIPE_MAX_TIME: 300, DOUBLE_TAP_TIME: 300, HOLD_TIME: 400,

  RHYTHM_PATTERNS: [
    { name: 'Basic', kick:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
    { name: 'Funk', kick:[1,0,0,0,0,0,1,0,1,0,0,0,0,0,1,0], snare:[0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,0], hat:[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1] },
    { name: 'Broken', kick:[1,0,0,1,0,0,1,0,1,0,0,1,0,0,1,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1], hat:[1,0,1,0,1,0,1,0,1,0,1,1,1,0,1,0] },
    { name: 'Minimal', kick:[1,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0] },
    { name: 'Trap', kick:[1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[1,0,1,1,1,0,1,1,1,0,1,1,1,0,1,1] },
    { name: 'Halftime', kick:[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], snare:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
  ],

  // Arpeggio pattern types
  ARP_PATTERNS: ['up-down', 'up', 'down', 'random', 'up-up-down', 'played'],

  // Mode -> color mapping
  MODE_COLORS: {
    phrygian:         { accent: '#a78bfa', rgb: '167,139,250' },
    aeolian:          { accent: '#818cf8', rgb: '129,140,248' },
    dorian:           { accent: '#22d3ee', rgb: '34,211,238' },
    mixolydian:       { accent: '#34d399', rgb: '52,211,153' },
    ionian:           { accent: '#fbbf24', rgb: '251,191,36' },
    lydian:           { accent: '#fb923c', rgb: '251,146,60' },
    'pent. major':    { accent: '#f9a8d4', rgb: '249,168,212' },
    'pent. minor':    { accent: '#c084fc', rgb: '192,132,252' },
    'harm. minor':    { accent: '#f472b6', rgb: '244,114,182' },
    'whole tone':     { accent: '#a3e635', rgb: '163,230,53' },
    'blues':          { accent: '#38bdf8', rgb: '56,189,248' },
    'melodic minor':  { accent: '#a78bfa', rgb: '167,139,250' },
    'phrygian dom':   { accent: '#f97316', rgb: '249,115,22' },
    'hirajoshi':      { accent: '#ec4899', rgb: '236,72,153' },
  },

  // Root note names for selector
  ROOT_NAMES: ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'],

  // Presets — each configures the entire instrument
  PRESETS: [
    {
      name: 'Default',
      bpm: 85,
      rootOffset: 0, // semitones from C4
      padVolume: -14, arpVolume: -8, melodyVolume: -6,
      kickVolume: -6, snareVolume: -10, hatVolume: -16,
      padOsc: 'sine', padHarm: 2, padMod: 1.2, padAttack: 1.0, padRelease: 2.5,
      arpOsc: 'sawtooth', arpAttack: 0.01, arpDecay: 0.3, arpSustain: 0.6, arpRelease: 0.8,
      melOsc: 'triangle', melAttack: 0.05, melDecay: 0.2, melSustain: 0.7, melRelease: 0.4,
      arpPattern: 'up-down', rhythmPattern: 0, swing: 0,
      reverbDecay: 2.5, delayFeedback: 0.3,
      padReverb: 0.35, padDelay: 0.25, arpReverb: 0.35, arpDelay: 0.25,
    },
    {
      name: 'Ambient Dream',
      bpm: 65,
      rootOffset: 0,
      padVolume: -10, arpVolume: -12, melodyVolume: -8,
      kickVolume: -60, snareVolume: -60, hatVolume: -60,
      padOsc: 'sine', padHarm: 3, padMod: 0.8, padAttack: 2.5, padRelease: 5.0,
      arpOsc: 'sine', arpAttack: 0.3, arpDecay: 1.0, arpSustain: 0.3, arpRelease: 2.0,
      melOsc: 'triangle', melAttack: 0.4, melDecay: 0.5, melSustain: 0.8, melRelease: 1.5,
      arpPattern: 'random', rhythmPattern: 3, swing: 0,
      reverbDecay: 5.0, delayFeedback: 0.45,
      padReverb: 0.7, padDelay: 0.5, arpReverb: 0.6, arpDelay: 0.4,
    },
    {
      name: 'Dark Techno',
      bpm: 128,
      rootOffset: 0,
      padVolume: -18, arpVolume: -6, melodyVolume: -10,
      kickVolume: -3, snareVolume: -8, hatVolume: -14,
      padOsc: 'sawtooth', padHarm: 1, padMod: 4.0, padAttack: 0.3, padRelease: 1.0,
      arpOsc: 'square', arpAttack: 0.001, arpDecay: 0.1, arpSustain: 0.2, arpRelease: 0.15,
      melOsc: 'sawtooth', melAttack: 0.01, melDecay: 0.1, melSustain: 0.4, melRelease: 0.2,
      arpPattern: 'up', rhythmPattern: 1, swing: 0,
      reverbDecay: 1.5, delayFeedback: 0.4,
      padReverb: 0.1, padDelay: 0.15, arpReverb: 0.2, arpDelay: 0.3,
    },
    {
      name: 'Lo-Fi Chill',
      bpm: 72,
      rootOffset: 5, // F
      padVolume: -12, arpVolume: -10, melodyVolume: -8,
      kickVolume: -6, snareVolume: -10, hatVolume: -18,
      padOsc: 'triangle', padHarm: 2, padMod: 0.5, padAttack: 1.5, padRelease: 3.0,
      arpOsc: 'triangle', arpAttack: 0.05, arpDecay: 0.5, arpSustain: 0.4, arpRelease: 1.0,
      melOsc: 'sine', melAttack: 0.1, melDecay: 0.3, melSustain: 0.6, melRelease: 0.8,
      arpPattern: 'up-down', rhythmPattern: 5, swing: 40,
      reverbDecay: 3.0, delayFeedback: 0.35,
      padReverb: 0.4, padDelay: 0.3, arpReverb: 0.3, arpDelay: 0.2,
    },
    {
      name: 'Bright Pop',
      bpm: 110,
      rootOffset: 7, // G
      padVolume: -14, arpVolume: -8, melodyVolume: -6,
      kickVolume: -4, snareVolume: -8, hatVolume: -14,
      padOsc: 'sine', padHarm: 2, padMod: 1.5, padAttack: 0.5, padRelease: 1.5,
      arpOsc: 'sawtooth', arpAttack: 0.01, arpDecay: 0.2, arpSustain: 0.7, arpRelease: 0.5,
      melOsc: 'sawtooth', melAttack: 0.02, melDecay: 0.15, melSustain: 0.6, melRelease: 0.3,
      arpPattern: 'up-up-down', rhythmPattern: 0, swing: 10,
      reverbDecay: 2.0, delayFeedback: 0.25,
      padReverb: 0.25, padDelay: 0.15, arpReverb: 0.3, arpDelay: 0.2,
    },
    {
      name: 'Deep Space',
      bpm: 55,
      rootOffset: 3, // D#
      padVolume: -8, arpVolume: -14, melodyVolume: -10,
      kickVolume: -60, snareVolume: -60, hatVolume: -60,
      padOsc: 'sine', padHarm: 5, padMod: 2.5, padAttack: 3.0, padRelease: 6.0,
      arpOsc: 'sine', arpAttack: 0.5, arpDecay: 1.5, arpSustain: 0.2, arpRelease: 3.0,
      melOsc: 'triangle', melAttack: 0.8, melDecay: 0.5, melSustain: 0.5, melRelease: 2.0,
      arpPattern: 'random', rhythmPattern: 3, swing: 0,
      reverbDecay: 8.0, delayFeedback: 0.55,
      padReverb: 0.8, padDelay: 0.6, arpReverb: 0.7, arpDelay: 0.5,
    },
    {
      name: 'Minimal',
      bpm: 120,
      rootOffset: 2, // D
      padVolume: -20, arpVolume: -10, melodyVolume: -60,
      kickVolume: -4, snareVolume: -12, hatVolume: -16,
      padOsc: 'sine', padHarm: 1, padMod: 0.3, padAttack: 0.8, padRelease: 2.0,
      arpOsc: 'sine', arpAttack: 0.005, arpDecay: 0.15, arpSustain: 0.1, arpRelease: 0.3,
      melOsc: 'sine', melAttack: 0.01, melDecay: 0.1, melSustain: 0.5, melRelease: 0.2,
      arpPattern: 'up', rhythmPattern: 3, swing: 0,
      reverbDecay: 2.0, delayFeedback: 0.3,
      padReverb: 0.2, padDelay: 0.1, arpReverb: 0.15, arpDelay: 0.35,
    },
    {
      name: 'Future Bass',
      bpm: 140,
      rootOffset: 10, // A#
      padVolume: -10, arpVolume: -6, melodyVolume: -6,
      kickVolume: -4, snareVolume: -6, hatVolume: -14,
      padOsc: 'sawtooth', padHarm: 2, padMod: 3.0, padAttack: 0.1, padRelease: 1.0,
      arpOsc: 'square', arpAttack: 0.005, arpDecay: 0.15, arpSustain: 0.5, arpRelease: 0.3,
      melOsc: 'square', melAttack: 0.01, melDecay: 0.1, melSustain: 0.5, melRelease: 0.25,
      arpPattern: 'up-up-down', rhythmPattern: 4, swing: 15,
      reverbDecay: 1.8, delayFeedback: 0.3,
      padReverb: 0.3, padDelay: 0.2, arpReverb: 0.25, arpDelay: 0.25,
    },
  ],

  SAMPLES: [
    { id: 'singing-bowl', name: 'singing bowl', url: SAMPLE_BASE + '240934__the_very_real_horst__neptun-solo-07-tibetan-singing-bowl.wav' },
    { id: 'water-drop', name: 'water drop', url: SAMPLE_BASE + '273868__beskhu__water-drop-3.aiff' },
    { id: 'bottle-blow', name: 'bottle blow', url: SAMPLE_BASE + '352796__cabled_mess__bottle-blown-08.wav' },
    { id: 'wind-chime', name: 'wind chime', url: SAMPLE_BASE + '398492__anthousai__wind-chimes-single-03.wav' },
    { id: 'keys-jingle', name: 'keys jingle', url: SAMPLE_BASE + '565909__fenodyrie__keys-jingling.wav' },
    { id: 'wood-knock', name: 'wood knock', url: SAMPLE_BASE + '573835__trp__door-knocks-wood-close-77mel-191026.wav' },
    { id: 'humming', name: 'humming', url: SAMPLE_BASE + '646179__mayatakeda__woman-humming-softly-mp3.mp3' },
    { id: 'finger-snap', name: 'finger snap', url: SAMPLE_BASE + '824674__bassimat__finger-snaps-001.wav' },
  ],
});

// ---- Mutable State ----
MUZE.State = {
  mouthOpenness: 0, lipCorner: 0, browHeight: 0, eyeOpenness: 0.5,
  mouthWidth: 0, headPitch: 0, headYaw: 0, headRoll: 0, faceDetected: false,
  handPresent: false, handY: 0.5, handX: 0.5, handOpen: true,
  currentScale: [0,2,3,5,7,9,10], melodyNote: null, chordIndex: 0,
  autoRhythm: false, riserActive: false, modeFrozen: false, portamentoMode: false,
  audioReady: false, _browRaw: 0,
  debugVisible: false,
  currentModeName: 'dorian',
  padSampleId: null,
  leadSampleId: null,
  // New state for features
  rootOffset: 0,          // semitones offset from C4 (0-11)
  bpm: 85,
  swing: 0,               // swing percentage 0-100
  arpPatternIdx: 0,       // index into ARP_PATTERNS
  presetIdx: 0,           // current preset index
  extraScaleMode: null,   // null = face-controlled modal, or string name of extra scale
};

// ---- Smoothing Filter ----
MUZE.Smooth = {
  _prev: {},
  update(key, raw, alpha) {
    if (!(key in this._prev)) { this._prev[key] = raw; return raw; }
    const s = alpha * raw + (1 - alpha) * this._prev[key];
    this._prev[key] = s; return s;
  },
  reset() { this._prev = {}; }
};
