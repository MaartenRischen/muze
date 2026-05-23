// Reusable data-integrity check: node test-data.js
global.window = global;
const fs = require('fs');
eval(fs.readFileSync(__dirname + '/js/config.js', 'utf8'));
eval(fs.readFileSync(__dirname + '/js/music.js', 'utf8'));
const C = MUZE.Config, M = MUZE.Music;
let errs = [];
C.RHYTHM_PATTERNS.forEach(r => { ['kick','snare','hat'].forEach(k => { if (r[k].length % 16 !== 0) errs.push(`${r.name}.${k} len ${r[k].length}`); }); });
C.PRESETS.forEach(p => { if (!MUZE.PresetExtensions[p.name]) errs.push(`preset ${p.name} missing extension`);
  if (p.rhythmPattern >= C.RHYTHM_PATTERNS.length) errs.push(`preset ${p.name} bad rhythmPattern ${p.rhythmPattern}`); });
Object.keys(M.EXTRA_SCALES).forEach(s => { if (!C.MODE_COLORS[s]) errs.push(`scale ${s} missing color`);
  if (M.getScaleName(M.EXTRA_SCALES[s]) === '?') errs.push(`scale ${s} unnamed`); });
console.log(`VERSION ${MUZE.VERSION} | presets ${C.PRESETS.length} | rhythms ${C.RHYTHM_PATTERNS.length} | scales ${Object.keys(M.EXTRA_SCALES).length}`);
if (errs.length) { console.error('FAIL:\n' + errs.join('\n')); process.exit(1); } else console.log('DATA OK');
