/* ============================================================
   MUZE — localStorage Persistence
   ============================================================ */

MUZE.Storage = {
  KEY: 'muze-settings-v2',

  _defaults: null,

  save() {
    const data = {};
    // Collect all slider + select values from the synth panel
    document.querySelectorAll('#synth-panel input[type=range], #synth-panel select').forEach(el => {
      if (el.id) data[el.id] = el.value;
    });
    // Save toggle states
    data['portamento'] = MUZE.State.portamentoMode;
    data['binaural-active'] = MUZE.Audio._binauralActive;
    data['binaural-follow'] = MUZE.Audio._binauralFollowChord;
    // Save sample selections
    data['pad-sample'] = MUZE.State.padSampleId;
    data['lead-sample'] = MUZE.State.leadSampleId;
    // Save new feature state
    data['rootOffset'] = MUZE.State.rootOffset;
    data['bpm'] = MUZE.State.bpm;
    data['swing'] = MUZE.State.swing;
    data['arpPatternIdx'] = MUZE.State.arpPatternIdx;
    data['presetIdx'] = MUZE.State.presetIdx;
    data['extraScaleMode'] = MUZE.State.extraScaleMode;
    // Save chord auto-advance state
    data['chordAutoAdvance'] = MUZE.ChordAdvance ? MUZE.ChordAdvance._active : false;

    // Save extended preset parameters (arpRate, padChorusDepth, delayTime, reverbDecay)
    if (MUZE.State.arpRate) data['arpRate'] = MUZE.State.arpRate;
    if (MUZE.State.padChorusDepth !== undefined) data['padChorusDepth'] = MUZE.State.padChorusDepth;
    if (MUZE.State.delayTime) data['delayTime'] = MUZE.State.delayTime;
    if (MUZE.State.reverbDecay !== undefined) data['reverbDecay'] = MUZE.State.reverbDecay;

    // Save loop recorder bar count
    if (MUZE.LoopRecorder) {
      data['loopBarCount'] = MUZE.LoopRecorder._barCount;
    }

    // Save scene data
    if (MUZE.SceneManager) {
      data['scenes'] = MUZE.SceneManager._scenes;
      data['activeScene'] = MUZE.SceneManager._activeSlot;
    }

    try {
      localStorage.setItem(this.KEY, JSON.stringify(data));
    } catch (e) { /* quota exceeded or private browsing */ }
  },

  load() {
    try {
      const raw = localStorage.getItem(this.KEY);
      if (!raw) return false;
      const data = JSON.parse(raw);

      // Restore slider + select values
      for (const [id, val] of Object.entries(data)) {
        const el = document.getElementById(id);
        if (el && (el.tagName === 'INPUT' || el.tagName === 'SELECT')) {
          el.value = val;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          if (el.tagName === 'SELECT') {
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }
        }
      }

      // Restore toggles
      if (data['portamento']) {
        MUZE.State.portamentoMode = data['portamento'] === true || data['portamento'] === 'true';
        MUZE.Audio.setPortamento(MUZE.State.portamentoMode);
        const btn = document.getElementById('mel-porta');
        if (btn) btn.textContent = MUZE.State.portamentoMode ? 'ON' : 'OFF';
      }

      // Restore sample selections
      if (data['pad-sample']) MUZE.State.padSampleId = data['pad-sample'];
      if (data['lead-sample']) MUZE.State.leadSampleId = data['lead-sample'];

      // Restore new features
      if (data['rootOffset'] !== undefined) {
        MUZE.State.rootOffset = +data['rootOffset'];
        const keyVal = document.getElementById('key-val');
        if (keyVal) keyVal.textContent = MUZE.Config.ROOT_NAMES[MUZE.State.rootOffset];
      }
      if (data['bpm'] !== undefined) {
        MUZE.Audio.setBPM(+data['bpm']);
        const bpmVal = document.getElementById('bpm-val');
        if (bpmVal) bpmVal.textContent = MUZE.State.bpm;
        const bpmSlider = document.getElementById('bpm-slider');
        if (bpmSlider) bpmSlider.value = MUZE.State.bpm;
      }
      if (data['swing'] !== undefined) {
        MUZE.Audio.setSwing(+data['swing']);
        const swingSlider = document.getElementById('swing-slider');
        if (swingSlider) swingSlider.value = MUZE.State.swing;
        const swingVal = document.getElementById('swing-val');
        if (swingVal) swingVal.textContent = MUZE.State.swing + '%';
      }
      if (data['arpPatternIdx'] !== undefined) {
        MUZE.State.arpPatternIdx = +data['arpPatternIdx'];
        const arpBtn = document.getElementById('arp-pattern');
        if (arpBtn) arpBtn.textContent = MUZE.Config.ARP_PATTERNS[MUZE.State.arpPatternIdx];
      }
      if (data['extraScaleMode'] && data['extraScaleMode'] !== 'null' && MUZE.Music.EXTRA_SCALES) {
        const scaleData = MUZE.Music.EXTRA_SCALES[data['extraScaleMode']];
        if (scaleData) {
          MUZE.State.extraScaleMode = data['extraScaleMode'];
          MUZE.State.modeFrozen = true;
          MUZE.State.currentScale = scaleData;
          const scaleVal = document.getElementById('scale-val');
          if (scaleVal) scaleVal.textContent = data['extraScaleMode'];
        }
      }

      // Restore extended preset parameters
      if (data['arpRate']) MUZE.State.arpRate = data['arpRate'];
      if (data['padChorusDepth'] !== undefined) MUZE.State.padChorusDepth = +data['padChorusDepth'];
      if (data['delayTime']) MUZE.State.delayTime = data['delayTime'];
      if (data['reverbDecay'] !== undefined) MUZE.State.reverbDecay = +data['reverbDecay'];
      // Apply extended params to audio engine once audio is ready
      if (MUZE.PresetExtensions && (data['arpRate'] || data['padChorusDepth'] !== undefined)) {
        // Defer to allow audio init to complete
        setTimeout(() => {
          if (MUZE.PresetExtensions.restoreFromState) MUZE.PresetExtensions.restoreFromState();
        }, 500);
      }

      // Restore loop recorder bar count
      if (data['loopBarCount'] && MUZE.LoopRecorder) {
        const bars = +data['loopBarCount'];
        if ([1, 2, 4, 8].includes(bars)) {
          MUZE.LoopRecorder._barCount = bars;
          const barEl = document.getElementById('loop-bar-count-btn') || document.getElementById('loop-bar-count');
          if (barEl) barEl.textContent = bars + ' BAR' + (bars > 1 ? 'S' : '');
        }
      }

      // Restore chord auto-advance
      if (data['chordAutoAdvance'] === true && MUZE.ChordAdvance) {
        MUZE.ChordAdvance._active = true;
        MUZE.ChordAdvance._start();
        const btn = document.getElementById('auto-chord-btn');
        if (btn) btn.classList.add('active');
        const val = document.getElementById('auto-chord-val');
        if (val) val.textContent = 'AUTO';
      }

      // Restore scenes
      if (data['scenes'] && MUZE.SceneManager) {
        MUZE.SceneManager._scenes = data['scenes'];
        MUZE.SceneManager._activeSlot = data['activeScene'] || -1;
        MUZE.SceneManager._updateSlotUI();
      }

      return true;
    } catch (e) { return false; }
  },

  // Call this after SynthMenu.init() to auto-save on changes
  enableAutoSave() {
    const debouncedSave = this._debounce(() => this.save(), 500);
    document.getElementById('synth-panel').addEventListener('input', debouncedSave);
    document.getElementById('synth-panel').addEventListener('change', debouncedSave);
    document.getElementById('synth-panel').addEventListener('click', debouncedSave);
    // Also save on perf bar interactions
    const perfBar = document.getElementById('perf-bar');
    if (perfBar) perfBar.addEventListener('click', debouncedSave);
    // Save on popup interactions
    document.querySelectorAll('.popup-panel').forEach(popup => {
      popup.addEventListener('input', debouncedSave);
      popup.addEventListener('click', debouncedSave);
    });
    // Save on chord advance toggle
    const autoChordBtn = document.getElementById('auto-chord-btn');
    if (autoChordBtn) autoChordBtn.addEventListener('click', debouncedSave);
    // Save on scene interactions
    const sceneBar = document.getElementById('scene-bar');
    if (sceneBar) sceneBar.addEventListener('click', debouncedSave);
  },

  _debounce(fn, ms) {
    let timer;
    return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); };
  }
};
