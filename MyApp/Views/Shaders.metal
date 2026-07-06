#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// --- value noise + fbm helpers ------------------------------------------------

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * valueNoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// --- Siri-style flowing glow --------------------------------------------------

// A domain-warped, multi-color flowing orb. `mode`: 0 = full Siri palette
// (listening), 1 = cooler blue/violet (processing). Alpha falls off radially so
// it composits over any background.
[[ stitchable ]] half4 siriGlow(float2 position, half4 color, float2 size, float time, float mode) {
    float2 uv = position / max(size, float2(1.0));
    float2 c = uv * 2.0 - 1.0;
    float t = time * 0.42;

    // Two-step domain warp for organic motion.
    float2 q = float2(fbm(uv * 3.0 + t), fbm(uv * 3.0 - t + 5.2));
    float2 r = float2(fbm(uv * 3.0 + q * 2.2 + t * 0.5),
                      fbm(uv * 3.0 + q * 2.2 - t * 0.3));
    float f = fbm(uv * 3.0 + r * 2.5);

    half3 blue   = half3(0.20, 0.48, 1.00);
    half3 purple = half3(0.66, 0.30, 1.00);
    half3 pink   = half3(1.00, 0.36, 0.72);
    half3 teal   = half3(0.20, 0.88, 0.86);

    half3 col = mix(blue, purple, half(smoothstep(0.0, 0.6, f)));
    col = mix(col, pink, half(smoothstep(0.45, 0.95, r.x)));
    col = mix(col, teal, half(smoothstep(0.30, 0.85, q.y)));

    // Cooler, calmer palette for processing.
    half3 coolA = mix(blue, purple, half(smoothstep(0.0, 0.7, f)));
    half3 coolB = mix(coolA, teal, half(smoothstep(0.4, 0.9, q.y)));
    col = mix(col, coolB, half(clamp(mode, 0.0, 1.0)));

    col *= half(0.75 + 0.65 * f);

    // Radial envelope with a soft breathing edge.
    float rad = length(c);
    float edge = 0.98 + 0.05 * sin(time * 1.6);
    float a = smoothstep(edge, 0.15, rad) * (0.65 + 0.45 * f);

    return half4(col * half(a), half(clamp(a, 0.0, 1.0)));
}
