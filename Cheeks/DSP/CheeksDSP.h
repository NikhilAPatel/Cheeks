#ifndef CHEEKS_DSP_H
#define CHEEKS_DSP_H

// The realtime audio core, written in C++ so nothing on the render path allocates, locks or
// retains. Swift talks to it through this C API only (it's the app's bridging header).
//
// Threading: setters are called from the main thread and read by the render thread through
// relaxed atomics. Getters read what the render thread last published.

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CheeksDeck CheeksDeck;
typedef struct CheeksEngine CheeksEngine;

/// Beat FX. The first group runs on the deck's FX bus, ahead of the time-stretcher, so an effect
/// can be applied to single stems and stays locked to the track's own beat.
typedef enum {
    CheeksFXNone = 0,
    CheeksFXEcho,
    CheeksFXPingPong,
    CheeksFXReverb,
    CheeksFXFlanger,
    CheeksFXPhaser,
    CheeksFXFilterLFO,
    CheeksFXGate,
    CheeksFXCrush,
    CheeksFXSpiral,
} CheeksFXType;

/// A snapshot for drawing: position in frames, playback speed, and the host time it was taken at.
typedef struct {
    double position;
    double rate;
    uint64_t hostTime;
} CheeksDisplayState;

// MARK: Deck lifecycle and audio

CheeksDeck *cheeks_deck_create(double sampleRate);
void cheeks_deck_destroy(CheeksDeck *deck);

/// One buffer is a full mix; four are stems. `stemScale` converts stem samples to ±1 (mix samples
/// always use 1/32768). The caller keeps the buffers alive until they're replaced.
void cheeks_deck_set_sources(CheeksDeck *deck, const int16_t *const *slots, int count, int64_t frames, float stemScale);
int64_t cheeks_deck_frames(const CheeksDeck *deck);

/// Transport, stems and FX only: what the stretcher (or direct path) produces, before EQ.
void cheeks_deck_render_source(CheeksDeck *deck, float *left, float *right, int frames);
/// The whole channel: source, isolator EQ, filter and metering, before trim and fader.
void cheeks_deck_render_channel(CheeksDeck *deck, float *left, float *right, int frames);

// MARK: Transport

void cheeks_deck_set_playing(CheeksDeck *deck, bool playing);
bool cheeks_deck_playing(const CheeksDeck *deck);
void cheeks_deck_set_reverse(CheeksDeck *deck, bool reverse);
bool cheeks_deck_reverse(const CheeksDeck *deck);

/// The position being heard, in frames: this is the timeline for sync, display and cues.
double cheeks_deck_position(const CheeksDeck *deck);
void cheeks_deck_seek(CheeksDeck *deck, double frame);
/// Moves relative to wherever the playhead is when the audio thread gets to it, so a jump keeps
/// the deck's exact phase.
void cheeks_deck_jump(CheeksDeck *deck, double deltaFrames);
/// Jumps to `frame` plus the current position within the beat, so a jump lands in time.
void cheeks_deck_seek_beat_locked(CheeksDeck *deck, double frame, double beatFrames, double firstBeatFrame);
CheeksDisplayState cheeks_deck_display_state(const CheeksDeck *deck);

bool cheeks_deck_reached_end(const CheeksDeck *deck);
void cheeks_deck_clear_reached_end(CheeksDeck *deck);

double cheeks_deck_nudge(const CheeksDeck *deck);
void cheeks_deck_add_nudge(CheeksDeck *deck, double frames);

/// `ratio` is the playback speed. With key lock the pitch holds; `keyShift` is in semitones.
void cheeks_deck_set_tempo(CheeksDeck *deck, double ratio, bool keyLock, int keyShift);
/// True while the stretcher is in the signal path. Exposed for tests and the CPU readout.
bool cheeks_deck_is_stretching(const CheeksDeck *deck);

// MARK: Scratch, brake, backspin

void cheeks_deck_scratch_begin(CheeksDeck *deck);
void cheeks_deck_scratch_move(CheeksDeck *deck, double deltaFrames);
void cheeks_deck_scratch_end(CheeksDeck *deck);
bool cheeks_deck_scratching(const CheeksDeck *deck);
double cheeks_deck_scratch_target(const CheeksDeck *deck);

/// Slows linearly to a stop over `frames`, like cutting a turntable's power.
void cheeks_deck_brake(CheeksDeck *deck, double frames);
/// Throws the platter backwards; it spins down to a stop over `frames`.
void cheeks_deck_backspin(CheeksDeck *deck, double frames);
bool cheeks_deck_ramping(const CheeksDeck *deck);

// MARK: Loop and slip

void cheeks_deck_set_loop(CheeksDeck *deck, double startFrame, double endFrame, bool active);
void cheeks_deck_set_loop_active(CheeksDeck *deck, bool active);
bool cheeks_deck_loop_active(const CheeksDeck *deck);
double cheeks_deck_loop_start(const CheeksDeck *deck);
double cheeks_deck_loop_end(const CheeksDeck *deck);

void cheeks_deck_slip_engage(CheeksDeck *deck);
/// Ends slip and jumps to where the track would have been.
void cheeks_deck_slip_release(CheeksDeck *deck);
/// Ends slip and stays where the deck is.
void cheeks_deck_slip_cancel(CheeksDeck *deck);
bool cheeks_deck_slip_engaged(const CheeksDeck *deck);
double cheeks_deck_slip_position(const CheeksDeck *deck);

// MARK: Stems, FX, EQ

void cheeks_deck_set_stem_gain(CheeksDeck *deck, int stem, float gain);
float cheeks_deck_stem_level(const CheeksDeck *deck, int stem);

/// The beat grid, for beat-synced FX. `beatFrames` of 0 means no grid is known.
void cheeks_deck_set_grid(CheeksDeck *deck, double beatFrames, double firstBeatFrame);
/// `stemMask` picks the stems that go through the FX bus (bit 0 = first stem); a full mix always does.
void cheeks_deck_set_fx(CheeksDeck *deck, CheeksFXType type, bool on, double beats, float depth, int stemMask);

/// Band gains are linear: 0 is a true kill (the band is removed), 1 is flat.
void cheeks_deck_set_eq(CheeksDeck *deck, float low, float mid, float high);
/// -1...0 sweeps a low-pass down, 0...1 sweeps a high-pass up.
void cheeks_deck_set_filter(CheeksDeck *deck, float amount);

/// Peak level since the last call (pre-fader), decaying like a meter's ballistics.
float cheeks_deck_peak(const CheeksDeck *deck);

// MARK: Engine

/// The decks are owned by the caller and must outlive the engine.
CheeksEngine *cheeks_engine_create(double sampleRate, CheeksDeck *const *decks, int count);
void cheeks_engine_destroy(CheeksEngine *engine);

/// Renders everything into the two output channels. Safe to call from the audio thread.
void cheeks_engine_render(CheeksEngine *engine, float *left, float *right, int frames);

void cheeks_engine_set_channel(CheeksEngine *engine, int channel, float trim, float fader, float cue);
/// `split` puts the master (mono) in the left channel and the cue bus (mono) in the right.
void cheeks_engine_set_master(CheeksEngine *engine, float master, float phones, float programInCue, bool split);

float cheeks_engine_master_peak(const CheeksEngine *engine);
float cheeks_engine_master_peak_right(const CheeksEngine *engine);
/// Current limiter gain reduction, in dB (0 when it isn't working).
float cheeks_engine_limiter_reduction(const CheeksEngine *engine);
/// Fraction of the time available for each render that was actually used (0...1), smoothed.
float cheeks_engine_load(const CheeksEngine *engine);

// Recording: the program bus, written to a lock-free ring by the render thread.
void cheeks_engine_set_recording(CheeksEngine *engine, bool enabled);
/// Reads up to `maxFrames` of captured audio. Call from one thread only.
int cheeks_engine_read_recording(CheeksEngine *engine, float *left, float *right, int maxFrames);
/// Frames dropped because the reader fell behind.
int64_t cheeks_engine_recording_overruns(const CheeksEngine *engine);

// Sampler: one-shots mixed into the program bus. Buffers are interleaved 16-bit stereo.
void cheeks_engine_set_sample(CheeksEngine *engine, int slot, const int16_t *pcm, int64_t frames);
void cheeks_engine_trigger_sample(CheeksEngine *engine, int slot, float gain);
void cheeks_engine_stop_sample(CheeksEngine *engine, int slot);
bool cheeks_engine_sample_active(const CheeksEngine *engine, int slot);

// Preview: an independent player for auditioning tracks from the browser, on the cue bus.
void cheeks_engine_set_preview(CheeksEngine *engine, const int16_t *pcm, int64_t frames);
void cheeks_engine_set_preview_playing(CheeksEngine *engine, bool playing);
void cheeks_engine_seek_preview(CheeksEngine *engine, double frame);
double cheeks_engine_preview_position(const CheeksEngine *engine);
/// With no split cable there's no cue bus to hear, so the preview can play through the master.
void cheeks_engine_set_preview_routing(CheeksEngine *engine, float toCue, float toMaster);

#ifdef __cplusplus
}
#endif

#endif
