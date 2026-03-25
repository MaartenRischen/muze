/* ============================================================
   MUZE — Bootstrap
   ============================================================ */

MUZE.Loop = {
  _running: false, _lastDetect: 0, _currentPadKey: null,
  _prevMelodyNote: null, _prevBrow: 0, _lastBrowSpike: 0,
  _debugEl: null, _modeHudEl: null,

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

  _tick() {
    if (!this._running) return;
    requestAnimationFrame(() => this._tick());
    const now = performance.now(), video = MUZE.Camera.video, S = MUZE.State, C = MUZE.Config;

    // Detection at interval
    if (now - this._lastDetect >= C.DETECT_INTERVAL && MUZE.Camera.available) {
      this._lastDetect = now;
      const ts = Math.round(now);

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

      const hr = MUZE.HandTracker.detect(video, ts + 1);
      if (hr && hr.landmarks && hr.landmarks.length > 0) {
        const r = MUZE.HandFeatures.extract(hr.landmarks);
        S.handPresent = r.handPresent;
        S.handX = MUZE.Smooth.update('handX', r.handX, C.SMOOTH_HAND);
        S.handY = MUZE.Smooth.update('handY', r.handY, C.SMOOTH_HAND);
        S.handOpen = r.handOpen;
      } else { S.handPresent = false; }

      // Background blur
      MUZE.BgBlur.render(video, ts + 2);
    }

    // Audio logic
    if (S.faceDetected && S.audioReady) {
      MUZE.Audio.updateParams(S);

      if (!S.modeFrozen) {
        S.currentScale = MUZE.Music.selectScale(S.lipCorner);
      }
      const scale = S.currentScale;
      const octShift = Math.floor(S.browHeight * C.OCTAVE_RANGE) * 12;
      const root = C.ROOT_NOTE + octShift;

      MUZE.Audio.updateArpNotes(scale, root);
      if (!MUZE.Audio._arpSeq) MUZE.Audio.startArpeggio();

      const degree = C.CHORD_DEGREES[S.chordIndex];
      const padNotes = MUZE.Music.getPadVoicing(C.ROOT_NOTE, scale, degree);
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
        }
      } else if (this._prevMelodyNote !== null) {
        MUZE.Audio.stopMelody();
        this._prevMelodyNote = null;
        S.melodyNote = null;
      }
    } else {
      if (this._currentPadKey) { MUZE.Audio.releasePad(); this._currentPadKey = null; }
      if (this._prevMelodyNote !== null) { MUZE.Audio.stopMelody(); this._prevMelodyNote = null; }
    }

    // Draw
    MUZE.Visualizer.draw();
    MUZE.Recorder.drawFrame();
    this._updateHUD(S);
  },

  _updateHUD(S) {
    // Mode HUD
    const modeName = MUZE.Music.getScaleName(S.currentScale).toUpperCase();
    const v = S.lipCorner;
    const pct = ((v + 1) / 2) * 100;
    const barW = 8;
    const left = Math.max(0, Math.min(100 - barW, pct - barW / 2));
    const hue = pct * 1.2;
    this._modeHudEl.innerHTML =
      `<div>${modeName}</div>` +
      `<div class="valence-bar"><div class="fill" style="left:${left}%;width:${barW}%;background:hsl(${hue},70%,55%)"></div></div>` +
      `<div class="valence-label">valence ${v.toFixed(2)}</div>`;

    // Debug (only update if visible)
    if (S.debugVisible) {
      const n = S.melodyNote ? MUZE.Music.midiToNote(S.melodyNote) : '-';
      const sc = MUZE.Music.getScaleName(S.currentScale);
      this._debugEl.innerHTML =
        '<div style="font:10px/1.5 monospace;color:rgba(255,255,255,0.6);' +
        'background:rgba(0,0,0,0.35);padding:5px 8px;border-radius:6px;' +
        'backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px)">' +
        `${S.faceDetected?'face':'...'} | ${sc} | chord ${S.chordIndex}<br>` +
        `smile:${S.lipCorner.toFixed(2)} brow:${S.browHeight.toFixed(2)} eyes:${S.eyeOpenness.toFixed(2)}<br>` +
        `pitch:${S.headPitch.toFixed(2)} yaw:${S.headYaw.toFixed(2)} roll:${S.headRoll.toFixed(2)}<br>` +
        `hand:${S.handPresent?(S.handOpen?'open':'fist'):'\u2014'} note:${n}<br>` +
        `auto:${S.autoRhythm?'ON':'\u2014'}` +
        '</div>';
    }
  }
};
