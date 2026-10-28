import Foundation

/// rekordbox-style 3-band waveform: per bin peak level of low / mid / high frequencies.
struct WaveformData {
    static let binsPerSecond = 150.0
    var low: [UInt8]
    var mid: [UInt8]
    var high: [UInt8]
    var count: Int { low.count }

    func encoded() -> Data {
        var data = Data()
        var n = UInt32(count)
        withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
        data.append(contentsOf: low)
        data.append(contentsOf: mid)
        data.append(contentsOf: high)
        return data
    }

    init(low: [UInt8], mid: [UInt8], high: [UInt8]) {
        self.low = low; self.mid = mid; self.high = high
    }

    init?(data: Data) {
        guard data.count >= 4 else { return nil }
        let n = Int(data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard data.count == 4 + n * 3 else { return nil }
        let bytes = [UInt8](data.dropFirst(4))
        low = Array(bytes[0..<n])
        mid = Array(bytes[n..<(2 * n)])
        high = Array(bytes[(2 * n)..<(3 * n)])
    }
}

struct AnalysisResult {
    var bpm: Double
    var firstBeat: Double
    var key: String?
    var waveform: WaveformData
}

enum TrackAnalyzer {
    static let tempoHop = 512
    static let keyDecimation = 4

    /// One streaming pass over the track collects the 3-band waveform, onset energies and a
    /// decimated signal for key detection, so analysis never holds a full-length Float copy.
    static func analyze(_ pcm: PCM16Stereo) -> AnalysisResult {
        let sr = AudioConfig.sampleRate
        let n = pcm.frames
        let binSize = max(1, Int(sr / WaveformData.binsPerSecond))
        let bins = n / binSize
        let hops = n / tempoHop
        let keyCount = n / keyDecimation

        var low = [Float](repeating: 0, count: bins)
        var mid = [Float](repeating: 0, count: bins)
        var high = [Float](repeating: 0, count: bins)
        var energyFull = [Float](repeating: 0, count: hops)
        var energyLow = [Float](repeating: 0, count: hops)
        var keySignal = [Float](repeating: 0, count: keyCount)

        // 4th-order filters are two cascaded biquads.
        let wl = Biquad.lowpass(200, sampleRate: sr), wh = Biquad.highpass(2500, sampleRate: sr)
        let tl = Biquad.lowpass(150, sampleRate: sr)
        var waveLow = (wl, wl), waveHigh = (wh, wh), tempoLow = (tl, tl)
        var keyLow = Biquad.lowpass(2500, sampleRate: sr)

        for i in 0..<n {
            let m = (pcm.left(i) + pcm.right(i)) * 0.5
            let b = i / binSize
            if b < bins {
                let l = waveLow.1.process(waveLow.0.process(m))
                let h = waveHigh.1.process(waveHigh.0.process(m))
                low[b] = max(low[b], abs(l))
                high[b] = max(high[b], abs(h))
                mid[b] = max(mid[b], abs(m - l - h))
            }
            let f = i / tempoHop
            if f < hops {
                let t = tempoLow.1.process(tempoLow.0.process(m))
                energyFull[f] += m * m
                energyLow[f] += t * t
            }
            if i < keyCount * keyDecimation {
                let y = keyLow.process(m)
                if i % keyDecimation == 0 { keySignal[i / keyDecimation] = y }
            }
        }

        let peak = max(low.max() ?? 0, mid.max() ?? 0, high.max() ?? 0, 0.0001)
        func quantize(_ values: [Float]) -> [UInt8] {
            values.map { UInt8(min(255, ($0 / peak) * 255)) }
        }
        let waveform = WaveformData(low: quantize(low), mid: quantize(mid), high: quantize(high))
        let (bpm, firstBeat) = detectTempo(energyFull: energyFull, energyLow: energyLow, sampleRate: sr)
        let key = KeyDetector.detect(signal: keySignal, rate: sr / Double(keyDecimation))
        return AnalysisResult(bpm: bpm, firstBeat: firstBeat, key: key, waveform: waveform)
    }

    /// Onset-envelope tempo detection: autocorrelation picks the period,
    /// then a comb search over the whole track refines BPM and finds the grid phase.
    /// `energyFull`/`energyLow` are per-hop (512 frames) energies of the mono mix and its <150 Hz band.
    static func detectTempo(energyFull: [Float], energyLow: [Float], sampleRate: Double) -> (bpm: Double, firstBeat: Double) {
        let fps = sampleRate / Double(tempoHop)
        let frames = energyFull.count
        guard frames > 64 else { return (120, 0) }

        // Onset strength: positive change in log energy, weighting the kick region.
        var onset = [Float](repeating: 0, count: frames)
        var prevFull: Float = 0, prevLow: Float = 0
        for f in 0..<frames {
            let lf = log(1 + 100 * energyFull[f]), ll = log(1 + 100 * energyLow[f])
            onset[f] = max(0, lf - prevFull) + 1.5 * max(0, ll - prevLow)
            prevFull = lf; prevLow = ll
        }
        let mean = onset.reduce(0, +) / Float(frames)
        onset = onset.map { max(0, $0 - mean) }

        // Coarse: autocorrelation over 85–175 BPM.
        let minLag = Int(fps * 60 / 175), maxLag = Int(fps * 60 / 85) + 1
        var bestLag = minLag
        var bestScore: Float = -1
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in 0..<(frames - lag) { s += onset[i] * onset[i + lag] }
            s /= Float(frames - lag)
            if s > bestScore { bestScore = s; bestLag = lag }
        }
        let coarseBPM = 60 * fps / Double(bestLag)

        // Fine: comb search for the BPM and phase that line up with the most onsets.
        var best = (score: Float(-1), bpm: coarseBPM, phase: 0.0)
        var candidate = coarseBPM - 2
        while candidate <= coarseBPM + 2 {
            let period = 60 * fps / candidate
            let steps = Int(period)
            for p in 0..<max(1, steps) {
                var s: Float = 0
                var pos = Double(p)
                while pos < Double(frames - 1) {
                    s += onset[Int(pos.rounded())]
                    pos += period
                }
                if s > best.score { best = (s, candidate, Double(p)) }
            }
            candidate += 0.02
        }

        var bpm = (best.bpm * 100).rounded() / 100
        if abs(bpm - bpm.rounded()) < 0.08 { bpm = bpm.rounded() }
        let beatLength = 60 / bpm
        var firstBeat = best.phase / fps
        while firstBeat >= beatLength { firstBeat -= beatLength }
        return (bpm, firstBeat)
    }
}
