"""End-to-end protocol self-test against a running server (mock or mlx).

Connects, completes the handshake, sends a C-major chord + drums, then receives
and validates a handful of binary audio frames. Exits 0 on PASS.

    .venv/bin/python selftest.py ws://127.0.0.1:8011/ws
"""

import asyncio
import json
import struct
import sys

import numpy as np
import websockets

HEADER_FMT = "<4sBBBBIII"
HEADER_SIZE = struct.calcsize(HEADER_FMT)


async def run(url: str) -> int:
    ws = None
    for _ in range(60):
        try:
            ws = await websockets.connect(url, max_size=None)
            break
        except Exception:  # noqa: BLE001
            await asyncio.sleep(0.25)
    if ws is None:
        print("FAIL: could not connect to", url)
        return 1

    async with ws:
        ready = json.loads(await ws.recv())
        assert ready.get("type") == "ready", f"bad handshake: {ready}"
        assert ready["sampleRate"] == 48000, ready
        assert ready["channels"] == 2, ready
        print("ready:", ready)

        await ws.send(json.dumps({
            "type": "control", "seq": 1, "transport": "play", "frames": 2,
            "stylePrompts": [{"text": "warm analog pad, lo-fi", "weight": 1.0}],
            "notesMidi": [60, 64, 67], "noteOnset": True, "freeHarmony": False,
            "drums": True, "drumsMasked": False, "bpm": 100,
            "cfgWeights": {"musiccoca": 3.0, "notes": 1.0, "drums": 1.0},
            "temperature": 1.2, "topK": 40,
        }))

        got, energy, seqs = 0, 0.0, []
        while got < 12:
            msg = await asyncio.wait_for(ws.recv(), timeout=20)
            if isinstance(msg, str):
                continue  # pong/status
            magic, mtype, ch, fmt, flags, seq, srate, frames = struct.unpack(
                HEADER_FMT, msg[:HEADER_SIZE])
            assert magic == b"MZA1", f"bad magic {magic!r}"
            if mtype == 2:
                print("server error frame:", msg[HEADER_SIZE:].decode("utf-8", "replace"))
                return 1
            if mtype != 0:
                continue
            assert ch == 2 and srate == 48000, (ch, srate)
            body = msg[HEADER_SIZE:]
            bps = 2 if fmt == 0 else 4
            assert len(body) == frames * ch * bps, (len(body), frames, ch, bps)
            pcm = (np.frombuffer(body, dtype="<i2").astype(np.float32) / 32768.0
                   if fmt == 0 else np.frombuffer(body, dtype="<f4"))
            energy += float(np.mean(pcm ** 2))
            seqs.append(seq)
            got += 1

        mono = energy / got
        contiguous = seqs == list(range(seqs[0], seqs[0] + len(seqs)))
        print(f"received {got} audio frames seq={seqs[0]}..{seqs[-1]} "
              f"contiguous={contiguous} mean_energy={mono:.6f}")
        assert contiguous, f"non-contiguous seq: {seqs}"
        assert mono > 1e-6, "silence — engine produced no audio for a held chord"
        print("PASS")
        return 0


if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "ws://127.0.0.1:8011/ws"
    sys.exit(asyncio.run(run(url)))
