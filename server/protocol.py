"""
Muze ⇄ Magenta wire protocol.

Server → Client: binary WebSocket frames. Each frame is one generate() chunk.

  HEADER (20 bytes, little-endian, no padding):
    bytes 0-3   : magic  b"MZA1"
    byte  4     : msgType  uint8   (0 = audio PCM, 1 = keepalive/silence, 2 = error JSON)
    byte  5     : channels uint8   (2)
    byte  6     : sampleFmt uint8  (0 = int16, 1 = float32)   -- default int16 (half the bandwidth)
    byte  7     : flags    uint8   (bit0 = stream (re)start -> client arms a fade-in)
    bytes 8-11  : seq      uint32  (monotonic chunk counter; a gap == packet loss)
    bytes 12-15 : sampleRate uint32 (48000)
    bytes 16-19 : frameCount uint32 (samples PER CHANNEL in this chunk)
  PAYLOAD:
    interleaved PCM  L,R,L,R...   length = frameCount * channels * bytesPerSample
    (int16: 2 bytes/sample, float32: 4 bytes/sample)

Client → Server: text/JSON control messages (see magenta_server.py / js/magenta-rt.js).

The format is deliberately tiny and fixed-offset so the browser can parse it with a
single DataView and a zero-copy Float32Array/Int16Array view — never decodeAudioData
(these are bare LPCM samples, not a container).
"""

import struct

import numpy as np

MAGIC = b"MZA1"
HEADER_FMT = "<4sBBBBIII"          # magic, msgType, channels, sampleFmt, flags, seq, sampleRate, frameCount
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # == 20

MSG_AUDIO = 0
MSG_KEEPALIVE = 1
MSG_ERROR = 2

FMT_INT16 = 0
FMT_FLOAT32 = 1

SAMPLE_RATE = 48000        # Magenta RT2 native: 48 kHz stereo
CHANNELS = 2
FRAME_SAMPLES = 1920       # one 40 ms model frame @ 48 kHz


def pack_audio(seq: int, audio: np.ndarray, sample_rate: int = SAMPLE_RATE,
               flags: int = 0, sample_fmt: int = FMT_INT16) -> bytes:
    """Pack a (frames, 2) float32 [-1, 1] block into a wire frame.

    audio: np.ndarray shape (N, 2) float32. N = frames * 1920 (per channel).
    """
    if audio.ndim != 2 or audio.shape[1] != CHANNELS:
        raise ValueError(f"audio must be (N, {CHANNELS}), got {audio.shape}")
    frame_count = audio.shape[0]
    inter = np.clip(audio, -1.0, 1.0).reshape(-1)   # (N,2) C-order -> L0,R0,L1,R1,...
    if sample_fmt == FMT_INT16:
        body = (inter * 32767.0).astype("<i2").tobytes()
    else:
        body = inter.astype("<f4").tobytes()
    header = struct.pack(HEADER_FMT, MAGIC, MSG_AUDIO, CHANNELS, sample_fmt,
                         flags & 0xFF, seq & 0xFFFFFFFF, sample_rate, frame_count)
    return header + body


def pack_keepalive(seq: int) -> bytes:
    return struct.pack(HEADER_FMT, MAGIC, MSG_KEEPALIVE, CHANNELS, FMT_INT16,
                       0, seq & 0xFFFFFFFF, SAMPLE_RATE, 0)


def pack_error(seq: int, code: str, message: str) -> bytes:
    import json
    body = json.dumps({"code": code, "message": message}).encode("utf-8")
    header = struct.pack(HEADER_FMT, MAGIC, MSG_ERROR, CHANNELS, FMT_INT16,
                         0, seq & 0xFFFFFFFF, SAMPLE_RATE, 0)
    return header + body
