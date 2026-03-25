/* ============================================================
   MUZE — Background Blur (DSLR-style DOF)
   CSS blurs the video, canvas draws sharp person with soft
   radial falloff centered on face — no hard edges.
   ============================================================ */

MUZE.BgBlur = {
  _active: false,
  _bgCanvas: null, _bgCtx: null,

  init() {
    this._bgCanvas = document.getElementById('bg-canvas');
    if (this._bgCanvas) {
      this._bgCtx = this._bgCanvas.getContext('2d');
    }
  },

  activate() {
    this._active = true;
    const check = () => {
      const v = MUZE.Camera.video;
      if (v && v.videoWidth) {
        this._bgCanvas.width = v.videoWidth;
        this._bgCanvas.height = v.videoHeight;
        this._bgCanvas.style.width = '100%';
        this._bgCanvas.style.height = '100%';
        this._bgCanvas.style.objectFit = 'cover';
        this._bgCanvas.style.transform = 'scaleX(-1)';
      } else setTimeout(check, 100);
    };
    check();
  },

  render(video, faceLandmarks) {
    if (!this._active || !this._bgCtx || !video || video.readyState < 2) return;
    const w = this._bgCanvas.width, h = this._bgCanvas.height;
    if (!w) return;
    const ctx = this._bgCtx;

    if (!faceLandmarks || !faceLandmarks.length) {
      ctx.clearRect(0, 0, w, h);
      return;
    }

    const lm = faceLandmarks[0];

    // Face center and size
    const noseTip = lm[1];
    const forehead = lm[10];
    const chin = lm[152];
    const leftEar = lm[234];
    const rightEar = lm[454];

    const cx = noseTip.x * w;
    const faceTop = forehead.y * h;
    const faceBottom = chin.y * h;
    const faceH = faceBottom - faceTop;
    const faceW = (rightEar.x - leftEar.x) * w;

    // Person center — slightly below nose to include torso
    const pcx = cx;
    const pcy = faceTop + faceH * 0.8;

    // Radii — tight around head + shoulders
    const rx = faceW * 1.0;
    const ry = faceH * 1.3;

    // Draw sharp video
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(video, 0, 0, w, h);

    // Erase edges with soft radial gradient → reveals blurred video behind
    ctx.save();
    ctx.globalCompositeOperation = 'destination-in';
    const grad = ctx.createRadialGradient(pcx, pcy, 0, pcx, pcy, Math.max(rx, ry));
    grad.addColorStop(0, 'rgba(255,255,255,1)');
    grad.addColorStop(0.3, 'rgba(255,255,255,1)');
    grad.addColorStop(0.6, 'rgba(255,255,255,0.2)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = grad;

    // Use ellipse transform for non-circular falloff
    ctx.translate(pcx, pcy);
    ctx.scale(1, ry / rx);
    ctx.translate(-pcx, -pcy);
    ctx.fillRect(0, 0, w, h);
    ctx.restore();
  }
};
