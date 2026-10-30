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
        fx.prepare(rate);
        isolator.prepare(rate);
        filter.prepare(rate);
        for (int s = 0; s < kStems; ++s) {
            stemTarget[s].store(1);
            stemGain[s] = 1;
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
    std::atomic<int> fxType{CheeksFXNone}, fxStemMask{0xF};
    std::atomic<bool> fxOn{false};
    std::atomic<double> fxBeats{1};
    std::atomic<float> fxDepth{0.5f};

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
        float high = 0;
        for (int i = 0; i < n; ++i) high = std::max(high, std::max(std::abs(left[i]), std::abs(right[i])));
        const float falling = relaxed(peak) * std::pow(peakFall, float(n) / kBlock);
        put(peak, std::max(high, falling));
    }

    Isolator isolator;
    SweepFilter filter;

private:
    enum Ramp { RampNone, RampBrake, RampBackspin };

    void renderChunk(float *left, float *right, int n) {
        applyCommands();
        if (sourceChanged) {
            sourceChanged = false;
            if (position >= double(frames)) position = 0;
            snapSends = true;
            declick.trigger();
            stretchDirty = true;
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
        fx.set(CheeksFXType(relaxed(fxType)), relaxed(fxOn), relaxed(fxBeats), relaxed(fxDepth));
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
            fx.process(busLeft, busRight, count, clock);
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
            const float target = sources == kStems ? relaxed(stemTarget[s]) : 1.0f;
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
            fx.process(busLeft, busRight, run, clock);
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
    bool sourceChanged = false, snapSends = true;

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

    BeatFX fx;
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
        fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
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
    std::atomic<float> masterPeak{0}, limiterDB{0}, cpuLoad{0};
    std::atomic<float> previewToCue{1}, previewToMaster{0};
    std::atomic<int> recordWrite{0}, recordRead{0};
    std::atomic<int64_t> overruns{0};
    std::atomic<double> previewSeek{kNoSeek};
    std::atomic<double> previewPosition{0};
    std::atomic<bool> previewPlaying{false};
    std::atomic<float> sampleGain[kSamples];
    std::atomic<bool> sampleTrigger[kSamples], sampleStop[kSamples], sampleActive[kSamples];

    TryLock voiceLock;
    Voice samples[kSamples];
    Voice preview;
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

        if (voiceLock.tryLock()) {
            for (int s = 0; s < kSamples; ++s) {
                if (sampleTrigger[s].exchange(false, std::memory_order_relaxed) && samples[s].pcm) {
                    samples[s].position = 0;
                    samples[s].active = true;
                    samples[s].gain = relaxed(sampleGain[s]);
                }
                if (sampleStop[s].exchange(false, std::memory_order_relaxed)) samples[s].active = false;
                samples[s].mixInto(programLeft, programRight, n, 1);
                put(sampleActive[s], samples[s].active);
            }
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

        limiter.process(programLeft, programRight, n);
        const float gainNow = limiter.lastGain();
        put(limiterDB, gainNow < 0.9999f ? -20 * std::log10(std::max(gainNow, 0.0001f)) : 0.0f);

        float high = 0;
        for (int i = 0; i < n; ++i) high = std::max(high, std::max(std::abs(programLeft[i]), std::abs(programRight[i])));

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

        const float fall = relaxed(masterPeak) * std::pow(0.9937f, float(n) / 16);
        put(masterPeak, std::max(high * masterTarget, fall));
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
    fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
    deck->renderSource(left, right, frames);
    fesetenv(&saved);
}
void cheeks_deck_render_channel(CheeksDeck *deck, float *left, float *right, int frames) {
    fenv_t saved;
    fegetenv(&saved);
    fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
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
    put(deck->fxType, int(type));
    put(deck->fxOn, on);
    put(deck->fxBeats, beats);
    put(deck->fxDepth, depth);
    put(deck->fxStemMask, stemMask);
}

void cheeks_deck_set_eq(CheeksDeck *deck, float low, float mid, float high) { deck->isolator.setGains(low, mid, high); }
void cheeks_deck_set_filter(CheeksDeck *deck, float amount) { deck->filter.setAmount(amount); }
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

float cheeks_engine_master_peak(const CheeksEngine *engine) { return relaxed(engine->masterPeak); }
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
    engine->samples[slot].pcm = pcm;
    engine->samples[slot].frames = frames;
    engine->samples[slot].active = false;
    engine->voiceLock.unlock();
}
void cheeks_engine_trigger_sample(CheeksEngine *engine, int slot, float gain) {
    if (slot < 0 || slot >= kSamples) return;
    put(engine->sampleGain[slot], gain);
    put(engine->sampleTrigger[slot], true);
    put(engine->sampleActive[slot], true);
}
void cheeks_engine_stop_sample(CheeksEngine *engine, int slot) {
    if (slot >= 0 && slot < kSamples) put(engine->sampleStop[slot], true);
}
bool cheeks_engine_sample_active(const CheeksEngine *engine, int slot) {
    return slot >= 0 && slot < kSamples && relaxed(engine->sampleActive[slot]);
}

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
