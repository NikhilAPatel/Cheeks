import Accelerate
import Foundation

/// Krumhansl–Schmuckler key detection on an averaged chromagram.
enum KeyDetector {
    private static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Returns the key in Camelot notation (e.g. "8A"), or nil for silence.
    static func detect(mono: [Float], sampleRate: Double) -> String? {
        // Downsample by 4 (~11 kHz) — plenty for pitch content up to ~2 kHz.
        let factor = 4
        let rate = sampleRate / Double(factor)
        let count = mono.count / factor
        guard count > 0 else { return nil }
        var signal = [Float](repeating: 0, count: count)
        var lowpass = Biquad.lowpass(2500, sampleRate: sampleRate)
        var j = 0
        for i in 0..<(count * factor) {
            let y = lowpass.process(mono[i])
            if i % factor == 0 { signal[j] = y; j += 1 }
        }

        let log2n: vDSP_Length = 13
        let n = 1 << Int(log2n)
        guard count > n, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        // Map each FFT bin to a pitch class (55 Hz – 2 kHz).
        var binPitchClass = [Int](repeating: -1, count: n / 2)
        for k in 1..<(n / 2) {
            let freq = Double(k) * rate / Double(n)
            guard freq >= 55, freq <= 2000 else { continue }
            let midi = 69 + 12 * log2(freq / 440)
            binPitchClass[k] = ((Int(midi.rounded()) % 12) + 12) % 12
        }

        var chroma = [Float](repeating: 0, count: 12)
        var frame = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        var start = 0
        while start + n <= count {
            vDSP_vmul(Array(signal[start..<(start + n)]), 1, window, 1, &frame, 1, vDSP_Length(n))
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
                }
            }
            for k in 1..<(n / 2) where binPitchClass[k] >= 0 {
                chroma[binPitchClass[k]] += sqrt(mags[k])
            }
            start += n
        }
        guard chroma.contains(where: { $0 > 0 }) else { return nil }

        var best = (score: -Float.infinity, pitchClass: 0, minor: false)
        for tonic in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                let rotated = (0..<12).map { profile[($0 - tonic + 12) % 12] }
                let score = correlation(chroma, rotated)
                if score > best.score { best = (score, tonic, minor) }
            }
        }
        return Camelot.code(pitchClass: best.pitchClass, minor: best.minor)
    }

    private static func correlation(_ a: [Float], _ b: [Float]) -> Float {
        let ma = a.reduce(0, +) / Float(a.count), mb = b.reduce(0, +) / Float(b.count)
        var num: Float = 0, da: Float = 0, db: Float = 0
        for i in a.indices {
            let x = a[i] - ma, y = b[i] - mb
            num += x * y; da += x * x; db += y * y
        }
        return num / max(sqrt(da * db), 1e-9)
    }
}
