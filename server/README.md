# Muze · Magenta RealTime 2 server

This turns **Google Magenta RealTime 2** (June 2026) into the generative core of
Muze. Muze stays the gesture / vibe / visual controller; this local service runs
the model and streams 48 kHz stereo audio that Muze plays back through its own
effects + visualizer.

## Why a server (the honest architecture)

Magenta RT2 is a **C++/MLX model** (230 M – 2.4 B params). It **cannot** run inside
a mobile web browser or on an iPhone — there is no WebGPU/JS port. The only way to
make it Muze's "core" is to run the model where it *can* run (an Apple-Silicon Mac /
GPU) and stream its audio to the Muze front-end:

```
 Muze web app  ──(control: style + chord + drums + CFG, JSON @ ~12 Hz)──▶  this server ──▶ Magenta RT2 (MLX)
   (browser)    ◀──────────(audio: 48 kHz stereo PCM, binary WebSocket)──────────┘
```

Muze remains fully playable **without** the server — the Tone.js synth engine is the
default sound and the Magenta layer is additive, so if the server is unreachable the
app degrades gracefully (the 🧠 **AI** button just shows a grey/red status dot).

When Muze runs on an **iPhone**, point it at your Mac: open the app with
`?mag=ws://<your-mac-ip>:8010/ws` (or set `localStorage.muzeMagentaUrl`). The Mac does
the generating; the phone streams it.

## Quick start (Apple Silicon)

```bash
cd server
uv venv --python 3.12 .venv            # or: python3 -m venv .venv
uv pip install --python .venv/bin/python "magenta-rt[mlx]" "fastapi" "uvicorn[standard]" "websockets"

# download the model (~0.5 GB for small, ~2.5 GB for base) into ~/Documents/Magenta
.venv/bin/mrt models init              # MusicCoCa + SpectroStream (shared, required)
.venv/bin/mrt models download mrt2_small   # or: mrt2_base (M-Pro/Max class, higher quality)

# run it — also serves the Muze web app on the same origin
./run.sh                               # http://localhost:8010  (auto: real model if present)
```

Then open **http://localhost:8010/**, tap **Start**, and tap the **🧠 AI** chip
(right-hand instrument column). Tap = on/off; **long-press = "free harmony"** (lets
Magenta improvise around your chord instead of locking to it).

### No weights yet? Mock mode runs the whole pipeline today

```bash
./run.sh --engine mock                 # pure-numpy synth, no model/weights needed
```

Mock mode renders your live chord + drums as a simple pad so you can verify the full
transport / routing / UI before (or without) downloading the model.

## Models & hardware

| model        | params | download | real-time on… |
|--------------|--------|----------|---------------|
| `mrt2_small` | 230 M  | ~0.5 GB  | any Apple-Silicon Mac (incl. Air) — **default** |
| `mrt2_base`  | 2.4 B  | ~2.5 GB  | M-Pro / M-Max class |

Measured on an **M4 Max**, `mrt2_small` generates ~**1.3× real-time** (2.0 s of audio
in ~1.55 s) — comfortably live. `mrt2_base` also clears real-time on a Max chip; use it
for higher quality.

```bash
./run.sh --model mrt2_base             # bigger/better (run.sh serves the web app too)
# ws-only (no static web hosting), e.g. behind your own static server:
.venv/bin/python magenta_server.py --engine mlx --model mrt2_small --port 8010
```

## How control maps to Magenta

The Muze client (`js/magenta-rt.js`) sends a small JSON control message ~12×/s:

* **style** — a weighted MusicCoCa text prompt built from the active Vibe / preset +
  musical mode + key + tempo (e.g. `"lo-fi hip hop, dusty rhodes, vinyl crackle,
  smoky cool minor | f minor key, slow, 72 bpm"`). Magenta has no tempo/key knobs, so
  key + bpm are encoded both in the **note pianoroll** and in this text.
* **notes** — the current chord voicing (root/3rd/5th/7th + melody) as a 128-pitch
  Magenta pianoroll, so generation stays harmonically locked to what you hear.
* **drums** — on/off, following Muze's BEAT toggle (off for ambient presets).
* **CFG / temperature** — driven by gestures: hand height → note adherence, mouth-open
  → style strength, brows → drum punch, hand-X → temperature.

## API surface used

`magenta_rt` 2.0.2 — the exported-`.mlxfn` real-time path:

```python
from magenta_rt import MagentaRT2Mlxfn
mrt = MagentaRT2Mlxfn(size="mrt2_small")          # loads .mlxfn, warms up MLX kernels
emb = mrt.embed_style("disco funk", use_mapper=True)
wav, state = mrt.generate(style=emb, notes=[...128 ints...], drums=[1],
                          cfg_musiccoca=3.0, frames=2, state=state)  # 2 × 40ms = 80ms
# wav.samples: (N, 2) float32 @ 48 kHz; thread `state` back in to continue
```

> **Threading note:** MLX GPU streams are thread-local, so the server builds the model
> and runs every `generate()` on a single dedicated worker thread.

## Files

| file | purpose |
|------|---------|
| `magenta_server.py` | FastAPI + WebSocket server, session/transport, generation loop |
| `engines.py`        | `MlxEngine` (real, `MagentaRT2Mlxfn`) + `MockEngine` (numpy) |
| `protocol.py`       | binary wire format (20-byte `MZA1` header + PCM) |
| `selftest.py`       | end-to-end protocol check against a running server |
| `smoke_mlx.py`      | real-model load + RTF benchmark |
| `test_client_logic.js` | node test of the browser control-mapping logic |

## License

Code (this server + magenta-rt) is Apache-2.0. The Magenta RT2 **weights** are
CC-BY-4.0 (commercial use allowed, attribution required). You are responsible for the
outputs you generate.
