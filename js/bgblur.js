/* ============================================================
   MUZE — Background Blur (MediaPipe Selfie Segmenter)
   Sigmoid threshold + box blur for smooth hair/edge feathering
   ============================================================ */

MUZE.BgBlur = {
  _active: false,
  _segmenter: null,
  _bgCanvas: null, _bgCtx: null,
  _tmpCanvas: null, _tmpCtx: null,
  _w: 0, _h: 0,
  _ready: false,
  _sigLUT: null,   // 256-entry sigmoid lookup table
  _blurBuf: null,  // temp buffer for box blur

  async init(ImageSegmenter, vision) {
    this._bgCanvas = document.getElementById('bg-canvas');
    this._bgCtx = this._bgCanvas.getContext('2d', { willReadFrequently: true });
    this._tmpCanvas = document.createElement('canvas');
    this._tmpCtx = this._tmpCanvas.getContext('2d', { willReadFrequently: true });

    // Build sigmoid LUT: sharpens the soft confidence fringe
    this._buildSigmoidLUT(0.5, 8);

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
      console.warn('BgBlur: segmenter failed', e);
      this._ready = false;
    }
  },

  // Sigmoid curve: tightens the 0.3-0.7 confidence zone into a crisp edge
  // midpoint: where the 50% transition is (0.5 = centered)
  // steepness: how sharp the cutoff is (6-12 range, higher = sharper)
  _buildSigmoidLUT(midpoint, steepness) {
    this._sigLUT = new Float32Array(256);
    for (let i = 0; i < 256; i++) {
      const x = i / 255;
      this._sigLUT[i] = 1 / (1 + Math.exp(-steepness * (x - midpoint)));
    }
  },

  // Horizontal box blur pass on a float32 array (width x height)
  _blurH(src, dst, w, h, r) {
    const d = r * 2 + 1;
    for (let y = 0; y < h; y++) {
      let sum = 0;
      const off = y * w;
      // Init window
      for (let x = -r; x <= r; x++) sum += src[off + Math.max(0, Math.min(w - 1, x))];
      for (let x = 0; x < w; x++) {
        dst[off + x] = sum / d;
        const left = Math.max(0, x - r);
        const right = Math.min(w - 1, x + r + 1);
        sum += src[off + right] - src[off + left];
      }
    }
  },

  // Vertical box blur pass
  _blurV(src, dst, w, h, r) {
    const d = r * 2 + 1;
    for (let x = 0; x < w; x++) {
      let sum = 0;
      for (let y = -r; y <= r; y++) sum += src[Math.max(0, Math.min(h - 1, y)) * w + x];
      for (let y = 0; y < h; y++) {
        dst[y * w + x] = sum / d;
        const top = Math.max(0, y - r);
        const bot = Math.min(h - 1, y + r + 1);
        sum += src[bot * w + x] - src[top * w + x];
      }
    }
  },

  // Full separable box blur (2-pass)
  _boxBlur(arr, w, h, radius) {
    if (!this._blurBuf || this._blurBuf.length !== arr.length) {
      this._blurBuf = new Float32Array(arr.length);
    }
    this._blurH(arr, this._blurBuf, w, h, radius);
    this._blurV(this._blurBuf, arr, w, h, radius);
  },

  _blurApplied: false,

  activate() {
    this._active = true;
    // Don't blur video yet — wait until first successful render
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

    const rawMask = result.confidenceMasks[0].getAsFloat32Array();

    // Step 1: Apply sigmoid to sharpen the transition band
    const lut = this._sigLUT;
    // PERF: reuse buffer instead of allocating per frame
    if (!this._processedBuf || this._processedBuf.length !== rawMask.length) {
      this._processedBuf = new Float32Array(rawMask.length);
    }
    const processed = this._processedBuf;
    for (let i = 0; i < rawMask.length; i++) {
      processed[i] = lut[rawMask[i] * 255 | 0];
    }

    // Step 2: Box blur for anti-aliased feathering (radius 3)
    this._boxBlur(processed, w, h, 3);

    // Step 3: Apply as alpha channel
    const imgData = this._tmpCtx.getImageData(0, 0, w, h);
    const d = imgData.data;
    const pixels = Math.min(processed.length, d.length / 4);
    for (let i = 0; i < pixels; i++) {
      d[i * 4 + 3] = processed[i] * 255 | 0;
    }

    this._bgCtx.clearRect(0, 0, w, h);
    this._bgCtx.putImageData(imgData, 0, 0);

    // Apply video blur only after first successful segmentation
    if (!this._blurApplied) {
      document.getElementById('cam').style.filter = 'blur(8px) brightness(1.1)';
      this._blurApplied = true;
    }

    result.confidenceMasks[0].close();
  }
};
