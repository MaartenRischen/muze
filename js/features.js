/* ============================================================
   MUZE — Sprint 3 Features
   Loop Recorder, Scene Manager, Gyroscope, Preset Crossfade
   ============================================================ */

// ============================================================
// MELODY LOOP RECORDER
// Records hand melody notes as timed events over 4 bars.
// On playback, replays the melody via the melody synth.
// User can overdub additional melody phrases on top.
// ============================================================
MUZE.LoopRecorder = {
  _state: 'empty', // empty | recording | playing | overdubbing
  _layers: [],      // array of arrays of {time, note, duration} events
  _loopDuration: 0, // ms
  _startTime: 0,
  _playbackPart: null,
  _progressRAF: null,
  _currentNote: null,
  _noteStartTime: 0,
  _barCount: 4,     // variable loop length: 1, 2, 4, or 8 bars
  _barOptions: [1, 2, 4, 8],

  init() {
    const ids = ['loop-rec-panel-btn', 'loop-overdub-panel-btn', 'loop-undo-panel-btn', 'loop-clear-panel-btn',
                 'loop-rec-btn', 'loop-overdub-btn', 'loop-undo-btn', 'loop-clear-btn'];
    const fns = [() => this._onRecBtn(), () => this._onOverdubBtn(), () => this._undoLayer(), () => this._clearAll()];
    for (let i = 0; i < 4; i++) {
      const el1 = document.getElementById(ids[i]);
      const el2 = document.getElementById(ids[i + 4]);
      if (el1) el1.addEventListener('click', fns[i]);
      if (el2) el2.addEventListener('click', fns[i]);
    }

    // Wire up bar-count cycle button if present
    const barBtn = document.getElementById('loop-bar-count-btn') || document.getElementById('loop-bar-count');
    if (barBtn) {
      barBtn.addEventListener('click', () => this.cycleBarCount());
      barBtn.textContent = this._barCount + ' BAR' + (this._barCount > 1 ? 'S' : '');
    }
  },

  _getLoopMs() {
    return (60000 / Tone.Transport.bpm.value) * 4 * this._barCount; // beats-per-bar * barCount
  },

  // Cycle loop length through 1, 2, 4, 8 bars
  cycleBarCount() {
    if (this._state !== 'empty') return this._barCount; // only change when idle
    const idx = this._barOptions.indexOf(this._barCount);
    this._barCount = this._barOptions[(idx + 1) % this._barOptions.length];
    // Update UI if a display element exists
    const el = document.getElementById('loop-bar-count');
    if (el) el.textContent = this._barCount + ' BAR' + (this._barCount > 1 ? 'S' : '');
    return this._barCount;
  },

  getBarCount() {
    return this._barCount;
  },

  setBarCount(bars) {
    if (!this._barOptions.includes(bars)) return;
    if (this._state !== 'empty') return; // only change when idle
    this._barCount = bars;
    const el = document.getElementById('loop-bar-count');
    if (el) el.textContent = this._barCount + ' BAR' + (this._barCount > 1 ? 'S' : '');
  },

  // Called from app.js main loop when hand melody note changes during recording
  recordNote(midiNote) {
    if (this._state !== 'recording' && this._state !== 'overdubbing') return;
    const now = performance.now();
    const elapsed = now - this._startTime;
    const layer = this._layers[this._layers.length - 1];
    if (!layer) return;

    // End previous note
    if (this._currentNote !== null) {
      const last = layer[layer.length - 1];
      if (last && last.duration === 0) {
        last.duration = Math.max(0.05, (elapsed - last.time) / 1000); // seconds
      }
    }

    if (midiNote !== null) {
      layer.push({ time: elapsed / 1000, note: MUZE.Music.midiToNote(midiNote), duration: 0 });
    }
    this._currentNote = midiNote;
    this._noteStartTime = now;
  },

  // Called when hand leaves frame during recording
  recordNoteOff() {
    if (this._state !== 'recording' && this._state !== 'overdubbing') return;
    const layer = this._layers[this._layers.length - 1];
    if (layer.length > 0) {
      const last = layer[layer.length - 1];
      if (last.duration === 0) {
        last.duration = Math.max(0.05, (performance.now() - this._noteStartTime) / 1000);
      }
    }
    this._currentNote = null;
  },

  _onRecBtn() {
    switch (this._state) {
      case 'empty': this._startRecording(); break;
      case 'recording': this._stopRecording(); break;
      case 'playing': this._startOverdub(); break;
      case 'overdubbing': this._stopOverdub(); break;
    }
  },

  _onOverdubBtn() {
    if (this._state === 'playing') this._startOverdub();
    else if (this._state === 'overdubbing') this._stopOverdub();
  },

  _startRecording() {
    this._state = 'counting';
    this._updateUI();
    const beatMs = 60000 / Tone.Transport.bpm.value;
    // Track count-in timers so cancel mid-count-in doesn't leave ghost hats firing 2s later.
    this._countInTimers = this._countInTimers || [];
    for (let i = 0; i < 4; i++) {
      this._countInTimers.push(setTimeout(() => {
        if (this._state !== 'counting') return;
        MUZE.Audio.triggerDrum('hat', 0.3);
      }, i * beatMs));
    }
    this._countInTimers.push(setTimeout(() => {
      if (this._state !== 'counting') return;
      this._state = 'recording';
      this._loopDuration = this._getLoopMs();
      this._startTime = performance.now();
      this._layers = [[]];
      this._currentNote = null;
      this._updateUI();
      this._startProgress();
      this._autoStopTimer = setTimeout(() => {
        if (this._state === 'recording') this._stopRecording();
      }, this._loopDuration);
    }, 4 * beatMs));
  },

  _clearCountInTimers() {
    if (!this._countInTimers) return;
    for (const id of this._countInTimers) clearTimeout(id);
    this._countInTimers = [];
  },

  _stopRecording() {
    this._clearCountInTimers();
    clearTimeout(this._autoStopTimer);
    this.recordNoteOff(); // close any open note
    if (this._layers[0].length === 0) {
      this._layers = [];
      this._state = 'empty';
      this._stopProgress();
      this._updateUI();
      return;
    }
    this._state = 'playing';
    this._buildPlayback();
    this._updateUI();
  },

  _startOverdub() {
    this._state = 'overdubbing';
    this._layers.push([]);
    this._startTime = performance.now();
    this._currentNote = null;
    this._updateUI();

    this._autoStopTimer = setTimeout(() => {
      if (this._state === 'overdubbing') this._stopOverdub();
    }, this._loopDuration);
  },

  _stopOverdub() {
    clearTimeout(this._autoStopTimer);
    this.recordNoteOff();
    if (this._layers[this._layers.length - 1].length === 0) this._layers.pop();
    this._state = 'playing';
    this._buildPlayback();
    this._updateUI();
  },

  _buildPlayback() {
    if (this._playbackPart) { this._playbackPart.stop(); this._playbackPart.dispose(); this._playbackPart = null; }

    // Merge all layers into one event list
    const events = [];
    for (const layer of this._layers) {
      for (const evt of layer) {
        events.push({ time: evt.time, note: evt.note, duration: evt.duration || 0.2 });
      }
    }
    events.sort((a, b) => a.time - b.time);

    const loopSec = this._loopDuration / 1000;
    this._playbackPart = new Tone.Part((time, evt) => {
      MUZE.Audio.melodySynth.triggerAttackRelease(evt.note, evt.duration, time, 0.6);
    }, events.map(e => [e.time, { note: e.note, duration: e.duration }]));

    this._playbackPart.loop = true;
    this._playbackPart.loopEnd = loopSec;
    this._playbackPart.start(0);
    this._startTime = performance.now();
    this._startProgress();
  },

  _undoLayer() {
    if (this._layers.length <= 0) return;
    this._layers.pop();
    if (this._layers.length === 0) { this._clearAll(); return; }
    this._buildPlayback();
    this._updateUI();
  },

  _clearAll() {
    this._clearCountInTimers();
    clearTimeout(this._autoStopTimer);
    if (this._playbackPart) { this._playbackPart.stop(); this._playbackPart.dispose(); this._playbackPart = null; }
    this._layers = [];
    this._state = 'empty';
    this._currentNote = null;
    this._stopProgress();
    this._updateUI();
  },

  _startProgress() {
    this._stopProgress();
    const fill = document.getElementById('loop-progress-fill');
    const bar = document.getElementById('loop-progress-bar');
    if (bar) bar.classList.remove('hidden');
    const tick = () => {
      if (this._state === 'empty') return;
      const elapsed = (performance.now() - this._startTime) % this._loopDuration;
      if (fill) fill.style.width = (elapsed / this._loopDuration * 100) + '%';
      this._progressRAF = requestAnimationFrame(tick);
    };
    this._progressRAF = requestAnimationFrame(tick);
  },

  _stopProgress() {
    if (this._progressRAF) { cancelAnimationFrame(this._progressRAF); this._progressRAF = null; }
    const fill = document.getElementById('loop-progress-fill');
    const bar = document.getElementById('loop-progress-bar');
    if (fill) fill.style.width = '0%';
    if (bar) bar.classList.add('hidden');
  },

  _updateUI() {
    const pRec = document.getElementById('loop-rec-panel-btn');
    const pOvr = document.getElementById('loop-overdub-panel-btn');
    const pUndo = document.getElementById('loop-undo-panel-btn');
    const pClear = document.getElementById('loop-clear-panel-btn');

    const isCounting = this._state === 'counting';
    const isRec = this._state === 'recording';
    const isOvr = this._state === 'overdubbing';
    const isPlay = this._state === 'playing';
    const hasLayers = this._layers.length > 0;

    if (pRec) {
      pRec.textContent = isCounting ? '● COUNT' : isRec || isOvr ? '■ STOP' : isPlay ? '● OVR' : '● REC';
      pRec.style.color = isCounting ? '#facc15' : isRec ? '#ef4444' : isOvr ? '#f59e0b' : '';
    }
    if (pOvr) pOvr.disabled = !isPlay;
    if (pUndo) pUndo.disabled = !hasLayers || isRec || isOvr;
    if (pClear) pClear.disabled = !hasLayers || isRec || isOvr;

    const bar = document.getElementById('loop-progress-bar');
    if (bar) {
      bar.classList.remove('recording', 'overdubbing');
      if (isRec) bar.classList.add('recording');
      if (isOvr) bar.classList.add('overdubbing');
    }
  }
};

// ============================================================
// SCENE / SNAPSHOT SYSTEM — 4 slots with crossfade recall
// ============================================================
MUZE.SceneManager = {
  _scenes: [null, null, null, null],
  _activeSlot: -1,
  _saveMode: false,

  init() {
    const saveBtn = document.getElementById('scene-save-btn');
    saveBtn.addEventListener('click', () => {
      this._saveMode = !this._saveMode;
      saveBtn.classList.toggle('active', this._saveMode);
      document.querySelectorAll('.scene-slot').forEach(s => {
        s.classList.toggle('save-mode', this._saveMode);
      });
    });

    document.querySelectorAll('.scene-slot').forEach(btn => {
      btn.addEventListener('click', () => {
        const idx = parseInt(btn.dataset.scene);
        if (this._saveMode) {
          this._saveScene(idx);
          this._saveMode = false;
          saveBtn.classList.remove('active');
          document.querySelectorAll('.scene-slot').forEach(s => s.classList.remove('save-mode'));
        } else {
          this._recallScene(idx);
        }
      });
    });
  },

  _captureState() {
    const S = MUZE.State;
    const M = MUZE.Mixer;
    return {
      // Synth params
      bpm: S.bpm,
      rootOffset: S.rootOffset,
      swing: S.swing,
      arpPatternIdx: S.arpPatternIdx,
      extraScaleMode: S.extraScaleMode,
      chordIndex: S.chordIndex,
      presetIdx: S.presetIdx,
      chordAutoAdvance: MUZE.ChordAdvance ? MUZE.ChordAdvance._active : false,
      // Mixer volumes
      volumes: {},
      pans: {},
      reverbSends: {},
      delaySends: {},
      // Synth oscillator types
      padOsc: document.getElementById('pad-osc')?.value || 'sine',
      arpOsc: document.getElementById('arp-osc')?.value || 'sawtooth',
      melOsc: document.getElementById('mel-osc')?.value || 'triangle',
      // Master
      masterVolume: M.master.volume,
      // Extended preset parameters
      arpRate: MUZE.State.arpRate || '8n',
      padChorusDepth: MUZE.State.padChorusDepth !== undefined ? MUZE.State.padChorusDepth : 0.3,
      delayTime: MUZE.State.delayTime || '8n.',
      reverbDecay: MUZE.State.reverbDecay !== undefined ? MUZE.State.reverbDecay : 2.5,
    };
  },

  _saveScene(idx) {
    const state = this._captureState();
    // Capture mixer channel data
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      const d = MUZE.Mixer.channels[ch];
      state.volumes[ch] = d.volume;
      state.pans[ch] = d.pan;
      state.reverbSends[ch] = d.reverbSend;
      state.delaySends[ch] = d.delaySend;
    }
    this._scenes[idx] = state;
    this._activeSlot = idx;
    this._updateSlotUI();

    // Visual feedback
    const btn = document.querySelector(`.scene-slot[data-scene="${idx}"]`);
    btn.classList.add('saved-flash');
    setTimeout(() => btn.classList.remove('saved-flash'), 400);
  },

  _recallScene(idx) {
    const scene = this._scenes[idx];
    if (!scene) return;

    this._activeSlot = idx;
    this._crossfadeTo(scene);
    this._updateSlotUI();
  },

  _crossfadeTo(scene) {
    const FADE_TIME = 2; // seconds

    // BPM crossfade
    Tone.Transport.bpm.rampTo(scene.bpm, FADE_TIME);
    MUZE.State.bpm = scene.bpm;
    document.getElementById('bpm-val').textContent = scene.bpm;
    document.getElementById('bpm-slider').value = scene.bpm;

    // Root note
    MUZE.State.rootOffset = scene.rootOffset;
    document.getElementById('key-val').textContent = MUZE.Config.ROOT_NAMES[scene.rootOffset];

    // Swing
    MUZE.Audio.setSwing(scene.swing);
    document.getElementById('swing-slider').value = scene.swing;
    document.getElementById('swing-val').textContent = scene.swing + '%';

    // Arp pattern
    MUZE.State.arpPatternIdx = scene.arpPatternIdx;
    const arpBtn = document.getElementById('arp-pattern');
    if (arpBtn) arpBtn.textContent = MUZE.Config.ARP_PATTERNS[scene.arpPatternIdx];

    // Scale mode
    MUZE.State.extraScaleMode = scene.extraScaleMode;
    if (scene.extraScaleMode) {
      MUZE.State.modeFrozen = true;
      MUZE.State.currentScale = MUZE.Music.EXTRA_SCALES[scene.extraScaleMode];
      document.getElementById('scale-val').textContent = scene.extraScaleMode;
    } else {
      MUZE.State.modeFrozen = false;
      document.getElementById('scale-val').textContent = 'modal';
    }

    // Chord
    MUZE.State.chordIndex = scene.chordIndex;
    document.querySelectorAll('.chord-btn').forEach((b, i) => b.classList.toggle('active', i === scene.chordIndex));
    MUZE.Loop._currentPadKey = null; // force pad retrigger

    // Mixer channels — crossfade volumes, sends
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      if (scene.volumes[ch] !== undefined) {
        const node = MUZE.Audio._nodes[ch];
        if (node) {
          node.gain.gain.rampTo(Tone.dbToGain(scene.volumes[ch]), FADE_TIME);
          MUZE.Mixer.channels[ch].volume = scene.volumes[ch];
        }
      }
      if (scene.pans[ch] !== undefined) {
        MUZE.Mixer.setChannelPan(ch, scene.pans[ch]);
      }
      if (scene.reverbSends[ch] !== undefined) {
        MUZE.Mixer.channels[ch].reverbSend = scene.reverbSends[ch];
        const node = MUZE.Audio._nodes[ch];
        if (node) node.reverbSend.gain.rampTo(scene.reverbSends[ch], FADE_TIME);
      }
      if (scene.delaySends[ch] !== undefined) {
        MUZE.Mixer.channels[ch].delaySend = scene.delaySends[ch];
        const node = MUZE.Audio._nodes[ch];
        if (node) node.delaySend.gain.rampTo(scene.delaySends[ch], FADE_TIME);
      }
    }

    // Master volume crossfade
    if (MUZE.Audio._masterGain) {
      MUZE.Audio._masterGain.gain.rampTo(Tone.dbToGain(scene.masterVolume), FADE_TIME);
      MUZE.Mixer.master.volume = scene.masterVolume;
    }

    // Chord auto-advance
    if (MUZE.ChordAdvance) {
      if (scene.chordAutoAdvance && !MUZE.ChordAdvance._active) {
        MUZE.ChordAdvance._active = true;
        MUZE.ChordAdvance._start();
        const acBtn = document.getElementById('auto-chord-btn');
        if (acBtn) acBtn.classList.add('active');
        const acVal = document.getElementById('auto-chord-val');
        if (acVal) acVal.textContent = 'AUTO';
      } else if (!scene.chordAutoAdvance && MUZE.ChordAdvance._active) {
        MUZE.ChordAdvance._active = false;
        MUZE.ChordAdvance._stop();
        const acBtn = document.getElementById('auto-chord-btn');
        if (acBtn) acBtn.classList.remove('active');
        const acVal = document.getElementById('auto-chord-val');
        if (acVal) acVal.textContent = 'OFF';
      }
    }

    // Extended preset parameters
    if (scene.arpRate) {
      MUZE.State.arpRate = scene.arpRate;
      if (MUZE.Audio._arpSeq) MUZE.Audio._arpSeq.interval = scene.arpRate;
    }
    if (scene.padChorusDepth !== undefined) {
      MUZE.State.padChorusDepth = scene.padChorusDepth;
      if (MUZE.Audio._chorusBus) MUZE.Audio._chorusBus.depth = scene.padChorusDepth;
      else if (MUZE.Audio._chorus) MUZE.Audio._chorus.depth = scene.padChorusDepth;
    }
    if (scene.delayTime) {
      MUZE.State.delayTime = scene.delayTime;
      if (MUZE.Audio._delayBus) {
        try {
          const dt = scene.delayTime;
          MUZE.Audio._delayBus.delayTime.rampTo(
            dt === '16n' ? 0.125 : dt === '8n.' ? 0.375 : dt === '4n.' ? 0.75 : 0.25, FADE_TIME);
        } catch(e) {}
      }
    }
    if (scene.reverbDecay !== undefined) {
      MUZE.State.reverbDecay = scene.reverbDecay;
      if (MUZE.Audio._reverbBus) {
        try { MUZE.Audio._reverbBus.decay = scene.reverbDecay; } catch(e) {}
      }
    }

    // Oscillator types (instant — no crossfade for these)
    if (scene.padOsc) {
      MUZE.Audio.padSynth.set({ oscillator: { type: scene.padOsc } });
    }
    if (scene.arpOsc) {
      MUZE.Audio.leadSynth.set({ oscillator: { type: scene.arpOsc } });
    }
    if (scene.melOsc) {
      MUZE.Audio.melodySynth.set({ oscillator: { type: scene.melOsc } });
    }
  },

  _updateSlotUI() {
    document.querySelectorAll('.scene-slot').forEach((btn, i) => {
      btn.classList.toggle('has-scene', this._scenes[i] !== null);
      btn.classList.toggle('active', i === this._activeSlot);
    });
  }
};

// ============================================================
// GYROSCOPE / ACCELEROMETER INTEGRATION
// Maps tilt to filter + reverb for expressive mobile control
// ============================================================
MUZE.Gyroscope = {
  _active: false,
  _gamma: 0, // left/right tilt (-90 to 90)
  _beta: 0,  // forward/back tilt (-180 to 180)
  _hasPermission: false,
  _smoothGamma: 0,
  _smoothBeta: 0,

  init() {
    const btn = document.getElementById('gyro-btn');
    btn.addEventListener('click', () => this._toggle());
  },

  async _toggle() {
    if (this._active) {
      this._deactivate();
      return;
    }

    // iOS requires permission request
    if (typeof DeviceOrientationEvent !== 'undefined' &&
        typeof DeviceOrientationEvent.requestPermission === 'function') {
      try {
        const permission = await DeviceOrientationEvent.requestPermission();
        if (permission !== 'granted') return;
        this._hasPermission = true;
      } catch (e) {
        console.warn('Gyroscope permission denied:', e);
        return;
      }
    }

    this._activate();
  },

  _activate() {
    this._active = true;
    document.getElementById('gyro-btn').classList.add('active-feature');
    document.getElementById('gyro-indicator').classList.remove('hidden');

    this._handler = (e) => {
      if (e.gamma !== null) this._gamma = e.gamma;
      if (e.beta !== null) this._beta = e.beta;
    };
    window.addEventListener('deviceorientation', this._handler);

    this._updateRAF = requestAnimationFrame(() => this._update());
  },

  _deactivate() {
    this._active = false;
    document.getElementById('gyro-btn').classList.remove('active-feature');
    document.getElementById('gyro-indicator').classList.add('hidden');

    if (this._handler) {
      window.removeEventListener('deviceorientation', this._handler);
    }
    if (this._updateRAF) {
      cancelAnimationFrame(this._updateRAF);
    }

    // Reset parameters
    if (MUZE.Audio._masterFilter) {
      // Filter will return to face control naturally
    }
  },

  _update() {
    if (!this._active) return;
    this._updateRAF = requestAnimationFrame(() => this._update());

    // Smooth the values
    const alpha = 0.15;
    this._smoothGamma = this._smoothGamma * (1 - alpha) + this._gamma * alpha;
    this._smoothBeta = this._smoothBeta * (1 - alpha) + this._beta * alpha;

    // Map gamma (left/right, -45 to +45 usable range) to pan offset on master
    const gammaClamp = Math.max(-45, Math.min(45, this._smoothGamma));
    const panValue = gammaClamp / 45; // -1 to +1

    // Map beta (forward/back, 0-90 range, center at ~45) to reverb modulation
    const betaNorm = Math.max(0, Math.min(1, (this._smoothBeta - 20) / 50));

    // Apply: gamma controls arp panning
    if (MUZE.Audio._nodes.arp) {
      MUZE.Audio._nodes.arp.panner.pan.rampTo(panValue * 0.7, 0.1);
    }
    // And melody panning (opposite direction for stereo width)
    if (MUZE.Audio._nodes.melody) {
      MUZE.Audio._nodes.melody.panner.pan.rampTo(-panValue * 0.5, 0.1);
    }

    // Beta controls reverb send amount on face-linked channels
    for (const ch of ['pad', 'arp', 'melody']) {
      const node = MUZE.Audio._nodes[ch];
      const data = MUZE.Mixer.channels[ch];
      if (node && data) {
        const baseReverb = data.reverbSend;
        node.reverbSend.gain.rampTo(baseReverb * (0.5 + betaNorm * 1.0), 0.1);
      }
    }

    // Update visual indicators
    const lrFill = document.getElementById('gyro-lr-fill');
    const fbFill = document.getElementById('gyro-fb-fill');
    if (lrFill) {
      const lrPct = ((panValue + 1) / 2) * 100;
      lrFill.style.left = Math.min(lrPct, 50) + '%';
      lrFill.style.width = Math.abs(lrPct - 50) + '%';
    }
    if (fbFill) {
      fbFill.style.width = (betaNorm * 100) + '%';
      fbFill.style.left = '0%';
    }
  }
};

// ============================================================
// BEAT REPEAT / STUTTER EFFECT
// Triple-tap drum zone to activate 2-second stutter
// ============================================================
MUZE.BeatRepeat = {
  _active: false,
  _tapTimes: [],
  _timeout: null,
  _stutterLoop: null,
  _lastDrum: 'kick',

  init() {
    // Listen for triple-tap on drum zone
    const zone = document.getElementById('touch-zone');
    zone.addEventListener('touchstart', (e) => this._onTap(e), { passive: true });
  },

  _onTap(e) {
    if (this._active) return;
    const now = performance.now();
    // Keep only taps within 500ms window
    this._tapTimes = this._tapTimes.filter(t => now - t < 500);
    this._tapTimes.push(now);

    if (this._tapTimes.length >= 3) {
      this._tapTimes = [];
      // Determine which drum zone was tapped
      const touch = e.changedTouches[0];
      const target = document.elementFromPoint(touch.clientX, touch.clientY);
      if (target) {
        const drum = target.dataset.drum || target.parentElement?.dataset?.drum || 'kick';
        this._lastDrum = drum;
      }
      this._startStutter();
    }
  },

  _startStutter() {
    this._active = true;
    const overlay = document.getElementById('beat-repeat-overlay');
    if (overlay) overlay.classList.add('active');

    const bpm = Tone.Transport.bpm.value;

    // Stutter pattern: 8th notes for 0.7s, then 16th, then 32nd
    const eighthMs = (60000 / bpm) / 2;
    const sixteenthMs = eighthMs / 2;
    const thirtySecondMs = sixteenthMs / 2;

    let elapsed = 0;
    const totalDuration = 2000;

    const schedule = [];
    // Phase 1: 8th notes for ~700ms
    let t = 0;
    while (t < 700 && t < totalDuration) {
      schedule.push(t);
      t += eighthMs;
    }
    // Phase 2: 16th notes for ~600ms
    while (t < 1300 && t < totalDuration) {
      schedule.push(t);
      t += sixteenthMs;
    }
    // Phase 3: 32nd notes to end
    while (t < totalDuration) {
      schedule.push(t);
      t += thirtySecondMs;
    }

    // Fire all scheduled hits
    const drum = this._lastDrum;
    const startTime = performance.now();
    let idx = 0;

    const tick = () => {
      if (!this._active) return;
      const now = performance.now();
      const e = now - startTime;

      while (idx < schedule.length && schedule[idx] <= e) {
        // Velocity increases with speed
        const phase = e / totalDuration;
        const vel = 0.4 + phase * 0.5;
        MUZE.Audio.triggerDrum(drum, vel);
        idx++;
      }

      if (e < totalDuration) {
        requestAnimationFrame(tick);
      } else {
        this._stopStutter();
      }
    };

    requestAnimationFrame(tick);

    // Safety timeout
    this._timeout = setTimeout(() => this._stopStutter(), totalDuration + 100);
  },

  _stopStutter() {
    this._active = false;
    clearTimeout(this._timeout);
    const overlay = document.getElementById('beat-repeat-overlay');
    if (overlay) overlay.classList.remove('active');
  }
};

// ============================================================
// CHORD PROGRESSION AUTO-ADVANCE
// Steps through a curated, musical progression (one chord per bar)
// instead of a flat I->ii->iii cycle. Progression is selectable.
// ============================================================
MUZE.ChordAdvance = {
  _active: false,
  _loop: null,
  _progIdx: 0,   // which progression in Config.PROGRESSIONS
  _step: 0,      // position within the current progression

  init() {
    const btn = document.getElementById('auto-chord-btn');
    if (!btn) return;

    btn.addEventListener('click', () => {
      this._active = !this._active;
      btn.classList.toggle('active', this._active);
      document.getElementById('auto-chord-val').textContent =
        this._active ? this.getProgressionName() : 'OFF';

      if (this._active) {
        this._start();
      } else {
        this._stop();
      }
    });
  },

  _progression() {
    const list = MUZE.Config.PROGRESSIONS;
    if (list && list.length) return list[this._progIdx % list.length];
    // Fallback: flat I..vi cycle if no library present
    return { name: 'AUTO', degrees: [0, 1, 2, 3, 4, 5] };
  },

  getProgressionName() {
    return this._progression().name;
  },

  // Cycle the selected progression (used by the perform UI). Restarts the
  // loop in-place if currently active so the change is heard immediately.
  cycleProgression() {
    const list = MUZE.Config.PROGRESSIONS;
    const n = (list && list.length) ? list.length : 1;
    this._progIdx = (this._progIdx + 1) % n;
    if (this._active) { this._stop(); this._start(); }
    return this.getProgressionName();
  },

  setProgression(idx) {
    const list = MUZE.Config.PROGRESSIONS;
    const n = (list && list.length) ? list.length : 1;
    this._progIdx = ((idx % n) + n) % n;
    if (this._active) { this._stop(); this._start(); }
  },

  // Apply the chord at the current step (visual + audio retrigger)
  _applyStep() {
    const prog = this._progression();
    const degree = prog.degrees[this._step % prog.degrees.length];
    MUZE.State.chordIndex = degree;
    document.querySelectorAll('.chord-btn').forEach((b, i) => {
      b.classList.toggle('active', i === degree);
    });
    this._updateNextIndicator();
    MUZE.Loop._currentPadKey = null; // force pad retrigger
  },

  _start() {
    this._step = 0;
    // Play the first chord of the progression immediately
    Tone.Draw.schedule(() => this._applyStep(), Tone.now());
    // Then advance one chord per bar
    this._loop = new Tone.Loop((time) => {
      this._step++;
      Tone.Draw.schedule(() => this._applyStep(), time);
    }, '1m');
    this._loop.start('+1m'); // first advance after one bar
  },

  _stop() {
    if (this._loop) {
      this._loop.stop();
      this._loop.dispose();
      this._loop = null;
    }
    document.querySelectorAll('.chord-btn.next-chord').forEach(b => b.classList.remove('next-chord'));
  },

  _updateNextIndicator() {
    document.querySelectorAll('.chord-btn.next-chord').forEach(b => b.classList.remove('next-chord'));
    if (!this._active) return;
    const prog = this._progression();
    const nextDegree = prog.degrees[(this._step + 1) % prog.degrees.length];
    const nextBtn = document.querySelector(`.chord-btn[data-chord="${nextDegree}"]`);
    if (nextBtn) nextBtn.classList.add('next-chord');
  }
};

// ============================================================
// VIBES — one-tap curated combos (preset + scale + key + groove +
// progression). The fastest path to "this already sounds good".
// Each vibe layers a fixed scale + drum groove + chord progression on
// top of a base preset, so a single tap reconfigures the whole instrument.
// ============================================================
MUZE.Vibes = {
  _idx: -1,

  // groove = index into Config.RHYTHM_PATTERNS; progression = index into
  // Config.PROGRESSIONS (or -1 for off); scale = key in Music.EXTRA_SCALES
  // (or null for face-controlled modal); key = rootOffset 0-11.
  LIST: [
    { name: 'Lofi Sunset',  preset: 'Lo-Fi Chill', scale: 'pent. minor',  key: 5,  groove: 7,  progression: 1 },
    { name: 'Neon Drive',   preset: 'Synthwave',    scale: 'pent. minor',  key: 9,  groove: 0,  progression: 0 },
    { name: 'Deep Calm',    preset: 'Meditation',   scale: 'in-sen',       key: 0,  groove: 3,  progression: 7 },
    { name: 'Midnight Jazz',preset: 'Trap Soul',    scale: 'blues',        key: 1,  groove: 7,  progression: 3 },
    { name: 'Festival',     preset: 'Future Bass',  scale: 'pent. major',  key: 10, groove: 4,  progression: 0 },
    { name: 'Cosmic Drift', preset: 'Deep Space',   scale: 'whole tone',   key: 3,  groove: 3,  progression: 9 },
    { name: 'Liquid Flow',  preset: 'Liquid DnB',   scale: 'pent. minor',  key: 2,  groove: 8,  progression: 6 },
    { name: 'Dark Ritual',  preset: 'Cinematic',    scale: 'hungarian min',key: 8,  groove: 5,  progression: 5 },
  ],

  init() {
    const btn = document.getElementById('perf-vibe-btn');
    if (!btn) return;
    btn.addEventListener('click', () => {
      this._idx = (this._idx + 1) % this.LIST.length;
      this.apply(this._idx);
      btn.textContent = this.LIST[this._idx].name;
    });
  },

  apply(idx) {
    const v = this.LIST[idx];
    if (!v) return;

    // 1. Base preset (bpm, key, synths, volumes, sends, swing, arp pattern)
    const pIdx = MUZE.Config.PRESETS.findIndex(p => p.name === v.preset);
    if (pIdx >= 0) MUZE.Audio.applyPreset(pIdx);

    // 2. Fixed scale (so the vibe sounds consistent without needing a smile)
    if (v.scale && MUZE.Music.EXTRA_SCALES[v.scale]) {
      MUZE.State.extraScaleMode = v.scale;
      MUZE.State.modeFrozen = true;
      MUZE.State.currentScale = MUZE.Music.EXTRA_SCALES[v.scale];
    } else {
      MUZE.State.extraScaleMode = null;
      MUZE.State.modeFrozen = false;
    }

    // 3. Key override (after preset, which also sets a key)
    if (v.key != null) MUZE.State.rootOffset = ((v.key % 12) + 12) % 12;

    // 4. Drum groove
    if (v.groove != null && MUZE.AutoRhythm &&
        v.groove < MUZE.Config.RHYTHM_PATTERNS.length) {
      MUZE.AutoRhythm._patIdx = v.groove;
      MUZE.AutoRhythm._useCustom = false;
      if (MUZE.AutoRhythm._active) MUZE.AutoRhythm._restart();
    }

    // 5. Chord progression
    if (MUZE.ChordAdvance) {
      if (v.progression != null && v.progression >= 0) {
        MUZE.ChordAdvance._stop();
        MUZE.ChordAdvance._progIdx = v.progression;
        MUZE.ChordAdvance._active = true;
        MUZE.ChordAdvance._start();
      } else {
        MUZE.ChordAdvance._active = false;
        MUZE.ChordAdvance._stop();
      }
    }

    MUZE.Loop._currentPadKey = null; // force pad retrigger
    this._idx = idx;
    this._syncLabels(v);
  },

  // Reflect the new state across the Perform tab controls
  _syncLabels(v) {
    const set = (id, txt) => { const el = document.getElementById(id); if (el) el.textContent = txt; };
    set('perf-vibe-btn', v.name);
    set('perf-preset-btn', v.preset);
    set('perf-scale-btn', v.scale || 'Modal (face)');
    set('scale-val', v.scale || 'modal');
    if (MUZE.ChordAdvance) {
      const label = MUZE.ChordAdvance._active ? MUZE.ChordAdvance.getProgressionName() : 'OFF';
      set('perf-chords-btn', label);
      set('auto-chord-val', label);
      const acBtn = document.getElementById('auto-chord-btn');
      if (acBtn) acBtn.classList.toggle('active', MUZE.ChordAdvance._active);
    }
    if (MUZE.PerformTab && MUZE.PerformTab._syncDisplays) MUZE.PerformTab._syncDisplays();
  }
};

// ============================================================
// SIDECHAIN PUMPING — Kick ducks pad volume
// ============================================================
MUZE.Sidechain = {
  _ducking: false,
  _duckGain: null,

  init() {
    // Create a gain node inline for the pad that we control for ducking
    // We'll use the existing pad gain node
  },

  duck() {
    const padNode = MUZE.Audio._nodes.pad;
    const arpNode = MUZE.Audio._nodes.arp;
    const now = Tone.now();

    // Duck pad to 10% with 5ms linear attack, 30ms hold, 300ms exponential release
    if (padNode) {
      const padGain = padNode.gain.gain.value;
      padNode.gain.gain.cancelScheduledValues(now);
      padNode.gain.gain.setValueAtTime(padGain, now);
      padNode.gain.gain.linearRampToValueAtTime(padGain * 0.10, now + 0.005);   // 5ms attack
      padNode.gain.gain.setValueAtTime(padGain * 0.10, now + 0.005 + 0.030);    // 30ms hold
      padNode.gain.gain.exponentialRampToValueAtTime(Math.max(padGain, 0.001), now + 0.005 + 0.030 + 0.300); // 300ms release
    }

    // Duck arp to 50% with same attack/hold, 250ms exponential release
    if (arpNode) {
      const arpGain = arpNode.gain.gain.value;
      arpNode.gain.gain.cancelScheduledValues(now);
      arpNode.gain.gain.setValueAtTime(arpGain, now);
      arpNode.gain.gain.linearRampToValueAtTime(arpGain * 0.50, now + 0.005);   // 5ms attack
      arpNode.gain.gain.setValueAtTime(arpGain * 0.50, now + 0.005 + 0.030);    // 30ms hold
      arpNode.gain.gain.exponentialRampToValueAtTime(Math.max(arpGain, 0.001), now + 0.005 + 0.030 + 0.250); // 250ms release
    }
  }
};
