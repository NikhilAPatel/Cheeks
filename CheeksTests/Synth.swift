import Foundation
@testable import Cheeks

/// Deterministic synthetic tracks: kick on every beat, hats on the off-beats, one chord per bar plus bass.
enum Synth {
    static let sampleRate = AudioConfig.sampleRate

    static let aMinor = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]] // Am F C G → 8A
    static let dMajor = [[62, 66, 69], [55, 59, 62], [57, 61, 64], [62, 66, 69]] // D G A D → 10B
    static let fMinor = [[53, 56, 60], [49, 53, 56], [51, 55, 58], [53, 56, 60]] // Fm Db Eb Fm → 4A

    static func frequency(midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    static func track(bpm: Double, firstBeat: Double, seconds: Double, chords: [[Int]]) -> PCM16Stereo {
        let sr = sampleRate
        let n = Int(seconds * sr)
        var x = [Float](repeating: 0, count: n)
        let beat = 60 / bpm

        var seed: UInt32 = 12345
        var i = 0
        while firstBeat + Double(i) * beat < seconds - 0.2 {
            let kickStart = Int((firstBeat + Double(i) * beat) * sr)
            for k in 0..<Int(0.15 * sr) where kickStart + k < n {
                let t = Double(k) / sr
                let f = 50 + 80 * exp(-t * 30)
                x[kickStart + k] += Float(0.9 * sin(2 * .pi * f * t) * exp(-t * 18))
            }
            let hatStart = Int((firstBeat + (Double(i) + 0.5) * beat) * sr)
            for k in 0..<Int(0.04 * sr) where hatStart + k < n {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                x[hatStart + k] += 0.15 * noise * Float(exp(-Double(k) / sr * 90))
            }
            i += 1
        }

        let bar = 4 * beat
        var j = 0
        while Double(j) * bar < seconds {
            let chord = chords[j % chords.count]
            let start = Int(Double(j) * bar * sr), end = min(n, Int(Double(j + 1) * bar * sr))
            for k in start..<end {
                let t = Double(k) / sr
                var v = 0.15 * sin(2 * .pi * frequency(midi: chord[0] - 24) * t)
                for note in chord { v += 0.08 * sin(2 * .pi * frequency(midi: note) * t) }
                x[k] += Float(v)
            }
            j += 1
        }

        let peak = x.map(abs).max() ?? 1
        x = x.map { $0 / peak * 0.9 }
        return PCM16Stereo(left: x, right: x)
    }

    /// Four stems of a little club track: a kick on every beat and a clap on 2 and 4, a bass and chords that change on
    /// the 1, and a melody that comes in at bar 16 and a singer at bar 32.
    static func clubStems(bpm: Double, firstBar: Double, bars: Int, jitter: Double = 0) -> [PCM16Stereo] {
        let sr = sampleRate, beat = 60 / bpm
        let count = Int((firstBar + Double(bars) * 4 * beat + 1) * sr)
        var vocals = [Float](repeating: 0, count: count), melody = vocals, bass = vocals, drums = vocals
        var random = SystemRandomNumberGenerator()
        for bar in 0..<bars {
            let root = [45, 41, 48, 43][(bar / 2) % 4]
            for b in 0..<4 {
                let nudge = jitter > 0 ? Double.random(in: -jitter...jitter, using: &random) : 0
                let start = Int((firstBar + Double(bar * 4 + b) * beat + nudge) * sr)
                for k in 0..<Int(0.14 * sr) where start + k >= 0 && start + k < count {
                    let t = Double(k) / sr
                    drums[start + k] += Float(0.9 * sin(2 * .pi * (55 + 90 * exp(-t * 40)) * t) * exp(-t * 18))
                    if b % 2 == 1, k < Int(0.09 * sr) { drums[start + k] += Float.random(in: -0.35...0.35, using: &random) * Float(exp(-t * 30)) }
                }
            }
            let barStart = Int((firstBar + Double(bar * 4) * beat) * sr), barLength = Int(4 * beat * sr)
            for k in 0..<barLength where barStart + k < count {
                let t = Double(k) / sr
                bass[barStart + k] = Float(0.35 * sin(2 * .pi * frequency(midi: root - 12) * t))
                if bar >= 16 {
                    melody[barStart + k] = Float(0.12 * (sin(2 * .pi * frequency(midi: root + 12) * t) + sin(2 * .pi * frequency(midi: root + 15) * t)
                        + sin(2 * .pi * frequency(midi: root + 19) * t)))
                }
                if bar >= 32, bar < 48 { vocals[barStart + k] = Float(0.3 * sin(2 * .pi * frequency(midi: root + 24) * t)) }
            }
        }
        // About as loud as a mastered track gets after loudness matching.
        let g = PCM16Stereo.stemHeadroom * 0.6
        return [vocals, melody, bass, drums].map { stem in
            let scaled = stem.map { $0 * g }
            return PCM16Stereo(left: scaled, right: scaled)
        }
    }
}
