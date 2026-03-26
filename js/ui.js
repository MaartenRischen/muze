/* ============================================================
   MUZE — UI (Touch, Synth Menu, Tutorial, Recorder, Samples)
   ============================================================ */

// ---- Instrument Toggle Buttons ----
MUZE.InstrumentToggles = {
  _padActive: false,
  _arpActive: false,
  _melodyActive: false,
  _beatActive: false,
  _binActive: false,
  // Map each button to its mixer channel(s)
  _channelMap: {
    pad: 'pad',
    arp: 'arp',
    melody: 'melody',
    beat: 'kick',
    bin: 'binaural',
  },

  // Volume gesture state
  _vol: { active: false, ch: null, inst: null, startY: 0, startDb: 0, btn: null },

  init() {
    const toggles = {
      'toggle-pad': () => this._togglePad(),
      'toggle-arp': () => this._toggleArp(),
      'toggle-melody': () => this._toggleMelody(),
      'toggle-beat': () => this._toggleBeat(),
      'toggle-bin': () => this._toggleBin(),
    };

    Object.keys(toggles).forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      el.style.touchAction = 'none'; // prevent browser gestures, enable pointer events

      let timer = null;
      let held = false;
      let startY = 0;
      let pointerId = null;

      el.addEventListener('pointerdown', (e) => {
        held = false;
        startY = e.clientY;
        pointerId = e.pointerId;
        el.setPointerCapture(e.pointerId); // capture so move/up fire even if finger drifts off
        timer = setTimeout(() => {
          held = true;
          this._volStart(el, startY);
        }, 350);
      });

      el.addEventListener('pointermove', (e) => {
        if (held && this._vol.active) {
          this._volMove(e.clientY);
        } else if (timer && Math.abs(e.clientY - startY) > 10) {
          clearTimeout(timer); timer = null;
        }
      });

      el.addEventListener('pointerup', (e) => {
        if (timer) { clearTimeout(timer); timer = null; }
        if (held) {
          this._volEnd();
          held = false;
          return;
        }
        held = false;
        toggles[id]();
      });

      el.addEventListener('pointercancel', () => {
        if (timer) { clearTimeout(timer); timer = null; }
        if (held) this._volEnd();
        held = false;
      });
    });
  },

  _volStart(btn, y) {
    const inst = btn.dataset.inst;
    const ch = this._channelMap[inst];
    if (!ch || !MUZE.Mixer.channels[ch]) return;

    const popup = document.getElementById('vol-slider-popup');
    const fill = document.getElementById('vol-slider-fill');
    const dbLabel = document.getElementById('vol-slider-db');

    const db = MUZE.Mixer.channels[ch].volume;
    this._vol = { active: true, ch, inst, startY: y, startDb: db, btn };

    // Position to the left of the button
    const rect = btn.getBoundingClientRect();
    popup.style.top = (rect.top + rect.height / 2) + 'px';
    popup.style.right = (window.innerWidth - rect.left + 8) + 'px';
    popup.style.transform = 'translateY(-50%)';

    dbLabel.textContent = Math.round(db) + ' dB';
    const pct = ((db + 30) / 36) * 100; // -30..+6 range
    fill.style.height = Math.max(0, Math.min(100, pct)) + '%';
    popup.classList.add('visible');
  },

  _volMove(y) {
    const v = this._vol;
    if (!v.active) return;

    // Drag up = louder, 200px travel = full range (-30 to +6 = 36dB)
    const delta = (v.startY - y) * (36 / 200);
    const db = Math.max(-30, Math.min(6, v.startDb + delta));

    MUZE.Mixer.setChannelVolume(v.ch, db);
    if (v.inst === 'beat') {
      MUZE.Mixer.setChannelVolume('snare', db - 4);
      MUZE.Mixer.setChannelVolume('hat', db - 10);
    }

    const fill = document.getElementById('vol-slider-fill');
    const dbLabel = document.getElementById('vol-slider-db');
    dbLabel.textContent = Math.round(db) + ' dB';
    const pct = ((db + 30) / 36) * 100;
    fill.style.height = Math.max(0, Math.min(100, pct)) + '%';
  },

  _volEnd() {
    this._vol.active = false;
    document.getElementById('vol-slider-popup').classList.remove('visible');
  },

  _togglePad() {
    this._padActive = !this._padActive;
    document.getElementById('toggle-pad').classList.toggle('active', this._padActive);
    MUZE.Mixer.toggleMute('pad');
    if (this._padActive && MUZE.Audio.triggerPad) {
      const root = MUZE.Music.getEffectiveRoot ? MUZE.Music.getEffectiveRoot() : 60;
      const scale = MUZE.State.currentScale || MUZE.Config.SCALE_DORIAN;
      const degree = MUZE.Config.CHORD_DEGREES[MUZE.State.chordIndex || 0];
      const notes = MUZE.Music.getPadVoicing(root, scale, degree);
      MUZE.Audio.triggerPad(notes);
    }
  },

  _toggleArp() {
    this._arpActive = !this._arpActive;
    document.getElementById('toggle-arp').classList.toggle('active', this._arpActive);
    MUZE.Mixer.toggleMute('arp');
    if (this._arpActive) {
      if (!MUZE.Audio._arpNotes || MUZE.Audio._arpNotes.length === 0) {
        const root = MUZE.Music.getEffectiveRoot ? MUZE.Music.getEffectiveRoot() : 60;
        MUZE.Audio.updateArpNotes(MUZE.State.currentScale || MUZE.Config.SCALE_DORIAN, root);
      }
      if (!MUZE.Audio._arpSeq) MUZE.Audio.startArpeggio();
    } else {
      MUZE.Audio.stopArpeggio();
    }
  },

  _toggleMelody() {
    this._melodyActive = !this._melodyActive;
    document.getElementById('toggle-melody').classList.toggle('active', this._melodyActive);
    MUZE.Mixer.toggleMute('melody');
  },

  _toggleBeat() {
    const active = MUZE.AutoRhythm.toggle();
    this._beatActive = active;
    MUZE.State.autoRhythm = active;
    document.getElementById('toggle-beat').classList.toggle('active', active);
    document.getElementById('rhythm-indicator').classList.toggle('visible', active);
  },

  _toggleBin() {
    const on = MUZE.Audio.toggleBinaural();
    this._binActive = on;
    document.getElementById('toggle-bin').classList.toggle('active', on);
  }
};

// Keep DrumToggle as alias for backward compat
MUZE.DrumToggle = { init() { /* handled by InstrumentToggles */ } };

// ---- Riser Button (replaces hold+swipe gesture) ----
MUZE.RiserBtn = {
  _active: false,
  init() {
    const btn = document.getElementById('riser-btn');
    btn.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this._active = true;
      MUZE.Audio.startRiser();
      MUZE.State.riserActive = true;
      btn.classList.add('active-feature');
      document.getElementById('riser-overlay')?.classList.add('active');
    });
    btn.addEventListener('touchend', (e) => {
      e.preventDefault();
      if (!this._active) return;
      this._active = false;
      MUZE.Audio.dropRiser();
      MUZE.State.riserActive = false;
      btn.classList.remove('active-feature');
      document.getElementById('riser-overlay')?.classList.remove('active');
      if (MUZE.Visualizer.triggerExplosion) {
        MUZE.Visualizer.triggerExplosion(window.innerWidth / 2, window.innerHeight * 0.4, 120);
      }
    });
    // Also support mouse for desktop
    btn.addEventListener('mousedown', (e) => {
      this._active = true;
      MUZE.Audio.startRiser();
      MUZE.State.riserActive = true;
      btn.classList.add('active-feature');
    });
    btn.addEventListener('mouseup', (e) => {
      if (!this._active) return;
      this._active = false;
      MUZE.Audio.dropRiser();
      MUZE.State.riserActive = false;
      btn.classList.remove('active-feature');
    });
  }
};

// ---- Chord Bar (extracted from old Touch module) ----
MUZE.ChordBar = {
  init() {
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
    document.querySelector('.chord-btn[data-chord="0"]').classList.add('active');
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

    // Arp pattern cycle button
    const arpPatBtn = document.getElementById('arp-pattern');
    if (arpPatBtn) {
      arpPatBtn.addEventListener('click', function() {
        MUZE.State.arpPatternIdx = (MUZE.State.arpPatternIdx + 1) % MUZE.Config.ARP_PATTERNS.length;
        this.textContent = MUZE.Config.ARP_PATTERNS[MUZE.State.arpPatternIdx];
      });
    }

    // Melody synth
    document.getElementById('mel-porta').addEventListener('click', function() {
      MUZE.State.portamentoMode = !MUZE.State.portamentoMode;
      this.textContent = MUZE.State.portamentoMode ? 'ON' : 'OFF';
      MUZE.Audio.setPortamento(MUZE.State.portamentoMode);
    });
    // Vibrato slider
    this._bind('mel-vib', (v) => MUZE.Audio.setVibratoAmount(+v));
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

    // Pad synth (single layer now — _padDetune2 removed for performance)
    this._bind('pad-osc', (v) => {
      MUZE.Audio.padSynth.set({ oscillator: { type: v } });
    }, true);
    this._bind('pad-harm', (v) => {
      MUZE.Audio.padSynth.set({ harmonicity: +v });
    });
    this._bind('pad-mod', (v) => {
      MUZE.Audio.padSynth.set({ modulationIndex: +v });
    });
    this._bind('pad-atk', (v) => {
      MUZE.Audio.padSynth.set({ envelope: { attack: +v } });
    });
    this._bind('pad-rel', (v) => {
      MUZE.Audio.padSynth.set({ envelope: { release: +v } });
    });
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
// PERFORM TAB — Wires buttons inside the synth panel Perform tab
// ============================================================
MUZE.PerformTab = {
  _tapTimes: [],

  init() {
    // ---- Preset cycle ----
    const presetBtn = document.getElementById('perf-preset-btn');
    if (presetBtn) {
      presetBtn.addEventListener('click', () => {
        const idx = (MUZE.State.presetIdx + 1) % MUZE.Config.PRESETS.length;
        MUZE.Audio.applyPreset(idx);
        presetBtn.textContent = MUZE.Config.PRESETS[idx].name;
        // Sync other displays
        this._syncDisplays();
      });
    }

    // ---- BPM slider ----
    const perfBpm = document.getElementById('perf-bpm');
    if (perfBpm) {
      const bpmVal = perfBpm.parentElement.querySelector('.val');
      perfBpm.addEventListener('input', () => {
        const val = +perfBpm.value;
        MUZE.Audio.setBPM(val);
        if (bpmVal) bpmVal.textContent = val;
        // Sync BPM popup slider
        const bpmSlider = document.getElementById('bpm-slider');
        if (bpmSlider) bpmSlider.value = val;
        const bpmSliderVal = document.getElementById('bpm-slider-val');
        if (bpmSliderVal) bpmSliderVal.textContent = val;
        const bpmValEl = document.getElementById('bpm-val');
        if (bpmValEl) bpmValEl.textContent = val;
      });
    }

    // ---- Swing slider ----
    const perfSwing = document.getElementById('perf-swing');
    if (perfSwing) {
      const swingVal = perfSwing.parentElement.querySelector('.val');
      perfSwing.addEventListener('input', () => {
        const val = +perfSwing.value;
        MUZE.Audio.setSwing(val);
        if (swingVal) swingVal.textContent = val + '%';
        // Sync BPM popup swing slider
        const swingSlider = document.getElementById('swing-slider');
        if (swingSlider) swingSlider.value = val;
        const swingValEl = document.getElementById('swing-val');
        if (swingValEl) swingValEl.textContent = val + '%';
      });
    }

    // ---- Tap tempo (unique id: perf-tap-tempo) ----
    const tapBtn = document.getElementById('perf-tap-tempo');
    if (tapBtn) {
      tapBtn.addEventListener('click', () => {
        const now = performance.now();
        this._tapTimes.push(now);
        if (this._tapTimes.length > 5) this._tapTimes.shift();
        if (this._tapTimes.length >= 2) {
          const last = this._tapTimes[this._tapTimes.length - 1];
          const prev = this._tapTimes[this._tapTimes.length - 2];
          if (last - prev > 2000) { this._tapTimes = [now]; return; }
        }
        if (this._tapTimes.length >= 2) {
          let total = 0;
          for (let i = 1; i < this._tapTimes.length; i++) {
            total += this._tapTimes[i] - this._tapTimes[i - 1];
          }
          const avgMs = total / (this._tapTimes.length - 1);
          const bpm = Math.round(60000 / avgMs);
          const clamped = Math.max(40, Math.min(200, bpm));
          MUZE.Audio.setBPM(clamped);
          this._syncDisplays();
        }
      });
    }

    // ---- Key cycle ----
    const keyBtn = document.getElementById('perf-key-btn');
    if (keyBtn) {
      keyBtn.addEventListener('click', () => {
        MUZE.State.rootOffset = (MUZE.State.rootOffset + 1) % 12;
        const name = MUZE.Config.ROOT_NAMES[MUZE.State.rootOffset];
        keyBtn.textContent = name;
        // Sync hidden key display
        const keyVal = document.getElementById('key-val');
        if (keyVal) keyVal.textContent = name;
        // Force pad retrigger
        MUZE.Loop._currentPadKey = null;
      });
    }

    // ---- Scale cycle ----
    const scaleBtn = document.getElementById('perf-scale-btn');
    if (scaleBtn) {
      const scaleNames = ['modal', ...Object.keys(MUZE.Music.EXTRA_SCALES)];
      let scaleIdx = 0;
      scaleBtn.addEventListener('click', () => {
        scaleIdx = (scaleIdx + 1) % scaleNames.length;
        const name = scaleNames[scaleIdx];
        if (name === 'modal') {
          MUZE.State.extraScaleMode = null;
          MUZE.State.modeFrozen = false;
          scaleBtn.textContent = 'Modal (face)';
        } else {
          MUZE.State.extraScaleMode = name;
          MUZE.State.modeFrozen = true;
          MUZE.State.currentScale = MUZE.Music.EXTRA_SCALES[name];
          scaleBtn.textContent = name;
        }
        const scaleVal = document.getElementById('scale-val');
        if (scaleVal) scaleVal.textContent = name === 'modal' ? 'modal' : name;
        // Force pad retrigger
        MUZE.Loop._currentPadKey = null;
      });
    }

    // ---- Chord auto-advance toggle ----
    const chordsBtn = document.getElementById('perf-chords-btn');
    if (chordsBtn) {
      chordsBtn.addEventListener('click', () => {
        if (!MUZE.ChordAdvance) return;
        MUZE.ChordAdvance._active = !MUZE.ChordAdvance._active;
        if (MUZE.ChordAdvance._active) {
          MUZE.ChordAdvance._start();
          chordsBtn.textContent = 'AUTO';
        } else {
          MUZE.ChordAdvance._stop();
          chordsBtn.textContent = 'OFF';
        }
        // Sync hidden auto-chord display
        const acBtn = document.getElementById('auto-chord-btn');
        if (acBtn) acBtn.classList.toggle('active', MUZE.ChordAdvance._active);
        const acVal = document.getElementById('auto-chord-val');
        if (acVal) acVal.textContent = MUZE.ChordAdvance._active ? 'AUTO' : 'OFF';
      });
    }

    // ---- Scene slots in Perform tab ----
    document.querySelectorAll('.scene-slot-panel').forEach(btn => {
      btn.addEventListener('click', () => {
        const idx = parseInt(btn.dataset.scene);
        if (MUZE.SceneManager) {
          if (MUZE.SceneManager._saveMode) {
            MUZE.SceneManager._saveScene(idx);
            MUZE.SceneManager._saveMode = false;
          } else {
            MUZE.SceneManager._recallScene(idx);
          }
          this._syncDisplays();
        }
      });
    });

    const sceneSaveBtn = document.getElementById('scene-save-panel-btn');
    if (sceneSaveBtn) {
      sceneSaveBtn.addEventListener('click', () => {
        if (!MUZE.SceneManager) return;
        MUZE.SceneManager._saveMode = !MUZE.SceneManager._saveMode;
        sceneSaveBtn.classList.toggle('active', MUZE.SceneManager._saveMode);
        document.querySelectorAll('.scene-slot-panel').forEach(s => {
          s.classList.toggle('save-mode', MUZE.SceneManager._saveMode);
        });
      });
    }

    // ---- Pad sample cycle in Perform tab ----
    const padSampleBtn = document.getElementById('pad-sample-panel-btn');
    if (padSampleBtn) {
      padSampleBtn.addEventListener('click', () => {
        if (MUZE.SampleUI) MUZE.SampleUI._cyclePad();
        // Sync label
        const samples = MUZE.SampleLib ? MUZE.SampleLib.getAllSamples() : [];
        const idx = MUZE.SampleUI ? MUZE.SampleUI._padIdx : -1;
        padSampleBtn.textContent = idx === -1 ? 'FM Synth' : samples[idx]?.name || 'FM Synth';
      });
    }

    // ---- Lead sample cycle in Perform tab ----
    const leadSampleBtn = document.getElementById('lead-sample-panel-btn');
    if (leadSampleBtn) {
      leadSampleBtn.addEventListener('click', () => {
        if (MUZE.SampleUI) MUZE.SampleUI._cycleLead();
        const samples = MUZE.SampleLib ? MUZE.SampleLib.getAllSamples() : [];
        const idx = MUZE.SampleUI ? MUZE.SampleUI._leadIdx : -1;
        leadSampleBtn.textContent = idx === -1 ? 'Synth' : samples[idx]?.name || 'Synth';
      });
    }
  },

  // Sync BPM/key/swing displays across perform tab and popups
  _syncDisplays() {
    const bpm = MUZE.State.bpm;
    const key = MUZE.Config.ROOT_NAMES[MUZE.State.rootOffset];
    const swing = MUZE.State.swing;

    // BPM
    const perfBpm = document.getElementById('perf-bpm');
    if (perfBpm) { perfBpm.value = bpm; const v = perfBpm.parentElement.querySelector('.val'); if (v) v.textContent = bpm; }
    const bpmSlider = document.getElementById('bpm-slider');
    if (bpmSlider) bpmSlider.value = bpm;
    const bpmSliderVal = document.getElementById('bpm-slider-val');
    if (bpmSliderVal) bpmSliderVal.textContent = bpm;
    const bpmVal = document.getElementById('bpm-val');
    if (bpmVal) bpmVal.textContent = bpm;

    // Key
    const perfKey = document.getElementById('perf-key-btn');
    if (perfKey) perfKey.textContent = key;
    const keyVal = document.getElementById('key-val');
    if (keyVal) keyVal.textContent = key;

    // Swing
    const perfSwing = document.getElementById('perf-swing');
    if (perfSwing) { perfSwing.value = swing; const v = perfSwing.parentElement.querySelector('.val'); if (v) v.textContent = swing + '%'; }
    const swingSlider = document.getElementById('swing-slider');
    if (swingSlider) swingSlider.value = swing;
    const swingVal = document.getElementById('swing-val');
    if (swingVal) swingVal.textContent = swing + '%';
  }
};

// ============================================================
// PERFORMANCE BAR — Presets, BPM, Key, Scale
// ============================================================
MUZE.PerfBar = {
  _tapTimes: [],

  init() {
    // Preset cycling
    document.getElementById('preset-btn').addEventListener('click', () => {
      const idx = (MUZE.State.presetIdx + 1) % MUZE.Config.PRESETS.length;
      MUZE.Audio.applyPreset(idx);
      document.getElementById('preset-name').textContent = MUZE.Config.PRESETS[idx].name;
      // Update BPM display
      document.getElementById('bpm-val').textContent = MUZE.State.bpm;
      document.getElementById('bpm-slider').value = MUZE.State.bpm;
      document.getElementById('bpm-slider-val').textContent = MUZE.State.bpm;
      // Update key display
      document.getElementById('key-val').textContent = MUZE.Config.ROOT_NAMES[MUZE.State.rootOffset];
      // Update swing display
      document.getElementById('swing-slider').value = MUZE.State.swing;
      document.getElementById('swing-val').textContent = MUZE.State.swing + '%';
    });

    // BPM popup
    document.getElementById('bpm-btn').addEventListener('click', () => {
      this._togglePopup('bpm-popup');
    });

    // BPM slider
    const bpmSlider = document.getElementById('bpm-slider');
    bpmSlider.addEventListener('input', () => {
      const val = +bpmSlider.value;
      MUZE.Audio.setBPM(val);
      document.getElementById('bpm-slider-val').textContent = val;
      document.getElementById('bpm-val').textContent = val;
    });

    // Tap tempo
    document.getElementById('tap-tempo-btn').addEventListener('click', () => {
      const now = performance.now();
      this._tapTimes.push(now);
      // Keep last 5 taps
      if (this._tapTimes.length > 5) this._tapTimes.shift();
      // Reset if gap > 2 seconds
      if (this._tapTimes.length >= 2) {
        const last = this._tapTimes[this._tapTimes.length - 1];
        const prev = this._tapTimes[this._tapTimes.length - 2];
        if (last - prev > 2000) {
          this._tapTimes = [now];
          return;
        }
      }
      if (this._tapTimes.length >= 2) {
        let total = 0;
        for (let i = 1; i < this._tapTimes.length; i++) {
          total += this._tapTimes[i] - this._tapTimes[i - 1];
        }
        const avgMs = total / (this._tapTimes.length - 1);
        const bpm = Math.round(60000 / avgMs);
        const clamped = Math.max(40, Math.min(200, bpm));
        MUZE.Audio.setBPM(clamped);
        document.getElementById('bpm-slider').value = clamped;
        document.getElementById('bpm-slider-val').textContent = clamped;
        document.getElementById('bpm-val').textContent = clamped;
      }
    });

    // Swing slider
    const swingSlider = document.getElementById('swing-slider');
    swingSlider.addEventListener('input', () => {
      const val = +swingSlider.value;
      MUZE.Audio.setSwing(val);
      document.getElementById('swing-val').textContent = val + '%';
    });

    // Key popup
    document.getElementById('key-btn').addEventListener('click', () => {
      this._togglePopup('key-popup');
    });
    this._buildKeyGrid();

    // Scale popup
    document.getElementById('scale-btn').addEventListener('click', () => {
      this._togglePopup('scale-popup');
    });
    this._buildScaleGrid();

    // Close buttons for all popups
    document.querySelectorAll('.popup-close').forEach(btn => {
      btn.addEventListener('click', () => {
        const popupId = btn.dataset.close;
        document.getElementById(popupId).classList.remove('open');
      });
    });

    // Close popups on outside tap/click
    const closePopupsOutside = (e) => {
      document.querySelectorAll('.popup-panel.open').forEach(popup => {
        if (!popup.contains(e.target) && !e.target.closest('#perf-bar')) {
          popup.classList.remove('open');
        }
      });
    };
    document.addEventListener('touchstart', closePopupsOutside);
    document.addEventListener('mousedown', closePopupsOutside);
  },

  _togglePopup(id) {
    // Close all popups first
    document.querySelectorAll('.popup-panel').forEach(p => {
      if (p.id !== id) p.classList.remove('open');
    });
    document.getElementById(id).classList.toggle('open');
  },

  _buildKeyGrid() {
    const grid = document.getElementById('key-grid');
    const names = MUZE.Config.ROOT_NAMES;
    names.forEach((name, i) => {
      const btn = document.createElement('button');
      btn.className = 'key-option' + (i === MUZE.State.rootOffset ? ' active' : '');
      btn.textContent = name;
      btn.addEventListener('click', () => {
        MUZE.State.rootOffset = i;
        document.getElementById('key-val').textContent = name;
        grid.querySelectorAll('.key-option').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        // Force pad retrigger
        MUZE.Loop._currentPadKey = null;
      });
      grid.appendChild(btn);
    });
  },

  _buildScaleGrid() {
    const grid = document.getElementById('scale-grid');
    // "Modal" = face-controlled (default)
    const modalBtn = document.createElement('button');
    modalBtn.className = 'scale-option active';
    modalBtn.textContent = 'MODAL (face)';
    modalBtn.addEventListener('click', () => {
      MUZE.State.extraScaleMode = null;
      MUZE.State.modeFrozen = false;
      document.getElementById('scale-val').textContent = 'modal';
      grid.querySelectorAll('.scale-option').forEach(b => b.classList.remove('active'));
      modalBtn.classList.add('active');
    });
    grid.appendChild(modalBtn);

    // Extra scales
    const extras = Object.keys(MUZE.Music.EXTRA_SCALES);
    extras.forEach(name => {
      const btn = document.createElement('button');
      btn.className = 'scale-option';
      btn.textContent = name.toUpperCase();
      btn.addEventListener('click', () => {
        MUZE.State.extraScaleMode = name;
        MUZE.State.modeFrozen = true; // freeze mode when using extra scale
        MUZE.State.currentScale = MUZE.Music.EXTRA_SCALES[name];
        document.getElementById('scale-val').textContent = name;
        grid.querySelectorAll('.scale-option').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        // Force pad retrigger
        MUZE.Loop._currentPadKey = null;
      });
      grid.appendChild(btn);
    });
  }
};

// ============================================================
// MIXER UI — Premium mobile DAW mixer with progressive disclosure
// Strip view: custom fader + segmented meter + pan + M/S
// Detail panel: EQ + sends + pan (slide-up sheet)
// ============================================================
MUZE.MixerUI = {
  _meterRAF: null,
  _metersRunning: false,
  _detailOpen: false,
  _detailCh: null,
  _peaks: {},           // peak hold values per channel
  _peakTimers: {},      // peak decay timers per channel

  init() {
    const panel = document.getElementById('mixer-panel');
    const strips = document.getElementById('mixer-strips');
    const detail = document.getElementById('mixer-detail');

    // Toggle mixer panel (from synth panel button)
    document.getElementById('mixer-btn').addEventListener('click', () => {
      const opening = !panel.classList.contains('open');
      panel.classList.toggle('open');
      if (opening) this._startMeters();
      else this._stopMeters();
    });

    // Toggle mixer panel (from toolbar MIX button)
    const toolbarMixBtn = document.getElementById('toolbar-mixer-btn');
    if (toolbarMixBtn) {
      toolbarMixBtn.addEventListener('click', () => {
        const opening = !panel.classList.contains('open');
        panel.classList.toggle('open');
        if (opening) this._startMeters();
        else this._stopMeters();
      });
    }

    document.getElementById('mixer-close').addEventListener('click', () => {
      panel.classList.remove('open');
      this._stopMeters();
      this._closeDetail();
    });

    // Close when tapping outside
    document.addEventListener('touchstart', (e) => {
      if (panel.classList.contains('open') && !panel.contains(e.target) && e.target.id !== 'mixer-btn') {
        panel.classList.remove('open');
        this._stopMeters();
        this._closeDetail();
      }
    });

    // Build channel strips
    for (const ch of MUZE.Mixer.CHANNEL_ORDER) {
      strips.appendChild(this._buildStrip(ch));
    }

    // Build master strip (pinned right)
    strips.appendChild(this._buildMasterStrip());
  },

  // ---- Extract RGB from hex/named color for CSS var injection ----
  _colorToRGB(color) {
    const ctx = document.createElement('canvas').getContext('2d');
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, 1, 1);
    const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
    return `${r}, ${g}, ${b}`;
  },

  // ---- Map dB value (-60 to +6) to percentage (0 to 1) ----
  _dbToPercent(db) {
    return Math.max(0, Math.min(1, (db + 60) / 66));
  },

  // ---- Map percentage (0 to 1) to dB value (-60 to +6) ----
  _percentToDb(pct) {
    return Math.max(-60, Math.min(6, pct * 66 - 60));
  },

  // ---- Setup custom fader touch handling ----
  _setupFaderTouch(container, ch, isMaster) {
    const track = container.querySelector('.fader-track');
    const fill = container.querySelector('.fader-fill');
    const thumb = container.querySelector('.fader-thumb');
    const tooltip = container.querySelector('.fader-tooltip');
    const faderVal = container.closest('.strip-fader').querySelector('.fader-val');
    let dragging = false;
    let startY = 0;
    let startPct = 0;

    const data = isMaster ? MUZE.Mixer.master : MUZE.Mixer.channels[ch];
    let currentDb = data.volume;
    let currentPct = this._dbToPercent(currentDb);

    // Set initial position
    fill.style.height = (currentPct * 100) + '%';
    thumb.style.bottom = (currentPct * 100) + '%';

    const updateVisuals = (pct, db) => {
      fill.style.height = (pct * 100) + '%';
      thumb.style.bottom = (pct * 100) + '%';
      const displayVal = db <= -60 ? '-inf' : (db % 1 === 0 ? db.toString() : db.toFixed(1));
      if (faderVal) faderVal.textContent = displayVal;
      if (tooltip) tooltip.textContent = (db <= -60 ? '-inf' : displayVal + ' dB');
    };

    const onTouchStart = (e) => {
      e.preventDefault();
      e.stopPropagation();
      dragging = true;
      const touch = e.changedTouches[0];
      startY = touch.clientY;
      startPct = currentPct;
      thumb.classList.add('touching');
      if (tooltip) tooltip.classList.add('visible');
    };

    const onTouchMove = (e) => {
      if (!dragging) return;
      e.preventDefault();
      e.stopPropagation();
      const touch = e.changedTouches[0];
      const trackRect = track.getBoundingClientRect();
      const trackHeight = trackRect.height;
      const deltaY = startY - touch.clientY;
      const deltaPct = deltaY / trackHeight;
      const newPct = Math.max(0, Math.min(1, startPct + deltaPct));
      const newDb = this._percentToDb(newPct);
      // Snap to 0.5 step
      const snappedDb = Math.round(newDb * 2) / 2;
      currentPct = this._dbToPercent(snappedDb);
      currentDb = snappedDb;

      updateVisuals(currentPct, currentDb);

      if (isMaster) {
        MUZE.Mixer.setMasterVolume(currentDb);
      } else {
        MUZE.Mixer.setChannelVolume(ch, currentDb);
      }
    };

    const onTouchEnd = (e) => {
      if (!dragging) return;
      dragging = false;
      thumb.classList.remove('touching');
      if (tooltip) tooltip.classList.remove('visible');
    };

    // Attach events to thumb for touch-and-drag (not tap-to-position)
    thumb.addEventListener('touchstart', onTouchStart, { passive: false });
    document.addEventListener('touchmove', onTouchMove, { passive: false });
    document.addEventListener('touchend', onTouchEnd, { passive: false });
    document.addEventListener('touchcancel', onTouchEnd, { passive: false });

    // Also support mouse for desktop testing
    thumb.addEventListener('mousedown', (e) => {
      e.preventDefault();
      dragging = true;
      startY = e.clientY;
      startPct = currentPct;
      thumb.classList.add('touching');
      if (tooltip) tooltip.classList.add('visible');
    });
    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      const trackRect = track.getBoundingClientRect();
      const trackHeight = trackRect.height;
      const deltaY = startY - e.clientY;
      const deltaPct = deltaY / trackHeight;
      const newPct = Math.max(0, Math.min(1, startPct + deltaPct));
      const newDb = this._percentToDb(newPct);
      const snappedDb = Math.round(newDb * 2) / 2;
      currentPct = this._dbToPercent(snappedDb);
      currentDb = snappedDb;
      updateVisuals(currentPct, currentDb);
      if (isMaster) {
        MUZE.Mixer.setMasterVolume(currentDb);
      } else {
        MUZE.Mixer.setChannelVolume(ch, currentDb);
      }
    });
    document.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false;
      thumb.classList.remove('touching');
      if (tooltip) tooltip.classList.remove('visible');
    });

    // Store update function for external access (when detail panel changes values)
    container._updateFader = (db) => {
      currentDb = db;
      currentPct = this._dbToPercent(db);
      updateVisuals(currentPct, currentDb);
    };
  },

  // ---- Build a channel strip (progressive: fader + meter + pan + M/S) ----
  _buildStrip(ch) {
    const data = MUZE.Mixer.channels[ch];
    const el = document.createElement('div');
    el.className = 'mixer-strip';
    el.dataset.ch = ch;
    el.style.setProperty('--strip-color', data.color);
    el.style.setProperty('--strip-color-rgb', this._colorToRGB(data.color));

    // Short label (max 4 chars)
    const label = ch.toUpperCase().slice(0, 4);

    // Pan position as percentage for the dot
    const panPct = ((data.pan + 1) / 2) * 100;

    // Calculate initial fader position
    const faderPct = this._dbToPercent(data.volume) * 100;

    el.innerHTML = `
      <div class="strip-label" data-ch="${ch}">${label}</div>
      <div class="strip-fader-area">
        <div class="strip-meter">
          <div class="strip-meter-fill" data-meter="${ch}"></div>
          <div class="strip-meter-peak" data-meter-peak="${ch}"></div>
        </div>
        <div class="strip-fader">
          <div class="fader-container">
            <div class="fader-track">
              <div class="fader-fill" style="height:${faderPct}%"></div>
              <div class="fader-thumb" style="bottom:${faderPct}%"></div>
            </div>
            <div class="fader-tooltip">${data.volume > -60 ? data.volume : '-inf'} dB</div>
          </div>
          <div class="fader-val">${data.volume > -60 ? data.volume : '-inf'}</div>
        </div>
      </div>
      <div class="strip-pan-indicator${ch === 'binaural' ? ' disabled' : ''}" data-ch="${ch}">
        <div class="pan-line">
          <div class="pan-dot" style="left:${panPct}%"></div>
        </div>
      </div>
      <div class="strip-buttons">
        <button class="mute-btn${data.mute ? ' active' : ''}">M</button>
        <button class="solo-btn${data.solo ? ' active' : ''}">S</button>
      </div>
    `;

    // Wire custom fader
    const faderContainer = el.querySelector('.fader-container');
    this._setupFaderTouch(faderContainer, ch, false);

    // Wire mute/solo
    el.querySelector('.mute-btn').addEventListener('click', function() {
      const muted = MUZE.Mixer.toggleMute(ch);
      this.classList.toggle('active', muted);
    });
    el.querySelector('.solo-btn').addEventListener('click', function() {
      const soloed = MUZE.Mixer.toggleSolo(ch);
      this.classList.toggle('active', soloed);
    });

    // Tap label -> open detail
    el.querySelector('.strip-label').addEventListener('click', () => {
      this._openDetail(ch);
    });

    // Tap pan indicator -> open detail (for adjusting pan in detail view)
    const panInd = el.querySelector('.strip-pan-indicator');
    if (ch !== 'binaural') {
      panInd.addEventListener('click', () => {
        this._openDetail(ch);
      });
    }

    return el;
  },

  // ---- Build master strip ----
  _buildMasterStrip() {
    const m = MUZE.Mixer.master;
    const el = document.createElement('div');
    el.className = 'mixer-strip master-strip';
    el.style.setProperty('--strip-color', '#fff');
    el.style.setProperty('--strip-color-rgb', '255, 255, 255');

    const faderPct = this._dbToPercent(m.volume) * 100;

    el.innerHTML = `
      <div class="strip-label">MSTR</div>
      <div class="strip-fader-area">
        <div class="strip-meter">
          <div class="strip-meter-fill" data-meter="master"></div>
          <div class="strip-meter-peak" data-meter-peak="master"></div>
        </div>
        <div class="strip-fader">
          <div class="fader-container">
            <div class="fader-track">
              <div class="fader-fill" style="height:${faderPct}%"></div>
              <div class="fader-thumb" style="bottom:${faderPct}%"></div>
            </div>
            <div class="fader-tooltip">${m.volume} dB</div>
          </div>
          <div class="fader-val">${m.volume}</div>
        </div>
      </div>
      <div class="master-limiter-val">LIM ${m.limiterThreshold}dB</div>
      <div class="strip-buttons"></div>
    `;

    // Wire custom master fader
    const faderContainer = el.querySelector('.fader-container');
    this._setupFaderTouch(faderContainer, 'master', true);

    // Tap label -> open master detail
    el.querySelector('.strip-label').addEventListener('click', () => {
      this._openDetail('master');
    });

    return el;
  },

  // ---- Open detail panel for a channel ----
  _openDetail(ch) {
    const detail = document.getElementById('mixer-detail');
    const strips = document.getElementById('mixer-strips');
    const isMaster = (ch === 'master');
    const data = isMaster ? MUZE.Mixer.master : MUZE.Mixer.channels[ch];
    const color = isMaster ? '#fff' : data.color;
    const label = isMaster ? 'MASTER' : ch.toUpperCase();

    this._detailOpen = true;
    this._detailCh = ch;

    // Build detail content
    let html = `
      <div class="detail-header">
        <div class="detail-ch-name" style="background:${color};color:#000">${label}</div>
        <button class="detail-back">BACK</button>
      </div>
      <div class="detail-content" style="--detail-color:${color}">
    `;

    // EQ section
    const eqLow = isMaster ? data.eqLow : data.eqLow;
    const eqMid = isMaster ? data.eqMid : data.eqMid;
    const eqHigh = isMaster ? data.eqHigh : data.eqHigh;

    html += `
        <div class="detail-eq">
          <div class="detail-section-label">EQUALIZER</div>
          <div class="detail-eq-sliders">
            <div class="detail-eq-band">
              <label>LOW</label>
              <input type="range" data-band="low" min="-12" max="12" step="0.5" value="${eqLow}" orient="vertical">
              <div class="detail-eq-val" data-eq-val="low">${eqLow > 0 ? '+' : ''}${eqLow} dB</div>
            </div>
            <div class="detail-eq-band">
              <label>MID</label>
              <input type="range" data-band="mid" min="-12" max="12" step="0.5" value="${eqMid}" orient="vertical">
              <div class="detail-eq-val" data-eq-val="mid">${eqMid > 0 ? '+' : ''}${eqMid} dB</div>
            </div>
            <div class="detail-eq-band">
              <label>HIGH</label>
              <input type="range" data-band="high" min="-12" max="12" step="0.5" value="${eqHigh}" orient="vertical">
              <div class="detail-eq-val" data-eq-val="high">${eqHigh > 0 ? '+' : ''}${eqHigh} dB</div>
            </div>
          </div>
        </div>
    `;

    // Sends section (channels only — not master)
    if (!isMaster) {
      html += `
        <div class="detail-sends">
          <div class="detail-section-label">SENDS</div>
          <div class="detail-send-row">
            <label>REVERB</label>
            <div class="detail-send-slider">
              <input type="range" data-send="reverb" min="0" max="1" step="0.01" value="${data.reverbSend}">
              <div class="detail-send-val" data-send-val="reverb">${Math.round(data.reverbSend * 100)}%</div>
            </div>
          </div>
          <div class="detail-send-row">
            <label>DELAY</label>
            <div class="detail-send-slider">
              <input type="range" data-send="delay" min="0" max="1" step="0.01" value="${data.delaySend}">
              <div class="detail-send-val" data-send-val="delay">${Math.round(data.delaySend * 100)}%</div>
            </div>
          </div>
        </div>
      `;
    }

    // Limiter threshold (master only)
    if (isMaster) {
      html += `
        <div class="detail-sends">
          <div class="detail-section-label">LIMITER</div>
          <div class="detail-send-row">
            <label>THRESHOLD</label>
            <div class="detail-send-slider">
              <input type="range" data-limiter min="-12" max="0" step="0.5" value="${data.limiterThreshold}">
              <div class="detail-send-val" data-limiter-val>${data.limiterThreshold} dB</div>
            </div>
          </div>
        </div>
      `;
    }

    // Pan section (channels only, not binaural)
    if (!isMaster && ch !== 'binaural') {
      html += `
        <div class="detail-pan">
          <div class="detail-section-label">PAN</div>
          <div class="detail-pan-slider">
            <input type="range" min="-1" max="1" step="0.05" value="${data.pan}">
            <div class="detail-pan-val">${data.pan === 0 ? 'C' : (data.pan < 0 ? Math.round(Math.abs(data.pan) * 100) + 'L' : Math.round(data.pan * 100) + 'R')}</div>
          </div>
        </div>
      `;
    }

    html += '</div>'; // close detail-content

    detail.innerHTML = html;

    // Wire detail back button
    detail.querySelector('.detail-back').addEventListener('click', () => {
      this._closeDetail();
    });

    // Wire EQ sliders
    detail.querySelectorAll('.detail-eq-band input').forEach(inp => {
      inp.addEventListener('input', () => {
        const band = inp.dataset.band;
        const v = +inp.value;
        if (isMaster) {
          MUZE.Mixer.setMasterEQ(band, v);
        } else {
          MUZE.Mixer.setChannelEQ(ch, band, v);
        }
        const valEl = detail.querySelector(`[data-eq-val="${band}"]`);
        if (valEl) valEl.textContent = (v > 0 ? '+' : '') + v + ' dB';
      });
    });

    // Wire send sliders (channels only)
    if (!isMaster) {
      detail.querySelectorAll('.detail-send-slider input[data-send]').forEach(inp => {
        inp.addEventListener('input', () => {
          const v = +inp.value;
          if (inp.dataset.send === 'reverb') {
            MUZE.Mixer.setChannelReverbSend(ch, v);
            const valEl = detail.querySelector('[data-send-val="reverb"]');
            if (valEl) valEl.textContent = Math.round(v * 100) + '%';
          } else {
            MUZE.Mixer.setChannelDelaySend(ch, v);
            const valEl = detail.querySelector('[data-send-val="delay"]');
            if (valEl) valEl.textContent = Math.round(v * 100) + '%';
          }
        });
      });
    }

    // Wire limiter slider (master only)
    if (isMaster) {
      const limInp = detail.querySelector('[data-limiter]');
      if (limInp) {
        limInp.addEventListener('input', () => {
          const v = +limInp.value;
          MUZE.Mixer.setMasterLimiter(v);
          const valEl = detail.querySelector('[data-limiter-val]');
          if (valEl) valEl.textContent = v + ' dB';
          // Also update the strip view limiter display
          const limDisp = document.querySelector('.master-limiter-val');
          if (limDisp) limDisp.textContent = 'LIM ' + v + 'dB';
        });
      }
    }

    // Wire pan slider (channels only)
    if (!isMaster && ch !== 'binaural') {
      const panInp = detail.querySelector('.detail-pan-slider input');
      if (panInp) {
        panInp.addEventListener('input', () => {
          const v = +panInp.value;
          MUZE.Mixer.setChannelPan(ch, v);
          const valEl = detail.querySelector('.detail-pan-val');
          if (valEl) valEl.textContent = v === 0 ? 'C' : (v < 0 ? Math.round(Math.abs(v) * 100) + 'L' : Math.round(v * 100) + 'R');
          // Update pan dot in strip view
          const panDot = document.querySelector(`.mixer-strip[data-ch="${ch}"] .pan-dot`);
          if (panDot) panDot.style.left = ((v + 1) / 2 * 100) + '%';
        });
      }
    }

    // Show detail, hide strips
    detail.classList.remove('hidden');
    // Force reflow before adding open class for transition
    detail.offsetHeight;
    detail.classList.add('open');
  },

  // ---- Close detail panel ----
  _closeDetail() {
    const detail = document.getElementById('mixer-detail');
    detail.classList.remove('open');
    this._detailOpen = false;
    this._detailCh = null;
    // Wait for transition to finish before hiding
    setTimeout(() => {
      if (!this._detailOpen) {
        detail.classList.add('hidden');
      }
    }, 350);
  },

  // ---- Meter Animation ----
  _startMeters() {
    if (this._metersRunning) return;
    this._metersRunning = true;
    this._updateMeters();
  },

  _stopMeters() {
    this._metersRunning = false;
    if (this._meterRAF) {
      cancelAnimationFrame(this._meterRAF);
      this._meterRAF = null;
    }
  },

  // ---- Get dB level for a channel (uses gain.value as proxy — no Tone.Meter FFT overhead) ----
  _getChannelDb(ch) {
    if (ch === 'master') {
      if (MUZE.Audio._masterGain) {
        const g = MUZE.Audio._masterGain.gain.value;
        return g > 0 ? 20 * Math.log10(g) : -60;
      }
      return -60;
    }
    const node = MUZE.Audio._nodes[ch];
    if (!node) return -60;
    const g = node.gain.gain.value;
    return g > 0 ? 20 * Math.log10(g) : -60;
  },

  _updateMeters() {
    if (!this._metersRunning) return;

    const allChannels = [...MUZE.Mixer.CHANNEL_ORDER, 'master'];

    for (const ch of allChannels) {
      const meterFill = document.querySelector(`[data-meter="${ch}"]`);
      if (!meterFill) continue;

      const db = this._getChannelDb(ch);
      // Convert dB to 0-100 range (-60dB = 0%, 0dB = 100%)
      const level = Math.max(0, Math.min(100, ((db + 60) / 60) * 100));

      meterFill.style.height = level + '%';

      // Apply hot / clipping classes based on dB level
      if (db > -1) {
        meterFill.classList.add('clipping');
        meterFill.classList.remove('hot');
      } else if (db > -6) {
        meterFill.classList.add('hot');
        meterFill.classList.remove('clipping');
      } else {
        meterFill.classList.remove('hot', 'clipping');
      }

      // Peak hold indicator
      const peakEl = document.querySelector(`[data-meter-peak="${ch}"]`);
      if (peakEl) {
        const prevPeak = this._peaks[ch] || 0;
        if (level > prevPeak) {
          // New peak
          this._peaks[ch] = level;
          peakEl.style.bottom = level + '%';
          peakEl.style.opacity = '1';
          // Reset decay timer
          clearTimeout(this._peakTimers[ch]);
          this._peakTimers[ch] = setTimeout(() => {
            this._decayPeak(ch, peakEl);
          }, 800);
        }
      }
    }

    this._meterRAF = requestAnimationFrame(() => this._updateMeters());
  },

  // ---- Decay peak hold indicator ----
  _decayPeak(ch, peakEl) {
    const decay = () => {
      if (!this._metersRunning) return;
      let currentPeak = this._peaks[ch] || 0;
      currentPeak -= 1.5; // fall rate: 1.5% per frame
      if (currentPeak <= 0) {
        this._peaks[ch] = 0;
        peakEl.style.opacity = '0';
        return;
      }
      this._peaks[ch] = currentPeak;
      peakEl.style.bottom = currentPeak + '%';
      requestAnimationFrame(decay);
    };
    requestAnimationFrame(decay);
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

  FIRST_TOUCH: [
    { title: 'Press Play', desc: 'Hit the play button (top right). Music starts immediately \u2014 a pad and arpeggio respond to your face.' },
    { title: 'Smile & Frown', desc: 'Smile \u2014 the music gets brighter. Frown \u2014 it gets darker. Your expression chooses the musical mode in real-time. Watch the mode name change in the top-left corner.' },
    { title: 'Move Your Hand', desc: 'Hold up your free hand to the camera. A melody synth follows your hand up and down. Open palm = smooth legato. Closed fist = short staccato.' },
    { title: 'Toggle Drums', desc: 'Tap the drum button in the toolbar to toggle auto-rhythm on and off. The pattern plays automatically in sync with your music.' },
    { title: 'Change Chords', desc: 'The bottom bar has 6 chord buttons (I ii iii IV V vi). Tap any chord and everything follows \u2014 pad, arpeggio, melody, all in key. You\'re performing!' },
  ],

  EXPLORING: [
    { title: 'Head Tilt = Filter', desc: 'Tilt your chin down \u2014 the sound gets muffled and warm as a lowpass filter closes. Chin up/forward = bright and open. This affects pad, arp, and melody.' },
    { title: 'Eyes = Space', desc: 'Open your eyes wide \u2014 reverb and delay increase, creating a spacious wash. Squint \u2014 the sound becomes dry and intimate. This is how you control the room size.' },
    { title: 'Head Roll = Shimmer', desc: 'Tilt your head sideways. Chorus depth increases, making both the pad AND the arpeggio shimmer and widen in stereo. Great for dreamy moments.' },
    { title: 'Eyebrows = Octave', desc: 'Raise your eyebrows to shift the melody and arpeggio up an octave. Lower them to come back down. Combine with hand position for a huge pitch range.' },
    { title: 'Riser & Drop', desc: 'Hold the riser button (\u2191) in the toolbar to build a riser noise while drums and pad duck. Release to drop: massive kick hit + reverb wash + visual explosion.' },
    { title: 'Tape Stop', desc: 'Available as a dramatic transition effect \u2014 pitch drops and tempo crawls, then snaps back.' },
    { title: 'Auto-Rhythm', desc: 'Tap the drum button in the toolbar to toggle auto-rhythm. Drum patterns play automatically in sync with your music.' },
    { title: 'Visual Effects', desc: 'Notice the glowing face contour, iris lights, and hand trail? These react to the music in real-time. The ring visualization pulses with the beat. Everything is connected.' },
  ],

  SOUND_DESIGN: [
    { title: 'Synth Panel', desc: 'Tap the gear icon (top right) to open the synth panel. Four tabs: Arp (arpeggio synthesis), Melody (hand synth), Pad (chord pad), and Binaural (binaural beats).' },
    { title: 'Presets', desc: 'In the gear panel\'s Perform tab, tap the preset button to cycle through 8 presets: Default, Ambient Dream, Dark Techno, Lo-Fi Chill, Bright Pop, Deep Space, Minimal, Future Bass. Each transforms the entire instrument.' },
    { title: 'Tempo & Swing', desc: 'In the Perform tab: drag the BPM slider (40-200), use TAP TEMPO for live tempo setting, and add swing for a shuffled groove feel. Swing is especially good with lo-fi presets.' },
    { title: 'Key & Scale', desc: 'Choose from 12 keys (C through B) and 14+ scales including pentatonic, harmonic minor, whole tone, blues, phrygian dominant, hirajoshi, and melodic minor. "Modal (face)" lets your expression choose the scale.' },
    { title: 'The Mixer', desc: 'Tap MIX (top right) to open the mixing desk. 8 channel strips (pad, arp, melody, kick, snare, hat, binaural, riser) + master. Each has volume fader, pan, 3-band EQ, reverb send, and delay send.' },
    { title: 'Channel Detail', desc: 'In the mixer, tap any channel label to open its detail panel with large EQ knobs, send controls, and pan. Mute (M) and Solo (S) buttons on each strip. Master strip has a limiter.' },
    { title: 'Chorus Shimmer', desc: 'Head roll controls chorus depth on both the pad AND the arpeggio synth. Tilt your head sideways to add lush stereo shimmer to both voices simultaneously.' },
    { title: 'Pad Samples', desc: 'In the Perform tab, tap the pad/lead buttons to cycle through sample-based sounds alongside the FM synth. Any recorded sample can be used as a pad or lead.' },
    { title: 'Binaural Beats', desc: 'In the Binaural tab: toggle on for a subtle low-frequency binaural beat. Choose "tonic" (fixed pitch) or "chord" (follows harmony). Adjust beat frequency (1-20 Hz) for different mental states.' },
  ],

  PERFORMANCE: [
    { title: 'Loop Your Melody', desc: 'In the Perform tab, tap REC to start the melody loop recorder. A 1-bar count-in plays, then your hand melody is recorded for 4 bars. When done, it loops back. Tap OVR to overdub more layers. Undo removes the last layer.' },
    { title: 'Loop Length', desc: 'Change the loop length before recording: cycle through 1, 2, 4, or 8 bars to match your musical idea. Shorter loops = tighter phrases. Longer = more freedom.' },
    { title: 'Save Scenes', desc: 'In the Perform tab, tap SAVE then a slot (1-4) to snapshot your entire setup: BPM, key, synth params, mixer levels, everything. Tap a saved slot to crossfade to that scene over 2 seconds.' },
    { title: 'Chord Auto-Advance', desc: 'In the Perform tab, toggle CHORDS to auto-cycle through I\u2192ii\u2192iii\u2192IV\u2192V\u2192vi every bar. An arrow on the chord bar shows what\'s coming next. Record a loop with auto-advance for instant chord progressions.' },
    { title: 'Drums & Riser', desc: 'Tap the drum button to toggle auto-rhythm. Hold the riser button (\u2191) to build tension, release to drop. These two buttons give you powerful live control from the toolbar.' },
    { title: 'Gyroscope', desc: 'Tap the gyro button to enable phone tilt control. Tilt left/right pans the arp and melody in opposite directions for stereo width. Tilt forward/back modulates reverb depth.' },
    { title: 'Record Video', desc: 'Tap the record button (circle, top right) to capture your performance as video with audio. On iOS, you can share directly to camera roll. The recording includes all visual effects.' },
    { title: 'Performance Flow', desc: 'A great live set: Start with a preset. Build a loop with your hand. Save it to Scene 1. Switch preset. Build another loop. Save to Scene 2. Now crossfade between scenes while using the riser and drums for transitions.' },
    { title: 'Master It', desc: 'Every parameter stacks and interacts. Face controls the mood. Hand plays the melody. Toolbar buttons drive rhythm and effects. Tilt adds expression. Scenes give you structure. There are no wrong moves \u2014 only your unique performance.' },
  ],

  init() {
    document.getElementById('help-btn').addEventListener('click', () => {
      if (this._active) { this._close(); return; }
      document.getElementById('tut-picker').classList.add('open');
    });
    document.getElementById('tut-close-pick').addEventListener('click', () => {
      document.getElementById('tut-picker').classList.remove('open');
    });
    document.getElementById('tut-first').addEventListener('click', () => this._start(this.FIRST_TOUCH));
    document.getElementById('tut-explore').addEventListener('click', () => this._start(this.EXPLORING));
    document.getElementById('tut-design').addEventListener('click', () => this._start(this.SOUND_DESIGN));
    document.getElementById('tut-perform').addEventListener('click', () => this._start(this.PERFORMANCE));
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
    this._mediaRec = new MediaRecorder(canvasStream, { mimeType: this._mimeType, videoBitsPerSecond: 6000000, audioBitsPerSecond: 256000 });
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
    const sansFont = 'Inter, -apple-system, sans-serif';
    const dataFont = 'SF Mono, Menlo, monospace';
    const sc = MUZE.Music.getScaleName(S.currentScale);
    const n = S.melodyNote ? MUZE.Music.midiToNote(S.melodyNote) : '-';
    ctx.fillStyle = 'rgba(22,22,25,0.85)';
    ctx.beginPath(); ctx.roundRect(6*s, 6*s, 220*s, 72*s, 8*s); ctx.fill();
    ctx.font = `${10*s}px ${dataFont}`; ctx.fillStyle = 'rgba(255,255,255,0.6)'; ctx.textAlign = 'left';
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
    const hudW = 190*s, hudH = 58*s, hudX = (w - hudW) / 2, hudY = h - 105*s;
    ctx.fillStyle = 'rgba(22,22,25,0.85)';
    ctx.beginPath(); ctx.roundRect(hudX, hudY, hudW, hudH, 12*s); ctx.fill();
    // Top-edge highlight
    ctx.strokeStyle = 'rgba(255,255,255,0.04)';
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(hudX + 12*s, hudY + 0.5); ctx.lineTo(hudX + hudW - 12*s, hudY + 0.5); ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.font = `600 ${20*s}px ${sansFont}`; ctx.textAlign = 'center';
    ctx.fillText(modeName, w / 2, hudY + 24*s);
    const barW = 150*s, barH = 5*s, barX = (w - barW) / 2, barY = hudY + 32*s;
    ctx.fillStyle = 'rgba(255,255,255,0.10)';
    ctx.beginPath(); ctx.roundRect(barX, barY, barW, barH, 2*s); ctx.fill();
    const pct = (v + 1) / 2;
    ctx.fillStyle = `hsl(${pct * 120},70%,55%)`;
    ctx.beginPath(); ctx.roundRect(barX + pct * (barW - 12*s), barY, 12*s, barH, 2*s); ctx.fill();
    ctx.font = `400 ${10*s}px ${sansFont}`; ctx.fillStyle = 'rgba(255,255,255,0.45)';
    ctx.fillText('valence ' + v.toFixed(2), w / 2, hudY + 50*s);

    if (S.autoRhythm) {
      ctx.font = `600 ${10*s}px ${sansFont}`; ctx.fillStyle = 'rgba(232,169,72,0.6)'; ctx.textAlign = 'center';
      ctx.fillText('AUTO', w / 2, h * 0.54);
    }

    // Chord bar
    const chordY = h - 40*s, chordH = 40*s;
    ctx.fillStyle = 'rgba(22,22,25,0.85)'; ctx.fillRect(0, chordY, w, chordH);
    // Top-edge highlight
    ctx.strokeStyle = 'rgba(255,255,255,0.04)';
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(0, chordY + 0.5); ctx.lineTo(w, chordY + 0.5); ctx.stroke();
    const chords = ['I', 'ii', 'iii', 'IV', 'V', 'vi'];
    const cw = w / 6;
    ctx.font = `600 ${12*s}px ${sansFont}`; ctx.textAlign = 'center';
    chords.forEach((c, i) => {
      if (i === S.chordIndex) { ctx.fillStyle = 'rgba(232,169,72,0.08)'; ctx.fillRect(cw * i, chordY, cw, chordH); }
      ctx.fillStyle = i === S.chordIndex ? '#e8a948' : 'rgba(255,255,255,0.3)';
      ctx.fillText(c, cw * i + cw / 2, chordY + chordH / 2 + 4*s);
    });

    ctx.fillStyle = '#f33';
    ctx.beginPath(); ctx.arc(w - 30*s, 20*s, 5*s, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.font = `600 ${9*s}px ${sansFont}`; ctx.textAlign = 'right';
    ctx.fillText('REC', w - 40*s, 24*s);
  },

  async _save() {
    const ext = this._mimeType.includes('mp4') ? 'mp4' : 'webm';
    const blob = new Blob(this._chunks, { type: this._mimeType });
    const fileName = `muze-${Date.now()}.${ext}`;
    if (navigator.canShare && navigator.canShare({ files: [new File([blob], fileName, { type: this._mimeType })] })) {
      try { await navigator.share({ files: [new File([blob], fileName, { type: this._mimeType })], title: 'Jammerman Session' }); return; } catch (e) {}
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

// ---- First-run Gesture Hints (disabled — drum zones removed) ----
MUZE.Hints = {
  init() { /* no-op: drum zone hints no longer relevant */ }
};
