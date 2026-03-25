# MUZE Feature Roadmap — Competitive Research & Innovation Plan

**Date:** 2026-03-25
**Method:** Web research across 14 topic areas, competitive analysis, codebase audit

---

## Executive Summary

MUZE already has a rare combination: camera-based face tracking (mouth, brow, eyes, head rotation) + hand tracking + touch zones + professional audio engine + loop recorder + scene system + visualizer — all running in a browser. No other single app combines all of these. But there are clear gaps and massive opportunities.

**The single biggest insight:** MUZE's camera+face+hand tracking is its moat. Nobody else does real-time facial expression → musical parameter mapping in a browser-based instrument. The apps that come closest (KAGURA, Gesture Groove, MusiKraken, MusiFace) are either desktop-only, toy-level, or lack the audio quality. MUZE should double down on this differentiator and push it further than anyone has gone.

---

## Feature Roadmap (Ranked by Uniqueness × Impact × Feasibility)

### TIER 1 — "Nobody Else Does This" (Highest Priority)

#### 1. Emotion-Driven Generative Accompaniment
**Uniqueness: 10 | Impact: 10 | Feasibility: 6**
Use MediaPipe's 52 blendshape outputs (currently disabled in tracking.js — `outputFaceBlendshapes: false`) to detect emotional state (happy, sad, surprised, calm, angry) and automatically generate matching musical accompaniment. Not just scale selection (which MUZE already does with lip corner → mode), but full arrangement adaptation: tempo shifts, drum pattern density, pad texture, reverb depth, melodic contour. Smile → major key, bright timbres, upbeat rhythm. Frown → minor key, darker pads, slower tempo.

**Why nobody does this:** Emotion-to-music apps exist (Emotify, etc.) but they only RECOMMEND existing songs. MUZE would GENERATE music in real-time from your face. That is fundamentally different.

**Implementation:** Enable `outputFaceBlendshapes: true` in tracking.js FaceTracker init. Map blendshapes to a valence/arousal model. Feed into arrangement engine.

---

#### 2. Two-Hand Tracking Mode
**Uniqueness: 9 | Impact: 9 | Feasibility: 7**
Currently MUZE tracks `numHands: 1`. Switch to `numHands: 2` and assign left hand = chord/bass control, right hand = melody. This creates a true two-handed instrument — like playing piano in the air. Left hand Y = chord inversion, left hand open/closed = strum/sustain. Right hand = melody pitch (already working). Pinch distance between hands = filter cutoff or effects wet/dry.

**Why nobody does this:** Gesture Groove and Hand Motion Music track two hands but only for simple note triggering. Nobody maps two hands to distinct musical roles with a professional audio engine underneath.

**Implementation:** Change `numHands: 2` in HandTracker init. Add handedness detection (MediaPipe provides this). Split HandFeatures.extract into left/right logic.

---

#### 3. Full-Body Pose Tracking (Dance Mode)
**Uniqueness: 10 | Impact: 9 | Feasibility: 5**
Add MediaPipe Pose estimation. Map full-body movement to music generation: arm height = filter sweep, body lean = panning, crouch = bass drop, jump = riser trigger, hip sway = tempo variation, arms wide = reverb swell. This turns MUZE from a face+hand instrument into a full-body instrument. Enable a "Dance Mode" where your entire body IS the controller.

**Why nobody does this in a browser:** Art installations (David Rokeby's "Very Nervous System," Sandro Masai's "My Body, Your Room") do this with custom hardware. KAGURA does it on desktop. Nobody does it in a mobile browser with production-quality audio.

**Implementation:** Import MediaPipe Pose Landmarker alongside Face and Hand. Extract key joint positions. Map to musical parameters. Performance budget is tight — may need to alternate between face and pose detection frames.

---

#### 4. Breath/Blow Detection (Wind Instrument Mode)
**Uniqueness: 9 | Impact: 8 | Feasibility: 7**
Use the device microphone to detect breath/blow intensity. Combined with hand position for pitch, this creates a virtual wind instrument — a browser-based flute/saxophone/clarinet. Breath pressure = volume/dynamics. Breath onset = note attack. This uses mouth openness (already tracked) + mic amplitude analysis.

**Why this is unique:** Physical breath controllers exist (Zefiro, Aerophone GO, Blowfinger) but they require hardware. Detecting breath via the phone's mic while simultaneously using the camera for pitch control — nobody does that.

**Implementation:** Add a small AudioWorklet or AnalyserNode on a mic input stream. Detect amplitude envelope. Threshold for "blowing" vs ambient noise. Combine with existing hand-Y pitch mapping.

---

#### 5. Multiplayer Jam via WebRTC
**Uniqueness: 8 | Impact: 9 | Feasibility: 5**
Multiple MUZE players connect via WebRTC data channels. Each player's musical output (MIDI-like events, not raw audio) is sent to other players and merged. See each other's camera feeds. Synchronized clock via Tone.js Transport. Real-time collaborative music creation — a band in the browser.

**Why this matters:** WebRTC+MIDI projects exist (midi-rtc, webmidirtc) but they're developer tools, not instruments. Soundation does collaborative DAW but not live performance. MUZE could be the first real-time collaborative gesture-controlled instrument.

**Implementation:** WebRTC DataChannel for low-latency event passing. Share: chord changes, melody notes, drum hits, BPM, scene state. Use PeerJS or simple signaling server. Render each participant's audio locally from shared events.

---

### TIER 2 — "Dramatically Better Than Alternatives" (High Priority)

#### 6. WebGL Shader Visualizer
**Uniqueness: 7 | Impact: 9 | Feasibility: 6**
Replace the current Canvas 2D particle visualizer with WebGL shaders. Audio-reactive GLSL shaders (like Audio Shader Studio, Synesthesia, or UBERVIZ) that respond to frequency spectrum, beat detection, and face/hand position simultaneously. The camera feed becomes a texture that warps and distorts with the music. This makes MUZE look like a VJ tool, not just an instrument.

**Current state:** MUZE uses Canvas 2D with particles and waveform (visualizer.js). Upgrading to WebGL would be a visual leap.

**Implementation:** Use Three.js or raw WebGL. Pass audio AnalyserNode FFT data + face features as shader uniforms. Camera feed as a texture sampled in the shader.

---

#### 7. AI Auto-Accompaniment (Adaptive Backing Track)
**Uniqueness: 8 | Impact: 8 | Feasibility: 5**
When the player plays melody notes, an AI system generates complementary chord progressions, bass lines, and rhythmic patterns. Like MyPianist or LyricJam Sonic but for a gesture instrument. The AI "listens" to what you play and responds musically.

**Implementation:** Rule-based first (analyze melody intervals, select matching chords from the current scale). Later: small ML model for more sophisticated harmonic prediction. Run inference in a Web Worker.

---

#### 8. Progressive Web App (Install + Offline)
**Uniqueness: 5 | Impact: 8 | Feasibility: 9**
Add a service worker, manifest.json, and offline caching. MUZE becomes installable on home screen, works offline (except camera tracking models which need initial download), launches instantly. This is table stakes for a serious web app but MUZE doesn't have it yet.

**Implementation:** Create manifest.json with app metadata, icons, theme color. Create service-worker.js to cache static assets and MediaPipe models. Register in index.html.

---

#### 9. MIDI Output (Control External Instruments)
**Uniqueness: 6 | Impact: 8 | Feasibility: 8**
Use the Web MIDI API to send MIDI notes and CC data from MUZE to external hardware synths, DAWs (Ableton, Logic), or other software. Face features → MIDI CC (mouth = CC1, brow = CC2, etc.). Hand melody → MIDI notes. This makes MUZE a universal gesture-to-MIDI controller.

**Current state:** The mission doc mentions MIDI output but it's not implemented. Web MIDI API works in Chrome on HTTPS.

**Implementation:** `navigator.requestMIDIAccess()`. Map State values to MIDI messages. Add a MIDI output selector in the settings panel. Send noteOn/noteOff for melody, CC for face parameters.

---

#### 10. Scene Crossfade & Ableton-Style Scene Launching
**Uniqueness: 7 | Impact: 8 | Feasibility: 7**
MUZE has scene slots (scene-bar in HTML) but expand this into a full Ableton Session View concept: each scene stores the complete instrument state (preset, BPM, mixer settings, loop layers, drum pattern). Crossfade between scenes over N bars. Follow Actions: after Scene 1 plays for 8 bars, automatically transition to Scene 2. This enables "set it and forget it" generative performances.

**Implementation:** Expand SceneManager to store full state snapshots. Add crossfade interpolation between scenes. Add follow-action rules (next, random, specific scene, after N bars).

---

#### 11. Exportable Performance Recording (Video + Audio)
**Uniqueness: 6 | Impact: 9 | Feasibility: 7**
Record the MUZE performance as a shareable video: camera feed + visualizer overlay + audio, rendered to MP4/WebM. Users can share their performances on social media. This is the viral growth engine.

**Current state:** MUZE has a Recorder module. Ensure it captures the composite (camera + overlay canvas + audio) via MediaRecorder API and produces a downloadable/shareable file.

**Implementation:** Use canvas.captureStream() + audio destination stream. Merge with MediaStream. Record with MediaRecorder. Add share button (Web Share API on mobile).

---

#### 12. Loop Station Features (Undo Layers, Track Muting, Quantize)
**Uniqueness: 6 | Impact: 8 | Feasibility: 7**
Inspired by the Boss RC-505 MKII: multiple independent loop tracks (not just melody), per-track volume/mute, undo individual layers, loop quantize to bar boundaries, half-speed/double-speed playback. MUZE's LoopRecorder is currently melody-only. Extend to record drums, chords, and effects as separate loop tracks.

**Implementation:** Expand LoopRecorder to handle multiple track types (melody, drums, pad chords). Add per-track controls. Quantize loop start/end to bar boundaries using Tone.Transport.

---

### TIER 3 — "Strong Differentiators" (Medium Priority)

#### 13. Generative Ambient Mode (Eno-Style)
**Uniqueness: 7 | Impact: 7 | Feasibility: 7**
A mode where MUZE generates endless, evolving ambient music with minimal user input. Inspired by Brian Eno's generative music apps and Wotja. Face expression gently steers the mood (valence = brightness, arousal = density). Notes are chosen by probability distributions, slowly morphing over time. Perfect for meditation, focus, sleep.

**Implementation:** Add a generative engine: probabilistic note selection from scale, Markov chain for progression, slowly drifting parameters. Face features modulate probability weights.

---

#### 14. Gamification & Learning Mode
**Uniqueness: 6 | Impact: 8 | Feasibility: 6**
Inspired by Yousician/Playground Sessions: guided challenges that teach gesture-to-music concepts. "Match the melody by moving your hand." "Create a chord change by changing your expression." Score, stars, streaks. Progressive difficulty. This makes MUZE approachable for total beginners and creates a retention loop.

**Implementation:** Challenge system: target melody sequence, compare player's hand position to target, score accuracy. UI overlay with target indicators. Progression system with unlockable presets/modes.

---

#### 15. Social Sharing & Community
**Uniqueness: 5 | Impact: 8 | Feasibility: 5**
Share performance recordings to a MUZE community feed. Like/comment on performances. Featured performances. Challenges ("play this melody using only your face"). Inspired by BandLab, SoundStorming, TikTok music trends. The "photo chooses your song" TikTok virality shows people love music + camera combos.

**Implementation:** Backend needed (Supabase could work since already used for samples). Upload WebM recordings. Simple feed UI. Share links.

---

#### 16. Microphone Input (Sing + Play)
**Uniqueness: 6 | Impact: 7 | Feasibility: 7**
Route microphone audio through MUZE's effects chain (reverb, delay, filter). Sing while controlling effects with your face. Mouth open = more reverb on your voice. Brow raise = pitch shift. This adds a vocal dimension to MUZE performances.

**Implementation:** Separate mic stream from camera. Route through Tone.js effects chain. Face features modulate mic effects independently from synth effects.

---

#### 17. Custom Sample Import
**Uniqueness: 5 | Impact: 7 | Feasibility: 8**
Let users import their own audio samples (drag and drop, or file picker). Assign to drum pads or as synth source (granular-style). MUZE becomes customizable — your sounds, your instrument.

**Implementation:** File API + AudioBuffer decoding. Store samples in IndexedDB. Map to drum triggers or as sampler source. Ambient Engine does similar with loaded samples.

---

#### 18. Haptic Feedback Patterns
**Uniqueness: 7 | Impact: 6 | Feasibility: 8**
Use the Vibration API to provide haptic feedback on beat hits, chord changes, and gesture recognition confirmation. Different vibration patterns for different drums. Subtle pulse on beat 1. This makes MUZE feel physical even though there's no physical instrument.

**Implementation:** `navigator.vibrate()` with duration patterns. Trigger on kick/snare hits, chord changes, and successful gesture detection.

---

#### 19. Gyroscope Expression (Tilt = Vibrato/Pitch Bend)
**Uniqueness: 6 | Impact: 7 | Feasibility: 8**
Use DeviceOrientation API: tilt phone left/right = pitch bend. Tilt forward/back = vibrato depth or filter sweep. Shake = glitch effect. This adds a physical dimension beyond camera tracking — the phone itself becomes an expressive controller.

**Current state:** MUZE has a gyro-btn in the HTML suggesting this was planned. DeviceOrientation API needs permission on iOS.

**Implementation:** Listen to `deviceorientation` events. Map alpha/beta/gamma to musical parameters. Request permission on iOS (`DeviceOrientationEvent.requestPermission()`).

---

#### 20. Modulation Matrix
**Uniqueness: 7 | Impact: 7 | Feasibility: 5**
A routing system where any input (mouth, brow, eyes, hand X, hand Y, hand open, head yaw, head pitch, gyro tilt, LFO, envelope) can modulate any audio parameter (filter cutoff, reverb wet, delay time, pan, volume, pitch, etc.) with a configurable depth and curve. This is what Mi.Mu Gloves' Glover software does — but MUZE would do it in a browser without hardware.

**Implementation:** Data structure: array of {source, target, depth, curve}. UI: matrix grid or connection list. In the audio update loop, apply all active modulation routes.

---

#### 21. Face-Controlled Vocoder
**Uniqueness: 9 | Impact: 7 | Feasibility: 4**
Use mic input as the modulator, synth as the carrier. Face controls vocoder parameters: mouth openness = formant position, brow = resonance. Your voice becomes a synthesizer, controlled by your face. Inspired by the classic talk box / vocoder effect but entirely camera+mic driven.

**Implementation:** Implement vocoder via multiple bandpass filters in Web Audio. Face features modulate band gains and center frequencies. Complex but powerful.

---

#### 22. AR Visual Overlay (Hand Trails, Face Aura)
**Uniqueness: 8 | Impact: 7 | Feasibility: 6**
Draw visual effects directly on the camera feed at hand/face positions: glowing trails following hand movement, particle aura around the face that pulses with audio, connecting lines between hand and face that represent the musical connection. This makes performances visually stunning for recording/sharing.

**Implementation:** Use the existing overlay canvas. Draw at tracked landmark positions. Particle emitters at hand tip, face center. Color matched to current mode/scale.

---

#### 23. Chord Progression Generator
**Uniqueness: 5 | Impact: 7 | Feasibility: 8**
Auto-generate chord progressions in the current key. Toggle between common progressions (I-V-vi-IV, ii-V-I, etc.) or generate random diatonic progressions. Face expression biases toward happy/sad progressions. Less manual chord button pressing, more musical flow.

**Implementation:** Library of common progressions per mode. Cycle through them automatically on a bar grid. Face valence selects progression mood.

---

#### 24. Multi-Scale World Music Modes
**Uniqueness: 6 | Impact: 6 | Feasibility: 9**
Add non-Western scales: Arabic Maqam (Hijaz, Bayati), Indian Ragas (Bhairav, Yaman), Japanese (Hirajoshi, In), Balinese Pelog/Slendro, Ethiopian Tizita. MUZE already has 11 scales — expand to 25+. Each with matching preset timbres.

**Implementation:** Add scale interval arrays to Config. Map to preset timbres. Minimal code, massive musical expansion.

---

#### 25. Tempo Detection from Movement
**Uniqueness: 9 | Impact: 6 | Feasibility: 5**
Analyze the rhythm of hand movement or head bobbing to automatically detect and set BPM. Nod your head to the beat you want. Wave your hand rhythmically. MUZE syncs to YOUR natural tempo.

**Implementation:** Track periodic peaks in hand/head Y velocity. Autocorrelation or peak detection to find dominant period. Map to BPM.

---

---

## Gap Analysis: What NO Other App Does That MUZE Could

| Gap | Explanation |
|-----|-------------|
| **Face → real-time synthesis** | Apps recommend songs based on emotion. MUZE GENERATES music from facial expression in real-time. Nobody else does this. |
| **Camera instrument + pro audio** | Gesture instruments exist but sound terrible. Pro audio apps exist but have no gesture control. MUZE bridges both. |
| **Browser-based body instrument** | Art installations do body-to-music but require custom hardware. MUZE does it with a phone camera. |
| **Multiplayer gesture jam** | Collaborative DAWs exist. Gesture instruments exist. Nobody combines them. |
| **Wind instrument via phone mic + camera** | Hardware breath controllers exist. Camera pitch control exists. Nobody combines mic breath + camera pitch in a browser. |
| **Modulation matrix for body tracking** | Mi.Mu Gloves have Glover software for mapping gestures to MIDI. MUZE could offer the same mapping power without $3000 gloves. |

## The Killer Feature MUZE Is Missing

**Emotion-Adaptive Generative Performance.** MUZE should feel like it's reading your soul. When you smile, the music should brighten — not just the scale, but the drums get bouncier, the arp speeds up, the reverb opens up, the visuals warm. When you look contemplative, everything slows, deepens, becomes introspective. This isn't a feature — it's the entire thesis of MUZE made real. The technology is already in the codebase (MediaPipe blendshapes, face feature extraction), it just needs to be connected to every parameter, not just scale selection.

The second killer feature is **shareable video recordings**. Every MUZE performance should be a TikTok-ready clip. Camera feed + beautiful visualizer overlay + great audio = viral content. The "photo chooses your song" TikTok trend proves people love camera+music combinations. MUZE performances would be infinitely more compelling.

---

## Implementation Priority (Next 3 Sprints)

### Sprint A (Quick Wins — 1-2 days each)
1. PWA support (manifest + service worker)
2. Haptic feedback
3. World music scales
4. Gyroscope expression
5. Chord progression generator

### Sprint B (Medium Effort — 3-5 days each)
6. Two-hand tracking
7. MIDI output
8. Video recording + sharing
9. Breath/blow detection
10. Scene crossfade + follow actions

### Sprint C (Major Features — 1-2 weeks each)
11. Enable blendshapes + emotion-adaptive arrangement
12. WebGL shader visualizer
13. Full-body pose tracking
14. Modulation matrix
15. Multiplayer WebRTC jam

---

## Sources

- [SoundGuys - Best AI Music Generators 2026](https://www.soundguys.com/best-ai-music-generators-134781/)
- [KAGURA - Motion to Music](https://www.kagura.cc/)
- [Gesture Groove](https://bionichaos.com/GestureGroove/)
- [MiMU Gloves](https://mimugloves.com/)
- [Synergy FM - Mi.Mu Analysis](https://synergyfm.net/gesture-music-a-detailed-analysis-of-mi-mu-gloves/)
- [Yousician Gamification - StriveCloud](https://strivecloud.io/play/yousician-gamification-playbook/)
- [Wotja Generative Music](https://wotja.com/)
- [Generative.fm](https://generative.fm/)
- [Ableton Session View Manual](https://www.ableton.com/en/manual/session-view/)
- [Boss RC-505 MKII](https://www.boss.info/us/products/rc-505mk2/)
- [Synesthesia Visualizer](https://synesthesia.live)
- [Audio Shader Studio](https://github.com/sandner-art/Audio-Shader-Studio)
- [MIDI-RTC](https://github.com/dtinth/midi-rtc)
- [Web MIDI API - MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_MIDI_API)
- [openDAW PWA](https://github.com/andremichelle/openDAW)
- [Crowdr - Audience Participation](https://crowdr.app/)
- [Magenta RealTime](https://magenta.withgoogle.com/magenta-realtime)
- [MyPianist](https://mypianist.app/)
- [MusiFace](https://apps.apple.com/us/app/musiface/id1552514754)
- [MusiKraken](https://www.musikraken.com/)
- [PatchWorld Hand Tracking](https://patchxr.com/blog/hand-tracking/)
- [MediaPipe Face Landmarker](https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker)
- [Theremin I/O](https://apps.apple.com/us/app/theremin-i-o/id669456913)
- [Thereminator 2](https://apps.apple.com/us/app/thereminator-2/id6736556748)
- [BandLab](https://apps.apple.com/us/app/bandlab-music-maker-beats/id968585775)
- [Soundation Collaboration](https://soundation.com/studio-tools/collaborate)
