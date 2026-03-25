/* ============================================================
   MUZE — Audio Engine (Send/Return Bus Architecture)
   Sprint 2: Professional audio quality + new features
   ============================================================ */

MUZE.Audio = {
  // Synth sources
  padSynth: null, leadSynth: null, melodySynth: null,
  kickSynth: null, snareSynth: null, hatSynth: null,
  riserSynth: null,
  _binauralL: null, _binauralR: null,
  _binauralActive: false, _binauralFollowChord: false,
  _binauralBeatHz: 4, _binauralBaseFreq: 110,

  // Sub oscillator for pad
  _padSub: null,

  // Kick click layer
  _kickClick: null,

  // Snare body layer
  _snareBody: null,

  // Open hat
  _openHatSynth: null, _openHatFilter: null,

  // Arp filter
  _arpFilter: null, _arpFilterEnv: null,

  // Arp stereo widener (ping-pong)
  _arpPingPong: null,

  // Melody vibrato LFO
  _melodyVibrato: null, _melodyVibratoGain: null,

  // Master tape saturation
  _masterSaturation: null,

  // Channel strip nodes: { eq, panner, gain, reverbSend, delaySend }
  _nodes: {},

  // Master chain
  _masterFilter: null, _masterFilterGain: null,
  _masterEQ: null, _masterGain: null, _limiter: null,
  analyser: null,

  // Send buses
  _reverbBus: null, _delayBus: null,

  // Pad-specific insert
  _padChorus: null,

  // Riser internals
  _riserGain: null, _riserFilter: null,

  // Melody state
  _melodyPlaying: false,

  // Arpeggio
  _arpSeq: null, _arpNotes: [], _arpIdx: 0,
  _arpPatternType: 'up-down',

  async init() {
    // Force iOS audio route to Bluetooth
    try {
      const sa = new Audio('data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//tQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWGluZwAAAA8AAAACAAABhgC7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7//////////////////////////////////////////////////////////////////8AAAAATGF2YzU4LjEzAAAAAAAAAAAAAAAAJAAAAAAAAAABhgBWMKFOAAAAAAAAAAAAAAAAAAAA//tQZAAP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAETEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//tQZB8P8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVQ==');
      sa.setAttribute('playsinline', '');
      await sa.play();
    } catch (e) { /* OK */ }

    await Tone.start();
    Tone.Transport.bpm.value = MUZE.Config.BPM_DEFAULT;

    // ============================================================
    // MASTER CHAIN: Saturation → Filter → EQ → Gain → Limiter → Analyser → Out
    // ============================================================
    this.analyser = new Tone.Analyser('waveform', 256);
    this._limiter = new Tone.Limiter(MUZE.Mixer.master.limiterThreshold);
    this._limiter.connect(this.analyser);
    this.analyser.toDestination();

    this._masterGain = new Tone.Gain(1).connect(this._limiter);
    this._masterMeter = new Tone.Meter();
    this._masterGain.connect(this._masterMeter);
    this._masterEQ = new Tone.EQ3(0, 0, 0).connect(this._masterGain);

    // Tape saturation — very subtle warmth on the master bus
    this._masterSaturation = new Tone.Distortion({
      distortion: 0.08,
      wet: 0.15,
      oversample: '2x'
    });
    this._masterSaturation.connect(this._masterEQ);

    this._masterFilterGain = new Tone.Gain(1).connect(this._masterSaturation);
    this._masterFilter = new Tone.Filter({ frequency: 2000, type: 'lowpass', rolloff: -24, Q: 1.2 }).connect(this._masterFilterGain);

    // ============================================================
    // SEND BUSES (shared reverb + delay, returns bypass face filter)
    // ============================================================
    // Subtle modulation on reverb tail for lushness
    this._reverbMod = new Tone.Chorus({
      frequency: 0.3,
      delayTime: 3.5,
      depth: 0.15,
      wet: 0.3
    });
    this._reverbMod.start();
    this._reverbMod.connect(this._masterSaturation);

    this._reverbBus = new Tone.Reverb({ decay: 3.2, preDelay: 0.035 }).connect(this._reverbMod);
    await this._reverbBus.ready;
    this._reverbBus.wet.value = 1; // fully wet — send level controls amount

    this._delayBus = new Tone.FeedbackDelay({ delayTime: '8n.', feedback: 0.3, wet: 1 }).connect(this._masterSaturation);

    // ============================================================
    // SYNTHS — Professional quality
    // ============================================================

    // ---- PAD SYNTH: FM + detuning + sub oscillator ----
    // Main pad with ±5 cent detuning for width
    this.padSynth = new Tone.PolySynth(Tone.FMSynth, {
      maxPolyphony: 6,
      voice: {
        harmonicity: 2, modulationIndex: 1.2,
        oscillator: { type: 'sine' },
        envelope: { attack: 1.0, decay: 0.4, sustain: 0.85, release: 2.5 },
        modulation: { type: 'triangle' },
        modulationEnvelope: { attack: 0.6, decay: 0.3, sustain: 0.7, release: 2.0 }
      }
    });
    // Detune for stereo width (±5 cents spread)
    this.padSynth.set({ detune: 5 });

    // Sub oscillator: one octave down, sine, subtle
    this._padSub = new Tone.PolySynth(Tone.Synth, {
      maxPolyphony: 6,
      oscillator: { type: 'sine' },
      envelope: { attack: 1.2, decay: 0.5, sustain: 0.9, release: 3.0 },
    });
    this._padSub.volume.value = -20; // subtle sub presence

    // Chorus insert for pad (enhanced: slightly higher rate for shimmer)
    this._padChorus = new Tone.Chorus({ frequency: 1.2, delayTime: 4.0, depth: 0, wet: 0.5 });
    this._padChorus.start();

    // Second detuned pad layer for unison width (detuned -5 cents)
    this._padDetune2 = new Tone.PolySynth(Tone.FMSynth, {
      maxPolyphony: 6,
      voice: {
        harmonicity: 2, modulationIndex: 1.2,
        oscillator: { type: 'sine' },
        envelope: { attack: 1.0, decay: 0.4, sustain: 0.85, release: 2.5 },
        modulation: { type: 'triangle' },
        modulationEnvelope: { attack: 0.6, decay: 0.3, sustain: 0.7, release: 2.0 }
      }
    });
    this._padDetune2.set({ detune: -5 });
    this._padDetune2.volume.value = -6; // slightly quieter for depth

    // Wire all pad layers through chorus
    this.padSynth.connect(this._padChorus);
    this._padSub.connect(this._padChorus);
    this._padDetune2.connect(this._padChorus);
    this._createChannelStrip('pad', this._padChorus);

    // ---- ARPEGGIO SYNTH: Filter envelope + stereo ping-pong ----
    this.leadSynth = new Tone.PolySynth(Tone.Synth, {
      maxPolyphony: 8,
      oscillator: { type: 'sawtooth' },
      envelope: { attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.8 },
    });

    // Filter with envelope for the arp — gives it that classic analog pluck
    this._arpFilter = new Tone.Filter({
      frequency: 2000,
      type: 'lowpass',
      rolloff: -24,
      Q: 2
    });

    // Stereo ping-pong delay (insert, very subtle for width)
    this._arpPingPong = new Tone.PingPongDelay({
      delayTime: '16n',
      feedback: 0.15,
      wet: 0.2
    });

    this.leadSynth.connect(this._arpFilter);
    this._arpFilter.connect(this._arpPingPong);
    this._createChannelStrip('arp', this._arpPingPong);

    // ---- MELODY SYNTH: Expressive filter envelope + vibrato ----
    this.melodySynth = new Tone.MonoSynth({
      oscillator: { type: 'triangle' },
      envelope: { attack: 0.05, decay: 0.2, sustain: 0.7, release: 0.4 },
      filterEnvelope: {
        attack: 0.02, decay: 0.3, sustain: 0.3, release: 0.5,
        baseFrequency: 200, octaves: 4.5, exponent: 2
      },
      filter: { type: 'lowpass', rolloff: -24, Q: 2 }
    });

    // Vibrato LFO for melody expressiveness
    this._melodyVibrato = new Tone.LFO({
      frequency: 5, // 5 Hz vibrato
      min: -15,     // ±15 cents
      max: 15,
      type: 'sine'
    });
    this._melodyVibratoGain = new Tone.Gain(0); // starts off, user can enable
    this._melodyVibrato.connect(this._melodyVibratoGain);
    this._melodyVibratoGain.connect(this.melodySynth.detune);
    this._melodyVibrato.start();

    this._createChannelStrip('melody', this.melodySynth);

    // ---- DRUMS — Layered for professional sound ----

    // KICK: MembraneSynth + click transient (short noise burst)
    this.kickSynth = new Tone.MembraneSynth({
      pitchDecay: 0.06, octaves: 7, oscillator: { type: 'sine' },
      envelope: { attack: 0.002, decay: 0.5, sustain: 0, release: 0.5 }
    });
    // Click transient: short filtered noise burst for definition
    this._kickClick = new Tone.NoiseSynth({
      noise: { type: 'white' },
      envelope: { attack: 0.001, decay: 0.015, sustain: 0, release: 0.01 }
    });
    this._kickClickFilter = new Tone.Filter({ frequency: 3500, type: 'bandpass', Q: 1.5 });
    this._kickClick.connect(this._kickClickFilter);
    // Mix kick layers
    const kickMix = new Tone.Gain(1);
    this.kickSynth.connect(kickMix);
    this._kickClickFilter.connect(kickMix);
    this._kickClick.volume.value = -12; // subtle click
    this._createChannelStrip('kick', kickMix);

    // SNARE: NoiseSynth (top) + short tonal body (bottom)
    this.snareSynth = new Tone.NoiseSynth({
      noise: { type: 'white' },
      envelope: { attack: 0.002, decay: 0.18, sustain: 0, release: 0.18 }
    });
    // Snare body: short pitched sine for "thwack"
    this._snareBody = new Tone.MembraneSynth({
      pitchDecay: 0.03, octaves: 3, oscillator: { type: 'sine' },
      envelope: { attack: 0.001, decay: 0.08, sustain: 0, release: 0.06 }
    });
    this._snareBody.volume.value = -8;
    const snareMix = new Tone.Gain(1);
    this.snareSynth.connect(snareMix);
    this._snareBody.connect(snareMix);
    this._createChannelStrip('snare', snareMix);

    // HAT: Closed hat (crisp) + open hat variation
    // Closed hat: short, crisp
    this.hatSynth = new Tone.NoiseSynth({
      noise: { type: 'white' },
      envelope: { attack: 0.001, decay: 0.04, sustain: 0, release: 0.03 }
    });
    this._hatFilter = new Tone.Filter({ frequency: 9000, type: 'highpass', rolloff: -24 });
    // Open hat: longer decay
    this._openHatSynth = new Tone.NoiseSynth({
      noise: { type: 'white' },
      envelope: { attack: 0.001, decay: 0.25, sustain: 0.05, release: 0.2 }
    });
    this._openHatFilter = new Tone.Filter({ frequency: 8000, type: 'highpass', rolloff: -12 });
    this._openHatSynth.connect(this._openHatFilter);

    const hatMix = new Tone.Gain(1);
    this.hatSynth.connect(this._hatFilter);
    this._hatFilter.connect(hatMix);
    this._openHatFilter.connect(hatMix);
    this._createChannelStrip('hat', hatMix);

    // ---- Binaural -> Channel Strip ----
    const binLPan = new Tone.Panner(-1);
    const binRPan = new Tone.Panner(1);
    const binMix = new Tone.Gain(1);
    this._binauralL = new Tone.Oscillator({ type: 'sine', frequency: 110 }).connect(binLPan);
    this._binauralR = new Tone.Oscillator({ type: 'sine', frequency: 114 }).connect(binRPan);
    binLPan.connect(binMix);
    binRPan.connect(binMix);
    this._createChannelStrip('binaural', binMix);

    // ---- Riser -> Channel Strip ----
    this._riserFilter = new Tone.Filter({ frequency: 200, type: 'bandpass', Q: 2 });
    this._riserGain = new Tone.Gain(0).connect(this._riserFilter);
    this.riserSynth = new Tone.Noise('pink').connect(this._riserGain);
    this.riserSynth.start();
    this._createChannelStrip('riser', this._riserFilter);

    // ---- GrainPlayer for sample-based pad ----
    this._padGrain = new Tone.GrainPlayer({ grainSize: 0.2, overlap: 0.1, loop: true });
    this._padGrain.volume.value = -60;
    this._padGrain.connect(this._padChorus); // same insert chain as synth pad
    this._padSampleMode = false;

    Tone.Transport.start();
    MUZE.State.audioReady = true;
  },

  // ============================================================
  // CHANNEL STRIP FACTORY
  // ============================================================
  _createChannelStrip(name, source) {
    const ch = MUZE.Mixer.channels[name];
    const eq = new Tone.EQ3(ch.eqLow, ch.eqMid, ch.eqHigh);
    const panner = new Tone.Panner(ch.pan);
    const gain = new Tone.Gain(Tone.dbToGain(ch.volume));
    const reverbSend = new Tone.Gain(ch.reverbSend);
    const delaySend = new Tone.Gain(ch.delaySend);

    // Wire: Source -> EQ -> Panner -> Gain
    source.connect(eq);
    eq.connect(panner);
    panner.connect(gain);

    // Dry path: face-linked channels go through master filter, others bypass to master saturation
    const faceLinked = MUZE.Mixer.channels[name].faceLinked;
    gain.connect(faceLinked ? this._masterFilter : this._masterSaturation);

    // Send paths (post-fader)
    gain.connect(reverbSend);
    reverbSend.connect(this._reverbBus);
    gain.connect(delaySend);
    delaySend.connect(this._delayBus);

    // Metering: connect gain to a Tone.Meter for real-time level readout
    const meter = new Tone.Meter();
    gain.connect(meter);

    this._nodes[name] = { eq, panner, gain, reverbSend, delaySend, meter };
  },

  // ============================================================
  // REAL-TIME PARAMETER UPDATES (face-driven)
  // ============================================================
  updateParams(state) {
    const C = MUZE.Config;

    // Master filter: head pitch
    const pitchN = 1 - Math.max(0, Math.min(1, (state.headPitch + 0.4) / 0.8));
    const filterFreq = C.FILTER_FREQ_MIN * Math.pow(C.FILTER_FREQ_MAX / C.FILTER_FREQ_MIN, pitchN);
    this._masterFilter.frequency.rampTo(filterFreq, 0.08);
    this._masterFilterGain.gain.rampTo(1 + (1 - pitchN) * 0.35, 0.08);

    // Reverb/delay sends: eye openness scales face-linked channels
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const data = MUZE.Mixer.channels[ch];
      const node = this._nodes[ch];
      if (!node || !data.faceLinked) continue;
      node.reverbSend.gain.rampTo(state.eyeOpenness * data.reverbSend, 0.1);
      node.delaySend.gain.rampTo(state.eyeOpenness * data.delaySend, 0.1);
    }

    // Chorus: head roll (pad insert only)
    const rollN = Math.min(1, Math.abs(state.headRoll) / 0.35);
    this._padChorus.depth = C.CHORUS_DEPTH_MIN + rollN * (C.CHORUS_DEPTH_MAX - C.CHORUS_DEPTH_MIN);

    // Arp filter envelope simulation: mouth openness opens the filter
    if (this._arpFilter) {
      const mouthN = Math.max(0, Math.min(1, state.mouthOpenness));
      const arpFilterFreq = 800 + mouthN * 6000;
      this._arpFilter.frequency.rampTo(arpFilterFreq, 0.08);
    }

    // Mode color update
    const modeName = MUZE.Music.getScaleName(state.currentScale);
    if (modeName !== state.currentModeName) {
      state.currentModeName = modeName;
      const colors = C.MODE_COLORS[modeName];
      if (colors) {
        document.documentElement.style.setProperty('--muze-accent', colors.accent);
        document.documentElement.style.setProperty('--muze-accent-rgb', colors.rgb);
        document.documentElement.style.setProperty('--muze-accent-glow', `rgba(${colors.rgb}, 0.25)`);
      }
    }
  },

  // ============================================================
  // PAD (triggers all layers)
  // ============================================================
  triggerPad(notes) {
    this.padSynth.releaseAll();
    this._padDetune2.releaseAll();
    this._padSub.releaseAll();
    this.padSynth.triggerAttack(notes, Tone.now(), 0.4);
    this._padDetune2.triggerAttack(notes, Tone.now(), 0.35);
    // Sub: one octave down
    const subNotes = notes.map(n => {
      const freq = Tone.Frequency(n).toFrequency();
      return Tone.Frequency(freq / 2).toNote();
    });
    this._padSub.triggerAttack(subNotes, Tone.now(), 0.3);
  },
  releasePad() {
    this.padSynth.releaseAll();
    this._padDetune2.releaseAll();
    this._padSub.releaseAll();
  },

  // ============================================================
  // HAND MELODY
  // ============================================================
  startMelody(note) {
    if (!this.melodySynth) return;
    this.melodySynth.triggerAttack(MUZE.Music.midiToNote(note), Tone.now(), 0.7);
    this._melodyPlaying = true;
  },
  updateMelody(note) {
    if (!this.melodySynth) return;
    if (!this._melodyPlaying) { this.startMelody(note); return; }
    this.melodySynth.setNote(MUZE.Music.midiToNote(note));
  },
  stopMelody() {
    if (this._melodyPlaying && this.melodySynth) {
      this.melodySynth.triggerRelease(Tone.now());
      this._melodyPlaying = false;
    }
  },
  setPortamento(on) { if (this.melodySynth) this.melodySynth.portamento = on ? 0.3 : 0; },

  // Vibrato control
  setVibratoAmount(amount) {
    // amount: 0-1
    if (this._melodyVibratoGain) {
      this._melodyVibratoGain.gain.rampTo(amount, 0.1);
    }
  },

  // ============================================================
  // DRUMS (layered)
  // ============================================================
  triggerDrum(type, velocity, isOpenHat) {
    const vel = velocity || 0.7;
    const now = Tone.now();
    switch (type) {
      case 'kick':
        this.kickSynth.triggerAttackRelease('C1', '8n', now, vel);
        this._kickClick.triggerAttackRelease('32n', now, vel * 0.6);
        // Sidechain: duck the pad
        if (MUZE.Sidechain) MUZE.Sidechain.duck();
        break;
      case 'snare':
        this.snareSynth.triggerAttackRelease('8n', now, vel);
        this._snareBody.triggerAttackRelease('E3', '16n', now, vel * 0.5);
        break;
      case 'hat':
        if (isOpenHat) {
          this._openHatSynth.triggerAttackRelease('8n', now, vel * 0.5);
        } else {
          this.hatSynth.triggerAttackRelease('32n', now, vel);
        }
        break;
    }
  },

  // ============================================================
  // RISER (hold -> build -> drop)
  // ============================================================
  _preRiserGains: {},

  startRiser() {
    this._riserGain.gain.rampTo(0.3, 4);
    this._riserFilter.frequency.rampTo(4000, 4);
    // Duck pad + drums via their channel gains
    for (const ch of ['pad', 'kick', 'snare', 'hat']) {
      const node = this._nodes[ch];
      if (node) {
        this._preRiserGains[ch] = node.gain.gain.value;
        node.gain.gain.rampTo(node.gain.gain.value * 0.1, 4);
      }
    }
  },

  dropRiser() {
    this._riserGain.gain.rampTo(0, 0.05);
    this._riserFilter.frequency.rampTo(200, 0.1);
    // Big kick hit
    this.kickSynth.triggerAttackRelease('C1', '4n', Tone.now(), 1);
    this._kickClick.triggerAttackRelease('32n', Tone.now(), 0.8);
    // Reverb wash: temporarily max all reverb sends
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const node = this._nodes[ch];
      if (!node) continue;
      node._reverbSendPre = node.reverbSend.gain.value;
      node.reverbSend.gain.rampTo(0.9, 0.05);
    }
    setTimeout(() => {
      for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
        const node = this._nodes[ch];
        if (!node || node._reverbSendPre === undefined) continue;
        node.reverbSend.gain.rampTo(node._reverbSendPre, 2);
      }
    }, 300);
    // Restore ducked volumes
    for (const ch of ['pad', 'kick', 'snare', 'hat']) {
      const node = this._nodes[ch];
      if (node && this._preRiserGains[ch] !== undefined) {
        node.gain.gain.rampTo(this._preRiserGains[ch], 0.05);
      }
    }
    this._preRiserGains = {};
  },

  cancelRiser() {
    this._riserGain.gain.rampTo(0, 0.3);
    this._riserFilter.frequency.rampTo(200, 0.3);
    for (const ch of ['pad', 'kick', 'snare', 'hat']) {
      const node = this._nodes[ch];
      if (node && this._preRiserGains[ch] !== undefined) {
        node.gain.gain.rampTo(this._preRiserGains[ch], 0.3);
      }
    }
    this._preRiserGains = {};
  },

  // ============================================================
  // ARPEGGIO (multiple pattern types)
  // ============================================================
  startArpeggio() {
    if (this._arpSeq) return;
    this._arpIdx = 0;
    this._arpSeq = new Tone.Loop((time) => {
      if (!this._arpNotes.length || !this.leadSynth) return;
      const note = this._arpNotes[this._arpIdx % this._arpNotes.length];
      this.leadSynth.triggerAttackRelease(note, '8n', time, 0.5);

      // Animate arp filter for each note (pluck effect)
      if (this._arpFilter) {
        this._arpFilter.frequency.setValueAtTime(6000, time);
        this._arpFilter.frequency.exponentialRampToValueAtTime(1200, time + 0.15);
      }

      this._arpIdx++;
    }, '8n');
    this._arpSeq.start(0);
  },

  updateArpNotes(scale, root) {
    const baseNotes = scale.map(i => MUZE.Music.midiToNote(root + i));
    const pattern = MUZE.Config.ARP_PATTERNS[MUZE.State.arpPatternIdx] || 'up-down';

    switch (pattern) {
      case 'up':
        this._arpNotes = [...baseNotes];
        break;
      case 'down':
        this._arpNotes = [...baseNotes].reverse();
        break;
      case 'random': {
        // Fisher-Yates shuffle but keep stable within a cycle
        const shuffled = [...baseNotes];
        for (let i = shuffled.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
        }
        this._arpNotes = shuffled;
        break;
      }
      case 'up-up-down': {
        const up1 = [...baseNotes];
        const up2 = [...baseNotes];
        const down = [...baseNotes].reverse().slice(1);
        this._arpNotes = [...up1, ...up2, ...down];
        break;
      }
      case 'played':
        // Just play in scale order (like 'up' but wraps at chord tones)
        this._arpNotes = [...baseNotes];
        break;
      case 'up-down':
      default: {
        const up = [...baseNotes];
        const down = [...baseNotes].reverse().slice(1);
        this._arpNotes = [...up, ...down];
        break;
      }
    }
  },

  stopArpeggio() {
    if (this._arpSeq) { this._arpSeq.stop(); this._arpSeq.dispose(); this._arpSeq = null; }
    this._arpNotes = [];
  },

  // ============================================================
  // BINAURAL
  // ============================================================
  toggleBinaural() {
    this._binauralActive = !this._binauralActive;
    if (this._binauralActive) {
      this._binauralL.start(); this._binauralR.start();
      this._updateBinauralFreq(this._binauralBaseFreq);
    } else {
      this._binauralL.stop(); this._binauralR.stop();
    }
    return this._binauralActive;
  },
  setBinauralBeatHz(hz) {
    this._binauralBeatHz = hz;
    if (this._binauralActive) this._updateBinauralFreq(this._binauralL.frequency.value);
  },
  setBinauralVolume(db) {
    this._binauralL.volume.value = db;
    this._binauralR.volume.value = db;
  },
  _updateBinauralFreq(baseFreq) {
    const half = this._binauralBeatHz / 2;
    this._binauralL.frequency.rampTo(baseFreq - half, 0.1);
    this._binauralR.frequency.rampTo(baseFreq + half, 0.1);
  },
  updateBinauralFromChord(notes) {
    if (!this._binauralActive || !this._binauralFollowChord) return;
    const freq = Tone.Frequency(notes[0]).toFrequency() / 2;
    this._updateBinauralFreq(freq);
  },

  // ============================================================
  // EFFECTS
  // ============================================================
  reverbThrow() {
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const node = this._nodes[ch];
      if (!node) continue;
      node._reverbSendPre = node.reverbSend.gain.value;
      node.reverbSend.gain.rampTo(0.9, 0.05);
    }
    setTimeout(() => {
      for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
        const node = this._nodes[ch];
        if (!node || node._reverbSendPre === undefined) continue;
        node.reverbSend.gain.rampTo(node._reverbSendPre, 1.5);
      }
    }, 200);
  },

  tapeStop() {
    const orig = Tone.Transport.bpm.value;
    Tone.Transport.bpm.rampTo(20, 0.4);
    [this.padSynth, this._padDetune2, this._padSub, this.leadSynth, this.melodySynth].forEach(s => {
      if (s) { s.set({ detune: 0 }); s.set({ detune: -2400 }); }
    });
    setTimeout(() => {
      Tone.Transport.bpm.rampTo(orig, 0.15);
      [this.padSynth, this._padDetune2, this.leadSynth, this.melodySynth].forEach(s => {
        if (s) s.set({ detune: 0 });
      });
      // Restore pad detuning
      this.padSynth.set({ detune: 5 });
      this._padDetune2.set({ detune: -5 });
      this._padSub.set({ detune: 0 });
    }, 500);
  },

  // ============================================================
  // BPM CONTROL
  // ============================================================
  setBPM(bpm) {
    const clamped = Math.max(MUZE.Config.BPM_MIN, Math.min(MUZE.Config.BPM_MAX, bpm));
    MUZE.State.bpm = clamped;
    Tone.Transport.bpm.rampTo(clamped, 0.1);
  },

  getBPM() {
    return Math.round(Tone.Transport.bpm.value);
  },

  // ============================================================
  // SWING CONTROL
  // ============================================================
  setSwing(amount) {
    // amount: 0-100 percentage
    MUZE.State.swing = amount;
    // Tone.js swing: 0-1 range, applied to 8th notes
    Tone.Transport.swing = amount / 100;
    Tone.Transport.swingSubdivision = '8n';
  },

  // ============================================================
  // PRESET SYSTEM
  // ============================================================
  applyPreset(presetIdx) {
    const P = MUZE.Config.PRESETS[presetIdx];
    if (!P) return;
    MUZE.State.presetIdx = presetIdx;

    const FADE = 2; // 2-second crossfade for smooth transitions

    // BPM — smooth ramp
    Tone.Transport.bpm.rampTo(P.bpm, FADE);
    MUZE.State.bpm = P.bpm;

    // Root note
    MUZE.State.rootOffset = P.rootOffset;

    // Pad synth params — oscillator types switch immediately, envelopes ramp
    this.padSynth.set({
      oscillator: { type: P.padOsc },
      harmonicity: P.padHarm,
      modulationIndex: P.padMod,
      envelope: { attack: P.padAttack, release: P.padRelease }
    });
    this._padDetune2.set({
      oscillator: { type: P.padOsc },
      harmonicity: P.padHarm,
      modulationIndex: P.padMod,
      envelope: { attack: P.padAttack, release: P.padRelease }
    });

    // Arp synth params
    this.leadSynth.set({
      oscillator: { type: P.arpOsc },
      envelope: { attack: P.arpAttack, decay: P.arpDecay, sustain: P.arpSustain, release: P.arpRelease }
    });

    // Melody synth params
    this.melodySynth.set({
      oscillator: { type: P.melOsc },
      envelope: { attack: P.melAttack, decay: P.melDecay, sustain: P.melSustain, release: P.melRelease }
    });

    // Volumes — crossfade using gain ramps instead of hard-setting
    const rampVol = (ch, db) => {
      const node = MUZE.Audio._nodes[ch];
      if (node) {
        node.gain.gain.rampTo(Tone.dbToGain(db), FADE);
        MUZE.Mixer.channels[ch].volume = db;
      }
    };
    rampVol('pad', P.padVolume);
    rampVol('arp', P.arpVolume);
    rampVol('melody', P.melodyVolume);
    rampVol('kick', P.kickVolume);
    rampVol('snare', P.snareVolume);
    rampVol('hat', P.hatVolume);

    // Sends — crossfade
    const rampSend = (ch, type, val) => {
      const node = MUZE.Audio._nodes[ch];
      if (!node) return;
      if (type === 'reverb') {
        node.reverbSend.gain.rampTo(val, FADE);
        MUZE.Mixer.channels[ch].reverbSend = val;
      } else {
        node.delaySend.gain.rampTo(val, FADE);
        MUZE.Mixer.channels[ch].delaySend = val;
      }
    };
    rampSend('pad', 'reverb', P.padReverb);
    rampSend('pad', 'delay', P.padDelay);
    rampSend('arp', 'reverb', P.arpReverb);
    rampSend('arp', 'delay', P.arpDelay);

    // Reverb decay & delay feedback
    if (this._reverbBus) {
      try {
        this._reverbBus.decay = P.reverbDecay;
      } catch(e) { /* may not be ramp-able */ }
    }
    if (this._delayBus) {
      this._delayBus.feedback.rampTo(P.delayFeedback, FADE);
    }

    // Arp pattern
    MUZE.State.arpPatternIdx = MUZE.Config.ARP_PATTERNS.indexOf(P.arpPattern);
    if (MUZE.State.arpPatternIdx < 0) MUZE.State.arpPatternIdx = 0;

    // Rhythm pattern
    if (MUZE.AutoRhythm._active) {
      MUZE.AutoRhythm._patIdx = P.rhythmPattern;
    }

    // Swing — smooth transition
    this.setSwing(P.swing);
  },

  // ============================================================
  // SAMPLE SWITCHING
  // ============================================================
  setPadSample(sampleId) {
    const buf = MUZE.SampleLib.get(sampleId);
    if (!buf) return;
    MUZE.State.padSampleId = sampleId;
    this._padGrain.buffer = buf;
    if (!this._padSampleMode) {
      this._padSampleMode = true;
      this.padSynth.volume.rampTo(-60, 0.3);
      this._padDetune2.volume.rampTo(-60, 0.3);
      this._padSub.volume.rampTo(-60, 0.3);
      this._padGrain.volume.rampTo(-14, 0.3);
      this._padGrain.start();
    }
  },
  setPadSynth() {
    this._padSampleMode = false;
    MUZE.State.padSampleId = null;
    this.padSynth.volume.rampTo(-14, 0.3);
    this._padDetune2.volume.rampTo(-6, 0.3);
    this._padSub.volume.rampTo(-20, 0.3);
    this._padGrain.volume.rampTo(-60, 0.3);
    setTimeout(() => { try { this._padGrain.stop(); } catch(e) {} }, 400);
  },

  // ============================================================
  // WAVEFORM DATA (for visualizer)
  // ============================================================
  getWaveform() {
    if (!this.analyser) return null;
    return this.analyser.getValue();
  }
};

// ============================================================
// MIC RECORDER
// ============================================================
MUZE.MicRecorder = {
  _mediaStream: null, _mediaRecorder: null, _chunks: [], _recording: false,
  async record(durationMs) {
    if (this._recording) return null;
    this._recording = true;
    this._mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    this._chunks = [];
    return new Promise((resolve) => {
      this._mediaRecorder = new MediaRecorder(this._mediaStream);
      this._mediaRecorder.ondataavailable = (e) => { if (e.data.size > 0) this._chunks.push(e.data); };
      this._mediaRecorder.onstop = async () => {
        this._mediaStream.getTracks().forEach(t => t.stop());
        this._recording = false;
        const blob = new Blob(this._chunks, { type: 'audio/webm' });
        const arrayBuf = await blob.arrayBuffer();
        const audioBuf = await Tone.context.decodeAudioData(arrayBuf);
        const toneBuf = new Tone.ToneAudioBuffer().fromArray(audioBuf.getChannelData(0));
        resolve(toneBuf);
      };
      this._mediaRecorder.start();
      setTimeout(() => { if (this._mediaRecorder.state === 'recording') this._mediaRecorder.stop(); }, durationMs || 2000);
    });
  },
  isRecording() { return this._recording; }
};

// ============================================================
// AUTO RHYTHM (with swing support)
// ============================================================
MUZE.AutoRhythm = {
  _seq: null, _active: false, _patIdx: 0,
  start() {
    if (this._seq) this._seq.dispose();
    this._active = true;
    this._seq = new Tone.Sequence((t, s) => {
      const p = MUZE.Config.RHYTHM_PATTERNS[this._patIdx];
      if (p.kick[s]) MUZE.Audio.triggerDrum('kick', 0.7);
      if (p.snare[s]) MUZE.Audio.triggerDrum('snare', 0.6);
      if (p.hat[s]) {
        // Every 4th hat hit has a chance to be open hat (adds variation)
        const isOpen = (s % 8 === 6);
        MUZE.Audio.triggerDrum('hat', 0.4, isOpen);
      }
    }, [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15], '16n');
    this._seq.start(0);
  },
  stop() { this._active = false; if (this._seq) { this._seq.stop(); this._seq.dispose(); this._seq = null; } },
  toggle() { if (this._active) this.stop(); else this.start(); return this._active; },
  nextPattern() { this._patIdx = (this._patIdx + 1) % MUZE.Config.RHYTHM_PATTERNS.length; },
  prevPattern() { this._patIdx = (this._patIdx - 1 + MUZE.Config.RHYTHM_PATTERNS.length) % MUZE.Config.RHYTHM_PATTERNS.length; },
  isActive() { return this._active; },
  getPatternName() { return MUZE.Config.RHYTHM_PATTERNS[this._patIdx].name; }
};
