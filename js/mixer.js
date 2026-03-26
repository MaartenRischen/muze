/* ============================================================
   MUZE — Mixer Data Model & Methods
   ============================================================ */

MUZE.Mixer = {
  channels: {
    pad:      { volume: -10, pan: 0,    eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.35, delaySend: 0.25, mute: false, solo: false, faceLinked: true,  color: '#60a5fa' },
    arp:      { volume: -12, pan: 0.3,  eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.35, delaySend: 0.25, mute: false, solo: false, faceLinked: true,  color: '#4ade80' },
    arp2:     { volume: -14, pan: -0.3, eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.30, delaySend: 0.20, mute: false, solo: false, faceLinked: true,  color: '#34d399' },
    melody:   { volume: -8,  pan: -0.3, eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.30, delaySend: 0.20, mute: false, solo: false, faceLinked: true,  color: '#c084fc' },
    kick:     { volume: -6,  pan: 0,    eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0,    delaySend: 0,    mute: false, solo: false, faceLinked: false, color: '#f87171' },
    snare:    { volume: -10, pan: 0,    eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.15, delaySend: 0,    mute: false, solo: false, faceLinked: false, color: '#fb923c' },
    hat:      { volume: -16, pan: 0.2,  eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.05, delaySend: 0,    mute: false, solo: false, faceLinked: false, color: '#facc15' },
    binaural: { volume: -24, pan: 0,    eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0,    delaySend: 0,    mute: false, solo: false, faceLinked: false, color: '#22d3ee' },
    riser:    { volume: -6,  pan: 0,    eqLow: 0, eqMid: 0, eqHigh: 0, reverbSend: 0.15, delaySend: 0,    mute: false, solo: false, faceLinked: false, color: '#e2e8f0' },
  },

  master: { volume: 0, eqLow: 0, eqMid: 0, eqHigh: 0, limiterThreshold: -3 },

  CHANNEL_ORDER: ['pad', 'arp', 'arp2', 'melody', 'kick', 'snare', 'hat', 'binaural', 'riser'],

  // ---- Channel Methods ----

  setChannelVolume(ch, db) {
    this.channels[ch].volume = db;
    const node = MUZE.Audio._nodes[ch];
    if (node) node.gain.gain.rampTo(Tone.dbToGain(db), 0.02);
  },

  setChannelPan(ch, val) {
    this.channels[ch].pan = val;
    const node = MUZE.Audio._nodes[ch];
    if (node) node.panner.pan.rampTo(val, 0.02);
  },

  setChannelEQ(ch, band, db) {
    const key = 'eq' + band.charAt(0).toUpperCase() + band.slice(1);
    this.channels[ch][key] = db;
    const node = MUZE.Audio._nodes[ch];
    if (node) node.eq[band].value = db;
  },

  setChannelReverbSend(ch, val) {
    this.channels[ch].reverbSend = val;
    // For face-linked channels, actual send is modulated by eye openness in updateParams()
    // For non-face-linked channels, set directly
    if (!this.channels[ch].faceLinked) {
      const node = MUZE.Audio._nodes[ch];
      if (node) node.reverbSend.gain.rampTo(val, 0.05);
    }
  },

  setChannelDelaySend(ch, val) {
    this.channels[ch].delaySend = val;
    if (!this.channels[ch].faceLinked) {
      const node = MUZE.Audio._nodes[ch];
      if (node) node.delaySend.gain.rampTo(val, 0.05);
    }
  },

  toggleMute(ch) {
    const data = this.channels[ch];
    data.mute = !data.mute;
    const node = MUZE.Audio._nodes[ch];
    if (node) {
      if (data.mute) {
        node._preMuteGain = node.gain.gain.value;
        node.gain.gain.rampTo(0, 0.02);
      } else {
        node.gain.gain.rampTo(node._preMuteGain || Tone.dbToGain(data.volume), 0.02);
      }
    }
    this._updateSoloState();
    return data.mute;
  },

  toggleSolo(ch) {
    const data = this.channels[ch];
    data.solo = !data.solo;
    this._updateSoloState();
    return data.solo;
  },

  _updateSoloState() {
    const anySolo = this.CHANNEL_ORDER.some(ch => this.channels[ch].solo);
    for (const ch of this.CHANNEL_ORDER) {
      const data = this.channels[ch];
      const node = MUZE.Audio._nodes[ch];
      if (!node) continue;
      if (data.mute) {
        node.gain.gain.rampTo(0, 0.02);
      } else if (anySolo && !data.solo) {
        node.gain.gain.rampTo(0, 0.02);
      } else {
        node.gain.gain.rampTo(Tone.dbToGain(data.volume), 0.02);
      }
    }
  },

  // ---- Master Methods ----

  setMasterVolume(db) {
    this.master.volume = db;
    if (MUZE.Audio._masterGain) {
      MUZE.Audio._masterGain.gain.rampTo(Tone.dbToGain(db), 0.02);
    }
  },

  setMasterEQ(band, db) {
    const key = 'eq' + band.charAt(0).toUpperCase() + band.slice(1);
    this.master[key] = db;
    if (MUZE.Audio._masterEQ) MUZE.Audio._masterEQ[band].value = db;
  },

  setMasterLimiter(threshold) {
    this.master.limiterThreshold = threshold;
    if (MUZE.Audio._limiter) MUZE.Audio._limiter.threshold.value = threshold;
  },
};
