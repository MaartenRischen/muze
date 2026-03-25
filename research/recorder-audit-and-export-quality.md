# MUZE Recorder Audit: Recording Quality, Export, and Mobile Sharing

**Date:** 2026-03-25
**Scope:** `Muze-sprint/js/ui.js` lines 1119-1321 (MUZE.Recorder)

---

## 1. Architecture Overview

The recorder has two modes:

- **STEREO** (default): Records a combined video+audio stream via `captureStream(30)` on a hidden 720px-wide canvas, muxed with the Tone.js master output via `createMediaStreamDestination()`.
- **MULTI**: Additionally records 4 separate audio stems (pad, arp, melody, drums) by tapping each channel's gain node into its own `MediaStreamDestination`.

The video includes a composited HUD overlay (mode name, valence bar, chord strip, debug telemetry, REC indicator) drawn each frame onto the recording canvas.

---

## 2. Audio Quality Assessment

### Current State

| Setting | Value | Verdict |
|---------|-------|---------|
| `audioBitsPerSecond` | **Not set** | Browser default (adaptive). Typically 128kbps Opus or ~128kbps AAC. |
| `audioBitrateMode` | **Not set** | Defaults to variable bitrate. |
| Audio codec priority | `audio/mp4` > `audio/webm;codecs=opus` > `audio/webm` | Good fallback chain. Safari gets AAC/MP4, Chrome gets Opus/WebM. |
| Sample rate | Inherits from `Tone.context` | Typically 44100 or 48000 Hz depending on device. Not explicitly controlled. |

### Problems

1. **No explicit audio bitrate.** The browser picks a default, which is usually around 128kbps. For a music app, this is noticeably lossy. Opus at 128kbps is decent but not studio quality; AAC at 128kbps is worse.

2. **Multitrack stems are lossy compressed.** The stem exports use the same `_audioMime()` (Opus or AAC). Stems should be lossless (WAV) so users can import them into a DAW without generational quality loss.

3. **No control over sample rate.** The `AudioContext` sample rate varies by device (44.1kHz on most, 48kHz on some). There is no normalization or documentation of what the user gets.

### Recommendations

- Set `audioBitsPerSecond: 256000` (256kbps) on the video MediaRecorder for high-quality audio in the combined recording.
- For multitrack stems, switch to WAV export via `ScriptProcessorNode`/`AudioWorklet` capture or `OfflineAudioContext` rendering (see section 6).
- Consider adding `audioBitrateMode: 'constant'` for predictable quality on the video export.

---

## 3. Video Codec and Quality Assessment

### Current State

| Setting | Value | Verdict |
|---------|-------|---------|
| Resolution | 720 x (aspect-ratio scaled) | Reasonable for social sharing. |
| Frame rate | `captureStream(30)` | 30fps is standard. |
| Codec priority | `video/mp4` > `video/webm;codecs=vp9,opus` > `video/webm` | Good. MP4 preferred (Safari), VP9 fallback (Chrome). |
| `videoBitsPerSecond` | 4,000,000 (4 Mbps) | Modest for 720p. Instagram recommends 5 Mbps; YouTube recommends 5-10 Mbps for 720p30. |

### Problems

1. **4 Mbps is on the low end for 720p video.** The canvas content (camera + overlay + HUD) has fine text and sharp edges that compress poorly at low bitrates. Artifacts will be visible around the debug text and chord bar.

2. **`captureStream()` drops frames in background tabs.** This is a known browser bug (Firefox especially, Chrome to a lesser extent). If a user switches tabs during recording, frames are lost.

3. **WebM format on Chrome is poorly supported on iOS.** When the video file is downloaded on a Chrome/Android device and shared to an iPhone user, it may not play. The MP4 path only works on Safari.

4. **No timecode/duration data until recording completes.** MediaRecorder WebM output often lacks proper duration metadata, causing some players to show "unknown duration."

### Recommendations

- Increase `videoBitsPerSecond` to `6_000_000` (6 Mbps) for sharper social media output.
- Consider the **WebCodecs API + mp4-muxer** approach for Chrome: this produces native MP4 (H.264 `avc1.42001f`) up to 10x faster than real-time, with consistent quality and no format conversion needed. Instagram/TikTok accept MP4 natively.
- Add a visibility change listener: warn the user or pause recording when the tab loses focus.
- For WebM output, run a fixup pass using `ts-ebml` or `fix-webm-duration` to inject proper duration metadata.

---

## 4. Multitrack Export Assessment

### Current State

The multitrack system taps into 4 channel gain nodes:

```
pad:   A._nodes.pad?.gain
arp:   A._nodes.arp?.gain
melody: A._nodes.melody?.gain
drums: kick.gain + snare.gain + hat.gain (merged)
```

Each tap goes through a `Tone.Gain(1)` into a `MediaStreamDestination`, then a separate `MediaRecorder`.

### Problems

1. **Tap point is pre-send.** The taps connect to each channel's `gain` node, which is post-EQ and post-panner but **before** the reverb/delay sends. This means the stems are dry-only. Users will get stems that sound different from the mixed output.

2. **No master bus stem.** There is no export of the wet reverb/delay return buses, so the spatial effects are lost entirely in multitrack mode.

3. **Race condition on stop.** The `stop()` method calls `_saveMultitrack()` when all pending track recorders fire `onstop`, but the main video recorder's `onstop` calls `_save()` independently. Both fire download prompts in parallel, which can overwhelm mobile browsers with 5 simultaneous downloads.

4. **No ZIP bundling.** Each stem downloads as a separate file. On mobile, this triggers 4-5 individual download prompts, which is a terrible UX. Desktop browsers may block the extra downloads as popups.

5. **Lossy format for stems.** As noted above, stems use Opus/AAC, not WAV.

### Recommendations

- Add a "wet" stem option that taps after the reverb/delay return buses, or add reverb/delay return as a 5th stem.
- Bundle all stems into a ZIP file using JSZip before triggering download.
- Switch stems to WAV export (see section 6).
- Add a brief delay between downloads, or use the File System Access API (`showSaveFilePicker`) for a single folder save.

---

## 5. Mobile Sharing Experience

### Current State

The `_save()` method uses the Web Share API with a files array:

```js
if (navigator.canShare && navigator.canShare({ files: [...] })) {
  await navigator.share({ files: [...], title: 'Muze Session' });
}
```

Falls back to `<a download>` click.

### Problems

1. **Web Share API file support is inconsistent.** Safari on iOS supports it well. Chrome on Android supports it. Chrome on iOS does NOT support `navigator.share()` with files. Firefox does not support it at all.

2. **Only the video gets the share sheet.** Multitrack stems bypass the share API entirely and go straight to download links. On mobile, there is no way to share stems to other apps.

3. **No share preview.** The share call includes a `title` but no `text` or `url`. Social apps benefit from descriptive text.

4. **WebM files cannot be shared to Instagram/TikTok.** These platforms require MP4. Chrome on Android produces WebM, so the share sheet opens but the target app rejects the file.

5. **File naming is timestamp-based.** `muze-1711360000000.webm` is not user-friendly for social sharing.

### Recommendations

- Add `text` to the share payload: `"Made with Muze - face-controlled music"`.
- Add a user-friendly filename: `muze-session-YYYY-MM-DD.mp4`.
- For Chrome/Android, convert WebM to MP4 client-side before sharing (using WebCodecs or ffmpeg.wasm).
- For multitrack, offer a "Share as ZIP" option using Web Share API with a zip file.
- Add fallback sharing: copy-to-clipboard for URLs, or show a QR code for cross-device transfer.

---

## 6. WAV / FLAC Export Path (Not Yet Implemented)

### How to Add WAV Export

**Approach A: Real-time capture via AudioWorklet**

Create an `AudioWorkletProcessor` that accumulates Float32Array buffers from each channel during recording. On stop, concatenate and encode to WAV by prepending a 44-byte RIFF header. Libraries: `wav-audio-encoder-js` or hand-rolled (it is only ~40 lines of code for PCM WAV).

Pros: Captures exactly what the user hears. Works with the existing real-time recording flow.
Cons: Large memory footprint for long recordings. A 5-minute stereo 48kHz recording is ~57 MB.

**Approach B: Offline rendering via OfflineAudioContext**

Reconstruct the audio graph in an `OfflineAudioContext`, replay the performance events, and render faster than real-time. Export the resulting `AudioBuffer` as WAV.

Pros: Can render at higher sample rates (96kHz). Deterministic output.
Cons: Requires serializing all performance events (notes, parameter changes, timing). Significant implementation effort. Cannot capture the camera/face-tracking driven parameter automation without recording those values.

**Approach C: Hybrid — record Float32 buffers, encode offline**

During real-time playback, capture raw PCM via AudioWorklet into a ring buffer or SharedArrayBuffer. On stop, encode to WAV/FLAC in a Web Worker.

Pros: Best of both worlds. Lossless capture of the actual performance. Encoding off the main thread.
Cons: Memory usage during recording. Need to handle worker communication.

### How to Add FLAC Export

Use `libflac.js` (Emscripten port of libFLAC). It supports streaming encode, so you can feed PCM chunks during recording and finalize on stop. FLAC files are ~60% the size of WAV with zero quality loss.

### Recommendation

**Approach C (hybrid) is best for MUZE.** During recording, capture raw PCM in an AudioWorklet. On stop, offer the user a choice:
- Quick share: compressed video+audio (current flow)
- High quality: WAV/FLAC stems (encoded in a Worker)
- Studio export: ZIP of WAV stems + mixed WAV

---

## 7. Offline Higher-Quality Rendering

### What OfflineAudioContext Could Do

- Render the mix at 96kHz / 32-bit float for mastering-grade output
- Apply dithering when downsampling to 16-bit for CD-quality WAV
- Re-render with higher-quality reverb/delay settings (longer tails, no compromises for real-time performance)

### Practical Limitations

- Cannot replay face-tracking automation without a recorded automation log
- Memory: a 5-minute 96kHz stereo render needs ~230 MB of RAM
- Blocks the main thread (OfflineAudioContext cannot run in a Worker as of 2026)
- Tone.js has known issues with OfflineAudioContext (transport scheduling quirks)

### Recommendation

This is a v2/v3 feature. For now, the AudioWorklet real-time capture approach (lossless PCM) gives 95% of the benefit at 10% of the implementation cost. If offline rendering is desired later, the first step is to log all automation data (face parameters, note events, chord changes) during playback so they can be replayed into an OfflineAudioContext.

---

## 8. Summary of Priority Fixes

| Priority | Issue | Fix | Effort |
|----------|-------|-----|--------|
| **P0** | No audio bitrate set | Add `audioBitsPerSecond: 256000` to video MediaRecorder | 1 line |
| **P0** | Video bitrate too low | Increase `videoBitsPerSecond` to `6_000_000` | 1 line |
| **P1** | Stems are lossy | Add WAV export via AudioWorklet PCM capture | Medium |
| **P1** | Multiple downloads on mobile | Bundle stems in ZIP (JSZip) | Small |
| **P1** | WebM unplayable on iOS | Investigate WebCodecs MP4 path for Chrome | Medium |
| **P2** | Dry-only stems | Add wet/reverb return as additional stem | Small |
| **P2** | No share text/metadata | Add descriptive text + friendly filename | Tiny |
| **P2** | Background tab frame drops | Add visibilitychange warning | Small |
| **P3** | No FLAC export | Integrate libflac.js | Medium |
| **P3** | No offline rendering | Log automation + OfflineAudioContext | Large |
| **P3** | WebM duration metadata | Use fix-webm-duration library | Small |

---

## Sources

- [MDN: MediaRecorder constructor](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/MediaRecorder)
- [MDN: MediaRecorder audioBitrateMode](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/audioBitrateMode)
- [MDN: OfflineAudioContext](https://developer.mozilla.org/en-US/docs/Web/API/OfflineAudioContext)
- [MDN: Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API)
- [MDN: HTMLCanvasElement.captureStream()](https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/captureStream)
- [Daniel Barta: Creating Audio on the Web Is Easy -- Until It's Time to Export](https://danielbarta.com/export-audio-on-the-web/)
- [web.dev: Web Share API](https://web.dev/articles/web-share)
- [Mux: The Skater Punk's Guide to MediaRecorder](https://www.mux.com/blog/how-to-use-mediarecorder)
- [DevTails: How to Save HTML Canvas to MP4 Using WebCodecs API](https://devtails.xyz/adam/how-to-save-html-canvas-to-mp4-using-web-codecs-api)
- [canvas-record (npm)](https://www.npmjs.com/package/canvas-record)
- [libflac.js (GitHub)](https://github.com/mmig/libflac.js/)
- [wav-audio-encoder-js (GitHub)](https://github.com/higuma/wav-audio-encoder-js)
- [waveform-playlist: Multitrack Web Audio editor](https://github.com/naomiaro/waveform-playlist)
- [W3C: captureStream() framerate issue](https://github.com/w3c/mediacapture-fromelement/issues/43)
- [Firefox bug: captureStream background tab](https://bugzilla.mozilla.org/show_bug.cgi?id=1344524)
- [Web Audio API performance notes](https://padenot.github.io/web-audio-perf/)
- [MDN: Web Audio API best practices](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Best_practices)
