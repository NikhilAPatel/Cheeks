import SwiftUI

/// The sampler's eight one-shots. They're synthesised when the app starts, so there's nothing to
/// license and nothing extra in the app's download.
enum SampleBank {
    static let names = ["AIR HORN", "SIREN", "RISER", "IMPACT", "LASER", "CLAP", "RIM", "REWIND"]

    static func color(_ i: Int) -> Color {
        let colors: [Color] = [Theme.danger, Theme.cue, Theme.warn, Color(red: 0.62, green: 0.3, blue: 1),
                               Color(red: 0.1, green: 0.8, blue: 0.72), Theme.play, Theme.accent, Color(red: 0.94, green: 0.3, blue: 0.72)]
        return colors[i % colors.count]
    }

    /// Renders all eight. Takes a moment, so it's called off the main thread.
    static func render() -> [PCM16Stereo] {
        [airHorn(), siren(), riser(), impact(), laser(), clap(), rim(), rewind()]
    }

    private static let sr = AudioConfig.sampleRate

    private static func make(seconds: Double, _ sample: (Double, Double) -> (Double, Double)) -> PCM16Stereo {
        let n = Int(seconds * sr)
        var left = [Float](repeating: 0, count: n), right = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let (l, r) = sample(t, t / seconds)
            left[i] = Float(l)
            right[i] = Float(r)
        }
        return PCM16Stereo(left: left, right: right)
    }

    private static func saw(_ phase: Double) -> Double { 2 * (phase - floor(phase + 0.5)) }

    private final class Noise {
        var seed: UInt32 = 0x9E37_79B9
        func next() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(Int32(bitPattern: seed)) / Double(Int32.max)
        }
    }

    /// The reggae air horn: detuned saws in a stack of fifths, with three stabs.
    private static func airHorn() -> PCM16Stereo {
        let notes = [233.1, 349.2, 466.2, 699.3]
        let stabs: [(Double, Double)] = [(0, 0.16), (0.2, 0.16), (0.4, 0.75)]
        return make(seconds: 1.3) { t, _ in
            var gate = 0.0
            for (start, length) in stabs where t >= start && t < start + length + 0.03 {
                let attack = min(1, (t - start) / 0.005)
                let release = min(1, max(0, (start + length + 0.03 - t) / 0.03))
                gate = max(gate, attack * release)
            }
            guard gate > 0 else { return (0, 0) }
            var l = 0.0, r = 0.0
            for note in notes {
                let bend = 1 - 0.01 * exp(-t * 18)
                l += saw(t * note * bend * 0.997)
                r += saw(t * note * bend * 1.003)
            }
            let v = 0.14 * gate
            return (tanh(l * v * 2) * 0.8, tanh(r * v * 2) * 0.8)
        }
    }

    private static func siren() -> PCM16Stereo {
        var phase = 0.0
        return make(seconds: 2.4) { t, p in
            let f = 700 + 500 * sin(2 * .pi * 1.6 * t)
            phase += f / sr
            let v = sin(2 * .pi * phase) + 0.3 * sin(4 * .pi * phase)
            let env = min(1, t / 0.02) * min(1, (1 - p) * 12) * 0.4
            return (v * env, v * env)
        }
    }

    /// White noise opening up, the classic build.
    private static func riser() -> PCM16Stereo {
        let noise = Noise()
        var lowL = 0.0, lowR = 0.0
        return make(seconds: 4) { _, p in
            let cutoff = 0.01 + 0.5 * p * p
            lowL += (noise.next() - lowL) * cutoff
            lowR += (noise.next() - lowR) * cutoff
            let env = p * p * 0.6 * min(1, (1 - p) * 40)
            return (lowL * env * 1.6, lowR * env * 1.6)
        }
    }

    /// A deep hit: a falling sine under a burst of noise.
    private static func impact() -> PCM16Stereo {
        let noise = Noise()
        var phase = 0.0
        return make(seconds: 2.2) { t, _ in
            let f = 38 + 110 * exp(-t * 14)
            phase += f / sr
            let body = sin(2 * .pi * phase) * exp(-t * 2.2)
            let crack = noise.next() * exp(-t * 28) * 0.4
            let v = tanh((body + crack) * 1.6) * 0.8
            return (v, v)
        }
    }

    private static func laser() -> PCM16Stereo {
        var phase = 0.0
        return make(seconds: 0.5) { t, _ in
            let f = 2800 * exp(-t * 9) + 90
            phase += f / sr
            let v = (sin(2 * .pi * phase) + 0.4 * saw(phase)) * exp(-t * 6) * 0.5
            return (v, v)
        }
    }

    /// Several hands, so it's slightly smeared in time.
    private static func clap() -> PCM16Stereo {
        let noise = Noise()
        return make(seconds: 0.45) { t, _ in
            let hits = [0.0, 0.012, 0.024, 0.038]
            var env = 0.0
            for hit in hits where t >= hit { env = max(env, exp(-(t - hit) * (hit == 0.038 ? 16 : 140))) }
            let v = noise.next() * env * 0.7
            return (v, v)
        }
    }

    private static func rim() -> PCM16Stereo {
        let noise = Noise()
        return make(seconds: 0.2) { t, _ in
            let tone = sin(2 * .pi * 1700 * t) * exp(-t * 90) + sin(2 * .pi * 480 * t) * exp(-t * 70)
            let v = (tone * 0.55 + noise.next() * exp(-t * 300) * 0.3)
            return (v, v)
        }
    }

    /// A tape being dragged backwards: pitch swoops down and back with a noisy edge.
    private static func rewind() -> PCM16Stereo {
        let noise = Noise()
        var phase = 0.0
        return make(seconds: 1) { t, p in
            let f = 400 + 900 * sin(.pi * p) + 200 * sin(2 * .pi * 11 * t)
            phase += f / sr
            let v = (saw(phase) * 0.4 + noise.next() * 0.1) * sin(.pi * p)
            return (v * 0.7, v * 0.7)
        }
    }
}
