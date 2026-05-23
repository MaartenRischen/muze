/* ============================================================
   MUZE — Config, State, Smoothing
   ============================================================ */

window.MUZE = {};

// Single source of truth for the displayed app version (shown in #build-version).
MUZE.VERSION = 'v6.8.0';

const SAMPLE_BASE = 'https://ffwbirepsanifejscguz.supabase.co/storage/v1/object/public/Samples/';

MUZE.Config = Object.freeze({
  CAM_WIDTH: 640, CAM_HEIGHT: 480,
  SMOOTH_FAST: 0.35, SMOOTH_SLOW: 0.15, SMOOTH_HAND: 0.30,

  MOUTH_OPEN_MIN: 0.015, MOUTH_OPEN_MAX: 0.09,
  LIP_SMILE_MIN: -0.045, LIP_SMILE_MAX: 0.045,
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
  DETECT_INTERVAL: 50,  // 20fps detection (was 30fps) — saves ~30% ML CPU
  SWIPE_THRESHOLD: 50, SWIPE_MAX_TIME: 300, DOUBLE_TAP_TIME: 300, HOLD_TIME: 400,

  RHYTHM_PATTERNS: [
    { name: 'Basic', kick:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
    { name: 'Funk', kick:[1,0,0,0,0,0,1,0,1,0,0,0,0,0,1,0], snare:[0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,0], hat:[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1] },
    { name: 'Broken', kick:[1,0,0,1,0,0,1,0,1,0,0,1,0,0,1,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1], hat:[1,0,1,0,1,0,1,0,1,0,1,1,1,0,1,0] },
    { name: 'Minimal', kick:[1,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0] },
    { name: 'Trap', kick:[1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[1,0,1,1,1,0,1,1,1,0,1,1,1,0,1,1] },
    { name: 'Halftime', kick:[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], snare:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
    { name: 'House',     kick:[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0] },
    { name: 'Boom Bap',  kick:[1,0,0,0,0,0,1,0,0,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
    { name: 'Liquid DnB',kick:[1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], hat:[1,0,1,1,1,0,1,0,1,0,1,1,1,0,1,0] },
    { name: 'Dembow',    kick:[1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], snare:[0,0,0,1,0,0,1,0,0,0,0,1,0,0,1,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
    { name: 'Afrobeat',  kick:[1,0,0,1,0,0,1,0,0,1,0,0,1,0,0,0], snare:[0,0,1,0,0,1,0,0,1,0,0,1,0,0,1,0], hat:[1,1,0,1,1,0,1,1,0,1,1,0,1,1,0,1] },
    { name: 'UK Garage', kick:[1,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,1,0,0,0,0], hat:[1,0,1,1,0,1,1,0,1,0,1,1,0,1,1,0] },
    { name: 'Bossa',     kick:[1,0,0,0,0,0,1,0,1,0,0,0,0,0,1,0], snare:[0,0,1,0,0,1,0,0,0,1,0,0,1,0,0,0], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
    { name: 'Drill',     kick:[1,0,0,0,0,0,1,0,0,1,0,0,0,0,0,0], snare:[0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], hat:[1,0,1,1,0,1,1,0,1,1,0,1,1,0,1,1] },
    { name: 'Breakbeat', kick:[1,0,0,0,0,0,1,1,0,0,1,0,0,0,0,0], snare:[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1], hat:[1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0] },
  ],

  // Arpeggio pattern types and note values
  ARP_PATTERNS: ['up-down', 'up', 'down', 'random', 'up-up-down', 'played'],
  ARP_NOTE_VALUES: ['4n', '8n', '8n.', '16n', '16n.', '32n'],

  // Curated chord progressions for auto-advance. Each value is a scale degree
  // 0-5 mapping to the chord buttons I, ii, iii, IV, V, vi. One chord per bar.
  PROGRESSIONS: [
    { name: 'Pop',        degrees: [0, 4, 5, 3] },          // I–V–vi–IV
    { name: 'Ballad',     degrees: [5, 3, 0, 4] },          // vi–IV–I–V
    { name: 'Doo-Wop',    degrees: [0, 5, 3, 4] },          // I–vi–IV–V
    { name: 'Jazz',       degrees: [1, 4, 0, 0] },          // ii–V–I
    { name: 'Canon',      degrees: [0, 4, 5, 2, 3, 0, 3, 4] }, // Pachelbel
    { name: 'Andalusian', degrees: [5, 4, 3, 2] },          // descending drama
    { name: 'Epic',       degrees: [5, 3, 4, 0] },          // vi–IV–V–I
    { name: 'Dreamy',     degrees: [0, 2, 3, 3] },          // I–iii–IV
    { name: 'Tension',    degrees: [1, 3, 4, 4] },          // ii–IV–V
    { name: 'Wander',     degrees: [0, 3, 1, 4] },          // I–IV–ii–V
  ],

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
    'in-sen':         { accent: '#6366f1', rgb: '99,102,241' },
    'iwato':          { accent: '#7c3aed', rgb: '124,58,237' },
    'egyptian':       { accent: '#eab308', rgb: '234,179,8' },
    'hungarian min':  { accent: '#dc2626', rgb: '220,38,38' },
    'double harm':    { accent: '#db2777', rgb: '219,39,119' },
    'ukrainian':      { accent: '#14b8a6', rgb: '20,184,166' },
  },

  // Color palettes — override the auto mode-driven accent with a fixed
  // global color. 'Auto' (accent null) restores mode-following behavior.
  PALETTES: [
    { name: 'Auto',    accent: null,      rgb: null },
    { name: 'Sunset',  accent: '#fb923c', rgb: '251,146,60' },
    { name: 'Ocean',   accent: '#38bdf8', rgb: '56,189,248' },
    { name: 'Magenta', accent: '#e879f9', rgb: '232,121,249' },
    { name: 'Mint',    accent: '#34d399', rgb: '52,211,153' },
    { name: 'Gold',    accent: '#fbbf24', rgb: '251,191,36' },
    { name: 'Mono',    accent: '#e5e7eb', rgb: '229,231,235' },
  ],

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
    {
      name: 'Cinematic',
      bpm: 70,
      rootOffset: 8, // G#/Ab — dark, filmic
      padVolume: -7, arpVolume: -13, melodyVolume: -8,
      kickVolume: -8, snareVolume: -16, hatVolume: -60,
      padOsc: 'sawtooth', padHarm: 2, padMod: 2.0, padAttack: 2.0, padRelease: 5.0,
      arpOsc: 'triangle', arpAttack: 0.2, arpDecay: 0.8, arpSustain: 0.4, arpRelease: 2.0,
      melOsc: 'sine', melAttack: 0.3, melDecay: 0.4, melSustain: 0.8, melRelease: 1.6,
      arpPattern: 'up-down', rhythmPattern: 5, swing: 0,
      reverbDecay: 6.0, delayFeedback: 0.4,
      padReverb: 0.65, padDelay: 0.35, arpReverb: 0.55, arpDelay: 0.4,
    },
    {
      name: 'Synthwave',
      bpm: 100,
      rootOffset: 9, // A — retro neon
      padVolume: -13, arpVolume: -7, melodyVolume: -6,
      kickVolume: -5, snareVolume: -8, hatVolume: -15,
      padOsc: 'sawtooth', padHarm: 2, padMod: 2.5, padAttack: 0.4, padRelease: 1.8,
      arpOsc: 'sawtooth', arpAttack: 0.01, arpDecay: 0.2, arpSustain: 0.6, arpRelease: 0.4,
      melOsc: 'sawtooth', melAttack: 0.02, melDecay: 0.2, melSustain: 0.7, melRelease: 0.35,
      arpPattern: 'up', rhythmPattern: 0, swing: 0,
      reverbDecay: 2.8, delayFeedback: 0.4,
      padReverb: 0.4, padDelay: 0.4, arpReverb: 0.3, arpDelay: 0.45,
    },
    {
      name: 'Vaporwave',
      bpm: 62,
      rootOffset: 5, // F — woozy, slow
      padVolume: -9, arpVolume: -11, melodyVolume: -8,
      kickVolume: -7, snareVolume: -12, hatVolume: -20,
      padOsc: 'triangle', padHarm: 3, padMod: 1.0, padAttack: 1.8, padRelease: 4.0,
      arpOsc: 'sine', arpAttack: 0.1, arpDecay: 0.6, arpSustain: 0.5, arpRelease: 1.4,
      melOsc: 'triangle', melAttack: 0.15, melDecay: 0.4, melSustain: 0.7, melRelease: 1.0,
      arpPattern: 'up-down', rhythmPattern: 5, swing: 35,
      reverbDecay: 4.5, delayFeedback: 0.5,
      padReverb: 0.6, padDelay: 0.45, arpReverb: 0.5, arpDelay: 0.4,
    },
    {
      name: 'Liquid DnB',
      bpm: 170,
      rootOffset: 2, // D — rolling, melodic
      padVolume: -12, arpVolume: -8, melodyVolume: -6,
      kickVolume: -5, snareVolume: -7, hatVolume: -16,
      padOsc: 'sine', padHarm: 2, padMod: 1.8, padAttack: 1.2, padRelease: 2.5,
      arpOsc: 'triangle', arpAttack: 0.005, arpDecay: 0.18, arpSustain: 0.4, arpRelease: 0.3,
      melOsc: 'sawtooth', melAttack: 0.01, melDecay: 0.15, melSustain: 0.5, melRelease: 0.3,
      arpPattern: 'up-up-down', rhythmPattern: 8, swing: 0,
      reverbDecay: 2.5, delayFeedback: 0.35,
      padReverb: 0.45, padDelay: 0.3, arpReverb: 0.35, arpDelay: 0.3,
    },
    {
      name: 'Meditation',
      bpm: 50,
      rootOffset: 0, // C — still, drone
      padVolume: -6, arpVolume: -18, melodyVolume: -12,
      kickVolume: -60, snareVolume: -60, hatVolume: -60,
      padOsc: 'sine', padHarm: 4, padMod: 1.5, padAttack: 4.0, padRelease: 8.0,
      arpOsc: 'sine', arpAttack: 1.0, arpDecay: 2.0, arpSustain: 0.3, arpRelease: 4.0,
      melOsc: 'sine', melAttack: 1.0, melDecay: 0.6, melSustain: 0.6, melRelease: 3.0,
      arpPattern: 'random', rhythmPattern: 3, swing: 0,
      reverbDecay: 9.0, delayFeedback: 0.6,
      padReverb: 0.85, padDelay: 0.55, arpReverb: 0.75, arpDelay: 0.5,
    },
    {
      name: 'Trap Soul',
      bpm: 72,
      rootOffset: 1, // C# — moody halftime
      padVolume: -11, arpVolume: -10, melodyVolume: -7,
      kickVolume: -3, snareVolume: -7, hatVolume: -13,
      padOsc: 'triangle', padHarm: 2, padMod: 1.5, padAttack: 0.6, padRelease: 2.2,
      arpOsc: 'triangle', arpAttack: 0.02, arpDecay: 0.3, arpSustain: 0.4, arpRelease: 0.6,
      melOsc: 'sine', melAttack: 0.04, melDecay: 0.25, melSustain: 0.6, melRelease: 0.6,
      arpPattern: 'down', rhythmPattern: 4, swing: 8,
      reverbDecay: 3.2, delayFeedback: 0.3,
      padReverb: 0.4, padDelay: 0.3, arpReverb: 0.35, arpDelay: 0.25,
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
  arpNoteValueIdx: 1,     // index into ARP_NOTE_VALUES (default '8n')
  arp2PatternIdx: 2,      // arp2 defaults to 'down'
  arp2NoteValueIdx: 3,    // arp2 defaults to '16n'
  presetIdx: 0,           // current preset index
  extraScaleMode: null,   // null = face-controlled modal, or string name of extra scale
  latencyMode: 'balanced', // 'low' (fast phone), 'balanced' (default), 'safe' (slow phone)
  auroraEnabled: true,     // ambient nebula backdrop behind the user
  faceGlowEnabled: true,   // face-mesh AR glow (contour, iris, particles, aura)
  liteMode: false,         // performance mode: drops ambient layers + caps particles
  palette: null,           // {accent,rgb} fixed color override, or null = follow mode
  paletteIdx: 0,           // index into Config.PALETTES (0 = Auto)
};

// ---- Smoothing Filter (legacy, kept for reference) ----
MUZE.Smooth = {
  _prev: {},
  update(key, raw, alpha) {
    if (!(key in this._prev)) { this._prev[key] = raw; return raw; }
    const s = alpha * raw + (1 - alpha) * this._prev[key];
    this._prev[key] = s; return s;
  },
  reset() { this._prev = {}; }
};

// ---- 1-Euro Filter (adaptive smoothing: low jitter when still, low lag when fast) ----
MUZE.OneEuroFilter = function(freq, minCutoff, beta, dCutoff) {
  this.freq = freq || 60;
  this.minCutoff = minCutoff || 1.0;
  this.beta = beta || 0.0;
  this.dCutoff = dCutoff || 1.0;
  this.x = null;
  this.dx = 0;
  this.lastTime = null;
};
MUZE.OneEuroFilter.prototype.filter = function(x, timestamp) {
  if (this.x === null) { this.x = x; this.lastTime = timestamp; return x; }
  var dt = (timestamp - this.lastTime) / 1000;
  if (dt <= 0) dt = 1 / this.freq;
  this.lastTime = timestamp;
  var dx = (x - this.x) / dt;
  var edx = this._alpha(dt, this.dCutoff) * dx + (1 - this._alpha(dt, this.dCutoff)) * this.dx;
  this.dx = edx;
  var cutoff = this.minCutoff + this.beta * Math.abs(edx);
  var ex = this._alpha(dt, cutoff) * x + (1 - this._alpha(dt, cutoff)) * this.x;
  this.x = ex;
  return ex;
};
MUZE.OneEuroFilter.prototype._alpha = function(dt, cutoff) {
  var tau = 1.0 / (2 * Math.PI * cutoff);
  return 1.0 / (1.0 + tau / dt);
};
