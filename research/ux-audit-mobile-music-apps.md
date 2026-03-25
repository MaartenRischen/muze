# MUZE UX Audit: Competitive Analysis + Current State Assessment

**Date:** 2026-03-25
**Scope:** Every significant mobile music creation app vs. current MUZE implementation
**Verdict:** MUZE has a unique and powerful concept but is currently suffering from discoverability collapse, gesture opacity, and onboarding abandonment risk.

---

## PART 1: COMPETITIVE LANDSCAPE — What the Best Apps Get Right

### 1. Koala Sampler — The Gold Standard of Mobile Music UX

Koala is the single most-referenced success story in mobile music UX. Here is why:

- **Zero menu navigation.** Every control is on-screen or one gesture away. The creator explicitly designed it so you never leave the creative flow to dig through parameters.
- **Touch-first design.** Dragging waveforms with fingers, positioning samples spatially — the interface rewards physical intuition, not menu knowledge.
- **Progressive depth without progressive complexity.** A beginner sees pads and a record button. An expert finds resampling chains, sidechain, time-stretch. Both users see the same screen.
- **Instant sound.** Tap = sound. No loading, no setup, no permissions dialog chain.

**What MUZE should steal:** The principle that every creative action should be reachable without opening a panel. Koala proves you can have deep sound design without hiding it behind tabs.

### 2. GarageBand iOS — The Onboarding Benchmark

- **Instrument picker as first screen** — user chooses what kind of music they want to make before seeing any complexity. This is a critical "personalization moment."
- **Photorealistic instruments reduce cognitive load** for beginners — a piano looks like a piano. But this becomes a liability for experts ("wearing oven mitts").
- **Hidden features are the main complaint.** Power users report that GarageBand hides essential controls behind non-obvious gestures. Sound familiar?
- **2025 Liquid Glass redesign** prioritized visual coherence over feature density.

**What MUZE should steal:** The instrument-picker-as-onboarding pattern. MUZE could show a "what do you want to do?" screen (jam with face, play drums, explore sounds) instead of dumping everything at once.

### 3. Figure (Propellerhead/Reason) — Touch Instrument Design

- **No skeuomorphism.** Flat-colored polygons, large text, everything functional, nothing decorative.
- **2D parameter spaces.** Rectangles where X = one parameter, Y = another. Moving your finger creates interplay between two continuous values. This is brilliant for filters (frequency + resonance).
- **But: discrete values on continuous surfaces fail.** When you need to hit a specific pitch or beat, the rectangle interface falls apart because there's no indication of which region maps to what.
- **Single-screen design.** Drums, bass, lead — all visible simultaneously. No panel switching during performance.

**What MUZE should steal:** The 2D parameter space concept is perfect for MUZE's drum zone. Instead of three stacked rows, the drum zone could map X to pattern variation and Y to velocity, giving each tap musical meaning beyond just "trigger."

### 4. FL Studio Mobile — Skeuomorphic Trust

- **Every knob, button, and meter looks real.** This isn't just aesthetics — skeuomorphism creates affordance. Users know a fader slides, a knob turns, a meter bounces.
- **Instantly recognizable pictograms** for instrument selection.
- **Each version was user-tested** specifically for mobile intuitiveness.

**What MUZE should steal:** MUZE's current slider thumbs in the synth panel are small and lack clear affordance. FL Studio proves that oversized, tactile-looking controls increase confidence.

### 5. Cubasis 3 — Mixer Excellence on Small Screens

- **Three channel-zoom levels.** Users choose their density: see all channels tiny, or zoom into 4 channels with full detail.
- **Rearrangeable insert/send effects.** Users customize signal flow visually.
- **Full-screen mode** for focused mixing.

**What MUZE should steal:** The zoom-level concept for the mixer. MUZE's mixer shows all channels at once with no option to zoom into a subset. On iPhone SE, those fader targets are dangerously small.

### 6. Endlesss — Speed-to-Jam

- **The entire app is optimized for speed-to-first-sound.** You can be jamming within seconds.
- **But: no starting tutorial.** Help menu assumes base-level knowledge. This caused user confusion and was later patched with tutorial missions.
- **Quantizer design flaw:** only shifts notes backward, cutting off input when users play slightly ahead of beat. Timing-critical UX must be forgiving in both directions.

**What MUZE should steal:** The "speed to jam" metric should be MUZE's north star. Currently MUZE requires: tap Begin Session -> wait for camera + ML models -> press Play. That's three gates before any sound.

### 7. Korg Gadget — Orientation as Information Architecture

- **Portrait = production overview (arrangement, track status).** Landscape = focused instrument editing.
- **Orientation switching is the navigation.** No hamburger menus, no tab bars for the primary workflow.
- **Sound browser with live preview** — hear sounds before committing.

**What MUZE should steal:** MUZE doesn't use orientation at all. Portrait could show the performance view, landscape could reveal the synth panel and mixer side-by-side.

### 8. BandLab — Personalization-First Onboarding

- **First-run asks music preferences.** This creates investment before the user even plays a note.
- **"Open Studio" button is poorly designed** — not a clear focal point, collapses on scroll, uses unclear iconography. A cautionary tale.
- **Two primary headers: "Track Type" and "Tools."** Simple information architecture that sections creation into digestible chunks.

**What MUZE should steal:** Music-preference onboarding. MUZE could ask "What vibe?" (ambient, beats, experimental) and auto-load the matching preset + tutorial path.

### 9. Teenage Engineering OP-Z — Minimalist Parameter Control

- **Tap to select, drag to adjust.** Two-phase interaction prevents accidental changes.
- **Color-coded pages** — parameter groups have distinct visual identities.
- **Real-time graphs** show the numbers behind the music. Users see mixer balance and effect amounts at a glance.

**What MUZE should steal:** The tap-to-select, drag-to-adjust pattern would solve MUZE's slider precision problem in the synth panel. Also: color-coding parameters by instrument (pad = one color, arp = another) across all views.

### 10. General Principles from Research

**Progressive Disclosure (Nielsen Norman Group):**
- Reveal only essential information first
- Hide advanced features behind deliberate user actions
- Never force users through complexity they don't need yet

**Touch Instrument Design (Academic Research):**
- Missing haptic feedback is the primary limitation of touchscreen instruments
- Multi-touch capability should be exploited, not ignored
- Auditory feedback must compensate for lack of tactile response

**Mobile Onboarding (2025/2026 Best Practices):**
- Nearly 1 in 5 users abandon after a single use
- 75% of apps are used once then never again
- Speed-to-value is the single most important onboarding metric
- Just-in-time guidance beats front-loaded tutorials
- Personalization creates attachment before first interaction

---

## PART 2: MUZE CURRENT STATE — Brutally Specific Findings

### A. ONBOARDING: Grade F

**Problem 1: The Start Screen Tells You Nothing Actionable**

```
"Your body is the instrument. Create music with your face, hands, and touch."
```

This is marketing copy, not onboarding. It tells the user *what MUZE is* but not *what to do first*. Compare to Koala's approach: the first thing you see is pads you can tap. Sound comes out. Done.

**Problem 2: Three Gates Before Sound**

1. Tap "Begin Session" (waits for models to load)
2. Camera permission dialog
3. Must tap Play button (starts paused!)

The app starts paused with no explanation. The user sees their face on camera, sees the HUD saying "DORIAN" and "C - 85 BPM" — none of which means anything to them — and hears silence. This is an abandonment cliff.

**Problem 3: Tutorial Is Opt-In and Text-Heavy**

The tutorial is behind the `?` button, which a first-time user won't tap because they don't yet know they need help. The tutorial itself is a text-card slideshow with no visual highlighting of the UI elements being described. Step 4 says "Bottom bar: 6 chord buttons. Above that: 3 drum zones" — but there's no arrow, no highlight, no dimming of other UI. The user must read the text, mentally map it to the screen, then try the action. This is 1990s-era help documentation, not modern onboarding.

**Problem 4: No First-Run Detection**

MUZE has no concept of "is this the user's first session?" There's no localStorage flag, no progressive reveal on first launch, no contextual hints. Every session starts identically whether you're a first-timer or a power user.

### B. DISCOVERABILITY: Grade D

**Problem 5: Invisible Gestures**

The following interactions exist but have zero visual affordance:

| Gesture | Action | Visual Hint? |
|---------|--------|-------------|
| Double-tap drum zone | Toggle auto-rhythm | None |
| Swipe right | Next drum pattern | None |
| Swipe left | Previous drum pattern | None |
| Swipe up | Reverb throw | None |
| Swipe down | Tape stop | None |
| Hold 400ms | Start riser | None |
| Hold + swipe up | Drop riser | None |
| Triple-tap | Beat repeat/stutter | None |

That's 8 gesture interactions with no discoverability mechanism whatsoever. No edge indicators, no peek animations, no gesture hints on idle. A user who never reads the tutorial will never discover these. This is the exact same problem GarageBand users complain about.

**Problem 6: Hidden Features in `display:none` Blocks**

The HTML contains entire functional sections wrapped in `<div style="display:none">`:
- Gyroscope button
- Loop recorder bar
- Scene manager bar
- Sample switcher buttons
- Gyro indicator

These are accessed only through the synth panel's Performance tab, which itself requires tapping the gear icon, then the "Perform" tab. That's 2 taps to reach core performance features. The Performance tab is a junk drawer — it contains Preset, Tempo, Key & Scale, Chords, Scenes, Loop Recorder, and Samples all in one scrollable list.

**Problem 7: The Gear Icon Is Overloaded**

The synth-menu-btn (gear icon) opens a panel containing:
- Performance settings (BPM, key, scale, presets, scenes, loop recorder, samples)
- Arp sound design (oscillator, ADSR, pattern)
- Melody sound design (portamento, vibrato, oscillator, ADSR)
- Pad sound design (oscillator, harmonicity, mod index, ADSR)
- Binaural beats toggle

This is 5 fundamentally different feature categories behind one icon. It violates the principle that one button should map to one conceptual action.

### C. TOUCH TARGETS: Grade C

**Problem 8: Drum Zone Has No Visual Boundaries**

The three drum zones (hat, snare, kick) are invisible rectangles stacked vertically. The only indication of boundaries is a 1px border between hat/snare and snare/kick (lines 141, 146 of style.css). The zone labels ("hat", "snare", "kick") are `opacity: 0.6`, `font-size: 10px`, `color: var(--muze-text-muted)`. On a camera feed background, these are essentially invisible.

A new user tapping randomly in the lower half of the screen will trigger drums without understanding the spatial layout. This is the opposite of what Figure does well (clear rectangular regions with color).

**Problem 9: Chord Bar Touch Targets Are 52px Tall But Only ~55px Wide**

With 6 chord buttons across a phone screen (375px iPhone), each button is approximately 62px wide. The minimum recommended touch target is 44x44px (Apple HIG), so these pass — but barely. The Roman numeral labels ("I", "ii", "iii", "IV", "V", "vi") are music theory notation that means nothing to most users.

**Problem 10: Toolbar Buttons Are 36x36px**

The Play, Record, Help, and Settings buttons are 36px diameter circles. Apple's HIG minimum is 44x44px. These are 18% below minimum. On an iPhone SE (320pt width), these will be difficult to hit accurately, especially during a live performance where the user is also holding the phone.

**Problem 11: Synth Panel Sliders Are 6px Tall**

Range inputs in the synth panel have `height: 6px` for the track. The thumb is `20px x 12px`. For precise parameter control (adjusting attack from 0.01 to 0.05), this is far too small. Cubasis 3 solved this with three zoom levels; FL Studio uses oversized skeuomorphic knobs.

### D. VISUAL HIERARCHY: Grade B-

**Problem 12: Mode HUD Dominates But Provides Little Actionable Info**

The Mode HUD (`#mode-hud`) is the largest on-screen element besides the camera feed. It shows:
- Mode name (e.g., "DORIAN") — 26px, 700 weight, 6px letter-spacing
- Key + BPM (e.g., "C - 85 BPM")
- Valence bar with numeric value

This information is useful for an experienced user who understands modal theory. For everyone else, "DORIAN" is meaningless. The HUD's visual prominence suggests it's the most important element, but it's actually passive — the user can't interact with it (pointer-events: none).

The valence bar is similarly opaque. It shows a value from -1.00 to +1.00 with no explanation of what it represents (facial expression → scale selection).

**Problem 13: No Visual Distinction Between Interactive and Passive Elements**

The chord bar (interactive) and the mode HUD (passive) use similar visual treatment — both have solid backgrounds, subtle borders, and accent colors. The drum zones (interactive) are invisible. The toolbar buttons (interactive) look like floating orbs. There's no consistent visual language saying "this is tappable" vs "this is informational."

**Problem 14: Accent Color Changes Are Meaningful But Unexplained**

The `MODE_COLORS` mapping (config.js, line 59-71) assigns each mode a unique accent color (phrygian = purple, ionian = gold, etc.). This color change is subtle and affects the HUD and valence bar. It's a beautiful design detail, but because it's never explained, it reads as decorative rather than informational.

### E. FEEDBACK: Grade B

**Problem 15: Drum Hit Feedback Is Good But Brief**

The `.hit` class on drum cells provides instant visual feedback — background flash + label scale. The 180ms timeout is appropriate. However, this feedback only uses the accent color (amber), not per-drum differentiation. Hat, snare, and kick all flash the same way. FL Studio and Koala use distinct colors per drum.

**Problem 16: No Feedback for Gesture Actions**

When a user successfully swipes right (next pattern), there's no visual confirmation. The pattern changes, but the user can't see what pattern is active unless they look at the debug panel. Similarly, reverb throw and tape stop have audio effects but no visual acknowledgment.

**Problem 17: Riser Overlay Is Well-Designed**

The riser overlay (`#riser-overlay`) with pulsing radial gradient is one of the best feedback mechanisms in the app. It's full-screen, impossible to miss, and correctly communicates "something is building." This pattern should be extended to other gesture effects.

### F. PANEL TRANSITIONS: Grade B+

**Problem 18: Synth Panel Slides From Right, Mixer Slides From Bottom**

This is actually a good pattern — different panels from different edges helps the user build a spatial model. The transitions use `cubic-bezier(0.22, 0.61, 0.36, 1)` which is smooth and professional. No complaints on the animation quality.

**Problem 19: No Gesture to Dismiss Panels**

Both panels require tapping a close button or tapping outside. There's no swipe-to-dismiss, which is the expected pattern on iOS since 2018 (modal sheets). This makes the panels feel slightly web-app rather than native.

### G. INFORMATION ARCHITECTURE: Grade D+

**Problem 20: Feature Organization Is Inside-Out**

The current architecture from a user's perspective:

```
Start Screen
  └─ Main View
       ├─ Drum zones (invisible)
       ├─ Chord bar (visible)
       ├─ Mode HUD (visible, not interactive)
       ├─ Toolbar: Play | Record | Help | Settings
       │    └─ Settings (Gear) → Synth Panel
       │         ├─ Perform tab (BPM, key, scale, presets, scenes, loop rec, samples)
       │         ├─ Arp tab (sound design)
       │         ├─ Melody tab (sound design)
       │         ├─ Pad tab (sound design)
       │         └─ Binaural tab
       │              └─ MIX button → Mixer Panel
       │                   └─ Channel strips → Detail panels (EQ, sends, pan)
       └─ (Tutorial behind ? button)
```

The mixer is two levels deep (gear → MIX button inside panel header). Scene management and loop recording are inside the Perform tab of the synth panel. These are performance features being treated as settings.

**Correct architecture should be:**

```
Main View
  ├─ Performance Layer (always visible)
  │    ├─ Drum pads (visible, colored)
  │    ├─ Chord buttons
  │    ├─ Mode/status display
  │    └─ Transport (play/rec) + quick access (scenes, patterns)
  ├─ Mix Layer (one swipe up)
  │    └─ Faders, meters, pan, M/S
  └─ Sound Design Layer (one swipe from side)
       ├─ Arp
       ├─ Melody
       ├─ Pad
       └─ Drums (missing entirely!)
```

**Problem 21: No Drum Sound Design**

Users can change pad oscillator, arp ADSR, melody wave shape — but there's zero control over drum sounds. No kit selection, no tuning, no decay. The sample switcher (pad-sample-btn, lead-sample-btn) handles pad and lead but not drums. This is a gap every competitor fills.

### H. MISSING FEATURES (From Competitive Analysis)

| Feature | Who Has It | MUZE Status |
|---------|-----------|-------------|
| Sound preview before selection | Korg Gadget, BandLab | Missing |
| Orientation-based layout switching | Korg Gadget | Missing |
| Undo/redo for all actions | Every DAW | Only on loop recorder |
| Visual gesture hints on idle | Figure, GarageBand | Missing |
| Haptic feedback on touch | Koala, GarageBand | Missing (web limitation, but could use Vibration API) |
| First-run personalization | BandLab, Spotify | Missing |
| Pattern visualization | Endlesss, FL Studio | Missing (patterns are invisible) |
| Multi-touch drum performance | Koala, every drum app | Partially (handles touches but no multi-touch visual feedback) |
| Swipe-to-dismiss panels | iOS standard since 2018 | Missing |
| Contextual tooltips | OP-Z app | Missing |

---

## PART 3: PRIORITY RECOMMENDATIONS

### Tier 1 — Fix Now (User Retention Risk)

1. **Auto-play on launch.** Remove the paused start state. When the camera loads, start the music. The play button should exist for pause/resume, not as a gate.

2. **First-run contextual hints.** On first session (check localStorage), show 3-4 floating hints pointing at real UI elements: "Tap for drums", "Swipe for effects", "Your face controls the mood". Dismiss on first interaction. Kill the slideshow tutorial.

3. **Make drum zones visible.** Add subtle background tints (hat = light, snare = medium, kick = dark) or at minimum increase label size and opacity. Users must be able to see where to tap.

4. **Increase toolbar button size to 44x44px.** This is a one-line CSS change that fixes an HIG violation.

### Tier 2 — Fix Soon (Engagement Risk)

5. **Surface scenes and loop recorder** out of the synth panel. Put 4 scene slots in a bottom-left cluster. Put loop controls in a floating bar that appears when recording starts.

6. **Add gesture hint animations.** After 10 seconds of inactivity on the drum zone, show a subtle animated arrow suggesting "swipe" or "double-tap." Fade after first successful gesture.

7. **Split the gear menu.** Separate "Performance" (BPM, key, scale) from "Sound Design" (synth parameters). Performance controls could live in a top-bar dropdown; sound design stays in the side panel.

8. **Add visual feedback for swipe/gesture actions.** Brief text flash ("PATTERN 3", "REVERB THROW", "TAPE STOP") that appears for 800ms, similar to how volume HUDs work on iOS.

### Tier 3 — Fix Eventually (Competitive Parity)

9. **Orientation support.** Portrait = performance, landscape = mixer + sound design side by side.

10. **Drum sound design.** Kit selection, basic tuning/decay per drum.

11. **Haptic feedback via Vibration API.** Even a basic 10ms vibration on drum hits would dramatically improve feel.

12. **Color-code instruments consistently** across all views (drum = red, pad = blue, arp = green, melody = yellow). Use these colors in the mixer strips AND the synth panel tabs AND the chord bar.

13. **Swipe-to-dismiss for all panels.**

---

## SOURCES

- [GarageBand Redesign Case Study - Medium](https://medium.com/@sitoepeiyi/ui-ux-case-study-garageband-redesign-5ec54591a6f1)
- [GarageBand UX Case Study - Ethan Hein](https://www.ethanhein.com/wp/2012/user-interface-case-study-ios-garageband/)
- [GarageBand Liquid Glass Update - MacRumors](https://www.macrumors.com/2025/11/03/garageband-liquid-glass-update/)
- [Koala Sampler Creator Interview - SynthTalk](https://www.synthtalk.net/articles/marek-bereza-creator-of-the-koala-sampler/)
- [Koala Sampler Review - Sound On Sound](https://www.soundonsound.com/reviews/elf-audio-koala-sampler)
- [Shabaka Hutchings on Koala - MusicRadar](https://www.musicradar.com/artists/the-koala-app-is-amazing-its-the-best-sampler-and-the-deeper-you-go-the-madder-it-gets-shabaka-hutchings-on-his-journey-from-jazz-saxophone-to-ipad-beatmaking)
- [Koala History - Microchop Substack](https://microchop.substack.com/p/a-brief-history-of-the-koala-sampler)
- [FL Studio Mobile UI Design - Artua](https://www.artua.com/iphone-app-design-fl-mobile/)
- [FL Studio UX Discussion - Image-Line Forums](https://forum.image-line.com/viewtopic.php?t=332780)
- [Cubasis 3 Review - Sound On Sound](https://www.soundonsound.com/reviews/steinberg-cubasis-3)
- [Cubasis 3 Review - MusicRadar](https://www.musicradar.com/reviews/steinberg-cubasis-3)
- [Endlesss Review - Engadget](https://www.engadget.com/2020-03-31-endless-music-collaboration-app.html)
- [Endlesss Review - MusicTech](https://musictech.com/reviews/software-instruments/endlesss/)
- [Figure UX Case Study - Ethan Hein](https://www.ethanhein.com/wp/2012/user-interface-case-study-propellerheads-figure/)
- [Korg Gadget 3 Features - KORG](https://www.korg.com/us/products/software/korg_gadget/)
- [BandLab Design Critique - IXD@Pratt](https://ixd.prattsi.org/2025/09/design-critique-bandlab-music-making-studio-mobile/)
- [BandLab UX Blog](https://blog.bandlab.com/inside-our-tech-uiux-design/)
- [OP-Z UX Review - Craigspeed](https://craigspeed.com/ui-reviews-teenage-engineering-opz/)
- [Teenage Engineering Design Philosophy - Medium](https://medium.com/@ihorkostiuk.design/the-product-design-of-teenage-engineering-why-it-works-71071f359a97)
- [Progressive Disclosure - NN/G](https://www.nngroup.com/articles/progressive-disclosure/)
- [Progressive Disclosure for Mobile - UX Planet](https://uxplanet.org/design-patterns-progressive-disclosure-for-mobile-apps-f41001a293ba)
- [Mobile Onboarding Best Practices - UXCam](https://uxcam.com/blog/10-apps-with-great-user-onboarding/)
- [200 Onboarding Flows Studied - DesignerUp](https://designerup.co/blog/i-studied-the-ux-ui-of-over-200-onboarding-flows-heres-everything-i-learned/)
- [Touch Instrument Design - Springer](https://link.springer.com/chapter/10.1007/978-3-319-58316-7_12)
