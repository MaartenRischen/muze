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

## AI core (Magenta RealTime 2) — optional

Muze can use Google's **Magenta RealTime 2** (June 2026 open-weights live music model)
as a generative core. It's a C++/MLX model, so it can't run in the browser — instead a
small **local server** (`server/`) runs the model on Apple Silicon and streams 48 kHz
audio that Muze plays through its own effects + visualizer. Your gestures, vibe, chord
and key steer the generation in real time.

```bash
cd server && ./run.sh          # serves the app + AI on http://localhost:8010
```

Then open http://localhost:8010/, tap **Start**, and tap the **🧠 AI** chip. No server?
Muze runs exactly as before on its built-in Tone.js engine (AI is additive + optional).
Full setup, models and the honest architecture: **[server/README.md](server/README.md)**.

## How you play

- **Smile / frown** → musical mode (valence): bright Lydian → dark Phrygian
- **Eyebrows** → octave shift
- **Open mouth** → opens the arp filter (brightness)
- **Head tilt / roll** → chorus + expression
- **Hand height** → melody pitch; **open palm** glides (legato), **fist** re-triggers (staccato)
- **Chord bar** (bottom) → pick the chord; or turn on an auto **progression**
- **Instrument toggles** (right) → Pad, Arp 1/2, Melody, Beat, Binaural, **🧠 AI**
- **🧠 AI** → layers **Magenta RealTime 2** generative audio on top, steered live by your
  vibe/chord/gestures (needs the local server — see below). Tap = on/off, hold = free harmony
- **✨ (toolbar)** → tap for the next Vibe, hold for a 🎲 Surprise
- **⚙ → Perform** → Vibes, Surprise, Share link, presets, key/scale, tempo, palettes, visuals, scenes, loop recorder
- **? (toolbar)** → guided tutorials + a Quick Reference gesture cheat-sheet
- **MIX** → per-channel mixer (volume, pan, EQ, reverb/delay sends)

## Quick start (the fast path)

Tap **✨** in the toolbar (or **⚙ → Perform → Vibe**) — each tap loads a complete
combo (synth preset + scale + key + drum groove + chord progression) **and turns
on a full arrangement so you hear it instantly**. **Hold ✨** (or **🎲 Surprise**)
for an endless stream of random combos. Pick a **Palette** to recolor every
visual, and **Copy link** to share the exact sound as a URL.

## Install

It's a PWA: open it in mobile Chrome/Safari and use **Add to Home Screen** to run
it full-screen as a standalone app (Jammerman icon, no browser chrome).

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
