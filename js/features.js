/* ============================================================
   MUZE — Sprint 3 Features
   Loop Recorder, Scene Manager, Gyroscope, Preset Crossfade
   ============================================================ */

// ============================================================
// LOOP RECORDER with Overdub
// Records using MediaRecorder + Tone.context destination stream
// ============================================================
MUZE.LoopRecorder = {
  _state: 'empty', // empty | recording | playing | overdubbing
  _layers: [],      // array of { player, buffer }
  _loopDuration: 0, // ms, set on first recording
  _startTime: 0,
  _progressRAF: null,
  _mediaRecorder: null,
  _chunks: [],
  _audioDest: null,
  _barCount: 4,

  init() {
    const recBtn = document.getElementById('loop-rec-btn');
    const overdubBtn = document.getElementById('loop-overdub-btn');
    const undoBtn = document.getElementById('loop-undo-btn');
    const clearBtn = document.getElementById('loop-clear-btn');

    recBtn.addEventListener('click', () => this._onRecBtn());
    overdubBtn.addEventListener('click', () => this._onOverdubBtn());
    undoBtn.addEventListener('click', () => this._undoLayer());
    clearBtn.addEventListener('click', () => this._clearAll());

    // Also wire panel buttons (in synth panel Performance tab)
    const pRec = document.getElementById('loop-rec-panel-btn');
    const pOvr = document.getElementById('loop-overdub-panel-btn');
    const pUndo = document.getElementById('loop-undo-panel-btn');
    const pClear = document.getElementById('loop-clear-panel-btn');
    if (pRec) pRec.addEventListener('click', () => this._onRecBtn());
    if (pOvr) pOvr.addEventListener('click', () => this._onOverdubBtn());
    if (pUndo) pUndo.addEventListener('click', () => this._undoLayer());
    if (pClear) pClear.addEventListener('click', () => this._clearAll());

    // Create a MediaStream destination from the audio context
    this._audioDest = Tone.context.createMediaStreamDestination();
    Tone.getDestination().connect(this._audioDest);
  },

  _getLoopMs() {
    // 4 bars at current BPM, 4/4 time
    const bpm = Tone.Transport.bpm.value;
    const beatsPerBar = 4;
    const msPerBeat = 60000 / bpm;
    return msPerBeat * beatsPerBar * this._barCount;
  },

  _getMimeType() {
    if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) return 'audio/webm;codecs=opus';
    if (MediaRecorder.isTypeSupported('audio/mp4')) return 'audio/mp4';
    return 'audio/webm';
  },

  _onRecBtn() {
    switch (this._state) {
      case 'empty':
        this._startRecording();
        break;
      case 'recording':
        this._stopRecording();
        break;
      case 'playing':
        this._startOverdub();
        break;
      case 'overdubbing':
        this._stopOverdub();
        break;
    }
  },

  _onOverdubBtn() {
    if (this._state === 'playing') {
      this._startOverdub();
    } else if (this._state === 'overdubbing') {
      this._stopOverdub();
    }
  },

  _startRecording() {
    this._state = 'recording';
    this._loopDuration = this._getLoopMs();
    this._startTime = performance.now();
    this._updateUI();
    this._startMediaRecorder();
    this._startProgress();

    // Auto-stop after loop duration
    this._autoStopTimer = setTimeout(() => {
      if (this._state === 'recording') {
        this._stopRecording();
      }
    }, this._loopDuration);
  },

  _startMediaRecorder() {
    this._chunks = [];
    const mime = this._getMimeType();
    this._mediaRecorder = new MediaRecorder(this._audioDest.stream, { mimeType: mime });
    this._mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) this._chunks.push(e.data);
    };
    this._mediaRecorder.start(50); // small timeslice for responsiveness
  },

  async _stopRecording() {
    clearTimeout(this._autoStopTimer);

    const blob = await this._stopMediaRecorder();
    if (!blob) { this._state = 'empty'; this._updateUI(); return; }

    try {
      const arrayBuf = await blob.arrayBuffer();
      const audioBuf = await Tone.context.decodeAudioData(arrayBuf);
      const toneBuf = new Tone.ToneAudioBuffer().fromArray(audioBuf.getChannelData(0));

      // Create looping player
      const player = new Tone.Player({
        url: toneBuf,
        loop: true,
      }).toDestination();
      player.start();

      this._layers.push({ player, buffer: toneBuf });
      this._state = 'playing';
      this._startTime = performance.now();
      this._startProgress();
    } catch (e) {
      console.warn('Loop recording failed to decode:', e);
      this._state = 'empty';
    }

    this._updateUI();
  },

  _stopMediaRecorder() {
    return new Promise((resolve) => {
      if (!this._mediaRecorder || this._mediaRecorder.state !== 'recording') {
        resolve(null);
        return;
      }
      this._mediaRecorder.onstop = () => {
        const mime = this._mediaRecorder.mimeType;
        const blob = new Blob(this._chunks, { type: mime });
        resolve(blob);
      };
      this._mediaRecorder.stop();
    });
  },

  _startOverdub() {
    this._state = 'overdubbing';
    this._updateUI();
    this._startMediaRecorder();

    // Auto-stop after one loop cycle
    this._autoStopTimer = setTimeout(() => {
      if (this._state === 'overdubbing') {
        this._stopOverdub();
      }
    }, this._loopDuration);
  },

  async _stopOverdub() {
    clearTimeout(this._autoStopTimer);

    const blob = await this._stopMediaRecorder();
    if (!blob) { this._state = 'playing'; this._updateUI(); return; }

    try {
      const arrayBuf = await blob.arrayBuffer();
      const audioBuf = await Tone.context.decodeAudioData(arrayBuf);
      const toneBuf = new Tone.ToneAudioBuffer().fromArray(audioBuf.getChannelData(0));

      const player = new Tone.Player({
        url: toneBuf,
        loop: true,
      }).toDestination();
      player.start();

      this._layers.push({ player, buffer: toneBuf });
    } catch (e) {
      console.warn('Overdub decode failed:', e);
    }

    this._state = 'playing';
    this._updateUI();
  },

  _undoLayer() {
    if (this._layers.length <= 0) return;
    const last = this._layers.pop();
    last.player.stop();
    last.player.dispose();

    if (this._layers.length === 0) {
      this._state = 'empty';
      this._stopProgress();
    }
    this._updateUI();
  },

  _clearAll() {
    for (const layer of this._layers) {
      layer.player.stop();
      layer.player.dispose();
    }
    this._layers = [];
    this._state = 'empty';
    this._stopProgress();
    this._updateUI();
  },

  _startProgress() {
    this._stopProgress();
    const fill = document.getElementById('loop-progress-fill');
    const head = document.getElementById('loop-progress-head');
    const tick = () => {
      if (this._state === 'empty') return;
      const elapsed = (performance.now() - this._startTime) % this._loopDuration;
      const pct = (elapsed / this._loopDuration) * 100;
      fill.style.width = pct + '%';
      head.style.left = pct + '%';
      this._progressRAF = requestAnimationFrame(tick);
    };
    this._progressRAF = requestAnimationFrame(tick);
  },

  _stopProgress() {
    if (this._progressRAF) {
      cancelAnimationFrame(this._progressRAF);
      this._progressRAF = null;
    }
    const fill = document.getElementById('loop-progress-fill');
    const head = document.getElementById('loop-progress-head');
    if (fill) fill.style.width = '0%';
    if (head) head.style.left = '0%';
  },

  _updateUI() {
    const recBtn = document.getElementById('loop-rec-btn');
    const overdubBtn = document.getElementById('loop-overdub-btn');
    const undoBtn = document.getElementById('loop-undo-btn');
    const clearBtn = document.getElementById('loop-clear-btn');
    const bar = document.getElementById('loop-bar');

    // Remove all state classes
    bar.classList.remove('state-recording', 'state-playing', 'state-overdubbing');

    switch (this._state) {
      case 'empty':
        recBtn.innerHTML = '&#9673;'; // circle
        recBtn.title = 'Start Loop';
        overdubBtn.disabled = true;
        undoBtn.disabled = true;
        clearBtn.disabled = true;
        break;
      case 'recording':
        bar.classList.add('state-recording');
        recBtn.innerHTML = '&#9632;'; // stop square
        recBtn.title = 'Stop Recording';
        overdubBtn.disabled = true;
        undoBtn.disabled = true;
        clearBtn.disabled = true;
        break;
      case 'playing':
        bar.classList.add('state-playing');
        recBtn.innerHTML = '&#9673;'; // circle for overdub start
        recBtn.title = 'Overdub';
        overdubBtn.disabled = false;
        undoBtn.disabled = this._layers.length <= 1;
        clearBtn.disabled = false;
        break;
      case 'overdubbing':
        bar.classList.add('state-overdubbing');
        recBtn.innerHTML = '&#9632;';
        recBtn.title = 'Stop Overdub';
        overdubBtn.disabled = false;
        clearBtn.disabled = false;
        undoBtn.disabled = true;
        break;
    }
    // Sync panel buttons
    const pRec = document.getElementById('loop-rec-panel-btn');
    const pOvr = document.getElementById('loop-overdub-panel-btn');
    const pUndo = document.getElementById('loop-undo-panel-btn');
    const pClear = document.getElementById('loop-clear-panel-btn');
    if (pRec) {
      pRec.disabled = false;
      pRec.textContent = this._state === 'recording' || this._state === 'overdubbing' ? '■ STOP' : '● REC';
      pRec.style.color = this._state === 'recording' ? '#ef4444' : this._state === 'overdubbing' ? '#f59e0b' : '';
    }
    if (pOvr) pOvr.disabled = overdubBtn.disabled;
    if (pUndo) pUndo.disabled = undoBtn.disabled;
    if (pClear) pClear.disabled = clearBtn.disabled;
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
      MUZE.Audio._padDetune2.set({ oscillator: { type: scene.padOsc } });
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
