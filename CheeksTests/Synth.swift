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
}
