// The realtime engine: decks, the time-stretcher, the mixer and the master bus, all rendered
// together in one callback. Nothing below allocates, locks or calls into Swift on the render path.
//
// The key idea is that `position` always means *what is being heard*. Audio is in memory, so when
// the stretcher is in use its input simply reads ahead of `position` by exactly the stretcher's
// latency. That gives three things AVAudioEngine effect chains can't:
//   - Hot cues, jumps and loops are instant, even with key lock on.
//   - Scratching goes straight to the speakers with no time-stretch lag.
//   - Decks stay sample-locked whether or not they're being stretched, since both run on one clock.

#define SIGNALSMITH_USE_ACCELERATE 1

#include "CheeksDSP.h"
#include "BeatFX.hpp"
#include "ColorFX.hpp"
#include "Primitives.hpp"
#include "signalsmith-stretch/signalsmith-stretch.h"

#include <atomic>
#include <cfloat>
#include <cmath>
#include <fenv.h>
#include <limits>
#include <mach/mach_time.h>
#include <memory>
#include <vector>

using namespace cheeks;

namespace {

constexpr int kBlock = 256;
/// The most input the stretcher may take in one block before the deck repositions it instead.
constexpr int kMaxFeed = 1536;
constexpr int kSeekBuffer = 1 << 15;
constexpr int kStems = 4;
constexpr double kNoSeek = std::numeric_limits<double>::quiet_NaN();
// Named differently on Intel, which the generic simulator build includes.
#if defined(__x86_64__)
const fenv_t *const kNoDenormals = FE_DFL_DISABLE_SSE_DENORMS_ENV;
#else
const fenv_t *const kNoDenormals = FE_DFL_DISABLE_DENORMS_ENV;
#endif

inline double clampd(double x, double lo, double hi) { return std::max(lo, std::min(hi, x)); }

/// A spin lock the main thread takes for a few instructions; the render thread only ever tries it.
class TryLock {
public:
    void lock() {
        while (flag.test_and_set(std::memory_order_acquire)) {}
    }
    bool tryLock() { return !flag.test_and_set(std::memory_order_acquire); }
    void unlock() { flag.clear(std::memory_order_release); }

private:
    std::atomic_flag flag = ATOMIC_FLAG_INIT;
};

template <typename T>
inline T relaxed(const std::atomic<T> &a) { return a.load(std::memory_order_relaxed); }
template <typename T>
inline void put(std::atomic<T> &a, T value) { a.store(value, std::memory_order_relaxed); }

inline void addTo(std::atomic<double> &a, double delta) {
    double current = a.load(std::memory_order_relaxed);
    while (!a.compare_exchange_weak(current, current + delta, std::memory_order_relaxed)) {}
}

} // namespace

struct CheeksDeck {
    explicit CheeksDeck(double rate) : sampleRate(rate), stretch(1234L) {
        stretch.configure(2, int(rate * 0.1), int(rate * 0.025), true);
        inputLatency = stretch.inputLatency();
        outputLatency = stretch.outputLatency();
        seekBuffer[0].assign(kSeekBuffer, 0);
        seekBuffer[1].assign(kSeekBuffer, 0);
        for (auto &link : fx) link.prepare(rate);
        color.prepare(rate);
        isolator.prepare(rate);
        filter.prepare(rate);
        for (int s = 0; s < kStems; ++s) {
            stemTarget[s].store(1);
            stemGain[s] = 1;
        }
        for (int l = 0; l < CHEEKS_FX_LINKS; ++l) {
            fxBeats[l].store(1);
            fxDepth[l].store(0.5f);
            fxReleaseBeat[l].store(kNoSeek);
        }
        peakFall = float(std::exp(-double(kBlock) / (0.18 * rate)));
    }

    // MARK: Control state, written by the main thread

    std::atomic<bool> playing{false}, reverse{false}, scratching{false}, loopOn{false}, slipOn{false}, reachedEnd{false};
    std::atomic<bool> keyLock{true}, slipRelease{false}, slipEngage{false}, scratchStart{false};
    std::atomic<double> ratioTarget{1}, scratchMoveIn{0}, loopStart{0}, loopEnd{0}, slipEngageAt{kNoSeek};
    std::atomic<double> pendingSeek{kNoSeek}, pendingDelta{0}, nudgeIn{0};
    std::atomic<double> lockedTarget{kNoSeek}, lockedBeat{0}, lockedFirst{0};
    std::atomic<double> brakeFrames{0}, backspinFrames{0};
    std::atomic<int> keyShift{0};
    std::atomic<float> stemTarget[kStems];
    std::atomic<double> beatFrames{0}, firstBeatFrame{0};

    // FX settings, applied at the start of each block
    std::atomic<int> fxType[CHEEKS_FX_LINKS] = {}, fxStemMask{0xF};
    std::atomic<bool> fxOn[CHEEKS_FX_LINKS] = {};
    std::atomic<double> fxBeats[CHEEKS_FX_LINKS], fxReleaseBeat[CHEEKS_FX_LINKS];
    std::atomic<float> fxDepth[CHEEKS_FX_LINKS];
    std::atomic<double> cutAtBeat{kNoSeek};
    std::atomic<bool> sourceCut{false};
    std::atomic<int> colorType{CheeksColorFilter};
    std::atomic<float> colorAmount{0};

    // MARK: Published state, written by the render thread

    std::atomic<double> published{0}, publishedRate{0}, publishedSlip{0}, publishedNudge{0}, publishedScratchTarget{0};
    std::atomic<uint64_t> publishedHostTime{0};
    std::atomic<bool> stretching{false}, ramping{false};
    std::atomic<float> stemLevel[kStems] = {};
    mutable std::atomic<float> peak{0};

    // MARK: Sources

    void setSources(const int16_t *const *newSlots, int count, int64_t newFrames, float scale) {
        lock.lock();
        for (int s = 0; s < kStems; ++s) slots[s] = s < count ? newSlots[s] : nullptr;
        sourceCount = std::min(count, kStems);
        // The same length means stems replacing their own mix: they sum back to it exactly, so
        // the audio carries straight on. Anything else is a new track.
        newTrack = newTrack || newFrames != frames;
        frames = newFrames;
        stemScale = scale;
        sourceChanged = true;
        lock.unlock();
        put(publishedFrames, newFrames);
    }

    std::atomic<int64_t> publishedFrames{0};

    // MARK: Rendering

    void renderSource(float *left, float *right, int n) {
        if (!lock.tryLock()) {
            std::fill(left, left + n, 0.0f);
            std::fill(right, right + n, 0.0f);
            return;
        }
        int done = 0;
        while (done < n) {
            const int chunk = std::min(n - done, kBlock);
            renderChunk(left + done, right + done, chunk);
            done += chunk;
        }
        lock.unlock();
        put(published, position);
        put(publishedRate, lastRate);
        put(publishedSlip, slipPosition);
        put(publishedNudge, nudge);
        publishedHostTime.store(mach_absolute_time(), std::memory_order_relaxed);
        put(stretching, inStretch);
        put(ramping, ramp != RampNone);
        for (int s = 0; s < kStems; ++s) put(stemLevel[s], blockStemPeak[s]);
    }

    void renderChannel(float *left, float *right, int n) {
        renderSource(left, right, n);
        isolator.process(left, right, n);
        filter.process(left, right, n);
        // Runs in real time, after the stretcher, so a beat is shorter when the deck's been sped up.
        color.process(left, right, n, CheeksColorType(relaxed(colorType)), relaxed(colorAmount), gridBeat() / std::max(ratioNow, 0.05));
        float high = 0;
        for (int i = 0; i < n; ++i) high = std::max(high, std::max(std::abs(left[i]), std::abs(right[i])));
        const float falling = relaxed(peak) * std::pow(peakFall, float(n) / kBlock);
        put(peak, std::max(high, falling));
    }

    double renderPosition() const { return position; }

    /// Where the next line of the beat grid (every `gridBeats`) falls in the block just rendered,
    /// in frames from its start, or -1 if it isn't in this block. `skip` is set when a line has just
    /// gone by: start now, that far in, and it's still in time.
    int framesToGrid(double gridBeats, int n, int64_t &skip) const {
        skip = 0;
        const double beat = relaxed(beatFrames), rate = lastRate;
        if (beat <= 0 || rate < 0.05 || !relaxed(playing)) return 0;
        const double line = gridBeats * beat;
        const double gridPosition = (position - rate * n - relaxed(firstBeatFrame)) / line;
        const double since = (gridPosition - std::floor(gridPosition)) * line / rate;
        if (since < sampleRate * kQuantizeForgiveness) {
            skip = int64_t(since);
            return 0;
        }
        const double until = line / rate - since;
        return until < double(n) ? int(until) : -1;
    }

    Isolator isolator;
    SweepFilter filter;
    ColorFX color;

private:
    static constexpr double kQuantizeForgiveness = 0.03;
    static constexpr double kLongestBeatWait = 3;

    enum Ramp { RampNone, RampBrake, RampBackspin };

    void renderChunk(float *left, float *right, int n) {
        applyCommands();
        if (sourceChanged) {
            sourceChanged = false;
            snapSends = true;
            if (newTrack) {
                newTrack = false;
                if (position >= double(frames)) position = 0;
                declick.trigger();
                stretchDirty = true;
            }
        }
        if (frames < 2 || sourceCount == 0) {
            std::fill(left, left + n, 0.0f);
            std::fill(right, right + n, 0.0f);
            declick.process(left, right, n);
            return;
        }
        updateFX();
        if (snapSends) {
            snapSends = false;
            std::copy(sendTarget, sendTarget + kStems, stemSend);
        }

        const bool isPlaying = relaxed(playing);
        if (isPlaying != wasPlaying) {
            wasPlaying = isPlaying;
            declick.trigger();
        }
        const bool scratch = relaxed(scratching);
        const double ratio = relaxed(ratioTarget);
        const int semitones = relaxed(keyShift);
        const bool keyLocked = relaxed(keyLock);
        // The stretcher only comes into the path when it's really needed. Otherwise the audio is
        // read directly, which sounds exactly like the file and uses almost no CPU.
        const bool settled = !motorActive && ramp == RampNone;
        const bool wantsStretch = isPlaying && !scratch && settled && !relaxed(reverse)
            && (semitones != 0 || (keyLocked && std::abs(ratio - 1) > 1e-6));
        if (wantsStretch != inStretch) {
            inStretch = wantsStretch;
            stretchDirty = wantsStretch;
            declick.trigger();
        }
        if (inStretch) {
            renderStretched(left, right, n, ratio, semitones, keyLocked);
        } else {
            renderDirect(left, right, n);
        }
    }

    void applyCommands() {
        // Slip starts from where the deck is right now, unless a seek was queued before it.
        if (slipEngage.exchange(false, std::memory_order_relaxed)) {
            const double at = relaxed(slipEngageAt);
            slipPosition = std::isnan(at) ? position : at;
        }
        const double seekTo = pendingSeek.exchange(kNoSeek, std::memory_order_relaxed);
        bool jumped = false;
        if (!std::isnan(seekTo)) {
            position = clampd(seekTo, 0, double(std::max<int64_t>(frames - 1, 0)));
            jumped = true;
        }
        const double locked = lockedTarget.exchange(kNoSeek, std::memory_order_relaxed);
        if (!std::isnan(locked)) {
            const double beat = relaxed(lockedBeat), first = relaxed(lockedFirst);
            double within = 0;
            if (beat > 0) {
                const double b = (position - first) / beat;
                within = (b - std::floor(b)) * beat;
            }
            position = clampd(locked + within, 0, double(std::max<int64_t>(frames - 1, 0)));
            jumped = true;
        }
        const double delta = pendingDelta.exchange(0, std::memory_order_relaxed);
        if (delta != 0) {
            position = clampd(position + delta, 0, double(std::max<int64_t>(frames - 1, 0)));
            jumped = true;
        }
        if (slipRelease.exchange(false, std::memory_order_relaxed)) {
            position = clampd(slipPosition, 0, double(std::max<int64_t>(frames - 1, 0)));
            jumped = true;
        }
        if (jumped) {
            declick.trigger();
            stretchDirty = true;
            scratchTargetNow = position;
        }
        if (scratchStart.exchange(false, std::memory_order_relaxed)) {
            scratchRate = relaxed(playing) ? relaxed(ratioTarget) : 0;
            motorActive = false;
            ramp = RampNone;
            scratchTargetNow = position;
        }
        scratchTargetNow += scratchMoveIn.exchange(0, std::memory_order_relaxed);
        put(publishedScratchTarget, scratchTargetNow);
        const bool scratch = relaxed(scratching);
        if (wasScratching && !scratch) {
            // Letting go: the platter spins back up under the motor instead of snapping to speed.
            motorRate = scratchRate;
            motorActive = true;
        }
        wasScratching = scratch;

        nudge += nudgeIn.exchange(0, std::memory_order_relaxed);

        const double brake = brakeFrames.exchange(0, std::memory_order_relaxed);
        if (brake > 0) {
            ramp = RampBrake;
            rampRate = ratioNow;
            rampStep = ratioNow / brake;
        }
        const double backspin = backspinFrames.exchange(0, std::memory_order_relaxed);
        if (backspin > 0) {
            ramp = RampBackspin;
            rampRate = -5;
            rampStep = 5 / backspin;
        }
    }

    void updateFX() {
        const double beat = (position - relaxed(firstBeatFrame)) / gridBeat();
        // A beat might never come: the deck could be in a short loop, in reverse or stopped. So
        // anything waiting for one gives up after a few seconds and happens anyway.
        const double patience = sampleRate * kLongestBeatWait;
        for (int l = 0; l < CHEEKS_FX_LINKS; ++l) {
            const double releaseAt = relaxed(fxReleaseBeat[l]);
            if (std::isnan(releaseAt)) {
                fxReleaseWaited[l] = 0;
            } else if (beat >= releaseAt || (fxReleaseWaited[l] += kBlock) > patience) {
                put(fxReleaseBeat[l], kNoSeek);
                put(fxOn[l], false);
            }
            fx[l].set(CheeksFXType(relaxed(fxType[l])), relaxed(fxOn[l]), relaxed(fxBeats[l]), relaxed(fxDepth[l]));
        }
        const double cutAt = relaxed(cutAtBeat);
        if (std::isnan(cutAt)) {
            cutWaited = 0;
        } else if (beat >= cutAt || (cutWaited += kBlock) > patience) {
            put(cutAtBeat, kNoSeek);
            put(sourceCut, true);
        }
        const int mask = relaxed(fxStemMask);
        for (int s = 0; s < kStems; ++s) sendTarget[s] = sourceCount == 1 || (mask >> s) & 1 ? 1.0f : 0.0f;
    }

    /// The playhead's speed for the next sample.
    inline double nextRate() {
        const double wanted = relaxed(ratioTarget);
        ratioNow += (wanted - ratioNow) * 0.003;
        if (std::abs(wanted - ratioNow) < 1e-7) ratioNow = wanted;

        if (relaxed(scratching)) {
            const double chase = clampd((scratchTargetNow - position) / (sampleRate * 0.015), -8, 8);
            scratchRate += (chase - scratchRate) * 0.01;
            return scratchRate;
        }
        if (ramp != RampNone) {
            if (ramp == RampBrake) {
                rampRate -= rampStep;
                if (rampRate <= 0) {
                    ramp = RampNone;
                    put(playing, false);
                    wasPlaying = false;
                    return 0;
                }
            } else {
                rampRate += rampStep;
                if (rampRate >= 0) {
                    ramp = RampNone;
                    put(playing, false);
                    wasPlaying = false;
                    return 0;
                }
            }
            return rampRate;
        }
        const bool isPlaying = relaxed(playing);
        const double cruising = isPlaying ? (relaxed(reverse) ? -ratioNow : ratioNow) : 0;
        if (motorActive) {
            motorRate += (cruising - motorRate) * 0.0012;
            if (std::abs(cruising - motorRate) < 0.002) motorActive = false;
            return motorRate;
        }
        if (!isPlaying) return 0;
        double rate = cruising;
        if (nudge != 0) {
            const double bend = clampd(nudge * 0.0004, -0.3, 0.3);
            rate += bend;
            nudge -= bend;
            if (std::abs(nudge) < 0.5) nudge = 0;
        }
        return rate;
    }

    /// Moves the playhead one sample. Returns true if a loop just wrapped.
    inline bool advance(double rate) {
        position += rate;
        lastRate = rate;
        if (relaxed(slipOn)) {
            if (relaxed(playing)) slipPosition += ratioNow;
        } else {
            slipPosition = position;
        }
        bool wrapped = false;
        if (loopNow && rate > 0 && position >= loopEndNow && loopEndNow > loopStartNow) {
            position -= loopEndNow - loopStartNow;
            wrapped = true;
        }
        const double last = double(frames - 1);
        if (position >= last) {
            position = last;
            if (relaxed(playing) && !relaxed(scratching)) {
                put(playing, false);
                wasPlaying = false;
                put(reachedEnd, true);
                declick.trigger();
            }
        } else if (position < 0) {
            position = 0;
        }
        return wrapped;
    }

    void readLoopState() {
        loopNow = relaxed(loopOn);
        loopStartNow = relaxed(loopStart);
        loopEndNow = relaxed(loopEnd);
    }

    // MARK: Direct path (speed changes, scratching, or no stretching needed)

    void renderDirect(float *left, float *right, int n) {
        readLoopState();
        int done = 0;
        while (done < n) {
            int count = n - done;
            bool wrapped = false;
            for (int i = 0; i < count; ++i) {
                const double rate = nextRate();
                trace[i] = position;
                speed[i] = rate;
                if (advance(rate)) {
                    wrapped = true;
                    count = i + 1;
                    break;
                }
            }
            readTrace(count);
            const double beat = gridBeat();
            // Effects run at the deck's tempo, so a pause or a scratch doesn't warp an echo already ringing.
            const double clockRate = std::max(ratioNow, 0.05);
            const BeatFX::Clock clock{beat / clockRate, (trace[0] - relaxed(firstBeatFrame)) / beat, speed[0] / beat};
            for (auto &link : fx) link.process(busLeft, busRight, count, clock);
            for (int i = 0; i < count; ++i) {
                left[done + i] = dryLeft[i] + busLeft[i];
                right[done + i] = dryRight[i] + busRight[i];
            }
            declick.process(left + done, right + done, count);
            if (wrapped) declick.trigger();
            done += count;
        }
    }

    /// Reads the positions in `trace` from every stem into the dry and FX buses.
    void readTrace(int n) {
        const int sources = sourceCount;
        const float scale = sources == kStems ? stemScale : 1.0f / 32768;
        const int64_t count = frames;
        std::fill(dryLeft, dryLeft + n, 0.0f);
        std::fill(dryRight, dryRight + n, 0.0f);
        std::fill(busLeft, busLeft + n, 0.0f);
        std::fill(busRight, busRight + n, 0.0f);
        for (int s = 0; s < sources; ++s) {
            const int16_t *p = slots[s];
            const float target = relaxed(sourceCut) ? 0.0f : sources == kStems ? relaxed(stemTarget[s]) : 1.0f;
            float gain = stemGain[s], send = stemSend[s];
            float high = 0;
            for (int i = 0; i < n; ++i) {
                gain += (target - gain) * 0.002f;
                send += (sendTarget[s] - send) * 0.003f;
                if (gain < 0.0001f) continue;
                const double pos = trace[i];
                const int64_t i0 = int64_t(pos);
                if (i0 < 0 || i0 >= count) continue;
                // Like a needle on vinyl: no movement, no sound.
                const float velocity = std::min(1.0f, float(std::abs(speed[i])) * 20);
                if (velocity <= 0) continue;
                const float frac = float(pos - double(i0));
                float l, r;
                if (frac == 0 || i0 < 1 || i0 + 2 >= count) {
                    l = float(p[i0 * 2]);
                    r = float(p[i0 * 2 + 1]);
                } else {
                    const int16_t *q = p + (i0 - 1) * 2;
                    l = hermite(frac, float(q[0]), float(q[2]), float(q[4]), float(q[6]));
                    r = hermite(frac, float(q[1]), float(q[3]), float(q[5]), float(q[7]));
                }
                const float amount = gain * velocity * scale;
                l *= amount;
                r *= amount;
                high = std::max(high, std::abs(l));
                dryLeft[i] += l * (1 - send);
                dryRight[i] += r * (1 - send);
                busLeft[i] += l * send;
                busRight[i] += r * send;
            }
            stemGain[s] = gain;
            stemSend[s] = send;
            blockStemPeak[s] = high;
        }
    }

    // MARK: Stretched path

    /// How far ahead of the heard position the stretcher's input has to be.
    inline double feedLead(double ratio) const { return double(inputLatency) + ratio * double(outputLatency); }

    inline double wrapIntoLoop(double x) const {
        if (loopNow && loopEndNow > loopStartNow && x >= loopEndNow) {
            const double length = loopEndNow - loopStartNow;
            x = loopStartNow + std::fmod(x - loopStartNow, length);
        }
        return x;
    }

    inline double feedError(double expected) const {
        double d = expected - feedPosition;
        if (loopNow && loopEndNow > loopStartNow) {
            const double length = loopEndNow - loopStartNow;
            if (d > length / 2) d -= length;
            if (d < -length / 2) d += length;
        }
        return d;
    }

    void renderStretched(float *left, float *right, int n, double ratio, int semitones, bool keyLocked) {
        readLoopState();
        const float pitchFactor = float(std::pow(2.0, semitones / 12.0) * (keyLocked ? 1.0 : ratio));
        if (pitchFactor != stretchPitch) {
            stretchPitch = pitchFactor;
            stretch.setTransposeFactor(pitchFactor);
        }

        const double lead = feedLead(ratioNow);
        const double predicted = wrapIntoLoop(position + ratioNow * n + lead);
        if (stretchDirty || std::abs(feedError(predicted)) > kMaxFeed) {
            if (!stretchDirty) declick.trigger();
            reposition(ratioNow);
            stretchDirty = false;
        }

        for (int i = 0; i < n; ++i) advance(nextRate());

        const double expected = wrapIntoLoop(position + feedLead(ratioNow));
        const int wanted = int(std::lround(feedError(expected)));
        const int count = std::max(0, std::min(kMaxFeed, wanted));
        readFeed(count);

        float *inputs[2] = {feedLeft, feedRight};
        float *outputs[2] = {left, right};
        stretch.process(inputs, count, outputs, n);
        declick.process(left, right, n);
    }

    /// Reads `count` frames of the stretcher's input, wrapping at loop ends, through the FX bus.
    void readFeed(int count) {
        int done = 0;
        const double beat = gridBeat();
        const double first = relaxed(firstBeatFrame);
        while (done < count) {
            int run = count - done;
            run = std::min(run, kBlock);
            bool wrapped = false;
            if (loopNow && loopEndNow > loopStartNow) {
                const double room = loopEndNow - feedPosition;
                if (room <= 0) {
                    feedPosition = loopStartNow + std::fmod(feedPosition - loopStartNow, loopEndNow - loopStartNow);
                    feedDeclick.trigger();
                    continue;
                }
                if (room <= double(run)) {
                    run = std::max(1, int(std::ceil(room)));
                    wrapped = true;
                }
            }
            for (int i = 0; i < run; ++i) {
                trace[i] = std::floor(feedPosition + i + 0.5);
                speed[i] = 1;
            }
            readTrace(run);
            const BeatFX::Clock clock{beat, (feedPosition - first) / beat, 1 / beat};
            for (auto &link : fx) link.process(busLeft, busRight, run, clock);
            for (int i = 0; i < run; ++i) {
                feedLeft[done + i] = dryLeft[i] + busLeft[i];
                feedRight[done + i] = dryRight[i] + busRight[i];
            }
            feedDeclick.process(feedLeft + done, feedRight + done, run);
            feedPosition += run;
            if (wrapped) {
                feedPosition = loopStartNow + std::max(0.0, feedPosition - loopEndNow);
                feedDeclick.trigger();
            }
            done += run;
        }
    }

    /// Restarts the stretcher so its next output sample is the current position. Its input is
    /// primed from the track, which is why a jump is heard immediately.
    void reposition(double ratio) {
        int length = stretch.outputSeekLength(float(std::max(ratio, 0.05)));
        length = std::min(length, kSeekBuffer);
        const int sources = sourceCount;
        const float scale = sources == kStems ? stemScale : 1.0f / 32768;
        double cursor = position;
        float *seekLeft = seekBuffer[0].data(), *seekRight = seekBuffer[1].data();
        std::fill(seekLeft, seekLeft + length, 0.0f);
        std::fill(seekRight, seekRight + length, 0.0f);
        const int64_t count = frames;
        for (int i = 0; i < length; ++i) {
            const int64_t frame = int64_t(cursor + 0.5);
            if (frame >= 0 && frame < count) {
                for (int s = 0; s < sources; ++s) {
                    const float gain = (sources == kStems ? stemGain[s] : 1.0f) * scale;
                    seekLeft[i] += float(slots[s][frame * 2]) * gain;
                    seekRight[i] += float(slots[s][frame * 2 + 1]) * gain;
                }
            }
            cursor += 1;
            if (loopNow && loopEndNow > loopStartNow && cursor >= loopEndNow) {
                cursor -= loopEndNow - loopStartNow;
            }
        }
        float *inputs[2] = {seekLeft, seekRight};
        stretch.outputSeek(inputs, length);
        feedPosition = cursor;
    }

    inline double gridBeat() const {
        const double beat = relaxed(beatFrames);
        return beat > 0 ? beat : sampleRate * 0.5;
    }

    double sampleRate;

    // Sources are swapped under the lock and only read inside it.
    TryLock lock;
    const int16_t *slots[kStems] = {};
    int sourceCount = 0;
    int64_t frames = 0;
    float stemScale = 1.0f / 16384;
    bool sourceChanged = false, newTrack = false, snapSends = true;

    // Render thread state
    double position = 0, slipPosition = 0, lastRate = 0, nudge = 0;
    double ratioNow = 1, scratchRate = 0, scratchTargetNow = 0, motorRate = 0, rampRate = 0, rampStep = 0;
    bool motorActive = false, wasPlaying = false, wasScratching = false;
    Ramp ramp = RampNone;
    bool loopNow = false;
    double loopStartNow = 0, loopEndNow = 0;

    float stemGain[kStems], stemSend[kStems] = {1, 1, 1, 1}, sendTarget[kStems] = {1, 1, 1, 1};
    float blockStemPeak[kStems] = {};

    signalsmith::stretch::SignalsmithStretch<float, std::mt19937> stretch;
    int inputLatency = 0, outputLatency = 0;
    double feedPosition = 0;
    float stretchPitch = 1;
    bool inStretch = false, stretchDirty = true;

    BeatFX fx[CHEEKS_FX_LINKS];
    double fxReleaseWaited[CHEEKS_FX_LINKS] = {}, cutWaited = 0;
    Declicker declick, feedDeclick;
    float peakFall = 0.99f;

    double trace[kBlock * 2], speed[kBlock * 2];
    float dryLeft[kBlock * 2], dryRight[kBlock * 2], busLeft[kBlock * 2], busRight[kBlock * 2];
    float feedLeft[kMaxFeed + kBlock], feedRight[kMaxFeed + kBlock];
    std::vector<float> seekBuffer[2];

};

// MARK: Engine

namespace {

/// A simple 16-bit stereo player, for the sampler and the browser preview.
struct Voice {
    const int16_t *pcm = nullptr;
    int64_t frames = 0;
    int64_t position = 0;
    bool active = false;
    float gain = 1;

    inline void mixInto(float *left, float *right, int n, float amount) {
        if (!active || !pcm) return;
        const float scale = gain * amount / 32768;
        for (int i = 0; i < n; ++i) {
            if (position >= frames) {
                active = false;
                return;
            }
            left[i] += float(pcm[position * 2]) * scale;
            right[i] += float(pcm[position * 2 + 1]) * scale;
            ++position;
        }
    }
};

/// One sampler pad. Every jump in its audio goes through its own declicker.
struct SamplerVoice {
    Voice voice;
    Declicker declick;
    bool loop = false, pending = false;
    int quantizeDeck = -1;
    double quantizeBeats = 0;
};

constexpr int kSamples = 8;
constexpr int kRecordFrames = 1 << 19; // about 12 s, far more than the drain interval

} // namespace

struct CheeksEngine {
    CheeksEngine(double rate, CheeksDeck *const *newDecks, int count) : sampleRate(rate), deckCount(std::min(count, 4)) {
        for (int d = 0; d < deckCount; ++d) decks[d] = newDecks[d];
        limiter.prepare(rate);
        record.assign(size_t(kRecordFrames) * 2, 0);
        ticksToSeconds = 0;
        mach_timebase_info_data_t base;
        mach_timebase_info(&base);
        ticksToSeconds = double(base.numer) / double(base.denom) * 1e-9;
    }

    void render(float *outLeft, float *outRight, int n) {
        const uint64_t start = mach_absolute_time();
        // Denormals from decaying filters and echo tails can cost a lot of CPU on the render thread.
        fenv_t savedEnv;
        fegetenv(&savedEnv);
        fesetenv(kNoDenormals);
        int done = 0;
        while (done < n) {
            const int chunk = std::min(n - done, kBlock);
            renderChunk(outLeft + done, outRight + done, chunk);
            done += chunk;
        }
        fesetenv(&savedEnv);
        const double used = double(mach_absolute_time() - start) * ticksToSeconds;
        const double available = double(n) / sampleRate;
        const float load = float(used / available);
        const float smoothed = relaxed(cpuLoad);
        put(cpuLoad, load > smoothed ? load : smoothed + (load - smoothed) * 0.02f);
    }

    std::atomic<float> trim[4], fader[4], cue[4];
    std::atomic<float> masterGain{0.9f}, phonesGain{0.8f}, programInCue{0.5f};
    std::atomic<bool> split{false}, recording{false};
    std::atomic<float> masterPeak{0}, masterPeakRight{0}, limiterDB{0}, cpuLoad{0};
    std::atomic<float> previewToCue{1}, previewToMaster{0};
    std::atomic<int> recordWrite{0}, recordRead{0};
    std::atomic<int64_t> overruns{0};
    std::atomic<double> previewSeek{kNoSeek};
    std::atomic<double> previewPosition{0};
    std::atomic<bool> previewPlaying{false};
    std::atomic<float> sampleGain[kSamples];
    std::atomic<bool> sampleTrigger[kSamples], sampleStop[kSamples], sampleActive[kSamples], sampleLoop[kSamples];
    std::atomic<int> sampleDeck[kSamples];
    std::atomic<double> sampleGrid[kSamples];
    std::atomic<float> samplerLevel{1};

    std::atomic<uint32_t> positionSequence{0};
    std::atomic<double> publishedPosition[4] = {};

    TryLock voiceLock;
    SamplerVoice samples[kSamples];
    Voice preview;

    TryLock captureLock;
    int16_t *captureBuffer = nullptr;
    int64_t captureMax = 0, captureCount = 0;
    std::atomic<int64_t> captureProgress{0};
    std::vector<float> record;

private:
    void renderChunk(float *outLeft, float *outRight, int n) {
        std::fill(programLeft, programLeft + n, 0.0f);
        std::fill(programRight, programRight + n, 0.0f);
        std::fill(cueLeft, cueLeft + n, 0.0f);
        std::fill(cueRight, cueRight + n, 0.0f);

        for (int d = 0; d < deckCount; ++d) {
            decks[d]->renderChannel(chLeft, chRight, n);
            const float trimTarget = relaxed(trim[d]), faderTarget = relaxed(fader[d]), cueTarget = relaxed(cue[d]);
            const float trimStep = (trimTarget - trimNow[d]) / n;
            const float faderStep = (faderTarget - faderNow[d]) / n;
            const float cueStep = (cueTarget - cueNow[d]) / n;
            for (int i = 0; i < n; ++i) {
                trimNow[d] += trimStep;
                faderNow[d] += faderStep;
                cueNow[d] += cueStep;
                const float l = chLeft[i] * trimNow[d], r = chRight[i] * trimNow[d];
                cueLeft[i] += l * cueNow[d];
                cueRight[i] += r * cueNow[d];
                programLeft[i] += l * faderNow[d];
                programRight[i] += r * faderNow[d];
            }
            trimNow[d] = trimTarget;
            faderNow[d] = faderTarget;
            cueNow[d] = cueTarget;
        }
        publishPositions();

        if (voiceLock.tryLock()) {
            for (int s = 0; s < kSamples; ++s) renderSampler(s, n);
            const double seekPreview = previewSeek.exchange(kNoSeek, std::memory_order_relaxed);
            if (!std::isnan(seekPreview)) preview.position = int64_t(seekPreview);
            preview.active = relaxed(previewPlaying) && preview.pcm && preview.position < preview.frames;
            if (preview.active) {
                const int64_t before = preview.position;
                preview.mixInto(cueLeft, cueRight, n, relaxed(previewToCue));
                const float toMaster = relaxed(previewToMaster);
                if (toMaster > 0) {
                    preview.position = before;
                    preview.mixInto(programLeft, programRight, n, toMaster);
                }
                put(previewPosition, double(preview.position));
            }
            voiceLock.unlock();
        }

        // The meters read ahead of the limiter, so going into the red means the mix is really over.
        float highLeft = 0, highRight = 0;
        for (int i = 0; i < n; ++i) {
            highLeft = std::max(highLeft, std::abs(programLeft[i]));
            highRight = std::max(highRight, std::abs(programRight[i]));
        }

        limiter.process(programLeft, programRight, n);
        writeCapture(n);
        const float gainNow = limiter.lastGain();
        put(limiterDB, gainNow < 0.9999f ? -20 * std::log10(std::max(gainNow, 0.0001f)) : 0.0f);

        if (relaxed(recording)) pushRecording(n);

        const float masterTarget = relaxed(masterGain), phonesTarget = relaxed(phonesGain), blendTarget = relaxed(programInCue);
        const bool isSplit = relaxed(split);
        const float splitTarget = isSplit ? 1 : 0;
        const float masterStep = (masterTarget - masterNow) / n;
        const float phonesStep = (phonesTarget - phonesNow) / n;
        const float blendStep = (blendTarget - blendNow) / n;
        const float splitStep = (splitTarget - splitNow) / n;
        for (int i = 0; i < n; ++i) {
            masterNow += masterStep;
            phonesNow += phonesStep;
            blendNow += blendStep;
            splitNow += splitStep;
            const float l = programLeft[i] * masterNow, r = programRight[i] * masterNow;
            if (splitNow <= 0) {
                outLeft[i] = l;
                outRight[i] = r;
            } else {
                const float monoMaster = (l + r) * 0.5f;
                const float cueMono = (cueLeft[i] + cueRight[i]) * 0.5f;
                const float programMono = (programLeft[i] + programRight[i]) * 0.5f;
                const float phones = (cueMono + programMono * blendNow) * phonesNow;
                // Soft-clips the cue bus, which sits outside the limiter, so it can't hurt your ears.
                const float softened = phones / (1 + std::abs(phones) * 0.25f);
                outLeft[i] = l + (monoMaster - l) * splitNow;
                outRight[i] = r + (softened - r) * splitNow;
            }
        }
        masterNow = masterTarget;
        phonesNow = phonesTarget;
        blendNow = blendTarget;
        splitNow = splitTarget;

        const float fall = std::pow(0.9937f, float(n) / 16);
        put(masterPeak, std::max(highLeft * masterTarget, relaxed(masterPeak) * fall));
        put(masterPeakRight, std::max(highRight * masterTarget, relaxed(masterPeakRight) * fall));
    }

    /// A sequence lock: the count is odd while the positions are being written, and a reader tries
    /// again if it changed underneath it. The render thread never waits for anyone.
    void publishPositions() {
        const uint32_t sequence = positionSequence.load(std::memory_order_relaxed);
        positionSequence.store(sequence + 1, std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_release);
        for (int d = 0; d < deckCount; ++d) put(publishedPosition[d], decks[d]->renderPosition());
        positionSequence.store(sequence + 2, std::memory_order_release);
    }

    /// Mixes one sampler pad into the program bus.
    void renderSampler(int s, int n) {
        SamplerVoice &pad = samples[s];
        if (sampleTrigger[s].exchange(false, std::memory_order_relaxed) && pad.voice.pcm) {
            pad.pending = true;
            pad.quantizeDeck = relaxed(sampleDeck[s]);
            pad.quantizeBeats = relaxed(sampleGrid[s]);
            pad.voice.gain = relaxed(sampleGain[s]);
        }
        pad.loop = relaxed(sampleLoop[s]);
        const bool stop = sampleStop[s].exchange(false, std::memory_order_relaxed);
        if (stop) pad.pending = false;
        if (!pad.pending && !pad.voice.active && !pad.declick.busy() && !stop) {
            put(sampleActive[s], false);
            return;
        }
        std::fill(voiceLeft, voiceLeft + n, 0.0f);
        std::fill(voiceRight, voiceRight + n, 0.0f);
        if (stop && pad.voice.active) {
            pad.voice.active = false;
            pad.declick.trigger();
        }
        int from = 0;
        if (pad.pending) {
            int64_t skip = 0;
            const bool locked = pad.quantizeDeck >= 0 && pad.quantizeDeck < deckCount;
            const int offset = locked ? decks[pad.quantizeDeck]->framesToGrid(pad.quantizeBeats, n, skip) : 0;
            if (offset >= 0) {
                // Whatever was playing carries on up to the moment the new one starts.
                renderVoice(pad, 0, offset);
                if (pad.voice.active) {
                    pad.declick.trigger();
                } else {
                    pad.declick.reset();
                }
                pad.voice.position = std::min(skip, pad.voice.frames);
                pad.voice.active = true;
                pad.pending = false;
                from = offset;
            }
        }
        renderVoice(pad, from, n);
        const float level = relaxed(samplerLevel);
        for (int i = 0; i < n; ++i) {
            programLeft[i] += voiceLeft[i] * level;
            programRight[i] += voiceRight[i] * level;
        }
        put(sampleActive[s], pad.voice.active || pad.pending);
    }

    /// Runs a pad from `from` up to `to` in the voice buffers, wrapping or ending as it goes.
    void renderVoice(SamplerVoice &pad, int from, int to) {
        Voice &v = pad.voice;
        int i = from;
        while (i < to && v.active && v.pcm) {
            const int run = int(std::min<int64_t>(to - i, v.frames - v.position));
            const float scale = v.gain / 32768;
            for (int k = 0; k < run; ++k) {
                voiceLeft[i + k] = float(v.pcm[(v.position + k) * 2]) * scale;
                voiceRight[i + k] = float(v.pcm[(v.position + k) * 2 + 1]) * scale;
            }
            v.position += run;
            pad.declick.process(voiceLeft + i, voiceRight + i, run);
            i += run;
            if (v.position >= v.frames) {
                if (pad.loop && v.frames > 0) {
                    v.position = 0;
                } else {
                    v.active = false;
                }
                pad.declick.trigger();
            }
        }
        if (i < to) pad.declick.process(voiceLeft + i, voiceRight + i, to - i);
    }

    void writeCapture(int n) {
        if (!captureLock.tryLock()) return;
        if (captureBuffer) {
            const int64_t count = std::min<int64_t>(n, captureMax - captureCount);
            int16_t *out = captureBuffer + captureCount * 2;
            for (int64_t i = 0; i < count; ++i) {
                out[i * 2] = int16_t(clampd(programLeft[i], -1, 1) * 32767);
                out[i * 2 + 1] = int16_t(clampd(programRight[i], -1, 1) * 32767);
            }
            captureCount += count;
            put(captureProgress, captureCount);
        }
        captureLock.unlock();
    }

    void pushRecording(int n) {
        int write = recordWrite.load(std::memory_order_relaxed);
        const int read = recordRead.load(std::memory_order_acquire);
        const int used = (write - read + kRecordFrames) % kRecordFrames;
        const int room = kRecordFrames - 1 - used;
        if (room < n) {
            overruns.fetch_add(n, std::memory_order_relaxed);
            return;
        }
        for (int i = 0; i < n; ++i) {
            record[size_t(write) * 2] = programLeft[i];
            record[size_t(write) * 2 + 1] = programRight[i];
            write = (write + 1) % kRecordFrames;
        }
        recordWrite.store(write, std::memory_order_release);
    }

    double sampleRate, ticksToSeconds;
    int deckCount;
    CheeksDeck *decks[4] = {};
    Limiter limiter;
    float trimNow[4] = {1, 1, 1, 1}, faderNow[4] = {}, cueNow[4] = {};
    float masterNow = 0.9f, phonesNow = 0.8f, blendNow = 0.5f, splitNow = 0;
    float chLeft[kBlock], chRight[kBlock], programLeft[kBlock], programRight[kBlock], cueLeft[kBlock], cueRight[kBlock];
    float voiceLeft[kBlock], voiceRight[kBlock];
};

// MARK: C API

extern "C" {

CheeksDeck *cheeks_deck_create(double sampleRate) { return new CheeksDeck(sampleRate); }
void cheeks_deck_destroy(CheeksDeck *deck) { delete deck; }

void cheeks_deck_set_sources(CheeksDeck *deck, const int16_t *const *slots, int count, int64_t frames, float stemScale) {
    deck->setSources(slots, count, frames, stemScale);
}
int64_t cheeks_deck_frames(const CheeksDeck *deck) { return relaxed(deck->publishedFrames); }

void cheeks_deck_render_source(CheeksDeck *deck, float *left, float *right, int frames) {
    fenv_t saved;
    fegetenv(&saved);
    fesetenv(kNoDenormals);
    deck->renderSource(left, right, frames);
    fesetenv(&saved);
}
void cheeks_deck_render_channel(CheeksDeck *deck, float *left, float *right, int frames) {
    fenv_t saved;
    fegetenv(&saved);
    fesetenv(kNoDenormals);
    int done = 0;
    while (done < frames) {
        const int chunk = std::min(frames - done, kBlock);
        deck->renderChannel(left + done, right + done, chunk);
        done += chunk;
    }
    fesetenv(&saved);
}

void cheeks_deck_set_playing(CheeksDeck *deck, bool playing) { put(deck->playing, playing); }
bool cheeks_deck_playing(const CheeksDeck *deck) { return relaxed(deck->playing); }
void cheeks_deck_set_reverse(CheeksDeck *deck, bool reverse) { put(deck->reverse, reverse); }
bool cheeks_deck_reverse(const CheeksDeck *deck) { return relaxed(deck->reverse); }

double cheeks_deck_position(const CheeksDeck *deck) {
    const double seek = relaxed(deck->pendingSeek);
    return std::isnan(seek) ? relaxed(deck->published) : seek;
}
void cheeks_deck_seek(CheeksDeck *deck, double frame) {
    put(deck->pendingSeek, frame);
    // The slip position follows too, unless slip is holding it.
    put(deck->published, frame);
}
void cheeks_deck_jump(CheeksDeck *deck, double deltaFrames) {
    const double seek = relaxed(deck->pendingSeek);
    if (!std::isnan(seek)) {
        put(deck->pendingSeek, std::max(0.0, seek + deltaFrames));
    } else {
        addTo(deck->pendingDelta, deltaFrames);
    }
    put(deck->published, std::max(0.0, relaxed(deck->published) + deltaFrames));
}
void cheeks_deck_seek_beat_locked(CheeksDeck *deck, double frame, double beatFrames, double firstBeatFrame) {
    put(deck->lockedBeat, beatFrames);
    put(deck->lockedFirst, firstBeatFrame);
    put(deck->lockedTarget, frame);
    double within = 0;
    if (beatFrames > 0) {
        const double b = (relaxed(deck->published) - firstBeatFrame) / beatFrames;
        within = (b - std::floor(b)) * beatFrames;
    }
    put(deck->published, frame + within);
}
CheeksDisplayState cheeks_deck_display_state(const CheeksDeck *deck) {
    CheeksDisplayState state;
    state.position = relaxed(deck->published);
    state.rate = relaxed(deck->publishedRate);
    state.hostTime = relaxed(deck->publishedHostTime);
    return state;
}

bool cheeks_deck_reached_end(const CheeksDeck *deck) { return relaxed(deck->reachedEnd); }
void cheeks_deck_clear_reached_end(CheeksDeck *deck) { put(deck->reachedEnd, false); }

double cheeks_deck_nudge(const CheeksDeck *deck) { return relaxed(deck->nudgeIn) + relaxed(deck->publishedNudge); }
void cheeks_deck_add_nudge(CheeksDeck *deck, double frames) { addTo(deck->nudgeIn, frames); }

void cheeks_deck_set_tempo(CheeksDeck *deck, double ratio, bool keyLock, int keyShift) {
    put(deck->ratioTarget, std::max(0.01, ratio));
    put(deck->keyLock, keyLock);
    put(deck->keyShift, keyShift);
}
bool cheeks_deck_is_stretching(const CheeksDeck *deck) { return relaxed(deck->stretching); }

void cheeks_deck_scratch_begin(CheeksDeck *deck) {
    put(deck->publishedScratchTarget, cheeks_deck_position(deck));
    put(deck->scratchStart, true);
    put(deck->scratching, true);
}
void cheeks_deck_scratch_move(CheeksDeck *deck, double deltaFrames) { addTo(deck->scratchMoveIn, deltaFrames); }
void cheeks_deck_scratch_end(CheeksDeck *deck) { put(deck->scratching, false); }
bool cheeks_deck_scratching(const CheeksDeck *deck) { return relaxed(deck->scratching); }
double cheeks_deck_scratch_target(const CheeksDeck *deck) { return relaxed(deck->publishedScratchTarget) + relaxed(deck->scratchMoveIn); }

void cheeks_deck_brake(CheeksDeck *deck, double frames) { put(deck->brakeFrames, frames); put(deck->ramping, true); }
void cheeks_deck_backspin(CheeksDeck *deck, double frames) { put(deck->backspinFrames, frames); put(deck->ramping, true); }
bool cheeks_deck_ramping(const CheeksDeck *deck) { return relaxed(deck->ramping); }

void cheeks_deck_set_loop(CheeksDeck *deck, double startFrame, double endFrame, bool active) {
    put(deck->loopStart, startFrame);
    put(deck->loopEnd, endFrame);
    put(deck->loopOn, active);
}
void cheeks_deck_set_loop_active(CheeksDeck *deck, bool active) { put(deck->loopOn, active); }
bool cheeks_deck_loop_active(const CheeksDeck *deck) { return relaxed(deck->loopOn); }
double cheeks_deck_loop_start(const CheeksDeck *deck) { return relaxed(deck->loopStart); }
double cheeks_deck_loop_end(const CheeksDeck *deck) { return relaxed(deck->loopEnd); }

void cheeks_deck_slip_engage(CheeksDeck *deck) {
    put(deck->publishedSlip, cheeks_deck_position(deck));
    put(deck->slipEngageAt, relaxed(deck->pendingSeek));
    put(deck->slipEngage, true);
    put(deck->slipOn, true);
}
void cheeks_deck_slip_release(CheeksDeck *deck) {
    if (!relaxed(deck->slipOn)) return;
    put(deck->slipOn, false);
    put(deck->slipRelease, true);
    put(deck->published, relaxed(deck->publishedSlip));
}
void cheeks_deck_slip_cancel(CheeksDeck *deck) { put(deck->slipOn, false); }
bool cheeks_deck_slip_engaged(const CheeksDeck *deck) { return relaxed(deck->slipOn); }
double cheeks_deck_slip_position(const CheeksDeck *deck) { return relaxed(deck->publishedSlip); }

void cheeks_deck_set_stem_gain(CheeksDeck *deck, int stem, float gain) {
    if (stem >= 0 && stem < kStems) put(deck->stemTarget[stem], gain);
}
float cheeks_deck_stem_level(const CheeksDeck *deck, int stem) {
    return stem >= 0 && stem < kStems ? relaxed(deck->stemLevel[stem]) : 0;
}

void cheeks_deck_set_grid(CheeksDeck *deck, double beatFrames, double firstBeatFrame) {
    put(deck->beatFrames, beatFrames);
    put(deck->firstBeatFrame, firstBeatFrame);
}
void cheeks_deck_set_fx(CheeksDeck *deck, CheeksFXType type, bool on, double beats, float depth, int stemMask) {
    cheeks_deck_set_fx_link(deck, 0, type, on, beats, depth);
    cheeks_deck_set_fx_stems(deck, stemMask);
}
void cheeks_deck_set_fx_link(CheeksDeck *deck, int link, CheeksFXType type, bool on, double beats, float depth) {
    if (link < 0 || link >= CHEEKS_FX_LINKS) return;
    put(deck->fxType[link], int(type));
    put(deck->fxOn[link], on);
    put(deck->fxBeats[link], beats);
    put(deck->fxDepth[link], depth);
    // Whatever's asked for now replaces a release that was waiting.
    put(deck->fxReleaseBeat[link], kNoSeek);
}
void cheeks_deck_set_fx_stems(CheeksDeck *deck, int stemMask) { put(deck->fxStemMask, stemMask); }
void cheeks_deck_release_fx_at(CheeksDeck *deck, int link, double beat) {
    if (link >= 0 && link < CHEEKS_FX_LINKS) put(deck->fxReleaseBeat[link], beat);
}
void cheeks_deck_cut_source_at(CheeksDeck *deck, double beat) { put(deck->cutAtBeat, beat); }
void cheeks_deck_restore_source(CheeksDeck *deck) {
    put(deck->cutAtBeat, kNoSeek);
    put(deck->sourceCut, false);
}
bool cheeks_deck_source_cut(const CheeksDeck *deck) { return relaxed(deck->sourceCut) || !std::isnan(relaxed(deck->cutAtBeat)); }

void cheeks_deck_set_eq(CheeksDeck *deck, float low, float mid, float high) { deck->isolator.setGains(low, mid, high); }
void cheeks_deck_set_filter(CheeksDeck *deck, float amount) { deck->filter.setAmount(amount); }
void cheeks_deck_set_color(CheeksDeck *deck, CheeksColorType type, float amount) {
    put(deck->colorType, int(type));
    put(deck->colorAmount, amount);
}
float cheeks_deck_peak(const CheeksDeck *deck) { return relaxed(deck->peak); }

CheeksEngine *cheeks_engine_create(double sampleRate, CheeksDeck *const *decks, int count) {
    auto *engine = new CheeksEngine(sampleRate, decks, count);
    for (int d = 0; d < 4; ++d) {
        engine->trim[d].store(1);
        engine->fader[d].store(0);
        engine->cue[d].store(0);
    }
    for (int s = 0; s < kSamples; ++s) {
        engine->sampleGain[s].store(1);
        engine->sampleTrigger[s].store(false);
        engine->sampleStop[s].store(false);
        engine->sampleActive[s].store(false);
        engine->sampleLoop[s].store(false);
        engine->sampleDeck[s].store(-1);
        engine->sampleGrid[s].store(0);
    }
    return engine;
}
void cheeks_engine_destroy(CheeksEngine *engine) { delete engine; }

void cheeks_engine_render(CheeksEngine *engine, float *left, float *right, int frames) { engine->render(left, right, frames); }

void cheeks_engine_set_channel(CheeksEngine *engine, int channel, float trim, float fader, float cue) {
    if (channel < 0 || channel >= 4) return;
    put(engine->trim[channel], trim);
    put(engine->fader[channel], fader);
    put(engine->cue[channel], cue);
}
void cheeks_engine_set_master(CheeksEngine *engine, float master, float phones, float programInCue, bool split) {
    put(engine->masterGain, master);
    put(engine->phonesGain, phones);
    put(engine->programInCue, programInCue);
    put(engine->split, split);
}

void cheeks_engine_positions(const CheeksEngine *engine, double *positions, int count) {
    const int n = std::min(count, 4);
    // A few tries is plenty: the writer takes nanoseconds, and every block or so at most.
    for (int attempt = 0; attempt < 16; ++attempt) {
        const uint32_t before = engine->positionSequence.load(std::memory_order_acquire);
        if (before & 1) continue;
        for (int d = 0; d < n; ++d) positions[d] = relaxed(engine->publishedPosition[d]);
        std::atomic_thread_fence(std::memory_order_acquire);
        if (engine->positionSequence.load(std::memory_order_relaxed) == before) return;
    }
    for (int d = 0; d < n; ++d) positions[d] = relaxed(engine->publishedPosition[d]);
}

float cheeks_engine_master_peak(const CheeksEngine *engine) { return relaxed(engine->masterPeak); }
float cheeks_engine_master_peak_right(const CheeksEngine *engine) { return relaxed(engine->masterPeakRight); }
float cheeks_engine_limiter_reduction(const CheeksEngine *engine) { return relaxed(engine->limiterDB); }
float cheeks_engine_load(const CheeksEngine *engine) { return relaxed(engine->cpuLoad); }

void cheeks_engine_set_recording(CheeksEngine *engine, bool enabled) { put(engine->recording, enabled); }

int cheeks_engine_read_recording(CheeksEngine *engine, float *left, float *right, int maxFrames) {
    int read = engine->recordRead.load(std::memory_order_relaxed);
    const int write = engine->recordWrite.load(std::memory_order_acquire);
    const int available = (write - read + kRecordFrames) % kRecordFrames;
    const int count = std::min(available, maxFrames);
    for (int i = 0; i < count; ++i) {
        left[i] = engine->record[size_t(read) * 2];
        right[i] = engine->record[size_t(read) * 2 + 1];
        read = (read + 1) % kRecordFrames;
    }
    engine->recordRead.store(read, std::memory_order_release);
    return count;
}
int64_t cheeks_engine_recording_overruns(const CheeksEngine *engine) { return engine->overruns.load(std::memory_order_relaxed); }

void cheeks_engine_set_sample(CheeksEngine *engine, int slot, const int16_t *pcm, int64_t frames) {
    if (slot < 0 || slot >= kSamples) return;
    engine->voiceLock.lock();
    engine->samples[slot].voice.pcm = pcm;
    engine->samples[slot].voice.frames = frames;
    engine->samples[slot].voice.active = false;
    engine->samples[slot].pending = false;
    engine->voiceLock.unlock();
}
void cheeks_engine_trigger_sample(CheeksEngine *engine, int slot, float gain) {
    cheeks_engine_trigger_sample_quantized(engine, slot, gain, -1, 0);
}
void cheeks_engine_trigger_sample_quantized(CheeksEngine *engine, int slot, float gain, int deck, double gridBeats) {
    if (slot < 0 || slot >= kSamples) return;
    put(engine->sampleGain[slot], gain);
    put(engine->sampleDeck[slot], deck);
    put(engine->sampleGrid[slot], gridBeats);
    // The last thing asked for wins, even if the render thread hasn't seen the one before it.
    put(engine->sampleStop[slot], false);
    put(engine->sampleTrigger[slot], true);
    put(engine->sampleActive[slot], true);
}
void cheeks_engine_stop_sample(CheeksEngine *engine, int slot) {
    if (slot < 0 || slot >= kSamples) return;
    put(engine->sampleTrigger[slot], false);
    put(engine->sampleStop[slot], true);
}
bool cheeks_engine_sample_active(const CheeksEngine *engine, int slot) {
    return slot >= 0 && slot < kSamples && relaxed(engine->sampleActive[slot]);
}

void cheeks_engine_set_sample_loop(CheeksEngine *engine, int slot, bool loop) {
    if (slot >= 0 && slot < kSamples) put(engine->sampleLoop[slot], loop);
}
void cheeks_engine_set_sampler_level(CheeksEngine *engine, float level) { put(engine->samplerLevel, level); }

void cheeks_engine_capture_start(CheeksEngine *engine, int16_t *buffer, int64_t maxFrames) {
    engine->captureLock.lock();
    engine->captureBuffer = buffer;
    engine->captureMax = maxFrames;
    engine->captureCount = 0;
    engine->captureLock.unlock();
    put(engine->captureProgress, int64_t(0));
}
int64_t cheeks_engine_capture_stop(CheeksEngine *engine) {
    engine->captureLock.lock();
    engine->captureBuffer = nullptr;
    const int64_t count = engine->captureCount;
    engine->captureLock.unlock();
    return count;
}
int64_t cheeks_engine_capture_frames(const CheeksEngine *engine) { return relaxed(engine->captureProgress); }

void cheeks_engine_set_preview(CheeksEngine *engine, const int16_t *pcm, int64_t frames) {
    engine->voiceLock.lock();
    engine->preview.pcm = pcm;
    engine->preview.frames = frames;
    engine->preview.position = 0;
    engine->preview.active = false;
    engine->voiceLock.unlock();
    put(engine->previewPosition, 0.0);
}
void cheeks_engine_set_preview_playing(CheeksEngine *engine, bool playing) { put(engine->previewPlaying, playing); }
void cheeks_engine_seek_preview(CheeksEngine *engine, double frame) {
    put(engine->previewSeek, frame);
    put(engine->previewPosition, frame);
}
double cheeks_engine_preview_position(const CheeksEngine *engine) { return relaxed(engine->previewPosition); }
void cheeks_engine_set_preview_routing(CheeksEngine *engine, float toCue, float toMaster) {
    put(engine->previewToCue, toCue);
    put(engine->previewToMaster, toMaster);
}

} // extern "C"
