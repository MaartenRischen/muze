# MUZE Tracking Audit: MediaPipe Face & Hand Detection

**Date:** 2026-03-25
**Files reviewed:**
- `Muze-sprint/js/tracking.js` (Camera, FaceTracker, HandTracker, FaceFeatures, HandFeatures)
- `Muze-sprint/js/app.js` (detection loop in MUZE.Loop._tick)
- `Muze-sprint/js/config.js` (smoothing params, thresholds, state)
- `Muze-sprint/js/audio.js` (updateParams — face-to-audio mapping)

---

## 1. DETECTION FREQUENCY

**Current:** `DETECT_INTERVAL: 33` ms (~30 fps), camera requested at `frameRate: { ideal: 30 }`.

**Verdict: Mostly correct, but blocking.**

The 33 ms interval matches the 30 fps camera, which is good — no point detecting faster than frames arrive. However, both `FaceTracker.detect()` and `HandTracker.detect()` run **synchronously and sequentially** within the same `requestAnimationFrame` callback:

```
const fr = MUZE.FaceTracker.detect(video, ts);       // ~8-15ms on GPU
// ... process face ...
const hr = MUZE.HandTracker.detect(video, ts + 1);   // ~10-18ms on GPU
```

On a mid-tier mobile device, face detection takes 8-15 ms and hand detection takes 10-18 ms. Combined, that is 18-33 ms — consuming nearly the entire 33 ms frame budget and leaving almost nothing for rendering, audio, and DOM updates. This causes **frame drops and audio glitches on weaker devices**.

**Recommendations:**
- **Alternate detections:** Run face on even frames, hand on odd frames. Each frame then costs only one model inference (~12 ms), leaving ~20 ms for everything else. At 30 fps this means each tracker still runs at 15 fps — more than adequate for musical expression.
- **Or stagger with a half-frame offset:** Face at t=0, hand at t=16ms, face at t=33ms, etc. This distributes GPU load more evenly.
- **Consider dropping to 20 fps detection** (`DETECT_INTERVAL: 50`) on devices where `navigator.hardwareConcurrency < 4` or where the GPU delegate falls back to CPU. The smoothing filter will interpolate between readings, and 20 Hz is still well above the ~5-8 Hz threshold where humans perceive parameter lag in musical contexts.

---

## 2. SMOOTHING FILTER

**Current implementation:** Simple exponential moving average (EMA):

```js
MUZE.Smooth = {
  update(key, raw, alpha) {
    if (!(key in this._prev)) { this._prev[key] = raw; return raw; }
    const s = alpha * raw + (1 - alpha) * this._prev[key];
    this._prev[key] = s; return s;
  }
};
```

**Config values:**
- `SMOOTH_FAST: 0.35` — mouth, lip, brow, eye, headPitch
- `SMOOTH_SLOW: 0.15` — mouthWidth, headYaw, headRoll
- `SMOOTH_HAND: 0.30` — handX, handY

**Problems identified:**

### 2a. Fixed alpha cannot solve the jitter-vs-lag tradeoff

A fixed EMA alpha is a compromise: low alpha = less jitter but more lag; high alpha = responsive but jittery. The current values (`0.35` for fast, `0.15` for slow) are reasonable starting points but create a **permanent ~2-3 frame lag** on fast gestures (mouth opening quickly for a filter sweep) and **visible jitter** when holding still (especially brow and eye, which have small pixel ranges).

**Recommendation: Replace with the 1-Euro Filter.** This is the standard solution in gesture-controlled instruments (used by Apple ARKit, Meta Quest hand tracking, and academic NIME instruments). It adapts the cutoff frequency based on signal velocity:
- When the user is still, cutoff drops low and jitter vanishes
- When the user moves fast, cutoff rises and lag disappears

Suggested parameters for musical control:
| Signal | minCutoff | beta | dcutoff |
|---|---|---|---|
| mouthOpenness | 1.0 | 0.007 | 1.0 |
| lipCorner | 1.5 | 0.004 | 1.0 |
| browHeight | 0.8 | 0.004 | 1.0 |
| eyeOpenness | 0.8 | 0.003 | 1.0 |
| headPitch | 1.0 | 0.007 | 1.0 |
| headYaw/Roll | 0.5 | 0.004 | 1.0 |
| handX/Y | 1.5 | 0.01 | 1.0 |

A JavaScript 1-Euro filter is ~30 lines of code and adds zero measurable overhead. Reference implementation: https://gery.casiez.net/1euro/ or npm package `1eurofilter`.

### 2b. Smoothing is time-unaware

The current EMA applies the same alpha regardless of how much time passed between samples. If a frame is dropped (detection takes too long), the next sample gets the same weight as if it arrived on time. The 1-Euro filter solves this automatically because it computes derivatives using actual timestamps.

### 2c. Hand smoothing should be higher

`SMOOTH_HAND: 0.30` makes hand position jittery when used for melody pitch. The hand landmark model has higher variance than face landmarks because the palm can partially occlude fingers. A value of `0.20-0.25` (more smoothing) would reduce melodic jitter, or better yet, the 1-Euro filter with a lower minCutoff for hand Y (melody pitch) than hand X.

---

## 3. FACE FEATURE EXTRACTION

### 3a. What is extracted (and mapped to audio)

| Feature | Extracted | Mapped to audio | Notes |
|---|---|---|---|
| mouthOpenness | Yes | Arp filter cutoff | Good |
| lipCorner (smile) | Yes | Scale/mode selection (valence) | Good |
| browHeight | Yes | Octave shift | Good, but see 3c |
| eyeOpenness | Yes | Reverb/delay send amount | Good |
| mouthWidth | Yes | **Nothing** | Wasted computation |
| headPitch | Yes | Master filter frequency | Good |
| headYaw | Yes | **Nothing** (only debug display) | Wasted computation |
| headRoll | Yes | Chorus depth on pad | Good |

**Two features are extracted but never used musically: `mouthWidth` and `headYaw`.**

### 3b. Missing features that should be extracted

**Tongue out detection (landmark 14 z-depth):** The lower lip landmark's z-coordinate moves forward significantly when the tongue is extended. This is a reliable, fun gesture that could trigger an effect (filter wobble, glitch, tape stop).

**Cheek puff (landmarks 205, 425):** Detectable from the lateral cheek landmarks moving outward. Could control sub-bass intensity or a "swell" effect.

**Lip pucker/kiss (lips close together + protrude in z):** Already partially captured by mouthWidth decreasing, but adding z-depth of lip landmarks makes it more robust. Natural mapping: vibrato depth.

**Jaw lateral movement:** Detectable from chin landmark (152) x-offset relative to nose bridge. Uncommon movement = good for a "special" trigger.

### 3c. Brow detection range is too narrow

```
BROW_MIN: 0.100, BROW_MAX: 0.143
```

This is a range of only 0.043 in normalized face-height units. For many users (especially those with heavier brow ridges or who wear glasses), the resting brow position already sits near or above 0.143. This means browHeight saturates at 1.0 for some users and never reaches 0 for others.

**Recommendation:** Implement auto-calibration during the first 3-5 seconds of face detection. Record the min and max brow position observed, then use those as the remap range. Store in `MUZE.State._browCalibMin/Max`. This is standard practice in face-controlled instruments (see NIME proceedings on facial instrument calibration).

### 3d. Lip corner (smile/frown) range is extremely narrow

```
LIP_SMILE_MIN: -0.025, LIP_SMILE_MAX: 0.025
```

Total range of 0.05. This makes the valence system hyper-sensitive — tiny involuntary lip movements cause mode changes. Combined with `SMOOTH_FAST: 0.35` this creates a nervous, flickery mode selection.

**Recommendations:**
- Widen to at least `LIP_SMILE_MIN: -0.04, LIP_SMILE_MAX: 0.04`
- Use `SMOOTH_SLOW` (0.15) instead of `SMOOTH_FAST` for lipCorner — mode changes should be deliberate, not twitchy
- Add hysteresis: require the valence to cross a threshold by some margin before switching modes, and don't switch back until it crosses back by the same margin

### 3e. Eye openness range may be too narrow for some users

```
EYE_OPEN_MIN: 0.012, EYE_OPEN_MAX: 0.055
```

Range of 0.043. People with monolid eyes or heavy eyelids may have a resting ratio near 0.012, making the feature useless for them. Auto-calibration (same as brow) would fix this.

### 3f. Blendshapes are disabled but would be more robust

The face tracker is configured with:
```
outputFaceBlendshapes: false,
outputFacialTransformationMatrixes: false
```

MediaPipe's 52 blendshape coefficients provide pre-computed, normalized values for expressions like `mouthSmileLeft`, `mouthSmileRight`, `browInnerUp`, `eyeBlinkLeft`, `jawOpen`, etc. These are:
- **Already calibrated** per-face (no need for manual min/max tuning)
- **More robust** than raw landmark distances (they account for face shape variation)
- **Cheaper to process** downstream (52 floats vs 478 3D landmarks)

The performance cost of enabling blendshapes is modest (~2-3 ms extra on GPU). Given that the current manual landmark-distance calculations are fragile and uncalibrated, **enabling blendshapes would be a significant quality improvement**.

Relevant blendshapes for MUZE:
| Blendshape | Maps to |
|---|---|
| jawOpen | mouthOpenness (replaces manual calc) |
| mouthSmileLeft + mouthSmileRight | lipCorner / valence |
| browInnerUp, browOuterUpLeft/Right | browHeight |
| eyeBlinkLeft + eyeBlinkRight | eyeOpenness (inverted) |
| mouthPucker | New: vibrato control |
| cheekPuff | New: sub swell |
| tongueOut | New: effect trigger |
| jawLeft / jawRight | New: stereo pan or pitch bend |

---

## 4. HAND TRACKING

### 4a. Only 1 hand tracked

`numHands: 1` is correct for the current architecture where one hand controls melody pitch. However, tracking 2 hands would enable:
- Left hand = melody pitch (Y), right hand = effects/volume (Y) or vice versa
- Two-hand spread = parameter (e.g., stereo width)
- Both hands fist = mute/pause gesture

The cost of `numHands: 2` is roughly 1.5x the single-hand cost (the palm detector runs once, but landmark regression runs twice). If alternating face/hand frames (recommendation from section 1), the budget is there.

### 4b. Hand openness threshold is a single magic number

```
handOpen: (avgFingerDist / palmSize) > 1.7
```

This binary open/closed detection is fragile:
- The threshold 1.7 was likely tuned on one hand size/camera distance
- It flickers at the boundary (no hysteresis)
- It discards the continuous value, which could control a parameter

**Recommendations:**
- Return the continuous `avgFingerDist / palmSize` ratio as `handSpread` (0-1 normalized)
- Map handSpread to a musical parameter (e.g., melody velocity, vibrato amount, filter resonance)
- For the binary open/closed, add hysteresis: open when ratio > 1.8, closed when ratio < 1.5

### 4c. Missing hand gestures

The current extraction computes only: position (X, Y), open/closed. There are many more gestures detectable from the 21 hand landmarks:

| Gesture | How to detect | Musical use |
|---|---|---|
| Pinch (thumb-index) | dist(lm[4], lm[8]) < palmSize * 0.3 | Fine pitch control, parameter tweak |
| Point (index extended, others curled) | lm[8].y < lm[6].y AND lm[12].y > lm[10].y | Trigger single notes, select |
| Peace / V sign | index + middle extended | Switch between melody modes |
| Thumbs up | lm[4].y < lm[3].y AND all fingers curled | Confirm / lock current scale |
| Wrist rotation (supination/pronation) | Compare palm normal vector z-component | Continuous: filter/pan |
| Hand velocity | delta of handX/handY between frames | Expressive dynamics, strum speed |
| Finger spread | max distance between adjacent fingertips | Continuous: reverb or chorus width |
| Finger wiggle | high-frequency oscillation of individual fingertip Y | Tremolo/vibrato rate |

### 4d. Hand detection confidence is conservative

```
minHandDetectionConfidence: 0.5,
minTrackingConfidence: 0.5
```

These defaults cause the tracker to re-run the expensive palm detection model frequently, because it loses tracking confidence easily (partial occlusion, quick movements). For a musical context where false positives are less costly than dropped tracking:

**Recommendation:** Lower `minTrackingConfidence` to `0.3` to maintain tracking through fast movements. Keep `minHandDetectionConfidence` at `0.5` to avoid phantom hand detection.

### 4e. HandX is extracted, smoothed, but never used musically

`S.handX` is computed and smoothed but only `S.handY` drives melody pitch. HandX should map to something — stereo pan of the melody, or a second musical dimension (e.g., timbre/filter cutoff on the melody synth).

---

## 5. DETECTION LOOP ARCHITECTURE ISSUES

### 5a. Timestamp hack

```js
const hr = MUZE.HandTracker.detect(video, ts + 1);
```

The `ts + 1` is a workaround because MediaPipe rejects duplicate timestamps. But this means the hand tracker processes a timestamp that doesn't match the actual video frame time. While unlikely to cause visible issues (it's only 1ms off), the correct solution is to use separate timestamp counters or to only call one tracker per frame (alternating).

### 5b. Face loss recovery is instant

When face detection returns no landmarks, `S.faceDetected` immediately becomes `false`, which causes the entire audio logic to stop (pads release, melody stops). This is jarring during momentary tracking loss (looking away briefly, hand crossing face, lighting change).

**Recommendation:** Add a grace period of 300-500 ms before declaring face lost:
```js
if (fr && fr.faceLandmarks && fr.faceLandmarks.length > 0) {
  S._lastFaceSeen = now;
  S.faceDetected = true;
  // ... extract features
} else if (now - S._lastFaceSeen > 400) {
  S.faceDetected = false;
}
```

### 5c. No frame skipping under load

If detection takes longer than `DETECT_INTERVAL`, the code simply runs detection on the next `requestAnimationFrame`. But it doesn't know it's behind — it just checks `now - this._lastDetect >= C.DETECT_INTERVAL`. This is fine, but there's no mechanism to **skip hand detection** when the frame is already behind budget. A simple addition:

```js
const detectStart = performance.now();
// ... face detection ...
if (performance.now() - detectStart < 20) {
  // Only run hand detection if we have budget left
  const hr = MUZE.HandTracker.detect(video, ts + 1);
}
```

---

## 6. HOW OTHER CAMERA-BASED INSTRUMENTS SOLVE JITTER/LATENCY

### Academic instruments (NIME proceedings)

- **1-Euro Filter** is the de facto standard. Originally published at CHI 2012 by Casiez, Roussel & Vogel, adopted by virtually every gesture-instrument since 2015.
- **Per-user calibration** at startup (5-10 seconds of guided min/max expressions) is used by EyeHarp, Sonify Your Face, and similar. MUZE does none of this.
- **Velocity gating:** Ignore parameter changes below a velocity threshold (derivative < epsilon). This eliminates micro-jitter without adding lag to intentional movements.
- **Hysteresis bands** on discrete state transitions (scale changes, gesture recognition) prevent flickering.

### Commercial products

- **ROLI Airwave** uses infrared cameras + their own hand tracking. Key insight: they separate "coarse gesture" (which note/chord) from "fine expression" (velocity, aftertouch) and apply different smoothing to each.
- **Imogen Heap's Mi.Mu Gloves** (sensor-based, not camera) use a **Kalman filter** for position and a **debounced state machine** for gestures. The state machine requires a gesture to be held for 2+ consecutive frames before triggering.
- **Virtual Theremin** implementations use **cubic interpolation** between detection points rather than linear EMA, giving smoother curves for pitch control.

### Key principles from the literature

1. **Separate detection rate from control rate.** Detect at camera framerate, but output smoothed parameters at audio rate (or at least at a fixed high rate using interpolation between detection samples).
2. **Never map raw detection output directly to audio.** Always smooth, always calibrate.
3. **Use dead zones** around neutral positions. A user's "resting face" is never perfectly still — define a zone around the calibrated neutral where the output is pinned to the neutral value.
4. **Lighting matters more than code.** Two desk lamps improve tracking more than any algorithmic optimization. Consider adding a "lighting quality" indicator in the UI.

---

## 7. SUMMARY OF PRIORITIZED RECOMMENDATIONS

### High Priority (biggest impact, lowest effort)

1. **Alternate face/hand detection** across frames — halves per-frame GPU cost
2. **Replace EMA with 1-Euro Filter** — eliminates the jitter-vs-lag tradeoff
3. **Enable blendshapes** (`outputFaceBlendshapes: true`) — more robust expression detection, pre-calibrated
4. **Add face loss grace period** (400ms) — eliminates jarring audio drops
5. **Lower `minTrackingConfidence` to 0.3** — maintains hand tracking through fast movements

### Medium Priority (significant improvement, moderate effort)

6. **Auto-calibrate brow and eye ranges** at startup — fixes per-user variation
7. **Widen lip corner range** and switch to SMOOTH_SLOW — stops nervous mode flickering
8. **Map handX to melody pan or timbre** — use the data you're already computing
9. **Map mouthWidth to a parameter** (delay feedback, pad detuning) — use the data you're already computing
10. **Map headYaw to stereo panning** of the master or arp — use the data you're already computing
11. **Add hysteresis to hand open/closed** — eliminates flickering at boundary

### Lower Priority (nice to have, more effort)

12. **Add pinch gesture detection** — enables fine control mode
13. **Add hand velocity** — enables expressive dynamics
14. **Return continuous hand spread** value — enables another expression dimension
15. **Add wrist rotation detection** — enables filter/pan sweep
16. **Track 2 hands** — enables dual-hand control paradigm
17. **Add per-user calibration wizard** (guided "raise eyebrows, smile wide, open mouth" sequence)
18. **Add lighting quality indicator** — helps users optimize their setup
19. **Detect tongue-out via blendshape** — fun trigger gesture
