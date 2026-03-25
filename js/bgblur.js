/* ============================================================
   MUZE — Background Blur (Landmark-based)
   Uses face landmarks to clip sharp person over blurred video.
   No extra ML model needed — piggybacks on existing face tracking.
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
    // Blur the raw video via CSS
    const cam = document.getElementById('cam');
    cam.style.filter = 'blur(12px) brightness(0.85)';
    // Size bg-canvas to match video
    const check = () => {
      const v = MUZE.Camera.video;
      if (v && v.videoWidth) {
        this._bgCanvas.width = v.videoWidth;
        this._bgCanvas.height = v.videoHeight;
        this._bgCanvas.style.width = '100%';
        this._bgCanvas.style.height = '100%';
        this._bgCanvas.style.objectFit = 'cover';
        this._bgCanvas.style.transform = 'scaleX(-1)';
      } else {
        setTimeout(check, 100);
      }
    };
    check();
  },

  render(video, faceLandmarks) {
    if (!this._active || !this._bgCtx || !video || video.readyState < 2) return;
    if (!faceLandmarks || !faceLandmarks.length) {
      // No face — clear canvas so blurred video shows through
      this._bgCtx.clearRect(0, 0, this._bgCanvas.width, this._bgCanvas.height);
      return;
    }

    const w = this._bgCanvas.width, h = this._bgCanvas.height;
    if (!w) return;
    const ctx = this._bgCtx;
    const lm = faceLandmarks[0]; // first face

    // Build an expanded silhouette from face landmarks
    // Face outline indices (jawline + forehead)
    const faceOutline = [
      10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
      397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
      172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10
    ];

    ctx.clearRect(0, 0, w, h);
    ctx.save();

    // Create clip path from face outline, expanded to cover head + shoulders
    ctx.beginPath();
    const cx = lm[1].x * w; // nose tip x
    const faceTop = lm[10].y * h; // forehead
    const chin = lm[152].y * h; // chin
    const faceH = chin - faceTop;
    const faceLeft = lm[234].x * w; // left ear
    const faceRight = lm[454].x * w; // right ear
    const faceW = faceRight - faceLeft;

    // Head region (ellipse around face, expanded)
    const headCx = cx;
    const headCy = faceTop + faceH * 0.4;
    const headRx = faceW * 0.9;
    const headRy = faceH * 0.75;
    ctx.ellipse(headCx, headCy, headRx, headRy, 0, 0, Math.PI * 2);

    // Shoulders + torso (trapezoid below face)
    const shoulderW = faceW * 2.2;
    const shoulderTop = chin + faceH * 0.15;
    const bodyBottom = h; // extend to bottom of frame
    ctx.moveTo(headCx - shoulderW / 2, shoulderTop);
    ctx.quadraticCurveTo(headCx - shoulderW * 0.6, shoulderTop + faceH * 0.3,
                         headCx - shoulderW * 0.7, bodyBottom);
    ctx.lineTo(headCx + shoulderW * 0.7, bodyBottom);
    ctx.quadraticCurveTo(headCx + shoulderW * 0.6, shoulderTop + faceH * 0.3,
                         headCx + shoulderW / 2, shoulderTop);
    ctx.closePath();
    ctx.clip();

    // Draw sharp video inside the clip
    ctx.drawImage(video, 0, 0, w, h);
    ctx.restore();

    // Soft edge: redraw with feathered shadow to blend
    ctx.save();
    ctx.globalCompositeOperation = 'destination-over';
    ctx.filter = 'blur(8px)';
    ctx.beginPath();
    ctx.ellipse(headCx, headCy, headRx + 4, headRy + 4, 0, 0, Math.PI * 2);
    ctx.moveTo(headCx - shoulderW / 2 - 4, shoulderTop);
    ctx.lineTo(headCx - shoulderW * 0.7 - 4, bodyBottom);
    ctx.lineTo(headCx + shoulderW * 0.7 + 4, bodyBottom);
    ctx.lineTo(headCx + shoulderW / 2 + 4, shoulderTop);
    ctx.closePath();
    ctx.clip();
    ctx.drawImage(video, 0, 0, w, h);
    ctx.restore();
  }
};
