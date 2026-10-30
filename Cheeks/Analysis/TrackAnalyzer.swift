import Foundation

/// rekordbox-style 3-band waveform: per bin peak level of low / mid / high frequencies.
struct WaveformData {
    static let binsPerSecond = 300.0
    /// Bumped when the format or its contents change, so stale caches get recomputed.
    private static let magic: UInt32 = 0x4348_5732
    var low: [UInt8]
    var mid: [UInt8]
    var high: [UInt8]
    var count: Int { low.count }

    func encoded() -> Data {
        var data = Data()
        var header = [Self.magic, UInt32(count)]
        header.withUnsafeBytes { data.append(contentsOf: $0) }
        data.append(contentsOf: low)
        data.append(contentsOf: mid)
        data.append(contentsOf: high)
        return data
    }

    init(low: [UInt8], mid: [UInt8], high: [UInt8]) {
        self.low = low; self.mid = mid; self.high = high
    }

    init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let (magic, count) = data.withUnsafeBytes { ($0.loadUnaligned(fromByteOffset: 0, as: UInt32.self), $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        let n = Int(count)
        guard magic == Self.magic, data.count == 8 + n * 3 else { return nil }
        let bytes = [UInt8](data.dropFirst(8))
        low = Array(bytes[0..<n])
        mid = Array(bytes[n..<(2 * n)])
        high = Array(bytes[(2 * n)..<(3 * n)])
    }
}

/// A waveform per stem, in `Stem.allCases` order, computed once a track has been split.
struct StemWaveformData {
    var levels: [[UInt8]]
    var count: Int { levels.first?.count ?? 0 }

    /// Peak level per bin of each stem, all on one scale, so their relative sizes mean something.
    init(stems: [PCM16Stereo]) {
        let binSize = max(1, Int(AudioConfig.sampleRate / WaveformData.binsPerSecond))
        var peaks: [[Int32]] = []
        var overall: Int32 = 1
        for stem in stems {
            let bins = stem.frames / binSize
            var values = [Int32](repeating: 0, count: bins)
            let data = stem.data
            values.withUnsafeMutableBufferPointer { out in
                for b in 0..<bins {
                    var high: Int32 = 0
                    for i in (b * binSize)..<((b + 1) * binSize) {
                        high = max(high, abs(Int32(data[i * 2])), abs(Int32(data[i * 2 + 1])))
                    }
                    out[b] = high
                }
            }
            overall = max(overall, values.max() ?? 0)
            peaks.append(values)
        }
        levels = peaks.map { values in values.map { UInt8(min(255, $0 * 255 / overall)) } }
    }
}

struct AnalysisResult {
    var bpm: Double
    var firstBeat: Double
    /// Tempo changes, for tracks that weren't played to a click.
    var tempoMarkers: [TempoMarker]?
    var phrases: [Phrase]?
    var key: String?
    /// Integrated loudness in LUFS.
    var loudness: Double?
    var waveform: WaveformData
}

enum TrackAnalyzer {
    static let tempoHop = 512
    static let keyDecimation = 4

    /// One streaming pass over the track collects the 3-band waveform, onset energies and a
    /// decimated signal for key detection, so analysis never holds a full-length Float copy.
    /// A grid the track already has, say from rekordbox, is what its phrases get counted against.
    static func analyze(_ pcm: PCM16Stereo, knownGrid: BeatGrid? = nil) -> AnalysisResult {
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

        var loudness = LoudnessMeter(sampleRate: sr)

        // 4th-order filters are two cascaded biquads.
        let wl = Biquad.lowpass(200, sampleRate: sr), wh = Biquad.highpass(2500, sampleRate: sr)
        let tl = Biquad.lowpass(150, sampleRate: sr)
        var waveLow = (wl, wl), waveHigh = (wh, wh), tempoLow = (tl, tl)
        var keyLow = Biquad.lowpass(2500, sampleRate: sr)

        for i in 0..<n {
            let left = pcm.left(i), right = pcm.right(i)
            loudness.add(left, right)
            let m = (left + right) * 0.5
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
        // Highs are always small next to bass; lifting them makes them readable on screen, as
        // rekordbox does.
        func quantize(_ values: [Float], lift: Float = 1) -> [UInt8] {
            values.map { UInt8(min(255, ($0 / peak) * lift * 255)) }
        }
        let waveform = WaveformData(low: quantize(low), mid: quantize(mid, lift: 1.1), high: quantize(high, lift: 1.5))
        let onset = onsetEnvelope(energyFull: energyFull, energyLow: energyLow)
        var (bpm, firstBeat) = detectTempo(onset: onset, sampleRate: sr)
        let markers = TempoMapDetector.detect(onset: onset, fps: sr / Double(tempoHop), bpm: bpm, firstBeat: firstBeat)
        if let markers, let first = markers.first {
            bpm = TempoMapDetector.typicalBPM(markers)
            firstBeat = first.time
        }
        let key = KeyDetector.detect(signal: keySignal, rate: sr / Double(keyDecimation))
        let grid = knownGrid ?? markers.flatMap { BeatGrid(markers: $0) } ?? BeatGrid(bpm: bpm, firstBeat: firstBeat)
        let phrases = PhraseAnalyzer.analyze(PhraseAnalyzer.Input(energyFull: energyFull, energyLow: energyLow, onset: onset,
                                                                  framesPerSecond: sr / Double(tempoHop), high: high,
                                                                  highBinsPerSecond: WaveformData.binsPerSecond, signal: keySignal,
                                                                  signalRate: sr / Double(keyDecimation), duration: Double(n) / sr), grid: grid)
        return AnalysisResult(bpm: bpm, firstBeat: firstBeat, tempoMarkers: markers, phrases: phrases, key: key, loudness: loudness.integrated, waveform: waveform)
    }

    /// Onset strength: positive change in log energy, weighting the kick region.
    /// `energyFull`/`energyLow` are per-hop (512 frames) energies of the mono mix and its <150 Hz band.
    static func onsetEnvelope(energyFull: [Float], energyLow: [Float]) -> [Float] {
        let frames = energyFull.count
        guard frames > 0 else { return [] }
        var onset = [Float](repeating: 0, count: frames)
        var prevFull: Float = 0, prevLow: Float = 0
        for f in 0..<frames {
            let lf = log(1 + 100 * energyFull[f]), ll = log(1 + 100 * energyLow[f])
            onset[f] = max(0, lf - prevFull) + 1.5 * max(0, ll - prevLow)
            prevFull = lf; prevLow = ll
        }
        let mean = onset.reduce(0, +) / Float(frames)
        return onset.map { max(0, $0 - mean) }
    }

    /// Onset-envelope tempo detection: autocorrelation picks the period,
    /// then a comb search over the whole track refines BPM and finds the grid phase.
    static func detectTempo(onset: [Float], sampleRate: Double) -> (bpm: Double, firstBeat: Double) {
        let fps = sampleRate / Double(tempoHop)
        let frames = onset.count
        guard frames > 64 else { return (120, 0) }

        // Coarse: autocorrelation over 85–175 BPM.
        let minLag = Int(fps * 60 / 175), maxLag = Int(fps * 60 / 85) + 1
        var bestLag = minLag
        var bestScore: Float = -1
        for lag in minLag...maxLag {
            var s: Float = 0
            for i in 0..<(frames - lag) { s += onset[i] * onset[i + lag] }
            s /= Float(frames - lag)
            // A beat correlates with its own half and double, so lean towards where tempos usually are.
            let octaves = log2(fps * 60 / Double(lag) / 125)
            s *= Float(exp(-0.5 * octaves * octaves / (0.85 * 0.85)))
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

        /// How well a tempo lines up with the onsets, at its best phase.
        func combScore(_ candidate: Double) -> (score: Float, phase: Double) {
            let period = 60 * fps / candidate
            var top = (score: Float(-1), phase: 0.0)
            for p in 0..<max(1, Int(period)) {
                var s: Float = 0
                var pos = Double(p)
                while pos < Double(frames - 1) {
                    s += onset[Int(pos.rounded())]
                    pos += period
                }
                if s > top.score { top = (s, Double(p)) }
            }
            return top
        }

        var bpm = (best.bpm * 100).rounded() / 100
        var phase = best.phase
        // Almost all produced music sits on a whole number, so take one if it fits nearly as well.
        // A slightly wrong tempo drifts off the grid over a whole track, so this matters.
        let whole = bpm.rounded()
        if abs(whole - bpm) < 0.7 {
            let fit = combScore(whole)
            if abs(whole - bpm) < 0.08 || fit.score >= best.score * 0.97 {
                bpm = whole
                phase = fit.phase
            }
        }

        // Which of the four beats is the "1": bars start where the biggest changes land.
        let period = 60 * fps / bpm
        var strongest = (score: Float(-1), beat: 0)
        for beat in 0..<4 {
            var s: Float = 0
            var pos = phase + Double(beat) * period
            while pos < Double(frames - 1) {
                s += onset[Int(pos.rounded())]
                pos += period * 4
            }
            if s > strongest.score { strongest = (s, beat) }
        }
        return (bpm, (phase + Double(strongest.beat) * period) / fps)
    }
}

/// Integrated loudness per ITU-R BS.1770: K-weighting, 400 ms blocks with 75% overlap, and both gates.
struct LoudnessMeter {
    private var shelf: (Biquad, Biquad)
    private var highPass: (Biquad, Biquad)
    private let hop: Int
    private var hopEnergy: Float = 0
    private var hopCount = 0
    private var recent: [Float] = [0, 0, 0, 0]
    private var filled = 0
    private var blocks: [Float] = []

    init(sampleRate: Double) {
        // The standard's two stages, designed for this sample rate.
        let shelfFilter = Biquad.highShelf(1681.97, gainDB: 3.99984, q: 0.70717, sampleRate: sampleRate)
        let high = Biquad.highpass(38.1355, sampleRate: sampleRate, q: 0.50033)
        shelf = (shelfFilter, shelfFilter)
        highPass = (high, high)
        hop = Int(sampleRate * 0.1)
    }

    mutating func add(_ left: Float, _ right: Float) {
        let l = highPass.0.process(shelf.0.process(left))
        let r = highPass.1.process(shelf.1.process(right))
        hopEnergy += l * l + r * r
        hopCount += 1
        guard hopCount == hop else { return }
        recent.removeFirst()
        recent.append(hopEnergy / Float(hop))
        hopEnergy = 0
        hopCount = 0
        filled += 1
        if filled >= 4 { blocks.append(recent.reduce(0, +) / 4) }
    }

    var integrated: Double? {
        func lufs(_ energy: Double) -> Double { -0.691 + 10 * log10(max(energy, 1e-12)) }
        let audible = blocks.filter { lufs(Double($0)) > -70 }
        guard !audible.isEmpty else { return nil }
        let mean = audible.reduce(0.0) { $0 + Double($1) } / Double(audible.count)
        let threshold = lufs(mean) - 10
        let gated = audible.filter { lufs(Double($0)) > threshold }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0.0) { $0 + Double($1) } / Double(gated.count))
    }
}
