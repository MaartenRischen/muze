/* ============================================================
   MUZE — Audio Engine (Send/Return Bus Architecture)
   ============================================================ */

MUZE.Audio = {
  // Synth sources
  padSynth: null, leadSynth: null, melodySynth: null,
  kickSynth: null, snareSynth: null, hatSynth: null,
  riserSynth: null,
  _binauralL: null, _binauralR: null,
  _binauralActive: false, _binauralFollowChord: false,
  _binauralBeatHz: 4, _binauralBaseFreq: 110,

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
    // MASTER CHAIN: Filter → EQ → Gain → Limiter → Analyser → Out
    // ============================================================
    this.analyser = new Tone.Analyser('waveform', 256);
    this._limiter = new Tone.Limiter(MUZE.Mixer.master.limiterThreshold);
    this._limiter.connect(this.analyser);
    this.analyser.toDestination();

    this._masterGain = new Tone.Gain(1).connect(this._limiter);
    this._masterMeter = new Tone.Meter();
    this._masterGain.connect(this._masterMeter);
    this._masterEQ = new Tone.EQ3(0, 0, 0).connect(this._masterGain);
    this._masterFilterGain = new Tone.Gain(1).connect(this._masterEQ);
    this._masterFilter = new Tone.Filter({ frequency: 2000, type: 'lowpass', rolloff: -24, Q: 1.2 }).connect(this._masterFilterGain);

    // ============================================================
    // SEND BUSES (shared reverb + delay, returns bypass face filter)
    // ============================================================
    this._reverbBus = new Tone.Reverb({ decay: 2.5, preDelay: 0.01 }).connect(this._masterEQ);
    await this._reverbBus.ready;
    this._reverbBus.wet.value = 1; // fully wet — send level controls amount

    this._delayBus = new Tone.FeedbackDelay({ delayTime: '8n.', feedback: 0.3, wet: 1 }).connect(this._masterEQ);

    // ============================================================
    // SYNTHS (same as before, but wired through channel strips)
    // ============================================================

    // ---- Pad synth → Chorus (insert) → Channel Strip ----
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
    this._padChorus = new Tone.Chorus({ frequency: 1.5, delayTime: 3.5, depth: 0, wet: 0.5 });
    this._padChorus.start();
    this.padSynth.connect(this._padChorus);
    this._createChannelStrip('pad', this._padChorus);

    // ---- Arpeggio synth → Channel Strip ----
    this.leadSynth = new Tone.PolySynth(Tone.Synth, {
      maxPolyphony: 8,
      oscillator: { type: 'sawtooth' },
      envelope: { attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.8 },
    });
    this._createChannelStrip('arp', this.leadSynth);

    // ---- Melody synth → Channel Strip ----
    this.melodySynth = new Tone.MonoSynth({
      oscillator: { type: 'triangle' },
      envelope: { attack: 0.05, decay: 0.2, sustain: 0.7, release: 0.4 },
      filterEnvelope: { attack: 0.05, decay: 0.1, sustain: 0.5, release: 0.3, baseFrequency: 300, octaves: 3 },
    });
    this._createChannelStrip('melody', this.melodySynth);

    // ---- Drums → Individual Channel Strips ----
    this.kickSynth = new Tone.MembraneSynth({
      pitchDecay: 0.06, octaves: 7, oscillator: { type: 'sine' },
      envelope: { attack: 0.002, decay: 0.5, sustain: 0, release: 0.5 }
    });
    this._createChannelStrip('kick', this.kickSynth);

    this.snareSynth = new Tone.NoiseSynth({
      noise: { type: 'white' },
      envelope: { attack: 0.002, decay: 0.18, sustain: 0, release: 0.18 }
    });
    this._createChannelStrip('snare', this.snareSynth);

    // Hat: NoiseSynth + highpass filter (MetalSynth has routing issues with EQ3)
    this.hatSynth = new Tone.NoiseSynth({
      noise: { type: 'white' },
      envelope: { attack: 0.001, decay: 0.08, sustain: 0, release: 0.05 }
    });
    this._hatFilter = new Tone.Filter({ frequency: 8000, type: 'highpass', rolloff: -12 });
    this.hatSynth.connect(this._hatFilter);
    this._createChannelStrip('hat', this._hatFilter);

    // ---- Binaural → Channel Strip ----
    // Hard L/R panning is internal; channel strip panner stays at 0
    const binLPan = new Tone.Panner(-1);
    const binRPan = new Tone.Panner(1);
    const binMix = new Tone.Gain(1);
    this._binauralL = new Tone.Oscillator({ type: 'sine', frequency: 110 }).connect(binLPan);
    this._binauralR = new Tone.Oscillator({ type: 'sine', frequency: 114 }).connect(binRPan);
    binLPan.connect(binMix);
    binRPan.connect(binMix);
    this._createChannelStrip('binaural', binMix);

    // ---- Riser → Channel Strip ----
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

    // Wire: Source → EQ → Panner → Gain
    source.connect(eq);
    eq.connect(panner);
    panner.connect(gain);

    // Dry path: face-linked channels go through master filter, others bypass to master EQ
    const faceLinked = MUZE.Mixer.channels[name].faceLinked;
    gain.connect(faceLinked ? this._masterFilter : this._masterEQ);

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
  // PAD
  // ============================================================
  triggerPad(notes) { this.padSynth.releaseAll(); this.padSynth.triggerAttack(notes, Tone.now(), 0.4); },
  releasePad() { this.padSynth.releaseAll(); },

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

  // ============================================================
  // DRUMS
  // ============================================================
  triggerDrum(type, velocity) {
    const vel = velocity || 0.7;
    const now = Tone.now();
    switch (type) {
      case 'kick': this.kickSynth.triggerAttackRelease('C1', '8n', now, vel); break;
      case 'snare': this.snareSynth.triggerAttackRelease('8n', now, vel); break;
      case 'hat': this.hatSynth.triggerAttackRelease('32n', now); break;
    }
  },

  // ============================================================
  // RISER (hold → build → drop)
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
  // ARPEGGIO
  // ============================================================
  startArpeggio() {
    if (this._arpSeq) return;
    this._arpIdx = 0;
    this._arpSeq = new Tone.Loop((time) => {
      if (!this._arpNotes.length || !this.leadSynth) return;
      const note = this._arpNotes[this._arpIdx % this._arpNotes.length];
      this.leadSynth.triggerAttackRelease(note, '8n', time, 0.5);
      this._arpIdx++;
    }, '8n');
    this._arpSeq.start(0);
  },
  updateArpNotes(scale, root) {
    const up = scale.map(i => MUZE.Music.midiToNote(root + i));
    const down = [...up].reverse().slice(1);
    this._arpNotes = [...up, ...down];
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
    [this.padSynth, this.leadSynth, this.melodySynth].forEach(s => {
      if (s) { s.set({ detune: 0 }); s.set({ detune: -2400 }); }
    });
    setTimeout(() => {
      Tone.Transport.bpm.rampTo(orig, 0.15);
      [this.padSynth, this.leadSynth, this.melodySynth].forEach(s => {
        if (s) s.set({ detune: 0 });
      });
    }, 500);
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
      this._padGrain.volume.rampTo(-14, 0.3);
      this._padGrain.start();
    }
  },
  setPadSynth() {
    this._padSampleMode = false;
    MUZE.State.padSampleId = null;
    this.padSynth.volume.rampTo(-14, 0.3);
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
// AUTO RHYTHM
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
      if (p.hat[s]) MUZE.Audio.triggerDrum('hat', 0.4);
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
