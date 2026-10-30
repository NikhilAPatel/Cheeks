#pragma once

#include "CheeksDSP.h"
#include "Primitives.hpp"
#include <cstdint>
#include <vector>

namespace cheeks {

/// The channel's COLOR knob, for everything except the plain filter. It sits after the EQ, so it
/// runs in real time rather than on the track's own clock. Turning left is the dark side of each
/// effect and turning right the bright side. Everything fades in from the centre, so at 12 o'clock
/// the channel is untouched, apart from any echo or reverb still ringing out.
class ColorFX {
public:
    void prepare(double rate) {
        sampleRate = rate;
        for (auto &line : echoLine) line.assign(kEchoLength, 0);
        for (int i = 0; i < kSpaceLines; ++i) spaceLine[i].assign(size_t(kSpaceLengths[i]), 0);
        for (auto &line : pitchLine) line.assign(kPitchLength, 0);
    }

    void process(float *left, float *right, int n, CheeksColorType type, float amount, double beatSamples) {
        const float size = std::min(1.0f, std::abs(amount));
        const bool dark = amount < 0;
        const bool on = size > 0.01f;
        if (type != CheeksColorFilter && on) lastType = type;

        const bool dub = on && type == CheeksColorDubEcho;
        if (dub || !echoIdle) runDub(left, right, n, dub ? size : 0, dark, beatSamples);
        const bool space = on && type == CheeksColorSpace;
        if (space || !spaceIdle) runSpace(left, right, n, space ? size : 0, dark);

        const bool inline_ = on && (type == CheeksColorNoise || type == CheeksColorCrush || type == CheeksColorPitch);
        if (inline_ || mix > 0.0005f) runInline(left, right, n, inline_ ? size : 0, dark, on ? amount : lastAmount);
        if (on) lastAmount = amount;
    }

private:
    static constexpr int kEchoLength = 1 << 18;
    static constexpr int kEchoMask = kEchoLength - 1;
    static constexpr int kSpaceLines = 8;
    static constexpr int kSpaceLengths[kSpaceLines] = {1087, 1283, 1447, 1663, 1871, 2141, 2389, 2707};
    static constexpr int kPitchLength = 4096;
    static constexpr int kPitchMask = kPitchLength - 1;

    /// A tape-style echo three-quarters of a beat long, with a filter in its feedback so each repeat
    /// gets darker or thinner. The further round the knob, the more goes in and the longer it lasts.
    void runDub(float *left, float *right, int n, float size, bool dark, double beatSamples) {
        const double wanted = std::min(double(kEchoLength - 8), std::max(64.0, beatSamples * 0.75));
        if (echoIdle) echoDelay = wanted;
        const float feedback = 0.55f + 0.4f * size;
        const float sendTarget = size * size;
        const float g = std::tan(float(kPi) * float(dark ? 1100.0 : 800.0) / float(sampleRate));
        echoFilter[0].set(g, 1.2f);
        echoFilter[1].set(g, 1.2f);
        float loudest = 0;
        for (int i = 0; i < n; ++i) {
            echoDelay += (wanted - echoDelay) * 0.0004;
            echoSend += (sendTarget - echoSend) * 0.004f;
            const double readPosition = double(echoWrite) - echoDelay;
            const int base = int(std::floor(readPosition));
            const float frac = float(readPosition - base);
            float wet[2];
            for (int c = 0; c < 2; ++c) {
                const float a = echoLine[c][base & kEchoMask], b = echoLine[c][(base + 1) & kEchoMask];
                wet[c] = a + (b - a) * frac;
                float low, band, high;
                echoFilter[c].process(wet[c], low, band, high);
                const float shaped = dark ? low : high;
                // The tape saturates gently, so a long feedback can't run away.
                const float back = shaped * feedback;
                echoLine[c][echoWrite] = (c == 0 ? left[i] : right[i]) * echoSend + back / (1 + std::abs(back) * 0.3f);
            }
            echoWrite = (echoWrite + 1) & kEchoMask;
            left[i] += wet[0];
            right[i] += wet[1];
            loudest = std::max(loudest, std::max(std::abs(wet[0]), std::abs(wet[1])));
        }
        echoIdle = sendTarget <= 0 && echoSend < 0.0005f && loudest < 0.00003f;
    }

    /// A short, wide reverb. The dark side is a cave and the bright side a thin, airy room.
    void runSpace(float *left, float *right, int n, float size, bool dark) {
        const float sendTarget = size;
        const double rt60 = 1.2 + 3.0 * size;
        for (int l = 0; l < kSpaceLines; ++l) {
            spaceDecay[l] = float(std::pow(10.0, -3.0 * kSpaceLengths[l] / (rt60 * sampleRate)));
        }
        const float damping = dark ? 0.75f : 0.2f;
        const float thinning = dark ? 0.0f : 0.96f;
        float loudest = 0;
        for (int i = 0; i < n; ++i) {
            spaceSend += (sendTarget - spaceSend) * 0.003f;
            const float input = (left[i] + right[i]) * 0.5f * spaceSend;
            float out[kSpaceLines];
            float sum = 0;
            for (int l = 0; l < kSpaceLines; ++l) {
                float x = spaceLine[l][spacePosition[l]];
                spaceState[l] += (x - spaceState[l]) * (1 - damping);
                x = spaceState[l];
                out[l] = x;
                sum += x;
            }
            const float householder = sum * 2.0f / kSpaceLines;
            for (int l = 0; l < kSpaceLines; ++l) {
                spaceLine[l][spacePosition[l]] = (out[l] - householder) * spaceDecay[l] + input;
                spacePosition[l] = (spacePosition[l] + 1) % kSpaceLengths[l];
            }
            float wetL = (out[0] - out[1] + out[2] - out[3] + out[4] - out[5] + out[6] - out[7]) * 0.4f;
            float wetR = (out[0] + out[1] - out[2] - out[3] + out[4] + out[5] - out[6] - out[7]) * 0.4f;
            // The bright side takes the low end out of the reverb, so it doesn't muddy the bass.
            spaceLow[0] += (wetL - spaceLow[0]) * 0.02f;
            spaceLow[1] += (wetR - spaceLow[1]) * 0.02f;
            wetL -= spaceLow[0] * thinning;
            wetR -= spaceLow[1] * thinning;
            left[i] += wetL;
            right[i] += wetR;
            loudest = std::max(loudest, std::max(std::abs(wetL), std::abs(wetR)));
        }
        spaceIdle = sendTarget <= 0 && spaceSend < 0.0005f && loudest < 0.00003f;
    }

    /// The effects that replace the signal rather than adding a tail: noise, crush and pitch.
    void runInline(float *left, float *right, int n, float size, bool dark, float amount) {
        const float mixTarget = size > 0 ? std::min(1.0f, size * 6) : 0;
        const float a = std::abs(amount);
        noiseCounter = (noiseCounter + 1) % 4;
        if (noiseCounter == 0) {
            // Noise opens up from the bass on the dark side, and comes down from the top on the bright side.
            const float frequency = dark ? 150 * std::pow(40.0f, a) : 12000 * std::pow(0.08f, a);
            const float g = std::tan(float(kPi) * std::min(frequency, float(sampleRate) * 0.45f) / float(sampleRate));
            noiseFilter.set(g, 0.9f);
        }
        for (int i = 0; i < n; ++i) {
            mix += (mixTarget - mix) * 0.003f;
            float wetL = left[i], wetR = right[i];
            switch (lastType) {
                case CheeksColorNoise: noise(wetL, wetR, dark, a); break;
                case CheeksColorCrush: crush(wetL, wetR, a); break;
                case CheeksColorPitch: pitch(wetL, wetR, amount); break;
                default: break;
            }
            left[i] += (wetL - left[i]) * mix;
            right[i] += (wetR - right[i]) * mix;
        }
    }

    inline void noise(float &l, float &r, bool dark, float a) {
        noiseSeed = noiseSeed * 1664525u + 1013904223u;
        const float white = float(int32_t(noiseSeed)) / 2147483648.0f;
        float low, band, high;
        noiseFilter.process(white, low, band, high);
        const float shaped = (dark ? low : high) * a * a * 0.5f;
        l += shaped;
        r += shaped;
    }

    inline void crush(float &l, float &r, float a) {
        const int hold = 1 + int(a * a * 24);
        const float levels = std::pow(2.0f, 13.0f - 10.0f * a);
        if (++crushCounter >= hold) {
            crushCounter = 0;
            crushHeld[0] = std::round(l * levels) / levels;
            crushHeld[1] = std::round(r * levels) / levels;
        }
        l = crushHeld[0];
        r = crushHeld[1];
    }

    /// A delay-line pitch shifter: two read heads sweep through the buffer at the new speed, half a
    /// window apart, each fading out before it jumps. Up to an octave either way.
    inline void pitch(float &l, float &r, float amount) {
        const float semitones = amount * 12;
        const float ratio = std::pow(2.0f, semitones / 12);
        const float window = 2048;
        pitchPhase += (1 - ratio) / window;
        pitchPhase -= std::floor(pitchPhase);
        pitchLine[0][pitchWrite] = l;
        pitchLine[1][pitchWrite] = r;
        float out[2] = {0, 0};
        for (int head = 0; head < 2; ++head) {
            float phase = pitchPhase + head * 0.5f;
            phase -= std::floor(phase);
            const float delay = 16 + phase * window;
            const float gain = std::sin(float(kPi) * phase);
            const float position = float(pitchWrite) - delay;
            const int base = int(std::floor(position));
            const float frac = position - float(base);
            for (int c = 0; c < 2; ++c) {
                const float a = pitchLine[c][base & kPitchMask], b = pitchLine[c][(base + 1) & kPitchMask];
                out[c] += (a + (b - a) * frac) * gain * gain;
            }
        }
        pitchWrite = (pitchWrite + 1) & kPitchMask;
        l = out[0];
        r = out[1];
    }

    double sampleRate = 44100;
    CheeksColorType lastType = CheeksColorFilter;
    float lastAmount = 0;

    std::vector<float> echoLine[2];
    SVF echoFilter[2];
    int echoWrite = 0;
    double echoDelay = 22050;
    float echoSend = 0;
    bool echoIdle = true;

    std::vector<float> spaceLine[kSpaceLines];
    int spacePosition[kSpaceLines] = {};
    float spaceState[kSpaceLines] = {}, spaceDecay[kSpaceLines] = {}, spaceLow[2] = {};
    float spaceSend = 0;
    bool spaceIdle = true;

    float mix = 0;
    SVF noiseFilter;
    uint32_t noiseSeed = 0x9E3779B9u;
    int noiseCounter = 0;
    float crushHeld[2] = {};
    int crushCounter = 0;
    std::vector<float> pitchLine[2];
    int pitchWrite = 0;
    float pitchPhase = 0;
};

} // namespace cheeks
