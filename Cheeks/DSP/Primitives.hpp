#pragma once

#include <algorithm>
#include <cmath>
#include <cstring>

// Small building blocks for the render path. Nothing here allocates once constructed.
namespace cheeks {

constexpr double kPi = 3.14159265358979323846;

/// Transposed direct form II biquad.
struct Biquad {
    float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    float z1 = 0, z2 = 0;

    inline float process(float x) {
        const float y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return y;
    }

    void reset() { z1 = z2 = 0; }

    static Biquad lowpass(double frequency, double q, double sampleRate) {
        const double w = 2 * kPi * frequency / sampleRate, c = std::cos(w), alpha = std::sin(w) / (2 * q);
        const double a0 = 1 + alpha;
        Biquad f;
        f.b0 = float((1 - c) / 2 / a0);
        f.b1 = float((1 - c) / a0);
        f.b2 = f.b0;
        f.a1 = float(-2 * c / a0);
        f.a2 = float((1 - alpha) / a0);
        return f;
    }

    static Biquad highpass(double frequency, double q, double sampleRate) {
        const double w = 2 * kPi * frequency / sampleRate, c = std::cos(w), alpha = std::sin(w) / (2 * q);
        const double a0 = 1 + alpha;
        Biquad f;
        f.b0 = float((1 + c) / 2 / a0);
        f.b1 = float(-(1 + c) / a0);
        f.b2 = f.b0;
        f.a1 = float(-2 * c / a0);
        f.a2 = float((1 - alpha) / a0);
        return f;
    }

    static Biquad allpass(double frequency, double q, double sampleRate) {
        const double w = 2 * kPi * frequency / sampleRate, c = std::cos(w), alpha = std::sin(w) / (2 * q);
        const double a0 = 1 + alpha;
        Biquad f;
        f.b0 = float((1 - alpha) / a0);
        f.b1 = float(-2 * c / a0);
        f.b2 = 1;
        f.a1 = f.b1;
        f.a2 = f.b0;
        return f;
    }
};

/// Linkwitz-Riley 3-band isolator, as in a DJ mixer: the bands sum to flat (an all-pass), and
/// turning one to zero removes that band instead of just shelving it down.
class Isolator {
public:
    void prepare(double sampleRate) {
        const double q = std::sqrt(0.5);
        for (int c = 0; c < 2; ++c) {
            for (int s = 0; s < 2; ++s) {
                low1[c][s] = Biquad::lowpass(kLowCross, q, sampleRate);
                rest1[c][s] = Biquad::highpass(kLowCross, q, sampleRate);
                mid2[c][s] = Biquad::lowpass(kHighCross, q, sampleRate);
                high2[c][s] = Biquad::highpass(kHighCross, q, sampleRate);
            }
            // Keeps the low band's phase in step with the two bands split off at the high crossover.
            lowPhase[c] = Biquad::allpass(kHighCross, q, sampleRate);
        }
    }

    void setGains(float low, float mid, float high) {
        target[0] = low;
        target[1] = mid;
        target[2] = high;
    }

    void process(float *left, float *right, int n) {
        float step[3];
        for (int b = 0; b < 3; ++b) step[b] = (target[b] - gain[b]) / float(n);
        float g0 = gain[0], g1 = gain[1], g2 = gain[2];
        for (int i = 0; i < n; ++i) {
            g0 += step[0];
            g1 += step[1];
            g2 += step[2];
            const float bands = std::min(1.0f, std::max({std::abs(g0 - 1), std::abs(g1 - 1), std::abs(g2 - 1)}) / kBlendWidth);
            left[i] = split(0, left[i], g0, g1, g2, bands);
            right[i] = split(1, right[i], g0, g1, g2, bands);
        }
        std::copy(target, target + 3, gain);
    }

private:
    static constexpr double kLowCross = 220, kHighCross = 2600;
    /// How far a band's gain moves from 1 before the signal's all coming through the bands.
    static constexpr float kBlendWidth = 0.05f;

    /// The bands add back to a flat level but with the phase turned, which can push a loud master's
    /// peaks up by 5 dB. So with every band at 1 the signal goes straight through, untouched. As the
    /// first knob leaves the centre it crossfades into the bands, which can then kill fully. The bands
    /// always run, so their filters are ready.
    inline float split(int c, float x, float g0, float g1, float g2, float bands) {
        const float low = lowPhase[c].process(low1[c][1].process(low1[c][0].process(x)));
        const float rest = rest1[c][1].process(rest1[c][0].process(x));
        const float mid = mid2[c][1].process(mid2[c][0].process(rest));
        const float high = high2[c][1].process(high2[c][0].process(rest));
        return x + (g0 * low + g1 * mid + g2 * high - x) * bands;
    }

    Biquad low1[2][2], rest1[2][2], mid2[2][2], high2[2][2], lowPhase[2];
    float gain[3] = {1, 1, 1}, target[3] = {1, 1, 1};
};

/// Zero-delay-feedback state-variable filter (Simper), which stays stable under fast sweeps.
struct SVF {
    float ic1 = 0, ic2 = 0, a1 = 1, a2 = 0, a3 = 0, k = 1;

    void set(float g, float resonanceK) {
        k = resonanceK;
        a1 = 1 / (1 + g * (g + k));
        a2 = g * a1;
        a3 = g * a2;
    }

    inline void process(float x, float &low, float &band, float &high) {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2 * v1 - ic1;
        ic2 = 2 * v2 - ic2;
        low = v2;
        band = v1;
        high = x - k * v1 - v2;
    }

    void reset() { ic1 = ic2 = 0; }
};

/// The channel's one-knob filter: low-pass to the left, high-pass to the right, out of circuit at centre.
class SweepFilter {
public:
    void prepare(double rate) { sampleRate = float(rate); }
    void setAmount(float value) { target = value; }

    void process(float *left, float *right, int n) {
        if (std::abs(target) < 0.001f && std::abs(amount) < 0.001f) {
            amount = target;
            filter[0].reset();
            filter[1].reset();
            return;
        }
        const float step = (target - amount) / float(n);
        for (int i = 0; i < n; ++i) {
            amount += step;
            if (i % kControlInterval == 0) updateCoefficients();
            for (int c = 0; c < 2; ++c) {
                float *x = c == 0 ? left : right;
                float low, band, high;
                filter[c].process(x[i], low, band, high);
                const float wet = amount < 0 ? low : high;
                x[i] += (wet - x[i]) * mix;
            }
        }
    }

private:
    static constexpr int kControlInterval = 16;

    void updateCoefficients() {
        const float a = std::abs(amount);
        const float frequency = amount < 0 ? 20000 * std::pow(110.0f / 20000, a) : 25 * std::pow(9000.0f / 25, a);
        const float g = std::tan(float(kPi) * std::min(frequency, sampleRate * 0.45f) / sampleRate);
        // A touch more resonance as it closes, like the sweep on a club mixer.
        const float q = 0.75f + 0.75f * a;
        filter[0].set(g, 1 / q);
        filter[1].set(g, 1 / q);
        // Fades in just off centre, so there's no step when the knob leaves its detent.
        mix = std::min(1.0f, std::max(0.0f, (a - 0.01f) / 0.05f));
    }

    SVF filter[2];
    float sampleRate = 44100, amount = 0, target = 0, mix = 0;
};

/// Removes clicks from any discontinuity. It remembers the last few output samples; when the stream
/// jumps, those are played backwards as a tail and crossfaded into the new audio. The tail starts
/// on the very last sample that was output, so the waveform stays continuous, and no extra audio
/// has to be produced from the old position (which the stretcher couldn't do cheaply anyway).
class Declicker {
public:
    static constexpr int kLength = 192; // 4.4 ms at 44.1 kHz

    Declicker() {
        for (int i = 0; i < kLength; ++i) curve[i] = float(0.5 * (1 + std::cos(kPi * (i + 0.5) / kLength)));
    }

    void trigger() {
        for (int i = 0; i < kLength; ++i) {
            const int from = (position - 1 - i + 2 * kLength) % kLength;
            tail[0][i] = history[0][from];
            tail[1][i] = history[1][from];
        }
        remaining = kLength;
    }

    bool busy() const { return remaining > 0; }

    /// Forgets what was played, for starting again from silence.
    void reset() {
        std::fill(&history[0][0], &history[0][0] + 2 * kLength, 0.0f);
        remaining = 0;
    }

    void process(float *left, float *right, int n) {
        for (int i = 0; i < n; ++i) {
            if (remaining > 0) {
                const int t = kLength - remaining;
                const float w = curve[t];
                left[i] += (tail[0][t] - left[i]) * w;
                right[i] += (tail[1][t] - right[i]) * w;
                --remaining;
            }
            history[0][position] = left[i];
            history[1][position] = right[i];
            position = (position + 1) % kLength;
        }
    }

private:
    float curve[kLength];
    float history[2][kLength] = {};
    float tail[2][kLength] = {};
    int position = 0, remaining = 0;
};

/// Look-ahead brickwall limiter on the program bus, so two hot decks can't clip the output or a
/// recording. It's silent until something crosses the ceiling, and it recovers quickly.
class Limiter {
public:
    void prepare(double sampleRate) {
        release = float(1 - std::exp(-1 / (0.12 * sampleRate)));
        std::fill(boxValues, boxValues + kLookAhead, 1.0f);
        boxSum = float(kLookAhead);
    }

    void process(float *left, float *right, int n) {
        float deepest = 1;
        for (int i = 0; i < n; ++i) {
            const float peak = std::max(std::abs(left[i]), std::abs(right[i]));
            const float wanted = peak > kCeiling ? kCeiling / peak : 1;
            envelope = std::min(wanted, envelope + (1 - envelope) * release);

            // Sliding minimum over the look-ahead window (monotonic queue).
            while (queueSize > 0 && queueValue[(queueHead + queueSize - 1) % kQueue] >= envelope) --queueSize;
            queueValue[(queueHead + queueSize) % kQueue] = envelope;
            queueIndex[(queueHead + queueSize) % kQueue] = counter;
            ++queueSize;
            while (counter - queueIndex[queueHead] >= kLookAhead) {
                queueHead = (queueHead + 1) % kQueue;
                --queueSize;
            }
            const float floorGain = queueValue[queueHead];
            ++counter;

            // Box-averaging the minimum makes the gain move smoothly and reach its target by the
            // time the peak leaves the delay line.
            boxSum += floorGain - boxValues[boxPosition];
            boxValues[boxPosition] = floorGain;
            boxPosition = (boxPosition + 1) % kLookAhead;
            const float gain = std::min(1.0f, boxSum / float(kLookAhead));
            deepest = std::min(deepest, gain);

            const float dl = delay[0][delayPosition], dr = delay[1][delayPosition];
            delay[0][delayPosition] = left[i];
            delay[1][delayPosition] = right[i];
            delayPosition = (delayPosition + 1) % kLookAhead;
            left[i] = dl * gain;
            right[i] = dr * gain;
        }
        reduction = deepest;
    }

    /// The deepest gain applied during the last block (1 = no limiting).
    float lastGain() const { return reduction; }

private:
    static constexpr int kLookAhead = 66; // 1.5 ms
    static constexpr int kQueue = kLookAhead + 1;
    static constexpr float kCeiling = 0.97f; // about -0.26 dBFS

    float delay[2][kLookAhead] = {};
    float boxValues[kLookAhead];
    float queueValue[kQueue];
    long queueIndex[kQueue];
    int queueHead = 0, queueSize = 0, delayPosition = 0, boxPosition = 0;
    long counter = 0;
    float boxSum = 0, envelope = 1, release = 0.001f, reduction = 1;
};

/// 4-point Catmull-Rom interpolation for reading audio at non-integer positions.
inline float hermite(float frac, float xm1, float x0, float x1, float x2) {
    const float c = (x1 - xm1) * 0.5f;
    const float v = x0 - x1;
    const float w = c + v;
    const float a = w + v + (x2 - x0) * 0.5f;
    const float b = w + a;
    return ((((a * frac) - b) * frac + c) * frac + x0);
}

} // namespace cheeks
