#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// --- value noise + fbm helpers ------------------------------------------------

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float hash11(float n) {
    return fract(sin(n) * 43758.5453123);
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
        p *= 2.03;
        a *= 0.5;
    }
    return v;
}

static float2 rotate2(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

static float lineSegmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// --- graphite app field -------------------------------------------------------

[[ stitchable ]] half4 metalBackdrop(float2 position, half4 color, float2 size, float time) {
    float2 uv = position / max(size, float2(1.0));
    float2 p = uv - 0.5;
    float aspect = max(size.x / max(size.y, 1.0), 1.0);
    p.x *= aspect;

    float t = time * 0.035;
    float grain = fbm(uv * 58.0 + float2(t * 0.7, -t));
    float brushed = fbm(float2(uv.x * 22.0 - t, uv.y * 3.0 + t * 0.4));
    float diagonal = sin((uv.x + uv.y) * 9.0 + t * 4.0) * 0.5 + 0.5;
    float vignette = 1.0 - smoothstep(0.26, 0.86, length(p));

    half3 graphite = half3(0.020, 0.024, 0.025);
    half3 charcoal = half3(0.060, 0.070, 0.070);
    half3 teal = half3(0.060, 0.470, 0.450);
    half3 amber = half3(0.720, 0.380, 0.120);
    half3 steel = half3(0.230, 0.310, 0.330);

    half3 col = mix(graphite, charcoal, half(0.35 + uv.y * 0.45));
    col += steel * half(0.045 * brushed);
    col += teal * half(0.090 * diagonal * vignette);
    col += amber * half(0.048 * (1.0 - uv.y) * smoothstep(0.25, 0.82, diagonal));
    col += half3(0.012) * half(grain);
    col *= half(0.74 + 0.26 * vignette);

    return half4(col, 1.0);
}

// --- reactive glass nanoparticles -------------------------------------------

// `mode`: 0 idle/armed, 1 listening, 2 extracting, 3 processing, 4 danger/error.
[[ stitchable ]] half4 nanoParticleCloud(float2 position, half4 color, float2 size, float time, float mode) {
    float diameter = max(min(size.x, size.y), 1.0);
    float2 uv = (position - size * 0.5) / diameter;
    float2 p = uv * 2.05;
    float rad = length(p);

    float listening = 1.0 - smoothstep(0.35, 0.95, abs(mode - 1.0));
    float extracting = 1.0 - smoothstep(0.35, 0.95, abs(mode - 2.0));
    float processing = 1.0 - smoothstep(0.35, 0.95, abs(mode - 3.0));
    float danger = 1.0 - smoothstep(0.35, 0.95, abs(mode - 4.0));
    float energy = clamp(0.22 + listening * 0.55 + extracting * 0.78 + processing * 0.40 + danger * 0.52, 0.0, 1.0);
    float expansion = 0.72 + listening * 0.13 + extracting * 0.20 + processing * 0.07 + danger * 0.10;
    float t = time * mix(0.10, 0.72, energy);

    half3 graphite = half3(0.025, 0.030, 0.030);
    half3 glass = half3(0.880, 1.000, 0.970);
    half3 teal = half3(0.110, 0.950, 0.860);
    half3 amber = half3(1.000, 0.610, 0.200);
    half3 coolSteel = half3(0.180, 0.560, 0.670);
    half3 red = half3(1.000, 0.240, 0.160);

    half3 col = graphite * half(0.05 * smoothstep(1.18, 0.10, rad));
    float alpha = 0.0;

    for (int i = 0; i < 30; i++) {
        float id = float(i) + 1.0;
        float seedA = hash11(id * 12.989);
        float seedB = hash11(id * 78.233);
        float seedC = hash11(id * 39.425);

        float angle = seedA * 6.2831853;
        float radius = sqrt(seedB) * expansion;
        float2 base = float2(cos(angle), sin(angle)) * radius;
        float orbitSpeed = mix(0.10, 0.34, seedC) * (seedA > 0.5 ? 1.0 : -1.0);
        float2 center = rotate2(base, t * orbitSpeed);
        center += float2(sin(t * (1.2 + seedA * 2.1) + seedB * 8.0),
                         cos(t * (1.0 + seedB * 2.0) + seedC * 9.0)) * (0.030 + 0.080 * energy);

        float pulse = 0.5 + 0.5 * sin(t * (2.2 + seedC * 3.0) + seedA * 9.0);
        float pointRadius = mix(0.018, 0.044, seedC) * (1.0 + 0.45 * extracting * pulse);
        float d = length(p - center);
        float core = exp(-(d * d) / max(pointRadius * pointRadius, 0.0001));
        float halo = exp(-(d * d) / max(pointRadius * pointRadius * 8.0, 0.0001));
        float glint = exp(-pow(length(p - center - float2(-0.010, -0.014)) / max(pointRadius * 0.38, 0.0001), 2.0));

        half warm = half(smoothstep(0.58, 0.98, seedB) * extracting + 0.18 * pulse);
        half3 particleColor = mix(teal, amber, warm);
        particleColor = mix(particleColor, coolSteel, half(processing * 0.70));
        particleColor = mix(particleColor, red, half(danger * 0.82));

        col += particleColor * half(core * (0.90 + 0.75 * energy));
        col += particleColor * half(halo * (0.11 + 0.20 * energy));
        col += glass * half(glint * (0.70 + 0.30 * energy));
        alpha += core * 0.74 + halo * 0.18;

        if (i < 18) {
            float neighborAngle = angle + 0.62 + seedC * 0.90;
            float2 neighbor = rotate2(float2(cos(neighborAngle), sin(neighborAngle)) * radius * (0.82 + seedA * 0.20),
                                      t * orbitSpeed * -0.74);
            float linkD = lineSegmentDistance(p, center, neighbor);
            float link = exp(-pow(linkD / (0.006 + 0.006 * energy), 2.0));
            float linkFade = smoothstep(0.95, 0.10, length(center - neighbor));
            col += particleColor * half(link * linkFade * (0.060 + 0.090 * energy));
            alpha += link * linkFade * 0.050;
        }
    }

    float lens = exp(-pow(rad * 1.08, 2.0)) * (0.10 + energy * 0.18);
    float glassEdge = exp(-pow((rad - expansion * 0.88) * 8.0, 2.0)) * (0.08 + 0.12 * energy);
    half3 modeColor = mix(teal, amber, half(extracting * 0.75));
    modeColor = mix(modeColor, coolSteel, half(processing * 0.62));
    modeColor = mix(modeColor, red, half(danger * 0.78));
    col += modeColor * half(lens + glassEdge);
    col += glass * half(glassEdge * 0.25);
    alpha = clamp(alpha + lens * 0.22 + glassEdge * 0.28, 0.0, 1.0);

    return half4(col * half(alpha), half(alpha));
}
