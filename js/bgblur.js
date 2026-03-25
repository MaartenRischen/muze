/* ============================================================
   MUZE — Background Blur (MediaPipe Selfie Segmenter)
   ============================================================ */

MUZE.BgBlur = {
  _active: false,
  _segmenter: null,
  _bgCanvas: null, _bgCtx: null,
  _tmpCanvas: null, _tmpCtx: null,
  _w: 0, _h: 0,
  _ready: false,

  async init(ImageSegmenter, vision) {
    this._bgCanvas = document.getElementById('bg-canvas');
    this._bgCtx = this._bgCanvas.getContext('2d', { willReadFrequently: true });
    this._tmpCanvas = document.createElement('canvas');
    this._tmpCtx = this._tmpCanvas.getContext('2d', { willReadFrequently: true });

    try {
      this._segmenter = await ImageSegmenter.createFromOptions(vision, {
        baseOptions: {
          modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite',
          delegate: 'GPU'
        },
        runningMode: 'VIDEO',
        outputCategoryMask: false,
        outputConfidenceMasks: true
      });
      console.log('BgBlur: segmenter loaded');
      this._ready = true;
    } catch (e) {
      console.warn('BgBlur: segmenter failed, falling back to CSS-only blur', e);
      this._ready = false;
    }
  },

  activate() {
    this._active = true;
    // CSS blur as base — always works
    document.getElementById('cam').style.filter = 'blur(12px) brightness(0.85)';
    // Size canvases when video is ready
    const check = () => {
      const v = MUZE.Camera.video;
      if (v && v.videoWidth) {
        this._w = v.videoWidth;
        this._h = v.videoHeight;
        this._bgCanvas.width = this._w;
        this._bgCanvas.height = this._h;
        this._tmpCanvas.width = this._w;
        this._tmpCanvas.height = this._h;
      } else setTimeout(check, 200);
    };
    check();
  },

  render(video, ts) {
    if (!this._active || !this._ready || !this._segmenter) return;
    if (!video || video.readyState < 2 || !this._w) return;

    const w = this._w, h = this._h;

    // Draw sharp video to temp canvas
    this._tmpCtx.drawImage(video, 0, 0, w, h);

    // Run segmenter
    let result;
    try {
      result = this._segmenter.segmentForVideo(video, ts);
    } catch (e) { return; }

    if (!result || !result.confidenceMasks || !result.confidenceMasks.length) return;

    const mask = result.confidenceMasks[0].getAsFloat32Array();
    const imgData = this._tmpCtx.getImageData(0, 0, w, h);
    const d = imgData.data;
    const pixels = Math.min(mask.length, d.length / 4);

    // Set alpha based on mask — person = opaque, background = transparent
    for (let i = 0; i < pixels; i++) {
      d[i * 4 + 3] = mask[i] * 255 | 0;
    }

    this._bgCtx.clearRect(0, 0, w, h);
    this._bgCtx.putImageData(imgData, 0, 0);

    result.confidenceMasks[0].close();
  }
};
