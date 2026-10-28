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
    static func analyze(_ audio: DecodedAudio) -> AnalysisResult {
        let mono = zip(audio.left, audio.right).map { ($0 + $1) * 0.5 }
        let waveform = makeWaveform(mono: mono, sampleRate: audio.sampleRate)
        let (bpm, firstBeat) = detectTempo(mono: mono, sampleRate: audio.sampleRate)
        let key = KeyDetector.detect(mono: mono, sampleRate: audio.sampleRate)
        return AnalysisResult(bpm: bpm, firstBeat: firstBeat, key: key, waveform: waveform)
    }

    static func makeWaveform(mono: [Float], sampleRate: Double) -> WaveformData {
        let lowBand = Biquad.cascade(.lowpass(200, sampleRate: sampleRate), mono)
        let highBand = Biquad.cascade(.highpass(2500, sampleRate: sampleRate), mono)
        let binSize = max(1, Int(sampleRate / WaveformData.binsPerSecond))
        let bins = mono.count / binSize
        var low = [Float](repeating: 0, count: bins)
        var mid = [Float](repeating: 0, count: bins)
        var high = [Float](repeating: 0, count: bins)
        for b in 0..<bins {
            var pl: Float = 0, pm: Float = 0, ph: Float = 0
            let start = b * binSize
            for i in start..<(start + binSize) {
                let l = lowBand[i], h = highBand[i]
                pl = max(pl, abs(l))
                ph = max(ph, abs(h))
                pm = max(pm, abs(mono[i] - l - h))
            }
            low[b] = pl; mid[b] = pm; high[b] = ph
        }
        let peak = max(low.max() ?? 0, mid.max() ?? 0, high.max() ?? 0, 0.0001)
        func quantize(_ values: [Float]) -> [UInt8] {
            values.map { UInt8(min(255, ($0 / peak) * 255)) }
        }
        return WaveformData(low: quantize(low), mid: quantize(mid), high: quantize(high))
    }

    /// Onset-envelope tempo detection: autocorrelation picks the period,
    /// then a comb search over the whole track refines BPM and finds the grid phase.
    static func detectTempo(mono: [Float], sampleRate: Double) -> (bpm: Double, firstBeat: Double) {
        let hop = 512
        let fps = sampleRate / Double(hop)
        let lowBand = Biquad.cascade(.lowpass(150, sampleRate: sampleRate), mono)
        let frames = mono.count / hop
        guard frames > 64 else { return (120, 0) }

        // Onset strength: positive change in log energy, weighting the kick region.
        var onset = [Float](repeating: 0, count: frames)
        var prevFull: Float = 0, prevLow: Float = 0
        for f in 0..<frames {
            var eFull: Float = 0, eLow: Float = 0
            for i in (f * hop)..<(f * hop + hop) {
                eFull += mono[i] * mono[i]
                eLow += lowBand[i] * lowBand[i]
            }
            let lf = log(1 + 100 * eFull), ll = log(1 + 100 * eLow)
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
