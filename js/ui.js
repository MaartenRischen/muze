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

    // Premium drum hit visual feedback
    if (MUZE.DrumFX) MUZE.DrumFX.init();

    document.querySelector('.chord-btn[data-chord="0"]').classList.add('active');
  },

  _onStart(e) {
    e.preventDefault();
    const t = e.changedTouches[0];
    const now = performance.now();
    this._touchStart = { x: t.clientX, y: t.clientY, time: now };
    this._isHolding = false;

    // INSTANT drum trigger on touchstart (zero latency)
    const target = document.elementFromPoint(t.clientX, t.clientY);
    if (target) {
      const drum = target.dataset.drum || target.parentElement?.dataset?.drum;
      if (drum && (!this._cooldown[drum] || now - this._cooldown[drum] > 120)) {
        this._cooldown[drum] = now;
        MUZE.Audio.triggerDrum(drum, 0.7);
        if (MUZE.DrumFX) MUZE.DrumFX.trigger(drum, t.clientX, t.clientY);
        if (MUZE.LoopRecorder) MUZE.LoopRecorder.recordHit(drum);
        const el = document.getElementById('zone-' + drum);
        if (el) { el.classList.add('hit'); setTimeout(() => el.classList.remove('hit'), 180); }
        this._drumFiredOnStart = true;
      }
    }

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
        if (MUZE.Visualizer.triggerExplosion) {
          const w = window.innerWidth, h = window.innerHeight;
          MUZE.Visualizer.triggerExplosion(w / 2, h * 0.4, 120);
        }
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

    // Drum already fired on touchstart — nothing to do here
    // (double-tap detection above handles auto-rhythm toggle)
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

    // Toggle mixer panel
    document.getElementById('mixer-btn').addEventListener('click', () => {
      const opening = !panel.classList.contains('open');
      panel.classList.toggle('open');
      if (opening) this._startMeters();
      else this._stopMeters();
    });

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

  BASIC: [
    { title: 'Smile', desc: 'Try smiling. The music shifts to a brighter, happier mode. Watch the mode name change and the colors shift.' },
    { title: 'Frown', desc: 'Now frown or make a sad face. The music becomes darker and more tense. Notice the purple tones.' },
    { title: 'Tilt Your Head', desc: 'Tilt your chin down \u2014 the sound gets muffled as the filter closes. Chin up = bright and open.' },
    { title: 'Chords & Drums', desc: 'Bottom bar: 6 chord buttons. Above that: 3 drum zones (hi-hat top, snare middle, kick bottom). Tap them!' },
    { title: 'Double Tap', desc: 'Double-tap anywhere in the drum zone to start an auto-rhythm. Double-tap again to stop.' },
    { title: 'Show Your Hand', desc: 'Hold your hand up to the camera. A melody synth appears \u2014 move up and down to change pitch.' },
    { title: 'Open vs Closed', desc: 'Open palm = legato. Closed fist = staccato. Toggle portamento in the gear menu for smooth glides.' },
    { title: 'Eyes = Reverb', desc: 'Open your eyes wide for more reverb and delay. Squint to dry things out. The ring visualization responds too.' },
    { title: 'Presets & BPM', desc: 'Top-left: tap PRESET to cycle through 8 sound presets. Tap BPM to set tempo, use TAP TEMPO for live timing. KEY and SCALE let you choose any key and mode.' },
    { title: 'Loop Recorder', desc: 'Left side: the loop bar. Tap the circle to record a 4-bar loop. When playing, tap again or + to overdub new layers. The undo arrow removes the last layer.' },
    { title: 'Scenes', desc: 'Bottom-left: 4 scene slots. Tap SAVE then a slot to snapshot your current settings. Tap any saved slot to crossfade smoothly to that vibe in 2 seconds.' },
    { title: 'Chord Auto-Advance', desc: 'Tap CHORDS in the performance bar to auto-cycle through I-ii-iii-IV-V-vi every bar. An arrow shows the next chord. Great for building full progressions.' },
    { title: 'You\'re Ready!', desc: 'Use the record button to capture performances. Tap ? again for the advanced tutorial.' },
  ],

  ADVANCED: [
    { title: 'Six Modes', desc: 'Smile controls the mode: Phrygian (dark) \u2192 Aeolian \u2192 Dorian \u2192 Mixolydian \u2192 Ionian \u2192 Lydian (bright). Each has its own color.' },
    { title: 'Filter (Head Pitch)', desc: 'Chin down = lowpass closes. Chin up = opens. Volume-compensated. Affects pad, melody, and arpeggio.' },
    { title: 'Reverb + Delay', desc: 'Eye openness scales reverb/delay. Wide = full wet, squint = dry. The reverb has subtle modulation for a lush tail.' },
    { title: 'Chorus (Head Roll)', desc: 'Tilt sideways for chorus depth \u2014 shimmer and stereo widening.' },
    { title: 'Octave (Brows)', desc: 'Raise eyebrows to shift melody and arpeggio up an octave.' },
    { title: 'Riser (Hold + Release)', desc: 'Hold finger 400ms+: noise sweep builds, drums duck. Swipe up to drop (big kick + reverb wash). Release without swipe to cancel.' },
    { title: 'Swipe Effects', desc: 'Swipe down: tape stop. Swipe up (no hold): reverb throw. Swipe left/right: cycle drum patterns.' },
    { title: 'Synth Panel', desc: 'Gear icon: Arp, Melody, Pad, Binaural tabs. Full ADSR, FX controls. Presets crossfade smoothly over 2 seconds.' },
    { title: 'Loop Recorder', desc: 'Record a 4-bar loop, then overdub layers on top. Undo removes the last layer. This is how you build a full arrangement live.' },
    { title: 'Scenes (4 Slots)', desc: 'Save your entire instrument state (BPM, key, volumes, sends, synth params) to 4 slots. Recall any scene with a smooth 2-second crossfade between settings.' },
    { title: 'Gyroscope', desc: 'Tap the rotation arrow button to enable phone tilt control. Left/right tilt pans the arp and melody. Forward/back tilt modulates reverb depth.' },
    { title: 'Beat Repeat', desc: 'Triple-tap any drum zone for a 2-second stutter effect. It accelerates from 8th to 16th to 32nd notes. Amazing for build-ups right before a drop.' },
    { title: 'Chord Auto-Advance', desc: 'Tap CHORDS to auto-cycle through the I-ii-iii-IV-V-vi progression every bar. Combine with loop recording to capture harmonic movement.' },
    { title: 'Sidechain Pump', desc: 'Every kick hit subtly ducks the pad volume for that classic pumping groove feel. It creates space and movement automatically.' },
    { title: 'Swing', desc: 'In the BPM popup, drag the swing slider to add shuffle feel. Works great with lo-fi and halftime presets.' },
    { title: 'Key & Scale', desc: '12 keys (C through B) and 11 scales including pentatonic, harmonic minor, whole tone, and blues. MODAL mode lets your face choose the scale.' },
    { title: 'Go Perform', desc: 'Layer face, hands, touch, loops, scenes, chord advance, and beat repeat. Switch between 4 vibes live. Every parameter stacks. There are no wrong moves.' },
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
