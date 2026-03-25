/* ============================================================
   MUZE — localStorage Persistence
   ============================================================ */

MUZE.Storage = {
  KEY: 'muze-settings-v1',

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

      return true;
    } catch (e) { return false; }
  },

  // Call this after SynthMenu.init() to auto-save on changes
  enableAutoSave() {
    const debouncedSave = this._debounce(() => this.save(), 500);
    document.getElementById('synth-panel').addEventListener('input', debouncedSave);
    document.getElementById('synth-panel').addEventListener('change', debouncedSave);
    document.getElementById('synth-panel').addEventListener('click', debouncedSave);
  },

  _debounce(fn, ms) {
    let timer;
    return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); };
  }
};
