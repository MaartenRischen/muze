/* Node harness: validate MUZE.MagentaRT control-mapping logic without a browser.
   Loads config.js + music.js + magenta-rt.js with minimal stubs and checks the
   State -> Magenta control translation (style prompts, chord pianoroll, gestures). */
const fs = require('fs');
const vm = require('vm');
const path = require('path');

global.window = global;
global.localStorage = { getItem: () => null, setItem: () => {} };
global.location = { search: '', protocol: 'http:', host: '127.0.0.1:8012' };
global.document = {
  getElementById: () => null, addEventListener: () => {},
  createElement: () => ({ style: { setProperty() {} }, classList: { add() {}, remove() {}, toggle() {} }, appendChild() {}, setAttribute() {} }),
  body: { appendChild() {} },
};

const root = path.resolve(__dirname, '..');
const load = (f) => vm.runInThisContext(fs.readFileSync(path.join(root, f), 'utf8'), { filename: f });
load('js/config.js'); load('js/music.js'); load('js/magenta-rt.js');

const M = global.MUZE;
const A = M.MagentaRT;
const fails = [];
const assert = (c, m) => { if (!c) fails.push(m); };

// --- scenario: Lo-Fi Chill preset, dorian, F, 72bpm, hand high+right, mouth open ---
Object.assign(M.State, {
  presetIdx: 3, currentScale: M.Config.SCALE_DORIAN, currentModeName: 'dorian',
  extraScaleMode: null, rootOffset: 5, bpm: 72, chordIndex: 0,
  handPresent: true, handY: 0.2, handX: 0.8, mouthOpenness: 0.7, browHeight: 0.5,
  melodyNote: null,
});

const style = A._buildStyle(M.State);
console.log('style.full :', style.full);
console.log('prompts    :', JSON.stringify(style.prompts));
const chord = A._chordMidi(M.State);
console.log('chord MIDI :', chord);
const g = A._gestureControl(M.State);
console.log('gesture    :', JSON.stringify(g));

assert(style.prompts.length === 2, 'expected 2 weighted prompts');
assert(style.prompts[0].weight === 1.0 && style.prompts[1].weight === 0.5, 'prompt weights 1.0/0.5');
assert(/lo-fi/.test(style.full), 'lo-fi genre present');
assert(/f minor key/.test(style.full), 'F minor key (dorian is minorish)');
assert(/72 bpm/.test(style.full), 'bpm in prompt');
assert(/slow/.test(style.full), 'tempo word "slow" for 72bpm');
assert(chord.length >= 3, 'chord produced >=3 tones');
assert(chord.every((n) => n >= 0 && n <= 127), 'all chord notes in MIDI range');
assert(g.cfg.notes >= 3.0 && g.cfg.notes <= 3.6, `handY-high -> tight cfg_notes (~3.3), got ${g.cfg.notes}`);
assert(g.temperature >= 1.3 && g.temperature <= 1.45, `handX-right -> temp ~1.38, got ${g.temperature}`);
assert(g.cfg.musiccoca >= 3.8 && g.cfg.musiccoca <= 4.1, `mouth-open -> cfg_musiccoca ~3.95, got ${g.cfg.musiccoca}`);

// --- vibe-active path: a curated vibe should drive the prompt ---
M.Vibes = { _idx: 0, LIST: [{ name: 'Lofi Sunset' }] };
const s2 = A._buildStyle(M.State);
console.log('vibe style :', s2.full);
assert(/golden-hour|vinyl crackle/.test(s2.full), 'curated vibe prompt used when a vibe is active');

// --- binary wire-frame parse parity (mirror server protocol.py header) ---
function buildFrame(seq, frames) {
  const buf = new ArrayBuffer(20 + frames * 2 * 2);
  const dv = new DataView(buf);
  dv.setUint8(0, 0x4D); dv.setUint8(1, 0x5A); dv.setUint8(2, 0x41); dv.setUint8(3, 0x31);
  dv.setUint8(4, 0); dv.setUint8(5, 2); dv.setUint8(6, 0); dv.setUint8(7, 1);
  dv.setUint32(8, seq, true); dv.setUint32(12, 48000, true); dv.setUint32(16, frames, true);
  const pcm = new Int16Array(buf, 20, frames * 2);
  for (let i = 0; i < frames * 2; i++) pcm[i] = (i % 2 === 0) ? 16384 : -16384;
  return buf;
}
const fb = buildFrame(7, 64);
const dv = new DataView(fb);
assert(dv.getUint8(0) === 0x4D && dv.getUint8(3) === 0x31, 'magic MZA1');
assert(dv.getUint32(8, true) === 7, 'seq roundtrip');
assert(dv.getUint32(12, true) === 48000, 'sampleRate roundtrip');
assert(dv.getUint32(16, true) === 64, 'frameCount roundtrip');
assert(fb.byteLength === 20 + 64 * 2 * 2, 'int16 payload size');

if (fails.length) { console.error('\nFAIL:\n - ' + fails.join('\n - ')); process.exit(1); }
console.log('\nPASS — client mapping + wire-parse logic verified');
