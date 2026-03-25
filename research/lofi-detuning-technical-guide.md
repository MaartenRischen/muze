# Lo-Fi Hip Hop Detuning: Complete Technical Reference for Web Audio / Tone.js

## Table of Contents

1. [Why Detuning is Central to Lo-Fi](#1-why-detuning-is-central-to-lo-fi)
2. [What Gets Detuned](#2-what-gets-detuned)
3. [Historical Context: Hardware Origins](#3-historical-context-hardware-origins)
4. [Tape Wow and Flutter (Pitch Drift)](#4-tape-wow-and-flutter-pitch-drift)
5. [Oscillator Detuning for Thickness](#5-oscillator-detuning-for-thickness)
6. [Sample Pitch Manipulation](#6-sample-pitch-manipulation)
7. [Micro-Detuning / Tuning Instability](#7-micro-detuning--tuning-instability)
8. [Vibrato as Detuning](#8-vibrato-as-detuning)
9. [Chorus and Ensemble Effects as Detuning](#9-chorus-and-ensemble-effects-as-detuning)
10. [Bitcrushing and Sample Rate Reduction](#10-bitcrushing-and-sample-rate-reduction)
11. [Plugin and Hardware Reference](#11-plugin-and-hardware-reference)
12. [Tone.js / Web Audio Implementation](#12-tonejs--web-audio-implementation)
13. [Combined Detuning Architecture](#13-combined-detuning-architecture)
14. [Key Formulas and Conversions](#14-key-formulas-and-conversions)

---

## 1. Why Detuning is Central to Lo-Fi

### The Psychology of Imperfection

Detuning is arguably the single most important effect in lo-fi hip hop. It creates the genre's signature "nostalgic," "warm," and "dreamy" quality through several perceptual mechanisms:

- **Analog memory association**: Slight pitch instability triggers memories of cassette tapes, vinyl records, and old radios -- media that was ubiquitous in the 1980s-90s. The brain associates these imperfections with "the past."
- **Warmth through beating**: When two slightly detuned signals combine, they produce slow amplitude modulations (beating). At rates of 1-6 Hz, this creates perceived "warmth" and "thickness." This is the same phenomenon that makes a piano chorus (three strings per note, slightly detuned) sound rich.
- **Dreamy quality**: Continuous micro-pitch variation creates a sensation of "floating" or "drifting" -- the audio equivalent of a soft-focus lens. The brain cannot lock onto a perfectly stable pitch, producing a trance-like, meditative quality.
- **Human imperfection**: Lo-fi explicitly embraces imperfection. Unquantized drums (the J Dilla influence), off-key notes, and pitch wobble all signal "human presence" as opposed to digital sterility. After 30+ years of digital pitch perfection, these artifacts feel refreshingly organic.
- **Masking and smoothing**: Detuning smears transients and blurs harmonic content, softening harsh frequencies. This is why lo-fi works as "study music" -- it lacks the sharp attacks and precise tuning that demand cognitive attention.

### The Nostalgic Trigger

The warmth people associate with lo-fi comes from what could be described as "the difference between sterile digital clarity and the warm world of memory, lit by a crackling gasoline lamp." Small sonic flaws trigger feelings of authenticity and presence, countering the sterility of highly polished music. Lo-fi is comforting precisely because of its imperfections.

---

## 2. What Gets Detuned

In lo-fi production, detuning is applied at multiple levels simultaneously:

| Target | Technique | Typical Amount |
|--------|-----------|---------------|
| **Individual oscillators** | Unison detune between voices | 3-15 cents |
| **Keys/Rhodes/Piano** | Per-note micro-detune | 5-15 cents |
| **Pads and chords** | Chorus + slow LFO detune | 5-25 cents |
| **Samples** | Pitch-shifting down | 1-4 semitones |
| **Individual instruments** | Per-channel tape wow/flutter | 5-30 cents peak |
| **Master bus** | Global tape emulation (wow + flutter + drift) | 5-20 cents peak |
| **Entire mix** | Vinyl wobble simulation | 2-10 cents peak |

The key insight is that lo-fi stacks multiple detuning sources. A Rhodes chord might have:
1. Per-oscillator unison detune (static, ~7 cents)
2. Per-note micro-detuning (random, 3-8 cents per note)
3. Channel-level tape flutter (LFO, ~10 cents peak at 6-12 Hz)
4. Master bus wow (LFO, ~15 cents peak at 0.5-2 Hz)

These compound into the thick, wobbly, "melting" quality that defines the genre.

---

## 3. Historical Context: Hardware Origins

### Cassette Tape Machines

Cassette decks created natural detuning through mechanical imperfection:
- **Wow**: Caused by irregular rotation of supply/takeup reels, off-center hubs, or belt stretch. Rate: 0.5-6 Hz. The slower the tape speed, the more pronounced.
- **Flutter**: Caused by worn capstans, lumpy pinch rollers, and tape tension irregularities. Rate: 6-100 Hz.
- **Scrape flutter**: High-frequency vibration (100+ Hz) from tape friction against heads, creating complex harmonic artifacts.

**Specifications by quality level:**
| Equipment | Wow & Flutter (weighted) | Approximate cents deviation |
|-----------|------------------------|----------------------------|
| Professional reel-to-reel | ~0.02% | ~0.4 cents |
| High-end cassette (Nakamichi) | ~0.08% | ~1.6 cents |
| Average cassette deck | ~0.2% | ~4 cents |
| Cheap/worn cassette player | 0.4%+ | ~8+ cents |
| Deliberately degraded (lo-fi aesthetic) | 0.5-2% | 10-40 cents |

**Conversion**: 1% speed deviation = approximately 17.3 cents. (Derived from: 100 cents / 5.946% per semitone, since 2^(1/12) = 1.05946.)

### Vinyl Records

Vinyl introduces pitch instability through:
- **Eccentric pressing**: The center hole is never perfectly centered. IEC 60098 allows up to 0.2mm offset. At worst case (inner groove), this creates up to 0.66% peak-to-peak wow, cycling once per revolution (0.55 Hz at 33 RPM, 0.75 Hz at 45 RPM).
- **Warped records**: Vertical warping causes the stylus to track at varying speeds, adding low-frequency wow.
- **Turntable wow/flutter**: Belt-drive turntables typically measure 0.12% peak; direct-drive achieves ~0.06%.

**Perceptual threshold**: Solo piano wow becomes audible at 0.14% RMS (approximately 0.4% peak-to-peak, or ~7 cents peak-to-peak). Most listeners detect pitch changes at ~1% speed variation (~17 cents).

### SP-404 / MPC Samplers

These legendary samplers create lo-fi detuning through:
- **Low sample rates**: The SP-1200 sampled at 26.04 kHz / 12-bit. Pitching samples down also reduced the effective sample rate, adding aliasing artifacts that sound like "grit."
- **Pitch-tempo coupling**: Unlike modern time-stretching, classic samplers change pitch when you change speed. Pitching a sample down 2 semitones also slows it by ~12%, creating the characteristic "slowed" dreamy quality.
- **DAC character**: The 12-bit converters of the SP-1200 and the 16-bit converters of the MPC60 added quantization noise and a subtly "stepped" quality to pitch transitions.
- **The SP-404's effects**: Built-in vinyl simulation, lo-fi effects, and pitch shifting (+/- 12 semitones on the MkII) that are specifically designed to sound characterfully degraded.

---

## 4. Tape Wow and Flutter (Pitch Drift)

### Precise Definitions and Frequency Ranges

Per IEC 60386 and AES6-2008 standards:

| Component | Frequency Range (IEC 60386) | Frequency Range (AES6-2008) | Character |
|-----------|----------------------------|----------------------------|-----------|
| **Drift** | Below 0.1 Hz | Below ~0.5 Hz | Very slow pitch wandering |
| **Wow** | 0.1 - 10 Hz | 0.5 - 6 Hz | Slow, swaying pitch changes |
| **Flutter** | 10 - 100 Hz | 6 - 100 Hz | Rapid, shimmering pitch changes |
| **Scrape flutter** | 100 - 1000+ Hz | -- | Metallic, resonant artifacts |

The traditional boundary is **4 Hz** (below = wow, above = flutter), though standards vary. The most perceptually annoying rate is exactly **4 Hz**.

### LFO Rates for Emulation

For lo-fi production, the practical ranges used in plugins and by producers:

**Wow:**
- Rate: **0.3 - 4 Hz** (most common: 0.5 - 2 Hz)
- Depth: **5 - 30 cents** peak (subtle: 5-10, obvious: 15-30)
- Character: Slow, dreamy, "seasick" swaying

**Flutter:**
- Rate: **6 - 20 Hz** (most common: 8-14 Hz)
- Depth: **2 - 10 cents** peak (subtle: 2-4, obvious: 5-10)
- Character: Rapid shimmer, "warbling," slightly metallic

**Drift (bonus layer):**
- Rate: **0.05 - 0.3 Hz** (one full cycle every 3-20 seconds)
- Depth: **3 - 15 cents**
- Character: Very slow pitch wander, barely perceptible moment-to-moment but adds "life"

### LFO Waveform Shape

Real tape wow/flutter is NOT a simple sine wave. Authentic emulation uses:

| Waveform | Use Case | Character |
|----------|----------|-----------|
| **Sine** | Basic wow | Smooth, regular swaying |
| **Triangle** | Basic flutter | Slightly more linear movement |
| **Filtered random/noise** | Most realistic | Irregular, unpredictable -- closest to real tape |
| **Rounded sawtooth** | Vinyl wow (eccentric hole) | Asymmetric -- fast rise, slow fall (or vice versa) |
| **Sine + noise** | Best composite | Smooth base with random perturbation |

**Key insight**: Authentic wow and flutter is much more nuanced than a simple LFO. Real tape machines produce quasi-periodic modulation with random amplitude and rate variations. The best emulators (SketchCassette, RC-20) use multiple LFOs plus noise modulation to achieve this. For Tone.js, combining a sine LFO with a noise-modulated component is the recommended approach.

### Application Point

In hardware and most plugins, tape wow/flutter is applied to the **master bus** or to the output of the entire instrument, not per-oscillator. However, some lo-fi producers apply different amounts to different instruments:
- Heavy on keys/Rhodes (most noticeable)
- Medium on pads/strings
- Light on drums (too much makes them sound broken rather than lo-fi)
- Master bus gets an additional subtle layer

### How Hardware Emulators Implement This

**RC-20 Retro Color (Wobble module):**
- Separate Wow and Flutter LFOs
- Wow rate: 0.1 - 4 Hz
- Flutter rate: 6 - 20 Hz
- Horizontal slider blends between wow and flutter
- Stereo mode applies different modulation to L/R channels (creates chorus-like widening)
- Technically: two independent LFOs with blendable output, connected to pitch modulation

**Aberrant DSP SketchCassette II:**
- 4 wow LFO waveforms: sine, triangle, rounded saw, inverse rounded saw
- 2 flutter LFO waveforms: sine, random
- FM mode: wow LFO modulates the flutter LFO rate (creating complex, evolving pitch patterns)
- Tempo-syncable wow and flutter rates
- Independent depth and rate for both components
- This is the most technically sophisticated tape emulation available

**Wavesfactory Cassette:**
- Wow Depth + Wow Rate parameters
- Flutter Depth + Flutter Rate parameters
- "Stability" master parameter (100% = no wobble, 0% = maximum)
- Stability Randomness parameter (0-100%) adds unpredictability
- Wow and flutter use sinusoidal LFOs weighted by the Stability parameter

**iZotope Vinyl:**
- Warp Depth: intensity of pitch warping
- Warp Model: selects different pitch envelope shapes
- RPM dial: affects the periodic rate of warping (33, 45, 78 RPM)
- Note: Warp only functions in AudioSuite/DirectX modes, not VST

---

## 5. Oscillator Detuning for Thickness

### Unison Voices and Detune Amounts

Oscillator detuning stacks multiple copies of the same pitch with slight tuning offsets:

| Voices | Typical Detune Spread | Character | CPU Cost |
|--------|----------------------|-----------|----------|
| **2** | +/- 5-10 cents | Subtle thickening, slight chorus | Low |
| **3** | +/- 7-12 cents | Richer, organ-like | Medium |
| **4** | +/- 10-15 cents | Full "supersaw" character | Medium |
| **8** | +/- 15-25 cents | Massive, diffuse | High |

**For lo-fi specifically**: 2-4 voices with 5-15 cents detune is typical. Lo-fi does not aim for the aggressive "supersaw" of EDM. The goal is subtle warmth, not wall-of-sound.

**Common pattern**: With 2 oscillators, set one to +7 cents and the other to -7 cents. This creates a slow beating pattern at about 1.8 Hz (for a 440 Hz fundamental), which is perceived as gentle warmth.

### Beating Frequency Calculation

When two oscillators are detuned by `d` cents at frequency `f` Hz:
```
Beat frequency = f * (2^(d/1200) - 1) Hz
```
Examples at 440 Hz:
- 5 cents detune: ~1.3 Hz beating
- 7 cents detune: ~1.8 Hz beating
- 10 cents detune: ~2.5 Hz beating
- 15 cents detune: ~3.8 Hz beating
- 25 cents detune: ~6.4 Hz beating

The sweet spot for lo-fi warmth is 1-4 Hz beating, which corresponds to roughly 5-15 cents at mid-frequency.

### How This Differs from Chorus

| Feature | Unison Detune | Chorus Effect |
|---------|--------------|---------------|
| Mechanism | Multiple oscillators, static pitch offset | Delayed copy with modulated delay time |
| Pitch relationship | Fixed offset (e.g., always +7 cents) | Continuously varying (oscillates around center) |
| Phase | Random or free-running | Creates comb filtering due to delay |
| Sound | Dense, stable thickening | Swirling, phasey, more "watery" |
| Artifacts | No phasing | Can produce notches/peaks in spectrum |
| CPU (Web Audio) | N oscillators per note | 1 delay line + 1 LFO per voice |

For lo-fi: both are used, but unison detune gives the "permanently warm" quality, while chorus adds the "moving, breathing" quality.

### Detuning on Specific Lo-Fi Instruments

**Rhodes / Electric Piano:**
- The Fender Rhodes naturally has slight detuning: each note uses a tine + tone bar assembly that acts as a tuning fork. Individual notes can drift as tuning springs loosen or tines fatigue.
- Lo-fi Rhodes emulation: **5-10 cents** of random per-note detune + **2-5 cents** of slow LFO modulation
- The bottom octave of a real Rhodes tends to pull sharp on hard strikes and drift as notes sustain
- Classic Rhodes sound already includes "stretch tuning" (slightly sharp in upper register, slightly flat in lower)

**Pads and Chords:**
- Pads benefit from wider detune: **10-20 cents** across 2-4 voices
- Add slow LFO (0.3-0.8 Hz) modulating detune by an additional +/- 5-10 cents
- This creates the "breathing," slowly evolving pad texture characteristic of lo-fi
- Chords with slight per-note detuning sound like a real ensemble where players are not perfectly in tune

---

## 6. Sample Pitch Manipulation

### Pitching Samples Down

This is a foundational lo-fi technique, directly descended from DJ Screw's "chopped and screwed" style.

**Typical amounts:**
| Amount | Effect | Use Case |
|--------|--------|----------|
| -1 semitone | Subtle darkening | Making bright samples sit better |
| -2 semitones | Noticeable "slowed" quality | Standard lo-fi sample treatment |
| -3 to -4 semitones | Obviously pitched down | Heavier, darker lo-fi |
| -5 to -8 semitones | Dramatic transformation | Chopped & screwed territory |

### How Pitch-Down Creates the Dreamy Quality

When a sample is pitched down without time-stretching (classic sampler behavior):

1. **Formant shift**: All formant frequencies shift downward proportionally. Vocals sound like they're coming from a larger throat/chest cavity, creating an intimate, "close" quality. Even a 2-semitone drop produces noticeably altered formants.
2. **Temporal stretching**: The sample plays slower, creating a languid, dreamlike pace. A -2 semitone shift adds ~12% to the duration.
3. **Bandwidth reduction**: High-frequency content shifts downward, effectively rolling off the top end. This is the "dark," "warm" quality.
4. **Transient softening**: Attack transients are stretched in time, making them less sharp.

### Chopped and Screwed Influence

DJ Screw pioneered slowing tracks to 60-70 BPM (from typical 85-100 BPM hip hop tempo), which involved:
- Pitch reduction of roughly 3-7 semitones (corresponding to the tempo reduction)
- The resulting deep, "underwater" quality became the sonic signature
- Modern lo-fi hip hop adopted this aesthetic but typically uses smaller shifts (1-3 semitones)
- The "slowed + reverb" subgenre (sometimes called "Gen Z's lo-fi") takes this further

### Vinyl Playback Speed Variation

Playing a 45 RPM record at 33 RPM drops pitch by approximately **5.3 semitones** (ratio = 33/45 = 0.733, cents = 1200 * log2(0.733) = -534 cents). This classic DJ trick is one origin of the lo-fi pitch-down aesthetic.

### Effect on Formants and Timbre

The formula for pitch change: `new_frequency = original_frequency * 2^(semitones/12)`

At -2 semitones: all frequencies multiply by 0.891. A vocal formant at 3000 Hz drops to 2673 Hz. This makes:
- Male voices sound deeper, more "chesty"
- Female voices sound androgynous, intimate
- Instruments lose "brightness" and gain "weight"
- Everything sounds like it's playing back on a worn, slow machine

---

## 7. Micro-Detuning / Tuning Instability

### Why Vintage Instruments Go Out of Tune

**Acoustic pianos:**
- Strings stretch over time under 15-20 tons of total tension
- Temperature changes cause frame expansion/contraction
- Well-maintained piano: drifts 1-3 cents per year
- Neglected piano: can drift 5-15 cents per year
- Badly neglected: 20-40+ cents flat

**Fender Rhodes:**
- Generally more stable than acoustic piano (no string tension)
- Tuning springs can loosen, causing individual notes to drift
- Tine fatigue from heavy playing causes pitch change
- The bottom octave is particularly prone to pulling sharp on attack
- Temperature changes affect the metal tines

**Analog synthesizers:**
- VCO (Voltage Controlled Oscillator) drift due to temperature changes
- Component aging in capacitors and resistors
- Power supply fluctuations
- Classic Minimoog: could drift 10-20+ cents over a session without retuning

### Per-Note Random Detuning (Micro-Detuning Table)

To simulate an out-of-tune instrument, assign a random but static pitch offset to each MIDI note:

**Recommended ranges for lo-fi:**
| Character | Range (cents) | Description |
|-----------|--------------|-------------|
| Subtle warmth | +/- 3-5 | Barely perceptible, adds "life" |
| Noticeably vintage | +/- 5-10 | Sounds like a piano that needs tuning |
| Honky-tonk / characterful | +/- 10-20 | Clearly out of tune, strong character |
| Broken / extreme | +/- 20-40 | Sounds damaged, use sparingly |

**The just-noticeable difference (JND) for pitch is 5-6 cents.** Detuning below this threshold adds perceived warmth without sounding "wrong." Lo-fi typically operates at or just above this threshold (5-15 cents).

### Per-Key vs. Global Detune

| Approach | Effect | Best For |
|----------|--------|----------|
| **Per-key detuning table** | Each note has its own offset; chords sound naturally "spread" | Rhodes, piano, melodic instruments |
| **Global detune** | All notes shift by the same amount | Less realistic; useful for "everything is slightly off" |
| **Per-key + slow drift** | Static per-key offsets + slow random LFO per note | Most realistic vintage feel |

**Implementation strategy**: Generate a detuning table of 128 values (one per MIDI note) with Gaussian distribution, mean=0, standard deviation=5-8 cents. Optionally add slow random drift (+/- 2-3 cents over 10-30 seconds) on top.

---

## 8. Vibrato as Detuning

### Lo-Fi Vibrato Parameters

Vibrato in lo-fi context is typically subtler and slower than classical vibrato:

| Parameter | Classical Vibrato | Lo-Fi Vibrato |
|-----------|------------------|---------------|
| **Rate** | 5-7 Hz | 3-5 Hz |
| **Depth** | 20-50 cents | 5-20 cents |
| **Waveform** | Sine | Sine (sometimes triangle) |
| **Application** | Solo melody lines | Keys, pads, entire bus |
| **Onset** | Delayed (after attack) | Often immediate or very short delay |

### Typical Lo-Fi Vibrato Settings

**On keys/Rhodes:**
- Rate: 3-5 Hz
- Depth: 8-15 cents
- Waveform: Sine
- Often combined with tremolo (amplitude modulation) at similar rate

**On pads:**
- Rate: 1-3 Hz (very slow)
- Depth: 5-10 cents
- Waveform: Sine or triangle
- Creates a gentle "breathing" quality
- Lower rate and amount than keys to avoid seasickness

**On lead/melody lines:**
- Rate: 4-6 Hz
- Depth: 15-30 cents
- Waveform: Sine
- More noticeable, adding expressiveness and human quality

### Delayed Vibrato (Onset Control)

In real performance, vibrato typically starts 200-500ms after a note begins. This is important for realism:
- The note attacks at a stable pitch
- Vibrato gradually fades in over 100-400ms
- At full depth, the pitch gently oscillates

**Implementation**: Use an envelope or ramp on the LFO amplitude:
- Delay: 150-400ms (no vibrato)
- Attack: 200-500ms (vibrato fades in linearly)
- Sustain: Full vibrato depth

### Vibrato vs. Tape Wow

| Feature | Vibrato | Tape Wow |
|---------|---------|----------|
| Applied to | Individual notes | Entire signal |
| Per-note onset | Yes (delayed) | No (continuous) |
| Rate | 3-7 Hz | 0.3-4 Hz |
| Phase relationship | Independent per note | Same phase for all notes |
| Musical purpose | Expression | Degradation/character |

---

## 9. Chorus and Ensemble Effects as Detuning

### How Chorus Creates Detuning

Chorus creates pitch variation through a modulated delay line:

1. The input signal is split: one copy is direct (dry), the other goes through a variable delay line
2. An LFO modulates the delay time, which causes the Doppler effect -- perceived pitch change
3. When the delay time increases, pitch drops; when it decreases, pitch rises
4. The wet and dry signals are mixed, creating the "multiple voices" illusion

**The effective pitch deviation** of a chorus depends on the LFO rate and depth:
```
Pitch deviation (cents) = 1200 * LFO_rate (Hz) * delay_depth (seconds) / ln(2)
```

### Typical Chorus Settings for Lo-Fi

| Parameter | Lo-Fi Setting | Range | Notes |
|-----------|--------------|-------|-------|
| **Delay time** | 15-25 ms | 5-50 ms | Center delay around which modulation occurs |
| **LFO Rate** | 0.5-1.5 Hz | 0.1-10 Hz | Slow for lo-fi; faster = more "watery" |
| **LFO Depth** | 2-5 ms | 0.5-10 ms | How much the delay time varies |
| **Mix** | 20-35% wet | 0-100% | Subtle blend; too much sounds phasey |
| **Feedback** | 0% | 0-100% | Chorus typically uses zero feedback |
| **Waveform** | Sine or Triangle | -- | Sine is smoother, triangle more linear |

**Specific lo-fi chorus recipe:**
- Delay: 20 ms
- Rate: 0.8 Hz
- Depth: 3 ms (delay modulates between 17-23 ms)
- Mix: 25% wet
- This creates approximately 8-12 cents of continuous pitch variation

### Chorus vs. Flanger vs. Phaser: Detuning Characteristics

| Effect | Delay Range | Creates Detuning? | Character |
|--------|------------|-------------------|-----------|
| **Chorus** | 5-50 ms | Yes (pitch modulation via Doppler) | Thickening, widening, "multiple voices" |
| **Flanger** | 0.5-5 ms | Minimal (comb filtering dominates) | Metallic, sweeping, jet-plane |
| **Phaser** | N/A (all-pass filters) | No (frequency-dependent phase shift) | Notchy, swirling |

For lo-fi: chorus is the primary modulation effect. Flanging is rarely used (too metallic). Phasing is occasionally used on guitars.

### Ensemble/Unison Effects

Ensemble effects (like the classic Roland Dimension D or Juno chorus) use multiple modulated delay lines with carefully chosen phase relationships:
- Typically 2-3 delay lines
- Each with its own LFO at slightly different rates
- Creates a richer, less "phasey" thickening than simple chorus
- More CPU-intensive but more natural-sounding

For lo-fi pads and keys, an ensemble-style chorus (multiple modulated delays) sounds more natural than a single-delay chorus.

---

## 10. Bitcrushing and Sample Rate Reduction

### How These Relate to Detuning

Bitcrushing and sample rate reduction are not "detuning" in the traditional sense, but they create artifacts that can sound like or interact with detuning:

### Sample Rate Reduction (Downsampling)

When you reduce the sample rate:
1. **Aliasing**: Frequencies above the Nyquist limit (sampleRate/2) fold back into the audible spectrum as new frequencies. These aliased frequencies are NOT harmonically related to the original, creating dissonant, metallic artifacts.
2. **Staircase quantization**: The signal becomes a series of discrete steps in time, adding high-frequency harmonics.
3. **Pitch tracking degradation**: The "stepped" time quantization can make pitch seem less stable, especially on pitched material.

**Typical lo-fi settings:**
| Sample Rate | Character |
|------------|-----------|
| 44100 Hz | Clean (standard) |
| 22050 Hz | Subtle dulling, slight grit |
| 11025 Hz | Obvious aliasing, "retro digital" |
| 8000 Hz | Telephone quality, heavy aliasing |
| 4000 Hz | Extreme degradation, 8-bit console character |

For lo-fi hip hop: **22050 Hz or 16000 Hz** gives subtle "vintage digital" quality without destroying musicality.

### Bit Depth Reduction (Bitcrushing)

Reducing bit depth quantizes amplitude:
| Bit Depth | Dynamic Range | Character |
|-----------|--------------|-----------|
| 16-bit | 96 dB | Clean (CD quality) |
| 12-bit | 72 dB | Classic sampler (SP-1200), subtle grit |
| 8-bit | 48 dB | Chiptune, obvious quantization noise |
| 6-bit | 36 dB | Heavy distortion, lo-fi character |
| 4-bit | 24 dB | Extreme, barely musical |

For lo-fi hip hop: **12-bit** is the sweet spot (SP-1200 territory). Drums at 10-12 bit sound characterfully gritty. Keys/pads benefit from higher bit depth (14-16) to preserve harmonic content.

**How bitcrushing mimics detuning**: The quantization noise created by bit reduction adds non-harmonic content that "smears" the perceived pitch. On sustained notes, the quantization error creates a subtle, gritty modulation that resembles micro-detuning.

---

## 11. Plugin and Hardware Reference

### RC-20 Retro Color (XLN Audio)

The Wobble module is the primary detuning tool:
- **Architecture**: Two independent LFOs (Wow + Flutter) mixed with a horizontal blend slider
- **Wow LFO rate**: 0.1 - 4 Hz
- **Flutter LFO rate**: 6 - 20 Hz
- **Blend control**: Crossfades between wow-dominant and flutter-dominant
- **Stereo mode**: Applies different modulation to L/R, creating chorus-like width
- **What it does technically**: Modulates the playback speed of the audio in real-time, creating pitch variation proportional to the LFO depth and rate
- **Typical lo-fi settings**: Wow-dominant (slider left of center), moderate depth, rate around 0.5-1.5 Hz

### Aberrant DSP SketchCassette II

The most technically sophisticated tape emulation:
- **Wow LFO shapes**: Sine, triangle, rounded sawtooth, inverse rounded sawtooth (4 shapes)
- **Flutter LFO shapes**: Sine, random (2 shapes)
- **FM mode**: Wow modulates flutter rate -- the flutter vibrato speed changes based on wow position. This creates complex, evolving pitch patterns that closely model real tape mechanics.
- **Tempo sync**: Both wow and flutter can sync to DAW tempo
- **Independent control**: Separate depth and rate for wow and flutter
- **The key differentiator**: The FM mode and multiple waveform options allow much more complex, realistic tape behavior than simple dual-LFO designs

### Wavesfactory Cassette

- **Stability parameter**: 0-100% (100% = no wobble, 0% = maximum)
- **Stability Randomness**: 0-100% adds unpredictable variation to the stability
- **Wow Depth/Rate**: Separate sinusoidal LFO for slow pitch changes
- **Flutter Depth/Rate**: Separate sinusoidal LFO for fast pitch changes
- **Both weighted by the Stability master control**: Stability acts as a macro controlling overall wobble amount

### iZotope Vinyl

- **Warp Depth**: Controls intensity of pitch warping (0-100%)
- **Warp Model**: Selects different pitch envelope shapes
- **RPM**: Affects periodicity (33/45/78) -- does not change pitch but changes the rate of warp cycling
- **Limitation**: Warp only works in AudioSuite/DirectX modes (not in real-time VST)
- **Best for**: Adding per-revolution vinyl-style pitch warping

### SP-404 (Roland)

Why it sounds "lo-fi" when pitching:
- **No time-stretching**: Pitch and speed are coupled. Pitch down = slower playback = darker, dreamier.
- **12-bit internal processing** (original SP-404): Adds quantization character
- **Built-in effects**: Vinyl Sim, Lo-Fi effect, and Cassette Sim effects baked into the workflow
- **The pitch range**: +/- 12 semitones on the MkII, with earlier models having more limited range (-4 to +2 on the SP-202)
- **Sample rate interaction**: Pitching down effectively reduces the sample rate of playback, compounding the lo-fi quality

### How Lofi Girl Channel Producers Use Detuning

Based on analysis of the genre's production techniques:
- **Primary technique**: Tape emulation on the master bus (RC-20 or similar) with subtle wow settings
- **Rhodes/keys**: 5-10 cents of per-note detuning plus chorus at 20-25% mix
- **Samples**: Often pitched down 1-3 semitones from original
- **Tempo**: 60-80 BPM (the slow tempo amplifies the perceived effect of pitch modulation)
- **High-frequency rolloff**: Combined with detuning, creates the "distant memory" quality
- **Layering**: Clean sound is produced first, then "made lo-fi" through processing chain:
  1. EQ (roll off highs above 8-12 kHz)
  2. Saturation/tape warmth
  3. Pitch wobble (wow/flutter)
  4. Vinyl crackle/noise
  5. Light compression

---

## 12. Tone.js / Web Audio Implementation

### Core Concept: The Detune AudioParam

Both the Web Audio `OscillatorNode` and Tone.js `Synth` expose a `detune` property:
- Type: `AudioParam` (a-rate for OscillatorNode)
- Unit: cents (100 cents = 1 semitone)
- Formula: `computedFrequency = frequency * 2^(detune/1200)`
- The `detune` AudioParam can be modulated by connecting other audio nodes to it

### Pattern 1: Tape Wow (Slow Pitch Drift)

```javascript
import * as Tone from 'tone';

// Create the synth
const synth = new Tone.PolySynth(Tone.Synth).toDestination();

// Create wow LFO
const wowLFO = new Tone.LFO({
  frequency: 0.8,        // 0.8 Hz - slow wow rate
  min: -15,              // -15 cents
  max: 15,               // +15 cents
  type: 'sine',          // Sine for smooth wow
  phase: 0               // Starting phase
});

// Connect LFO to synth's detune
wowLFO.connect(synth.detune);
wowLFO.start();
```

### Pattern 2: Tape Flutter (Fast Shimmer)

```javascript
const flutterLFO = new Tone.LFO({
  frequency: 10,          // 10 Hz - flutter rate
  min: -4,                // -4 cents
  max: 4,                 // +4 cents
  type: 'sine'
});

flutterLFO.connect(synth.detune);
flutterLFO.start();
```

### Pattern 3: Combined Wow + Flutter + Random Drift

```javascript
import * as Tone from 'tone';

class TapeWobble {
  constructor(targetNode) {
    // --- Wow: slow, deep pitch drift ---
    this.wowLFO = new Tone.LFO({
      frequency: 0.6,        // 0.6 Hz
      min: -12,              // -12 cents
      max: 12,               // +12 cents
      type: 'sine'
    });

    // --- Flutter: fast, shallow shimmer ---
    this.flutterLFO = new Tone.LFO({
      frequency: 11,         // 11 Hz
      min: -3,               // -3 cents
      max: 3,                // +3 cents
      type: 'triangle'       // Triangle for flutter
    });

    // --- Drift: very slow wander ---
    this.driftLFO = new Tone.LFO({
      frequency: 0.07,       // ~14-second cycle
      min: -5,               // -5 cents
      max: 5,                // +5 cents
      type: 'sine'
    });

    // Connect all three to the target's detune
    this.wowLFO.connect(targetNode.detune);
    this.flutterLFO.connect(targetNode.detune);
    this.driftLFO.connect(targetNode.detune);
  }

  start() {
    this.wowLFO.start();
    this.flutterLFO.start();
    this.driftLFO.start();
  }

  stop() {
    this.wowLFO.stop();
    this.flutterLFO.stop();
    this.driftLFO.stop();
  }

  dispose() {
    this.wowLFO.dispose();
    this.flutterLFO.dispose();
    this.driftLFO.dispose();
  }

  // Adjust intensity (0 = off, 1 = full lo-fi)
  setIntensity(value) {
    const v = Math.max(0, Math.min(1, value));
    this.wowLFO.min = -12 * v;
    this.wowLFO.max = 12 * v;
    this.flutterLFO.min = -3 * v;
    this.flutterLFO.max = 3 * v;
    this.driftLFO.min = -5 * v;
    this.driftLFO.max = 5 * v;
  }
}

// Usage:
const synth = new Tone.PolySynth(Tone.Synth).toDestination();
const tapeWobble = new TapeWobble(synth);
tapeWobble.start();
```

### Pattern 4: Per-Note Random Detuning (Micro-Detuning Table)

```javascript
// Generate a detuning table: 128 MIDI notes, Gaussian distribution
function generateDetuneTable(stdDev = 7) {
  const table = new Float32Array(128);
  for (let i = 0; i < 128; i++) {
    // Box-Muller transform for Gaussian distribution
    const u1 = Math.random();
    const u2 = Math.random();
    const gaussian = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
    table[i] = gaussian * stdDev; // cents, std dev = stdDev
  }
  return table;
}

const detuneTable = generateDetuneTable(7); // +/- ~7 cents std dev

// When triggering a note, apply the per-note detune
function playNote(synth, note, duration, time) {
  const midiNote = Tone.Frequency(note).toMidi();
  const noteDetune = detuneTable[midiNote];

  // Apply per-note detune before triggering
  synth.set({ detune: noteDetune });
  synth.triggerAttackRelease(note, duration, time);
}
```

**For PolySynth**: Since PolySynth manages multiple voices internally, per-note detuning requires a different approach -- either using individual Synth instances or applying the detune at the frequency level:

```javascript
// Alternative: Adjust frequency directly for PolySynth
function getDetunedFrequency(note, detuneTable) {
  const midiNote = Tone.Frequency(note).toMidi();
  const detuneCents = detuneTable[midiNote];
  const baseFreq = Tone.Frequency(note).toFrequency();
  return baseFreq * Math.pow(2, detuneCents / 1200);
}

// Usage with PolySynth:
const freq = getDetunedFrequency('C4', detuneTable);
polySynth.triggerAttackRelease(freq, '4n');
```

### Pattern 5: Vinyl Wobble (Eccentric Hole Simulation)

```javascript
class VinylWobble {
  constructor(targetNode, rpm = 33) {
    // Rotation frequency: 33 RPM = 0.55 Hz, 45 RPM = 0.75 Hz
    const rotationHz = rpm / 60;

    // Primary wow from eccentric hole
    this.rotationLFO = new Tone.LFO({
      frequency: rotationHz,
      min: -8,               // -8 cents (moderate eccentricity)
      max: 8,                // +8 cents
      type: 'sine'           // Smooth sinusoidal for rotation
    });

    // Secondary: warp from record surface irregularities
    this.warpLFO = new Tone.LFO({
      frequency: rotationHz * 2,  // 2x rotation for surface warps
      min: -3,
      max: 3,
      type: 'sine',
      phase: 45               // Phase offset for complexity
    });

    this.rotationLFO.connect(targetNode.detune);
    this.warpLFO.connect(targetNode.detune);
  }

  start() {
    this.rotationLFO.start();
    this.warpLFO.start();
  }

  stop() {
    this.rotationLFO.stop();
    this.warpLFO.stop();
  }

  dispose() {
    this.rotationLFO.dispose();
    this.warpLFO.dispose();
  }
}
```

### Pattern 6: Vibrato with Delayed Onset

```javascript
class LofiVibrato {
  constructor(targetNode) {
    this.lfo = new Tone.LFO({
      frequency: 4.5,         // 4.5 Hz vibrato rate
      min: -12,               // -12 cents
      max: 12,                // +12 cents
      type: 'sine',
      amplitude: 0            // Start silent
    });
    this.lfo.connect(targetNode.detune);
    this.lfo.start();
  }

  // Call on note attack: vibrato fades in after delay
  triggerVibrato(delay = 0.3, fadeIn = 0.4) {
    const now = Tone.now();
    this.lfo.amplitude.cancelScheduledValues(now);
    this.lfo.amplitude.setValueAtTime(0, now);
    // Hold at zero for 'delay' seconds
    this.lfo.amplitude.setValueAtTime(0, now + delay);
    // Ramp to full over 'fadeIn' seconds
    this.lfo.amplitude.linearRampToValueAtTime(1, now + delay + fadeIn);
  }

  // Call on note release
  releaseVibrato(fadeOut = 0.1) {
    const now = Tone.now();
    this.lfo.amplitude.cancelScheduledValues(now);
    this.lfo.amplitude.linearRampToValueAtTime(0, now + fadeOut);
  }

  dispose() {
    this.lfo.dispose();
  }
}
```

### Pattern 7: Lo-Fi Chorus via Delay Line

```javascript
class LofiChorus {
  constructor() {
    // Tone.js has a built-in Chorus, but here's the manual approach
    // for more control:

    this.input = new Tone.Gain();
    this.output = new Tone.Gain();
    this.wetGain = new Tone.Gain(0.25);  // 25% wet

    // Modulated delay line
    this.delay = new Tone.Delay({
      delayTime: 0.020,      // 20ms base delay
      maxDelay: 0.050
    });

    // LFO modulates the delay time
    this.lfo = new Tone.LFO({
      frequency: 0.8,        // 0.8 Hz
      min: 0.017,            // 17ms
      max: 0.023,            // 23ms (3ms depth around 20ms center)
      type: 'sine'
    });

    // Signal routing
    this.input.connect(this.output);              // Dry path
    this.input.connect(this.delay);               // Wet path
    this.delay.connect(this.wetGain);
    this.wetGain.connect(this.output);
    this.lfo.connect(this.delay.delayTime);

    this.lfo.start();
  }

  connect(destination) {
    this.output.connect(destination);
    return this;
  }

  dispose() {
    this.input.dispose();
    this.output.dispose();
    this.wetGain.dispose();
    this.delay.dispose();
    this.lfo.dispose();
  }
}

// Or use the built-in:
const chorus = new Tone.Chorus({
  frequency: 0.8,
  delayTime: 20,
  depth: 0.3,
  wet: 0.25,
  type: 'sine'
}).toDestination();
```

### Pattern 8: Raw Web Audio API -- Vibrato (Maximum Performance)

For mobile-critical paths, use the raw Web Audio API to avoid Tone.js overhead:

```javascript
function createVibrato(audioContext, targetOscillator, rate = 5, depthCents = 30) {
  // Create LFO oscillator
  const lfo = audioContext.createOscillator();
  lfo.frequency.value = rate;  // Hz
  lfo.type = 'sine';

  // Gain node to scale LFO output to cents
  const lfoGain = audioContext.createGain();
  lfoGain.gain.value = depthCents;  // Output range: +/- depthCents

  // Connect: lfo -> gain -> oscillator.detune
  lfo.connect(lfoGain);
  lfoGain.connect(targetOscillator.detune);

  lfo.start();
  return { lfo, lfoGain };
}
```

### Pattern 9: Adding Noise-Modulated Randomness (More Realistic Tape)

```javascript
// For more realistic tape emulation, add noise-based modulation
// Using a noise source filtered to the wow/flutter frequency range

class RealisticTapeWobble {
  constructor(targetNode) {
    // --- Deterministic wow ---
    this.wowLFO = new Tone.LFO({
      frequency: 0.7,
      min: -10,
      max: 10,
      type: 'sine'
    });

    // --- Deterministic flutter ---
    this.flutterLFO = new Tone.LFO({
      frequency: 12,
      min: -3,
      max: 3,
      type: 'triangle'
    });

    // --- Noise-based random component ---
    // Use Tone.Noise filtered to low frequencies for random drift
    this.noise = new Tone.Noise('pink');
    this.noiseFilter = new Tone.Filter({
      frequency: 4,          // Only pass frequencies below 4 Hz
      type: 'lowpass',
      rolloff: -24
    });
    this.noiseGain = new Tone.Gain(5); // Scale to +/- ~5 cents

    // Connect noise chain
    this.noise.connect(this.noiseFilter);
    this.noiseFilter.connect(this.noiseGain);

    // Connect all to target detune
    this.wowLFO.connect(targetNode.detune);
    this.flutterLFO.connect(targetNode.detune);
    this.noiseGain.connect(targetNode.detune);
  }

  start() {
    this.wowLFO.start();
    this.flutterLFO.start();
    this.noise.start();
  }

  stop() {
    this.wowLFO.stop();
    this.flutterLFO.stop();
    this.noise.stop();
  }

  dispose() {
    this.wowLFO.dispose();
    this.flutterLFO.dispose();
    this.noise.dispose();
    this.noiseFilter.dispose();
    this.noiseGain.dispose();
  }
}
```

### Pattern 10: Sample Pitch-Down with Tone.js Player

```javascript
// Method 1: Using playbackRate (changes both pitch and speed -- classic lo-fi)
const player = new Tone.Player('/samples/rhodes-chord.wav').toDestination();
player.playbackRate = Math.pow(2, -2 / 12); // -2 semitones = 0.891x speed

// Method 2: Using PitchShift (changes pitch, preserves speed)
const pitchShift = new Tone.PitchShift(-2).toDestination(); // -2 semitones
const player2 = new Tone.Player('/samples/rhodes-chord.wav');
player2.connect(pitchShift);

// Method 3: Using GrainPlayer (granular pitch shift, best quality)
const grainPlayer = new Tone.GrainPlayer({
  url: '/samples/rhodes-chord.wav',
  detune: -200,           // -200 cents = -2 semitones
  grainSize: 0.1,         // 100ms grains
  overlap: 0.05           // 50ms overlap
}).toDestination();
```

---

## 13. Combined Detuning Architecture

### The Full Lo-Fi Detuning Stack

For a complete lo-fi instrument chain, layer these detuning sources:

```
Per-Oscillator Detune (static, +/- 7 cents between voices)
    |
    v
Per-Note Micro-Detune (static table, +/- 5-8 cents per MIDI note)
    |
    v
Vibrato LFO (per-note, 4 Hz, +/- 10 cents, delayed onset)
    |
    v
Chorus Effect (20ms delay, 0.8 Hz mod, ~10 cents variation)
    |
    v
Channel Tape Flutter (12 Hz, +/- 3 cents)
    |
    v
Master Bus Tape Wow (0.6 Hz, +/- 12 cents)
    |
    v
Master Bus Drift (0.07 Hz, +/- 5 cents)
    |
    v
Master Bus Noise Modulation (filtered pink noise, +/- 3 cents)
```

**Total peak-to-peak pitch variation**: Up to ~50-80 cents combined, but different components operate at different rates and are rarely all at maximum simultaneously. The RMS deviation is typically 15-25 cents, which falls in the "warm and dreamy" zone.

### Implementation Priority

For a Web Audio / Tone.js app, implement in this order (highest impact first):

1. **Master bus wow** -- Single LFO, massive lo-fi impact, low CPU
2. **Per-note micro-detuning table** -- One-time generation, applied per note trigger
3. **Master bus flutter** -- Second LFO, adds shimmer
4. **Chorus on keys/pads** -- Standard Tone.Chorus or manual delay line
5. **Per-oscillator unison detune** -- Requires multiple oscillators per note
6. **Vibrato with delayed onset** -- Adds expressiveness
7. **Noise-based random modulation** -- Adds realism, higher CPU cost
8. **Drift LFO** -- Very subtle, lowest priority

---

## 14. Key Formulas and Conversions

### Cents to Frequency Ratio
```
ratio = 2^(cents / 1200)
```
Examples:
- 1 cent = 1.000578
- 5 cents = 1.00289
- 10 cents = 1.00579
- 50 cents = 1.02930
- 100 cents (1 semitone) = 1.05946
- 1200 cents (1 octave) = 2.0

### Frequency Ratio to Cents
```
cents = 1200 * log2(ratio)
```

### Speed Percentage to Cents
```
cents = 1200 * log2(1 + percentage/100)
```
Approximate shortcut: **1% speed change = ~17.3 cents**

Examples:
- 0.1% wow/flutter = ~1.7 cents
- 0.2% = ~3.5 cents
- 0.5% = ~8.6 cents
- 1.0% = ~17.3 cents
- 2.0% = ~34.3 cents

### Beating Frequency from Detune
```
beat_rate = base_freq * (2^(detune_cents/1200) - 1)
```

### LFO Depth to Pitch Deviation
For an LFO connected to OscillatorNode.detune with a GainNode:
```
Peak pitch deviation = GainNode.gain.value (in cents)
LFO output range is -1 to +1
Therefore: pitch swings from -gain to +gain cents
```

### Performance Budget (Mobile)

Based on Tone.js performance research:

| Component | Approximate CPU per instance | Notes |
|-----------|------|-------|
| Tone.LFO (sine) | Very low | Just an oscillator + scaling |
| Tone.LFO (custom) | Low | Slightly more than sine |
| Tone.Noise + Filter | Medium | Continuous audio generation |
| Tone.Chorus | Medium | Delay line + LFO |
| Tone.Synth | Medium | Per voice |
| Tone.PolySynth (8 voices) | High | 8x synth |
| Tone.PitchShift | High | Uses granular processing |
| ConvolverNode | Very High | Avoid on mobile |
| PannerNode (HRTF) | Very High | Use 'equalpower' instead |

**Mobile optimization tips:**
- Set `Tone.setContext(new Tone.Context({ latencyHint: "playback" }))` for scheduling-heavy apps
- Limit total polyphony to 4-6 voices on mobile
- Use raw Web Audio LFOs (OscillatorNode -> GainNode -> target.detune) instead of Tone.LFO where performance is critical
- Prefer `AudioBufferSourceNode.playbackRate` over `detune` for sample pitch (better browser support, especially Safari)
- Keep total active audio nodes under 30-40 on mobile
- Schedule slightly in advance (`+0.1` seconds) to prevent glitches
- Use `Tone.Draw.schedule()` for visual updates instead of doing DOM work in audio callbacks
- Load audio files carefully on memory-constrained devices -- large buffers can crash mobile browsers during decoding
- Avoid ConvolverNode and HRTF PannerNode on mobile

### Browser Compatibility Notes

- **OscillatorNode.detune**: a-rate AudioParam, well-supported across all modern browsers
- **AudioBufferSourceNode.detune**: Safari does NOT support this. Firefox limits to +/- 1 octave. Use `playbackRate` instead.
- **Multiple LFOs connected to same AudioParam**: Fully supported -- signals are summed additively. This is the basis for combining wow + flutter + drift on a single detune target.
- **GainNode for scaling**: Connecting LFO -> GainNode -> target.detune is the standard pattern for controlling modulation depth.

---

## Quick Reference: Lo-Fi Detuning Cheat Sheet

| Technique | Rate | Depth | Waveform | Target |
|-----------|------|-------|----------|--------|
| Wow | 0.5-2 Hz | +/- 10-15 cents | Sine | Master bus detune |
| Flutter | 8-14 Hz | +/- 2-4 cents | Triangle/Sine | Master bus detune |
| Drift | 0.05-0.2 Hz | +/- 3-8 cents | Sine | Master bus detune |
| Vinyl wobble | 0.55 Hz (33rpm) | +/- 5-8 cents | Sine | Master bus detune |
| Micro-detune | Static | +/- 5-8 cents | N/A (random table) | Per-note at trigger |
| Vibrato | 3-5 Hz | +/- 8-15 cents | Sine | Per-voice detune |
| Chorus (LFO) | 0.5-1.5 Hz | 2-4ms delay depth | Sine | Modulated delay line |
| Unison detune | Static | +/- 5-10 cents | N/A | Per-oscillator |

---

## Sources

- [Wow and Flutter Measurement - Wikipedia](https://en.wikipedia.org/wiki/Wow_and_flutter_measurement)
- [Wow & Flutter: What Is It, and How to Measure It - Medium](https://reflectiveobserver.medium.com/wow-flutter-explained-31cc9495d24)
- [Wow and Flutter - Baby Audio](https://babyaud.io/blog/wow-and-flutter)
- [Q. Are Wow and Flutter Key to That Analogue Tape Sound? - Sound On Sound](https://www.soundonsound.com/sound-advice/q-are-wow-and-flutter-key-analogue-tape-sound)
- [Wow Control by Goodhertz - Manual](https://manuals.goodhertz.com/3.13/wow-ctrl/)
- [Wow and Flutter Technical Background - akustik-messen.de](https://www.akustik-messen.de/index.php/en/background-information/hi-fi/wow-and-flutter)
- [Stereo Lab - WOW! Turntable Specifications](https://pspatialaudio.com/wow.htm)
- [RC-20 Retro Color - XLN Audio](https://www.xlnaudio.com/products/addictive_fx/effect/rc-20_retro_color)
- [XLN Audio RC-20 Retro Color Review - MusicRadar](https://www.musicradar.com/reviews/tech/xln-audio-rc-20-retro-color-646595)
- [SketchCassette II - Aberrant DSP](https://aberrantdsp.com/plugins/sketchcassette/)
- [SketchCassette II Released - Aberrant DSP](https://aberrantdsp.com/sketchcassette-ii-released/)
- [Wavesfactory Cassette Manual (PDF)](https://www.wavesfactory.com/audio-plugins/manuals/Cassette-User-Manual.pdf)
- [Wavesfactory Cassette - Official Page](https://www.wavesfactory.com/audio-plugins/cassette/)
- [iZotope Vinyl - Using Vinyl Documentation](https://s3.amazonaws.com/izotopedownloads/docs/vinyl/en/using-vinyl/index.html)
- [Chopped and Screwed - Wikipedia](https://en.wikipedia.org/wiki/Chopped_and_screwed)
- [Slowed and Reverb Explainer - OkayPlayer](https://www.okayplayer.com/originals/slowed-and-reverb-videos-lo-fi-hip-hop.html)
- [Flanger and Chorus Technical Details - Dmytro Duk](https://dmytroduk.com/music-notes/flanger-and-chorus/)
- [Chorus, Flange, and Phase Differences - Sweetwater](https://www.sweetwater.com/insync/chorus-flange-and-phase-pedals-difference/)
- [Unison vs. Chorus - KVR Audio Forum](https://www.kvraudio.com/forum/viewtopic.php?t=119267)
- [Detuning in Cents - KVR Audio Forum](https://www.kvraudio.com/forum/viewtopic.php?t=320443)
- [Bitcrushers and Sample Rate Reduction - Perfect Circuit](https://www.perfectcircuit.com/signal/weird-fx-bitcrushers)
- [OscillatorNode: detune - MDN Web Docs](https://developer.mozilla.org/en-US/docs/Web/API/OscillatorNode/detune)
- [Web Audio Vibrato Lesson - web-audio-school](https://github.com/mmckegg/web-audio-school/blob/master/lessons/1.%20Subtractive%20Synthesis/07.%20Vibrato/lesson.md)
- [Tone.js LFO Documentation](https://tonejs.github.io/docs/15.1.22/classes/LFO.html)
- [Tone.js Performance Wiki](https://github.com/Tonejs/Tone.js/wiki/Performance)
- [Tone.js PitchShift](https://tonejs.github.io/docs/15.0.4/classes/PitchShift.html)
- [Tone.js GrainPlayer](https://tonejs.github.io/docs/15.1.22/classes/GrainPlayer.html)
- [Pitch Shifting in Web Audio API - zpl.fi](https://zpl.fi/pitch-shifting-in-web-audio-api/)
- [Exploring Lo-Fi Techniques - Sweetwater](https://www.sweetwater.com/insync/exploring-lo-fi-techniques-to-achieve-warm-nostalgic-sounds/)
- [The Ultimate Guide to LoFi Hip-Hop Production - Audio Plugin Deals](https://audioplugin.deals/blog/the-ultimate-guide-to-lofi-hip-hop-production/)
- [How to Make Lo-Fi Music - Splice](https://splice.com/blog/how-to-make-lofi-music/)
- [Rhodes Piano Tuning Manual - fenderrhodes.com](https://www.fenderrhodes.com/org/manual/ch5.html)
- [How Often Should I Tune My Piano - Piano Price Point](https://pianopricepoint.com/how-often-should-i-tune-my-piano/)
- [Vibrato - SFZ Format](https://sfzformat.com/tutorials/vibrato/)
- [LFOs: The Ultimate Guide - Lunacy Audio](https://lunacy.audio/low-frequency-oscillator-lfos/)
- [FL Studio Wow & Flutter Module](https://www.image-line.com/fl-studio-learning/fl-studio-mobile-online-manual/html/plugins/FL%20Studio%20Mobile_Module_Wow_and_Flutter.htm)
- [How to Make Lo-Fi Hip Hop - Mastering The Mix](https://www.masteringthemix.com/blogs/learn/how-to-make-lo-fi-hip-hop)
- [Lo-fi Music - Wikipedia](https://en.wikipedia.org/wiki/Lo-fi_music)
