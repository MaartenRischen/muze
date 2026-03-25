/* ============================================================
   MUZE — UI (Touch, Synth Menu, Tutorial, Recorder, Samples)
   ============================================================ */

// ---- Touch Handler ----
MUZE.Touch = {
  _cooldown: {}, _touchStart: null, _lastTapTime: 0, _holdTimer: null, _isHolding: false,

  init() {
    // Chord zone
    const selectChord = (el) => {
      if (el && el.dataset.chord !== undefined) {
        const idx = parseInt(el.dataset.chord);
        MUZE.State.chordIndex = idx;
        document.querySelectorAll('.chord-btn').forEach((b, i) => b.classList.toggle('active', i === idx));
      }
    };
    document.getElementById('chord-zone').addEventListener('touchstart', (e) => {
      e.preventDefault();
      const t = e.changedTouches[0];
      selectChord(document.elementFromPoint(t.clientX, t.clientY));
    }, { passive: false });
    document.querySelectorAll('.chord-btn').forEach(btn => {
      btn.addEventListener('click', () => selectChord(btn));
    });

    // Drum zone
    const z = document.getElementById('touch-zone');
    z.addEventListener('touchstart', this._onStart.bind(this), { passive: false });
    z.addEventListener('touchmove', (e) => e.preventDefault(), { passive: false });
    z.addEventListener('touchend', this._onEnd.bind(this), { passive: false });
    z.addEventListener('touchcancel', this._onEnd.bind(this), { passive: false });

    document.querySelector('.chord-btn[data-chord="0"]').classList.add('active');
  },

  _onStart(e) {
    e.preventDefault();
    const t = e.changedTouches[0];
    this._touchStart = { x: t.clientX, y: t.clientY, time: performance.now() };
    this._isHolding = false;
    this._holdTimer = setTimeout(() => {
      this._isHolding = true;
      MUZE.Audio.startRiser();
      MUZE.State.riserActive = true;
      document.getElementById('riser-overlay').classList.add('active');
    }, MUZE.Config.HOLD_TIME);
  },

  _onEnd(e) {
    e.preventDefault();
    if (!this._touchStart) return;
    const t = e.changedTouches[0];
    const dx = t.clientX - this._touchStart.x;
    const dy = t.clientY - this._touchStart.y;
    const dt = performance.now() - this._touchStart.time;
    clearTimeout(this._holdTimer);

    if (this._isHolding) {
      if (dy < -MUZE.Config.SWIPE_THRESHOLD) {
        MUZE.Audio.dropRiser();
      } else {
        MUZE.Audio.cancelRiser();
      }
      MUZE.State.riserActive = false;
      document.getElementById('riser-overlay').classList.remove('active');
      this._isHolding = false;
      this._touchStart = null;
      return;
    }

    const C = MUZE.Config, ax = Math.abs(dx), ay = Math.abs(dy);
    if (dt < C.SWIPE_MAX_TIME && (ax > C.SWIPE_THRESHOLD || ay > C.SWIPE_THRESHOLD)) {
      if (ax > ay) {
        if (dx > C.SWIPE_THRESHOLD) MUZE.AutoRhythm.nextPattern();
        else if (dx < -C.SWIPE_THRESHOLD) MUZE.AutoRhythm.prevPattern();
      } else if (dy > C.SWIPE_THRESHOLD) {
        MUZE.Audio.tapeStop();
      } else if (dy < -C.SWIPE_THRESHOLD) {
        MUZE.Audio.reverbThrow();
      }
      this._touchStart = null;
      return;
    }

    // Double-tap → toggle auto rhythm
    const now = performance.now();
    if (now - this._lastTapTime < C.DOUBLE_TAP_TIME) {
      const active = MUZE.AutoRhythm.toggle();
      MUZE.State.autoRhythm = active;
      document.getElementById('rhythm-indicator').classList.toggle('visible', active);
      this._lastTapTime = 0;
      this._touchStart = null;
      return;
    }
    this._lastTapTime = now;

    // Single tap → drum hit with velocity
    const target = document.elementFromPoint(t.clientX, t.clientY);
    if (target) {
      const drum = target.dataset.drum || target.parentElement?.dataset?.drum;
      if (drum) {
        const cn = performance.now();
        if (!this._cooldown[drum] || cn - this._cooldown[drum] > 50) {
          this._cooldown[drum] = cn;
          // Velocity: faster taps = harder hits
          const velocity = Math.min(1, Math.max(0.3, 1 - (dt / 300)));
          MUZE.Audio.triggerDrum(drum, velocity);
          const el = document.getElementById('zone-' + drum);
          if (el) {
            el.classList.add('hit');
            setTimeout(() => el.classList.remove('hit'), 120);
          }
        }
      }
    }
    this._touchStart = null;
  }
};

// ---- Synth Menu (sound design only — mixing moved to Mixer) ----
MUZE.SynthMenu = {
  init() {
    const panel = document.getElementById('synth-panel');
    document.getElementById('synth-menu-btn').addEventListener('click', () => {
      panel.classList.toggle('open');
    });

    document.querySelectorAll('.synth-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.synth-tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.synth-tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(tab.dataset.tab).classList.add('active');
      });
    });

    document.addEventListener('touchstart', (e) => {
      if (panel.classList.contains('open') && !panel.contains(e.target) && e.target.id !== 'synth-menu-btn') {
        panel.classList.remove('open');
      }
    });

    // Arp synth (sound design only)
    this._bind('arp-osc', (v) => MUZE.Audio.leadSynth.set({ oscillator: { type: v } }), true);
    this._bind('arp-atk', (v) => MUZE.Audio.leadSynth.set({ envelope: { attack: +v } }));
    this._bind('arp-dec', (v) => MUZE.Audio.leadSynth.set({ envelope: { decay: +v } }));
    this._bind('arp-sus', (v) => MUZE.Audio.leadSynth.set({ envelope: { sustain: +v } }));
    this._bind('arp-rel', (v) => MUZE.Audio.leadSynth.set({ envelope: { release: +v } }));

    // Melody synth
    document.getElementById('mel-porta').addEventListener('click', function() {
      MUZE.State.portamentoMode = !MUZE.State.portamentoMode;
      this.textContent = MUZE.State.portamentoMode ? 'ON' : 'OFF';
      MUZE.Audio.setPortamento(MUZE.State.portamentoMode);
    });
    this._bind('mel-osc', (v) => MUZE.Audio.melodySynth.set({ oscillator: { type: v } }), true);
    this._bind('mel-atk', (v) => MUZE.Audio.melodySynth.set({ envelope: { attack: +v } }));
    this._bind('mel-dec', (v) => MUZE.Audio.melodySynth.set({ envelope: { decay: +v } }));
    this._bind('mel-sus', (v) => MUZE.Audio.melodySynth.set({ envelope: { sustain: +v } }));
    this._bind('mel-rel', (v) => MUZE.Audio.melodySynth.set({ envelope: { release: +v } }));

    // Binaural
    document.getElementById('bin-toggle').addEventListener('click', function() {
      const on = MUZE.Audio.toggleBinaural();
      this.textContent = on ? 'ON' : 'OFF';
    });
    document.getElementById('bin-mode').addEventListener('click', function() {
      MUZE.Audio._binauralFollowChord = !MUZE.Audio._binauralFollowChord;
      this.textContent = MUZE.Audio._binauralFollowChord ? 'chord' : 'tonic';
      if (!MUZE.Audio._binauralFollowChord) MUZE.Audio._updateBinauralFreq(MUZE.Audio._binauralBaseFreq);
    });
    this._bind('bin-hz', (v) => MUZE.Audio.setBinauralBeatHz(+v));

    // Pad synth
    this._bind('pad-osc', (v) => MUZE.Audio.padSynth.set({ oscillator: { type: v } }), true);
    this._bind('pad-harm', (v) => MUZE.Audio.padSynth.set({ harmonicity: +v }));
    this._bind('pad-mod', (v) => MUZE.Audio.padSynth.set({ modulationIndex: +v }));
    this._bind('pad-atk', (v) => MUZE.Audio.padSynth.set({ envelope: { attack: +v } }));
    this._bind('pad-rel', (v) => MUZE.Audio.padSynth.set({ envelope: { release: +v } }));
  },

  _bind(id, fn, isSelect) {
    const el = document.getElementById(id);
    if (!el) return;
    const valEl = el.parentElement.querySelector('.val');
    if (isSelect) {
      el.addEventListener('change', () => fn(el.value));
    } else {
      el.addEventListener('input', () => {
        fn(el.value);
        if (valEl) valEl.textContent = parseFloat(el.value).toFixed(el.step.includes('.') ? el.step.split('.')[1].length : 0);
      });
    }
  }
};

// ============================================================
// MIXER UI — Builds and wires the channel strip interface
// ============================================================
MUZE.MixerUI = {
  init() {
    const panel = document.getElementById('mixer-panel');
    const strips = document.getElementById('mixer-strips');

    // Toggle
    document.getElementById('mixer-btn').addEventListener('click', () => panel.classList.toggle('open'));
    document.getElementById('mixer-close').addEventListener('click', () => panel.classList.remove('open'));

    // Close when tapping outside
    document.addEventListener('touchstart', (e) => {
      if (panel.classList.contains('open') && !panel.contains(e.target) && e.target.id !== 'mixer-btn') {
        panel.classList.remove('open');
      }
    });

    // Build channel strips
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      strips.appendChild(this._buildStrip(ch));
    }
    // Master strip
    strips.appendChild(this._buildMasterStrip());
  },

  _buildStrip(ch) {
    const data = MUZE.Mixer.channels[ch];
    const el = document.createElement('div');
    el.className = 'mixer-strip';
    el.dataset.ch = ch;
    el.style.setProperty('--strip-color', data.color);

    el.innerHTML = `
      <div class="strip-label">${ch.toUpperCase().slice(0, 4)}</div>
      <div class="strip-eq">
        <div class="eq-slider"><label>H</label><input type="range" data-band="high" min="-12" max="12" step="0.5" value="${data.eqHigh}"></div>
        <div class="eq-slider"><label>M</label><input type="range" data-band="mid" min="-12" max="12" step="0.5" value="${data.eqMid}"></div>
        <div class="eq-slider"><label>L</label><input type="range" data-band="low" min="-12" max="12" step="0.5" value="${data.eqLow}"></div>
      </div>
      <div class="strip-sends">
        <div class="send-knob"><label>RV</label><input type="range" data-send="reverb" min="0" max="1" step="0.02" value="${data.reverbSend}"></div>
        <div class="send-knob"><label>DL</label><input type="range" data-send="delay" min="0" max="1" step="0.02" value="${data.delaySend}"></div>
      </div>
      <div class="strip-pan"><label>PAN</label><input type="range" min="-1" max="1" step="0.05" value="${data.pan}"></div>
      <div class="strip-fader">
        <input type="range" min="-60" max="6" step="0.5" value="${data.volume}" orient="vertical">
        <div class="fader-val">${data.volume}</div>
      </div>
      <div class="strip-buttons">
        <button class="mute-btn">M</button>
        <button class="solo-btn">S</button>
      </div>
    `;

    // Wire EQ
    el.querySelectorAll('.eq-slider input').forEach(inp => {
      inp.addEventListener('input', () => MUZE.Mixer.setChannelEQ(ch, inp.dataset.band, +inp.value));
    });

    // Wire sends
    el.querySelectorAll('.send-knob input').forEach(inp => {
      inp.addEventListener('input', () => {
        if (inp.dataset.send === 'reverb') MUZE.Mixer.setChannelReverbSend(ch, +inp.value);
        else MUZE.Mixer.setChannelDelaySend(ch, +inp.value);
      });
    });

    // Wire pan
    el.querySelector('.strip-pan input').addEventListener('input', function() {
      MUZE.Mixer.setChannelPan(ch, +this.value);
    });

    // Wire fader
    const fader = el.querySelector('.strip-fader input');
    const faderVal = el.querySelector('.fader-val');
    fader.addEventListener('input', () => {
      MUZE.Mixer.setChannelVolume(ch, +fader.value);
      faderVal.textContent = fader.value;
    });

    // Wire mute/solo
    el.querySelector('.mute-btn').addEventListener('click', function() {
      const muted = MUZE.Mixer.toggleMute(ch);
      this.classList.toggle('active', muted);
    });
    el.querySelector('.solo-btn').addEventListener('click', function() {
      const soloed = MUZE.Mixer.toggleSolo(ch);
      this.classList.toggle('active', soloed);
    });

    // Disable pan for binaural (stereo separation is internal)
    if (ch === 'binaural') {
      el.querySelector('.strip-pan input').disabled = true;
      el.querySelector('.strip-pan input').style.opacity = '0.3';
    }

    return el;
  },

  _buildMasterStrip() {
    const m = MUZE.Mixer.master;
    const el = document.createElement('div');
    el.className = 'mixer-strip master-strip';
    el.style.setProperty('--strip-color', '#fff');

    el.innerHTML = `
      <div class="strip-label" style="background:#fff;color:#000">MSTR</div>
      <div class="strip-eq">
        <div class="eq-slider"><label>H</label><input type="range" data-band="high" min="-12" max="12" step="0.5" value="${m.eqHigh}"></div>
        <div class="eq-slider"><label>M</label><input type="range" data-band="mid" min="-12" max="12" step="0.5" value="${m.eqMid}"></div>
        <div class="eq-slider"><label>L</label><input type="range" data-band="low" min="-12" max="12" step="0.5" value="${m.eqLow}"></div>
      </div>
      <div class="strip-sends">
        <div class="send-knob"><label>LIM</label><input type="range" min="-12" max="0" step="0.5" value="${m.limiterThreshold}"></div>
      </div>
      <div class="strip-pan"><label>&nbsp;</label><input type="range" disabled style="opacity:0.2"></div>
      <div class="strip-fader">
        <input type="range" min="-60" max="6" step="0.5" value="${m.volume}" orient="vertical">
        <div class="fader-val">${m.volume}</div>
      </div>
      <div class="strip-buttons"></div>
    `;

    // Wire master EQ
    el.querySelectorAll('.eq-slider input').forEach(inp => {
      inp.addEventListener('input', () => MUZE.Mixer.setMasterEQ(inp.dataset.band, +inp.value));
    });

    // Wire limiter
    el.querySelector('.send-knob input').addEventListener('input', function() {
      MUZE.Mixer.setMasterLimiter(+this.value);
    });

    // Wire master fader
    const fader = el.querySelector('.strip-fader input');
    const faderVal = el.querySelector('.fader-val');
    fader.addEventListener('input', () => {
      MUZE.Mixer.setMasterVolume(+fader.value);
      faderVal.textContent = fader.value;
    });

    return el;
  }
};

// ---- Sample Switcher UI ----
MUZE.SampleUI = {
  _padIdx: -1, // -1 = synth mode
  _leadIdx: -1,

  init() {
    const padBtn = document.getElementById('pad-sample-btn');
    const leadBtn = document.getElementById('lead-sample-btn');
    if (!padBtn || !leadBtn) return;

    padBtn.addEventListener('click', () => this._cyclePad());
    leadBtn.addEventListener('click', () => this._cycleLead());
  },

  _cyclePad() {
    const samples = MUZE.SampleLib.getAllSamples();
    this._padIdx++;
    if (this._padIdx >= samples.length) {
      this._padIdx = -1;
      MUZE.Audio.setPadSynth();
      this._updateBtn('pad-sample-btn', 'PAD', 'FM Synth');
    } else {
      const s = samples[this._padIdx];
      MUZE.Audio.setPadSample(s.id);
      this._updateBtn('pad-sample-btn', 'PAD', s.name);
    }
  },

  _cycleLead() {
    // For now, lead sample switching just shows what's available
    // Full sample-based melody would require a Sampler — coming in future sessions
    const samples = MUZE.SampleLib.getAllSamples();
    this._leadIdx++;
    if (this._leadIdx >= samples.length) this._leadIdx = -1;
    const name = this._leadIdx === -1 ? 'Synth' : samples[this._leadIdx].name;
    this._updateBtn('lead-sample-btn', 'LEAD', name);
    MUZE.State.leadSampleId = this._leadIdx === -1 ? null : samples[this._leadIdx].id;
  },

  _updateBtn(id, label, value) {
    const btn = document.getElementById(id);
    if (btn) btn.innerHTML = `<span class="label">${label}</span>${value}`;
  }
};

// ---- Tutorial ----
MUZE.Tutorial = {
  _steps: [], _idx: 0, _active: false,

  BASIC: [
    { title: 'Smile', desc: 'Try smiling. The music shifts to a brighter, happier mode. Watch the mode name change and the colors shift.' },
    { title: 'Frown', desc: 'Now frown or make a sad face. The music becomes darker and more tense. Notice the purple tones.' },
    { title: 'Tilt Your Head', desc: 'Tilt your chin down \u2014 the sound gets muffled as the filter closes. Chin up = bright and open.' },
    { title: 'Chords & Drums', desc: 'Bottom bar: 6 chord buttons. Above that: 3 drum zones (hi-hat top, snare middle, kick bottom). Tap them!' },
    { title: 'Double Tap', desc: 'Double-tap anywhere in the drum zone to start an auto-rhythm. Double-tap again to stop.' },
    { title: 'Show Your Hand', desc: 'Hold your hand up to the camera. A melody synth appears \u2014 move up and down to change pitch.' },
    { title: 'Open vs Closed', desc: 'Open palm = legato. Closed fist = staccato. Toggle portamento in the gear menu for smooth glides.' },
    { title: 'Eyes = Reverb', desc: 'Open your eyes wide for more reverb and delay. Squint to dry things out. The ring visualization responds too.' },
    { title: 'You\'re Ready!', desc: 'Use the record button to capture performances. Tap ? again for the advanced tutorial.' },
  ],

  ADVANCED: [
    { title: 'Six Modes', desc: 'Smile controls the mode: Phrygian (dark) \u2192 Aeolian \u2192 Dorian \u2192 Mixolydian \u2192 Ionian \u2192 Lydian (bright). Each has its own color.' },
    { title: 'Filter (Head Pitch)', desc: 'Chin down = lowpass closes. Chin up = opens. Volume-compensated. Affects pad, melody, and arpeggio.' },
    { title: 'Reverb + Delay', desc: 'Eye openness scales reverb/delay. Wide = full wet, squint = dry. Gear menu sliders set the max.' },
    { title: 'Chorus (Head Roll)', desc: 'Tilt sideways for chorus depth \u2014 shimmer and stereo widening.' },
    { title: 'Octave (Brows)', desc: 'Raise eyebrows to shift melody and arpeggio up an octave.' },
    { title: 'Riser (Hold + Release)', desc: 'Hold finger 400ms+: noise sweep builds, drums duck. Swipe up to drop (big kick + reverb wash). Release without swipe to cancel.' },
    { title: 'Swipe Effects', desc: 'Swipe down: tape stop. Swipe up (no hold): reverb throw. Swipe left/right: cycle drum patterns.' },
    { title: 'Synth Panel', desc: 'Gear icon: Arp, Melody, Pad, Drums, Binaural tabs. Full ADSR, FX, volume, pan controls.' },
    { title: 'Pad Samples', desc: 'Tap the PAD button (top-right) to cycle through sample-based pads. FM Synth is the default.' },
    { title: 'Velocity', desc: 'Drum velocity responds to tap speed. Quick taps = hard hits. Slower taps = softer.' },
    { title: 'Settings Persist', desc: 'All your synth settings are saved automatically. They\'ll be restored next time you open MUZE.' },
    { title: 'Go Perform', desc: 'Layer face, hands, and touch. Every parameter stacks. There are no wrong moves.' },
  ],

  init() {
    document.getElementById('help-btn').addEventListener('click', () => {
      if (this._active) { this._close(); return; }
      document.getElementById('tut-picker').classList.add('open');
    });
    document.getElementById('tut-close-pick').addEventListener('click', () => {
      document.getElementById('tut-picker').classList.remove('open');
    });
    document.getElementById('tut-basic').addEventListener('click', () => this._start(this.BASIC));
    document.getElementById('tut-advanced').addEventListener('click', () => this._start(this.ADVANCED));
    document.getElementById('tut-next').addEventListener('click', () => this._go(1));
    document.getElementById('tut-prev').addEventListener('click', () => this._go(-1));
    document.getElementById('tut-exit').addEventListener('click', () => this._close());
  },

  _start(steps) {
    this._steps = steps; this._idx = 0; this._active = true;
    document.getElementById('tut-picker').classList.remove('open');
    document.getElementById('tut-overlay').classList.add('active');
    this._render();
  },
  _go(dir) {
    this._idx = Math.max(0, Math.min(this._steps.length - 1, this._idx + dir));
    this._render();
  },
  _render() {
    const s = this._steps[this._idx];
    document.getElementById('tut-step-label').textContent = `Step ${this._idx + 1} of ${this._steps.length}`;
    document.getElementById('tut-title').textContent = s.title;
    document.getElementById('tut-desc').textContent = s.desc;
    document.getElementById('tut-prev').style.visibility = this._idx === 0 ? 'hidden' : 'visible';
    document.getElementById('tut-next').textContent = this._idx === this._steps.length - 1 ? 'done' : 'next \u2192';
    if (this._idx === this._steps.length - 1) {
      document.getElementById('tut-next').onclick = () => this._close();
    } else {
      document.getElementById('tut-next').onclick = () => this._go(1);
    }
  },
  _close() {
    this._active = false;
    document.getElementById('tut-overlay').classList.remove('active');
    document.getElementById('tut-picker').classList.remove('open');
  }
};

// ---- Recorder ----
MUZE.Recorder = {
  _mediaRec: null, _chunks: [], _recording: false,
  _recCanvas: null, _recCtx: null, _audioDest: null, _mimeType: null,
  _w: 0, _h: 0, _multitrack: false,
  _trackRecs: [], _trackChunks: {},

  init() {
    this._recCanvas = document.getElementById('rec-canvas');
    this._recCtx = this._recCanvas.getContext('2d');
    this._audioDest = Tone.context.createMediaStreamDestination();
    Tone.getDestination().connect(this._audioDest);

    this._trackDests = {};
    const A = MUZE.Audio;
    const trackSources = {
      pad: A._nodes.pad?.gain,
      arp: A._nodes.arp?.gain,
      melody: A._nodes.melody?.gain,
      drums: null // merge kick+snare+hat
    };
    this._trackTaps = {};
    for (const [name, source] of Object.entries(trackSources)) {
      const dest = Tone.context.createMediaStreamDestination();
      const tap = new Tone.Gain(1);
      tap.connect(dest);
      this._trackDests[name] = dest;
      this._trackTaps[name] = tap;
      if (source) source.connect(tap);
    }
    // Drums: merge individual drum channel gains into one tap
    if (A._nodes.kick?.gain) A._nodes.kick.gain.connect(this._trackTaps.drums);
    if (A._nodes.snare?.gain) A._nodes.snare.gain.connect(this._trackTaps.drums);
    if (A._nodes.hat?.gain) A._nodes.hat.gain.connect(this._trackTaps.drums);

    document.getElementById('rec-btn').addEventListener('click', () => {
      if (this._recording) this.stop(); else this.start();
    });
    document.getElementById('rec-multitrack').addEventListener('click', function() {
      MUZE.Recorder._multitrack = !MUZE.Recorder._multitrack;
      this.textContent = MUZE.Recorder._multitrack ? 'MULTI' : 'STEREO';
    });
  },

  _audioMime() {
    if (MediaRecorder.isTypeSupported('audio/mp4')) return 'audio/mp4';
    if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) return 'audio/webm;codecs=opus';
    return 'audio/webm';
  },

  start() {
    this._w = 720;
    this._h = Math.round(720 * (window.innerHeight / window.innerWidth));
    this._recCanvas.width = this._w; this._recCanvas.height = this._h;

    const canvasStream = this._recCanvas.captureStream(30);
    const audioTrack = this._audioDest.stream.getAudioTracks()[0];
    if (audioTrack) canvasStream.addTrack(audioTrack);

    this._mimeType = MediaRecorder.isTypeSupported('video/mp4') ? 'video/mp4' :
      MediaRecorder.isTypeSupported('video/webm;codecs=vp9,opus') ? 'video/webm;codecs=vp9,opus' : 'video/webm';

    this._chunks = [];
    this._mediaRec = new MediaRecorder(canvasStream, { mimeType: this._mimeType, videoBitsPerSecond: 4000000 });
    this._mediaRec.ondataavailable = (e) => { if (e.data.size > 0) this._chunks.push(e.data); };
    this._mediaRec.onstop = () => this._save();
    this._mediaRec.start(500);

    this._trackRecs = [];
    if (this._multitrack) {
      const aMime = this._audioMime();
      for (const [name, dest] of Object.entries(this._trackDests)) {
        this._trackChunks[name] = [];
        const rec = new MediaRecorder(dest.stream, { mimeType: aMime });
        rec.ondataavailable = (e) => { if (e.data.size > 0) this._trackChunks[name].push(e.data); };
        rec.start(500);
        this._trackRecs.push({ name, rec, mime: aMime });
      }
    }

    this._recording = true;
    document.getElementById('rec-btn').classList.add('recording');
  },

  stop() {
    this._recording = false;
    if (this._mediaRec && this._mediaRec.state === 'recording') this._mediaRec.stop();
    const pending = this._trackRecs.filter(t => t.rec.state === 'recording');
    let done = 0;
    if (pending.length) {
      pending.forEach(t => {
        t.rec.onstop = () => { done++; if (done === pending.length) this._saveMultitrack(); };
        t.rec.stop();
      });
    }
    document.getElementById('rec-btn').classList.remove('recording');
  },

  drawFrame() {
    if (!this._recording) return;
    const ctx = this._recCtx, w = this._w, h = this._h, S = MUZE.State;
    const vid = MUZE.Camera.video;
    if (vid.readyState >= 2) {
      const vw = vid.videoWidth, vh = vid.videoHeight;
      const canvasRatio = w / h, vidRatio = vw / vh;
      let sx = 0, sy = 0, sw = vw, sh = vh;
      if (vidRatio > canvasRatio) { sw = vh * canvasRatio; sx = (vw - sw) / 2; }
      else { sh = vw / canvasRatio; sy = (vh - sh) / 2; }
      ctx.save(); ctx.translate(w, 0); ctx.scale(-1, 1);
      ctx.drawImage(vid, sx, sy, sw, sh, 0, 0, w, h);
      ctx.restore();
    }
    ctx.drawImage(document.getElementById('overlay'), 0, 0, w, h);

    const s = w / 720;
    const sc = MUZE.Music.getScaleName(S.currentScale);
    const n = S.melodyNote ? MUZE.Music.midiToNote(S.melodyNote) : '-';
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath(); ctx.roundRect(6*s, 6*s, 220*s, 72*s, 6*s); ctx.fill();
    ctx.font = `${10*s}px monospace`; ctx.fillStyle = 'rgba(255,255,255,0.6)'; ctx.textAlign = 'left';
    const dbg = [
      `${S.faceDetected?'face':'...'} | ${sc} | chord ${S.chordIndex}`,
      `smile:${S.lipCorner.toFixed(2)} brow:${S.browHeight.toFixed(2)} eyes:${S.eyeOpenness.toFixed(2)}`,
      `pitch:${S.headPitch.toFixed(2)} yaw:${S.headYaw.toFixed(2)} roll:${S.headRoll.toFixed(2)}`,
      `hand:${S.handPresent?(S.handOpen?'open':'fist'):'\u2014'} note:${n} auto:${S.autoRhythm?'ON':'\u2014'}`,
    ];
    dbg.forEach((line, i) => ctx.fillText(line, 12*s, (18 + i*15)*s));

    // Mode HUD
    const modeName = MUZE.Music.getScaleName(S.currentScale).toUpperCase();
    const v = S.lipCorner;
    const hudW = 180*s, hudH = 54*s, hudX = (w - hudW) / 2, hudY = h - 100*s;
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.beginPath(); ctx.roundRect(hudX, hudY, hudW, hudH, 10*s); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.font = `bold ${22*s}px monospace`; ctx.textAlign = 'center';
    ctx.fillText(modeName, w / 2, hudY + 24*s);
    const barW = 140*s, barH = 5*s, barX = (w - barW) / 2, barY = hudY + 30*s;
    ctx.fillStyle = 'rgba(255,255,255,0.15)';
    ctx.beginPath(); ctx.roundRect(barX, barY, barW, barH, 2*s); ctx.fill();
    const pct = (v + 1) / 2;
    ctx.fillStyle = `hsl(${pct * 120},70%,55%)`;
    ctx.beginPath(); ctx.roundRect(barX + pct * (barW - 12*s), barY, 12*s, barH, 2*s); ctx.fill();
    ctx.font = `${10*s}px monospace`; ctx.fillStyle = 'rgba(255,255,255,0.5)';
    ctx.fillText('valence ' + v.toFixed(2), w / 2, hudY + 48*s);

    if (S.autoRhythm) {
      ctx.font = `${11*s}px monospace`; ctx.fillStyle = 'rgba(255,255,255,0.5)'; ctx.textAlign = 'center';
      ctx.fillText('AUTO', w / 2, h * 0.54);
    }

    // Chord bar
    const chordY = h - 40*s, chordH = 40*s;
    ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(0, chordY, w, chordH);
    const chords = ['I', 'ii', 'iii', 'IV', 'V', 'vi'];
    const cw = w / 6;
    ctx.font = `${12*s}px monospace`; ctx.textAlign = 'center';
    chords.forEach((c, i) => {
      if (i === S.chordIndex) { ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.fillRect(cw * i, chordY, cw, chordH); }
      ctx.fillStyle = i === S.chordIndex ? '#fff' : 'rgba(255,255,255,0.3)';
      ctx.fillText(c, cw * i + cw / 2, chordY + chordH / 2 + 4*s);
    });

    ctx.fillStyle = '#f33';
    ctx.beginPath(); ctx.arc(w - 30*s, 20*s, 5*s, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.font = `${10*s}px monospace`; ctx.textAlign = 'right';
    ctx.fillText('REC', w - 40*s, 24*s);
  },

  async _save() {
    const ext = this._mimeType.includes('mp4') ? 'mp4' : 'webm';
    const blob = new Blob(this._chunks, { type: this._mimeType });
    const fileName = `muze-${Date.now()}.${ext}`;
    if (navigator.canShare && navigator.canShare({ files: [new File([blob], fileName, { type: this._mimeType })] })) {
      try { await navigator.share({ files: [new File([blob], fileName, { type: this._mimeType })], title: 'Muze Session' }); return; } catch (e) {}
    }
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = fileName; a.click();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  },

  _saveMultitrack() {
    const ts = Date.now();
    for (const [name, chunks] of Object.entries(this._trackChunks)) {
      if (!chunks.length) continue;
      const rec = this._trackRecs.find(t => t.name === name);
      const ext = rec.mime.includes('mp4') ? 'm4a' : 'webm';
      const blob = new Blob(chunks, { type: rec.mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a'); a.href = url; a.download = `muze-${name}-${ts}.${ext}`; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 5000);
    }
  }
};
