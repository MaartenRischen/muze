# Muze Audio Engine Audit & Optimization Report

**Date:** 2026-03-25
**Files analyzed:** `/Users/maartenrischen/Desktop/Muze-sprint/js/audio.js`, `mixer.js`, `features.js`, `app.js`, `config.js`

---

## Executive Summary

The Muze audio engine is well-structured with a professional send/return bus architecture, good gain staging defaults, and several smart performance choices (removing per-channel Meter nodes, staggering face/hand detection). However, there are **14 issues** ranging from crash risks to performance drains to architectural concerns. This report details each issue, its severity, and the exact fix.

---

## 1. NODE COUNT ANALYSIS

### Current Node Count (Estimated Web Audio Nodes)

| Category | Nodes | Details |
|----------|-------|---------|
| Master chain | ~15 | Analyser(waveform) + Analyser(FFT) + Limiter(~3 internal) + Gain + EQ3(~6 internal: 3 BiquadFilters + splitter/merger) + WaveShaper + 4 Gains + Filter(-24dB = 2 BiquadFilters) |
| Reverb bus | ~10 | Reverb(ConvolverNode + internal gains) + EQ3(~6) for damping |
| Delay bus | ~3 | FeedbackDelay (delay + gain + feedback loop) |
| Per-channel strip x8 | ~88 | Each: EQ3(~6) + Panner(1) + Gain(1) + reverbSend Gain(1) + delaySend Gain(1) = ~10 nodes x 8 channels + channel wiring |
| Pad synth | ~15 | PolySynth(FMSynth, 4 voices) + PolySynth(Synth, 3 sub voices) + Chorus(~3) |
| Arp synth | ~12 | PolySynth(Synth, 8 voices) + Filter(-24dB = 2 BiquadFilters) |
| Melody synth | ~8 | MonoSynth(osc + filter + envelopes) + LFO + Gain |
| Drums | ~14 | Kick(MembraneSynth + NoiseSynth + Filter + Gain) + Snare(NoiseSynth + Filter + MembraneSynth + Gain) + Hat(2x NoiseSynth + 2x Filter + Gain) |
| Binaural | ~5 | 2x Oscillator + 2x Panner + Gain |
| Riser | ~3 | Noise + Gain + Filter |
| GrainPlayer | ~2 | GrainPlayer + connection to chorus |
| **TOTAL** | **~175** | |

This is a **heavy node graph** for mobile. Desktop Chrome handles ~200 nodes fine, but iOS Safari starts showing strain above ~80-100 active nodes, especially with ConvolverNode + multiple EQ3 instances.

---

## 2. CRITICAL ISSUES (Crash / Audio Failure Risks)

### ISSUE 1: No AudioContext Interruption Recovery (iOS Crash)
**Severity: CRITICAL**
**Location:** `audio.js` — no `statechange` listener anywhere

On iOS Safari, when a user receives a phone call, switches tabs, locks the screen, or Siri activates, the AudioContext enters the `"interrupted"` state. There is **no recovery code** in the engine. The audio will go silent permanently until the page is force-reloaded.

**Fix:**
```javascript
// Add to the end of init(), after Tone.Transport.start()
const ctx = Tone.context.rawContext;
ctx.addEventListener('statechange', () => {
  if (ctx.state === 'interrupted' || ctx.state === 'suspended') {
    // Attempt resume on next user interaction
    const resume = async () => {
      try {
        await ctx.resume();
        if (ctx.state === 'running') {
          document.removeEventListener('touchstart', resume);
          document.removeEventListener('click', resume);
        }
      } catch (e) { /* retry on next interaction */ }
    };
    document.addEventListener('touchstart', resume, { once: false });
    document.addEventListener('click', resume, { once: false });
  }
});
```

### ISSUE 2: Sidechain Duck Reads Live Gain Value — Race Condition
**Severity: HIGH**
**Location:** `features.js:752-768` — `MUZE.Sidechain.duck()`

The sidechain reads `padNode.gain.gain.value` as the "current" gain, then schedules an automation envelope from that value. But `.value` returns the **last-set** value, not the currently-interpolated value during a ramp. If a duck fires while a previous duck's release ramp is still active, the `padGain` captured will be wrong (could be the ducked value, not the target). Over repeated kicks, the gain drifts toward zero.

Additionally, `cancelScheduledValues(now)` + `setValueAtTime(padGain, now)` is correct, but `padGain` itself is unreliable.

**Fix:**
```javascript
// Store the "home" gain value separately, don't read from the live node
MUZE.Sidechain = {
  _padHomeGain: null,
  _arpHomeGain: null,

  duck() {
    const padNode = MUZE.Audio._nodes.pad;
    const arpNode = MUZE.Audio._nodes.arp;
    const now = Tone.now();

    // Use stored home gain, fall back to current mixer dB setting
    if (padNode) {
      const padGain = this._padHomeGain ??
        Tone.dbToGain(MUZE.Mixer.channels.pad.volume);
      this._padHomeGain = padGain;

      padNode.gain.gain.cancelScheduledValues(now);
      padNode.gain.gain.setValueAtTime(padGain, now);  // snap to known-good value
      padNode.gain.gain.linearRampToValueAtTime(padGain * 0.10, now + 0.005);
      padNode.gain.gain.setValueAtTime(padGain * 0.10, now + 0.035);
      padNode.gain.gain.exponentialRampToValueAtTime(
        Math.max(padGain, 0.001), now + 0.335
      );
    }
    // Same pattern for arp...
  },

  // Call this whenever mixer volume changes
  updateHomeGains() {
    this._padHomeGain = Tone.dbToGain(MUZE.Mixer.channels.pad.volume);
    this._arpHomeGain = Tone.dbToGain(MUZE.Mixer.channels.arp.volume);
  }
};
```

### ISSUE 3: Riser Noise Source Runs Permanently
**Severity: HIGH**
**Location:** `audio.js:278-279`

```javascript
this.riserSynth = new Tone.Noise('pink').connect(this._riserGain);
this.riserSynth.start(); // <-- starts immediately, never stops
```

The pink noise oscillator is started at init and runs forever, even when `_riserGain` is at 0. While the gain suppresses audible output, the noise generator is still **computing samples every audio frame**. On mobile, this is wasted CPU.

**Fix:**
```javascript
// In init(): don't start the noise
this.riserSynth = new Tone.Noise('pink').connect(this._riserGain);
// DO NOT call .start() here

// In startRiser():
startRiser() {
  if (this.riserSynth.state !== 'started') this.riserSynth.start();
  this._riserGain.gain.rampTo(0.3, 4);
  // ... rest of method
},

// In dropRiser() and cancelRiser(), after fading to 0:
// Schedule stop after fade completes
setTimeout(() => {
  if (this.riserSynth.state === 'started') this.riserSynth.stop();
}, 350); // after the 0.3s fade
```

### ISSUE 4: PolySynth Voice Exhaustion with No releaseAll Before Chord Change
**Severity: HIGH**
**Location:** `audio.js:398-408` — `triggerPad()`

```javascript
triggerPad(notes) {
  this.padSynth.releaseAll();  // releases but doesn't instantly free voices
  this._padSub.releaseAll();
  this.padSynth.triggerAttack(notes, Tone.now(), 0.4);
```

`releaseAll()` starts the release envelope (2.5 seconds for the pad!) but does **not** free the voice. If the user changes chords quickly (say twice within 2.5s), the old voices are still in their release phase and still "allocated." With `maxPolyphony: 4` and 3-note chords, you exhaust voices after 2 rapid chord changes. Tone.js logs "Max polyphony exceeded. Note dropped" and drops notes silently.

**Fix — increase maxPolyphony to account for release tail overlap:**
```javascript
this.padSynth = new Tone.PolySynth(Tone.FMSynth, {
  maxPolyphony: 8,  // 3 current + 3 releasing + 2 safety margin
  // ...
});

this._padSub = new Tone.PolySynth(Tone.Synth, {
  maxPolyphony: 8,  // same reasoning
  // ...
});
```

Alternatively, force a hard stop before re-triggering (worse sonically but safe):
```javascript
triggerPad(notes) {
  // Force-kill all voices immediately
  this.padSynth.releaseAll(Tone.now());
  // Wait a tiny bit for voices to actually free
  const t = Tone.now() + 0.01;
  this.padSynth.triggerAttack(notes, t, 0.4);
```

---

## 3. PERFORMANCE ISSUES

### ISSUE 5: 9x EQ3 Instances = ~54 BiquadFilterNodes
**Severity: MEDIUM-HIGH**
**Location:** `_createChannelStrip()` — line 297

Each `Tone.EQ3` internally creates 3 `BiquadFilterNode`s plus a `ChannelSplitterNode` and `ChannelMergerNode` (approximately 5-6 Web Audio nodes). You have:
- 8 channel strips x 1 EQ3 = 8 EQ3 instances
- 1 master EQ3
- 1 reverb damping EQ3

That is **10 EQ3 instances = ~60 BiquadFilterNodes**. Most of these are initialized to flat (0, 0, 0) and never changed by the user.

**Fix — Lazy EQ creation:**
```javascript
_createChannelStrip(name, source) {
  const ch = MUZE.Mixer.channels[name];
  const panner = new Tone.Panner(ch.pan);
  const gain = new Tone.Gain(Tone.dbToGain(ch.volume));
  const reverbSend = new Tone.Gain(ch.reverbSend);
  const delaySend = new Tone.Gain(ch.delaySend);

  // Skip EQ if all bands are flat — create on demand
  let eq = null;
  let eqInput = source; // bypass EQ by default

  if (ch.eqLow !== 0 || ch.eqMid !== 0 || ch.eqHigh !== 0) {
    eq = new Tone.EQ3(ch.eqLow, ch.eqMid, ch.eqHigh);
    source.connect(eq);
    eqInput = eq;
  }

  eqInput.connect(panner);
  panner.connect(gain);
  // ... rest of routing

  this._nodes[name] = {
    eq, panner, gain, reverbSend, delaySend, source,
    _eqBypassed: eq === null
  };
},

// Lazy EQ insertion when user first adjusts
_ensureEQ(name) {
  const node = this._nodes[name];
  if (!node._eqBypassed) return node.eq;
  const ch = MUZE.Mixer.channels[name];
  const eq = new Tone.EQ3(ch.eqLow, ch.eqMid, ch.eqHigh);
  node.source.disconnect(node.panner);
  node.source.connect(eq);
  eq.connect(node.panner);
  node.eq = eq;
  node._eqBypassed = false;
  return eq;
}
```

This saves ~48 BiquadFilterNodes at startup, since most channels will never have their EQ touched.

### ISSUE 6: Reverb Damping EQ3 — Overkill, Use a Single Filter
**Severity: MEDIUM**
**Location:** `audio.js:113`

```javascript
this._reverbDamping = new Tone.EQ3({ low: 0, mid: 0, high: -6 })
```

You only need to cut highs. A full EQ3 (~6 nodes) is wasteful for what a single `Tone.Filter` (1-2 nodes) with `lowshelf` or a simple lowpass can do.

**Fix:**
```javascript
// Replace EQ3 with a single lowpass/lowshelf filter
this._reverbDamping = new Tone.Filter({
  frequency: 4000,
  type: 'lowpass',
  rolloff: -12
}).connect(this._masterSaturation);
this._reverbBus = new Tone.Reverb({ decay: 3.2, preDelay: 0.035 })
  .connect(this._reverbDamping);
```

Saves ~4-5 nodes.

### ISSUE 7: Master Filter at -24dB Rolloff Uses 2 BiquadFilterNodes
**Severity: LOW-MEDIUM**
**Location:** `audio.js:105`

```javascript
this._masterFilter = new Tone.Filter({ frequency: 2000, type: 'lowpass', rolloff: -24, Q: 1.2 })
```

In Tone.js, `-24` rolloff means 2 cascaded BiquadFilterNodes. Since this filter is modulated in real-time by head pitch (line 330: `this._masterFilter.frequency.rampTo(filterFreq, 0.08)`), and the full range is 800-10000 Hz, a `-12` rolloff (single BiquadFilter) would cut the node count in half while still being very audible as a tonal control.

**Fix:**
```javascript
this._masterFilter = new Tone.Filter({
  frequency: 2000, type: 'lowpass', rolloff: -12, Q: 2.5  // sharper Q compensates for gentler slope
})
```

### ISSUE 8: Two Analysers Running Every Frame
**Severity: MEDIUM**
**Location:** `audio.js:76,83`

Both `Tone.Analyser('waveform', 256)` and `Tone.Analyser('fft', 512)` perform FFT computations every audio render quantum (128 samples). The FFT analyser with 512 bins is especially costly. If the visualizer only needs waveform data for the main animation, the FFT analyser should be created on-demand or disabled when not visible.

**Fix:**
```javascript
// Create FFT analyser lazily
_fftAnalyserCreated: false,

getFFT() {
  if (!this._fftAnalyserCreated) {
    this.fftAnalyser = new Tone.Analyser('fft', 512);
    this._masterGain.connect(this.fftAnalyser);
    this._fftAnalyserCreated = true;
  }
  return this.fftAnalyser ? this.fftAnalyser.getValue() : null;
}
```

Or if both visualizations are always shown, reduce the FFT size to 256.

### ISSUE 9: Tone.Chorus on Pad Runs Continuously
**Severity: LOW-MEDIUM**
**Location:** `audio.js:149`

The chorus effect uses an LFO-modulated delay internally, computing even when the pad is silent. Unlike the riser noise, this is less impactful since the chorus is a lightweight effect, but on mobile every node matters.

Consider: chorus could be started/stopped with pad trigger/release, though the complexity may not be worth it given the chorus is relatively cheap.

---

## 4. TIMING & SCHEDULING ISSUES

### ISSUE 10: setTimeout for Musical Events — Unreliable Timing
**Severity: HIGH**
**Location:** `audio.js:470,615,630`

Three instances of `setTimeout` are used for musically-timed events:

1. **Line 470** — Reverb throw recovery after 300ms
2. **Line 615** — Reverb throw recovery after 200ms
3. **Line 630** — Tape stop recovery after 500ms

`setTimeout` runs on the main thread and is subject to 4ms minimum delay, GC pauses, and tab throttling (background tabs can delay setTimeout to 1000ms+). These should use `Tone.Transport.scheduleOnce` which uses the audio clock.

**Fix:**
```javascript
// BEFORE (unreliable):
setTimeout(() => {
  for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
    const node = this._nodes[ch];
    if (!node || node._reverbSendPre === undefined) continue;
    node.reverbSend.gain.rampTo(node._reverbSendPre, 2);
  }
}, 300);

// AFTER (sample-accurate):
Tone.Transport.scheduleOnce((time) => {
  for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
    const node = this._nodes[ch];
    if (!node || node._reverbSendPre === undefined) continue;
    node.reverbSend.gain.rampTo(node._reverbSendPre, 2, time);
  }
}, '+0.3');  // 300ms from now, audio-clock precise
```

Apply the same pattern to all three setTimeout instances for musical timing.

### ISSUE 11: updateParams() Called Every Animation Frame — Excessive rampTo Scheduling
**Severity: MEDIUM**
**Location:** `app.js:86` calls `MUZE.Audio.updateParams(S)` on every `requestAnimationFrame` tick.

At 60fps, this means 60 calls/second to `updateParams()`, each scheduling `rampTo()` automations on:
- `_masterFilter.frequency` (line 330)
- `_masterFilterGain.gain` (line 331)
- Up to 3 channel `reverbSend.gain` values (line 338-339)
- Up to 3 channel `delaySend.gain` values (line 339)
- `_arpFilter.frequency` (line 350)
- `_padChorus.depth` (direct assignment, fine)

Each `rampTo()` call creates a scheduled automation event on the audio thread. At 60fps, you're scheduling ~480 automation events per second. Most of these are redundant because the face values haven't changed significantly between frames.

**Fix — Add a dead-zone / dirty check:**
```javascript
updateParams(state) {
  const C = MUZE.Config;

  // Only update filter if head pitch changed meaningfully
  const pitchN = 1 - Math.max(0, Math.min(1, (state.headPitch + 0.4) / 0.8));
  if (Math.abs(pitchN - (this._lastPitchN || 0)) > 0.005) {
    this._lastPitchN = pitchN;
    const filterFreq = C.FILTER_FREQ_MIN *
      Math.pow(C.FILTER_FREQ_MAX / C.FILTER_FREQ_MIN, pitchN);
    this._masterFilter.frequency.rampTo(filterFreq, 0.08);
    this._masterFilterGain.gain.rampTo(1 + (1 - pitchN) * 0.35, 0.08);
  }

  // Only update sends if eye openness changed meaningfully
  if (Math.abs(state.eyeOpenness - (this._lastEyeOpenness || 0)) > 0.01) {
    this._lastEyeOpenness = state.eyeOpenness;
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const data = MUZE.Mixer.channels[ch];
      const node = this._nodes[ch];
      if (!node || !data.faceLinked) continue;
      node.reverbSend.gain.rampTo(state.eyeOpenness * data.reverbSend, 0.1);
      node.delaySend.gain.rampTo(state.eyeOpenness * data.delaySend, 0.1);
    }
  }

  // Same pattern for mouth openness -> arp filter
  if (Math.abs(state.mouthOpenness - (this._lastMouth || 0)) > 0.01) {
    this._lastMouth = state.mouthOpenness;
    if (this._arpFilter) {
      const mouthN = Math.max(0, Math.min(1, state.mouthOpenness));
      this._arpFilter.frequency.rampTo(800 + mouthN * 6000, 0.08);
    }
  }

  // Chorus depth: direct assignment is fine, no rampTo needed
  // ... rest unchanged
}
```

This reduces automation scheduling from ~480/sec to ~30-60/sec (only when values actually change).

---

## 5. GAIN STAGING ISSUES

### ISSUE 12: Potential Summing Overload at Master Bus
**Severity: MEDIUM**
**Location:** `mixer.js` channel defaults + `_masterSaturation` convergence point

Current channel volumes in dBFS:
- pad: -14, arp: -8, melody: -6, kick: -6, snare: -10, hat: -16, binaural: -24, riser: -6

Converting to linear gain and summing worst-case (all channels active):
```
pad:      0.20  (×3 notes = ~0.60 peak)
arp:      0.40  (×8 voices potential)
melody:   0.50
kick:     0.50
snare:    0.32
hat:      0.16
riser:    0.50
+ reverb return (correlated energy from all sends)
+ delay return
```

Worst-case sum: **~3.0-4.0 linear gain** before the limiter, which is **+9 to +12 dBFS**. The limiter threshold is at -3 dBFS. This means the limiter is doing **12-15 dB of gain reduction** in busy passages. That is aggressive limiting that will cause audible pumping and distortion.

**Best practice:** Mix channels so the sum naturally peaks around -6 to -3 dBFS, with the limiter only catching occasional transients (2-3 dB of reduction max).

**Fix — Lower channel defaults:**
```javascript
channels: {
  pad:      { volume: -18, ... },  // was -14
  arp:      { volume: -14, ... },  // was -8
  melody:   { volume: -12, ... },  // was -6
  kick:     { volume: -10, ... },  // was -6
  snare:    { volume: -14, ... },  // was -10
  hat:      { volume: -20, ... },  // was -16
  binaural: { volume: -28, ... },  // was -24
  riser:    { volume: -10, ... },  // was -6
},
master: { volume: -3, ... },       // was 0
```

This gives a natural sum around -6 to -3 dBFS, letting the limiter work as a safety net rather than a crutch.

### ISSUE 13: Reverb and Delay Returns Have No Level Control
**Severity: LOW-MEDIUM**
**Location:** `audio.js:115,119`

The reverb and delay buses connect directly to `_masterSaturation` with no return-level gain node. The return level is entirely determined by the individual channel send levels. This means:
- You can't globally turn down the reverb return without changing every channel's send
- The reverb adds correlated energy that pushes the master sum even further over 0 dBFS

**Fix:**
```javascript
this._reverbReturn = new Tone.Gain(0.7).connect(this._masterSaturation);
this._reverbDamping.connect(this._reverbReturn);  // insert return gain

this._delayReturn = new Tone.Gain(0.6).connect(this._masterSaturation);
this._delayBus.connect(this._delayReturn);  // insert return gain
```

---

## 6. MOBILE-SPECIFIC CONCERNS

### ISSUE 14: Convolution Reverb (Tone.Reverb) CPU Cost on Mobile
**Severity: MEDIUM**
**Location:** `audio.js:115`

`Tone.Reverb` generates an impulse response buffer and feeds it into a `ConvolverNode`. ConvolverNode is one of the most CPU-intensive Web Audio nodes. On low-end Android devices and older iPhones, this alone can consume 15-25% of the audio thread budget.

**Mitigation options (from least to most invasive):**
1. **Reduce reverb decay time** from 3.2s to 2.0s (shorter IR = less computation)
2. **Use Tone.Reverb with a shorter pre-generated IR** (reduce `preDelay` to 0)
3. **On mobile, fall back to FeedbackDelay-based fake reverb:**

```javascript
// Detect mobile
const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);

if (isMobile) {
  // Cheap reverb approximation: short multi-tap delay
  this._reverbBus = new Tone.FeedbackDelay({
    delayTime: 0.05,
    feedback: 0.6,
    wet: 1
  });
  // No await needed, no ConvolverNode
} else {
  this._reverbBus = new Tone.Reverb({ decay: 3.2, preDelay: 0.035 });
  await this._reverbBus.ready;
  this._reverbBus.wet.value = 1;
}
```

---

## 7. ADDITIONAL OBSERVATIONS

### Tape Stop Effect — Detune Race Condition
**Location:** `audio.js:625-637`

```javascript
[this.padSynth, this._padSub, this.leadSynth, this.melodySynth].forEach(s => {
  if (s) { s.set({ detune: 0 }); s.set({ detune: -2400 }); }
});
```

Two consecutive `.set()` calls in the same synchronous block. The first `set({ detune: 0 })` is immediately overwritten by `set({ detune: -2400 })`. The intent is probably to snap to 0 first then ramp down, but `.set()` is not a ramp — it's an instant value change. The first call is effectively dead code.

**Fix:**
```javascript
// Just set the target directly:
[this.padSynth, this._padSub, this.leadSynth, this.melodySynth].forEach(s => {
  if (s) s.set({ detune: -2400 });
});
```

Or if a ramp is desired:
```javascript
// Use Tone.js automation for a smooth pitch drop
this.padSynth.detune.rampTo(-2400, 0.4);
```

### Missing Cleanup / Dispose Method
The `MUZE.Audio` object has no `destroy()` or `dispose()` method. If the app ever needs to tear down and reinitialize audio (e.g., switching audio output devices, or a PWA lifecycle event), there is no way to properly clean up the ~175 nodes. This creates a memory leak risk.

### Arp Filter Envelope — Double Modulation Conflict
**Location:** `audio.js:350` (face-driven mouth openness) + `audio.js:544-546` (per-note pluck)

The arp filter frequency is modulated by two independent sources:
1. `updateParams()` sets it based on mouth openness every frame
2. The arp loop callback sets it to 6000 and ramps to 1200 on each note

These compete with each other. If mouth openness is low (filter at 800Hz) and a note triggers (jumps to 6000Hz), the next frame's `updateParams()` will immediately try to ramp it back to 800Hz, fighting the pluck envelope. The result: inconsistent pluck character depending on face state.

**Fix:** Use a dedicated filter for the per-note pluck, separate from the face-controlled filter:
```javascript
// In init, create two filters in series:
this._arpFilter = new Tone.Filter({ frequency: 2000, type: 'lowpass', rolloff: -12, Q: 2 }); // face control
this._arpPluckFilter = new Tone.Filter({ frequency: 6000, type: 'lowpass', rolloff: -12, Q: 1 }); // per-note

this.leadSynth.connect(this._arpPluckFilter);
this._arpPluckFilter.connect(this._arpFilter);
this._createChannelStrip('arp', this._arpFilter);
```

---

## 8. PRIORITY ACTION PLAN

| Priority | Issue | Impact | Effort |
|----------|-------|--------|--------|
| P0 | #1 iOS AudioContext recovery | App-breaking on iOS | 15 min |
| P0 | #4 PolySynth voice exhaustion | Silent notes, broken chords | 5 min |
| P1 | #2 Sidechain gain drift | Gain goes to zero over time | 30 min |
| P1 | #10 setTimeout for musical events | Timing drift, background tab failure | 20 min |
| P1 | #3 Riser noise runs forever | Wasted CPU on mobile | 10 min |
| P1 | #12 Gain staging overload | Limiter pumping, distortion | 15 min |
| P2 | #5 Lazy EQ creation | ~48 fewer nodes at startup | 45 min |
| P2 | #11 updateParams dead-zone | ~8x fewer automation events | 20 min |
| P2 | #8 Lazy FFT analyser | Save FFT computation | 10 min |
| P2 | #6 Reverb damping single filter | ~4-5 fewer nodes | 5 min |
| P2 | #13 Return level controls | Better mix control | 10 min |
| P3 | #14 Mobile reverb fallback | Less CPU on mobile | 30 min |
| P3 | #7 Master filter -12dB rolloff | 1 fewer node | 2 min |
| P3 | #9 Chorus lifecycle | Minor CPU save | 15 min |

**Total estimated effort for P0+P1 fixes: ~1.5 hours**
**Total for all fixes: ~3.5 hours**

---

## Sources

- [Web Audio API Best Practices — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Best_practices)
- [Web Audio API Performance and Debugging Notes](https://padenot.github.io/web-audio-perf/)
- [Tone.js Performance Wiki](https://github.com/Tonejs/Tone.js/wiki/Performance)
- [Tone.js Transport Scheduling Wiki](https://github.com/tonejs/tone.js/wiki/Transport)
- [AudioWorklet Optimization — Casey Primozic](https://cprimozic.net/blog/webaudio-audioworklet-optimization/)
- [Profiling Web Audio Apps in Chrome](https://web.dev/articles/profiling-web-audio-apps-in-chrome)
- [AudioContext Stuck on "interrupted" in Safari — WebAudio Issue #2585](https://github.com/WebAudio/web-audio-api/issues/2585)
- [Tone.js PolySynth Max Polyphony Issue #939](https://github.com/Tonejs/Tone.js/issues/939)
- [Sidechain Compressor AudioWorklet — GitHub](https://github.com/jadujoel/sidechain-compressor-audio-worklet)
- [Tone.js Reverb CPU — FeedbackCombFilter Alternative Issue #672](https://github.com/Tonejs/Tone.js/issues/672)
- [A Tale of Two Clocks — Web Audio Scheduling](https://www.html5rocks.com/tutorials/audio/scheduling/)
- [Tone.js Draw — Syncing Visuals with Audio](https://tonejs.github.io/docs/r13/Draw)
- [Gain Staging Best Practices — iZotope](https://www.izotope.com/en/learn/gain-staging-what-it-is-and-how-to-do-it)
- [Convolution vs Algorithmic Reverb](https://www.masteringbox.com/learn/convolution-and-algorithmic-reverb)
- [Unlock Web Audio in Safari — Matt Montag](https://www.mattmontag.com/web/unlock-web-audio-in-safari-for-ios-and-macos)
- [Spotify Web Audio Bench](https://github.com/spotify/web-audio-bench)
