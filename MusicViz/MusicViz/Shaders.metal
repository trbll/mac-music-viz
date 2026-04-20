#include <metal_stdlib>
using namespace metal;

struct AudioUniforms {
    float time;
    float beat;
    float2 resolution;
    float bass;
    float mid;
    float treble;
    float loudness;
};

// Mirrors Swift `PresetParams` in ParamStore.swift.
// Four float4 slots hold 16 scalar params, then four float4 colors.
struct PresetParams {
    float4 p0;
    float4 p1;
    float4 p2;
    float4 p3;
    float4 c0;
    float4 c1;
    float4 c2;
    float4 c3;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
};

// Big-triangle fullscreen pass
vertex VOut vertex_fullscreen(uint vid [[vertex_id]]) {
    float2 p = float2((vid == 2) ? 3.0 : -1.0,
                      (vid == 1) ? 3.0 : -1.0);
    VOut o;
    o.position = float4(p, 0.0, 1.0);
    o.uv = p * 0.5 + 0.5;
    o.uv.y = 1.0 - o.uv.y;
    return o;
}

// ---------- palette helpers ----------

// Procedural IQ-style palette. Kept for shaders that want a default cyclic
// color without asking the user. Presets normally use palette2/3/4Cyc below.
[[maybe_unused]] static inline float3 palette(float t) {
    const float3 a = float3(0.5, 0.5, 0.5);
    const float3 b = float3(0.5, 0.5, 0.5);
    const float3 c = float3(1.0, 1.0, 1.0);
    const float3 d = float3(0.00, 0.33, 0.67);
    return a + b * cos(6.2831853 * (c * t + d));
}

// 2-stop linear gradient. t is clamped to [0, 1].
[[maybe_unused]] static inline float3 palette2(float t, float3 c0, float3 c1) {
    return mix(c0, c1, clamp(t, 0.0, 1.0));
}

// 3-stop linear palette. t ∈ [0, 1] is split into two equal segments.
[[maybe_unused]] static inline float3 palette3(float t, float3 c0, float3 c1, float3 c2) {
    t = clamp(t, 0.0, 1.0) * 2.0;
    float f = fract(t);
    return (t < 1.0) ? mix(c0, c1, f) : mix(c1, c2, f);
}

// 4-stop linear palette. t ∈ [0, 1] split into three equal segments.
[[maybe_unused]] static inline float3 palette4Lin(float t, float3 c0, float3 c1, float3 c2, float3 c3) {
    t = clamp(t, 0.0, 1.0) * 3.0;
    int i = clamp(int(floor(t)), 0, 2);
    float f = t - float(i);
    if (i == 0) return mix(c0, c1, f);
    if (i == 1) return mix(c1, c2, f);
    return mix(c2, c3, f);
}

// 4-stop cyclic palette. t wraps; good for continuous color flow.
[[maybe_unused]] static inline float3 palette4Cyc(float t, float3 c0, float3 c1, float3 c2, float3 c3) {
    t = fract(t) * 4.0;
    int i = int(floor(t)) % 4;
    float f = fract(t);
    if (i == 0) return mix(c0, c1, f);
    if (i == 1) return mix(c1, c2, f);
    if (i == 2) return mix(c2, c3, f);
    return mix(c3, c0, f);
}

[[maybe_unused]] static inline float2 rotate2(float2 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[[maybe_unused]] static inline float hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

[[maybe_unused]] static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

[[maybe_unused]] static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

[[maybe_unused]] static inline float fbm4(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += valueNoise(p) * amp;
        p = rotate2(p * 2.03, 0.58);
        amp *= 0.5;
    }
    return v;
}

[[maybe_unused]] static inline float segmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

// ---------- 1. Plasma ----------
// params: p0.x=scale, p0.y=speed, p0.z=bassReact, p0.w=brightness
// colors: c0..c3 = 4-stop cyclic palette
fragment float4 fragment_plasma(VOut in [[stage_in]],
                                constant AudioUniforms& u [[buffer(0)]],
                                constant PresetParams& p [[buffer(1)]]) {
    float scale      = p.p0.x;
    float speed      = p.p0.y;
    float bassReact  = p.p0.z;
    float brightness = p.p0.w;

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = (in.uv * 2.0 - 1.0);
    uv.x *= aspect;

    float t = u.time * speed + u.loudness * 2.0;
    float v = 0.0;
    v += sin(uv.x * scale + t);
    v += sin(uv.y * scale + t * 1.3);
    v += sin((uv.x + uv.y) * scale + t * 0.7);
    v += sin(length(uv * scale + float2(sin(t * 0.5), cos(t * 0.4))) - t * 2.0);
    v *= 0.25;
    v += u.bass * bassReact;

    float phase = v * 0.5 + 0.5 + u.beat * 0.1;
    float3 col = palette4Cyc(phase, p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb);
    col *= brightness * (0.55 + 0.45 * (u.loudness + u.beat * 0.4));
    return float4(col, 1.0);
}

// ---------- 2. Tunnel ----------
// params: p0.x=ringSpeed, p0.y=spokes, p0.z=beatPunch, p0.w=bassReact
// colors: c0..c3 = 4-stop cyclic palette
fragment float4 fragment_tunnel(VOut in [[stage_in]],
                                constant AudioUniforms& u [[buffer(0)]],
                                constant PresetParams& p [[buffer(1)]]) {
    float ringSpeed = p.p0.x;
    float spokes    = max(1.0, p.p0.y);
    float beatPunch = p.p0.z;
    float bassReact = p.p0.w;

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    float r = length(uv);
    float a = atan2(uv.y, uv.x);
    float depth = 1.0 / max(r, 0.01);
    float t = u.time * 0.5;

    float rings  = sin(depth * 3.0 - t * ringSpeed - u.bass * 5.0 * bassReact);
    float sp     = sin(a * spokes + t * 1.3);
    float v = rings * 0.55 + sp * 0.3;

    float3 col = palette4Cyc(depth * 0.12 + t * 0.07,
                             p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb);
    col *= 0.4 + 0.6 * (v * 0.5 + 0.5);
    col *= smoothstep(0.0, 0.25, r);
    col *= 1.0 + u.beat * beatPunch;
    return float4(col, 1.0);
}

// ---------- 3. Spectrum bars ----------
// params: p0.x=gain, p0.y=peak, p0.z=floorGlow
// colors: c0..c2 = 3-stop palette across x (low → high freq)
fragment float4 fragment_bars(VOut in [[stage_in]],
                              constant AudioUniforms& u [[buffer(0)]],
                              constant PresetParams& p [[buffer(1)]],
                              texture2d<float> spec [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float gain     = p.p0.x;
    float peakAmt  = p.p0.y;
    float floorAmt = p.p0.z;

    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;

    float mag = spec.sample(s, float2(uv.x, 0.5)).r;
    float h = mag * gain;
    float below = step(uv.y, h);

    float3 barCol = palette3(uv.x, p.c0.rgb, p.c1.rgb, p.c2.rgb);
    float3 col = barCol * below;

    float peak = smoothstep(h - 0.008, h, uv.y) * step(uv.y, h + 0.002);
    col += peak * peakAmt;

    col += barCol * 0.15 * exp(-uv.y * 5.0) * (0.2 + u.loudness) * floorAmt;
    return float4(col, 1.0);
}

// ---------- 4. Oscilloscope ----------
// params: p0.x=thickness, p0.y=glow, p0.z=scanlines(0/1), p0.w=grid(0/1)
// colors: c0 = trace, c1 = glow/grid tint
fragment float4 fragment_oscilloscope(VOut in [[stage_in]],
                                      constant AudioUniforms& u [[buffer(0)]],
                                      constant PresetParams& p [[buffer(1)]],
                                      texture2d<float> spec [[texture(0)]],
                                      texture2d<float> wave [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float thickness = max(0.1, p.p0.x);
    float glowAmt   = p.p0.y;
    float scanlines = step(0.5, p.p0.z);
    float grid      = step(0.5, p.p0.w);
    float3 trace    = p.c0.rgb;
    float3 glowCol  = p.c1.rgb;

    float2 uv = in.uv;

    float w = wave.sample(s, float2(uv.x, 0.5)).r;
    float lineY = 0.5 + w * 0.42;
    float d = abs(uv.y - lineY);

    float core = exp(-d * (180.0 / thickness));
    float glow = exp(-d * (22.0 / thickness)) * 0.35 * glowAmt;
    float3 col = trace * core + glowCol * glow;

    float gx = smoothstep(0.98, 1.0, sin(uv.x * 40.0 + 1.5708) * 0.5 + 0.5);
    float gy = smoothstep(0.98, 1.0, sin(uv.y * 28.0 + 1.5708) * 0.5 + 0.5);
    col += glowCol * 0.35 * (gx + gy) * grid;

    float scan = 0.82 + 0.18 * (0.5 + 0.5 * sin(uv.y * u.resolution.y * 3.14159));
    col *= mix(1.0, scan, scanlines);
    col *= 1.0 + u.beat * 0.4;
    return float4(col, 1.0);
}

// ---------- 5. Apple Bloom ----------
// params: p0.x=blobCount, p0.y=speed, p0.z=bassReact, p0.w=gamma
// colors: c0..c3 = 4-stop cyclic palette indexed by blob
fragment float4 fragment_bloom(VOut in [[stage_in]],
                               constant AudioUniforms& u [[buffer(0)]],
                               constant PresetParams& p [[buffer(1)]]) {
    int blobCount  = int(clamp(p.p0.x, 1.0, 12.0));
    float speed    = p.p0.y;
    float bassReact= p.p0.z;
    float gamma    = max(0.1, p.p0.w);

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv - 0.5;
    uv.x *= aspect;

    float t = u.time * speed;
    float3 col = float3(0.0);

    for (int i = 0; i < blobCount; i++) {
        float fi = float(i);
        float2 c = float2(sin(t * (0.6 + fi * 0.11) + fi),
                          cos(t * (0.45 + fi * 0.17) - fi * 0.7)) * 0.45;
        float d = length(uv - c);
        float r = 0.30 + 0.10 * sin(t + fi) + u.bass * bassReact + u.beat * 0.08;
        float blob = smoothstep(r, r - 0.35, d);
        float3 blobCol = palette4Cyc(fi / max(float(blobCount), 1.0) + u.time * 0.04,
                                     p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb);
        col += blobCol * blob * 0.55;
    }
    col *= 1.0 - length(uv) * 0.4;
    col = pow(col, float3(gamma));
    return float4(col, 1.0);
}

// ---------- 6. Chladni Plate ----------
// params: p0.x=modeX, p0.y=modeY, p0.z=lineSharpness, p0.w=beatFlash, p1.x=drift, p1.y=scale
// colors: c0..c2 = plate shadow, nodal line, beat highlight
fragment float4 fragment_chladni(VOut in [[stage_in]],
                                 constant AudioUniforms& u [[buffer(0)]],
                                 constant PresetParams& p [[buffer(1)]]) {
    float modeX     = max(1.0, p.p0.x + u.mid * 1.25);
    float modeY     = max(1.0, p.p0.y + u.treble * 1.50);
    float sharpness = max(1.0, p.p0.z);
    float beatFlash = p.p0.w;
    float drift     = p.p1.x;
    float scale     = max(0.1, p.p1.y);

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;
    uv *= scale;
    uv = rotate2(uv, sin(u.time * drift * 0.18) * 0.32);

    float t = u.time * drift + u.bass * 0.65;
    float x = uv.x + sin(t + uv.y * 2.1) * 0.055 * drift;
    float y = uv.y + cos(t * 1.2 + uv.x * 1.7) * 0.055 * drift;

    float a = sin(modeX * 3.1415926 * x + t) * sin(modeY * 3.1415926 * y - t * 0.7);
    float b = sin(modeY * 3.1415926 * x - t * 0.5) * sin(modeX * 3.1415926 * y + t * 0.8);
    float v = a - b;

    float line = exp(-abs(v) * sharpness * (0.65 + u.loudness * 0.45));
    float ghost = exp(-abs(v) * sharpness * 0.15) * 0.20;
    float vignette = 1.0 - smoothstep(0.75, 1.45, length(uv));

    float highlight = clamp(line + u.beat * 0.28, 0.0, 1.0);
    float3 col = p.c0.rgb * (0.18 + ghost);
    col += mix(p.c1.rgb, p.c2.rgb, highlight) * line * (1.0 + u.beat * beatFlash);
    col += p.c1.rgb * ghost * (0.35 + u.treble * 0.35);
    col *= vignette;
    return float4(col, 1.0);
}

// ---------- 7. Aurora Ribbon ----------
// params: p0.x=layers, p0.y=flowSpeed, p0.z=gain, p0.w=shimmer, p1.x=haze
// colors: c0..c3 = horizon shadow and aurora stops
fragment float4 fragment_aurora(VOut in [[stage_in]],
                                constant AudioUniforms& u [[buffer(0)]],
                                constant PresetParams& p [[buffer(1)]],
                                texture2d<float> spec [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    int layers    = int(clamp(p.p0.x, 1.0, 12.0));
    float speed   = p.p0.y;
    float gain    = p.p0.z;
    float shimmer = p.p0.w;
    float haze    = p.p1.x;

    float2 uv = in.uv;
    float t = u.time * speed;
    float3 col = p.c0.rgb * (0.22 + 0.36 * (1.0 - uv.y));

    for (int i = 0; i < 12; i++) {
        if (i >= layers) { break; }
        float fi = float(i);
        float denom = max(float(layers - 1), 1.0);
        float layerT = fi / denom;
        float sampleX = fract(uv.x * (0.72 + fi * 0.055) + layerT * 0.23 + t * (0.08 + fi * 0.015));
        float mag = spec.sample(s, float2(sampleX, 0.5)).r * gain;

        float wave = sin(uv.x * (5.0 + fi * 1.4) + t * (1.2 + layerT) + sin(uv.x * 3.0 + fi));
        wave += 0.45 * sin(uv.x * (13.0 + fi) - t * (0.7 + fi * 0.08));
        float y = 0.70 - layerT * 0.46 + wave * 0.035 - mag * 0.18 - u.beat * 0.035;
        float width = 0.030 + mag * 0.075 + u.bass * 0.020;
        float d = abs(uv.y - y);
        float core = exp(-(d * d) / max(width * width, 1e-4));
        float curtain = exp(-max(uv.y - y, 0.0) * (3.0 + fi * 0.28)) * step(y, uv.y);
        float sparkle = 0.78 + 0.22 * sin(uv.x * 180.0 + t * 18.0 + fi * 9.1);

        float3 ribbon = palette4Lin(layerT + mag * 0.16 + u.time * 0.025,
                                    p.c1.rgb, p.c2.rgb, p.c3.rgb, p.c1.rgb);
        col += ribbon * core * (0.34 + mag * 1.2) * mix(1.0, sparkle, shimmer);
        col += ribbon * curtain * haze * (0.055 + mag * 0.10);
    }

    col += p.c2.rgb * exp(-uv.y * 5.0) * u.loudness * 0.12;
    return float4(col, 1.0);
}

// ---------- 8. Kaleidoscope Prism ----------
// params: p0.x=segments, p0.y=rotation, p0.z=warp, p0.w=beatPunch, p1.x=prism
// colors: c0..c3 = 4-stop cyclic palette
fragment float4 fragment_kaleidoscope(VOut in [[stage_in]],
                                      constant AudioUniforms& u [[buffer(0)]],
                                      constant PresetParams& p [[buffer(1)]],
                                      texture2d<float> spec [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float segments  = max(3.0, p.p0.x);
    float rotation  = p.p0.y;
    float warp      = p.p0.z;
    float beatPunch = p.p0.w;
    float prism     = p.p1.x;

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    float r = length(uv);
    float a = atan2(uv.y, uv.x) + u.time * rotation + u.bass * 0.35;
    float slice = 6.2831853 / segments;
    float folded = abs(fract(a / slice + 0.5) - 0.5) * 2.0;
    float sampleX = fract(r * 0.72 + folded * 0.38 + u.time * 0.025);
    float mag = spec.sample(s, float2(sampleX, 0.5)).r;

    float radial = r * (10.0 + warp * 8.0) - u.time * (1.5 + rotation) + mag * warp * 8.0;
    float facets = sin(radial) * 0.45 + sin(folded * segments * 3.1415926 + radial * 0.45) * 0.35;
    float edge = smoothstep(0.95, 1.0, folded) + smoothstep(0.02, 0.0, folded);
    float glow = 0.42 + 0.58 * (facets * 0.5 + 0.5);

    float phase = r * 0.55 + folded * 0.35 + facets * 0.10 + u.time * 0.035 + mag * 0.20;
    float offset = prism * (0.035 + mag * 0.025 + u.treble * 0.015);
    float3 col;
    col.r = palette4Cyc(phase + offset, p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb).r;
    col.g = palette4Cyc(phase, p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb).g;
    col.b = palette4Cyc(phase - offset, p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb).b;

    col *= glow * (0.55 + mag * 1.8 + u.loudness * 0.45);
    col += (p.c1.rgb + p.c2.rgb) * edge * 0.10;
    col *= 1.0 - smoothstep(1.35, 1.85, r);
    col *= 1.0 + u.beat * beatPunch;
    return float4(col, 1.0);
}

// ---------- 9. Topographic Pulse ----------
// params: p0.x=contours, p0.y=terrainScale, p0.z=drift, p0.w=shockwave, p1.x=lineWidth
// colors: c0..c3 = elevation palette
fragment float4 fragment_topographic(VOut in [[stage_in]],
                                     constant AudioUniforms& u [[buffer(0)]],
                                     constant PresetParams& p [[buffer(1)]],
                                     texture2d<float> spec [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float contours  = max(1.0, p.p0.x);
    float scale     = p.p0.y;
    float drift     = p.p0.z;
    float shockwave = p.p0.w;
    float lineWidth = p.p1.x;

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    float t = u.time * drift;
    float2 q = uv * scale + float2(t * 0.33, -t * 0.21);
    float terrain = fbm4(q);
    terrain += 0.18 * sin(q.x * 1.7 + t + u.mid * 2.0);
    terrain += 0.12 * sin(q.y * 2.3 - t * 0.8 + u.treble * 3.0);

    float r = length(uv);
    float mag = spec.sample(s, float2(clamp(r, 0.0, 1.0), 0.5)).r;
    terrain += mag * 0.45 + u.bass * 0.12;

    float shockR = fract(u.time * 0.08) * 1.35;
    float shock = exp(-abs(r - shockR) * 18.0) * (u.beat + mag * 0.35) * shockwave;
    float height = clamp(terrain * 0.72 + shock * 0.18, 0.0, 1.0);

    float contourValue = height * contours + shock;
    float f = fract(contourValue);
    float d = min(f, 1.0 - f);
    float width = max(0.003, lineWidth * 0.016);
    float line = smoothstep(width, 0.0, d);

    float3 land = palette4Lin(height, p.c0.rgb, p.c1.rgb, p.c2.rgb, p.c3.rgb);
    float3 col = mix(p.c0.rgb * 0.45, land, 0.42 + height * 0.58);
    col = mix(col, p.c3.rgb, line * (0.70 + u.treble * 0.30));
    col += p.c1.rgb * shock * 0.18;
    col *= 1.0 - smoothstep(1.25, 1.85, r) * 0.40;
    return float4(col, 1.0);
}

// ---------- 10. Spectral Constellation ----------
// params: p0.x=density, p0.y=spiral, p0.z=connectionGlow, p0.w=speed, p1.x=sparkle
// colors: c0..c2 = low, mid, high frequency stars
fragment float4 fragment_constellation(VOut in [[stage_in]],
                                       constant AudioUniforms& u [[buffer(0)]],
                                       constant PresetParams& p [[buffer(1)]],
                                       texture2d<float> spec [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    int density       = int(clamp(p.p0.x, 8.0, 128.0));
    float spiral      = p.p0.y;
    float connectGlow = p.p0.z;
    float speed       = p.p0.w;
    float sparkleAmt  = p.p1.x;

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    float t = u.time * speed;
    float3 col = float3(0.004, 0.006, 0.012) * (1.0 + u.loudness);

    for (int i = 0; i < 128; i++) {
        if (i >= density) { break; }
        float fi = float(i);
        float count = max(float(density), 1.0);
        float freq = (fi + 0.5) / count;
        float mag = spec.sample(s, float2(freq, 0.5)).r;

        float angle = fi * 2.3999632 + spiral * freq * 6.2831853 + t * (0.35 + freq) + u.bass * 0.35;
        float radius = 0.07 + pow(freq, 0.72) * 0.82 + mag * 0.085 + sin(t + fi * 1.7) * 0.010;
        float2 pos = float2(cos(angle), sin(angle)) * radius;

        float size = 0.008 + mag * 0.034 + u.treble * 0.004;
        float d = length(uv - pos);
        float star = exp(-(d * d) / max(size * size, 1e-5));
        float twinkle = 0.76 + 0.24 * sin(t * 22.0 + hash11(fi * 17.23) * 6.2831853);
        float3 starCol = palette3(freq + mag * 0.20, p.c0.rgb, p.c1.rgb, p.c2.rgb);
        col += starCol * star * (0.50 + mag * 3.0 + u.beat * 0.45) * mix(1.0, twinkle, sparkleAmt);

        if (i > 0) {
            float pf = (fi - 0.5) / count;
            float pmag = spec.sample(s, float2(pf, 0.5)).r;
            float pangle = (fi - 1.0) * 2.3999632 + spiral * pf * 6.2831853 + t * (0.35 + pf) + u.bass * 0.35;
            float pradius = 0.07 + pow(pf, 0.72) * 0.82 + pmag * 0.085 + sin(t + (fi - 1.0) * 1.7) * 0.010;
            float2 prev = float2(cos(pangle), sin(pangle)) * pradius;
            float lineD = segmentDistance(uv, prev, pos);
            float line = exp(-lineD * 120.0) * min(mag, pmag) * connectGlow;
            col += mix(starCol, p.c1.rgb, 0.45) * line * 0.34;
        }
    }

    col += p.c1.rgb * exp(-length(uv) * 3.2) * u.loudness * 0.08;
    return float4(col, 1.0);
}

// ---------- 11. Vinyl Scanner ----------
// params: p0.x=grooves, p0.y=scanSpeed, p0.z=wobble, p0.w=notchGain, p1.x=labelGlow
// colors: c0 = record shadow, c1 = grooves, c2 = scanner/label accent
fragment float4 fragment_vinyl(VOut in [[stage_in]],
                               constant AudioUniforms& u [[buffer(0)]],
                               constant PresetParams& p [[buffer(1)]],
                               texture2d<float> spec [[texture(0)]],
                               texture2d<float> wave [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float grooves   = max(1.0, p.p0.x);
    float scanSpeed = p.p0.y;
    float wobble    = p.p0.z;
    float notchGain = p.p0.w;
    float labelGlow = p.p1.x;

    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 uv = in.uv * 2.0 - 1.0;
    uv.x *= aspect;

    float r = length(uv);
    float a = atan2(uv.y, uv.x);
    float angle01 = fract(a / 6.2831853 + 0.5);
    float wav = wave.sample(s, float2(angle01, 0.5)).r;
    float specMag = spec.sample(s, float2(fract(angle01 + r * 0.23), 0.5)).r;

    float disc = (1.0 - smoothstep(0.78, 0.82, r)) * smoothstep(0.08, 0.13, r);
    float warpedR = r + wav * wobble * 0.010 + specMag * notchGain * 0.003;
    float grooveWave = sin(warpedR * grooves * 6.2831853 + specMag * notchGain * 2.3);
    float grooveLine = smoothstep(0.82, 1.0, grooveWave * 0.5 + 0.5);
    float fineGroove = 0.5 + 0.5 * sin(warpedR * grooves * 18.849556 + u.time * 0.12);

    float scanAngle = u.time * scanSpeed * 1.55;
    float angleDist = abs(atan2(sin(a - scanAngle), cos(a - scanAngle)));
    float scan = exp(-angleDist * 30.0) * smoothstep(0.16, 0.72, r) * (1.0 - smoothstep(0.76, 0.84, r));
    float notch = smoothstep(0.45, 1.0, specMag * notchGain) * scan;

    float label = 1.0 - smoothstep(0.18, 0.22, r);
    float hole = 1.0 - smoothstep(0.028, 0.045, r);

    float3 col = p.c0.rgb * (0.22 + 0.45 * (1.0 - smoothstep(0.0, 0.85, r)));
    col += p.c1.rgb * disc * (grooveLine * 0.30 + fineGroove * 0.050 + specMag * 0.18);
    col += p.c2.rgb * (scan * 0.22 + notch * 0.90) * (1.0 + u.beat * 0.55);
    col = mix(col, mix(p.c2.rgb, p.c1.rgb, 0.35) * (0.28 + labelGlow * (0.20 + u.loudness * 0.35)), label);
    col = mix(col, p.c0.rgb * 0.12, hole);
    col *= 1.0 - smoothstep(0.82, 1.15, r);
    return float4(col, 1.0);
}
