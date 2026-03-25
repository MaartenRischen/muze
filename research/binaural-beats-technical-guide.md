# Binaural Beats Technical Guide for Muze App
## Combining Binaural Beats with Lo-Fi Hip Hop for Meditation

---

## 1. HOW BINAURAL BEATS WORK

### 1.1 Technical Mechanism

Binaural beats are an auditory illusion created when two tones of slightly different frequencies are presented separately to each ear via headphones. The brain's **superior olivary complex** (in the brainstem) — the first brain region that processes sound input from both ears — detects the frequency difference and generates the perception of a third "beat" tone oscillating at the difference frequency.

**Example:** Left ear receives 200 Hz, right ear receives 210 Hz → brain perceives a 10 Hz binaural beat.

The mechanism relies on **neural phase-locking**: neurons generate action potentials at well-defined phases of the periodic acoustic signal. When two slightly different frequencies arrive at each ear, the phase difference shifts cyclically, and the brain interprets this as a pulsating beat.

### 1.2 Technical Constraints

| Parameter | Constraint |
|-----------|-----------|
| Carrier frequency | Must be below **1000-1500 Hz** (binaural beats wane completely past 1000 Hz) |
| Frequency difference | Must be **less than 30 Hz** (ideally under 26 Hz) |
| Perceivable beat range | **1-30 Hz** (coincides with main EEG frequency bands) |
| Maximum perceivable beat | **25 Hz** at carrier ~440 Hz; lower at other carriers |
| Optimal perception | Carrier tones between **400-500 Hz** for perception clarity |

### 1.3 Why Headphones Are Required

Binaural beats **only work with headphones** because each ear must receive a different frequency in isolation. Without headphones:
- The two tones mix acoustically in the room before reaching the ears
- Both ears hear both frequencies simultaneously
- The brain cannot compute the interaural frequency difference
- The binaural illusion does not form

This is in contrast to isochronal tones, which do not require headphones (see Section 6).

### 1.4 Scientific Evidence and Research Status

**What the research supports:**
- Binaural beats DO create measurable changes in EEG activity
- Enhancement of EEG power has been found for theta, alpha, and gamma bands
- Required stimulation durations: **6-10 minutes for theta**, **5 minutes for alpha**, **15 minutes for gamma** entrainment
- Theta binaural beats at 6 Hz enabled participants to enter deep theta-level meditative state within **10 minutes** (2017 study)
- Moderate evidence for anxiety reduction and pain management
- A 2025 study (Nature Scientific Reports) found binaural beats attenuated vigilance decrement

**What remains uncertain:**
- The "brainwave entrainment hypothesis" (external stimulation → brain oscillates at same frequency) has mixed evidence
- No clear consensus either for or against the entrainment hypothesis
- Binaural beats produce weaker cortical entrainment compared to monaural beats
- Effects may not be superior to music therapy alone for anxiety/depression
- A 2023 study found binaural beats *deteriorated* cognitive test scores in some conditions
- Considerable heterogeneity in study methodologies makes comparison difficult

**Key insight for your app:** The subjective experience and relaxation benefits appear more robust than the strict "entrainment" mechanism. Even if the entrainment effect is modest, the perceptual experience combined with music creates genuine relaxation value.

---

## 2. FREQUENCY BANDS AND BRAINWAVE STATES

### 2.1 Complete Frequency Band Reference

| Band | Frequency Range | Brain State | Associated Effects |
|------|----------------|-------------|-------------------|
| **Delta (δ)** | 0.5-4 Hz | Deep sleep | Dreamless sleep, healing, physical restoration, HGH release, immune system recovery |
| **Theta (θ)** | 4-8 Hz | Light sleep / deep meditation | Creativity, REM sleep, memory consolidation, emotional processing, hypnagogic states |
| **Alpha (α)** | 8-13 Hz | Relaxed wakefulness | Calm focus, relaxation, stress reduction, bridge between conscious and subconscious |
| **Beta (β)** | 13-30 Hz | Active thinking | Alertness, concentration, problem-solving, active conversation, working memory |
| **Gamma (γ)** | 30-50 Hz | Peak performance | Insight, "aha" moments, cross-modal perception, information integration, peak awareness |

### 2.2 Most Relevant for Meditation

**Primary: Theta (4-8 Hz)** — The "sweet spot" for meditation
- Deepest meditative states accessible with binaural beats
- Associated with the hypnagogic state between waking and sleeping
- Experienced meditators naturally produce more theta waves
- Best target: **6 Hz** (validated in studies)

**Secondary: Alpha (8-13 Hz)** — Gateway to meditation
- Best for beginners and "relaxed awareness" meditation
- Promotes calm, focused attention without drowsiness
- Ideal starting point before deepening to theta
- Best target: **10 Hz** (center of alpha range)

**Supportive: Delta (0.5-4 Hz)** — For sleep meditation / yoga nidra
- Extremely deep states, risk of falling asleep
- Best for sleep-focused sessions
- Best target: **2-3 Hz**

### 2.3 Most Relevant for Creative/Flow States

**Primary: Alpha-Theta Border (7-10 Hz)** — The "flow state" zone
- Where relaxation meets light focus
- Associated with creative insight and "in the zone" feeling
- Best target: **8 Hz** (alpha-theta crossover)

**Secondary: Gamma (40 Hz)** — For peak creative insight
- Associated with "eureka" moments
- Used by Brain.fm for focus modes
- Best target: **40 Hz** (but note: at edge of binaural beat perception range)

**Tertiary: Low Beta (13-15 Hz)** — For focused creative work
- Active but relaxed concentration
- Good for writing, coding, creative problem-solving

### 2.4 Optimal Carrier Frequencies (The Oster Curve)

Dr. Gerald Oster's 1973 landmark paper "Auditory Beats in the Brain" (Scientific American) established the **Oster Curve**, mapping carrier frequency to binaural beat perception strength.

| Target Beat Frequency | Optimal Carrier Range | Notes |
|----------------------|----------------------|-------|
| Theta (4-8 Hz) | **160-210 Hz** | Most audible theta perception |
| Alpha (8-13 Hz) | **230-240 Hz** | Strongest alpha perception |
| General optimal | **400-500 Hz** | Best overall perception |
| Maximum perception | **~440 Hz** | Peak of the Oster Curve |
| Upper limit | **<1000 Hz** | Binaural beats cease above this |

**Practical recommendation for your app: Use carrier frequencies in the 180-440 Hz range.**

- **200 Hz** carrier: Warm, pleasant, good for theta/delta targets (sleep/deep meditation)
- **250 Hz** carrier: Balanced, works well across all beat frequencies
- **300-400 Hz** carrier: Slightly brighter, good for alpha/beta targets (focus/creative)
- **432 Hz** carrier: Popular in meditation communities (claimed "natural" tuning, though scientific evidence for superiority is lacking)
- **440 Hz** carrier: Standard concert pitch A4, peak binaural perception

---

## 3. IMPLEMENTATION WITH WEB AUDIO / TONE.JS

### 3.1 Basic Binaural Beat Generation

The fundamental pattern: two oscillators, each hard-panned to one ear.

```javascript
// === Using raw Web Audio API ===
const audioCtx = new AudioContext();

// Left ear oscillator
const oscLeft = audioCtx.createOscillator();
const panLeft = audioCtx.createStereoPanner();
oscLeft.frequency.value = 200;      // carrier frequency
panLeft.pan.value = -1;             // full left
oscLeft.connect(panLeft).connect(audioCtx.destination);

// Right ear oscillator
const oscRight = audioCtx.createOscillator();
const panRight = audioCtx.createStereoPanner();
oscRight.frequency.value = 210;     // carrier + 10 Hz = 10 Hz alpha beat
panRight.pan.value = 1;             // full right
oscRight.connect(panRight).connect(audioCtx.destination);

// Gain control for volume
const gainNode = audioCtx.createGain();
gainNode.gain.value = 0.15;         // Keep binaural beats quiet relative to music
oscLeft.connect(gainNode);
oscRight.connect(gainNode);
gainNode.connect(audioCtx.destination);

oscLeft.start();
oscRight.start();
```

```javascript
// === Using Tone.js ===
import * as Tone from 'tone';

// Create binaural beat with Tone.js
const leftOsc = new Tone.Oscillator({
  frequency: 200,
  type: 'sine',       // Always use sine waves for binaural beats
  volume: -25          // dB — quiet relative to music
}).toDestination();

const rightOsc = new Tone.Oscillator({
  frequency: 210,
  type: 'sine',
  volume: -25
}).toDestination();

// Pan hard left and right
const pannerLeft = new Tone.Panner(-1);
const pannerRight = new Tone.Panner(1);

leftOsc.connect(pannerLeft);
pannerLeft.toDestination();

rightOsc.connect(pannerRight);
pannerRight.toDestination();

leftOsc.start();
rightOsc.start();
```

### 3.2 Smooth Frequency Transitions Between States

Tone.js provides sample-accurate scheduling for smooth ramps:

```javascript
// Transition from Alpha (10 Hz beat) to Theta (6 Hz beat) over 60 seconds
// Carrier = 200 Hz

// Starting state: L=200 Hz, R=210 Hz (10 Hz alpha)
// Target state:   L=200 Hz, R=206 Hz (6 Hz theta)

// Method 1: linearRampTo (smooth linear transition)
rightOsc.frequency.linearRampTo(206, 60);  // ramp over 60 seconds

// Method 2: exponentialRampTo (more natural-sounding curve)
rightOsc.frequency.exponentialRampTo(206, 60);

// Method 3: rampTo (auto-selects linear or exponential based on units)
rightOsc.frequency.rampTo(206, 60);

// Method 4: Scheduled multi-stage session
const now = Tone.now();
rightOsc.frequency.setValueAtTime(210, now);                    // Start: 10 Hz alpha
rightOsc.frequency.linearRampToValueAtTime(208, now + 120);     // 2 min: ease to 8 Hz
rightOsc.frequency.linearRampToValueAtTime(206, now + 300);     // 5 min: deepen to 6 Hz theta
rightOsc.frequency.linearRampToValueAtTime(204, now + 600);     // 10 min: deep 4 Hz theta
rightOsc.frequency.linearRampToValueAtTime(208, now + 840);     // 14 min: rise back to alpha
rightOsc.frequency.linearRampToValueAtTime(210, now + 900);     // 15 min: gentle awakening
```

### 3.3 Optimal Settings for Pleasant Listening

| Parameter | Recommended Value | Notes |
|-----------|------------------|-------|
| Waveform | **Sine wave only** | Other waveforms create harmonic content that disrupts the binaural effect |
| Carrier frequency | **200-300 Hz** under lo-fi music | Sits below most melodic content |
| Beat volume | **-20 to -30 dB** relative to music | Should be barely consciously noticeable |
| Beat volume ratio | **10-20% of music volume** | Subliminal but present |
| Fade in/out | **3-5 seconds** | Avoid jarring clicks |

### 3.4 Layering Under Music Without Being Obtrusive

```javascript
// Architecture for layering binaural beats under lo-fi music

// Music channel
const musicPlayer = new Tone.Player('/path/to/lofi-track.mp3');
const musicGain = new Tone.Gain(0.8);  // Music at 80%
musicPlayer.connect(musicGain).connect(Tone.Destination);

// Binaural beat channel
const binauralGain = new Tone.Gain(0.12);  // Binaural at 12%
leftOsc.connect(pannerLeft);
rightOsc.connect(pannerRight);
pannerLeft.connect(binauralGain);
pannerRight.connect(binauralGain);
binauralGain.connect(Tone.Destination);

// Optional: Low-pass filter to soften the binaural tone
const lpFilter = new Tone.Filter({
  frequency: 500,
  type: 'lowpass',
  rolloff: -12
});
binauralGain.connect(lpFilter);
lpFilter.connect(Tone.Destination);
```

### 3.5 Multiple Binaural Beat Layers

You CAN stack multiple binaural beat layers, but with important caveats:

**What works:**
- The Monroe Institute's Hemi-Sync technology layers multiple frequencies
- Different carrier frequencies can each carry their own beat frequency
- Example: 200/206 Hz (6 Hz theta) + 350/360 Hz (10 Hz alpha) simultaneously

**What to watch out for:**
- Mixing multiple beats can create conflicting neural responses
- Best practice: limit to **1-2 simultaneous layers**
- If using two layers, use well-separated carrier frequencies (e.g., 200 Hz and 400 Hz)
- Keep combined volume low

```javascript
// Two-layer binaural beat example
// Layer 1: Theta (6 Hz) at 200 Hz carrier
const thetaLeft = new Tone.Oscillator({ frequency: 200, type: 'sine', volume: -28 });
const thetaRight = new Tone.Oscillator({ frequency: 206, type: 'sine', volume: -28 });

// Layer 2: Alpha (10 Hz) at 400 Hz carrier
const alphaLeft = new Tone.Oscillator({ frequency: 400, type: 'sine', volume: -30 });
const alphaRight = new Tone.Oscillator({ frequency: 410, type: 'sine', volume: -30 });

// Pan and connect each pair separately
```

---

## 4. COMBINING WITH MUSIC

### 4.1 How Top Apps Handle This

**Brain.fm** — Does NOT use traditional binaural beats. Instead uses **neural phase-locking** via amplitude modulation directly embedded in the music. Volume modulations at target frequencies (e.g., 12-20 Hz beta for focus) are woven into both stereo channels. This is stronger than binaural beats because it stimulates the auditory system directly rather than relying on the brain to compute a difference frequency. Published in Nature Communications Biology (2024).

**Endel** — Uses binaural beats as a specific "scenario" mode separate from its main generative soundscapes. Core technology uses pentatonic scale (like video game music design) for familiarity. Adapts to biometric inputs (heart rate via wearables). Responds to time of day, weather, and user activity.

**Calm** — Primarily music/voice-guided. When binaural beats are used, they are a subtle underlayer beneath nature sounds and ambient textures.

### 4.2 Best Practices for Integration with Lo-Fi Hip Hop

**Frequency Separation Strategy:**
- Lo-fi hip hop typically sits in 60-90 BPM range
- Most melodic content (keys, pads) occupies 300 Hz - 5 kHz
- Drums occupy 60-200 Hz (kick) and 2-10 kHz (hats/snare texture)
- **Place binaural carrier at 180-250 Hz** — sits in a natural pocket between kick drum fundamental and melodic content
- This range also happens to be optimal for theta/alpha perception per the Oster Curve

**Volume Strategy:**
- Binaural beats at **10-15% the volume of the music** (-18 to -24 dB below)
- User should barely notice them consciously
- Provide separate volume sliders for music and binaural beat intensity
- Some users prefer to *feel* the beats; others want them fully subliminal

**Ensuring Binaural Effect Is Not Masked:**
- Music with lots of sustained low-mid content (200-400 Hz) can mask the binaural carrier
- Solutions:
  - **Sidechain duck** the music slightly in the carrier frequency range
  - Use **EQ notching** on the music: subtle 2-3 dB cut at the carrier frequency
  - Choose lo-fi tracks with **sparse arrangements** in the low-mid range
  - Use **sine wave** carriers (no harmonics to clash with music)
  - The binaural beat itself (the perceived difference frequency at 4-10 Hz) is generated internally by the brain, so it cannot be directly masked — but the carrier tones CAN be masked, which prevents the brain from forming the beat

### 4.3 Should the Carrier Frequency Relate to Musical Key?

**Short answer: Ideally yes, but it is not strictly necessary for the binaural effect to work.**

**Why it helps:**
- A carrier frequency that is harmonically related to the musical key creates a more consonant, pleasant overall sound
- If the music is in the key of A (440 Hz), using a carrier of 220 Hz (A3) or 110 Hz (A2) creates harmonic alignment
- Dissonant carriers against the music key create an uneasy feeling that undermines relaxation

**Practical approach:**
- Analyze or set the key of each lo-fi track
- Choose a carrier frequency that is a musical note in that key
- Common meditation-friendly carriers that work as musical notes:

| Musical Note | Frequency (Hz) | Good For |
|-------------|----------------|----------|
| G3 | 196 Hz | Theta beats, warm tone |
| A3 | 220 Hz | Universal, matches A-key music |
| B3 | 247 Hz | Alpha beats |
| C4 | 261 Hz | Matches C-key music (very common key) |
| D4 | 293 Hz | Bright but warm |
| E4 | 329 Hz | Good for alpha/beta |
| A4 | 440 Hz | Peak perception, standard tuning |

**For 432 Hz tuning enthusiasts:** Using 216 Hz (A3 in 432 tuning) or 432 Hz as carriers is popular in the meditation community, though scientific evidence for superiority over 440 Hz tuning is not established.

---

## 5. MEDITATION SESSION DESIGN

### 5.1 Typical Session Lengths

| Session Type | Duration | Target Audience |
|-------------|----------|----------------|
| Quick reset | 3-5 min | Beginners, micro-breaks |
| Short session | 10-15 min | Regular practice, daily use |
| Standard session | 20-30 min | Committed practitioners |
| Deep session | 45-60 min | Advanced, weekend practice |
| Sleep session | 30-90 min | Sleep onset, plays until asleep |

**Recommendation for your app:** Default to **15-minute sessions** with options for 5, 10, 15, 20, 30, and 45 minutes. A 2017 study found that 10 minutes of 6 Hz theta binaural beats was sufficient to induce a deep meditative state.

### 5.2 Frequency Progression Over a Session

**The "Descent and Ascent" Pattern (most common):**

```
Session Timeline (20-minute example):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Phase 1: INDUCTION (0-3 min)
  Beta → Alpha transition (14 Hz → 10 Hz)
  Purpose: Settle the mind from active state
  Music: Full lo-fi arrangement, normal energy

Phase 2: DEEPENING (3-8 min)
  Alpha → Theta transition (10 Hz → 6 Hz)
  Purpose: Guide into meditative state
  Music: Gradually strip back arrangement, reduce drums

Phase 3: SUSTAIN (8-16 min)
  Hold at Theta (6 Hz) or deep Theta (4-5 Hz)
  Purpose: Maintain deep meditation
  Music: Minimal — ambient pads, occasional soft melodic elements

Phase 4: RETURN (16-19 min)
  Theta → Alpha transition (6 Hz → 10 Hz)
  Purpose: Gentle return to waking consciousness
  Music: Gradually reintroduce elements

Phase 5: AWAKENING (19-20 min)
  Alpha → light Beta (10 Hz → 13 Hz)
  Purpose: Alert but calm re-engagement
  Music: Full arrangement returns gently
  Optional: Gentle bell or chime
```

**Sleep Session Pattern (no return phase):**
```
0-5 min:   Alpha (10 Hz) — relaxation onset
5-15 min:  Theta (6 Hz) — drowsiness
15-30 min: Delta (2-3 Hz) — sleep onset
30+ min:   Hold Delta or fade out
```

### 5.3 What Makes a Meditation Audio Experience Effective

Based on research and industry best practices:

1. **Predictability without monotony** — Subtle variation within a consistent framework
2. **Gradual transitions** — No sudden changes in frequency, volume, or musical texture
3. **Appropriate pacing** — Allow 5+ minutes before expecting deep states
4. **Minimal cognitive load** — Simple, repetitive musical patterns (pentatonic scale, limited harmonic movement)
5. **Natural sounds integration** — Rain, water, forest sounds increase relaxation (but can mask binaural beats if too loud)
6. **Warm timbres** — Soft pads, electric piano, gentle guitar (all hallmarks of lo-fi hip hop)
7. **Consistent low-frequency foundation** — Gives the nervous system something stable to entrain to
8. **Graceful ending** — Never end abruptly; always fade or transition up

---

## 6. ISOCHRONAL TONES AS ALTERNATIVE/COMPLEMENT

### 6.1 How Isochronal Tones Differ

| Feature | Binaural Beats | Isochronal Tones |
|---------|---------------|------------------|
| Mechanism | Two different frequencies, one per ear | Single tone pulsing on/off at target frequency |
| Headphones required | **Yes** | **No** |
| Entrainment strength | Moderate (indirect, brain-computed) | Stronger (direct rhythmic stimulation) |
| Musical integration | Easier (continuous tone, less noticeable) | Harder (pulsing is more audible/distracting) |
| Research base | More studied (88% of studies) | Less studied (12% of studies) |
| Speaker playback | Does not work | Works |

### 6.2 Using Both Together

You could offer both in your app:
- **Binaural beats** as the default for headphone users (more subtle, integrates better with lo-fi music)
- **Isochronal tones** as a fallback/option when headphones are not detected (or as an enhancement layer)
- **Combined mode**: Isochronal pulse on top of binaural carrier for maximum entrainment

```javascript
// Isochronal tone implementation with Tone.js
const isoTone = new Tone.Oscillator({
  frequency: 250,   // carrier
  type: 'sine',
  volume: -22
});

// LFO to create the pulsing effect at target brainwave frequency
const lfo = new Tone.LFO({
  frequency: 6,      // 6 Hz theta pulse
  min: 0,
  max: 1,
  type: 'square'     // sharp on/off for isochronal; use 'sine' for smoother
});

const ampEnv = new Tone.Gain(0);
lfo.connect(ampEnv.gain);
isoTone.connect(ampEnv);
ampEnv.toDestination();

isoTone.start();
lfo.start();
```

---

## 7. FACE TRACKING & ADAPTIVE MEDITATION

### 7.1 Facial Expression → Binaural Beat Parameter Mapping

Your app's face tracking (presumably via MediaPipe or TensorFlow.js face landmarks) can detect several states relevant to meditation:

| Facial Signal | Detection Method | What It Indicates | Parameter Mapping |
|--------------|-----------------|-------------------|-------------------|
| **Eyes closed** | Eye aspect ratio (EAR) < threshold | Meditation engagement | Deepen frequency (move toward theta) |
| **Eyes open** | EAR > threshold | Distraction/alertness | Hold or raise frequency (stay alpha) |
| **Relaxed brow** | Low brow landmark movement | Low stress | Maintain current state, possibly deepen |
| **Furrowed brow** | High brow landmark tension | Concentration/stress | Slightly raise frequency, add calming elements |
| **Jaw relaxation** | Mouth slightly open, jaw dropped | Deep relaxation | Good signal for theta/delta transition |
| **Jaw clenching** | Jaw landmarks compressed | Tension | Add more alpha, slow the deepening |
| **Slow blink rate** | Blink frequency < 10/min | Relaxation/drowsiness | Can deepen toward theta |
| **Micro-expressions** | Brief facial movements | Emotional processing | Maintain steady state, don't change |
| **Stable stillness** | Low overall landmark movement variance | Deep meditation achieved | Hold steady, minimal changes |
| **Head nodding/drooping** | Head pose estimation, pitch angle | Falling asleep | If sleep mode: deepen to delta. If meditation mode: gently raise to alpha |

### 7.2 Detecting Meditation Depth

Create a composite "meditation depth score" (0-100) from multiple signals:

```javascript
function calculateMeditationDepth(faceData) {
  const weights = {
    eyesClosed: 0.30,        // Most important signal
    facialStillness: 0.25,   // Low variance in landmarks over time
    jawRelaxation: 0.15,     // Relaxed jaw = relaxed body
    browRelaxation: 0.15,    // Smooth forehead = low stress
    blinkRate: 0.10,         // Slow blinks = relaxation
    headStability: 0.05      // Minimal head movement
  };

  let score = 0;
  score += weights.eyesClosed * (faceData.eyesClosed ? 1.0 : 0.2);
  score += weights.facialStillness * faceData.stillnessScore;      // 0-1
  score += weights.jawRelaxation * faceData.jawRelaxScore;         // 0-1
  score += weights.browRelaxation * (1 - faceData.browTension);    // 0-1
  score += weights.blinkRate * mapBlinkRate(faceData.blinksPerMin); // 0-1
  score += weights.headStability * faceData.headStabilityScore;    // 0-1

  return Math.round(score * 100);
}

// Map meditation depth to binaural beat frequency
function depthToFrequency(depth) {
  // depth 0-100 maps to frequency range
  // 0 (not meditating) = 13 Hz (low beta, alert)
  // 30 (light relaxation) = 10 Hz (alpha)
  // 60 (moderate meditation) = 7 Hz (theta border)
  // 80 (deep meditation) = 5 Hz (theta)
  // 100 (very deep) = 3 Hz (deep theta/delta border)

  const maxFreq = 13;  // Hz
  const minFreq = 3;   // Hz
  return maxFreq - (depth / 100) * (maxFreq - minFreq);
}
```

### 7.3 Adaptive "Meditation Mode" Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MEDITATION MODE                       │
│                                                         │
│  ┌──────────┐    ┌─────────────┐    ┌───────────────┐  │
│  │  Camera   │───▶│ Face Track  │───▶│ Meditation    │  │
│  │  Input    │    │ (MediaPipe) │    │ Depth Score   │  │
│  └──────────┘    └─────────────┘    └───────┬───────┘  │
│                                             │           │
│                                     ┌───────▼───────┐  │
│                                     │   Smoothing   │  │
│                                     │   (EMA filter  │  │
│                                     │   over 5-10s)  │  │
│                                     └───────┬───────┘  │
│                                             │           │
│              ┌──────────────────────────────┼──────┐   │
│              │                              │      │   │
│      ┌───────▼───────┐  ┌──────────▼──────┐ ┌──▼──┐  │
│      │ Binaural Beat │  │ Music Arranger  │ │ UI  │  │
│      │ Controller    │  │ Controller      │ │     │  │
│      │               │  │                 │ │     │  │
│      │ • Beat freq   │  │ • Track layers  │ │Viz  │  │
│      │ • Carrier freq│  │ • Drum volume   │ │Color│  │
│      │ • Volume      │  │ • Pad intensity │ │Orb  │  │
│      │ • Transitions │  │ • FX depth      │ │     │  │
│      └───────────────┘  └─────────────────┘ └─────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**How it would work in practice:**

1. **User starts session** — Alpha beats (10 Hz) begin, full lo-fi arrangement plays
2. **User closes eyes** — System detects within 2-3 seconds, begins slowly deepening toward theta
3. **Face relaxes over time** — Meditation depth score climbs, beats gradually shift to 6-7 Hz theta
4. **User opens eyes briefly** — System detects, pauses deepening but does NOT jump back (use hysteresis to avoid jarring changes)
5. **User resettles** — System resumes gentle deepening
6. **Deep stillness detected** — Score reaches 80+, beats at 4-5 Hz deep theta, music stripped to ambient pads
7. **Session timer approaches end** — Regardless of face state, system begins gradual return to alpha, music re-engages
8. **User opens eyes** — Final transition to alert alpha, session summary shown

**Critical design principle: SMOOTHING**
- Never make instant changes based on face data
- Use an Exponential Moving Average (EMA) with a 5-10 second window
- The audio should lag behind face changes by several seconds
- This prevents jarring transitions when the user shifts position, scratches their face, etc.

```javascript
// Exponential Moving Average for smooth meditation depth tracking
class MeditationDepthTracker {
  constructor(smoothingFactor = 0.05) {  // Lower = smoother (0.02-0.1 range)
    this.smoothingFactor = smoothingFactor;
    this.currentDepth = 0;
  }

  update(rawDepth) {
    this.currentDepth = this.smoothingFactor * rawDepth
                      + (1 - this.smoothingFactor) * this.currentDepth;
    return this.currentDepth;
  }

  // Asymmetric smoothing: deepen slowly, but respond faster to disturbance
  updateAsymmetric(rawDepth) {
    const factor = rawDepth > this.currentDepth
      ? 0.03    // Deepen slowly (takes ~30 seconds to respond)
      : 0.08;   // Rise faster if disturbance detected (~12 seconds)
    this.currentDepth = factor * rawDepth + (1 - factor) * this.currentDepth;
    return this.currentDepth;
  }
}
```

### 7.4 Additional Adaptive Music Behaviors

| Meditation Depth | Lo-Fi Music Adaptation | Binaural Adaptation |
|-----------------|----------------------|-------------------|
| 0-20 (alert) | Full arrangement, drums active | 12-13 Hz (low beta) |
| 20-40 (settling) | Reduce hi-hat velocity, soften snare | 10-12 Hz (alpha) |
| 40-60 (relaxed) | Remove drums, keep bass + pads | 7-10 Hz (low alpha/high theta) |
| 60-80 (deep) | Pads only, long reverb tails | 5-7 Hz (theta) |
| 80-100 (very deep) | Minimal drone, near-silence with texture | 3-5 Hz (deep theta/delta) |

---

## 8. COMPLETE BINAURAL BEAT ENGINE (Reference Implementation)

```javascript
// BinauralBeatEngine.js — Complete reference for Muze app
import * as Tone from 'tone';

class BinauralBeatEngine {
  constructor() {
    this.leftOsc = null;
    this.rightOsc = null;
    this.leftPanner = null;
    this.rightPanner = null;
    this.gainNode = null;
    this.carrierFreq = 200;
    this.beatFreq = 10;
    this.isPlaying = false;
  }

  init(carrierFreq = 200, beatFreq = 10, volume = -24) {
    this.carrierFreq = carrierFreq;
    this.beatFreq = beatFreq;

    // Oscillators
    this.leftOsc = new Tone.Oscillator({
      frequency: carrierFreq,
      type: 'sine'
    });
    this.rightOsc = new Tone.Oscillator({
      frequency: carrierFreq + beatFreq,
      type: 'sine'
    });

    // Stereo panning (hard left/right)
    this.leftPanner = new Tone.Panner(-1);
    this.rightPanner = new Tone.Panner(1);

    // Master gain
    this.gainNode = new Tone.Gain(Tone.dbToGain(volume));

    // Signal chain
    this.leftOsc.connect(this.leftPanner);
    this.rightOsc.connect(this.rightPanner);
    this.leftPanner.connect(this.gainNode);
    this.rightPanner.connect(this.gainNode);
    this.gainNode.toDestination();
  }

  start() {
    if (!this.isPlaying) {
      this.leftOsc.start();
      this.rightOsc.start();
      this.isPlaying = true;
    }
  }

  stop(fadeTime = 3) {
    if (this.isPlaying) {
      this.gainNode.gain.linearRampTo(0, fadeTime);
      setTimeout(() => {
        this.leftOsc.stop();
        this.rightOsc.stop();
        this.isPlaying = false;
      }, fadeTime * 1000 + 100);
    }
  }

  // Smoothly transition to a new beat frequency
  setBeatFrequency(newBeatFreq, rampTime = 10) {
    this.beatFreq = newBeatFreq;
    this.rightOsc.frequency.linearRampTo(
      this.carrierFreq + newBeatFreq,
      rampTime
    );
  }

  // Change carrier frequency (both oscillators move together)
  setCarrierFrequency(newCarrier, rampTime = 10) {
    this.carrierFreq = newCarrier;
    this.leftOsc.frequency.linearRampTo(newCarrier, rampTime);
    this.rightOsc.frequency.linearRampTo(newCarrier + this.beatFreq, rampTime);
  }

  // Set volume in dB
  setVolume(dbValue, rampTime = 2) {
    this.gainNode.gain.linearRampTo(Tone.dbToGain(dbValue), rampTime);
  }

  // Schedule a complete meditation session
  scheduleSession(durationMinutes = 15) {
    const now = Tone.now();
    const dur = durationMinutes * 60;  // total seconds

    // Phase 1: Induction (0-15% of session) — Alpha
    this.rightOsc.frequency.setValueAtTime(this.carrierFreq + 10, now);

    // Phase 2: Deepening (15-40%) — Alpha to Theta
    this.rightOsc.frequency.linearRampToValueAtTime(
      this.carrierFreq + 6, now + dur * 0.4
    );

    // Phase 3: Sustain (40-80%) — Deep Theta
    this.rightOsc.frequency.setValueAtTime(
      this.carrierFreq + 5, now + dur * 0.5
    );

    // Phase 4: Return (80-95%) — Theta to Alpha
    this.rightOsc.frequency.linearRampToValueAtTime(
      this.carrierFreq + 10, now + dur * 0.95
    );

    // Phase 5: Awakening (95-100%) — Alpha to low Beta
    this.rightOsc.frequency.linearRampToValueAtTime(
      this.carrierFreq + 13, now + dur
    );
  }

  dispose() {
    this.leftOsc?.dispose();
    this.rightOsc?.dispose();
    this.leftPanner?.dispose();
    this.rightPanner?.dispose();
    this.gainNode?.dispose();
  }
}

export default BinauralBeatEngine;
```

---

## 9. KEY RECOMMENDATIONS FOR MUZE

1. **Use 200-250 Hz carrier frequencies** as default — they sit in the sweet spot of the Oster Curve for theta/alpha AND fit below most lo-fi melodic content
2. **Start users at alpha (10 Hz)** and deepen based on session goal and face tracking data
3. **Keep binaural beats at -20 to -28 dB** below music level — they should be felt, not heard
4. **Always use sine waves** — other waveforms create harmonics that interfere with music and binaural perception
5. **Implement asymmetric smoothing** on face tracking → audio parameter mapping (slow to deepen, faster to respond to disturbance)
6. **Consider implementing amplitude modulation** as Brain.fm does (neural phase-locking) as a more potent alternative or supplement to traditional binaural beats
7. **Offer isochronal tones** as a speaker-friendly alternative when headphones are not detected
8. **Match carrier frequency to musical key** when possible for consonant integration
9. **Minimum effective session**: 5-10 minutes based on research (theta entrainment validated at 6-10 min)
10. **Always provide a gentle return phase** — never cut off binaural beats abruptly

---

## SOURCES

### Scientific Papers
- [Binaural beats to entrain the brain? Systematic review (2023)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10198548/)
- [Binaural Beats through the Auditory Pathway (2020)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7082494/)
- [Parametric investigation of binaural beats for brain entrainment (2025)](https://www.nature.com/articles/s41598-025-88517-z)
- [Reverse effect of home-use binaural beats (2023)](https://www.nature.com/articles/s41598-023-38313-4)
- [Personalized Theta and Beta Binaural Beats (2021)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8636003/)
- [Efficiency of Binaural Beats on Anxiety and Depression (2024)](https://www.mdpi.com/2076-3417/14/13/5675)
- [Review of Binaural Beats and the Brain (2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11367212/)
- [EEG activity in response to binaural beats (2015)](https://www.sciencedirect.com/science/article/abs/pii/S0167876014016353)
- [Effects of binaural beats on working memory (2022)](https://pmc.ncbi.nlm.nih.gov/articles/PMC9153928/)
- [Binaural beats synchronize brain activity (ScienceDaily, 2020)](https://www.sciencedaily.com/releases/2020/02/200217143447.htm)
- [Real-Time EEG-Guided Binaural Beat Audio (2024)](https://www.mdpi.com/2673-9488/5/4/44)

### Technical Implementation
- [BinauralBeatJS — Web Audio API library](https://github.com/ichabodcole/BinauralBeatJS)
- [Binaural beats generator using Tone.js](https://github.com/room2g1t/binaural-beats-generator)
- [Tone.js Signals (frequency ramping)](https://github.com/Tonejs/Tone.js/wiki/Signals)
- [Tone.js Param documentation](https://tonejs.github.io/docs/14.7.38/Param)
- [StereoPannerNode — MDN](https://developer.mozilla.org/en-US/docs/Web/API/StereoPannerNode)
- [Web Audio spatialization basics — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Web_audio_spatialization_basics)

### Industry & Apps
- [Brain.fm Science](https://www.brain.fm/science)
- [Brain.fm: Binaural Beats vs Neural Phase-Locking](https://www.brain.fm/blog/binaural-beats-vs-neural-phase-locking)
- [Brain.fm: How Neural Phase-Locking Works](https://www.brain.fm/blog/how-neural-phase-locking-works)
- [Endel Science](https://endel.io/science)
- [MorphCast Emotion AI](https://www.morphcast.com/)

### Reference Guides
- [Understanding the Oster Curve](https://www.binauralbeatsmeditation.com/oster-curve/)
- [Carrier Frequencies Explained](https://binauralpure.com/blog/carrier-frequencies-explained)
- [Binaural Beats Frequency Guide](https://www.binauralbeatsmeditation.com/frequency-guide/)
- [Binaural Beats — Psychology Today](https://www.psychologytoday.com/us/basics/binaural-beats)
- [Binaural Beats — WebMD](https://www.webmd.com/balance/what-are-binaural-beats)
- [Binaural Beats — Healthline](https://www.healthline.com/health/binaural-beats)
- [Isochronic Tones vs Binaural Beats — Brain.fm](https://www.brain.fm/blog/isochronic_tones_vs_binaural_beats_which_is_better_for_your_mind)
- [The Masking of Binaural Beats (Audiology)](https://www.tandfonline.com/doi/abs/10.3109/00206097209089293)
- [Binaural Beats — Auditory Neuroscience](https://auditoryneuroscience.com/spatial-hearing/binaural-beats)
