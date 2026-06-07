/* ============================================================
   MUZE — Magenta RealTime 2 core (generative engine client)

   Makes Google's Magenta RealTime 2 the generative core of Muze: a local
   MLX server (server/) runs the model and streams 48kHz stereo audio; this
   module steers it live from Muze's gesture / vibe / chord / scale state and
   plays the stream back THROUGH Muze's existing master chain (so it gets the
   EQ + saturation + limiter and shows up in the visualizer).

   Magenta is ADDITIVE: the Tone.js synth engine keeps running, so if the
   server is unreachable Muze degrades gracefully to its built-in sound.

   Wire format (server -> client): see server/protocol.py — 20-byte LE header
   ("MZA1") + interleaved int16/float32 PCM.
   ============================================================ */

MUZE.MagentaRT = {
  // ---- connection ----
  enabled: false,
  status: 'idle',          // idle | connecting | live | buffering | reconnecting | offline
  _url: null,
  _ws: null,
  _attempt: 0,
  _reconnTimer: null,
  _fadeTimer: null,

  // ---- audio graph ----
  _ctx: null,
  intake: null,            // Tone.Gain sub-master -> _masterSaturation
  _nativeIntake: null,     // its native GainNode (sources connect here)
  _intakeGain: 0.85,       // headroom under the limiter
  _srcRate: 48000,         // server PCM rate (Magenta = 48k)
  _ctxRate: 48000,

  // ---- jitter buffer / scheduler ----
  _nextStartTime: 0,
  _active: null,           // Set of live AudioBufferSourceNodes
  _coalesce: null,         // queued decoded AudioBuffers awaiting flush
  _coalesceFrames: 0,
  _restartPending: false,
  _underruns: 0,
  _TARGET_AHEAD: 0.4,
  _MAX_AHEAD: 1.0,
  _PLAYOUT: 0.25,          // coalesce to ~250ms playout buffers
  _flushTimer: null,

  // ---- control loop ----
  _tickTimer: null,
  _seq: 0,
  _lastStyle: '',
  _lastChordKey: '',
  _freeHarmony: false,

  // ============================================================
  // Init — call AFTER MUZE.Audio.init() built the master chain.
  // ============================================================
  init() {
    if (!MUZE.Audio || !MUZE.Audio._masterSaturation) {
      console.warn('[MagentaRT] master chain not ready; init skipped');
      return;
    }
    this._ctx = Tone.context.rawContext;
    this._ctxRate = (Tone.context && Tone.context.sampleRate) || this._ctx.sampleRate || 48000;
    this._active = new Set();
    this._coalesce = [];

    // Sub-master gain -> full FX + visualizer. Native sources connect to .input.
    this.intake = new Tone.Gain(this._intakeGain).connect(MUZE.Audio._masterSaturation);
    this._nativeIntake = this.intake.input;          // native GainNode
    this._nativeIntake.gain.value = 0;               // start silent; fade in when live

    this._url = this._resolveUrl();

    // iOS AudioContext interruption recovery (mirrors audio-engine.js)
    try {
      this._ctx.addEventListener('statechange', () => this._onCtxState());
    } catch (e) { /* older Safari */ }
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && this.enabled && this._ctx.state === 'running') this._rebase();
    });

    this._wireButton();
    this._setStatus('idle');
    console.log('[MagentaRT] ready · server', this._url, '· ctxRate', this._ctxRate);
  },

  _resolveUrl() {
    try {
      const q = new URLSearchParams(location.search).get('mag');
      if (q) return q;
      const ls = localStorage.getItem('muzeMagentaUrl');
      if (ls) return ls;
    } catch (e) { /* ignore */ }
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    let host = location.host;
    if (!host || location.protocol === 'file:') host = '127.0.0.1:8010';
    return proto + '//' + host + '/ws';
  },

  // ============================================================
  // Enable / disable the AI core
  // ============================================================
  toggle() { this.enabled ? this.disable() : this.enable(); },

  enable() {
    if (this.enabled) return;
    if (!this.intake) { this.init(); if (!this.intake) return; }
    clearTimeout(this._fadeTimer);     // cancel any pending deferred reset from a just-prior disable()
    this.enabled = true;
    this._attempt = 0;
    this._btnActive(true);
    if (this._ctx.state !== 'running') { try { this._ctx.resume(); } catch (e) {} }
    this._connect();
    this._startLoops();
  },

  disable() {
    if (!this.enabled) return;
    this.enabled = false;
    this._btnActive(false);
    this._stopLoops();
    this._fadeOutAndStop();
    clearTimeout(this._reconnTimer);
    if (this._ws) { try { this._ws.onclose = null; this._ws.close(); } catch (e) {} this._ws = null; }
    this._setStatus('idle');
  },

  // ============================================================
  // WebSocket lifecycle
  // ============================================================
  _connect() {
    if (!this.enabled) return;
    this._setStatus(this._attempt === 0 ? 'connecting' : 'reconnecting');
    let ws;
    try { ws = new WebSocket(this._url); } catch (e) { this._scheduleReconnect(); return; }
    ws.binaryType = 'arraybuffer';
    this._ws = ws;
    ws.onopen = () => {
      this._attempt = 0;
      this._setStatus('live');
      this._send({ type: 'hello', protocol: 1, sampleRate: this._srcRate });
      this._sendControl(true);     // immediate full snapshot + play
    };
    ws.onmessage = (ev) => this._onMessage(ev);
    ws.onerror = () => { /* close handler does the work */ };
    ws.onclose = () => {
      this._ws = null;
      this._resetScheduler();
      if (this.enabled) this._scheduleReconnect();
    };
  },

  _scheduleReconnect() {
    if (!this.enabled) return;
    this._setStatus(this._attempt === 0 ? 'reconnecting' : 'offline');
    const base = Math.min(30000, 500 * Math.pow(2, this._attempt));
    const wait = base * (0.5 + Math.random());     // +/-50% jitter
    this._attempt++;
    clearTimeout(this._reconnTimer);
    this._reconnTimer = setTimeout(() => this._connect(), wait);
  },

  _send(obj) {
    if (!this._ws || this._ws.readyState !== 1) return;
    try { this._ws.send(JSON.stringify(obj)); } catch (e) { /* ignore */ }
  },

  // ============================================================
  // Incoming audio: decode -> coalesce -> gapless schedule
  // ============================================================
  _onMessage(ev) {
    const data = ev.data;
    if (typeof data === 'string') {
      try {
        const m = JSON.parse(data);
        if (m.type === 'ready') {
          this._srcRate = m.sampleRate || 48000;
          if (m.engine) this._serverEngine = m.engine;
        }
      } catch (e) { /* ignore */ }
      return;
    }
    const buf = data;                                   // ArrayBuffer
    if (!buf || buf.byteLength < 20) return;
    const dv = new DataView(buf);
    if (dv.getUint8(0) !== 0x4D || dv.getUint8(1) !== 0x5A ||
        dv.getUint8(2) !== 0x41 || dv.getUint8(3) !== 0x31) return;   // "MZA1"
    const mtype = dv.getUint8(4), ch = dv.getUint8(5), fmt = dv.getUint8(6), flags = dv.getUint8(7);
    const srate = dv.getUint32(12, true), frames = dv.getUint32(16, true);
    if (mtype === 2) {                                  // error
      try { console.warn('[MagentaRT] server error', new TextDecoder().decode(new Uint8Array(buf, 20))); } catch (e) {}
      return;
    }
    if (mtype !== 0 || frames === 0) return;            // keepalive
    const bps = fmt === 0 ? 2 : 4;
    if (buf.byteLength < 20 + frames * ch * bps) return;   // truncated/malformed frame -> drop cleanly

    const L = new Float32Array(frames), R = new Float32Array(frames);
    if (fmt === 0) {                                    // int16 interleaved
      const pcm = new Int16Array(buf, 20, frames * ch);
      for (let i = 0, j = 0; i < frames; i++) { L[i] = pcm[j++] / 32768; R[i] = ch > 1 ? pcm[j++] / 32768 : L[i]; }
    } else {                                            // float32 interleaved
      const pcm = new Float32Array(buf, 20, frames * ch);
      for (let i = 0, j = 0; i < frames; i++) { L[i] = pcm[j++]; R[i] = ch > 1 ? pcm[j++] : L[i]; }
    }
    // Build at the TRUE source rate; the graph resamples on playback if ctxRate differs.
    const ab = this._ctx.createBuffer(2, frames, srate);
    ab.copyToChannel(L, 0, 0); ab.copyToChannel(R, 1, 0);
    this._coalesce.push(ab); this._coalesceFrames += frames;
    if (flags & 1) this._restartPending = true;
    if (this._coalesceFrames >= this._PLAYOUT * this._srcRate) this._flush();
  },

  _flush() {
    if (!this._coalesce.length) return;
    const total = this._coalesceFrames;
    const out = this._ctx.createBuffer(2, total, this._srcRate);
    let off = 0;
    for (const b of this._coalesce) {
      out.copyToChannel(b.getChannelData(0), 0, off);
      out.copyToChannel(b.getChannelData(1), 1, off);
      off += b.length;
    }
    this._coalesce = []; this._coalesceFrames = 0;
    this._scheduleBuffer(out);
  },

  _scheduleBuffer(buf) {
    if (!this.enabled || this._ctx.state !== 'running') return;
    const now = this._ctx.currentTime;
    const lead = this._nextStartTime - now;
    if (lead > this._MAX_AHEAD) return;                 // overrun: drop future audio (unheard)

    let fadeIn = false;
    if (this._nextStartTime < now + 0.02) {             // first buffer or underrun -> (re)prime
      this._nextStartTime = now + this._TARGET_AHEAD;
      fadeIn = true;
      if (this.status === 'buffering') this._setStatus('live');
    }
    if (this._restartPending) { fadeIn = true; this._restartPending = false; }

    const startTime = this._nextStartTime;
    const src = this._ctx.createBufferSource();
    src.buffer = buf;
    src.connect(this._nativeIntake);
    src.onended = () => this._active.delete(src);
    try { src.start(startTime); } catch (e) { return; }
    this._active.add(src);
    this._nextStartTime += buf.length / this._srcRate;

    if (fadeIn) {
      const g = this._nativeIntake.gain;
      try {
        g.cancelScheduledValues(startTime);
        g.setValueAtTime(0, startTime);
        g.linearRampToValueAtTime(this._intakeGain, startTime + 0.03);
      } catch (e) { g.value = this._intakeGain; }
    }
  },

  _playoutWatch() {
    if (!this.enabled) return;
    if (this._coalesceFrames > 0) this._flush();        // don't let small frames starve
    if (this._ctx.state !== 'running') return;
    const lead = this._nextStartTime - this._ctx.currentTime;
    if (lead <= 0.02 && this.status === 'live' && this._ws && this._ws.readyState === 1) {
      this._underruns++;
      this._setStatus('buffering');
    }
  },

  _fadeOutAndStop() {
    if (!this._nativeIntake) return;
    const g = this._nativeIntake.gain, t = this._ctx.currentTime;
    try {
      g.cancelScheduledValues(t);
      g.setValueAtTime(g.value, t);
      g.linearRampToValueAtTime(0, t + 0.04);
    } catch (e) { try { g.value = 0; } catch (_) {} }
    clearTimeout(this._fadeTimer);
    this._fadeTimer = setTimeout(() => { if (!this.enabled) this._resetScheduler(); }, 90);
  },

  _resetScheduler() {
    if (this._active) { for (const s of this._active) { try { s.stop(); } catch (e) {} } this._active.clear(); }
    this._coalesce = []; this._coalesceFrames = 0;
    this._nextStartTime = 0;
    this._restartPending = true;
  },

  _rebase() { this._nextStartTime = 0; this._restartPending = true; },

  _onCtxState() {
    const st = this._ctx.state;
    if (st !== 'running') { this._resetScheduler(); }
    else if (this.enabled) { this._rebase(); }
  },

  // ============================================================
  // Control loop: MUZE.State -> Magenta control
  // ============================================================
  _startLoops() {
    clearInterval(this._tickTimer);
    clearInterval(this._flushTimer);
    this._tickTimer = setInterval(() => this._sendControl(false), 80);   // 12.5 Hz
    this._flushTimer = setInterval(() => this._playoutWatch(), 60);
  },
  _stopLoops() {
    clearInterval(this._tickTimer); this._tickTimer = null;
    clearInterval(this._flushTimer); this._flushTimer = null;
  },

  _sendControl(force) {
    if (!this._ws || this._ws.readyState !== 1) return;
    const S = MUZE.State, C = MUZE.Config;
    const msg = { type: 'control', seq: this._seq++, t: Date.now() / 1000, transport: 'play', frames: 2 };

    const style = this._buildStyle(S);
    if (force || style.full !== this._lastStyle) {
      msg.stylePrompts = style.prompts;
      this._lastStyle = style.full;
    }

    const chord = this._chordMidi(S);
    const chordKey = chord.join(',');
    msg.notesMidi = chord;
    msg.noteOnset = force || chordKey !== this._lastChordKey;
    msg.freeHarmony = !!this._freeHarmony;
    this._lastChordKey = chordKey;

    const IT = MUZE.InstrumentToggles;
    const preset = C.PRESETS[S.presetIdx] || null;
    const presetHasDrums = preset ? preset.kickVolume > -40 : true;
    msg.drums = !!(IT && IT._beatActive) && presetHasDrums;
    msg.drumsMasked = false;
    msg.bpm = S.bpm | 0;

    const g = this._gestureControl(S);
    msg.cfgWeights = g.cfg;
    msg.temperature = g.temperature;
    msg.topK = g.topK;
    msg.key = { root: S.rootOffset | 0, name: C.ROOT_NAMES[(S.rootOffset | 0) % 12], mode: this._modeName(S) };

    this._send(msg);
  },

  _modeName(S) {
    return S.extraScaleMode || S.currentModeName || 'dorian';
  },

  // -- chord voicing -> active MIDI pitches (mirrors Music.getPadVoicing) --
  _chordMidi(S) {
    const scale = (S.currentScale && S.currentScale.length) ? S.currentScale : [0, 2, 3, 5, 7, 9, 10];
    const root = 60 + (S.rootOffset | 0);              // Music.getEffectiveRoot()
    const len = scale.length;
    const d = ((S.chordIndex | 0) % len + len) % len;
    const tone = (i) => root + 12 * Math.floor((d + i) / len) + scale[(d + i) % len];
    const raw = [root + scale[d] - 12, tone(0), tone(2), tone(4), tone(6)];
    const out = [];
    for (const t of raw) { const m = ((t % 128) + 128) % 128; if (out.indexOf(m) < 0) out.push(m); }
    const IT = MUZE.InstrumentToggles;
    if (IT && IT._melodyActive && S.melodyNote != null) {
      const m = ((S.melodyNote % 128) + 128) % 128; if (out.indexOf(m) < 0) out.push(m);
    }
    return out;
  },

  // -- gestures -> CFG weights / temperature / top_k --
  _gestureControl(S) {
    const lerp = (a, b, t) => a + (b - a) * Math.max(0, Math.min(1, t));
    const handUp = !!S.handPresent;
    const handY = handUp ? S.handY : 0.5;              // top = 0
    const handX = handUp ? S.handX : 0.5;
    const mouth = S.mouthOpenness || 0;
    const brow = S.browHeight || 0;
    return {
      cfg: {
        notes: +lerp(0.5, 4.0, 1 - handY).toFixed(2),    // hand high = tight melodic adherence
        musiccoca: +lerp(1.5, 5.0, mouth).toFixed(2),    // mouth open = stronger style lock
        drums: +lerp(0.5, 3.5, brow).toFixed(2),         // raised brows = punchier drums
      },
      temperature: +lerp(0.9, 1.5, handX).toFixed(2),    // left tight, right wild
      topK: Math.round(lerp(24, 56, handX)),
    };
  },

  // -- style prompt: genre core (w=1.0) + key/tempo modifier (w=0.5) --
  _buildStyle(S) {
    const C = MUZE.Config;
    const coreParts = [];
    let vibeActive = false;
    if (MUZE.Vibes && MUZE.Vibes._idx >= 0 && MUZE.Vibes.LIST && MUZE.Vibes.LIST[MUZE.Vibes._idx]) {
      const vname = MUZE.Vibes.LIST[MUZE.Vibes._idx].name;
      if (this.VIBE_PROMPT[vname]) { coreParts.push(this.VIBE_PROMPT[vname]); vibeActive = true; }
    }
    const mode = this._modeName(S);
    if (!vibeActive) {
      const preset = C.PRESETS[S.presetIdx];
      coreParts.push(this.PRESET_GENRE[preset && preset.name] || 'warm electronic synth');
      const mg = this.MODE_GENRE[mode];
      if (mg) coreParts.push(mg.desc);
    }
    const minorish = this._isMinorish(mode);
    const rootName = C.ROOT_NAMES[(S.rootOffset | 0) % 12];
    const modParts = [
      rootName + (minorish ? ' minor key' : ' major key'),
      this._tempoWord(S.bpm) + ', ' + (S.bpm | 0) + ' bpm',
    ];
    let core = coreParts.join(', ').toLowerCase();
    if (core.length > 140) core = core.slice(0, 140);
    const mods = modParts.join(', ').toLowerCase();
    return { full: core + ' | ' + mods, prompts: [{ text: core, weight: 1.0 }, { text: mods, weight: 0.5 }] };
  },

  _tempoWord(bpm) {
    bpm = bpm | 0;
    if (bpm < 60) return 'very slow';
    if (bpm < 80) return 'slow';
    if (bpm < 100) return 'mid-tempo';
    if (bpm < 130) return 'upbeat';
    if (bpm < 160) return 'fast';
    return 'frenetic';
  },

  _isMinorish(mode) {
    return this._MINORISH.indexOf(mode) >= 0;
  },

  _MINORISH: ['aeolian', 'dorian', 'phrygian', 'pent. minor', 'blues', 'harm. minor',
    'melodic minor', 'phrygian dom', 'hungarian min', 'iwato', 'in-sen', 'hirajoshi', 'double harm', 'ukrainian'],

  MODE_GENRE: {
    lydian: { desc: 'bright dreamy floating' }, ionian: { desc: 'happy bright major' },
    mixolydian: { desc: 'warm bluesy groovy' }, dorian: { desc: 'smoky cool minor' },
    aeolian: { desc: 'melancholy natural minor' }, phrygian: { desc: 'dark brooding exotic' },
    'pent. major': { desc: 'open carefree folk' }, 'pent. minor': { desc: 'soulful bluesy minor' },
    'harm. minor': { desc: 'dramatic exotic minor' }, 'whole tone': { desc: 'dreamlike floating whole-tone haze' },
    blues: { desc: 'gritty bluesy soulful' }, 'melodic minor': { desc: 'sophisticated jazzy minor' },
    'phrygian dom': { desc: 'fiery flamenco middle-eastern' }, hirajoshi: { desc: 'delicate japanese koto' },
    'in-sen': { desc: 'sparse meditative japanese' }, iwato: { desc: 'haunting japanese pentatonic' },
    egyptian: { desc: 'ancient suspended desert' }, 'hungarian min': { desc: 'gypsy dramatic exotic' },
    'double harm': { desc: 'byzantine arabic ornate' }, ukrainian: { desc: 'epic eastern-european raised-fourth' },
  },

  VIBE_PROMPT: {
    'Lofi Sunset': 'lo-fi hip hop beat, warm rhodes, vinyl crackle, lazy mellow boom-bap, golden-hour nostalgia',
    'Neon Drive': '1980s synthwave, gated drums, neon arpeggios, retro analog saturation, night highway drive',
    'Deep Calm': 'ambient meditation drone, soft singing-bowl pads, breathy spacious, deeply peaceful',
    'Midnight Jazz': 'smoky late-night jazz, upright bass, brushed drums, blue-note piano, intimate club',
    'Festival': 'euphoric future bass, big supersaw drops, festival energy, bright vocal chops, anthemic',
    'Cosmic Drift': 'ambient cinematic space drone, evolving pads, shimmering textures, dreamlike floating',
    'Liquid Flow': 'liquid drum and bass, rolling breakbeat, lush warm pads, melodic soulful, flowing',
    'Dark Ritual': 'dark cinematic, ominous orchestral drones, hungarian-minor tension, ritualistic, dread',
    'Tokyo': 'vaporwave city pop, woozy chorused keys, pitched-down dreamy, neon tokyo nostalgia',
    'Desert': 'hypnotic dark techno, middle-eastern double-harmonic motifs, sand-blown drive, mysterious',
    'Bollywood': 'bright bollywood pop fusion, sitar and tabla, egyptian-scale melody, festive cinematic',
    'Aurora': 'vast ambient cinematic, glacial evolving pads, ukrainian-mode shimmer, awe and wonder',
    'Rio': 'sunny bossa nova samba, nylon guitar, breezy pentatonic, carnival warmth, beach',
    'Night Drill': 'uk drill, sliding 808 bass, dark menacing minor, sparse trappy hats, gritty night',
    'Jungle': 'ragga jungle, chopped amen breaks, deep sub bass, rave stabs, frantic energetic',
    'Sakura': 'ambient japanese, koto and shakuhachi, iwato pentatonic, cherry-blossom stillness, serene',
  },

  PRESET_GENRE: {
    'Default': 'warm electronic synth',
    'Ambient Dream': 'ethereal ambient pads, slow evolving, weightless',
    'Dark Techno': 'dark techno, driving analog bass, hypnotic stabs',
    'Lo-Fi Chill': 'lo-fi hip hop, dusty rhodes, vinyl crackle',
    'Bright Pop': 'bright upbeat synth-pop, catchy plucks',
    'Deep Space': 'ambient space drone, vast cinematic pads',
    'Minimal': 'minimal techno, sparse hypnotic',
    'Future Bass': 'future bass, lush supersaws, big drops',
    'Cinematic': 'epic cinematic score, dark filmic strings and brass',
    'Synthwave': '1980s synthwave, neon arps, gated drums',
    'Vaporwave': 'vaporwave, woozy chopped chords, slow dreamy',
    'Liquid DnB': 'liquid drum and bass, rolling melodic breakbeat',
    'Meditation': 'meditative drone, singing bowls, deep calm',
    'Trap Soul': 'trap soul, moody 808s, halftime, smooth rnb',
  },

  // ============================================================
  // Button / status UI
  // ============================================================
  _wireButton() {
    const btn = document.getElementById('toggle-magenta');
    if (!btn) return;
    this._btn = btn;
    btn.addEventListener('click', () => this.toggle());
    // long-press toggles "free harmony" (let Magenta improvise around the chord)
    let held = false, timer = null;
    btn.addEventListener('pointerdown', (e) => {
      held = false;
      try { btn.setPointerCapture(e.pointerId); } catch (_) {}
      timer = setTimeout(() => {
        held = true;
        this._freeHarmony = !this._freeHarmony;
        this._toast(this._freeHarmony ? '🧠 free harmony ON' : '🧠 free harmony OFF');
      }, 500);
    });
    btn.addEventListener('pointerup', () => { if (timer) { clearTimeout(timer); timer = null; } });
    btn.addEventListener('pointercancel', () => { if (timer) { clearTimeout(timer); timer = null; } });
    // suppress the click that follows a long-press
    btn.addEventListener('click', (e) => { if (held) { e.stopImmediatePropagation(); held = false; } }, true);
  },

  _btnActive(on) {
    if (this._btn) this._btn.classList.toggle('active', !!on);
  },

  _STATUS_COLOR: {
    idle: 'rgba(255,255,255,0.25)', connecting: '#fbbf24', reconnecting: '#fbbf24',
    live: '#34d399', buffering: '#fbbf24', offline: '#f87171',
  },

  _setStatus(s) {
    this.status = s;
    if (this._btn) {
      this._btn.dataset.mag = s;
      const col = this._STATUS_COLOR[s] || 'rgba(255,255,255,0.25)';
      this._btn.style.setProperty('--mag-status', col);
      const pulse = (s === 'connecting' || s === 'reconnecting' || s === 'buffering');
      this._btn.style.boxShadow = (this.enabled ? ('0 0 0 1.5px ' + col + (pulse ? '' : '')) : 'none');
    }
  },

  _toast(text) {
    if (MUZE.Vibes && MUZE.Vibes._toast) MUZE.Vibes._toast(text);
  },
};
