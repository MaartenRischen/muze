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
  _binauralActive: false, _binauralFollowChord: true,
  _binauralBeatHz: 2.5, _binauralBaseFreq: 110,

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

  // (Removed: _arpPingPong — shared delay bus handles this)

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

  // Arpeggio 1 + 2
  _arpSeq: null, _arpNotes: [], _arpIdx: 0,
  _arp2Seq: null, _arp2Notes: [], _arp2Idx: 0,

  async init() {
    // Force iOS audio route to Bluetooth
    try {
      const sa = new Audio('data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//tQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWGluZwAAAA8AAAACAAABhgC7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7u7//////////////////////////////////////////////////////////////////8AAAAATGF2YzU4LjEzAAAAAAAAAAAAAAAAJAAAAAAAAAABhgBWMKFOAAAAAAAAAAAAAAAAAAAA//tQZAAP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAETEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//tQZB8P8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVQ==');
      sa.setAttribute('playsinline', '');
      await sa.play();
    } catch (e) { /* OK */ }

    // Apply latency mode before starting audio
    const latencyMode = MUZE.State.latencyMode || 'balanced';
    const latencyHint = latencyMode === 'low' ? 'interactive' : latencyMode === 'safe' ? 'playback' : 'balanced';
    Tone.context.lookAhead = latencyMode === 'safe' ? 0.2 : latencyMode === 'low' ? 0.05 : 0.1;
    await Tone.start();
    // Ensure stereo output (iOS can sometimes collapse to mono)
    Tone.Destination.channelCount = 2;
    Tone.Destination.channelCountMode = 'explicit';
    Tone.Transport.bpm.value = MUZE.Config.BPM_DEFAULT;

    // iOS AudioContext recovery: resume on interruption (phone call, tab switch, screen lock)
    const ctx = Tone.context.rawContext;
    if (ctx) {
      ctx.addEventListener('statechange', () => {
        if (ctx.state === 'interrupted' || ctx.state === 'suspended') {
          const resume = () => {
            ctx.resume().then(() => { Tone.Transport.start(); });
            document.removeEventListener('touchstart', resume);
            document.removeEventListener('click', resume);
          };
          document.addEventListener('touchstart', resume, { once: true });
          document.addEventListener('click', resume, { once: true });
        }
      });
      // Also handle visibility change
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden && ctx.state !== 'running') {
          ctx.resume().catch(() => {});
        }
      });
    }

    // ============================================================
    // MASTER CHAIN: Saturation → Filter → EQ → Gain → Limiter → Analyser → Out
    // ============================================================
    this.analyser = new Tone.Analyser('waveform', 256);
    this._limiter = new Tone.Limiter(MUZE.Mixer.master.limiterThreshold);
    this._limiter.connect(this.analyser);
    this.analyser.toDestination();

    this._masterGain = new Tone.Gain(1).connect(this._limiter);
    // FFT analyser for frequency visualization
    this.fftAnalyser = new Tone.Analyser('fft', 512);
    this._masterGain.connect(this.fftAnalyser);
    // PERF: Removed _masterMeter (Tone.Meter does FFT every frame). Use gain.value as proxy.
    this._masterEQ = new Tone.EQ3(0, 0, 0).connect(this._masterGain);

    // Simplified saturation: single gain stage (saves 4 nodes + WaveShaper CPU)
    // The WaveShaper parallel chain was costing stereo processing per sample
    this._masterSaturation = new Tone.Gain(0.95).connect(this._masterEQ);

    this._masterFilterGain = new Tone.Gain(1).connect(this._masterSaturation);
    this._masterFilter = new Tone.Filter({ frequency: 2000, type: 'lowpass', rolloff: -24, Q: 1.2 }).connect(this._masterFilterGain);

    // ============================================================
    // SEND BUSES (shared reverb + delay, returns bypass face filter)
    // ============================================================
    // (Removed: reverb modulation chorus — unnecessary CPU for barely audible effect)

    // Reverb HF damping: single lowpass filter (replaces EQ3, saves ~4 BiquadFilter nodes)
    this._reverbDamping = new Tone.Filter({ frequency: 6000, type: 'lowpass', rolloff: -12 }).connect(this._masterSaturation);

    this._reverbBus = new Tone.Reverb({ decay: 2.0, preDelay: 0.03 }).connect(this._reverbDamping);
    await this._reverbBus.ready;
    this._reverbBus.wet.value = 1; // fully wet — send level controls amount

    this._delayBus = new Tone.FeedbackDelay({ delayTime: '8n.', feedback: 0.3, wet: 1 }).connect(this._masterSaturation);

    // ============================================================
    // SYNTHS — Professional quality
    // ============================================================

    // ---- PAD SYNTH: FM + sub oscillator ----
    // PERF: maxPolyphony 3 (plays 3-note chords), removed _padDetune2 entirely
    this.padSynth = new Tone.PolySynth(Tone.FMSynth, {
      maxPolyphony: 4,
      voice: {
        harmonicity: 1.5, modulationIndex: 2.5,
        oscillator: { type: 'fatsine', count: 3, spread: 18 },
        envelope: { attack: 1.0, decay: 0.4, sustain: 0.85, release: 2.5 },
        modulation: { type: 'triangle' },
        modulationEnvelope: { attack: 0.6, decay: 0.3, sustain: 0.7, release: 2.0 }
      }
    });
    // Detune for stereo width (±5 cents spread)
    this.padSynth.set({ detune: 5 });

    // Sub oscillator: one octave down, sine, subtle
    this._padSub = new Tone.PolySynth(Tone.Synth, {
      maxPolyphony: 4,
      oscillator: { type: 'sine' },
      envelope: { attack: 1.2, decay: 0.5, sustain: 0.9, release: 3.0 },
    });
    this._padSub.volume.value = -14; // increased sub presence

    // Chorus insert for pad (enhanced: slightly higher rate for shimmer)
    this._padChorus = new Tone.Chorus({ frequency: 1.2, delayTime: 4.0, depth: 0.35, wet: 0.5 });
    // Chorus starts lazily when channel is unmuted (saves ~5% CPU per idle chorus)

    // (Removed: _padDetune2 — single pad layer + sub is enough, saves 3 FMSynth voices)

    // Wire pad layers through chorus
    this.padSynth.connect(this._padChorus);
    this._padSub.connect(this._padChorus);
    this._createChannelStrip('pad', this._padChorus);

    // ---- ARPEGGIO SYNTH: Filter envelope + stereo ping-pong ----
    this.leadSynth = new Tone.PolySynth(Tone.Synth, {
      maxPolyphony: 4,
      oscillator: { type: 'fatsawtooth', count: 2, spread: 20 },
      envelope: { attack: 0.005, decay: 0.25, sustain: 0.15, release: 0.25 },
    });

    // Filter with envelope for the arp — gives it that classic analog pluck
    this._arpFilter = new Tone.Filter({
      frequency: 2000,
      type: 'lowpass',
      rolloff: -24,
      Q: 5
    });

    // (Removed: _arpPingPong — shared delay bus handles stereo width)

    // Chorus insert for arp (shimmer, controlled by head roll like pad)
    this._arpChorus = new Tone.Chorus({ frequency: 1.2, delayTime: 4.0, depth: 0.35, wet: 0.4 });

    this.leadSynth.connect(this._arpFilter);
    this._arpFilter.connect(this._arpChorus);
    this._createChannelStrip('arp', this._arpChorus);

    // ---- ARPEGGIO 2 SYNTH ----
    this.leadSynth2 = new Tone.PolySynth(Tone.Synth, {
      maxPolyphony: 3,
      oscillator: { type: 'triangle', count: 2, spread: 15 },
      envelope: { attack: 0.01, decay: 0.3, sustain: 0.2, release: 0.3 },
    });
    this._arp2Filter = new Tone.Filter({ frequency: 1800, type: 'lowpass', rolloff: -24, Q: 4 });
    this._arp2Chorus = new Tone.Chorus({ frequency: 1.5, delayTime: 3.5, depth: 0.3, wet: 0.35 });
    this.leadSynth2.connect(this._arp2Filter);
    this._arp2Filter.connect(this._arp2Chorus);
    this._createChannelStrip('arp2', this._arp2Chorus);

    // ---- MELODY SYNTH: Expressive filter envelope + vibrato ----
    this.melodySynth = new Tone.MonoSynth({
      oscillator: { type: 'fatsawtooth', count: 2, spread: 15 },
      envelope: { attack: 0.05, decay: 0.2, sustain: 0.7, release: 0.4 },
      filterEnvelope: {
        attack: 0.02, decay: 0.3, sustain: 0.3, release: 0.5,
        baseFrequency: 400, octaves: 4.5, exponent: 2
      },
      filter: { type: 'lowpass', rolloff: -24, Q: 4 }
    });

    // Vibrato LFO for melody expressiveness
    this._melodyVibrato = new Tone.LFO({
      frequency: 5, // 5 Hz vibrato
      min: -15,     // ±15 cents
      max: 15,
      type: 'sine'
    });
    this._melodyVibratoGain = new Tone.Gain(0.15); // always-on subtle vibrato
    this._melodyVibrato.connect(this._melodyVibratoGain);
    this._melodyVibratoGain.connect(this.melodySynth.detune);
    this._melodyVibrato.start();

    this._createChannelStrip('melody', this.melodySynth);

    // ---- DRUMS — Layered for professional sound ----

    // KICK: MembraneSynth + click transient (short noise burst)
    this.kickSynth = new Tone.MembraneSynth({
      pitchDecay: 0.06, octaves: 5, oscillator: { type: 'sine' },
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
    this._kickClick.volume.value = -7; // more click presence
    this._createChannelStrip('kick', kickMix);

    // SNARE: NoiseSynth (top) + short tonal body (bottom)
    this.snareSynth = new Tone.NoiseSynth({
      noise: { type: 'pink' },
      envelope: { attack: 0.002, decay: 0.18, sustain: 0, release: 0.18 }
    });
    // Bandpass filter on snare noise layer for tighter character
    this._snareNoiseFilter = new Tone.Filter({ frequency: 3500, type: 'bandpass', Q: 1.2 });
    // Snare body: short pitched sine for "thwack"
    this._snareBody = new Tone.MembraneSynth({
      pitchDecay: 0.03, octaves: 3, oscillator: { type: 'sine' },
      envelope: { attack: 0.001, decay: 0.08, sustain: 0, release: 0.06 }
    });
    this._snareBody.volume.value = -5;
    const snareMix = new Tone.Gain(1);
    this.snareSynth.connect(this._snareNoiseFilter);
    this._snareNoiseFilter.connect(snareMix);
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
    this._binauralL = new Tone.Oscillator({ type: 'sine', frequency: 108.75 }).connect(binLPan);
    this._binauralR = new Tone.Oscillator({ type: 'sine', frequency: 111.25 }).connect(binRPan);
    binLPan.connect(binMix);
    binRPan.connect(binMix);
    this._createChannelStrip('binaural', binMix);

    // ---- Riser -> Channel Strip ----
    this._riserFilter = new Tone.Filter({ frequency: 200, type: 'bandpass', Q: 2 });
    this._riserGain = new Tone.Gain(0).connect(this._riserFilter);
    this.riserSynth = new Tone.Noise('pink').connect(this._riserGain);
    // Don't start noise here — only start on startRiser(), stop after fadeout
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

    // PERF: Removed per-channel Tone.Meter (9 FFT nodes). Use gain.value as proxy.
    this._nodes[name] = { eq, panner, gain, reverbSend, delaySend };
  },

  // ============================================================
  // REAL-TIME PARAMETER UPDATES (face-driven)
  // Dead-zone: only schedule rampTo when value changes by >0.5%
  // ============================================================
  _lastFilterFreq: 2000,
  _lastFilterGain: 1,
  _lastChorusDepth: 0,
  _lastArpFilterFreq: 800,
  _lastSendValues: {},

  updateParams(state) {
    const C = MUZE.Config;

    // Master filter: head pitch
    const pitchN = 1 - Math.max(0, Math.min(1, (state.headPitch + 0.4) / 0.8));
    const filterFreq = C.FILTER_FREQ_MIN * Math.pow(C.FILTER_FREQ_MAX / C.FILTER_FREQ_MIN, pitchN);
    if (Math.abs(filterFreq - this._lastFilterFreq) / this._lastFilterFreq > 0.005) {
      this._masterFilter.frequency.rampTo(filterFreq, 0.08);
      this._lastFilterFreq = filterFreq;
    }
    const filterGainVal = 1 + (1 - pitchN) * 0.35;
    if (Math.abs(filterGainVal - this._lastFilterGain) / this._lastFilterGain > 0.005) {
      this._masterFilterGain.gain.rampTo(filterGainVal, 0.08);
      this._lastFilterGain = filterGainVal;
    }

    // Reverb/delay sends: eye openness scales face-linked channels
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const data = MUZE.Mixer.channels[ch];
      const node = this._nodes[ch];
      if (!node || !data.faceLinked) continue;
      const reverbTarget = state.eyeOpenness * data.reverbSend;
      const delayTarget = state.eyeOpenness * data.delaySend;
      const key = ch;
      if (!this._lastSendValues[key]) this._lastSendValues[key] = { reverb: 0, delay: 0 };
      const lastReverb = this._lastSendValues[key].reverb;
      const lastDelay = this._lastSendValues[key].delay;
      if (lastReverb === 0 || Math.abs(reverbTarget - lastReverb) / (lastReverb || 0.001) > 0.005) {
        node.reverbSend.gain.rampTo(reverbTarget, 0.1);
        this._lastSendValues[key].reverb = reverbTarget;
      }
      if (lastDelay === 0 || Math.abs(delayTarget - lastDelay) / (lastDelay || 0.001) > 0.005) {
        node.delaySend.gain.rampTo(delayTarget, 0.1);
        this._lastSendValues[key].delay = delayTarget;
      }
    }

    // Chorus: head roll (pad + arp inserts)
    const rollN = Math.min(1, Math.abs(state.headRoll) / 0.35);
    const chorusDepth = C.CHORUS_DEPTH_MIN + rollN * (C.CHORUS_DEPTH_MAX - C.CHORUS_DEPTH_MIN);
    if (Math.abs(chorusDepth - this._lastChorusDepth) / (this._lastChorusDepth || 0.001) > 0.005) {
      this._padChorus.depth = chorusDepth;
      if (this._arpChorus) this._arpChorus.depth = chorusDepth * 0.7;
      this._lastChorusDepth = chorusDepth;
    }

    // Arp filter envelope simulation: mouth openness opens the filter
    if (this._arpFilter) {
      const mouthN = Math.max(0, Math.min(1, state.mouthOpenness));
      const arpFilterFreq = 800 + mouthN * 6000;
      if (Math.abs(arpFilterFreq - this._lastArpFilterFreq) / this._lastArpFilterFreq > 0.005) {
        this._arpFilter.frequency.rampTo(arpFilterFreq, 0.08);
        this._lastArpFilterFreq = arpFilterFreq;
      }
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
    this._padSub.releaseAll();
    this.padSynth.triggerAttack(notes, Tone.now(), 0.4);
    // Sub: one octave down
    const subNotes = notes.map(n => {
      const freq = Tone.Frequency(n).toFrequency();
      return Tone.Frequency(freq / 2).toNote();
    });
    this._padSub.triggerAttack(subNotes, Tone.now(), 0.3);
  },
  releasePad() {
    this.padSynth.releaseAll();
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
  // time parameter: use scheduled Transport time for tight quantization.
  // Falls back to Tone.now() for manual/preview triggers from UI.
  triggerDrum(type, velocity, isOpenHat, time) {
    const vel = velocity || 0.7;
    const t = time != null ? time : Tone.now();
    switch (type) {
      case 'kick':
        this.kickSynth.triggerAttackRelease('C1', '8n', t, vel);
        this._kickClick.triggerAttackRelease('32n', t, vel * 0.6);
        this._sidechainDuck(t);
        break;
      case 'snare':
        this.snareSynth.triggerAttackRelease('8n', t, vel);
        this._snareBody.triggerAttackRelease('B2', '16n', t, vel * 0.5);
        break;
      case 'hat':
        if (isOpenHat) {
          this._openHatSynth.triggerAttackRelease('8n', t, vel * 0.5);
        } else {
          this.hatSynth.triggerAttackRelease('32n', t, vel);
        }
        break;
    }
  },

  // ============================================================
  // SIDECHAIN DUCK — uses scheduled time for Transport-locked ducking
  // ============================================================
  _sidechainDuck(time) {
    const t = time != null ? time : Tone.now();
    // Only duck channels that are NOT muted — otherwise ducking restores them to audible
    if (!MUZE.Mixer.channels.pad.mute) {
      const padNode = this._nodes.pad;
      if (padNode) {
        const g = padNode.gain.gain;
        const cur = g.value;
        if (cur > 0.001) {
          g.cancelScheduledValues(t);
          g.setValueAtTime(cur * 0.15, t);
          g.exponentialRampToValueAtTime(cur, t + 0.25);
        }
      }
    }
    if (!MUZE.Mixer.channels.arp.mute) {
      const arpNode = this._nodes.arp;
      if (arpNode) {
        const g = arpNode.gain.gain;
        const cur = g.value;
        if (cur > 0.001) {
          g.cancelScheduledValues(t);
          g.setValueAtTime(cur * 0.5, t);
          g.exponentialRampToValueAtTime(cur, t + 0.2);
        }
      }
    }
  },

  // ============================================================
  // RISER (hold -> build -> drop)
  // NOTE: The pause handler in index.html MUST call cancelRiser() when pausing
  // during an active riser, otherwise ducked volumes stay ducked forever.
  // Add to pause handler: if (MUZE.State.riserActive) { MUZE.Audio.cancelRiser(); ... }
  // ============================================================
  _preRiserGains: {},

  startRiser() {
    try { this.riserSynth.start(); } catch(e) {}
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
    // Transport-scheduled stop prevents timing drift in background tabs
    Tone.Transport.scheduleOnce(() => { try { this.riserSynth.stop(); } catch(e) {} }, '+0.2');
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
    // Transport-scheduled reverb wash recovery
    Tone.Transport.scheduleOnce(() => {
      for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
        const node = this._nodes[ch];
        if (!node || node._reverbSendPre === undefined) continue;
        node.reverbSend.gain.rampTo(node._reverbSendPre, 2);
      }
    }, '+0.3');
    // Restore ducked volumes (fallback to mixer defaults if _preRiserGains is empty)
    for (const ch of ['pad', 'kick', 'snare', 'hat']) {
      const node = this._nodes[ch];
      if (!node) continue;
      const restoreGain = this._preRiserGains[ch] !== undefined
        ? this._preRiserGains[ch]
        : Tone.dbToGain(MUZE.Mixer.channels[ch].volume);
      node.gain.gain.rampTo(restoreGain, 0.05);
    }
    this._preRiserGains = {};
  },

  cancelRiser() {
    this._riserGain.gain.rampTo(0, 0.3);
    this._riserFilter.frequency.rampTo(200, 0.3);
    // Transport-scheduled stop prevents timing drift in background tabs
    Tone.Transport.scheduleOnce(() => { try { this.riserSynth.stop(); } catch(e) {} }, '+0.5');
    for (const ch of ['pad', 'kick', 'snare', 'hat']) {
      const node = this._nodes[ch];
      if (!node) continue;
      const restoreGain = this._preRiserGains[ch] !== undefined
        ? this._preRiserGains[ch]
        : Tone.dbToGain(MUZE.Mixer.channels[ch].volume);
      node.gain.gain.rampTo(restoreGain, 0.3);
    }
    this._preRiserGains = {};
  },

  // ============================================================
  // ARPEGGIO (dual arp, configurable note value + pattern)
  // ============================================================
  _arpProps(id) {
    return id === 2
      ? { seq: '_arp2Seq', notes: '_arp2Notes', idx: '_arp2Idx', synth: 'leadSynth2', filter: '_arp2Filter', patKey: 'arp2PatternIdx', noteKey: 'arp2NoteValueIdx' }
      : { seq: '_arpSeq',  notes: '_arpNotes',  idx: '_arpIdx',  synth: 'leadSynth',  filter: '_arpFilter',  patKey: 'arpPatternIdx',  noteKey: 'arpNoteValueIdx' };
  },

  startArpeggio(arpId) {
    const p = this._arpProps(arpId);
    if (this[p.seq]) return;
    this[p.idx] = 0;
    const noteVal = MUZE.Config.ARP_NOTE_VALUES[MUZE.State[p.noteKey]] || '8n';
    const synth = this[p.synth];
    const filter = this[p.filter];
    // Throttle filter envelope: only every 2nd note to halve automation overhead
    let filterTick = 0;
    this[p.seq] = new Tone.Loop((time) => {
      const notes = this[p.notes];
      if (!notes.length || !synth) return;
      const note = notes[this[p.idx] % notes.length];
      const accent = (this[p.idx] % 4 === 0) ? 0.7 : 0.4 + Math.random() * 0.1;
      synth.triggerAttackRelease(note, noteVal, time, accent);
      if (filter && (filterTick++ & 1) === 0) {
        filter.frequency.setValueAtTime(5000, time);
        filter.frequency.exponentialRampToValueAtTime(1400, time + 0.12);
      }
      this[p.idx]++;
    }, noteVal);
    this[p.seq].start(0);
  },

  updateArpNotes(scale, root, arpId) {
    const p = this._arpProps(arpId);
    const baseNotes = scale.map(i => MUZE.Music.midiToNote(root + i));
    const pattern = MUZE.Config.ARP_PATTERNS[MUZE.State[p.patKey]] || 'up-down';

    switch (pattern) {
      case 'up':
        this[p.notes] = [...baseNotes]; break;
      case 'down':
        this[p.notes] = [...baseNotes].reverse(); break;
      case 'random': {
        const shuffled = [...baseNotes];
        for (let i = shuffled.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
        }
        this[p.notes] = shuffled; break;
      }
      case 'up-up-down': {
        const down = [...baseNotes].reverse().slice(1);
        this[p.notes] = [...baseNotes, ...baseNotes, ...down]; break;
      }
      case 'played':
        this[p.notes] = [...baseNotes]; break;
      case 'up-down': default: {
        const down = [...baseNotes].reverse().slice(1);
        this[p.notes] = [...baseNotes, ...down]; break;
      }
    }
  },

  stopArpeggio(arpId) {
    const p = this._arpProps(arpId);
    if (this[p.seq]) { this[p.seq].stop(); this[p.seq].dispose(); this[p.seq] = null; }
    this[p.notes] = [];
  },

  restartArpWithNewRate(arpId) {
    const p = this._arpProps(arpId);
    const wasRunning = !!this[p.seq];
    const savedNotes = [...(this[p.notes] || [])];
    if (wasRunning) { this[p.seq].stop(); this[p.seq].dispose(); this[p.seq] = null; }
    this[p.notes] = savedNotes;
    if (wasRunning) this.startArpeggio(arpId);
  },

  // ============================================================
  // BINAURAL
  // ============================================================
  toggleBinaural() {
    this._binauralActive = !this._binauralActive;
    if (this._binauralActive && this._binauralL.state !== 'started') {
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
    const self = this;
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const node = self._nodes[ch];
      if (!node) continue;
      node._reverbSendPre = node.reverbSend.gain.value;
      node.reverbSend.gain.rampTo(0.9, 0.05);
    }
    // Use setTimeout for reliable wall-clock timing (Transport time drifts with BPM changes)
    setTimeout(() => {
      for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
        const node = self._nodes[ch];
        if (!node || node._reverbSendPre === undefined) continue;
        node.reverbSend.gain.rampTo(node._reverbSendPre, 1.5);
      }
    }, 200);
  },

  tapeStop() {
    const self = this;
    const orig = Tone.Transport.bpm.value;
    Tone.Transport.bpm.rampTo(20, 0.4);
    [self.padSynth, self._padSub, self.leadSynth, self.melodySynth].forEach(s => {
      if (s) { s.set({ detune: 0 }); s.set({ detune: -2400 }); }
    });
    // Use setTimeout for reliable wall-clock timing (Transport slows to 20 BPM so scheduleOnce is unreliable)
    setTimeout(() => {
      Tone.Transport.bpm.rampTo(orig, 0.15);
      [self.padSynth, self._padSub, self.leadSynth, self.melodySynth].forEach(s => {
        if (s) s.set({ detune: 0 });
      });
      // Restore pad detuning
      self.padSynth.set({ detune: 5 });
      self._padSub.set({ detune: 0 });
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
      this._padSub.volume.rampTo(-60, 0.3);
      this._padGrain.volume.rampTo(-14, 0.3);
      this._padGrain.start();
    }
  },
  setPadSynth() {
    this._padSampleMode = false;
    MUZE.State.padSampleId = null;
    this.padSynth.volume.rampTo(-14, 0.3);
    this._padSub.volume.rampTo(-14, 0.3);
    this._padGrain.volume.rampTo(-60, 0.3);
    // Transport-scheduled stop prevents timing drift in background tabs
    Tone.Transport.scheduleOnce(() => { try { this._padGrain.stop(); } catch(e) {} }, '+0.4');
  },

  // ============================================================
  // WAVEFORM DATA (for visualizer)
  // ============================================================
  getWaveform() {
    if (!this.analyser) return null;
    return this.analyser.getValue();
  },

  getFFT() {
    return this.fftAnalyser ? this.fftAnalyser.getValue() : null;
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
  _currentStep: -1,  // for UI highlight

  // User-editable step sequencer pattern (velocity per step, 0 = off)
  _userPattern: {
    kick:  [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
    snare: [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
    hat:   [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
  },
  _useCustom: false,  // false = preset patterns, true = user sequencer

  start() {
    if (this._seq) this._seq.dispose();
    this._active = true;
    this._seq = new Tone.Sequence((t, s) => {
      this._currentStep = s;
      if (this._useCustom) {
        const u = this._userPattern;
        if (u.kick[s] > 0) MUZE.Audio.triggerDrum('kick', u.kick[s], false, t);
        if (u.snare[s] > 0) MUZE.Audio.triggerDrum('snare', u.snare[s], false, t);
        if (u.hat[s] > 0) MUZE.Audio.triggerDrum('hat', u.hat[s], s % 8 === 6, t);
      } else {
        const p = MUZE.Config.RHYTHM_PATTERNS[this._patIdx];
        if (p.kick[s]) MUZE.Audio.triggerDrum('kick', 0.7, false, t);
        if (p.snare[s]) MUZE.Audio.triggerDrum('snare', 0.6, false, t);
        if (p.hat[s]) MUZE.Audio.triggerDrum('hat', 0.4, s % 8 === 6, t);
      }
    }, [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15], '16n');
    this._seq.start(0);
  },

  stop() {
    this._active = false;
    this._currentStep = -1;
    if (this._seq) { this._seq.stop(); this._seq.dispose(); this._seq = null; }
  },

  toggle() { if (this._active) this.stop(); else this.start(); return this._active; },

  // Restart if running (to pick up pattern changes)
  _restart() { if (this._active) { this.stop(); this.start(); } },

  nextPattern() { this._patIdx = (this._patIdx + 1) % MUZE.Config.RHYTHM_PATTERNS.length; this._restart(); },
  prevPattern() { this._patIdx = (this._patIdx - 1 + MUZE.Config.RHYTHM_PATTERNS.length) % MUZE.Config.RHYTHM_PATTERNS.length; this._restart(); },
  isActive() { return this._active; },
  getPatternName() { return this._useCustom ? 'Custom' : MUZE.Config.RHYTHM_PATTERNS[this._patIdx].name; },

  // Load a preset into the user pattern for editing
  loadPresetToCustom(idx) {
    const p = MUZE.Config.RHYTHM_PATTERNS[idx || this._patIdx];
    this._userPattern.kick  = p.kick.map(v => v ? 0.7 : 0);
    this._userPattern.snare = p.snare.map(v => v ? 0.6 : 0);
    this._userPattern.hat   = p.hat.map(v => v ? 0.4 : 0);
  },

  // Toggle a step (cycles: off → 0.7 → 0.4 → off for velocity control)
  toggleStep(inst, step) {
    const arr = this._userPattern[inst];
    if (!arr) return;
    if (arr[step] === 0) arr[step] = 0.7;
    else if (arr[step] >= 0.6) arr[step] = 0.4;
    else arr[step] = 0;
  },

  // Set velocity directly
  setStepVelocity(inst, step, vel) {
    if (this._userPattern[inst]) this._userPattern[inst][step] = vel;
  },

  // Clear all steps
  clearPattern() {
    for (const inst of ['kick', 'snare', 'hat']) {
      this._userPattern[inst] = [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0];
    }
  }
};
