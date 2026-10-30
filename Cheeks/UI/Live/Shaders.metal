#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 uv = float2((vid << 1) & 2, vid & 2);
    VOut out;
    out.position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
    out.uv = uv;
    return out;
}

static inline float saturate1(float x) { return clamp(x, 0.0, 1.0); }

// MARK: Scrolling waveform

static inline float4 readBin(texture2d<float, access::read> atlas, int row, int count, int i) {
    if (i < 0 || i >= count) return float4(0);
    return atlas.read(uint2(i & (WAVE_ROW_WIDTH - 1), row + (i >> 12)));
}

/// Fill of a shape with half-height `height` at distance `y` from the centre, antialiased.
static inline float shapeCoverage(float y, float height, float aa) {
    return 1.0 - smoothstep(height - aa, height + aa, y);
}

/// A band's colour: bright through its core, falling away towards its edge, with a fine lit rim.
static inline float3 bandShade(float3 color, float y, float height, float aa) {
    float inside = saturate1(y / max(height, 0.002));
    float3 shaded = color * (1.12 - 0.5 * inside * inside);
    float rim = smoothstep(height - 3.5 * aa, height - aa, y);
    return mix(shaded, color * 1.35 + 0.08, rim * 0.5);
}

/// Position on the beat grid at time `t` (x), and the length of a beat there in seconds (y).
/// Each section is time, first beat, seconds per beat.
static inline float2 gridAt(float t, constant float4 *sections, int count) {
    int i = 0;
    for (int k = 1; k < count; ++k) {
        if (t < sections[k].x) break;
        i = k;
    }
    return float2(sections[i].y + (t - sections[i].x) / sections[i].z, sections[i].z);
}

fragment float4 waveform_fragment(VOut in [[stage_in]],
                                  constant WaveUniforms &u [[buffer(0)]],
                                  constant float4 *cues [[buffer(1)]],
                                  constant float4 *sections [[buffer(2)]],
                                  texture2d<float, access::read> bands [[texture(0)]],
                                  texture2d<float, access::read> stems [[texture(1)]],
                                  texture2d<float> letters [[texture(2)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    const float2 px = in.position.xy;
    const float t = u.startSeconds + px.x * u.secondsPerPixel;
    const float midY = u.size.y * 0.5;
    const float headroom = 2.0 * u.scale;
    const float y = abs(px.y - midY) / (midY - headroom);
    const float aa = 0.75 / (midY - headroom);

    // Near-black, with every other eight bars lifted very slightly so phrases read at a glance.
    float3 color = float3(0.016, 0.018, 0.022);
    const float secondsPerPixelAbs = abs(u.secondsPerPixel);
    const float2 gridHere = u.sectionCount > 0 ? gridAt(t, sections, u.sectionCount) : float2(0, 1);
    const float beats = gridHere.x, beatSeconds = gridHere.y;
    if (u.sectionCount > 0 && u.loaded > 0.5) {
        const float phrase = fmod(floor(beats / 32.0) + 4096.0, 2.0);
        color += float3(0.012, 0.013, 0.016) * phrase;
    }

    if (u.loaded < 0.5) {
        // An empty deck: a single fine centre line.
        const float line = 1.0 - smoothstep(0.0, 1.0, abs(px.y - midY));
        return float4(color + line * 0.1, 1);
    }
    const bool inTrack = t >= 0 && t <= u.duration;

    // Loop region, under everything else.
    if (u.loopStart >= 0 && u.loopEnd > u.loopStart && t >= u.loopStart && t <= u.loopEnd) {
        const float strength = u.loopActive > 0.5 ? 1.0 : 0.35;
        color = mix(color, float3(1.0, 0.56, 0.05), 0.17 * strength);
    }

    // Beat grid, under the waveform so it never hides the audio.
    if (u.sectionCount > 0 && inTrack) {
        const float nearest = round(beats);
        const float distancePx = abs(beats - nearest) * beatSeconds / secondsPerPixelAbs;
        const float line = 1.0 - smoothstep(0.35 * u.scale, 0.35 * u.scale + 1.0, distancePx);
        const bool isBar = fmod(nearest + 40000.0, 4.0) < 0.5;
        color += line * (isBar ? float3(0.2, 0.21, 0.24) : float3(0.07, 0.075, 0.09));
    }

    // Waveform
    if (inTrack) {
        const int level = u.level;
        const float scaled = t * u.binsPerSecond / float(1 << level);
        const int i0 = int(floor(scaled));
        const float f = scaled - float(i0);
        const int row = u.levelRow[level], count = u.levelCount[level];
        // Catmull-Rom through four bins, so zoomed-in waves have real curves, not polygon edges.
        const float4 a = readBin(bands, row, count, i0 - 1), b = readBin(bands, row, count, i0);
        const float4 c = readBin(bands, row, count, i0 + 1), d = readBin(bands, row, count, i0 + 2);
        float4 v = 0.5 * (2.0 * b + (c - a) * f + (2.0 * a - 5.0 * b + 4.0 * c - d) * f * f + (3.0 * b - a - 3.0 * c + d) * f * f * f);
        v = clamp(v, 0.0, 1.0) * u.reveal;

        float3 wave = color;
        if (u.colorStyle == 1) {
            // RGB style: one shape whose colour comes from the balance of the bands.
            const float height = pow(max(v.r, max(v.g, v.b)), 0.82);
            const float total = max(v.r + v.g + v.b, 0.001);
            const float3 mixColor = normalize(float3(v.r * 1.1, v.g * 0.9, v.b * 1.5) / total + 0.03) * 1.25;
            wave = mix(wave, bandShade(mixColor, y, height, aa), shapeCoverage(y, height, aa));
        } else {
            // rekordbox's 3-band: bass outermost, mids inside it, highs at the core.
            const float low = pow(v.r, 0.78);
            const float mid = pow(v.g, 0.9) * 0.78;
            const float high = pow(v.b, 0.85) * 0.56;
            wave = mix(wave, bandShade(u.lowColor.rgb, y, low, aa), shapeCoverage(y, low, aa));
            wave = mix(wave, bandShade(u.midColor.rgb, y, mid, aa), shapeCoverage(y, mid, aa));
            wave = mix(wave, bandShade(u.highColor.rgb, y, high, aa), shapeCoverage(y, high, aa));
        }

        if (u.stemBlend > 0.001) {
            const float4 sa = readBin(stems, row, count, i0), sb = readBin(stems, row, count, i0 + 1);
            float4 s = clamp(mix(sa, sb, f), 0.0, 1.0) * u.reveal;
            float3 stemWave = color;
            // Stacked by size: bass and drums behind, melody over them, vocals at the front. A
            // muted stem drops to a dim ghost, so you can see what's been taken out.
            const int order[4] = {2, 3, 1, 0};
            const float scales[4] = {1.0, 0.92, 0.72, 0.56};
            for (int k = 0; k < 4; ++k) {
                const int stem = order[k];
                const float height = pow(s[stem], 0.86) * scales[k];
                const float gain = u.stemGains[stem];
                const float3 base = u.stemColors[stem].rgb * (0.16 + 0.84 * gain);
                const float coverage = shapeCoverage(y, height, aa) * (0.35 + 0.65 * gain);
                stemWave = mix(stemWave, bandShade(base, y, height, aa), coverage);
            }
            wave = mix(wave, stemWave, u.stemBlend);
        }

        // What's already played is dimmed and greyed, so the eye goes to what's coming.
        if (px.x < u.playheadX) {
            const float grey = dot(wave, float3(0.3, 0.55, 0.15));
            wave = mix(wave, float3(grey), 0.45) * 0.42;
        }
        color = wave;
    }

    // Bar ticks along the top and bottom edges, red like rekordbox's.
    if (u.sectionCount > 0 && inTrack) {
        const float nearest = round(beats);
        const float dx = abs(beats - nearest) * beatSeconds / secondsPerPixelAbs;
        const float edge = min(px.y, u.size.y - px.y);
        const bool isBar = fmod(nearest + 40000.0, 4.0) < 0.5;
        const float size = (isBar ? 5.0 : 2.5) * u.scale;
        const float tick = saturate1(size - edge) / size;
        const float widthAtY = (isBar ? 3.2 : 0.7) * u.scale * tick;
        const float mark = 1.0 - smoothstep(widthAtY - 0.8, widthAtY + 0.8, dx);
        if (tick > 0) color = mix(color, isBar ? float3(1.0, 0.16, 0.14) : float3(0.75, 0.77, 0.82), mark);
    }

    // Loop edges
    if (u.loopStart >= 0 && u.loopEnd > u.loopStart) {
        const float toStart = abs(t - u.loopStart) / secondsPerPixelAbs;
        const float toEnd = abs(t - u.loopEnd) / secondsPerPixelAbs;
        const float edge = 1.0 - smoothstep(0.5 * u.scale, 0.5 * u.scale + 1.0, min(toStart, toEnd));
        color = mix(color, float3(1.0, 0.62, 0.12), edge * (u.loopActive > 0.5 ? 1.0 : 0.5));
    }

    // Memory cue and the current cue point: triangles rising from the bottom edge.
    const float fromBottom = u.size.y - px.y;
    {
        const float dx = abs(t - u.cuePoint) / secondsPerPixelAbs;
        const float tri = 7.0 * u.scale;
        const float width = saturate1(1.0 - fromBottom / tri) * 5.5 * u.scale;
        const float mark = 1.0 - smoothstep(width - 0.8, width + 0.8, dx);
        if (fromBottom < tri) color = mix(color, float3(1.0, 0.62, 0.1), mark);
    }
    if (u.memoryCue >= 0) {
        const float dx = abs(t - u.memoryCue) / secondsPerPixelAbs;
        const float tri = 6.0 * u.scale;
        const float width = saturate1(1.0 - px.y / tri) * 4.5 * u.scale;
        const float mark = 1.0 - smoothstep(width - 0.8, width + 0.8, dx);
        if (px.y < tri) color = mix(color, float3(1.0, 0.2, 0.2), mark);
    }

    // Hot cues: a line through the wave with a lettered flag at the top.
    const float flagWidth = 12.0 * u.scale, flagHeight = 11.0 * u.scale;
    for (int i = 0; i < u.cueCount; ++i) {
        const float4 cue = cues[i]; // time, r, g, b; the letter index is the array position's alpha in the next entry
        const float cueX = (cue.x - u.startSeconds) / u.secondsPerPixel;
        const float3 cueColor = cue.yzw;
        const float dx = abs(px.x - cueX);
        if (dx < 1.5 * u.scale) {
            const float line = 1.0 - smoothstep(0.45 * u.scale, 0.45 * u.scale + 1.0, dx);
            color = mix(color, cueColor, line * 0.9);
        }
        const float2 flag = float2(px.x - cueX, px.y);
        if (flag.x >= 0 && flag.x <= flagWidth && flag.y >= 0 && flag.y <= flagHeight) {
            const float letterIndex = cues[WAVE_MAX_CUES + i].x;
            const float2 uv = float2((letterIndex + flag.x / flagWidth) / 8.0, flag.y / flagHeight);
            const float glyph = letters.sample(linear, uv).a;
            color = mix(cueColor, float3(0.02), glyph);
        }
    }

    // Playhead: a bright line with a soft glow that lifts slightly on the beat, and caps.
    {
        const float dx = abs(px.x - u.playheadX);
        const float core = 1.0 - smoothstep(0.55 * u.scale, 0.55 * u.scale + 1.0, dx);
        const float glowSize = 7.0 * u.scale;
        const float glow = exp(-dx * dx / (glowSize * glowSize * 0.18)) * (0.13 + 0.14 * u.beatPulse);
        color += float3(0.75, 0.85, 1.0) * glow;
        color = mix(color, float3(1.0), core);
        const float capEdge = min(px.y, u.size.y - px.y);
        const float capSize = 5.0 * u.scale;
        const float capWidth = saturate1(1.0 - capEdge / capSize) * 4.5 * u.scale;
        const float cap = 1.0 - smoothstep(capWidth - 0.8, capWidth + 0.8, dx);
        if (capEdge < capSize) color = mix(color, float3(1.0), cap);
    }

    return float4(color, 1);
}

// MARK: Whole-track overview

fragment float4 overview_fragment(VOut in [[stage_in]],
                                  constant OverviewUniforms &u [[buffer(0)]],
                                  constant float4 *cues [[buffer(1)]],
                                  texture2d<float> columns [[texture(0)]],
                                  texture2d<float> letters [[texture(1)]]) {
    constexpr sampler smooth(filter::linear, address::clamp_to_edge);
    const float2 px = in.position.xy;
    const float x = px.x / u.size.x;
    float3 color = float3(0.012, 0.013, 0.016);
    if (u.duration <= 0) return float4(color, 1);

    const float4 v = columns.sample(smooth, float2(x, 0.5));
    const float flag = 7.0 * u.scale;
    const float usable = u.size.y - 1.0 * u.scale;
    const float h = (u.size.y - px.y) / usable; // 0 at the bottom, 1 at the top
    const float aa = 1.0 / usable;

    const float low = pow(v.r, 0.8), mid = pow(v.g, 0.8) * 0.82, high = pow(v.b, 0.75) * 0.6;
    const bool played = x < u.progress;
    float3 wave = color;
    wave = mix(wave, u.lowColor.rgb, 1.0 - smoothstep(low - aa, low + aa, h));
    wave = mix(wave, u.midColor.rgb, 1.0 - smoothstep(mid - aa, mid + aa, h));
    wave = mix(wave, u.highColor.rgb, 1.0 - smoothstep(high - aa, high + aa, h));
    if (played) {
        const float grey = dot(wave, float3(0.3, 0.55, 0.15));
        wave = mix(wave, float3(grey), 0.7) * 0.4;
    }
    color = wave + (u.hover * 0.04);

    // The last thirty seconds are marked, and blink when the playhead gets there.
    if (u.duration > 30 && x > (u.duration - 30) / u.duration) {
        color = mix(color, float3(1, 0.1, 0.08), (0.12 + 0.28 * u.warn) * (1.0 - smoothstep(0.0, 2.0 * u.scale, px.y)) + 0.05);
    }

    if (u.loopStart >= 0 && u.loopEnd > u.loopStart) {
        const float a = u.loopStart / u.duration, b = u.loopEnd / u.duration;
        const float minWidth = 2.0 * u.scale / u.size.x;
        if (x >= a && x <= max(b, a + minWidth)) {
            color = mix(color, float3(1.0, 0.56, 0.05), u.loopActive > 0.5 ? 0.55 : 0.25);
        }
    }

    for (int i = 0; i < u.cueCount; ++i) {
        const float4 cue = cues[i];
        const float cueX = cue.x / u.duration * u.size.x;
        const float dx = px.x - cueX;
        if (abs(dx) < 1.0 * u.scale) color = mix(color, cue.yzw, 0.85);
        if (dx >= 0 && dx < flag && px.y < flag) color = cue.yzw;
    }
    if (u.memoryCue >= 0) {
        const float dx = abs(px.x - u.memoryCue / u.duration * u.size.x);
        const float tri = 4.0 * u.scale;
        const float width = saturate1(1.0 - px.y / tri) * 3.0 * u.scale;
        if (px.y < tri && dx < width) color = float3(1, 0.22, 0.2);
    }
    {
        const float dx = abs(px.x - u.cuePoint / u.duration * u.size.x);
        const float tri = 3.5 * u.scale;
        const float fromBottom = u.size.y - px.y;
        const float width = saturate1(1.0 - fromBottom / tri) * 2.8 * u.scale;
        if (fromBottom < tri && dx < width) color = float3(1, 0.62, 0.1);
    }

    const float playX = u.progress * u.size.x;
    const float d = abs(px.x - playX);
    color = mix(color, float3(1), 1.0 - smoothstep(0.5 * u.scale, 0.5 * u.scale + 1.0, d));
    return float4(color, 1);
}

// MARK: Jog wheel

static inline float grain(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// Two soft highlights opposite each other, the way light catches circular brushing or vinyl grooves.
static inline float anisotropic(float theta, float light, float sharp) {
    return pow(abs(cos(theta - light)), sharp);
}

/// Bakes everything that never changes into a texture: housing, brushed-metal ring, LED channel,
/// vinyl with its fixed sheen, and the hub's bezel. It runs once per size, so it can be as rich as
/// it likes.
fragment float4 jog_bake_fragment(VOut in [[stage_in]], constant JogUniforms &u [[buffer(0)]]) {
    const float2 p = (in.position.xy - u.size * 0.5) / (u.size.x * 0.5);
    const float r = length(p);
    const float px = 2.0 / u.size.x;
    const float theta = atan2(p.y, p.x);
    if (r > 1.0) return float4(0);

    float3 color;
    // Light comes from the top left. `lit` is +1 facing it and -1 facing away.
    const float lit = dot(normalize(p + 0.0001), normalize(float2(-0.55, -0.83)));

    if (r > 0.925) {
        // Moulded housing: a stepped black bezel with a soft chamfer catching the light.
        color = float3(0.04, 0.042, 0.047) + 0.03 * lit;
        const float chamfer = exp(-pow((r - 0.955) / 0.012, 2.0));
        color += chamfer * (0.1 + 0.16 * saturate1(lit));
        const float outer = exp(-pow((r - 0.992) / 0.006, 2.0));
        color += outer * (0.03 + 0.14 * saturate1(lit));
    } else if (r > 0.815) {
        // Brushed aluminium: circular brushing makes wedges of light, plus very fine grain.
        const float a1 = anisotropic(theta, -2.15, 18.0);
        const float a2 = anisotropic(theta, -0.5, 60.0);
        const float a3 = anisotropic(theta, 1.1, 8.0);
        float metal = 0.17 + 0.5 * a1 + 0.26 * a2 + 0.07 * a3;
        const float streak = grain(float2(floor(r / (px * 1.5)), 3.0)) - 0.5;
        metal += streak * 0.055;
        metal += (grain(in.position.xy) - 0.5) * 0.012;
        color = float3(metal) * float3(0.98, 0.99, 1.02);
        // Chamfers at both edges of the ring.
        const float outerEdge = exp(-pow((r - 0.921) / 0.0035, 2.0));
        const float innerEdge = exp(-pow((r - 0.819) / 0.0035, 2.0));
        color += outerEdge * (0.2 + 0.5 * saturate1(lit));
        color += innerEdge * (0.2 + 0.5 * saturate1(-lit));
        const float gapShadow = smoothstep(0.84, 0.815, r);
        color *= 1.0 - gapShadow * 0.5;
    } else if (r > 0.78) {
        // The channel the LEDs sit in.
        color = float3(0.012, 0.013, 0.016);
        const float upper = exp(-pow((r - 0.787) / 0.003, 2.0));
        color += upper * 0.06 * (0.5 + 0.5 * lit);
    } else if (r > 0.455) {
        // Vinyl: near-black with fine grooves, a couple of track bands, and the sheen that stays
        // fixed in space while the record turns beneath it. That sheen is what sells it as a record.
        float base = 0.028;
        const float groove = 0.5 + 0.5 * cos(r * 2.0 * M_PI_F / (px * 3.4));
        base += 0.012 * groove;
        const float band1 = smoothstep(0.004, 0.0, abs(r - 0.56));
        const float band2 = smoothstep(0.004, 0.0, abs(r - 0.675));
        base = mix(base, 0.012, max(band1, band2));
        const float sheen = 0.3 * anisotropic(theta, -2.2, 22.0) + 0.15 * anisotropic(theta, -2.2, 5.0) + 0.09 * anisotropic(theta, -0.3, 34.0);
        float3 vinyl = float3(base) + float3(0.98, 1.0, 1.05) * sheen * (0.55 + 0.45 * groove);
        // Small shadow where the record meets the channel, and where the hub sits on the record.
        vinyl *= 1.0 - 0.6 * smoothstep(0.745, 0.78, r);
        vinyl *= 1.0 - 0.55 * smoothstep(0.495, 0.455, r);
        color = vinyl;
    } else if (r > 0.425) {
        // Polished bezel around the hub, its light opposite on the inner and outer edges.
        const float a = anisotropic(theta, -2.15, 10.0);
        float metal = 0.15 + 0.55 * a + 0.08 * anisotropic(theta, 1.0, 4.0);
        const float crown = (r - 0.44) / 0.015;
        metal *= 0.9 + 0.2 * crown * saturate1(lit);
        color = float3(metal);
        color += exp(-pow((r - 0.4525) / 0.0025, 2.0)) * (0.1 + 0.35 * saturate1(lit));
    } else {
        // The hub itself is drawn live (the label turns). Alpha 0 marks it.
        return float4(0, 0, 0, 0);
    }

    // Antialias the outer edge against the panel.
    const float alpha = 1.0 - smoothstep(1.0 - px * 1.5, 1.0, r);
    return float4(color * alpha, alpha);
}

fragment float4 jog_fragment(VOut in [[stage_in]],
                             constant JogUniforms &u [[buffer(0)]],
                             texture2d<float> base [[texture(0)]],
                             texture2d<float> art [[texture(1)]]) {
    constexpr sampler smooth(filter::linear, address::clamp_to_edge);
    const float2 p = (in.position.xy - u.size * 0.5) / (u.size.x * 0.5);
    const float r = length(p);
    if (r > 1.0) return float4(0);
    const float px = 2.0 / u.size.x;
    float theta = atan2(p.y, p.x) + M_PI_2_F; // 0 at twelve o'clock, clockwise
    if (theta < 0) theta += 2.0 * M_PI_F;
    const float2 uv = in.position.xy / u.size;
    float4 baked = base.sample(smooth, uv);
    float3 color = baked.rgb;
    const float alpha = baked.a;

    // Angle from the platter's marker, 0...2π ahead of it.
    float fromMarker = fmod(theta - u.rotation, 2.0 * M_PI_F);
    if (fromMarker < 0) fromMarker += 2.0 * M_PI_F;

    if (r > 0.815 && r < 0.925) {
        // Grip notches, cut into the ring and turning with it. They catch light on one wall.
        const float count = 180.0;
        const float along = fromMarker * count / (2.0 * M_PI_F);
        const float cell = fract(along);
        const float width = fwidth(along);
        const float wall = smoothstep(0.32 - width, 0.32 + width, cell) * (1.0 - smoothstep(0.68 - width, 0.68 + width, cell));
        const float band = smoothstep(0.838, 0.842, r) * (1.0 - smoothstep(0.9, 0.904, r));
        color *= 1.0 - wall * band * 0.62;
        const float lip = smoothstep(0.66, 0.7, cell) * (1.0 - smoothstep(0.72, 0.8, cell));
        color += lip * band * 0.06;
        color *= 1.0 + u.touchRing * 0.12;
    }

    if (r > 0.455 && r < 0.78) {
        // The record turns: a faint printed marker line, and pressure lights it from below.
        const float angular = min(fromMarker, 2.0 * M_PI_F - fromMarker);
        const float distancePx = angular * r / px;
        const float line = (1.0 - smoothstep(0.9, 1.9, distancePx)) * smoothstep(0.47, 0.48, r) * (1.0 - smoothstep(0.755, 0.765, r));
        color = mix(color, float3(0.92, 0.93, 0.96), line * 0.92);
        // Fine pressed specks turning with the disc, so even a bare record visibly moves.
        const float specks = grain(float2(floor(fromMarker * 90.0), floor(r * 60.0)));
        if (specks > 0.975) color += 0.012;
        color += u.vinylTint.rgb * 0.05 * (1.0 - smoothstep(0.46, 0.78, r));
        color += u.ledColor.rgb * u.touchPlatter * 0.05;
    }

    // LED ring: individual lights in the channel, with a comet tail behind the marker, the cue
    // point in amber, the loop in orange, and a soft bloom onto the metal and vinyl on either side.
    const float ledR = 0.797;
    const float ledDistance = abs(r - ledR);
    const float ledCount = 96.0;
    const float cellAngle = 2.0 * M_PI_F / ledCount;
    const float index = floor(theta / cellAngle);
    const float within = fract(theta / cellAngle);

    // Brightness of the light this pixel belongs to; also used for the bloom.
    const float idle = 0.2 + 0.1 * u.beatPulse + 0.25 * max(u.touchPlatter, u.touchRing);
    float behind = fmod(u.rotation - (index + 0.5) * cellAngle, 2.0 * M_PI_F);
    if (behind < 0) behind += 2.0 * M_PI_F;
    const float comet = exp(-behind * 2.6) * 1.1;
    // On launch or a track load, the ring sweeps on clockwise with a bright leading edge.
    const float turn = theta / (2.0 * M_PI_F);
    const float sweep = saturate1((u.wake * 1.12 - turn) / 0.12);
    const float leading = sweep * (1.0 - sweep) * 4.0 * (1.0 - u.wake);
    float level = (u.loaded > 0.5 ? idle + comet : 0.06) * sweep + leading * 1.4;
    float3 ledTint = u.ledColor.rgb;
    if (u.warn > 0.001) ledTint = mix(ledTint, float3(1, 0.12, 0.08), u.warn);

    // Cue and loop are placed relative to the platter, so they sweep round with the record.
    if (u.loopFrom < 90.0) {
        float a = fmod(theta - u.rotation - u.loopFrom, 2.0 * M_PI_F);
        if (a < 0) a += 2.0 * M_PI_F;
        float span = fmod(u.loopTo - u.loopFrom, 2.0 * M_PI_F);
        if (span < 0) span += 2.0 * M_PI_F;
        if (a <= span) {
            ledTint = mix(ledTint, float3(1.0, 0.5, 0.04), 0.95);
            level = max(level, 0.55);
        }
    }
    if (u.cueAngle < 90.0) {
        float a = fmod(theta - u.rotation - u.cueAngle, 2.0 * M_PI_F);
        if (a < 0) a += 2.0 * M_PI_F;
        a = min(a, 2.0 * M_PI_F - a);
        if (a < cellAngle * 1.5) {
            ledTint = float3(1.0, 0.62, 0.08);
            level = max(level, 1.3);
        }
    }

    if (ledDistance < 0.016) {
        const float across = 1.0 - smoothstep(0.0075, 0.0105, ledDistance);
        const float seg = smoothstep(0.08, 0.16, within) * (1.0 - smoothstep(0.84, 0.92, within));
        const float light = across * seg;
        // Unlit LEDs stay faintly visible.
        color = mix(color, ledTint * 0.1 + 0.015, across * seg * 0.8);
        color += ledTint * light * level * 1.25;
        color += float3(1) * light * max(0.0, level - 0.75) * 0.4; // hot centre on the brightest ones
    }
    // Bloom
    if (u.loaded > 0.5 && r > 0.66 && r < 0.93) {
        const float spread = exp(-pow(ledDistance / 0.038, 2.0));
        color += ledTint * spread * level * 0.26;
    }

    // Hub: the turning label under glass, with track progress around its rim.
    if (r <= 0.455) {
        float3 hub = float3(0.0);
        const float labelR = 0.405;
        if (r < labelR) {
            const float c = cos(-u.rotation), s = sin(-u.rotation);
            const float2 q = float2(p.x * c - p.y * s, p.x * s + p.y * c) / labelR;
            if (u.hasArt > 0.5) {
                hub = art.sample(smooth, q * 0.5 + 0.5).rgb;
            } else {
                // A pressed paper label: fine rings and a two-tone split that shows it turning.
                const float rr = length(q);
                const float split = smoothstep(-0.012, 0.012, q.x);
                hub = mix(u.labelColor.rgb * 0.55, u.labelColor.rgb, split);
                hub *= 0.9 + 0.1 * cos(rr * 44.0);
            }
            // The readouts sit on this, so it's dimmed and darkens towards the rim.
            const float rr = r / labelR;
            hub *= mix(u.artDim, u.artDim * 0.5, rr * rr);
            // A soft reflection on the glass from the top left.
            hub += 0.05 * (1.0 - smoothstep(0.0, 0.34, length(p - float2(-0.14, -0.2))));
            hub *= smoothstep(labelR, labelR - px * 1.5, r);
        }
        // Progress ring in the gap between the label and the bezel.
        const float ringR = 0.415;
        const float ring = 1.0 - smoothstep(0.0045, 0.0045 + px * 1.2, abs(r - ringR));
        hub = mix(hub, float3(1), ring * 0.13);
        if (u.loaded > 0.5 && turn <= u.progress) {
            const float3 tint = mix(u.ledColor.rgb, float3(1, 0.12, 0.08), u.warn);
            hub = mix(hub, tint * 1.15, ring);
        }
        // The baked bezel covers from 0.425 outwards; the hub shows where the bake is transparent.
        return float4(mix(hub, color, baked.a), 1.0);
    }

    return float4(color, alpha);
}

// MARK: Level meters

/// LED segments. Unlit ones stay faintly visible, the top colours are amber and red, and a single
/// held peak hangs above the level.
fragment float4 meter_fragment(VOut in [[stage_in]], constant MeterUniforms &u [[buffer(0)]]) {
    const float2 px = in.position.xy;
    const bool vertical = u.vertical > 0.5;
    const float along = vertical ? 1.0 - px.y / u.size.y : px.x / u.size.x;
    const float across = vertical ? px.x / u.size.x : px.y / u.size.y;

    const float gapFraction = 0.12;
    const float barWidth = 1.0 / float(u.bars);
    const float slot = across / barWidth;
    const int bar = clamp(int(floor(slot)), 0, u.bars - 1);
    const float within = slot - float(bar);
    if (u.bars > 1 && (within < gapFraction || within > 1.0 - gapFraction)) return float4(0, 0, 0, 0);

    const float segments = vertical ? 30.0 : 40.0;
    const float position = along * segments;
    const float index = floor(position);
    const float segment = position - index;
    const float lengthPx = (vertical ? u.size.y : u.size.x) / segments;
    const float gap = min(0.35, 0.8 * u.scale / lengthPx);
    if (segment > 1.0 - gap) return float4(0, 0, 0, 0);

    const float fraction = (index + 0.5) / segments;
    float3 tint = float3(0.1, 0.82, 0.3);
    if (fraction > 0.72) tint = float3(0.98, 0.7, 0.08);
    if (fraction > 0.9) tint = float3(1.0, 0.17, 0.13);

    const float level = u.levels[bar], peak = u.peaks[bar];
    const float on = fraction <= level ? 1.0 : 0.0;
    const float isPeak = abs(fraction - peak) < 0.5 / segments && peak > 0.02 ? 1.0 : 0.0;
    const float glow = max(on, isPeak);
    return float4(mix(tint * 0.13, tint, glow), 1);
}

// MARK: Beat and phase display

/// One deck's four beat blocks. `dir` makes them grow outwards from the centre scale.
static inline float3 beatBlocks(float3 color, float2 px, constant PhaseUniforms &u, float beat, float active, float startX, float dir) {
    const float blockW = 18.0 * u.scale, blockGap = 2.5 * u.scale;
    const float inset = 1.5 * u.scale;
    if (px.y < inset || px.y > u.size.y - inset) return color;
    for (int i = 0; i < 4; ++i) {
        const float x0 = startX + dir * (float(i) * (blockW + blockGap));
        const float x1 = x0 + dir * blockW;
        if (px.x < min(x0, x1) || px.x > max(x0, x1)) continue;
        const bool current = beat >= 0 && int(floor(beat)) == i && active > 0.5;
        const float within = beat >= 0 ? fract(beat) : 1.0;
        const float3 tint = i == 0 ? float3(1.0, 0.27, 0.2) : u.accent.rgb;
        const float lit = current ? (1.0 - within * 0.45) : 0.0;
        return tint * 0.13 + tint * lit;
    }
    return color;
}

/// The strip between the two waveforms: four beat blocks per deck, and a centre scale showing how
/// far deck 2 is from deck 1. When they're locked, the centre marker sits still in the middle.
fragment float4 phase_fragment(VOut in [[stage_in]], constant PhaseUniforms &u [[buffer(0)]]) {
    const float2 px = in.position.xy;
    float3 color = float3(0.02, 0.021, 0.025);
    const float midX = u.size.x * 0.5;
    const float h = u.size.y;
    const float scaleHalf = 62.0 * u.scale;
    color = beatBlocks(color, px, u, u.beatA, u.activeA, midX - scaleHalf - 6.0 * u.scale, -1.0);
    color = beatBlocks(color, px, u, u.beatB, u.activeB, midX + scaleHalf + 6.0 * u.scale, 1.0);

    // Centre scale: ticks every eighth of a beat, an index in the middle, and the moving marker.
    const float dx = px.x - midX;
    if (abs(dx) <= scaleHalf) {
        const float tickSpacing = scaleHalf / 4.0;
        const float tick = abs(fract(dx / tickSpacing + 0.5) - 0.5) * tickSpacing;
        if (tick < 0.4 * u.scale && abs(px.y - h * 0.5) < h * 0.22) color += 0.12;
        if (abs(dx) < 0.5 * u.scale) color = float3(0.8);
        if (u.activeA > 0.5 && u.activeB > 0.5) {
            const float markerX = clamp(u.offsetBeats * 2.0, -1.0, 1.0) * scaleHalf;
            const float marker = abs(dx - markerX);
            const float3 tint = abs(u.offsetBeats) < 0.008 ? float3(0.2, 0.95, 0.45) : float3(1.0, 0.62, 0.1);
            if (marker < 2.0 * u.scale) color = tint;
            const float glow = exp(-marker * marker / (36.0 * u.scale * u.scale));
            color += tint * glow * 0.2;
        }
    }
    return float4(color, 1);
}
