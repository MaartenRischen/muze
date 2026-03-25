/* ============================================================
   MUZE — Bootstrap
   ============================================================ */

MUZE.Loop = {
  _running: false, _lastDetect: 0, _currentPadKey: null,
  _prevMelodyNote: null, _prevBrow: 0, _lastBrowSpike: 0,
  _debugEl: null, _modeHudEl: null,
  _lastHUDUpdate: 0, _hudThrottleMs: 200, // PERF: throttle HUD to ~5fps
  _prevHUDModeName: '', _prevHUDRootName: '', _prevHUDBPM: 0, _prevHUDValence: null,
  _detectCycle: 0, // PERF: stagger face/hand detection on alternating frames

  init() {
    MUZE.Visualizer.init();
    this._debugEl = document.getElementById('debug');
    this._modeHudEl = document.getElementById('mode-hud');

    // Debug toggle (tap top-left corner)
    document.getElementById('debug-toggle').addEventListener('click', () => {
      MUZE.State.debugVisible = !MUZE.State.debugVisible;
      this._debugEl.classList.toggle('visible', MUZE.State.debugVisible);
    });
  },

  start() { this._running = true; this._tick(); },

  // Render loop without audio logic (for paused state)
  _tickVisualOnly() {
    if (this._running) return; // full tick takes over
    requestAnimationFrame(() => this._tickVisualOnly());
    // DO NOT REMOVE — BgBlur render
    if (MUZE.BgBlur && MUZE.BgBlur._ready && MUZE.Camera.video) {
      MUZE.BgBlur.render(MUZE.Camera.video, Math.round(performance.now()) + 2);
    }
    MUZE.Visualizer.draw();
    MUZE.Recorder.drawFrame();
  },

  _tick() {
    if (!this._running) return;
    requestAnimationFrame(() => this._tick());
    const now = performance.now(), video = MUZE.Camera.video, S = MUZE.State, C = MUZE.Config;

    // Detection at interval — PERF: stagger face and hand on alternating cycles
    // to halve per-frame ML cost (~15fps each instead of ~30fps both)
    if (now - this._lastDetect >= C.DETECT_INTERVAL && MUZE.Camera.available) {
      this._lastDetect = now;
      const ts = Math.round(now);
      this._detectCycle = (this._detectCycle || 0) + 1;

      if (this._detectCycle % 2 === 0) {
        // Even cycle: face detection
        const fr = MUZE.FaceTracker.detect(video, ts);
        if (fr && fr.faceLandmarks && fr.faceLandmarks.length > 0) {
          const r = MUZE.FaceFeatures.extract(fr.faceLandmarks[0]);
          if (r) {
            S.mouthOpenness = MUZE.Smooth.update('mouth', r.mouthOpenness, C.SMOOTH_FAST);
            S.lipCorner = MUZE.Smooth.update('lip', r.lipCorner, C.SMOOTH_FAST);
            S.browHeight = MUZE.Smooth.update('brow', r.browHeight, C.SMOOTH_FAST);
            S.eyeOpenness = MUZE.Smooth.update('eye', r.eyeOpenness, C.SMOOTH_FAST);
            S.mouthWidth = MUZE.Smooth.update('mouthW', r.mouthWidth, C.SMOOTH_SLOW);
            S.headPitch = MUZE.Smooth.update('pitch', r.headPitch, C.SMOOTH_FAST);
            S.headYaw = MUZE.Smooth.update('yaw', r.headYaw, C.SMOOTH_SLOW);
            S.headRoll = MUZE.Smooth.update('roll', r.headRoll, C.SMOOTH_SLOW);
            S.faceDetected = true;
          }
        } else { S.faceDetected = false; }
      } else {
        // Odd cycle: hand detection
        const hr = MUZE.HandTracker.detect(video, ts + 1);
        if (hr && hr.landmarks && hr.landmarks.length > 0) {
          const r = MUZE.HandFeatures.extract(hr.landmarks);
          S.handPresent = r.handPresent;
          S.handX = MUZE.Smooth.update('handX', r.handX, C.SMOOTH_HAND);
          S.handY = MUZE.Smooth.update('handY', r.handY, C.SMOOTH_HAND);
          S.handOpen = r.handOpen;
        } else { S.handPresent = false; }
      }

      // DO NOT REMOVE — Background blur
      if (MUZE.BgBlur && MUZE.BgBlur._ready) MUZE.BgBlur.render(video, ts + 2);
    }

    // Audio logic
    if (S.faceDetected && S.audioReady) {
      MUZE.Audio.updateParams(S);

      if (!S.modeFrozen) {
        S.currentScale = MUZE.Music.selectScale(S.lipCorner);
      }
      const scale = S.currentScale;
      const octShift = Math.floor(S.browHeight * C.OCTAVE_RANGE) * 12;
      // Use effective root note (base + user offset)
      const effectiveRoot = MUZE.Music.getEffectiveRoot();
      const root = effectiveRoot + octShift;

      MUZE.Audio.updateArpNotes(scale, root);
      if (!MUZE.Audio._arpSeq) MUZE.Audio.startArpeggio();

      const degree = C.CHORD_DEGREES[S.chordIndex];
      const padNotes = MUZE.Music.getPadVoicing(effectiveRoot, scale, degree);
      const padKey = padNotes.join(',');
      if (padKey !== this._currentPadKey) {
        this._currentPadKey = padKey;
        MUZE.Audio.triggerPad(padNotes);
        MUZE.Audio.updateBinauralFromChord(padNotes);
      }

      // Hand melody
      if (S.handPresent) {
        const note = MUZE.Music.quantize(1 - S.handY, scale, root, C.OCTAVE_RANGE);
        S.melodyNote = note;
        if (note !== this._prevMelodyNote) {
          if (S.portamentoMode) {
            MUZE.Audio.updateMelody(note);
          } else {
            MUZE.Audio.stopMelody();
            MUZE.Audio.startMelody(note);
          }
          this._prevMelodyNote = note;
          // Feed melody note to loop recorder
          if (MUZE.LoopRecorder) MUZE.LoopRecorder.recordNote(note);
        }
      } else if (this._prevMelodyNote !== null) {
        MUZE.Audio.stopMelody();
        this._prevMelodyNote = null;
        S.melodyNote = null;
        // Tell loop recorder hand left
        if (MUZE.LoopRecorder) MUZE.LoopRecorder.recordNoteOff();
      }
    } else {
      if (this._currentPadKey) { MUZE.Audio.releasePad(); this._currentPadKey = null; }
      if (this._prevMelodyNote !== null) { MUZE.Audio.stopMelody(); this._prevMelodyNote = null; }
    }

    // Draw
    MUZE.Visualizer.draw();
    MUZE.Recorder.drawFrame();
    // PERF: Throttle HUD updates to ~5fps (every 200ms) to avoid DOM reflow every frame
    if (now - this._lastHUDUpdate >= this._hudThrottleMs) {
      this._lastHUDUpdate = now;
      this._updateHUD(S);
    }
  },

  _updateHUD(S) {
    // Mode HUD — uses current accent color for cohesive look
    const modeName = MUZE.Music.getScaleName(S.currentScale).toUpperCase();
    const rootName = MUZE.Config.ROOT_NAMES[S.rootOffset];
    const bpm = MUZE.Audio.getBPM();
    const v = S.lipCorner;
    const vRounded = v.toFixed(2);

    // PERF: Skip DOM update if nothing changed
    if (modeName === this._prevHUDModeName && rootName === this._prevHUDRootName &&
        bpm === this._prevHUDBPM && vRounded === this._prevHUDValence) {
      return;
    }
    this._prevHUDModeName = modeName;
    this._prevHUDRootName = rootName;
    this._prevHUDBPM = bpm;
    this._prevHUDValence = vRounded;

    const pct = ((v + 1) / 2) * 100;
    const barW = 10;
    const left = Math.max(0, Math.min(100 - barW, pct - barW / 2));
    // PERF: Cache accent color from CSS variable (only changes on mode change, already handled above)
    const accent = MUZE.Config.MODE_COLORS[S.currentModeName]?.accent || '#e8a948';
    // Show loop state in HUD meta if looping
    let loopInfo = '';
    if (MUZE.LoopRecorder && MUZE.LoopRecorder._state !== 'empty') {
      const layers = MUZE.LoopRecorder._layers.length;
      const st = MUZE.LoopRecorder._state;
      const stLabel = st === 'recording' ? 'REC' : st === 'overdubbing' ? 'OVR' : 'LOOP';
      loopInfo = ` &middot; ${stLabel} (${layers})`;
    }
    if (MUZE.ChordAdvance && MUZE.ChordAdvance._active) {
      loopInfo += ' &middot; AUTO-C';
    }
    this._modeHudEl.innerHTML =
      `<div class="mode-name">${modeName}</div>` +
      `<div class="hud-meta">${rootName} &middot; ${bpm} BPM${loopInfo}</div>` +
      `<div class="valence-bar"><div class="fill" style="left:${left}%;width:${barW}%;background:${accent}"></div></div>` +
      `<div class="valence-label">valence <span class="valence-value">${vRounded}</span></div>`;

    // Debug (only update if visible)
    if (S.debugVisible) {
      const n = S.melodyNote ? MUZE.Music.midiToNote(S.melodyNote) : '-';
      const sc = MUZE.Music.getScaleName(S.currentScale);
      this._debugEl.innerHTML =
        `<div style="font:10px/1.5 var(--font-data, 'SF Mono', monospace);font-feature-settings:'tnum';color:rgba(255,255,255,0.6);` +
        `background:var(--elevation-1, #161619);padding:6px 10px;border-radius:8px;` +
        `border:1px solid rgba(255,255,255,0.05);box-shadow:0 2px 8px rgba(0,0,0,0.3)">` +
        `${S.faceDetected?'face':'...'} | ${sc} | chord ${S.chordIndex} | ${rootName}${4 + Math.floor(S.rootOffset / 12)}<br>` +
        `smile:${S.lipCorner.toFixed(2)} brow:${S.browHeight.toFixed(2)} eyes:${S.eyeOpenness.toFixed(2)}<br>` +
        `pitch:${S.headPitch.toFixed(2)} yaw:${S.headYaw.toFixed(2)} roll:${S.headRoll.toFixed(2)}<br>` +
        `hand:${S.handPresent?(S.handOpen?'open':'fist'):'\u2014'} note:${n}<br>` +
        `auto:${S.autoRhythm?'ON':'\u2014'} | bpm:${bpm} | swing:${S.swing}%` +
        '</div>';
    }
  }
};
