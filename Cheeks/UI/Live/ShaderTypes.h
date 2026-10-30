#ifndef CHEEKS_SHADER_TYPES_H
#define CHEEKS_SHADER_TYPES_H

// Uniforms shared by Swift and Metal. Everything that moves on screen is drawn from these,
// on the GPU, so a frame costs the main thread almost nothing.

#include <simd/simd.h>

#define WAVE_ROW_WIDTH 4096
#define WAVE_LEVELS 6
#define WAVE_MAX_CUES 10
#define WAVE_MAX_SECTIONS 24

typedef struct {
    simd_float2 size;           // drawable size in pixels
    float scale;                // pixels per point
    float playheadX;            // pixels from the left
    float startSeconds;         // track time at the left edge
    float secondsPerPixel;      // track seconds per pixel; already allows for the deck's tempo
    float binsPerSecond;
    float binsPerPixel;

    int level;                  // which max-pooled level of the bin atlas to read
    int levelRow[WAVE_LEVELS];  // first atlas row of each level
    int levelCount[WAVE_LEVELS];// bins in each level

    int sectionCount;           // tempo sections on screen; 0 when there's no grid
    float padding0;
    float position;             // track time at the playhead
    float duration;

    float loopStart;            // < 0 when no loop is set
    float loopEnd;
    float loopActive;
    float cuePoint;

    float memoryCue;            // < 0 when unset
    int cueCount;
    float reveal;               // 0...1, the waveform opening out when a track loads
    float stemBlend;            // 0 = 3-band colours, 1 = stem colours

    simd_float4 stemGains;      // heard level of each stem, order vocals, melody, bass, drums
    simd_float4 lowColor;
    simd_float4 midColor;
    simd_float4 highColor;
    simd_float4 stemColors[4];
    int colorStyle;             // 0 = 3-band, 1 = RGB
    float beatPulse;            // 1 on the beat, decaying
    float loaded;
    float padding;
} WaveUniforms;

typedef struct {
    simd_float2 size;
    float scale;
    float progress;             // 0...1 through the track
    float duration;
    float warn;                 // 1 in the last 30 seconds, blinking
    float loopStart;            // seconds, < 0 when none
    float loopEnd;
    float loopActive;
    float memoryCue;
    float cuePoint;
    int cueCount;
    float hover;                // 0...1, brightens while it's being touched
    float padding;
    simd_float4 lowColor;
    simd_float4 midColor;
    simd_float4 highColor;
} OverviewUniforms;

typedef struct {
    simd_float2 size;
    float scale;
    float rotation;             // platter angle in radians
    float progress;             // 0...1 through the track
    float warn;                 // last-30-seconds warning, 0...1
    float touchPlatter;         // 0...1, eased
    float touchRing;            // 0...1, eased
    float cueAngle;             // radians relative to the platter; 99 when off the ring
    float loopFrom;             // loop arc in radians relative to the platter; 99 when off
    float loopTo;
    float beatPulse;            // 1 on the beat, decaying
    float wake;                 // 0...1, the ring sweeping on at launch or on load
    float loaded;
    float hasArt;
    float artDim;
    float padding;
    simd_float4 ledColor;
    simd_float4 labelColor;     // tint for the generated label when a track has no artwork
    simd_float4 vinylTint;      // faint tint from the artwork's dominant colour
} JogUniforms;

typedef struct {
    simd_float2 size;
    float scale;
    float padding;
    float levels[4];            // eased level per bar, 0...1 on the meter's scale
    float peaks[4];             // held peak per bar
    int bars;
    float limit;                // limiter activity, 0...1
    float vertical;
    float padding2;
} MeterUniforms;

typedef struct {
    simd_float2 size;
    float scale;
    float beatA;                // position in the bar, 0...4, or < 0 when there's no grid
    float beatB;
    float offsetBeats;          // phase difference of deck 2 from deck 1, in beats, -0.5...0.5
    float synced;
    float activeA;
    float activeB;
    float padding;
    simd_float4 accent;
} PhaseUniforms;

#endif
