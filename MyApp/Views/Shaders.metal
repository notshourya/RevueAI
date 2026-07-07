#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// --- noise helpers ------------------------------------------------------------

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

// --- liquid glass blob --------------------------------------------------------
//
// RevueAI's capture identity: a soft translucent form that breathes when idle
// and ripples with energy while the AI is live. Pure glass — bright rim, faint
// body, a wandering specular — with only a restrained state hue.
//
// `mode`: 0 idle, 1 listening, 2 extracting, 3 processing, 4 danger/error.

[[ stitchable ]] half4 liquidGlassBlob(float2 position, half4 color, float2 size, float time, float mode) {
    float diameter = max(min(size.x, size.y), 1.0);
    float2 p = (position - size * 0.5) / (diameter * 0.5);
    float r = length(p);
    float theta = atan2(p.y, p.x);

    float listening  = 1.0 - smoothstep(0.35, 0.95, abs(mode - 1.0));
    float extracting = 1.0 - smoothstep(0.35, 0.95, abs(mode - 2.0));
    float processing = 1.0 - smoothstep(0.35, 0.95, abs(mode - 3.0));
    float danger     = 1.0 - smoothstep(0.35, 0.95, abs(mode - 4.0));
    float energy = clamp(0.18 + 0.55 * listening + 0.80 * extracting + 0.35 * processing + 0.60 * danger, 0.0, 1.0);

    float t = time * mix(0.35, 1.15, energy);
    float amp = mix(0.020, 0.075, energy);

    // Organic outline: a circle whose radius is modulated by slow traveling
    // waves plus a whisper of noise, so the form never repeats exactly.
    float R = 0.66
        + amp * sin(theta * 3.0 + t * 1.30)
        + amp * 0.70 * sin(theta * 5.0 - t * 0.90 + 1.7)
        + amp * 0.45 * sin(theta * 8.0 + t * 1.90 + 4.2)
        + 0.014 * (valueNoise(float2(theta * 1.8 + 7.0, t * 0.55)) - 0.5);

    float d = r - R;

    float body = 1.0 - smoothstep(-0.015, 0.030, d);
    float rim = exp(-pow(abs(d) / 0.018, 1.6));
    float innerRim = exp(-pow(abs(r - R * 0.78) / 0.050, 2.0)) * 0.5;
    float core = exp(-r * r * 2.4);

    // A specular highlight that slowly wanders the upper body.
    float2 highlight = float2(cos(t * 0.7), sin(t * 0.9)) * R * 0.35 + float2(-0.18, 0.22);
    float spec = exp(-pow(length(p - highlight) / 0.16, 2.0));

    half3 glass = half3(0.92, 0.96, 1.00);
    half3 tint = half3(0.55, 0.75, 0.85);
    tint = mix(tint, half3(1.00, 0.62, 0.30), half(extracting * 0.80));
    tint = mix(tint, half3(0.55, 0.60, 0.70), half(processing * 0.70));
    tint = mix(tint, half3(1.00, 0.28, 0.22), half(danger * 0.85));

    half3 col = half3(0.0);
    half bodyAlpha = half(body * (0.16 + 0.10 * energy));
    col += tint * bodyAlpha * half(0.9);
    col += tint * half(core * body * (0.18 + 0.30 * energy));
    col += glass * half(rim * (0.55 + 0.35 * energy));
    col += tint * half(innerRim * body);
    col += glass * half(spec * body * 0.65);

    float alpha = clamp(float(bodyAlpha) + rim * 0.75 + innerRim * 0.40 * body + spec * body * 0.50, 0.0, 1.0);
    return half4(col, half(alpha));
}
