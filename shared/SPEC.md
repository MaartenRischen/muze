# Jammerman — Shared Logic Specification

This document formally defines all platform-agnostic algorithms shared between the iOS and web implementations. Both platforms MUST produce identical results for identical inputs. Cross-platform correctness is enforced via shared test vectors in `test-vectors/`.

---

## 1. Scales

### 1.1 Modal Scales (face-controlled via lip corner / valence)

| Name | Intervals |
|------|-----------|
| Lydian | [0, 2, 4, 6, 7, 9, 11] |
| Ionian | [0, 2, 4, 5, 7, 9, 11] |
| Mixolydian | [0, 2, 4, 5, 7, 9, 10] |
| Dorian | [0, 2, 3, 5, 7, 9, 10] |
| Aeolian | [0, 2, 3, 5, 7, 8, 10] |
| Phrygian | [0, 1, 3, 5, 7, 8, 10] |

Ordered from brightest (Lydian, high valence) to darkest (Phrygian, low valence).

### 1.2 Extended Scales (user-selectable via UI)

| Name | Intervals |
|------|-----------|
| pent. major | [0, 2, 4, 7, 9] |
| pent. minor | [0, 3, 5, 7, 10] |
| harm. minor | [0, 2, 3, 5, 7, 8, 11] |
| whole tone | [0, 2, 4, 6, 8, 10] |
| blues | [0, 3, 5, 6, 7, 10] |
| melodic minor | [0, 2, 3, 5, 7, 9, 11] |
| phrygian dom | [0, 1, 4, 5, 7, 8, 10] |
| hirajoshi | [0, 2, 3, 7, 8] |

---

## 2. Scale Selection

```
function selectScale(lipCorner: float, extraScaleMode: string | null) -> int[]
```

If `extraScaleMode` is set (non-null), return the corresponding extended scale. Otherwise, select based on `lipCorner` value:

| Condition | Scale |
|-----------|-------|
| lipCorner > 0.80 | Lydian |
| lipCorner > 0.60 | Ionian |
| lipCorner > 0.40 | Mixolydian |
| lipCorner > 0.20 | Dorian |
| lipCorner > 0.00 | Aeolian |
| lipCorner <= 0.00 | Phrygian |

Fallback if `extraScaleMode` name not found: Dorian.

---

## 3. Note Quantization

```
function quantize(value: float [0..1], scale: int[], root: int (MIDI), octaveRange: int) -> int (MIDI)
```

Algorithm:
1. `total = scale.length * octaveRange`
2. `idx = clamp(round(value * (total - 1)), 0, total - 1)`
3. Return `root + floor(idx / scale.length) * 12 + scale[idx % scale.length]`

---

## 4. MIDI to Note Name

```
function midiToNote(midi: int) -> string
```

- Note names: `['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']`
- `noteName = NOTE_NAMES[midi % 12]`
- `octave = floor(midi / 12) - 1`
- Return `noteName + octave`

---

## 5. Pad Voicing

```
function getPadVoicing(root: int (MIDI), scale: int[], degree: int) -> string[4]
```

Open 4-note voicing:
1. `d = degree % scale.length`
2. `root_note = root + scale[d]`
3. `third = root + scale[(d + 2) % scale.length]`
4. `fifth = root + scale[(d + 4) % scale.length]`
5. `seventh = root + scale[(d + 6) % scale.length]`
6. Return `[midiToNote(root_note - 12), midiToNote(third), midiToNote(fifth), midiToNote(seventh)]`

---

## 6. Arp Notes

```
function getArpNotes(scale: int[], root: int (MIDI), degree: int, octaveRange: int) -> string[]
```

1. `d = degree % scale.length`
2. `chordTones = [scale[d], scale[(d+2) % len], scale[(d+4) % len], scale[(d+6) % len]]`
3. For each octave 0..octaveRange-1, for each chordTone interval:
   - Push `midiToNote(root + octave * 12 + interval)`
4. Return collected notes

---

## 7. Snap to Scale

```
function snapToScale(midiNote: int, scale: int[], root: int (MIDI)) -> int (MIDI)
```

Find the closest note in the scale across octaves -1..8:
- For each octave, for each interval in scale:
  - `candidate = root + octave * 12 + interval`
  - Track minimum `|candidate - midiNote|`
- Return closest candidate

---

## 8. Euclidean Rhythm (Bjorklund's Algorithm)

```
function euclidean(pulses: int, steps: int) -> int[]
```

- If `pulses >= steps`: return array of `steps` ones
- If `pulses <= 0`: return array of `steps` zeros
- Otherwise, apply Bjorklund's algorithm:
  1. `counts = pulses arrays of [1]`
  2. `remainders = (steps - pulses) arrays of [0]`
  3. While `remainders.length > 1`:
     - Pair each count with a remainder (zip shortest)
     - Excess counts or remainders become the new remainders
  4. Flatten all arrays

---

## 9. One-Euro Filter (Adaptive Smoothing)

```
class OneEuroFilter(freq, minCutoff, beta, dCutoff)
```

### Constructor parameters:
- `freq`: Expected sample rate (Hz), default 60
- `minCutoff`: Minimum cutoff frequency, default 1.0
- `beta`: Speed coefficient (higher = less lag during fast movement), default 0.0
- `dCutoff`: Cutoff for derivative filter, default 1.0

### State:
- `x`: Previous filtered value (null initially)
- `dx`: Previous filtered derivative (0 initially)
- `lastTime`: Previous timestamp (null initially)

### filter(x, timestamp) -> float:
1. If first call (`x` is null): set `x = input`, `lastTime = timestamp`, return input
2. `dt = (timestamp - lastTime) / 1000` (seconds). If `dt <= 0`, use `1/freq`
3. `dx_raw = (x - prev_x) / dt`
4. `dx_filtered = alpha(dt, dCutoff) * dx_raw + (1 - alpha(dt, dCutoff)) * prev_dx`
5. `cutoff = minCutoff + beta * |dx_filtered|`
6. `x_filtered = alpha(dt, cutoff) * x + (1 - alpha(dt, cutoff)) * prev_x`
7. Update state, return `x_filtered`

### alpha(dt, cutoff) -> float:
- `tau = 1 / (2 * PI * cutoff)`
- Return `1 / (1 + tau / dt)`

---

## 10. Face Feature Extraction

### Input
Array of face landmarks, each `{x, y, z}` in normalized coordinates [0..1].

### MediaPipe Landmark Indices
| Feature | Index |
|---------|-------|
| UPPER_LIP | 13 |
| LOWER_LIP | 14 |
| LEFT_MOUTH | 61 |
| RIGHT_MOUTH | 291 |
| R_EYE_TOP | 159 |
| R_EYE_BOT | 145 |
| L_EYE_TOP | 386 |
| L_EYE_BOT | 374 |
| R_BROW | 105 |
| L_BROW | 334 |
| NOSE_TIP | 1 |
| FOREHEAD | 10 |
| CHIN | 152 |
| L_EAR | 234 |
| R_EAR | 454 |

> **iOS Note:** Apple Vision framework uses different landmark indices. Create a mapping layer that translates Vision landmark points to the same semantic features listed above.

### Normalization Constants
| Parameter | Min | Max |
|-----------|-----|-----|
| Mouth openness | 0.015 | 0.09 |
| Lip smile | -0.045 | 0.045 |
| Brow height | 0.100 | 0.143 |
| Eye openness | 0.012 | 0.055 |
| Mouth width | 0.28 | 0.38 |

### Extraction Algorithm

All distances normalized by `faceHeight = dist3d(FOREHEAD, CHIN)`. Bail out if faceHeight < 0.001.

1. **mouthOpenness** [0..1]: `clamp01(remap(dist3d(UPPER_LIP, LOWER_LIP) / faceHeight, 0.015, 0.09))`
2. **lipCorner** [-1..1]: `clamp(remap(avg_corner_lift / faceHeight, -0.045, 0.045), -1, 1)` where `avg_corner_lift = avg of (midMouthY - leftMouth.y) and (midMouthY - rightMouth.y)`, `midMouthY = avg of UPPER_LIP.y and LOWER_LIP.y`
3. **browHeight** [0..1]: `clamp01(remap(avg_brow_dist / faceHeight, 0.100, 0.143))` where `avg_brow_dist = avg of |R_BROW.y - R_EYE_TOP.y| and |L_BROW.y - L_EYE_TOP.y|`
4. **eyeOpenness** [0..1]: `clamp01(remap(avg_eye_dist / faceHeight, 0.012, 0.055))` where `avg_eye_dist = avg of dist3d(R_EYE_TOP, R_EYE_BOT) and dist3d(L_EYE_TOP, L_EYE_BOT)`
5. **mouthWidth** [0..1]: `clamp01(remap(dist2d(LEFT_MOUTH, RIGHT_MOUTH) / faceHeight, 0.28, 0.38))`
6. **headYaw** [radians]: `atan2(dist2d(NOSE_TIP, L_EAR) - dist2d(NOSE_TIP, R_EAR), faceHeight)`
7. **headPitch** [radians]: `(NOSE_TIP.y - avg(FOREHEAD.y, CHIN.y)) / faceHeight * PI * 0.5`
8. **headRoll** [radians]: `atan2(L_EAR.y - R_EAR.y, L_EAR.x - R_EAR.x)`

### Helper functions:
- `dist3d(a, b) = sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)`
- `dist2d(a, b) = sqrt((a.x-b.x)^2 + (a.y-b.y)^2)`
- `remap(v, min, max) = (v - min) / (max - min)`
- `clamp01(v) = max(0, min(1, v))`
- `clamp(v, lo, hi) = max(lo, min(hi, v))`

---

## 11. Hand Feature Extraction

### Input
Array of hand landmark sets. Each hand has 21 landmarks `{x, y, z}`.

### MediaPipe Hand Landmark Indices
| Feature | Index |
|---------|-------|
| Wrist | 0 |
| Index tip | 8 |
| Middle base | 9 |
| Middle tip | 12 |
| Ring tip | 16 |
| Pinky tip | 20 |

### Extraction Algorithm (first hand only)

1. `handX = 1 - avg(lm[0].x, lm[9].x)` (mirrored)
2. `handY = avg(lm[0].y, lm[9].y)`
3. `palmSize = dist3d(lm[0], lm[9])`
4. `avgFingerDist = avg(dist3d(lm[8], lm[0]), dist3d(lm[12], lm[0]), dist3d(lm[16], lm[0]), dist3d(lm[20], lm[0]))`
5. `ratio = avgFingerDist / palmSize`
6. **handOpen** (with hysteresis):
   - If previously open: stay open while `ratio > 1.55`
   - If previously closed: open when `ratio > 1.85`
   - Initial state: `ratio > 1.7`

---

## 12. Constants

### Root note
- Base MIDI note: 60 (C4)
- Effective root: `60 + rootOffset` where `rootOffset` is 0..11

### Chord degrees
`[0, 1, 2, 3, 4, 5]`

### Octave range
Default: 2

### Tempo
- Default BPM: 85
- Range: 40..200

### Arp patterns
`['up-down', 'up', 'down', 'random', 'up-up-down', 'played']`

### Arp note values
`['4n', '8n', '8n.', '16n', '16n.', '32n']`

---

## 13. Presets

See `shared/schemas/preset.schema.json` for the full preset schema. Presets define all instrument parameters and are shared across platforms. The iOS app writes the full schema; the web app ignores iOS-only fields (e.g., AUv3 plugin references).

### Default Presets
| Name | BPM | Root | Character |
|------|-----|------|-----------|
| Default | 85 | C | Balanced starting point |
| Ambient Dream | 65 | C | Slow, wide reverb, no drums |
| Dark Techno | 128 | C | Fast, aggressive, heavy drums |
| Lo-Fi Chill | 72 | F | Warm, swing, relaxed |
| Bright Pop | 110 | G | Upbeat, clear, punchy |
| Deep Space | 55 | D# | Very slow, huge reverb, ethereal |
| Minimal | 120 | D | Sparse, clean, rhythmic |
| Future Bass | 140 | A# | High energy, wide, punchy |

---

## 14. State Schema

See `shared/schemas/state.schema.json` for the complete state object definition used by both platforms.
