#pragma once

#include "CheeksDSP.h"
#include "Primitives.hpp"
#include <vector>

namespace cheeks {

/// The deck's FX bus. It sits ahead of the time-stretcher, so an effect can run on single stems
/// (only those stems feed the bus) and its timing follows the track's own beat at any tempo.
/// Echo and reverb keep ringing out after they're switched off.
class BeatFX {
public:
    struct Clock {
        /// Length of a beat in samples of this processing clock.
        double beatSamples;
        /// Position on the track's beat grid at the first sample, and its change per sample.
        double beatPosition;
        double beatIncrement;
    };

    void prepare(double rate) {
        sampleRate = rate;
        for (auto &line : echoLine) line.assign(kEchoLength, 0);
        for (auto &line : flangeLine) line.assign(kFlangeLength, 0);
        for (int i = 0; i < kReverbLines; ++i) reverbLine[i].assign(size_t(kReverbLengths[i]), 0);
        for (int i = 0; i < 2; ++i) diffuser[i].assign(size_t(kDiffuserLengths[i]), 0);
        echoLowCut[0] = echoLowCut[1] = Biquad::highpass(120, 0.7, rate);
        echoTone[0] = echoTone[1] = Biquad::lowpass(6000, 0.7, rate);
    }

    void set(CheeksFXType newType, bool isOn, double newBeats, float newDepth) {
        type = newType;
        on = isOn;
        beats = newBeats > 0 ? newBeats : 1;
        depth = newDepth;
    }

    void process(float *left, float *right, int n, const Clock &clock) {
        const bool echoing = on && (type == CheeksFXEcho || type == CheeksFXPingPong || type == CheeksFXSpiral);
        const bool reverbing = on && type == CheeksFXReverb;
        const bool modulating = on && type >= CheeksFXFlanger && type <= CheeksFXCrush;
        if (modulating) modType = type;

        if (modulating || modMix > 0.0005f) {
            runModulation(left, right, n, clock, modulating);
        }
        if (echoing || !echoIdle) runEcho(left, right, n, clock, echoing);
        if (reverbing || !reverbIdle) runReverb(left, right, n, clock, reverbing);
    }

private:
    static constexpr int kEchoLength = 1 << 18; // about 5.9 s at 44.1 kHz
    static constexpr int kEchoMask = kEchoLength - 1;
    static constexpr int kFlangeLength = 2048;
    static constexpr int kFlangeMask = kFlangeLength - 1;
    static constexpr int kReverbLines = 8;
    static constexpr int kReverbLengths[kReverbLines] = {1151, 1327, 1559, 1801, 2069, 2351, 2633, 2939};
    static constexpr int kDiffuserLengths[2] = {241, 557};

    // MARK: Echo, ping-pong and spiral

    void runEcho(float *left, float *right, int n, const Clock &clock, bool active) {
        const bool pingPong = type == CheeksFXPingPong;
        const bool spiral = type == CheeksFXSpiral;
        const double wanted = std::min(double(kEchoLength - 8), std::max(64.0, beats * clock.beatSamples));
        const float gateTarget = active ? 1 : 0;
        const float wetTarget = active ? 0.35f + 0.65f * depth : echoWet;
        // Feedback rises with depth; a spiral runs nearly self-sustaining and then bends down.
        const float feedback = spiral ? 0.86f + 0.1f * depth : 0.3f + 0.52f * depth;
        // Starting from silence there's nothing to glide from.
        if (echoIdle) echoDelay = wanted;
        float loudest = 0;
        for (int i = 0; i < n; ++i) {
            // The tape-style slew means changing the beat length glides instead of clicking.
            const double slew = spiral ? 0.00012 : 0.0006;
            echoDelay += (wanted - echoDelay) * slew;
            echoGate += (gateTarget - echoGate) * 0.004f;
            echoWet += (wetTarget - echoWet) * 0.004f;

            const double readPosition = double(echoWrite) - echoDelay;
            const int base = int(std::floor(readPosition));
            const float frac = float(readPosition - base);
            float wet[2];
            for (int c = 0; c < 2; ++c) {
                const float a = echoLine[c][base & kEchoMask], b = echoLine[c][(base + 1) & kEchoMask];
                wet[c] = a + (b - a) * frac;
            }
            const float feedL = echoLowCut[0].process(echoTone[0].process(pingPong ? wet[1] : wet[0])) * feedback;
            const float feedR = echoLowCut[1].process(echoTone[1].process(pingPong ? wet[0] : wet[1])) * feedback;
            const float inL = left[i] * echoGate, inR = right[i] * echoGate;
            // Ping-pong starts the signal on one side and lets the feedback throw it across.
            echoLine[0][echoWrite] = (pingPong ? (inL + inR) * 0.7f : inL) + feedL;
            echoLine[1][echoWrite] = (pingPong ? 0 : inR) + feedR;
            echoWrite = (echoWrite + 1) & kEchoMask;

            left[i] += wet[0] * echoWet;
            right[i] += wet[1] * echoWet;
            loudest = std::max(loudest, std::max(std::abs(wet[0]), std::abs(wet[1])));
        }
        echoIdle = !active && loudest < 0.00003f;
    }

    // MARK: Reverb

    /// An 8-line feedback delay network with a Householder mix and damping in the loop.
    void runReverb(float *left, float *right, int n, const Clock &clock, bool active) {
        const double beatSeconds = clock.beatSamples / sampleRate;
        const double rt60 = std::min(9.0, std::max(0.7, beats * beatSeconds * 3 + double(depth) * 2));
        for (int l = 0; l < kReverbLines; ++l) {
            reverbDecay[l] = float(std::pow(10.0, -3.0 * kReverbLengths[l] / (rt60 * sampleRate)));
        }
        const float gateTarget = active ? 1 : 0;
        const float wetTarget = active ? 0.2f + 0.7f * depth : reverbWet;
        const float damping = 0.3f;
        float loudest = 0;
        for (int i = 0; i < n; ++i) {
            reverbGate += (gateTarget - reverbGate) * 0.004f;
            reverbWet += (wetTarget - reverbWet) * 0.004f;
            float input = (left[i] + right[i]) * 0.5f * reverbGate;
            for (int d = 0; d < 2; ++d) {
                const float delayed = diffuser[d][diffuserPosition[d]];
                const float mixed = input + delayed * 0.6f;
                diffuser[d][diffuserPosition[d]] = mixed;
                input = delayed - mixed * 0.6f;
                diffuserPosition[d] = (diffuserPosition[d] + 1) % kDiffuserLengths[d];
            }
            float out[kReverbLines];
            float sum = 0;
            for (int l = 0; l < kReverbLines; ++l) {
                float x = reverbLine[l][reverbPosition[l]];
                reverbState[l] += (x - reverbState[l]) * (1 - damping);
                x = reverbState[l];
                out[l] = x;
                sum += x;
            }
            const float mix = sum * 2.0f / kReverbLines;
            for (int l = 0; l < kReverbLines; ++l) {
                reverbLine[l][reverbPosition[l]] = (out[l] - mix) * reverbDecay[l] + input;
                reverbPosition[l] = (reverbPosition[l] + 1) % kReverbLengths[l];
            }
            const float wetL = (out[0] - out[1] + out[2] - out[3] + out[4] - out[5] + out[6] - out[7]) * 0.35f;
            const float wetR = (out[0] + out[1] - out[2] - out[3] + out[4] + out[5] - out[6] - out[7]) * 0.35f;
            left[i] += wetL * reverbWet;
            right[i] += wetR * reverbWet;
            loudest = std::max(loudest, std::max(std::abs(wetL), std::abs(wetR)));
        }
        reverbIdle = !active && loudest < 0.00003f;
    }

    // MARK: Flanger, phaser, filter LFO, gate, crush

    void runModulation(float *left, float *right, int n, const Clock &clock, bool active) {
        const float mixTarget = active ? 1 : 0;
        double beatPosition = clock.beatPosition;
        const double phaseStep = clock.beatIncrement / std::max(beats, 0.0001);
        double phase = beatPosition / std::max(beats, 0.0001);
        for (int i = 0; i < n; ++i) {
            modMix += (mixTarget - modMix) * 0.003f;
            const double fractional = phase - std::floor(phase);
            float wetL = left[i], wetR = right[i];
            switch (modType) {
                case CheeksFXFlanger: flange(wetL, wetR, fractional); break;
                case CheeksFXPhaser: phaser(wetL, wetR, fractional, i); break;
                case CheeksFXFilterLFO: sweep(wetL, wetR, fractional, i); break;
                case CheeksFXGate: gate(wetL, wetR, fractional); break;
                case CheeksFXCrush: crush(wetL, wetR); break;
                default: break;
            }
            left[i] += (wetL - left[i]) * modMix;
            right[i] += (wetR - right[i]) * modMix;
            phase += phaseStep;
        }
    }

    inline void flange(float &l, float &r, double phase) {
        const float feedback = 0.25f + 0.55f * depth;
        const float base = float(sampleRate * 0.0009), span = float(sampleRate * 0.0045);
        for (int c = 0; c < 2; ++c) {
            float &x = c == 0 ? l : r;
            // The channels sweep a quarter-turn apart, which spreads the effect across the stereo field.
            const double lfo = 0.5 + 0.5 * std::sin(2 * kPi * (phase + (c == 0 ? 0 : 0.25)));
            const float delaySamples = base + span * float(lfo);
            const float position = float(flangeWrite) - delaySamples;
            const int whole = int(std::floor(position));
            const float frac = position - float(whole);
            const float a = flangeLine[c][whole & kFlangeMask], b = flangeLine[c][(whole + 1) & kFlangeMask];
            const float delayed = a + (b - a) * frac;
            flangeLine[c][flangeWrite] = x + delayed * feedback;
            x = (x + delayed) * 0.7f;
        }
        flangeWrite = (flangeWrite + 1) & kFlangeMask;
    }

    inline void phaser(float &l, float &r, double phase, int i) {
        if (i % 16 == 0) {
            const double lfo = 0.5 + 0.5 * std::sin(2 * kPi * phase);
            const double frequency = 180 * std::pow(22.0, lfo);
            const double t = std::tan(kPi * frequency / sampleRate);
            phaserCoefficient = float((t - 1) / (t + 1));
        }
        const float feedback = 0.2f + 0.55f * depth;
        for (int c = 0; c < 2; ++c) {
            float &x = c == 0 ? l : r;
            float v = x + phaserLast[c] * feedback;
            for (int s = 0; s < 4; ++s) {
                const float y = phaserCoefficient * v + phaserState[c][s];
                phaserState[c][s] = v - phaserCoefficient * y;
                v = y;
            }
            phaserLast[c] = v;
            x = (x + v) * 0.7f;
        }
    }

    inline void sweep(float &l, float &r, double phase, int i) {
        if (i % 16 == 0) {
            const double lfo = 0.5 - 0.5 * std::cos(2 * kPi * phase);
            const double frequency = 200 * std::pow(40.0, lfo);
            const float g = float(std::tan(kPi * std::min(frequency, sampleRate * 0.45) / sampleRate));
            const float k = 1.0f / (0.8f + 3.2f * depth);
            lfoFilter[0].set(g, k);
            lfoFilter[1].set(g, k);
        }
        float low, band, high;
        lfoFilter[0].process(l, low, band, high);
        l = low;
        lfoFilter[1].process(r, low, band, high);
        r = low;
    }

    inline void gate(float &l, float &r, double phase) {
        const float wanted = phase < 0.5 ? 1 : 1 - depth;
        gateGain += (wanted - gateGain) * 0.012f;
        l *= gateGain;
        r *= gateGain;
    }

    inline void crush(float &l, float &r) {
        const float d = depth * depth;
        const int hold = 1 + int(d * 30);
        const float levels = float(std::pow(2.0, 14.0 - 10.0 * depth));
        if (++crushCounter >= hold) {
            crushCounter = 0;
            crushHeld[0] = std::round(l * levels) / levels;
            crushHeld[1] = std::round(r * levels) / levels;
        }
        l = crushHeld[0];
        r = crushHeld[1];
    }

    double sampleRate = 44100;
    CheeksFXType type = CheeksFXNone, modType = CheeksFXNone;
    bool on = false;
    double beats = 1;
    float depth = 0.5f;

    std::vector<float> echoLine[2];
    Biquad echoLowCut[2], echoTone[2];
    int echoWrite = 0;
    double echoDelay = 22050;
    float echoGate = 0, echoWet = 0;
    bool echoIdle = true;

    std::vector<float> reverbLine[kReverbLines], diffuser[2];
    int reverbPosition[kReverbLines] = {}, diffuserPosition[2] = {};
    float reverbState[kReverbLines] = {}, reverbDecay[kReverbLines] = {};
    float reverbGate = 0, reverbWet = 0;
    bool reverbIdle = true;

    float modMix = 0;
    std::vector<float> flangeLine[2];
    int flangeWrite = 0;
    float phaserState[2][4] = {}, phaserLast[2] = {}, phaserCoefficient = 0;
    SVF lfoFilter[2];
    float gateGain = 1;
    float crushHeld[2] = {};
    int crushCounter = 0;
};

} // namespace cheeks
