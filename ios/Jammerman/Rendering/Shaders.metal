#include <metal_stdlib>
using namespace metal;

// ============================================================================
// Muze — Metal Shaders
// All vertex/fragment shaders for the GPU-accelerated visualizer
// ============================================================================

// MARK: - Shared Types

struct VisualizerUniforms {
    float2 screenSize;
    float time;
    float beatPulse;
    float energy;
    float3 accentColor;
    float2 faceCenter;     // normalized 0..1
    float bloomRadius;
    float haloGlow;
    float haloFlash;
};

// MARK: - Fullscreen Quad (used by vignette, flash, gradients, trail composite)

struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadVertexOut fullscreenQuadVertex(uint vid [[vertex_id]]) {
    // Triangle strip: 0,1,2,3 → full screen quad
    float2 positions[4] = {
        float2(-1, -1), float2(1, -1),
        float2(-1,  1), float2(1,  1)
    };
    float2 uvs[4] = {
        float2(0, 1), float2(1, 1),
        float2(0, 0), float2(1, 0)
    };
    QuadVertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = uvs[vid];
    return out;
}

// MARK: - Particle Rendering (instanced)

struct ParticleInstance {
    float2 position;   // screen pixels
    float size;        // radius in pixels
    float life;        // 0..1
    float4 color;      // RGBA with pre-multiplied alpha
};

struct ParticleVertexOut {
    float4 position [[position]];
    float2 uv;        // -1..1 from center
    float life;
    float4 color;
};

vertex ParticleVertexOut particleVertex(uint vid [[vertex_id]],
                                        uint iid [[instance_id]],
                                        constant ParticleInstance *particles [[buffer(0)]],
                                        constant VisualizerUniforms &uniforms [[buffer(1)]]) {
    ParticleInstance p = particles[iid];

    // Expand point to quad (triangle strip)
    float2 offsets[4] = {
        float2(-1, -1), float2(1, -1),
        float2(-1,  1), float2(1,  1)
    };
    float2 offset = offsets[vid] * p.size;
    float2 screenPos = p.position + offset;

    // Convert screen pixels to clip space (-1..1)
    float2 clip = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    clip.y = -clip.y; // flip Y for Metal

    ParticleVertexOut out;
    out.position = float4(clip, 0, 1);
    out.uv = offsets[vid];
    out.life = p.life;
    out.color = p.color;
    return out;
}

fragment float4 particleFragment(ParticleVertexOut in [[stage_in]]) {
    // Soft radial falloff — the glow effect
    float dist = length(in.uv);
    if (dist > 1.0) discard_fragment();

    // Smooth falloff: bright center, soft edges
    float alpha = 1.0 - smoothstep(0.0, 1.0, dist);
    alpha *= alpha; // quadratic falloff for softer glow
    alpha *= in.life * in.life; // fade with life
    alpha *= in.color.a;
    return float4(in.color.rgb * alpha, alpha);
}

// MARK: - Line Rendering (thick lines via screen-aligned quads)

struct LineVertex {
    float2 position;  // screen pixels
    float2 normal;    // perpendicular direction (unit)
    float alpha;      // per-vertex alpha
};

struct LineVertexOut {
    float4 position [[position]];
    float alpha;
    float edge;       // -1..1 across line width (for soft edges)
};

vertex LineVertexOut lineVertex(uint vid [[vertex_id]],
                                constant LineVertex *vertices [[buffer(0)]],
                                constant VisualizerUniforms &uniforms [[buffer(1)]],
                                constant float &lineWidth [[buffer(2)]]) {
    LineVertex v = vertices[vid];

    // Extrude along normal by half line width
    float side = (vid % 2 == 0) ? -1.0 : 1.0;
    float2 screenPos = v.position + v.normal * lineWidth * 0.5 * side;

    float2 clip = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    clip.y = -clip.y;

    LineVertexOut out;
    out.position = float4(clip, 0, 1);
    out.alpha = v.alpha;
    out.edge = side;
    return out;
}

fragment float4 lineFragment(LineVertexOut in [[stage_in]],
                              constant float4 &color [[buffer(0)]]) {
    // Soft edges for anti-aliasing
    float edgeFade = 1.0 - smoothstep(0.6, 1.0, abs(in.edge));
    float a = color.a * in.alpha * edgeFade;
    return float4(color.rgb * a, a);
}

// MARK: - Radial Gradient (for halos, iris glow, landmarks, explosion)

struct GradientParams {
    float2 center;     // screen pixels
    float innerRadius;
    float outerRadius;
    float4 innerColor;
    float4 outerColor;
};

fragment float4 radialGradientFragment(QuadVertexOut in [[stage_in]],
                                        constant GradientParams &params [[buffer(0)]],
                                        constant VisualizerUniforms &uniforms [[buffer(1)]]) {
    float2 fragPos = in.uv * uniforms.screenSize;
    float dist = length(fragPos - params.center);

    float t = saturate((dist - params.innerRadius) / max(params.outerRadius - params.innerRadius, 0.001));
    float4 color = mix(params.innerColor, params.outerColor, t);
    return float4(color.rgb * color.a, color.a);
}

// MARK: - Vignette

fragment float4 vignetteFragment(QuadVertexOut in [[stage_in]],
                                  constant VisualizerUniforms &uniforms [[buffer(0)]]) {
    float2 center = float2(0.5, 0.5);
    float dist = length(in.uv - center) / 0.707; // normalize to corner distance

    // 4-stop gradient: 0→0, 0.5→0, 0.8→0.15, 1.0→0.4
    float alpha = 0.0;
    if (dist > 0.5) {
        float t = (dist - 0.5) / 0.5;
        alpha = mix(0.0, 0.4, smoothstep(0.0, 1.0, t));
    }

    return float4(0, 0, 0, alpha);
}

// MARK: - Beat Flash

fragment float4 beatFlashFragment(QuadVertexOut in [[stage_in]],
                                   constant VisualizerUniforms &uniforms [[buffer(0)]]) {
    if (uniforms.beatPulse < 0.4) discard_fragment();
    float flashAlpha = (uniforms.beatPulse - 0.4) * 0.15;
    float3 flashColor = uniforms.accentColor * 0.3 + 0.7;
    return float4(flashColor * flashAlpha, flashAlpha);
}

// MARK: - Trail Composite (sample trail texture, additive blend)

fragment float4 trailCompositeFragment(QuadVertexOut in [[stage_in]],
                                        texture2d<float> trailTex [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    return trailTex.sample(s, in.uv);
}

// MARK: - Trail Fade (multiply alpha to create long-exposure decay)

fragment float4 trailFadeFragment(QuadVertexOut in [[stage_in]],
                                   texture2d<float> trailTex [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    float4 color = trailTex.sample(s, in.uv);
    return color * float4(1, 1, 1, 0.975); // 2.5% decay per frame
}

// MARK: - Person Segmentation Darken

fragment float4 segDarkenFragment(QuadVertexOut in [[stage_in]],
                                   texture2d<float> segMask [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    float2 uv = float2(1.0 - in.uv.x, in.uv.y); // mirror X for front camera
    float person = segMask.sample(s, uv).r;

    // Darken background (where person < 0.5), person area stays transparent
    float bgAlpha = (1.0 - smoothstep(0.3, 0.7, person)) * 0.55;
    return float4(0, 0, 0, bgAlpha);
}

// MARK: - Person Segmentation Cutout (destinationOut equivalent)

fragment float4 segCutoutFragment(QuadVertexOut in [[stage_in]],
                                   texture2d<float> segMask [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    float2 uv = float2(1.0 - in.uv.x, in.uv.y); // mirror X
    float person = segMask.sample(s, uv).r;

    // Output person alpha — used with destinationOut-like blend to erase person area
    float cutout = smoothstep(0.3, 0.7, person);
    return float4(cutout, cutout, cutout, cutout);
}

// MARK: - Ellipse/Ring (for shockwaves, halo rings)

struct EllipseInstance {
    float2 center;     // screen pixels
    float2 radii;      // x radius, y radius
    float lineWidth;
    float4 color;
};

struct EllipseVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float lineWidth;
    float2 radii;
};

vertex EllipseVertexOut ellipseVertex(uint vid [[vertex_id]],
                                      uint iid [[instance_id]],
                                      constant EllipseInstance *ellipses [[buffer(0)]],
                                      constant VisualizerUniforms &uniforms [[buffer(1)]]) {
    EllipseInstance e = ellipses[iid];

    float2 offsets[4] = {
        float2(-1, -1), float2(1, -1),
        float2(-1,  1), float2(1,  1)
    };
    float margin = e.lineWidth + 2.0; // extra for anti-aliasing
    float2 screenPos = e.center + offsets[vid] * (e.radii + margin);

    float2 clip = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    clip.y = -clip.y;

    EllipseVertexOut out;
    out.position = float4(clip, 0, 1);
    out.uv = offsets[vid] * (e.radii + margin);
    out.color = e.color;
    out.lineWidth = e.lineWidth;
    out.radii = e.radii;
    return out;
}

fragment float4 ellipseFragment(EllipseVertexOut in [[stage_in]]) {
    // Ellipse SDF
    float2 p = in.uv / in.radii;
    float d = length(p) - 1.0;
    float pixelDist = d * min(in.radii.x, in.radii.y);

    // Ring: visible near the edge
    float halfWidth = in.lineWidth * 0.5;
    float ring = 1.0 - smoothstep(halfWidth - 1.0, halfWidth + 1.0, abs(pixelDist));

    float a = ring * in.color.a;
    if (a < 0.001) discard_fragment();
    return float4(in.color.rgb * a, a);
}
