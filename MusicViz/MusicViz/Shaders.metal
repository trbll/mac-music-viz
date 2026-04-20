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

// ---------- helpers ----------

static inline float3 palette(float t) {
    const float3 a = float3(0.5, 0.5, 0.5);
    const float3 b = float3(0.5, 0.5, 0.5);
    const float3 c = float3(1.0, 1.0, 1.0);
    const float3 d = float3(0.00, 0.33, 0.67);
    return a + b * cos(6.2831853 * (c * t + d));
}

// ---------- 1. Plasma ----------
// params: p0.x=scale, p0.y=speed, p0.z=bassReact, p0.w=brightness
// colors: c0 = tint
fragment float4 fragment_plasma(VOut in [[stage_in]],
                                constant AudioUniforms& u [[buffer(0)]],
                                constant PresetParams& p [[buffer(1)]]) {
    float scale      = p.p0.x;
    float speed      = p.p0.y;
    float bassReact  = p.p0.z;
    float brightness = p.p0.w;
    float3 tint      = p.c0.rgb;

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

    float3 col = palette(v + u.beat * 0.15);
    col *= tint;
    col *= brightness * (0.55 + 0.45 * (u.loudness + u.beat * 0.4));
    return float4(col, 1.0);
}

// ---------- 2. Tunnel ----------
// params: p0.x=ringSpeed, p0.y=spokes, p0.z=beatPunch, p0.w=bassReact
// colors: c0 = tint
fragment float4 fragment_tunnel(VOut in [[stage_in]],
                                constant AudioUniforms& u [[buffer(0)]],
                                constant PresetParams& p [[buffer(1)]]) {
    float ringSpeed = p.p0.x;
    float spokes    = max(1.0, p.p0.y);
    float beatPunch = p.p0.z;
    float bassReact = p.p0.w;
    float3 tint     = p.c0.rgb;

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

    float3 col = palette(depth * 0.12 + t * 0.07);
    col *= tint;
    col *= 0.4 + 0.6 * (v * 0.5 + 0.5);
    col *= smoothstep(0.0, 0.25, r);
    col *= 1.0 + u.beat * beatPunch;
    return float4(col, 1.0);
}

// ---------- 3. Spectrum bars ----------
// params: p0.x=gain, p0.y=peak, p0.z=floorGlow
// colors: c0 = tint
fragment float4 fragment_bars(VOut in [[stage_in]],
                              constant AudioUniforms& u [[buffer(0)]],
                              constant PresetParams& p [[buffer(1)]],
                              texture2d<float> spec [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float gain       = p.p0.x;
    float peakAmt    = p.p0.y;
    float floorAmt   = p.p0.z;
    float3 tint      = p.c0.rgb;

    float2 uv = in.uv;
    uv.y = 1.0 - uv.y;

    float mag = spec.sample(s, float2(uv.x, 0.5)).r;
    float h = mag * gain;
    float below = step(uv.y, h);

    float3 col = palette(uv.x * 0.7 + u.time * 0.03) * below;

    float peak = smoothstep(h - 0.008, h, uv.y) * step(uv.y, h + 0.002);
    col += peak * peakAmt;

    col += palette(uv.x) * 0.15 * exp(-uv.y * 5.0) * (0.2 + u.loudness) * floorAmt;
    col *= tint;
    return float4(col, 1.0);
}

// ---------- 4. Oscilloscope ----------
// params: p0.x=thickness, p0.y=glow, p0.z=scanlines(0/1), p0.w=grid(0/1)
// colors: c0 = trace
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

    float2 uv = in.uv;

    float w = wave.sample(s, float2(uv.x, 0.5)).r;
    float lineY = 0.5 + w * 0.42;
    float d = abs(uv.y - lineY);

    float core = exp(-d * (180.0 / thickness));
    float glow = exp(-d * (22.0 / thickness)) * 0.35 * glowAmt;
    float3 col = trace * core + trace * 0.35 * glow;

    float gx = smoothstep(0.98, 1.0, sin(uv.x * 40.0 + 1.5708) * 0.5 + 0.5);
    float gy = smoothstep(0.98, 1.0, sin(uv.y * 28.0 + 1.5708) * 0.5 + 0.5);
    col += trace * 0.12 * (gx + gy) * grid;

    float scan = 0.82 + 0.18 * (0.5 + 0.5 * sin(uv.y * u.resolution.y * 3.14159));
    col *= mix(1.0, scan, scanlines);
    col *= 1.0 + u.beat * 0.4;
    return float4(col, 1.0);
}

// ---------- 5. Apple Bloom ----------
// params: p0.x=blobCount, p0.y=speed, p0.z=bassReact, p0.w=gamma
// colors: c0 = tint
fragment float4 fragment_bloom(VOut in [[stage_in]],
                               constant AudioUniforms& u [[buffer(0)]],
                               constant PresetParams& p [[buffer(1)]]) {
    int blobCount  = int(clamp(p.p0.x, 1.0, 12.0));
    float speed    = p.p0.y;
    float bassReact= p.p0.z;
    float gamma    = max(0.1, p.p0.w);
    float3 tint    = p.c0.rgb;

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
        col += palette(fi * 0.23 + u.time * 0.04) * blob * 0.55;
    }
    col *= tint;
    col *= 1.0 - length(uv) * 0.4;
    col = pow(col, float3(gamma));
    return float4(col, 1.0);
}
