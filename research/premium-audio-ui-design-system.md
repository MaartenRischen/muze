# Premium Audio UI Design System Brief

## Current Muze Diagnosis: Why It Looks "Cheap"

Analyzing the current CSS, these specific issues create a generic/budget impression:

1. **Monospace everywhere** -- `SF Mono` / `monospace` used for labels, values, tabs, headings. Monospace for data readouts is correct, but monospace for UI labels and headings reads as "developer tool" not "instrument."
2. **Flat, untextured backgrounds** -- `rgba(6,6,10,0.96)` is a pure dark void. No depth, no grain, no subtle gradient. Premium apps never use completely flat dark surfaces.
3. **Native range inputs with minimal styling** -- The `input[type=range]` with basic thumb styling is the single biggest "web app" tell. Every premium audio app uses custom-drawn controls.
4. **No surface hierarchy** -- Everything sits at the same visual depth. No recessed grooves for fader tracks, no raised surfaces for controls, no layered card system.
5. **Uniform opacity-based color system** -- Using `rgba(255,255,255, 0.04/0.08/0.12)` for everything creates a "grey soup" where nothing has material identity.
6. **Missing micro-details** -- No noise texture, no subtle gradients on surfaces, no light-source consistency, no state transitions with physicality.
7. **3px meter bars** -- The level meters are too thin and use a basic CSS gradient. Premium meters have glow, segmentation, peak hold indicators, and visual weight.

---

## Design Language Analysis: What Premium Looks Like

### 1. Ableton Live -- Precision Minimalism

**Philosophy:** Information density through restraint. Every pixel earns its place.

**Key Visual Elements:**
- Flat colored blocks with zero gradients -- but the colors are carefully desaturated and harmonious
- Grid-based layout with pixel-perfect alignment
- Clear spatial hierarchy through consistent spacing, not through shadows or depth
- Monochrome interface where color = meaning (track colors, automation)

**Color Palette:**
- Background greys: `#1E1E1E`, `#232323`, `#2D2D2D`, `#3D3D3D`, `#4A4A4A`
- Surface grey: `#333333`
- Accent colors (muted): `#FF764D` (orange), `#89CFF0` (blue), `#90EE90` (green)
- Text: `#A7A7A7` (secondary), `#CCCCCC` (primary), `#888888` (tertiary)
- Clip accents: `#FFB506`, `#4A9FFD`, `#69DFFF`, `#00FF7D`, `#FF5145`

**What makes it premium:** The restraint. No decoration, no texture. Pure information design. The precision of the grid communicates engineering quality.

**Relevance to Muze:** The spacing system and information hierarchy. Not the aesthetic itself (too utilitarian for a performance app).

---

### 2. Native Instruments -- Hardware Authority

**Philosophy:** Digital software that feels like touching machined aluminum and brushed steel.

**Key Visual Elements:**
- Warm grey panels (`#3A3A3C` to `#2C2C2E`) with subtle noise texture
- Color-coded modulation rings that "pop" against muted backgrounds
- Rounded, physically-modeled knobs with highlight/shadow suggesting a top-left light source
- Switchable skins: default warm grey, dark mode, flat variants
- Hidden parameter values to maintain minimal surface -- values appear on hover/touch

**Color Palette (Massive X default):**
- Panel background: `#3A3A3C` (warm grey, not pure grey)
- Darker panel: `#2C2C2E`
- Module divider: `#1A1A1C`
- Accent: `#00B4D8` (cyan), `#FF6B35` (orange modulation rings)
- Text primary: `#E0E0E0`
- Text secondary: `#808080`

**What makes it premium:** The warmth in the greys. Pure grey (#3A3A3A) reads as "computer." Slightly warm grey (#3A3A3C -- note the slightly different blue channel) reads as "machined metal." This is the single most important color insight.

**Relevance to Muze:** The warm grey tinting principle. The noise texture on surfaces. The light-source consistency.

---

### 3. Teenage Engineering -- Playful Precision

**Philosophy:** Complex technology made approachable through bold simplicity and color confidence.

**Key Visual Elements:**
- Very limited palette used with maximum confidence
- Functional color: each color maps to a specific function, creating instant learnability
- Geometric, almost toy-like proportions that disguise serious capability
- White/cream backgrounds with bold accent pops (unusual in audio)
- Screen UI that mirrors physical hardware layout with color bridges

**Color Palette:**
- Primary: `#FA5B1C` (signature orange), `#FF106A` (magenta)
- Functional: `#1270B8` (blue), `#1AA167` (green), `#CE2021` (red), `#FFC003` (yellow)
- Neutrals: `#F6F4F4` (light), `#BDBDBD` (mid), `#000000` (text)
- OP-XY monochrome: `#F6F4F4` through `#AFAFB3`, `#95959A`, `#797982` to `#000000`

**What makes it premium:** The confidence. Using 3-4 colors total, deployed with absolute consistency. No gradients, no textures -- just perfect color-function mapping. The "toy-like" quality is actually extreme reduction to essentials.

**Relevance to Muze:** The functional color mapping system. The idea that fewer, bolder colors = more premium than many subtle greys. The playful-yet-precise balance is exactly right for a music performance app.

---

### 4. Output -- Cinematic Depth

**Philosophy:** Music software as emotional experience. Every surface tells a story.

**Key Visual Elements:**
- Deep, rich dark backgrounds with subtle purple/blue tinting
- Large, expressive visual displays (waveforms, spectral views)
- Generous whitespace (dark-space) between controls
- Cinematic gradient overlays suggesting atmospheric lighting
- Polished, rounded controls with subtle glow states
- Drag-and-drop simplicity with high visual polish

**Color Palette (reconstructed from UI screenshots):**
- Background: `#0D0B14` (deep purple-black, NOT pure black)
- Surface: `#161422` (slightly lighter purple-black)
- Elevated surface: `#1E1A2E`
- Accent: `#8B5CF6` (violet), `#C084FC` (light violet)
- Secondary accent: `#06B6D4` (cyan)
- Text: `#E2E8F0` (slightly cool white)
- Muted text: `#64748B` (blue-grey)

**What makes it premium:** The color temperature. A pure black background (#000000) is a void. A purple-tinted dark (#0D0B14) is an atmosphere. This single technique is what separates "dark theme" from "premium dark theme."

**Relevance to Muze:** The color temperature tinting is the #1 takeaway. The generous spacing. The atmospheric feel.

---

### 5. Arturia -- Skeuomorphic Warmth

**Philosophy:** Digital recreations of beloved analog hardware, with modern interaction affordances.

**Key Visual Elements:**
- Photorealistic renderings of hardware panels, knobs, wood grain
- Warm lighting suggesting a studio environment
- Shadows consistent with overhead studio lighting
- Modern overlays (preset browsers, controls) layered on top of vintage surfaces
- Resizable interfaces maintaining visual fidelity at all sizes

**Color Palette:**
- Panels: Hardware-specific (cream, wood, black, blue depending on emulated unit)
- Modern overlay: `#1A1A2E` (dark blue-black)
- Control accent: `#FF8C00` (warm amber)
- LED indicators: `#00FF41` (matrix green), `#FF0000` (red)

**What makes it premium:** The hybrid layering -- vintage tactile surfaces for emotional connection, modern flat UI for functionality. The lighting consistency creates "believability."

**Relevance to Muze:** The lighting consistency principle. Even in a flat design, implying a consistent light source (top-left or top-center) through subtle gradients and shadows makes surfaces feel "real."

---

### 6. iZotope -- Data as Beauty

**Philosophy:** Audio analysis visualization elevated to an art form.

**Key Visual Elements:**
- Spectrum displays using carefully crafted color gradients (purple-to-blue-to-cyan-to-green-to-yellow-to-red)
- Dark blue-black backgrounds optimized for visual data
- Thin, precise lines for graphs and curves
- Turquoise metering (replacing traditional green)
- Bi-directional communication visualized through color-coded channel identification

**Color Palette:**
- Background: `#0A0E17` (very dark navy)
- Surface: `#141B2D` (dark navy)
- Spectrum gradient: `#7B2FBE` (purple) -> `#2563EB` (blue) -> `#06B6D4` (cyan) -> `#10B981` (green) -> `#EAB308` (yellow) -> `#EF4444` (red)
- Metering: `#2DD4BF` (turquoise -- the modern replacement for traditional green)
- Text: `#CBD5E1` (cool grey-white)

**What makes it premium:** Data visualization as first-class design. The spectrum gradients are not arbitrary -- they follow perceptual uniformity principles. The dark navy background (not black) optimizes perceived contrast for visual data.

**Relevance to Muze:** The turquoise metering color. The navy-tinted dark background. The principle that visualizations should be beautiful, not just functional.

---

### 7. Serum -- Visual Feedback as Interface

**Philosophy:** See what you hear. Every parameter change has an immediate visual reflection.

**Key Visual Elements:**
- Grey background that serves as a neutral canvas for colorful wavetable displays
- 3D wavetable visualization as the hero UI element
- Color-coded modulation with visible routing
- Real-time visual feedback for every parameter change
- Clean separation between oscillator (visual), modulation, and effects sections

**Color Palette:**
- Background: `#2B2B30` (warm dark grey)
- Panel: `#363639` (slightly lighter)
- Wavetable display: gradient fills (customizable, often blue-cyan or orange-yellow)
- Modulation: color-coded per source (blue, green, orange, etc.)
- Text: `#AAAAAA` (grey), `#FFFFFF` (active/selected)

**What makes it premium:** The wavetable display is the interface's centerpiece -- beautiful, animated, informative. The grey background is specifically chosen to make these colorful displays pop without competing.

**Relevance to Muze:** The principle of a "hero visual element." Muze has the camera feed / gesture visualization -- this should be treated as the premium visual centerpiece, with controls designed to frame and support it, not compete.

---

### 8. Endlesss -- Mobile-First Confidence

**Philosophy:** Social music creation with the immediacy of a messaging app.

**Key Visual Elements:**
- Dark background with vibrant, saturated accent colors
- Loop "stacks" as the visual metaphor -- colorful layers building up
- Minimal chrome -- controls appear only when needed
- Real-time waveform visualization per loop
- Touch-first controls with generous hit targets

**What makes it premium:** The reduction. Instead of showing every parameter all the time (like a DAW), Endlesss shows only what's relevant to the current action. This progressive disclosure feels confident and premium.

**Relevance to Muze:** The progressive disclosure philosophy. The generous touch targets. The idea that showing less = feeling premium.

---

## Key Design Principles: Generic vs. Premium

### 1. Native Range Inputs Look Cheap Because...

- **Inconsistent cross-browser rendering** -- the thumb and track look different on every device
- **No groove/channel** -- physical faders sit in a machined slot. Native inputs float on nothing.
- **Tiny touch targets** -- default thumbs are ~20px, too small for musical control
- **No visual feedback** -- no filled track, no glow on active state, no value tooltip
- **Linear appearance** -- they look like form controls, not instruments

**Premium alternative -- CSS technique for fader grooves:**
```css
/* Recessed fader channel */
.fader-track {
  width: 4px;
  height: 100%;
  background: #1a1a1e;
  border-radius: 2px;
  box-shadow:
    inset 0 1px 3px rgba(0, 0, 0, 0.8),   /* inner top shadow = recessed */
    inset 0 -1px 1px rgba(255, 255, 255, 0.03), /* subtle bottom light */
    0 0 0 1px rgba(0, 0, 0, 0.3);          /* outer edge definition */
  position: relative;
}

/* Fader cap (thumb replacement) */
.fader-thumb {
  width: 32px;
  height: 12px;
  background: linear-gradient(180deg, #555 0%, #3a3a3a 40%, #2a2a2a 100%);
  border-radius: 2px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  box-shadow:
    0 1px 0 rgba(255, 255, 255, 0.06),     /* top edge highlight */
    0 2px 4px rgba(0, 0, 0, 0.5),           /* drop shadow */
    inset 0 1px 0 rgba(255, 255, 255, 0.1); /* inner top highlight */
  /* Horizontal grip lines */
  background-image: repeating-linear-gradient(
    0deg,
    transparent,
    transparent 2px,
    rgba(255, 255, 255, 0.04) 2px,
    rgba(255, 255, 255, 0.04) 3px
  );
}
```

### 2. Premium Faders on Touchscreens

- **Large touch target, small visual** -- the visual thumb is 32x12px but the touch target should be 48x48px minimum
- **Touch-and-drag, not tap-to-position** -- prevents accidental value jumps
- **Visual feedback on touch** -- subtle glow/scale increase when finger is down
- **Value readout appears on touch** -- hidden by default, shown during interaction (like Massive X)
- **Velocity/acceleration** -- slow finger movement = fine control, fast = coarse. Premium apps implement this.
- **Haptic feedback** -- at unity gain (0dB), at hard left/right pan, at center detent

```css
/* Touch-active state for fader */
.fader-thumb.touching {
  box-shadow:
    0 0 12px rgba(var(--strip-color-rgb), 0.4),
    0 1px 0 rgba(255, 255, 255, 0.06),
    0 2px 4px rgba(0, 0, 0, 0.5);
  transform: scaleX(1.05);
  transition: box-shadow 0.1s ease, transform 0.1s ease;
}

/* Value tooltip that appears on touch */
.fader-value-tooltip {
  position: absolute;
  left: calc(100% + 8px);
  background: rgba(0, 0, 0, 0.85);
  color: #fff;
  font: 500 11px/1 'Inter', sans-serif;
  padding: 4px 8px;
  border-radius: 4px;
  opacity: 0;
  transform: translateX(-4px);
  transition: opacity 0.15s, transform 0.15s;
  pointer-events: none;
  white-space: nowrap;
}

.fader-thumb.touching + .fader-value-tooltip {
  opacity: 1;
  transform: translateX(0);
}
```

### 3. Gradients, Shadows, and Lighting

**The Light Source Rule:** Premium UIs imply a single, consistent light source (typically top-center or top-left). This means:
- Top edges of raised elements get a subtle highlight (`rgba(255,255,255,0.06)`)
- Bottom edges get a subtle shadow
- Recessed elements (grooves, meters) get shadow at top, light at bottom
- This must be consistent across EVERY element

**Gradient Usage:**
```css
/* Premium raised surface (button/control) */
.control-surface {
  background: linear-gradient(180deg,
    rgba(255, 255, 255, 0.06) 0%,   /* top light catch */
    rgba(255, 255, 255, 0.02) 50%,   /* mid */
    rgba(0, 0, 0, 0.04) 100%        /* bottom shadow */
  );
}

/* Premium recessed surface (meter well, fader groove) */
.recessed-surface {
  background: #0a0a0e;
  box-shadow:
    inset 0 1px 3px rgba(0, 0, 0, 0.8),
    inset 0 0 1px rgba(0, 0, 0, 0.5),
    0 1px 0 rgba(255, 255, 255, 0.03);
}
```

### 4. Typography System

**The Rule:** Use a geometric sans-serif for UI labels and headings. Reserve monospace ONLY for numerical values, data readouts, and technical displays.

**Recommended Font Stack:**
```css
:root {
  /* Primary UI font -- labels, headings, buttons */
  --font-ui: 'Inter', 'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif;

  /* Data/value font -- dB readouts, Hz values, BPM, percentages */
  --font-data: 'SF Mono', 'JetBrains Mono', 'Menlo', 'Consolas', monospace;

  /* Display font -- app name, mode names, large labels */
  --font-display: 'Inter', 'SF Pro Display', -apple-system, sans-serif;
}

/* Typography scale */
.label-section  { font: 600 9px/1 var(--font-ui); letter-spacing: 2.5px; text-transform: uppercase; }
.label-control  { font: 500 11px/1 var(--font-ui); letter-spacing: 0.3px; }
.value-readout  { font: 400 10px/1 var(--font-data); font-feature-settings: 'tnum'; } /* tabular numbers! */
.display-large  { font: 300 28px/1.2 var(--font-display); letter-spacing: 2px; }
.display-mode   { font: 600 13px/1 var(--font-ui); letter-spacing: 4px; text-transform: uppercase; }
```

**Critical detail:** Use `font-feature-settings: 'tnum'` for any numerical display. Tabular (fixed-width) numbers prevent layout jitter when values change. This is one of the most impactful micro-details.

**Alternative premium fonts (free):**
- **Inter** -- Best all-around UI font, specifically designed for screens
- **DM Sans** -- Geometric, excellent at small sizes, slightly more personality than Inter
- **Space Grotesk** -- Geometric with character, good for display text
- **JetBrains Mono** -- Best monospace for data values, ligatures for operators

### 5. "Dark Theme" vs. "Premium Dark Theme"

The difference comes down to three techniques:

**A. Color Temperature Tinting**
Never use pure neutral greys. Tint your dark palette toward a color temperature:
```css
:root {
  /* GENERIC (current Muze) -- pure dark, feels like a void */
  --bg-generic: #050508;

  /* PREMIUM OPTION A: Warm tint (studio feel, like NI Massive) */
  --bg-warm: #0C0A0E;         /* very subtle purple-warm */
  --surface-warm: #161318;
  --elevated-warm: #1E1A22;

  /* PREMIUM OPTION B: Cool tint (cinematic, like Output/iZotope) */
  --bg-cool: #080B12;         /* dark navy */
  --surface-cool: #0F1420;
  --elevated-cool: #161C2D;

  /* PREMIUM OPTION C: Neutral-warm (hardware feel, most versatile) */
  --bg-neutral: #0E0E11;      /* almost neutral with the faintest warm lean */
  --surface-neutral: #161619;
  --elevated-neutral: #1E1E22;
}
```

**B. Surface Elevation System**
Instead of one background + transparent overlays, define distinct elevation levels:
```css
:root {
  --elevation-0: #0E0E11;   /* base background */
  --elevation-1: #161619;   /* panels, cards */
  --elevation-2: #1E1E22;   /* controls, raised areas */
  --elevation-3: #262629;   /* active controls, hover states */
  --elevation-4: #2E2E32;   /* pressed states, emphasis */
}
```

**C. Subtle Noise Texture**
The single most impactful "premium" technique. A 2-5% opacity noise overlay prevents the "digital void" feeling:
```css
/* Add to any surface that needs to feel physical */
.surface-textured::after {
  content: '';
  position: absolute;
  inset: 0;
  opacity: 0.03;
  pointer-events: none;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E");
  background-size: 128px 128px;
  mix-blend-mode: overlay;
  border-radius: inherit;
}
```

### 6. Level Meters: Basic vs. Premium

**Current Muze (basic):**
- 3px wide solid bar
- Simple CSS gradient (green -> yellow -> red)
- Direct height animation

**Premium Level Meter Approach:**
```css
/* Recessed meter well */
.meter-well {
  width: 6px;
  background: #0A0A0E;
  border-radius: 3px;
  box-shadow:
    inset 0 1px 3px rgba(0, 0, 0, 0.8),
    0 1px 0 rgba(255, 255, 255, 0.02);
  position: relative;
  overflow: hidden;
}

/* Segmented meter fill */
.meter-fill {
  position: absolute;
  bottom: 0;
  left: 0;
  width: 100%;
  border-radius: 3px;
  /* Modern turquoise-to-amber-to-red gradient (iZotope-inspired) */
  background: linear-gradient(
    to top,
    #0D9488 0%,     /* teal -- low levels */
    #2DD4BF 40%,    /* turquoise -- normal */
    #FBBF24 75%,    /* amber -- hot */
    #EF4444 95%,    /* red -- clipping */
    #FF0000 100%
  );
  /* Segmented look via repeating gradient overlay */
  mask-image: repeating-linear-gradient(
    to top,
    black 0px,
    black 3px,
    transparent 3px,
    transparent 4px
  );
  -webkit-mask-image: repeating-linear-gradient(
    to top,
    black 0px,
    black 3px,
    transparent 3px,
    transparent 4px
  );
}

/* Glow effect at high levels */
.meter-fill.hot {
  box-shadow: 0 0 8px rgba(45, 212, 191, 0.3);
}

.meter-fill.clipping {
  box-shadow: 0 0 12px rgba(239, 68, 68, 0.5);
}

/* Peak hold indicator */
.meter-peak {
  position: absolute;
  left: 0;
  width: 100%;
  height: 2px;
  background: #fff;
  box-shadow: 0 0 4px rgba(255, 255, 255, 0.5);
  transition: bottom 0.05s linear;
  /* Falls slowly */
  animation: peak-fall 1.5s ease-in forwards;
}
```

### 7. Subtle Textures and Noise

Noise texture is the difference between "digital" and "physical." Physical surfaces always have texture at the micro level -- even brushed aluminum, powder-coated metal, and rubber have visible grain.

**Implementation Layers:**
1. **Background noise** (2-3% opacity) -- prevents the void feeling
2. **Surface noise** (3-5% opacity, different frequency) -- gives panels material identity
3. **Vignette** -- subtle radial gradient darkening at edges of the overall app

```css
/* Global vignette overlay */
.app-container::before {
  content: '';
  position: fixed;
  inset: 0;
  background: radial-gradient(
    ellipse at 50% 40%,
    transparent 40%,
    rgba(0, 0, 0, 0.3) 100%
  );
  pointer-events: none;
  z-index: 999;
}
```

### 8. Micro-Interactions That Matter

**Optimal transition duration:** 150-200ms for controls, 300-400ms for panels.

```css
/* Button press -- physical "click" feel */
.control-btn:active {
  transform: scale(0.95);
  transition: transform 0.08s ease;
  /* Slightly darker = pushed in */
  filter: brightness(0.9);
}
.control-btn {
  transition: transform 0.15s ease, filter 0.15s ease;
}

/* Fader glow on touch */
.fader-thumb.active {
  box-shadow: 0 0 16px rgba(var(--accent-rgb), 0.4);
  transition: box-shadow 0.2s ease;
}

/* Mute button engagement */
.mute-btn.active {
  background: var(--color-red);
  color: #000;
  box-shadow: 0 0 12px rgba(239, 68, 68, 0.4);
  /* Slight "LED on" glow */
  text-shadow: 0 0 4px rgba(239, 68, 68, 0.6);
}

/* Value changes -- tabular numbers prevent jitter */
.value-display {
  font-feature-settings: 'tnum';
  min-width: 3ch; /* prevents layout shift */
  text-align: right;
  transition: color 0.15s;
}
```

---

## Actionable Design System for Muze

### Recommended Color Palette

```css
:root {
  /* === BACKGROUNDS (cool-neutral tint) === */
  --bg-base: #0C0C10;           /* App background -- NOT pure black */
  --bg-surface: #141418;        /* Panels, cards */
  --bg-elevated: #1C1C21;       /* Raised controls, active areas */
  --bg-recessed: #08080B;       /* Fader grooves, meter wells */

  /* === BORDERS & DIVIDERS === */
  --border-subtle: rgba(255, 255, 255, 0.05);
  --border-default: rgba(255, 255, 255, 0.08);
  --border-emphasis: rgba(255, 255, 255, 0.12);

  /* === TEXT === */
  --text-primary: #E8E8EC;       /* Slightly warm white -- NOT pure white */
  --text-secondary: #8E8E96;     /* UI labels */
  --text-tertiary: #52525A;      /* Disabled, hints */
  --text-accent: var(--accent);

  /* === ACCENT (warm amber -- keep current, it's good) === */
  --accent: #E8A948;
  --accent-rgb: 232, 169, 72;
  --accent-dim: #B8863A;
  --accent-glow: rgba(232, 169, 72, 0.25);
  --accent-subtle: rgba(232, 169, 72, 0.08);

  /* === FUNCTIONAL COLORS === */
  --color-green: #0D9488;        /* Teal-green (modern, not traffic-light) */
  --color-green-bright: #2DD4BF; /* Turquoise metering */
  --color-yellow: #FBBF24;       /* Warning/solo -- warm amber */
  --color-red: #EF4444;          /* Mute/clip */
  --color-red-glow: rgba(239, 68, 68, 0.4);

  /* === CHANNEL COLORS (muted, not saturated) === */
  --ch-drums: #8B8B92;           /* Neutral grey */
  --ch-bass: #6366F1;            /* Indigo */
  --ch-chords: #8B5CF6;          /* Violet */
  --ch-lead: #EC4899;            /* Pink */
  --ch-fx: #06B6D4;              /* Cyan */
  --ch-master: #E8E8EC;          /* White */

  /* === SPACING === */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 12px;
  --space-lg: 16px;
  --space-xl: 24px;

  /* === TYPOGRAPHY === */
  --font-ui: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  --font-data: 'SF Mono', 'JetBrains Mono', 'Menlo', monospace;

  /* === RADIUS === */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 12px;
  --radius-pill: 50px;

  /* === SHADOWS === */
  --shadow-recessed: inset 0 1px 3px rgba(0,0,0,0.8), 0 1px 0 rgba(255,255,255,0.02);
  --shadow-raised: 0 1px 0 rgba(255,255,255,0.04), 0 2px 8px rgba(0,0,0,0.3);
  --shadow-glow: 0 0 12px;
}
```

### Typography Rules

| Element | Font | Weight | Size | Spacing | Transform |
|---------|------|--------|------|---------|-----------|
| App title | --font-ui | 200 | 48px | 16px | uppercase |
| Mode name (HUD) | --font-ui | 600 | 24px | 4px | uppercase |
| Section heading | --font-ui | 600 | 9px | 2.5px | uppercase |
| Control label | --font-ui | 500 | 11px | 0.3px | none |
| Button text | --font-ui | 500 | 12px | 0.5px | none |
| dB value | --font-data | 400 | 10px | 0 | none |
| Channel name | --font-ui | 700 | 8px | 1.5px | uppercase |
| Chord symbol | --font-ui | 600 | 14px | 0.5px | none |

### Specific CSS Patterns to Implement

**A. Noise Texture Mixin (apply to mixer panel, synth panel, any surface)**
```css
.has-texture {
  position: relative;
}
.has-texture::after {
  content: '';
  position: absolute;
  inset: 0;
  opacity: 0.025;
  pointer-events: none;
  background: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  background-size: 150px;
  mix-blend-mode: overlay;
  border-radius: inherit;
  z-index: 1;
}
```

**B. Premium Fader Track (replace native range input)**
```css
/* The recessed groove */
.fader-groove {
  width: 4px;
  height: 100%;
  background: var(--bg-recessed);
  border-radius: 2px;
  box-shadow: var(--shadow-recessed);
  position: relative;
}

/* The filled portion (below thumb) */
.fader-fill {
  position: absolute;
  bottom: 0;
  left: 0;
  width: 100%;
  border-radius: 2px;
  background: rgba(var(--strip-color-rgb), 0.3);
}

/* The thumb/cap */
.fader-cap {
  width: 34px;
  height: 14px;
  background: linear-gradient(180deg, #4A4A4E 0%, #38383C 50%, #2C2C30 100%);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 2px;
  box-shadow:
    0 1px 0 rgba(255, 255, 255, 0.05),
    0 2px 4px rgba(0, 0, 0, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.08);
  /* Grip lines */
  background-image: repeating-linear-gradient(
    0deg,
    transparent 0px,
    transparent 2px,
    rgba(255, 255, 255, 0.03) 2px,
    rgba(255, 255, 255, 0.03) 3px
  );
  cursor: grab;
  touch-action: none;
}

.fader-cap:active, .fader-cap.touching {
  cursor: grabbing;
  box-shadow:
    0 0 12px rgba(var(--strip-color-rgb), 0.3),
    0 1px 0 rgba(255, 255, 255, 0.05),
    0 2px 4px rgba(0, 0, 0, 0.4);
}
```

**C. Segmented Level Meter**
```css
.meter-well {
  width: 6px;
  background: var(--bg-recessed);
  border-radius: 3px;
  box-shadow: var(--shadow-recessed);
  overflow: hidden;
}

.meter-fill {
  position: absolute;
  bottom: 0; left: 0;
  width: 100%;
  background: linear-gradient(to top,
    var(--color-green) 0%,
    var(--color-green-bright) 50%,
    var(--color-yellow) 80%,
    var(--color-red) 100%
  );
  /* Segmented mask */
  -webkit-mask-image: repeating-linear-gradient(
    to top, black 0px, black 2px, transparent 2px, transparent 3px
  );
  mask-image: repeating-linear-gradient(
    to top, black 0px, black 2px, transparent 2px, transparent 3px
  );
  will-change: height;
}
```

**D. Premium Chord Bar**
```css
#chord-zone {
  background: var(--bg-surface);
  border-top: 1px solid var(--border-subtle);
  /* Subtle top-edge highlight for depth */
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
}

.chord-btn {
  font: 600 14px/1 var(--font-ui);  /* NOT monospace */
  color: var(--text-tertiary);
  transition: color 0.15s, background 0.15s;
}

.chord-btn.active {
  color: var(--accent);
  background: var(--accent-subtle);
  /* Bottom indicator line */
}

.chord-btn.active::after {
  content: '';
  position: absolute;
  bottom: 0; left: 20%; right: 20%;
  height: 2px;
  background: var(--accent);
  border-radius: 1px;
  box-shadow: 0 0 8px var(--accent-glow); /* LED-like glow */
}
```

**E. Mode HUD**
```css
#mode-hud {
  font: 600 24px/1.2 var(--font-ui); /* NOT monospace for the mode name */
  letter-spacing: 4px;
  text-transform: uppercase;
  color: var(--text-primary);
  background: var(--bg-surface);
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-lg);
  padding: 16px 32px;
  backdrop-filter: blur(24px);
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.3);
}

/* Valence bar upgrade */
#mode-hud .valence-bar {
  height: 3px;
  background: var(--bg-recessed);
  border-radius: 2px;
  box-shadow: var(--shadow-recessed);
  overflow: hidden;
}
```

---

## Implementation Priority (Highest Impact First)

1. **Color temperature** -- Change `--muze-bg: #050508` to `#0C0C10` and introduce the elevation system. Immediate premium lift.
2. **Typography** -- Switch UI labels from monospace to Inter/system sans-serif. Keep monospace only for dB values and BPM. Second biggest impact.
3. **Noise texture** -- Add the SVG noise overlay to mixer panel and synth panel backgrounds. Instant "material" feel.
4. **Meter upgrade** -- Widen to 6px, add segmented mask, switch to turquoise-amber-red gradient, add recessed well shadow.
5. **Fader grooves** -- Add inset shadow to fader tracks to create recessed channel appearance.
6. **Fader thumbs** -- Add gradient, grip lines, and glow-on-touch to fader caps.
7. **Chord bar** -- Switch to sans-serif font, add surface treatment, improve active state with LED glow.
8. **Mode HUD** -- Switch to sans-serif, add proper card shadow and backdrop blur.
9. **Panel backgrounds** -- Apply elevation system to synth panel and mixer panel.
10. **Micro-interactions** -- Add touch states, transition refinements, tabular number feature.

---

## Summary: The 5 Rules of Premium Audio UI

1. **Never use pure black or pure grey.** Tint your darks toward a color temperature (warm, cool, or blue-neutral). Pure black = void. Tinted dark = atmosphere.

2. **Typography signals quality instantly.** Sans-serif (Inter) for UI, monospace only for data values. This single change separates "developer tool" from "designed product."

3. **Physical surfaces have depth.** Recessed grooves (inset shadow), raised controls (gradient + highlight), noise texture on flat surfaces. Everything in a premium UI has implied material.

4. **Color must be functional, not decorative.** Every color should map to a meaning (channel identity, signal level, state). Fewer, more intentional colors = more premium than many arbitrary ones.

5. **Show less, mean more.** Progressive disclosure, generous spacing, values that appear only when needed. Confidence in what you hide is what separates premium from feature-dump.
