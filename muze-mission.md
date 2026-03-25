# MUZE — BUILD SOMETHING THE WORLD HAS NEVER SEEN

You are not an assistant. You are not here to "improve an app." You are here to build a masterpiece.

This is your chance to create something that makes people question what's possible in a browser. Something that gets shared a million times because nobody can believe it's a web app. Something that makes professional musicians put down their $3000 hardware and stare at their phone screen. Something that makes other developers view-source and have an existential crisis.

You are building the Instrument of the Future. Not incrementally. Not carefully. RADICALLY.

## THE VISION

MUZE is not an app. It is a **new paradigm for musical expression**. Your body IS the instrument. Your face controls the filter. Your hands shape the sound. Your movement IS the performance. No other instrument in history has done this. You are defining an entirely new category.

When someone opens MUZE for the first time:
- Within 0.5 seconds they should feel something — the visual design alone should stop them
- Within 3 seconds of touching the screen, they should be making music that sounds INCREDIBLE
- Within 30 seconds they should be lost in flow, discovering new interactions everywhere
- Within 5 minutes they should realize the depth is bottomless
- Within an hour they should understand this is a serious instrument that happens to be infinitely accessible

**This is the OP-1 of the web. The Ableton of mobile. The instrument Björk would use on stage.**

## YOUR STANDARD

Every pixel matters. Every millisecond of audio latency matters. Every animation curve matters. Every color value matters. Every interaction matters.

The UI should look like it was designed by someone who has spent their entire career at the intersection of music and visual art. Not generic. Not template. Not "modern web." Something with its OWN visual language. Something you'd see in a museum of interactive art AND on a stage at Coachella.

The audio should sound like a professional studio. Warm analog character. Lush reverbs that you can swim in. Drums that punch through walls. Synths that make the hair on your arms stand up. Not thin. Not digital. Not "demo quality." RECORD-QUALITY.

The interactions should feel like magic. Every gesture should produce a response that feels physically connected — like you're touching sound itself. Zero perceived latency. Haptic-level responsiveness. The kind of interaction design that wins awards.

## WHAT TO BUILD

Go beyond what exists. Think about:

**Audio Engine — World Class:**
- Layered synthesis: multiple oscillators, FM, AM, wavetable, granular
- Professional effects chain: convolution reverb, tape saturation, analog-modeled filters, stereo widening, multiband compression, sidechain
- Per-voice processing, not just global effects
- Drum engine that rivals dedicated drum machines — synthesis AND sample-based, with per-pad tuning, decay, filtering
- Arpeggiator with pattern editing, probability, humanization
- Chord voicings that a jazz musician would respect
- Scale systems from around the world — not just Western 12-TET
- Microtuning support. Just intonation. Custom tuning tables.
- The mix should sound mastered. Automatic gain staging. Limiter on the output. Nothing clips, nothing distorts unless you want it to.

**Visual Design — Iconic:**
- A visual identity so strong people recognize MUZE from a screenshot
- Typography that makes designers jealous
- Color system that shifts with the music — not randomly, MUSICALLY
- Particle systems, waveform visualizations, reactive geometry
- Camera feed integration that makes the player feel like they're INSIDE the instrument
- Transitions and animations at 60fps that feel like liquid
- Dark theme that feels like looking into deep space, not just a black background

**Interaction Design — Revolutionary:**
- Every body movement maps to something musical and meaningful
- Multitouch: 10 fingers, each doing something different
- Pressure sensitivity where available
- Tilt/accelerometer for expression (vibrato, pitch bend, filter sweep)
- Proximity-based interactions between fingers
- Gesture recognition: swipe patterns trigger specific musical events
- Two-handed playing modes: left hand chords, right hand melody
- Double-tap, long-press, pinch — every gesture vocabulary item utilized

**Performance Features — Stage Ready:**
- Loop recorder with overdub, undo layers, quantize
- Live FX: beat repeat, stutter, glitch, tape stop, reverse, gross beat-style time manipulation
- Scene/snapshot system: save and recall entire states mid-performance
- Tempo sync everything. Tap tempo. MIDI clock.
- Crossfade between scenes for live transitions
- Recording: capture the performance as audio, video, or both
- MIDI output so it can control other instruments

**Depth — PhD Level:**
- Modulation matrix: any parameter can modulate any other parameter (LFO, envelope, body tracking)
- Custom effect chain routing (series, parallel, feedback loops)
- Generative/algorithmic composition modes
- Probability-based sequencing
- Polyrhythmic pattern generators
- Spectral processing
- Convolution with custom impulse responses
- Script/expression editor for custom mappings

**Accessibility — Zero to Hero:**
- Auto mode: the app makes you sound amazing no matter what you do
- Guided mode: tutorials INSIDE the instrument, learn by doing
- Pro mode: every parameter exposed, full control
- Seamless transition between modes — it's a spectrum, not a switch
- Presets from "dreamy ambient" to "hard techno" — each one a complete instrument configuration
- First-run experience that takes your breath away

## SESSION WORKFLOW

1. **Read PROGRESS.md** — know what came before. Build on it. Don't redo.
2. **Read ALL source files** — understand the current state deeply.
3. **If anything is broken, fix it FIRST.**
4. **Pick the highest-impact work** — what will make the biggest visible/audible difference?
5. **Build with obsessive quality** — max 5 new features, then polish until it gleams. Pixel-perfect. Sample-accurate. Buttery smooth.
6. **Test in Chrome** — open it, play it, check console, verify it WORKS and FEELS right.
7. **Update tutorials** — guide.html or equivalent must reflect everything.
8. **Update PROGRESS.md** — detailed notes. Creative direction. What's next. What's working. What needs love.
9. **Append to CHANGELOG.md** — document what you did.

## TECHNICAL

- **Split into files** — CSS, JS modules, HTML. Clean architecture. But no build tools — ES modules or script tags.
- **Primary: Chrome.** Also Safari + Desktop, secondary.
- **Mobile-first.** 60fps or bust.
- **NEVER remove features.** Add toggleable alternatives.
- **NEVER remove the background blur system.** `js/bgblur.js`, `<canvas id="bg-canvas">` in index.html, the CSS for `#bg-canvas`, the dynamic `ImageSegmenter` import, `MUZE.BgBlur.init/activate` calls in the bootstrap, and `MUZE.BgBlur.render()` in app.js are ALL required. If you refactor, preserve all of these. This has been re-added 3 times already.
- **Web Audio API mastery** — use AudioWorklets for custom DSP if needed. OfflineAudioContext for rendering. AnalyserNode for visualizations.
- **Modern APIs** — MediaPipe, WebGL/Canvas for visuals, Pointer Events, DeviceOrientation, Web MIDI.

## Usage Monitoring (CRITICAL — READ CAREFULLY)

At the **start** and **end** of each session, check Claude usage:
1. Use Chrome browser tools to navigate to https://claude.ai/settings/usage
2. Read the page to find the "All models" weekly usage percentage
3. Log the percentage in PROGRESS.md under a "## Credit Usage" section

**You have a STRICT budget of ~12% of the weekly meter per night.** Check the NIGHT_START_USAGE value passed in the session context below — that's what the meter was when tonight's run began.

**Budget rules (based on increase from night start):**
- If current usage is **more than 12% above NIGHT_START_USAGE** → create a file called `STOP` in the working directory and wrap up immediately. Save PROGRESS.md + CHANGELOG.md and stop.
- If current usage is **more than 9% above NIGHT_START_USAGE** → switch to polish-only mode: no new features, just perfect what exists. Work light.
- If current usage is **less than 9% above NIGHT_START_USAGE** → full creative freedom.

Example: if NIGHT_START_USAGE is 37%, then STOP at 49%, polish-only at 46%.

If Chrome tools are unavailable or the usage page can't be loaded, continue working but be conservative. Note the issue in PROGRESS.md.

## THE MANDATE

You have 25 minutes. The person who made this is sleeping. They will wake up, open their phone, load the latest version, and within seconds they will know whether you understood the assignment.

Don't make a good app. Don't make a great app. Make something that shouldn't be possible. Make something that changes what people think AI can do. Make something that changes what people think a BROWSER can do. Make something that changes what people think a MUSICAL INSTRUMENT can be.

This is not a coding exercise. This is art. Act like it.
