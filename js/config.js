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

  SCALE_LYDIAN: [0,2,4,6,7,9,11],
  SCALE_IONIAN: [0,2,4,5,7,9,11],
  SCALE_MIXOLYDIAN: [0,2,4,5,7,9,10],
  SCALE_DORIAN: [0,2,3,5,7,9,10],
  SCALE_AEOLIAN: [0,2,3,5,7,8,10],
  SCALE_PHRYGIAN: [0,1,3,5,7,8,10],

  ROOT_NOTE: 60, OCTAVE_RANGE: 2, BPM_DEFAULT: 85,
  CHORD_DEGREES: [0, 3, 4, 2, 5, 0],
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

  // Mode → color mapping
  MODE_COLORS: {
    phrygian:   { accent: '#a78bfa', rgb: '167,139,250' },
    aeolian:    { accent: '#818cf8', rgb: '129,140,248' },
    dorian:     { accent: '#22d3ee', rgb: '34,211,238' },
    mixolydian: { accent: '#34d399', rgb: '52,211,153' },
    ionian:     { accent: '#fbbf24', rgb: '251,191,36' },
    lydian:     { accent: '#fb923c', rgb: '251,146,60' },
  },

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
