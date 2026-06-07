"""Real Magenta RT2 (MLX) smoke test via the production MlxEngine path."""
import time

import numpy as np

from engines import MlxEngine

t0 = time.time()
e = MlxEngine(size="mrt2_small")
print(f"[load] MlxEngine(mrt2_small, .mlxfn) ready in {time.time()-t0:.1f}s")

e.update_control({
    "stylePrompts": [{"text": "warm lo-fi hip hop, rhodes, vinyl crackle", "weight": 1.0},
                     {"text": "C minor key, slow, 80 bpm", "weight": 0.5}],
    "notesMidi": [48, 60, 63, 67], "noteOnset": True, "freeHarmony": False,
    "drums": True, "drumsMasked": False, "bpm": 80,
    "cfg": {"musiccoca": 4.0, "notes": 1.5, "drums": 2.0},
    "temperature": 1.2, "topK": 40,
})

t0 = time.time()
a = e.generate(2)   # 80 ms, includes first-call Metal warmup
warm = time.time() - t0
print(f"[warmup] first generate(2) -> {a.shape} {a.dtype} in {warm:.2f}s")

# steady-state: 25 chunks of 80 ms = 2.0 s of audio, threading state
N = 25
t0 = time.time()
last = None
for _ in range(N):
    last = e.generate(2)
dt = time.time() - t0
audio_s = N * 2 * 0.04
rms = float(np.sqrt(np.mean(last ** 2)))
print(f"[steady] generated {audio_s:.1f}s audio in {dt:.2f}s -> RTF={audio_s/dt:.2f} "
      f"(>1 = real-time) last_rms={rms:.4f}")
print("PASS" if (audio_s/dt) > 0.9 and rms > 1e-4 else "WARN: below real-time or silent")
