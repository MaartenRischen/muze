# Changelog

## v7.0.0 — Magenta RealTime 2 AI core
- New **🧠 AI** instrument toggle: streams Google **Magenta RealTime 2** (the
  June 2026 open-weights live music model) as a generative layer, steered live by
  the same controls you already play — your active Vibe/preset + mode + key + tempo
  become a MusicCoCa style prompt, your chord voicing becomes Magenta's note
  pianoroll, the BEAT toggle drives its drums, and gestures map to its CFG /
  temperature (hand height → note adherence, mouth → style strength, brows → drum
  punch, hand-X → temperature). Long-press the AI chip for "free harmony" (let
  Magenta improvise around the chord).
- The model runs in a small **local MLX server** (`server/`) — it's a C++/MLX model
  and can't run in the browser — and streams 48 kHz stereo audio back over a
  WebSocket. Muze plays it **through the existing master chain** (EQ, saturation,
  limiter, visualizer), gapless, with a jitter buffer + auto-reconnect.
- Magenta is **additive and optional**: with no server reachable, Muze runs exactly
  as before on the Tone.js engine (the AI chip just shows a grey status dot). On
  iPhone, point the app at your Mac with `?mag=ws://<mac-ip>:8010/ws`.
- See `server/README.md` for the one-command setup. Measured ~1.3× real-time with
  `mrt2_small` on an M4 Max.

## v6.9.0 — Installable app + icon
- Added a PWA manifest + a real app icon (glowing aura orb over an equalizer),
  so Jammerman can be installed to the home screen as a standalone app
  (Add to Home Screen on iOS). Replaces the emoji favicon.

## v6.8.0 — Shareable sounds
- 'Copy link' (⚙ → Perform) encodes your preset, key, scale, groove, chord
  progression and palette into a URL. Open the link and the sound loads
  automatically (#muze=...), so you can share or bookmark a vibe.

## v6.7.0 — Toolbar tap/hold
- The ✨ toolbar button: tap for the next vibe, hold (~0.5s) for a 🎲 Surprise
  random combo. Both announce via the on-screen toast.

## v6.6.0 — Body paints the backdrop
- The aurora's warm light clouds now subtly echo the current melody note's
  color, so playing with your hand gently tints the backdrop. Degrades to pure
  accent when no melody is playing.

## v6.5.0 — Quick Reference
- Added a 'Quick Reference' card to the Help (?) menu: an at-a-glance gesture
  map (Face / Hand / One-tap magic / Touch) for when you don't want the full
  step-by-step tutorial. Reuses the tutorial card UI.

## v6.4.0 — Scenes capture the whole vibe
- Scene snapshots now save + restore the color palette, drum groove, chord
  progression, and visual toggles (aurora/face-glow/lite) in addition to the
  sound. Recall a scene and the full look + groove come back. Old scenes still load.

## v6.3.0 — More content
- +3 drum grooves (Bossa, Drill, Breakbeat) and +4 vibes (Rio, Night Drill,
  Jungle, Sakura). Surprise now draws from all grooves (Euclidean included).

## v6.2.0 — Accessibility
- Respect the OS **prefers-reduced-motion** setting: on first run (before any
  customization), default to Lite mode for users who've asked for reduced motion.
  A saved preference always wins.

## v6.1.0 — Discoverability
- Prominent **✨ Vibe** button in the top toolbar that cycles vibes with an
  on-screen toast, so the one-tap-great-sound path is findable without opening
  the settings panel.

## v6.0.0 — Instant arrangements (capstone)
- **Vibes now play a full arrangement instantly**: tapping a vibe (or Surprise)
  auto-enables Pad + Arp + Melody, plus Beat when the preset has live drums, so
  you hear a complete track immediately instead of un-muting instruments by hand.
- Added `InstrumentToggles.setActive(inst, on)` (idempotent programmatic toggle).
- Added `README.md` + this changelog.

## v5.9.0 — Robustness & content polish
- Fixed Euclidean grooves: they were 32-step but the sequencer is 16-step, so
  only the first bar ever played. Now single 16-step bars (audibly identical,
  consistent, fully playable).
- Scale-picker derives its index from state — Vibes/Scenes no longer desync it.
- +4 vibes (Tokyo, Desert, Bollywood, Aurora) using the new exotic scales.

## v5.8.0 — Color palettes
- Global palette override (Auto, Sunset, Ocean, Magenta, Mint, Gold, Mono) via
  `MUZE.Theme`, applied consistently across visualizer, mood lighting, and CSS
  accents. Persisted.

## v5.7.0 — Surprise Me
- One-tap randomizer: builds a fresh random combo (preset + scale + key + groove
  + progression) for endless variety. Shares the Vibe apply path.

## v5.6.0 — Visuals & performance settings
- New Visuals panel: Aurora toggle, Face-glow toggle, and a Lite mode that drops
  ambient layers and caps particle systems for lower-end phones. Persisted.

## v5.5.0 — Vibes
- One-tap curated combos (preset + fixed scale + key + drum groove + chord
  progression): Lofi Sunset, Neon Drive, Deep Calm, Midnight Jazz, Festival,
  Cosmic Drift, Liquid Flow, Dark Ritual.

## v5.4.0 — Real chord progressions
- Replaced the flat I→ii→iii auto-cycle with 10 curated progressions (Pop,
  Ballad, Doo-Wop, Jazz, Canon, Andalusian, Epic, Dreamy, Tension, Wander),
  one chord per bar, with a next-chord indicator.

## v5.3.0 — Aurora backdrop
- Audio-reactive aurora/nebula + twinkling starfield behind the user, drawn
  under the halo. Drifts and blooms with energy/bass, tinted by the accent.

## v5.2.0 — Sound expansion
- +6 scales (in-sen, iwato, egyptian, hungarian min, double harm, ukrainian).
- +6 presets (Cinematic, Synthwave, Vaporwave, Liquid DnB, Meditation, Trap Soul).
- +6 drum grooves (House, Boom Bap, Liquid DnB, Dembow, Afrobeat, UK Garage).
- Live version label sourced from a single `MUZE.VERSION`.

## v5.1.0 and earlier
- Send/return bus audio engine, face/hand tracking, background blur, halo,
  waveform ring, frequency arc, face-mesh AR, drum FX, mixer, loop recorder,
  scenes, presets, tutorials. See git history.
