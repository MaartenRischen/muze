"""
Muze ⇄ Magenta RealTime 2 streaming server.

A local WebSocket service that holds ONE persistent Magenta RT2 (MLX) model and
streams continuous 48 kHz stereo audio to the Muze web app, steered live by the
app's gesture / vibe / chord / scale state.

  * Client connects to  ws://<host>:<port>/ws
  * Client → server:  JSON control messages (style prompts, note pianoroll, drums, CFG…)
  * Server → client:  binary audio frames (see protocol.py)

Run:
    # real model (after `mrt models init && mrt models download mrt2_small`):
    python magenta_server.py --engine mlx --model mrt2_small --serve-web
    # no weights yet? the numpy mock proves the whole pipeline:
    python magenta_server.py --engine mock --serve-web

Then open  http://localhost:8010/  (with --serve-web) or your existing Muze URL,
and tap the 🧠 AI core button.
"""

import argparse
import asyncio
import json
import os
from concurrent.futures import ThreadPoolExecutor

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import protocol
from engines import make_engine

# ---- single shared model: only one generation may run at a time ----
EXECUTOR = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mrt-gen")

app = FastAPI(title="Muze · Magenta RT2 server")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

STATE = {
    "engine": None,
    "engine_note": "(not initialised)",
    "model": "-",
    "current_session": 0,   # newest connection wins (page reloads take over cleanly)
    "clients": 0,
}


class Session:
    """Per-connection mutable transport state (the engine holds the musical state)."""

    def __init__(self):
        self.frames = 2          # 40 ms * 2 = 80 ms per chunk (low latency, low loop overhead)
        self.transport = "stop"  # 'play' | 'stop'
        self._need_restart = True

    def apply(self, data: dict):
        if "frames" in data:
            try:
                self.frames = max(1, min(25, int(data["frames"])))
            except (TypeError, ValueError):
                pass
        if "transport" in data:
            t = data["transport"]
            if t in ("play", "stop"):
                if t == "play" and self.transport != "play":
                    self._need_restart = True
                self.transport = t

    def consume_restart(self) -> bool:
        r = self._need_restart
        self._need_restart = False
        return r


def normalize_control(data: dict) -> dict:
    """Pick out the engine-relevant fields from a raw control message."""
    out = {}
    for k in ("stylePrompts", "notesMidi", "noteOnset", "freeHarmony",
              "drums", "drumsMasked", "temperature", "topK", "bpm"):
        if k in data:
            out[k] = data[k]
    if "cfgWeights" in data and isinstance(data["cfgWeights"], dict):
        out["cfg"] = data["cfgWeights"]
    return out


async def _receiver(ws: WebSocket, engine, session: Session, sid: int):
    while sid == STATE["current_session"]:
        try:
            raw = await ws.receive_text()
        except WebSocketDisconnect:
            break
        except RuntimeError:
            break
        try:
            data = json.loads(raw)
        except (ValueError, TypeError):
            continue
        mtype = data.get("type")
        if mtype == "control":
            session.apply(data)
            ctrl = normalize_control(data)
            if ctrl:
                engine.update_control(ctrl)
        elif mtype == "ping":
            try:
                await ws.send_text(json.dumps({"type": "pong", "t": data.get("t")}))
            except RuntimeError:
                break
        elif mtype == "bye":
            break


async def _streamer(ws: WebSocket, engine, session: Session, sid: int):
    loop = asyncio.get_event_loop()
    seq = 0
    next_t = loop.time()
    while sid == STATE["current_session"]:
        if session.transport != "play":
            next_t = loop.time()
            await asyncio.sleep(0.03)
            continue
        frames = session.frames
        try:
            audio = await loop.run_in_executor(EXECUTOR, engine.generate, frames)
        except Exception as e:  # noqa: BLE001 — keep the socket alive, report once
            try:
                await ws.send_bytes(protocol.pack_error(seq, "generate_failed", str(e)))
            except (RuntimeError, WebSocketDisconnect):
                break
            await asyncio.sleep(0.2)
            continue
        flags = 1 if session.consume_restart() else 0
        try:
            await ws.send_bytes(protocol.pack_audio(seq, audio, engine.sample_rate, flags))
        except (RuntimeError, WebSocketDisconnect):
            break
        seq += 1
        next_t += frames * 0.04
        delay = next_t - loop.time()
        if delay > 0:
            await asyncio.sleep(delay)
        elif delay < -0.5:
            next_t = loop.time()   # fell far behind (slow first compile) -> rebase clock


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    engine = STATE["engine"]
    if engine is None:
        await ws.close(code=1011)
        return
    STATE["current_session"] += 1
    sid = STATE["current_session"]
    STATE["clients"] += 1
    loop = asyncio.get_event_loop()
    # Reset on the worker thread so it serialises behind any in-flight generate()
    # from a prior session (otherwise a takeover could resume from stale MLX state).
    await loop.run_in_executor(EXECUTOR, engine.reset)
    session = Session()
    try:
        # optional hello handshake (client may send one first); reply ready either way
        try:
            await ws.send_text(json.dumps({
                "type": "ready", "protocol": 1,
                "sampleRate": engine.sample_rate, "frameSamples": protocol.FRAME_SAMPLES,
                "channels": engine.channels, "engine": engine.name, "model": STATE["model"],
            }))
        except RuntimeError:
            return
        recv = asyncio.create_task(_receiver(ws, engine, session, sid))
        send = asyncio.create_task(_streamer(ws, engine, session, sid))
        done, pending = await asyncio.wait({recv, send}, return_when=asyncio.FIRST_COMPLETED)
        for t in pending:
            t.cancel()
        await asyncio.gather(*pending, return_exceptions=True)   # drain cancellations cleanly
    finally:
        STATE["clients"] = max(0, STATE["clients"] - 1)
        try:
            await ws.close()
        except RuntimeError:
            pass


@app.get("/status")
async def status():
    eng = STATE["engine"]
    return JSONResponse({
        "ok": eng is not None,
        "engine": eng.name if eng else None,
        "engine_note": STATE["engine_note"],
        "model": STATE["model"],
        "sampleRate": eng.sample_rate if eng else None,
        "clients": STATE["clients"],
    })


@app.get("/health")
async def health():
    return {"ok": STATE["engine"] is not None}


def build_app(args):
    # MLX GPU streams are thread-local: the model MUST be constructed on the same
    # (single) worker thread that later runs generate(), or MLX raises
    # "no Stream(gpu, N) in current thread". So build it inside EXECUTOR.
    engine, note = EXECUTOR.submit(make_engine, args.engine, args.model, args.bits).result()
    STATE["engine"] = engine
    STATE["engine_note"] = note
    STATE["model"] = args.model if engine.name == "mlx" else "(mock)"
    print(f"[muze-magenta] engine ready: {note}")

    if args.serve_web:
        from fastapi.staticfiles import StaticFiles
        web_dir = args.web_dir or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        # mounted LAST so the /ws and /status routes above take precedence
        app.mount("/", StaticFiles(directory=web_dir, html=True), name="web")
        print(f"[muze-magenta] serving Muze web app from {web_dir}")
    return app


def main():
    p = argparse.ArgumentParser(description="Muze · Magenta RT2 streaming server")
    p.add_argument("--engine", choices=["auto", "mlx", "mock"], default="auto",
                   help="auto = real model if available else mock")
    p.add_argument("--model", default="mrt2_small", choices=["mrt2_small", "mrt2_base"])
    p.add_argument("--bits", type=int, default=8, help="MLX quantization (4, 8, or 0=off)")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8010)
    p.add_argument("--serve-web", action="store_true",
                   help="also serve the Muze web app (one origin, one command)")
    p.add_argument("--web-dir", default=None, help="path to the Muze web root")
    args = p.parse_args()
    if args.bits == 0:
        args.bits = None

    import uvicorn
    build_app(args)
    print(f"[muze-magenta] listening on http://{args.host}:{args.port}  (ws: /ws)")
    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
