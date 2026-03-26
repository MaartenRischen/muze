/* ============================================================
   MUZE — Camera & Body Tracking
   ============================================================ */

// ---- Camera ----
MUZE.Camera = {
  video: null, stream: null, available: false,
  async init() {
    this.video = document.getElementById('cam');
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      console.warn('Camera API unavailable. Secure context:', window.isSecureContext, 'Protocol:', location.protocol);
      this.available = false;
      return; // Continue without camera — app still works for touch/synth
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 }, frameRate: { ideal: 30 } },
        audio: false
      });
      this.video.srcObject = this.stream;
      await new Promise(r => { this.video.onloadedmetadata = r; });
      await this.video.play();
      this.available = true;
    } catch (e) {
      console.warn('Camera init failed:', e.message);
      this.available = false;
    }
  }
};

// ---- Face Tracker ----
MUZE.FaceTracker = {
  landmarker: null,
  async init(FL, vision) {
    this.landmarker = await FL.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task',
        delegate: 'GPU'
      },
      runningMode: 'VIDEO', numFaces: 1,
      outputFaceBlendshapes: false,
      outputFacialTransformationMatrixes: false
    });
  },
  detect(video, ts) {
    if (!this.landmarker) return null;
    try { return this.landmarker.detectForVideo(video, ts); }
    catch (e) { return null; }
  }
};

// ---- Hand Tracker ----
MUZE.HandTracker = {
  landmarker: null,
  async init(HL, vision) {
    this.landmarker = await HL.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task',
        delegate: 'GPU'
      },
      runningMode: 'VIDEO', numHands: 1,
      minHandDetectionConfidence: 0.35,
      minTrackingConfidence: 0.3
    });
  },
  detect(video, ts) {
    if (!this.landmarker) return null;
    try { return this.landmarker.detectForVideo(video, ts); }
    catch (e) { return null; }
  }
};

// ---- Face Feature Extraction ----
MUZE.FaceFeatures = {
  // Named landmark indices
  LM: {
    UPPER_LIP: 13, LOWER_LIP: 14,
    LEFT_MOUTH: 61, RIGHT_MOUTH: 291,
    R_EYE_TOP: 159, R_EYE_BOT: 145,
    L_EYE_TOP: 386, L_EYE_BOT: 374,
    R_BROW: 105, L_BROW: 334,
    NOSE_TIP: 1, FOREHEAD: 10, CHIN: 152,
    L_EAR: 234, R_EAR: 454
  },

  extract(landmarks) {
    const L = this.LM, C = MUZE.Config;
    const faceHeight = this._dist3d(landmarks[L.FOREHEAD], landmarks[L.CHIN]);
    if (faceHeight < 0.001) return null;

    // Mouth openness (0-1)
    const mouthOpen = this._clamp01(this._remap(
      this._dist3d(landmarks[L.UPPER_LIP], landmarks[L.LOWER_LIP]) / faceHeight,
      C.MOUTH_OPEN_MIN, C.MOUTH_OPEN_MAX
    ));

    // Lip corner (smile/frown) (-1 to +1)
    const midMouthY = (landmarks[L.UPPER_LIP].y + landmarks[L.LOWER_LIP].y) / 2;
    const lipCorner = this._clamp(this._remap(
      ((midMouthY - landmarks[L.LEFT_MOUTH].y) + (midMouthY - landmarks[L.RIGHT_MOUTH].y)) / 2 / faceHeight,
      C.LIP_SMILE_MIN, C.LIP_SMILE_MAX
    ), -1, 1);

    // Brow height (0-1)
    const browNorm = (
      Math.abs(landmarks[L.R_BROW].y - landmarks[L.R_EYE_TOP].y) +
      Math.abs(landmarks[L.L_BROW].y - landmarks[L.L_EYE_TOP].y)
    ) / 2 / faceHeight;
    MUZE.State._browRaw = browNorm;
    const browHeight = this._clamp01(this._remap(browNorm, C.BROW_MIN, C.BROW_MAX));

    // Eye openness (0-1)
    const eyeOpenness = this._clamp01(this._remap(
      (this._dist3d(landmarks[L.R_EYE_TOP], landmarks[L.R_EYE_BOT]) +
       this._dist3d(landmarks[L.L_EYE_TOP], landmarks[L.L_EYE_BOT])) / 2 / faceHeight,
      C.EYE_OPEN_MIN, C.EYE_OPEN_MAX
    ));

    // Mouth width (0-1)
    const mouthWidth = this._clamp01(this._remap(
      this._dist2d(landmarks[L.LEFT_MOUTH], landmarks[L.RIGHT_MOUTH]) / faceHeight,
      C.MOUTH_WIDTH_MIN, C.MOUTH_WIDTH_MAX
    ));

    // Head rotation
    const headYaw = Math.atan2(
      this._dist2d(landmarks[L.NOSE_TIP], landmarks[L.L_EAR]) -
      this._dist2d(landmarks[L.NOSE_TIP], landmarks[L.R_EAR]),
      faceHeight
    );
    const headPitch = (landmarks[L.NOSE_TIP].y -
      (landmarks[L.FOREHEAD].y + landmarks[L.CHIN].y) / 2) / faceHeight * Math.PI * 0.5;
    const headRoll = Math.atan2(
      landmarks[L.L_EAR].y - landmarks[L.R_EAR].y,
      landmarks[L.L_EAR].x - landmarks[L.R_EAR].x
    );

    return { mouthOpenness: mouthOpen, lipCorner, browHeight, eyeOpenness, mouthWidth, headPitch, headYaw, headRoll };
  },

  _dist3d(a, b) { return Math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2 + ((a.z||0)-(b.z||0))**2); },
  _dist2d(a, b) { return Math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2); },
  _remap(v, min, max) { return (v - min) / (max - min); },
  _clamp01(v) { return Math.max(0, Math.min(1, v)); },
  _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
};

// ---- Hand Feature Extraction ----
MUZE.HandFeatures = {
  extract(landmarks) {
    if (!landmarks || !landmarks.length) {
      return { handPresent: false, handY: 0.5, handX: 0.5, handOpen: true };
    }
    const lm = landmarks[0];
    const handX = (lm[0].x + lm[9].x) / 2;
    const handY = (lm[0].y + lm[9].y) / 2;
    const palmSize = this._dist3d(lm[0], lm[9]);
    const avgFingerDist = (
      this._dist3d(lm[8], lm[0]) + this._dist3d(lm[12], lm[0]) +
      this._dist3d(lm[16], lm[0]) + this._dist3d(lm[20], lm[0])
    ) / 4;
    const ratio = avgFingerDist / palmSize;
    // Hysteresis: need to cross 1.85 to open, 1.55 to close
    if (this._lastOpen === undefined) this._lastOpen = ratio > 1.7;
    const open = this._lastOpen ? (ratio > 1.55) : (ratio > 1.85);
    this._lastOpen = open;
    return {
      handPresent: true,
      handX: 1 - handX,
      handY: handY,
      handOpen: open
    };
  },
  _dist3d(a, b) { return Math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2 + ((a.z||0)-(b.z||0))**2); }
};
