"""
Generation engines behind a single tiny interface.

    BaseEngine.update_control(ctrl: dict)   # cheap, called from the WS receiver task
    BaseEngine.generate(frames: int) -> np.ndarray   # (frames*1920, 2) float32 [-1,1]
    BaseEngine.reset()                       # new streaming session -> fresh model state

Two implementations:

  * MlxEngine  — the real thing. Holds ONE persistent Magenta RT2 (MLX) model + ONE
                 streaming `state`, and changes style / notes / drums / CFG *per call*
                 (the documented streaming pattern). Style text prompts are embedded
                 with MusicCoCa and weight-averaged in the 768-dim space (app-layer
                 multi-prompt blending). Runs on Apple Silicon GPU via MLX.

  * MockEngine — pure-numpy additive synth. No model, no weights, no heavy deps. It
                 audibly renders the *same* control messages (held chord tones + an
                 optional drum pulse) so the entire transport / routing / UI pipeline
                 is testable end-to-end on any machine, today. This is the graceful
                 path before `mrt models download` has run.

The control dict the client sends is normalised by magenta_server into:
    {
      "stylePrompts": [{"text": str, "weight": float}, ...],
      "notesMidi":    [int, ...],   # active MIDI pitches (Muze chord voicing + melody)
      "noteOnset":    bool,         # True on a chord change -> Magenta onsets, else sustain
      "freeHarmony":  bool,         # True -> non-chord pitches masked (model free to fill)
      "drums":        bool,
      "drumsMasked":  bool,         # True -> send Magenta drums=-1 (masked) instead of 0
      "cfg":          {"musiccoca": f, "notes": f, "drums": f},
      "temperature":  float,
      "topK":         int,
      "bpm":          int,
    }
"""

import threading

import numpy as np

from protocol import CHANNELS, FRAME_SAMPLES, SAMPLE_RATE

# Magenta RT2 conditioning ranges (from the model source).
CFG_MIN, CFG_MAX = -1.0, 7.0
TEMP_MIN, TEMP_MAX = 0.5, 2.0


def _clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def default_control() -> dict:
    return {
        "stylePrompts": [{"text": "warm ambient electronic", "weight": 1.0}],
        "notesMidi": [],
        "noteOnset": False,
        "freeHarmony": False,
        "drums": False,
        "drumsMasked": False,
        "cfg": {"musiccoca": 3.0, "notes": 1.0, "drums": 1.0},
        "temperature": 1.3,
        "topK": 40,
        "bpm": 90,
    }


def build_notes_vector(midi_list, onset: bool, free_harmony: bool):
    """Muze chord voicing -> Magenta 128-int per-pitch state vector.

    Magenta per-pitch state: -1 masked (model free), 0 off, 1 sustain, 2 onset, 3 free-on.
    Empty chord -> None (fully masked: Magenta improvises harmony).
    """
    if not midi_list:
        return None
    off_val = -1 if free_harmony else 0     # free: let model fill non-chord pitches
    vec = [off_val] * 128
    on_val = 2 if onset else 1
    for m in midi_list:
        m = int(m)
        if 0 <= m <= 127:
            vec[m] = on_val
    return vec


def drums_value(drums: bool, masked: bool) -> int:
    if masked:
        return -1
    return 1 if drums else 0


class BaseEngine:
    name = "base"
    sample_rate = SAMPLE_RATE
    channels = CHANNELS

    def __init__(self):
        self._lock = threading.Lock()
        self._ctrl = default_control()

    def update_control(self, ctrl: dict):
        with self._lock:
            # shallow-merge known keys; ignore unknowns
            for k, v in ctrl.items():
                if k == "cfg" and isinstance(v, dict):
                    self._ctrl["cfg"].update(v)
                else:
                    self._ctrl[k] = v
        self._on_control_changed(ctrl)

    def _snapshot(self) -> dict:
        with self._lock:
            c = dict(self._ctrl)
            c["cfg"] = dict(self._ctrl["cfg"])
            c["notesMidi"] = list(self._ctrl["notesMidi"])
            c["stylePrompts"] = [dict(p) for p in self._ctrl["stylePrompts"]]
            return c

    def _on_control_changed(self, ctrl: dict):
        pass

    def generate(self, frames: int) -> np.ndarray:
        raise NotImplementedError

    def reset(self):
        pass

    def close(self):
        pass


# ----------------------------------------------------------------------------
# Mock engine: pure-numpy additive synth (no model needed)
# ----------------------------------------------------------------------------
class MockEngine(BaseEngine):
    """Audible stand-in so the pipeline runs without the model.

    Renders the live chord voicing as a soft detuned-sine pad with continuous
    per-voice phase (gapless across chunks), plus a kick+hat pulse when drums
    are on, locked to the current bpm. It is not meant to sound like Magenta —
    it exists to prove that control messages reach the engine and stream back
    as gapless, visualised audio.
    """

    name = "mock"

    def __init__(self):
        super().__init__()
        self._phase = {}          # midi -> running phase (radians), persists across calls
        self._gain = {}           # midi -> current envelope gain (smoothed toward target)
        self._t = 0               # global sample counter (for drums)

    def reset(self):
        self._phase.clear()
        self._gain.clear()
        self._t = 0

    @staticmethod
    def _midi_hz(m):
        return 440.0 * (2.0 ** ((m - 69) / 12.0))

    def generate(self, frames: int) -> np.ndarray:
        n = frames * FRAME_SAMPLES
        c = self._snapshot()
        active = set(int(m) for m in c["notesMidi"] if 0 <= int(m) <= 127)
        sr = self.sample_rate

        out = np.zeros((n, 2), dtype=np.float32)
        idx = np.arange(n, dtype=np.float64)

        # Pad: one detuned-sine voice per active pitch, with a slow gain glide so
        # notes fade in/out instead of clicking.
        target_per_voice = 0.22 / max(1, len(active)) if active else 0.0
        voices = set(self._phase) | active
        for m in voices:
            tgt = target_per_voice if m in active else 0.0
            g0 = self._gain.get(m, 0.0)
            # exponential glide toward target across the block (~30 ms time constant)
            glide = np.exp(-idx / (0.03 * sr))
            env = tgt + (g0 - tgt) * glide
            if tgt == 0.0 and g0 < 1e-4:
                self._phase.pop(m, None)
                self._gain.pop(m, None)
                continue
            f = self._midi_hz(m)
            ph0 = self._phase.get(m, 0.0)
            w = 2 * np.pi * f / sr
            phase = ph0 + w * (idx + 1)
            # subtle detune for width: L slightly flat, R slightly sharp
            wl = 2 * np.pi * (f * 0.9985) / sr
            wr = 2 * np.pi * (f * 1.0015) / sr
            left = np.sin(ph0 + wl * (idx + 1)) + 0.3 * np.sin(2 * (ph0 + wl * (idx + 1)))
            right = np.sin(ph0 + wr * (idx + 1)) + 0.3 * np.sin(2 * (ph0 + wr * (idx + 1)))
            out[:, 0] += (env * left).astype(np.float32)
            out[:, 1] += (env * right).astype(np.float32)
            self._phase[m] = float((phase[-1]) % (2 * np.pi))
            self._gain[m] = float(env[-1])

        # Drums: kick on each beat, hat on the off-eighths, from bpm.
        if c["drums"] and not c["drumsMasked"]:
            bpm = max(40, min(200, int(c["bpm"])))
            beat_samples = sr * 60.0 / bpm
            gt = self._t + idx
            beat_pos = np.mod(gt, beat_samples) / beat_samples           # 0..1 within beat
            # kick: short decaying sine burst at the start of each beat
            kick_env = np.exp(-beat_pos * 18.0)
            kick = 0.5 * kick_env * np.sin(2 * np.pi * 60.0 * gt / sr)
            # hat: noise burst at the eighth-note midpoint
            eighth = np.mod(gt, beat_samples / 2.0) / (beat_samples / 2.0)
            hat_env = np.exp(-eighth * 60.0)
            rng = (np.sin(gt * 12.9898) * 43758.5453)
            noise = (rng - np.floor(rng)) * 2 - 1
            hat = 0.10 * hat_env * noise
            d = (kick + hat).astype(np.float32)
            out[:, 0] += d
            out[:, 1] += d

        self._t += n
        # soft clip for safety
        np.tanh(out, out=out)
        return out


# ----------------------------------------------------------------------------
# Real engine: Magenta RealTime 2 via MLX
# ----------------------------------------------------------------------------
class MlxEngine(BaseEngine):
    """Persistent Magenta RT2 (MLX) model, streamed by repeated generate().

    Uses MagentaRT2Mlxfn — the exported `.mlxfn` runtime that `mrt models
    download` fetches and that `mrt mlx generate` uses by default (quantization
    is baked into the .mlxfn, so there is no `bits` knob here). The C++-parity
    MLX engine is the real-time path on Apple Silicon.
    """

    name = "mlx"

    def __init__(self, size: str = "mrt2_small"):
        super().__init__()
        from magenta_rt import MagentaRT2Mlxfn  # heavy import; only when really used
        self.size = size
        self.mrt = MagentaRT2Mlxfn(size=size)   # loads .mlxfn + warms up MLX kernels
        self.state = None
        self._style_cache = {}        # text -> 768-dim np.ndarray
        self._embedding = None        # current blended StyleEmbedding
        self._prompts_dirty = True

    def reset(self):
        self.state = None

    def _on_control_changed(self, ctrl: dict):
        if "stylePrompts" in ctrl:
            with self._lock:           # set under the lock so the test-and-clear in
                self._prompts_dirty = True   # generate() can't drop a concurrent update

    def _embed_text(self, text: str) -> np.ndarray:
        emb = self._style_cache.get(text)
        if emb is None:
            emb = np.asarray(self.mrt.embed_style(text, use_mapper=True), dtype=np.float32)
            # cap the cache so a long jam session doesn't grow unbounded
            if len(self._style_cache) > 64:
                self._style_cache.clear()
            self._style_cache[text] = emb
        return emb

    def _recompute_embedding(self, prompts):
        embs, weights = [], []
        for p in prompts:
            text = (p.get("text") or "").strip()
            if not text:
                continue
            w = float(p.get("weight", 1.0))
            if w <= 0:
                continue
            embs.append(self._embed_text(text))
            weights.append(w)
        if not embs:
            self._embedding = None
            return
        wsum = sum(weights) or 1.0
        blended = sum(e * w for e, w in zip(embs, weights)) / wsum
        self._embedding = blended.astype(np.float32)

    def generate(self, frames: int) -> np.ndarray:
        # Test-and-clear the dirty flag atomically with the snapshot so a style
        # change arriving mid-generate is never silently dropped.
        with self._lock:
            dirty = self._prompts_dirty
            self._prompts_dirty = False
            c = dict(self._ctrl)
            c["cfg"] = dict(self._ctrl["cfg"])
            c["notesMidi"] = list(self._ctrl["notesMidi"])
            c["stylePrompts"] = [dict(p) for p in self._ctrl["stylePrompts"]]
        if dirty:
            self._recompute_embedding(c["stylePrompts"])

        notes = build_notes_vector(c["notesMidi"], c["noteOnset"], c["freeHarmony"])
        drums = [drums_value(c["drums"], c["drumsMasked"])]   # mlxfn wants a 1-element list
        cfg = c["cfg"]

        wav, self.state = self.mrt.generate(
            style=self._embedding,
            notes=notes,
            drums=drums,
            cfg_musiccoca=_clamp(float(cfg["musiccoca"]), CFG_MIN, CFG_MAX),
            cfg_notes=_clamp(float(cfg["notes"]), CFG_MIN, CFG_MAX),
            cfg_drums=_clamp(float(cfg["drums"]), CFG_MIN, CFG_MAX),
            temperature=_clamp(float(c["temperature"]), TEMP_MIN, TEMP_MAX),
            top_k=int(c["topK"]),
            frames=frames,
            state=self.state,
        )
        samples = np.asarray(wav.samples, dtype=np.float32)
        if samples.ndim == 1:
            samples = np.stack([samples, samples], axis=1)
        if samples.shape[1] != CHANNELS:
            samples = samples[:, :CHANNELS]
        return samples


def make_engine(prefer: str = "auto", size: str = "mrt2_small", bits=None):
    """Build the best available engine.

    prefer: 'auto' (real if weights present, else mock), 'mlx' (force real), 'mock' (force mock).
    `bits` is accepted for CLI compatibility but ignored (the .mlxfn is pre-quantized).
    Returns (engine, note: str).
    """
    if prefer == "mock":
        return MockEngine(), "forced mock engine (numpy synth)"
    try:
        eng = MlxEngine(size=size)
        return eng, f"Magenta RT2 MLX engine ({size}, exported .mlxfn)"
    except Exception as e:  # noqa: BLE001 — any import/load failure -> mock
        if prefer == "mlx":
            raise
        return MockEngine(), f"magenta-rt unavailable ({type(e).__name__}: {e}); using mock engine"
