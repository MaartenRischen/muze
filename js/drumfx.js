/* ============================================================
   MUZE — Premium Drum Hit Visual Feedback
   Canvas 2D ripples + particles, CSS flash/pulse/kick shake
   60fps safe — no layout thrashing, compositor-friendly
   ============================================================ */

MUZE.DrumFX = (() => {
  // ---- Color palettes per drum type ----
  // Canvas: r/g/b for ripples + particles
  // CSS:    hex for label glow, flash color set via --drum-flash-color in style.css
  const COLORS = {
    hat:   { r: 0,   g: 220, b: 255, hex: '#00dcff' },   // cyan / ice blue
    snare: { r: 255, g: 240, b: 180, hex: '#fff0b4' },   // bright white-yellow
    kick:  { r: 255, g: 90,  b: 40,  hex: '#ff5a28' },   // deep red-orange
  };

  // ---- State ----
  let _canvas = null;
  let _ctx = null;
  let _dpr = 1;
  let _w = 0;
  let _h = 0;
  let _ripples = [];
  let _particles = [];
  let _running = false;
  let _rafId = null;
  let _touchZoneRect = null;
  let _resizeTimer = null;

  // ---- Ripple config ----
  const RIPPLE_MAX_RADIUS = 160;
  const RIPPLE_DURATION = 500;   // ms
  const RIPPLE_LINE_WIDTH = 1.5;       // thin crisp ring
  const RIPPLE_GLOW_WIDTH = 6;         // wider soft glow underneath

  // ---- Particle config ----
  const PARTICLE_COUNT_MIN = 12;
  const PARTICLE_COUNT_MAX = 15;
  const PARTICLE_SPEED_MIN = 1.5;
  const PARTICLE_SPEED_MAX = 5;
  const PARTICLE_LIFE = 400;     // ms
  const PARTICLE_SIZE_MIN = 1.5;
  const PARTICLE_SIZE_MAX = 4;

  // ---- Kick screen punch ----
  let _kickPunchActive = false;
  let _kickPunchTimer = null;
  const KICK_PUNCH_MS = 40;

  // ---- Public API ----
  function init() {
    _createCanvas();
    _cacheZoneRect();
    window.addEventListener('resize', _onResize);
    _start();
  }

  /**
   * Trigger all visual effects for a drum hit.
   * @param {string} drum — 'hat' | 'snare' | 'kick'
   * @param {number} clientX — touch X in viewport coords
   * @param {number} clientY — touch Y in viewport coords
   */
  function trigger(drum, clientX, clientY) {
    const color = COLORS[drum];
    if (!color) return;

    // Convert viewport coords to canvas-local coords
    _cacheZoneRect(); // ensure fresh (cheap — reads cached unless resized)
    const localX = clientX - _touchZoneRect.left;
    const localY = clientY - _touchZoneRect.top;

    // 1. Ripple
    _spawnRipple(localX, localY, color);

    // 2. Particles
    _spawnParticles(localX, localY, color);

    // 3. CSS flash + fade (::before overlay, color set per-zone in CSS)
    _flashZone(drum);

    // 4. Label glow-pulse (CSS driven)
    _pulseLabel(drum, color);

    // 5. Kick screen-wide micro-punch
    if (drum === 'kick') {
      _kickPunch();
    }
  }

  // ---- Canvas setup ----

  function _createCanvas() {
    _canvas = document.createElement('canvas');
    _canvas.id = 'drum-fx-canvas';
    _canvas.style.cssText = [
      'position:fixed',
      'pointer-events:none',
      'z-index:2',          // same z as touch-zone, but pointer-events:none
      'left:0',
      'width:100%',
    ].join(';');
    _ctx = _canvas.getContext('2d');
    // Insert right after #touch-zone so it layers on top
    const touchZone = document.getElementById('touch-zone');
    touchZone.parentNode.insertBefore(_canvas, touchZone.nextSibling);
    _sizeCanvas();
  }

  function _sizeCanvas() {
    const tz = document.getElementById('touch-zone');
    if (!tz) return;
    const rect = tz.getBoundingClientRect();
    _dpr = window.devicePixelRatio || 1;
    _w = rect.width;
    _h = rect.height;
    _canvas.width = Math.round(_w * _dpr);
    _canvas.height = Math.round(_h * _dpr);
    _canvas.style.top = rect.top + 'px';
    _canvas.style.height = _h + 'px';
    _ctx.setTransform(_dpr, 0, 0, _dpr, 0, 0);
    _touchZoneRect = rect;
  }

  function _cacheZoneRect() {
    // getBoundingClientRect is cheap (no layout forced if nothing dirty)
    const tz = document.getElementById('touch-zone');
    if (tz) _touchZoneRect = tz.getBoundingClientRect();
    return _touchZoneRect;
  }

  function _onResize() {
    clearTimeout(_resizeTimer);
    _resizeTimer = setTimeout(() => {
      _sizeCanvas();
    }, 100);
  }

  // ---- Render loop (separate from main visualizer — only active when effects are alive) ----

  function _start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  function _loop() {
    if (!_running) return;

    // Only run RAF when there are active effects
    if (_ripples.length === 0 && _particles.length === 0) {
      _running = false;
      // Clear canvas once
      _ctx.clearRect(0, 0, _w, _h);
      return;
    }

    _rafId = requestAnimationFrame(_loop);
    _draw();
  }

  function _draw() {
    const now = performance.now();
    _ctx.clearRect(0, 0, _w, _h);

    // ---- Draw ripples ----
    for (let i = _ripples.length - 1; i >= 0; i--) {
      const rip = _ripples[i];
      const elapsed = now - rip.born;
      const t = elapsed / RIPPLE_DURATION;

      if (t >= 1) {
        // PERF: swap-and-pop O(1) removal
        _ripples[i] = _ripples[_ripples.length - 1];
        _ripples.pop();
        continue;
      }

      // Ease-out cubic for radius expansion
      const easeOut = 1 - Math.pow(1 - t, 3);
      const radius = easeOut * RIPPLE_MAX_RADIUS;

      // Opacity: starts strong, fades out with ease-in curve
      const opacity = 1 - Math.pow(t, 2);

      // Primary ripple ring — soft glow underneath (wider, low alpha)
      _ctx.beginPath();
      _ctx.arc(rip.x, rip.y, radius, 0, Math.PI * 2);
      _ctx.strokeStyle = `rgba(${rip.r}, ${rip.g}, ${rip.b}, ${(0.15 * opacity).toFixed(3)})`;
      _ctx.lineWidth = RIPPLE_GLOW_WIDTH * (1 - t * 0.4);
      _ctx.stroke();

      // Primary ripple ring — crisp thin stroke on top
      _ctx.beginPath();
      _ctx.arc(rip.x, rip.y, radius, 0, Math.PI * 2);
      _ctx.strokeStyle = `rgba(${rip.r}, ${rip.g}, ${rip.b}, ${(0.7 * opacity).toFixed(3)})`;
      _ctx.lineWidth = RIPPLE_LINE_WIDTH * (1 - t * 0.5);
      _ctx.stroke();

      // Secondary outer ripple (delayed, slower expansion, creates depth)
      if (t > 0.08) {
        const t2 = (t - 0.08) / 0.92;
        const easeOut2 = 1 - Math.pow(1 - t2, 3);
        const radius2 = easeOut2 * RIPPLE_MAX_RADIUS * 1.35;
        const opacity2 = 1 - Math.pow(t2, 1.5);

        // Outer ring glow
        _ctx.beginPath();
        _ctx.arc(rip.x, rip.y, radius2, 0, Math.PI * 2);
        _ctx.strokeStyle = `rgba(${rip.r}, ${rip.g}, ${rip.b}, ${(0.08 * opacity2).toFixed(3)})`;
        _ctx.lineWidth = RIPPLE_GLOW_WIDTH * 0.7;
        _ctx.stroke();

        // Outer ring crisp
        _ctx.beginPath();
        _ctx.arc(rip.x, rip.y, radius2, 0, Math.PI * 2);
        _ctx.strokeStyle = `rgba(${rip.r}, ${rip.g}, ${rip.b}, ${(0.3 * opacity2).toFixed(3)})`;
        _ctx.lineWidth = 1;
        _ctx.stroke();
      }

      // Inner glow fill (very brief — initial impact)
      if (t < 0.25) {
        const glowOpacity = (1 - t / 0.25) * 0.18;
        const grad = _ctx.createRadialGradient(rip.x, rip.y, 0, rip.x, rip.y, radius * 0.7);
        grad.addColorStop(0, `rgba(${rip.r}, ${rip.g}, ${rip.b}, ${glowOpacity.toFixed(3)})`);
        grad.addColorStop(1, `rgba(${rip.r}, ${rip.g}, ${rip.b}, 0)`);
        _ctx.beginPath();
        _ctx.arc(rip.x, rip.y, radius * 0.7, 0, Math.PI * 2);
        _ctx.fillStyle = grad;
        _ctx.fill();
      }
    }

    // ---- Draw particles ----
    for (let i = _particles.length - 1; i >= 0; i--) {
      const p = _particles[i];
      const elapsed = now - p.born;
      const t = elapsed / PARTICLE_LIFE;

      if (t >= 1) {
        // PERF: swap-and-pop O(1) removal
        _particles[i] = _particles[_particles.length - 1];
        _particles.pop();
        continue;
      }

      // Update position — drag physics: exponential deceleration
      const drag = Math.pow(1 - t, 1.8);
      p.x += p.vx * drag;
      p.y += p.vy * drag;

      // Opacity: quick in, smooth fade-out
      const opacity = t < 0.08 ? t / 0.08 : 1 - Math.pow((t - 0.08) / 0.92, 1.5);

      // Size: starts at max, shrinks gently
      const size = p.size * (1 - t * 0.55);

      // Glow halo behind each particle (soft, wider)
      const glowR = Math.max(size * 3, 4);
      const grad = _ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, glowR);
      grad.addColorStop(0, `rgba(${p.r}, ${p.g}, ${p.b}, ${(opacity * 0.2).toFixed(3)})`);
      grad.addColorStop(1, `rgba(${p.r}, ${p.g}, ${p.b}, 0)`);
      _ctx.beginPath();
      _ctx.arc(p.x, p.y, glowR, 0, Math.PI * 2);
      _ctx.fillStyle = grad;
      _ctx.fill();

      // Core particle (solid, bright)
      _ctx.beginPath();
      _ctx.arc(p.x, p.y, size, 0, Math.PI * 2);
      _ctx.fillStyle = `rgba(${p.r}, ${p.g}, ${p.b}, ${(opacity * 0.95).toFixed(3)})`;
      _ctx.fill();
    }
  }

  // ---- Spawners ----

  function _spawnRipple(x, y, color) {
    _ripples.push({
      x, y,
      r: color.r, g: color.g, b: color.b,
      born: performance.now(),
    });
    // Restart render loop if dormant
    if (!_running) _start();
  }

  function _spawnParticles(x, y, color) {
    const count = PARTICLE_COUNT_MIN + Math.floor(Math.random() * (PARTICLE_COUNT_MAX - PARTICLE_COUNT_MIN + 1));
    const now = performance.now();

    for (let i = 0; i < count; i++) {
      const angle = (Math.PI * 2 / count) * i + (Math.random() - 0.5) * 0.8;
      const speed = PARTICLE_SPEED_MIN + Math.random() * (PARTICLE_SPEED_MAX - PARTICLE_SPEED_MIN);
      const size = PARTICLE_SIZE_MIN + Math.random() * (PARTICLE_SIZE_MAX - PARTICLE_SIZE_MIN);

      _particles.push({
        x, y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        r: color.r, g: color.g, b: color.b,
        size,
        born: now + Math.random() * 30, // slight stagger for organic feel
      });
    }
    // Restart render loop if dormant
    if (!_running) _start();
  }

  // ---- CSS-driven effects ----

  function _flashZone(drum) {
    const el = document.getElementById('zone-' + drum);
    if (!el) return;

    // --drum-flash-color is pre-set per zone in CSS
    el.classList.add('drum-flash');

    // Hold flash briefly, then remove class to trigger CSS fade-out transition
    // Flash visible ~30ms, then 200ms ease-out fade
    setTimeout(() => {
      el.classList.remove('drum-flash');
    }, 30);
  }

  function _pulseLabel(drum, color) {
    const el = document.getElementById('zone-' + drum);
    if (!el) return;

    el.style.setProperty('--drum-glow-color', color.hex);
    el.classList.add('drum-label-pulse');

    setTimeout(() => {
      el.classList.remove('drum-label-pulse');
    }, 300);
  }

  function _kickPunch() {
    if (_kickPunchActive) return;
    _kickPunchActive = true;

    const body = document.body;
    // Phase 1: instant scale-up
    body.classList.remove('kick-settle');
    body.classList.add('kick-punch');

    clearTimeout(_kickPunchTimer);
    _kickPunchTimer = setTimeout(() => {
      // Phase 2: smooth settle-back
      body.classList.remove('kick-punch');
      body.classList.add('kick-settle');
      setTimeout(() => {
        body.classList.remove('kick-settle');
        _kickPunchActive = false;
      }, 70);
    }, KICK_PUNCH_MS);
  }

  // ---- Cleanup ----
  function destroy() {
    _running = false;
    cancelAnimationFrame(_rafId);
    window.removeEventListener('resize', _onResize);
    if (_canvas && _canvas.parentNode) {
      _canvas.parentNode.removeChild(_canvas);
    }
    _ripples = [];
    _particles = [];
  }

  return { init, trigger, destroy };
})();
