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
  },

  _getLoopMs() {
    return (60000 / Tone.Transport.bpm.value) * 4 * 4; // 4 bars
  },

  // Called from app.js main loop when hand melody note changes during recording
  recordNote(midiNote) {
    if (this._state !== 'recording' && this._state !== 'overdubbing') return;
    const now = performance.now();
    const elapsed = now - this._startTime;
    const layer = this._layers[this._layers.length - 1];

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
  },

  _stopRecording() {
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

    const isRec = this._state === 'recording';
    const isOvr = this._state === 'overdubbing';
    const isPlay = this._state === 'playing';
    const hasLayers = this._layers.length > 0;

    if (pRec) {
      pRec.textContent = isRec || isOvr ? '■ STOP' : isPlay ? '● OVR' : '● REC';
      pRec.style.color = isRec ? '#ef4444' : isOvr ? '#f59e0b' : '';
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
// Cycles I -> ii -> iii -> IV -> V -> vi on each bar
// ============================================================
MUZE.ChordAdvance = {
  _active: false,
  _loop: null,
  _chordIdx: 0,

  init() {
    const btn = document.getElementById('auto-chord-btn');
    if (!btn) return;

    btn.addEventListener('click', () => {
      this._active = !this._active;
      btn.classList.toggle('active', this._active);
      document.getElementById('auto-chord-val').textContent = this._active ? 'AUTO' : 'OFF';

      if (this._active) {
        this._start();
      } else {
        this._stop();
      }
    });
  },

  _start() {
    this._chordIdx = MUZE.State.chordIndex;
    // Advance chord every bar (4 beats)
    this._loop = new Tone.Loop((time) => {
      this._chordIdx = (this._chordIdx + 1) % 6;
      // Schedule chord change
      Tone.Draw.schedule(() => {
        MUZE.State.chordIndex = this._chordIdx;
        document.querySelectorAll('.chord-btn').forEach((b, i) => {
          b.classList.toggle('active', i === this._chordIdx);
        });
        // Show next chord indicator
        this._updateNextIndicator();
        // Force pad retrigger
        MUZE.Loop._currentPadKey = null;
      }, time);
    }, '1m');
    this._loop.start(0);
    this._updateNextIndicator();
  },

  _stop() {
    if (this._loop) {
      this._loop.stop();
      this._loop.dispose();
      this._loop = null;
    }
    // Remove next indicators
    document.querySelectorAll('.chord-btn.next-chord').forEach(b => b.classList.remove('next-chord'));
  },

  _updateNextIndicator() {
    document.querySelectorAll('.chord-btn.next-chord').forEach(b => b.classList.remove('next-chord'));
    if (!this._active) return;
    const nextIdx = (this._chordIdx + 1) % 6;
    const nextBtn = document.querySelector(`.chord-btn[data-chord="${nextIdx}"]`);
    if (nextBtn) nextBtn.classList.add('next-chord');
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
    if (!padNode) return;

    const now = Tone.now();
    const currentGain = padNode.gain.gain.value;

    // Quick duck down, slow release (classic sidechain curve)
    padNode.gain.gain.cancelScheduledValues(now);
    padNode.gain.gain.setValueAtTime(currentGain, now);
    padNode.gain.gain.linearRampToValueAtTime(currentGain * 0.3, now + 0.01); // fast attack
    padNode.gain.gain.linearRampToValueAtTime(currentGain, now + 0.15); // release
  }
};
