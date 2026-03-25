/* ============================================================
   MUZE — Background Blur (Selfie Segmentation)
   ============================================================ */

MUZE.BgBlur = {
  _segmenter: null, _active: false,
  _bgCanvas: null, _bgCtx: null,
  _sharpCanvas: null, _sharpCtx: null,
  _blurCanvas: null, _blurCtx: null,
  _w: 0, _h: 0,

  async init(ImageSegmenter, vision) {
    this._bgCanvas = document.getElementById('bg-canvas');
    this._bgCtx = this._bgCanvas.getContext('2d', { willReadFrequently: true });
    this._sharpCanvas = document.createElement('canvas');
    this._sharpCtx = this._sharpCanvas.getContext('2d', { willReadFrequently: true });
    this._blurCanvas = document.createElement('canvas');
    this._blurCtx = this._blurCanvas.getContext('2d');

    this._segmenter = await ImageSegmenter.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite',
        delegate: 'GPU'
      },
      runningMode: 'VIDEO',
      outputCategoryMask: false,
      outputConfidenceMasks: true
    });
  },

  resize() {
    const video = MUZE.Camera.video;
    const vw = video.videoWidth || 640, vh = video.videoHeight || 480;
    this._w = vw; this._h = vh;
    [this._bgCanvas, this._sharpCanvas, this._blurCanvas].forEach(c => {
      c.width = vw; c.height = vh;
    });
    this._bgCanvas.style.width = '100%';
    this._bgCanvas.style.height = '100%';
    this._bgCanvas.style.objectFit = 'cover';
    this._bgCanvas.style.transform = 'scaleX(-1)';
  },

  activate() {
    this._active = true;
    document.getElementById('cam').classList.add('hidden');
    const check = () => {
      if (MUZE.Camera.video && MUZE.Camera.video.videoWidth) this.resize();
      else setTimeout(check, 100);
    };
    check();
  },

  render(video, ts) {
    if (!this._active || !this._segmenter || video.readyState < 2) return;
    if (!this._w) this.resize();
    const w = this._w, h = this._h;

    // Draw video (not mirrored — CSS handles mirror)
    this._sharpCtx.drawImage(video, 0, 0, w, h);

    // Blurred version
    this._blurCtx.filter = 'blur(14px)';
    this._blurCtx.drawImage(this._sharpCanvas, 0, 0);
    this._blurCtx.filter = 'none';

    // Segment at native video resolution
    let result;
    try { result = this._segmenter.segmentForVideo(video, ts); } catch(e) { return; }
    if (!result || !result.confidenceMasks || !result.confidenceMasks.length) return;
    const conf = result.confidenceMasks[0].getAsFloat32Array();

    // Get pixel data
    const sharp = this._sharpCtx.getImageData(0, 0, w, h);
    const blur = this._blurCtx.getImageData(0, 0, w, h);
    const sd = sharp.data, bd = blur.data;
    const pixels = Math.min(conf.length, sd.length / 4);

    // Blend per-pixel: person from sharp, background from blur
    for (let i = 0; i < pixels; i++) {
      const p = i * 4;
      const a = conf[i]; // 0=bg, 1=person
      const b = 1 - a;
      sd[p]     = sd[p]     * a + bd[p]     * b | 0;
      sd[p + 1] = sd[p + 1] * a + bd[p + 1] * b | 0;
      sd[p + 2] = sd[p + 2] * a + bd[p + 2] * b | 0;
    }

    this._bgCtx.putImageData(sharp, 0, 0);
    result.confidenceMasks[0].close();
  }
};
