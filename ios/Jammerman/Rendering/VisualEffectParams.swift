// Muze — Visual Effect Parameters
// Per-effect mute + tunable params for dev finetuning

import Foundation

class VisualEffectParams: ObservableObject {

    // MARK: - Effect Mute States
    @Published var ringEnabled = true
    @Published var haloEnabled = true
    @Published var particlesEnabled = true
    @Published var irisEnabled = true
    @Published var landmarksEnabled = true
    @Published var modeGeoEnabled = true
    @Published var freqArcEnabled = true
    @Published var connectionWebEnabled = true
    @Published var arpVizEnabled = true
    @Published var trailEnabled = true
    @Published var segEnabled = true
    @Published var vignetteEnabled = true
    @Published var burstEnabled = true
    @Published var ghostTrailsEnabled = true

    // MARK: - Ring Params
    @Published var ringRadius: Float = 0.18        // fraction of min(w,h)
    @Published var ringWobble: Float = 1.0         // wobble intensity multiplier
    @Published var ringGlowWidth: Float = 14       // widest glow pass width (points)
    @Published var ringCoreWidth: Float = 1.0      // thinnest core pass width (points)
    @Published var ringAlpha: Float = 0.5          // peak core alpha

    // MARK: - Halo Params
    @Published var haloOffsetY: Float = 0.18       // fraction of h above nose
    @Published var haloSize: Float = 0.7           // fraction of w
    @Published var haloAlpha: Float = 0.3          // base ambient alpha
    @Published var haloInnerAlpha: Float = 0.4     // inner core alpha
    @Published var haloFlashAlpha: Float = 0.5     // beat flash alpha

    // MARK: - Particle Params
    @Published var particleCount: Int = 50
    @Published var particleSize: Float = 3.0       // base size multiplier
    @Published var particleAlpha: Float = 0.5      // alpha multiplier
    @Published var particleSpawnRate: Float = 12    // spawn per second at max energy

    // MARK: - Iris Params
    @Published var irisSize: Float = 10            // base radius (points)
    @Published var irisAlpha: Float = 0.5          // peak alpha
    @Published var irisPulse: Float = 1.8          // beat pulse scale

    // MARK: - Landmark Params
    @Published var landmarkSize: Float = 5         // base radius (points)
    @Published var landmarkAlpha: Float = 0.4      // peak alpha

    // MARK: - Mode Geometry Params
    @Published var modeGeoAlpha: Float = 0.02      // line alpha

    // MARK: - Frequency Arc Params
    @Published var freqArcBarWidth: Float = 4      // bar width (points)
    @Published var freqArcHeight: Float = 40       // max bar height (points)
    @Published var freqArcRadius: Float = 0.4      // arc radius fraction of w
    @Published var freqArcY: Float = 0.92          // Y position fraction of h

    // MARK: - Connection Web Params
    @Published var webAlpha: Float = 0.15          // base line alpha
    @Published var webLineWidth: Float = 1.5       // line width (points)

    // MARK: - Arp Viz Params
    @Published var arpGlowSize: Float = 12         // active note glow (points)
    @Published var arpDotSize: Float = 3           // inactive dot size (points)
    @Published var arpColumnHeight: Float = 280    // column height (points)

    // MARK: - Trail Params
    @Published var trailCoreWidth: Float = 4       // core line width (points)
    @Published var trailGlowMult: Float = 2.0      // glow width multiplier
    @Published var trailCoreAlpha: Float = 0.9
    @Published var trailGlowAlpha: Float = 0.3
    @Published var trailDecay: Float = 0.975       // per-frame alpha retention

    // MARK: - Segmentation Params
    @Published var segDarkenAlpha: Float = 0.65
    @Published var segFeather: Float = -8
    @Published var segScaleX: Float = 0.63
    @Published var segScaleY: Float = 0.99
    @Published var segEdgeLow: Float = 0.25
    @Published var segEdgeHigh: Float = 0.75

    // MARK: - Vignette Params
    @Published var vignetteStrength: Float = 0.4   // max darkness at corners

    // MARK: - Burst Params
    @Published var burstCount: Int = 15            // particles per burst
    @Published var burstSize: Float = 2.0          // particle size mult

    // MARK: - Ghost Trail Params
    @Published var ghostCount: Int = 4             // max snapshots
    @Published var ghostDecay: Float = 0.88        // opacity decay per frame
}
