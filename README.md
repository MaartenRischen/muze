# Jammerman (Muze)

**Your body is the instrument.** A browser-based musical instrument played with
your face, hands, and touch. Built with [Tone.js](https://tonejs.github.io/) for
audio and [MediaPipe](https://developers.google.com/mediapipe) for face + hand
tracking and background segmentation. Runs entirely client-side — no build step.

Primary target: **Chrome on mobile** (iOS/Android). Secondary: desktop Chrome, Safari.

## Run it

It's static — serve the folder and open `index.html` over HTTP (camera + audio
require a secure context, so `file://` won't work):

```bash
python3 -m http.server 8123
# then open http://localhost:8123/index.html and tap "Begin Session"
```

Grant camera + microphone permission when prompted.

## How you play

- **Smile / frown** → musical mode (valence): bright Lydian → dark Phrygian
- **Eyebrows** → octave shift
- **Open mouth** → opens the arp filter (brightness)
- **Head tilt / roll** → chorus + expression
- **Hand height** → melody pitch; **open palm** glides (legato), **fist** re-triggers (staccato)
- **Chord bar** (bottom) → pick the chord; or turn on an auto **progression**
- **Instrument toggles** (right) → Pad, Arp 1/2, Melody, Beat, Binaural
- **⚙ → Perform** → Vibes, Surprise, presets, key/scale, tempo, palettes, visuals, scenes, loop recorder
- **MIX** → per-channel mixer (volume, pan, EQ, reverb/delay sends)

## Quick start (the fast path)

Open **⚙ → Perform → Vibe** and tap it — each tap loads a complete combo
(synth preset + scale + key + drum groove + chord progression) **and turns on a
full arrangement so you hear it instantly**. Hit **🎲 Surprise** for an endless
stream of random combos. Pick a **Palette** to recolor every visual.

## Architecture

Plain ES — one global namespace `MUZE`, no bundler. Files load in order from
`index.html`:

| File | Responsibility |
|------|----------------|
| `js/config.js` | Frozen `Config` (scales, presets, grooves, progressions, palettes), mutable `State`, smoothing filters, `VERSION` |
| `js/tracking.js` | Camera + MediaPipe face/hand landmark extraction |
| `js/bgblur.js` | Selfie segmentation → background blur + person cutout |
| `js/music.js` | Music theory (scales, voicings, quantize, euclidean), sample library, preset extensions |
| `js/audio-engine.js` | Tone.js send/return bus engine, synths, drums, presets, auto-rhythm |
| `js/mixer.js` | Per-channel mixer model |
| `js/visualizer.js` | Canvas 2D audio-reactive visuals (aurora, waveform ring, halo, frequency arc, face mesh AR, particles) |
| `js/moodlight.js` | CSS-variable mood lighting synced to mode + beat |
| `js/drumfx.js` | Drum hit visual FX |
| `js/storage.js` | localStorage persistence |
| `js/ui.js` | Instrument toggles, perform tab, popups, mixer UI |
| `js/features.js` | Loop recorder, scenes, gyroscope, chord progressions, **Vibes**, **Theme**, **VisualSettings** |
| `js/app.js` | Main render/audio loop (`MUZE.Loop`) |

### Color flow

The accent color drives every visual. By default it follows the musical mode
(`MODE_COLORS`). A fixed **Palette** override (`MUZE.Theme`) pins one color across
the visualizer, mood lighting, and CSS custom properties.

## Dev tooling

- `node test-data.js` — validates config/music data integrity (presets, grooves, scales, progressions, vibes, palettes).
- `./snapshot.sh <NN-slug> "desc"` — copies the runnable app into `versions/<NN-slug>/` (gitignored) for side-by-side comparison.

See [CHANGELOG.md](CHANGELOG.md) for version history.
