import Accelerate
import Foundation

/// What a track is doing in every bar, worked out from its stems: its real grid, which beat is the 1, its phrases,
/// which stems are playing, and what notes are sounding. Transitions are planned from this.
///
/// It leans on the stems because the drums stem shows the kick far more clearly than the mix does, and an arrangement
/// is mostly stems coming and going. A port of `tools/autodj/analyze.py`, which is where to try changes first.
struct TrackMap: Codable, Hashable {
    /// Bumped when the contents change, so saved maps get worked out again.
    static let currentVersion = 1
    var version = TrackMap.currentVersion

    var bpm: Double
    /// A beat that lands on a kick's attack, in seconds. It may be any beat of the bar.
    var firstBeat: Double
    /// How far the kicks stray from a straight grid, in ms. A drifting track doesn't get its grid replaced.
    var drift: Double
    /// Whether a straight grid fits: the kicks are there, and they sit on it.
    var isSteady: Bool
    /// Where bar 0 starts, in seconds. It's on a 1.
    var firstBar: Double
    var barCount: Int

    /// Each stem's level per bar in dB, in `Stem.allCases` order.
    var levels: [[Float]]
    var kickLevels: [Float]
    /// How much of each bar someone's singing in, 0...1.
    var vocal: [Float]
    /// Which stems are really there in each bar, against how loud each gets in this track.
    var on: [[Bool]]
    var hasKick: [Bool]
    /// The whole bar's level in dB.
    var energy: [Float]
    /// Bars where a 16-bar phrase starts are this, modulo 16.
    var lattice: Int
    /// Bars where the arrangement changes.
    var boundaries: [Int]
    /// Pitch-class energy per bar, in the melody and bass, and in the vocal.
    var harmony: [[Float]]
    var vocalNotes: [[Float]]
    var keyRoot: Int
    var keyIsMinor: Bool

    var barSeconds: Double { 240 / bpm }
    func seconds(atBar bar: Int) -> Double { firstBar + Double(bar) * barSeconds }
}

/// Maps are saved beside the stems, so a track only gets mapped once.
enum TrackMapStore {
    static func map(for id: UUID, stems: [PCM16Stereo]) -> TrackMap? {
        let url = StemCache.shared.directory.appendingPathComponent(id.uuidString).appendingPathExtension("map")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(TrackMap.self, from: data),
           saved.version == TrackMap.currentVersion {
            return saved
        }
        guard let map = TrackMapper.map(stems: stems) else { return nil }
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: url, options: .atomic) }
        return map
    }
}

enum TrackMapper {
    private static let rate = AudioConfig.sampleRate
    private static let hop = 256
    private static let hopsPerSecond = AudioConfig.sampleRate / 256
    // Stem order, from `Stem.allCases`.
    private static let vocals = Stem.vocals.rawValue, melody = Stem.melody.rawValue, bass = Stem.bass.rawValue, drums = Stem.drums.rawValue
    /// A kick's band reaches half its peak a little after the attack starts.
    private static let attackLag = 0.003
    /// Kicks further than this from a straight grid (90th percentile, ms) mean it doesn't fit.
    static let steadyDrift = 13.5

    /// Nil if the stems are too short to say anything about.
    static func map(stems: [PCM16Stereo]) -> TrackMap? {
        guard stems.count == 4, stems[0].frames > Int(rate * 20) else { return nil }
        let frames = stems[0].frames
        let (kickOnsets, brightOnsets) = onsets(stems[drums])
        guard let fitted = fitGrid(low: kickOnsets, high: brightOnsets) else { return nil }
        let beat = 60 / fitted.bpm
        let attack = attackOffset(stems[drums], bpm: fitted.bpm, first: fitted.first)
        let first = max(0, fitted.first + attack - attackLag)
        let origin = first - (first / beat).rounded(.down) * beat
        let beatCount = Int((Double(frames) / rate - origin) / beat)
        guard beatCount >= 16 else { return nil }
        let edges = (0...beatCount).map { Int(((origin + Double($0) * beat) * rate).rounded()) }

        // Every stem's level per beat, all on one scale, plus the kick.
        let power = (0..<4).map { beatPower(stems[$0], edges: edges) }
        let kickPower = beatPower(stems[drums], edges: edges, filter: Biquad.lowpass(120, sampleRate: rate))
        let levelDB = power.map { $0.map(decibels) }
        let kickDB = kickPower.map(decibels)
        let chromaHarmony = chroma(of: [stems[melody], stems[bass]], edges: edges)
        let chromaVocal = chroma(of: [stems[vocals]], edges: edges)

        let downbeat = findDownbeat(levelDB: levelDB, kickDB: kickDB, chroma: chromaHarmony, drums: stems[drums], edges: edges)
        let barBeats = Array(stride(from: downbeat, to: beatCount - 3, by: 4))
        let bars = barBeats.count
        guard bars >= 8 else { return nil }

        func overBar(_ values: [Float], _ start: Int) -> Float { decibels(values[start..<(start + 4)].reduce(0, +) / 4) }
        let barLevels = (0..<4).map { s in barBeats.map { overBar(power[s], $0) } }
        let barKick = barBeats.map { overBar(kickPower, $0) }
        // A track with no singer still leaks a quiet vocal stem, so it has to stand up against the whole mix too.
        let vocalTop = percentile(levelDB[vocals], 98)
        let loudest = (0..<4).map { percentile(levelDB[$0], 97) }.max() ?? 0
        let vocalFloor = max(vocalTop - 14, loudest - 16)
        let cover = barBeats.map { start in Float(levelDB[vocals][start..<(start + 4)].filter { $0 > vocalFloor }.count) / 4 }

        let tops = barLevels.map { percentile($0, 97) }
        let overall = tops.max() ?? 0
        let on = (0..<4).map { s in barLevels[s].map { $0 > max(tops[s] - 14, overall - 26) } }
        let kickTop = percentile(barKick, 95)
        let hasKick = barKick.map { $0 > max(kickTop - 12, overall - 30) }
        let energy = (0..<bars).map { b -> Float in
            10 * log10((0..<4).reduce(Float(1e-9)) { $0 + pow(10, barLevels[$1][b] / 10) })
        }

        let features = (0..<bars).map { b -> [Float] in
            (0..<4).map { clamp(barLevels[$0][b]) } + [clamp(barKick[b]), max(cover[b] * -30, -30)]
        }
        let change = novelty(features, reach: 4)
        var bestLattice = (score: -Float.infinity, lattice: 0)
        for offset in 0..<16 {
            var score: Float = 0
            for bar in stride(from: offset, to: bars, by: 16) { score += change[bar] * change[bar] }
            for bar in stride(from: offset, to: bars, by: 8) { score += 0.5 * change[bar] * change[bar] }
            if score > bestLattice.score { bestLattice = (score, offset) }
        }
        let threshold = max(percentile(change, 70), 2)
        var boundaries: Set<Int> = [0, bars]
        for line in stride(from: bestLattice.lattice % 4, to: bars, by: 4) {
            let reach = change[max(0, line - 1)..<min(bars, line + 2)]
            if (reach.max() ?? 0) >= threshold { boundaries.insert(line) }
        }

        let barHarmony = barBeats.map { start in sum(chromaHarmony[start..<(start + 4)]) }
        let barVocal = barBeats.map { start in sum(chromaVocal[start..<(start + 4)]) }
        let key = detectKey(chromaHarmony)
        let keptKicks = hasKick.filter { $0 }.count
        return TrackMap(
            bpm: fitted.bpm, firstBeat: first, drift: fitted.drift, isSteady: fitted.drift < steadyDrift && keptKicks * 4 > bars,
            firstBar: origin + Double(downbeat) * beat, barCount: bars,
            levels: barLevels, kickLevels: barKick, vocal: cover, on: on, hasKick: hasKick, energy: energy,
            lattice: bestLattice.lattice, boundaries: boundaries.sorted(), harmony: barHarmony, vocalNotes: barVocal,
            keyRoot: key.root, keyIsMinor: key.minor)
    }

    // MARK: Grid

    /// Half-wave rectified change in log level per hop: in the kick's band, and in everything above it.
    private static func onsets(_ drums: PCM16Stereo) -> (low: [Float], high: [Float]) {
        let count = drums.frames / hop
        var low = [Float](repeating: 0, count: count), high = low
        var filter = Biquad.lowpass(150, sampleRate: rate)
        var lastLow: Float = 0, lastHigh: Float = 0
        let data = drums.data, scale = 1 / (2 * PCM16Stereo.stemHeadroom * 32768)
        for h in 0..<count {
            var lowEnergy: Float = 0, highEnergy: Float = 0
            for i in (h * hop)..<((h + 1) * hop) {
                let x = (Float(data[i * 2]) + Float(data[i * 2 + 1])) * scale
                let y = filter.process(x)
                lowEnergy += y * y
                highEnergy += (x - y) * (x - y)
            }
            let l = log(1 + (lowEnergy / Float(hop)).squareRoot() * 200), r = log(1 + (highEnergy / Float(hop)).squareRoot() * 200)
            low[h] = max(0, l - lastLow)
            high[h] = max(0, r - lastHigh)
            lastLow = l
            lastHigh = r
        }
        return (low, high)
    }

    /// How sharply the onsets fold up at this beat length, and where.
    private static func foldScore(_ onset: [Float], period: Double) -> (score: Float, peak: Int) {
        let bins = Int(period.rounded())
        guard bins >= 8 else { return (0, 0) }
        var sums = [Float](repeating: 0, count: bins + 1), counts = [Float](repeating: 0, count: bins + 1)
        var position = 0.0
        for value in onset {
            let index = min(Int(position), bins)
            sums[index] += value
            counts[index] += 1
            position += 1
            if position >= period { position -= period }
        }
        // The last part-bin is short, and it belongs with the first.
        sums[0] += sums[bins]
        counts[0] += counts[bins]
        var fold = (0..<bins).map { counts[$0] > 0 ? sums[$0] / counts[$0] : 0 }
        let raw = fold
        for i in 0..<bins { fold[i] = (raw[(i + bins - 1) % bins] + raw[i] + raw[(i + 1) % bins]) / 3 }
        let peak = fold.indices.max { fold[$0] < fold[$1] } ?? 0
        return (fold[peak] - fold.sorted()[bins / 2], peak)
    }

    /// A constant-tempo grid, lined up on the kicks. Most club tracks have one.
    private static func fitGrid(low: [Float], high: [Float]) -> (bpm: Double, first: Double, drift: Double)? {
        guard low.count > 1000 else { return nil }
        let loudest = percentile(zip(low, high).map { $0 + 0.25 * $1 }, 99.5)
        guard loudest > 0 else { return nil }
        let onset = zip(low, high).map { ($0 + 0.25 * $1) / loudest }
        // A beat folds up sharply at the true tempo and its multiples, so the usual club range is preferred.
        var best = (score: Float(-1), bpm: 120.0)
        var bpm = 70.0
        while bpm < 190 {
            let spread = log2(bpm / 125) / 0.45
            let score = foldScore(onset, period: hopsPerSecond * 60 / bpm).score * Float(exp(-0.5 * spread * spread))
            if score > best.score { best = (score, bpm) }
            bpm += 0.1
        }
        var fine = (score: Float(-1), bpm: best.bpm)
        var candidate = best.bpm - 0.3
        while candidate < best.bpm + 0.3 {
            let score = foldScore(onset, period: hopsPerSecond * 60 / candidate).score
            if score > fine.score { fine = (score, candidate) }
            candidate += 0.005
        }

        // Regress the kicks' positions against beat numbers, for the tempo and phase exactly.
        var period = hopsPerSecond * 60 / fine.bpm
        var phase = Double(foldScore(onset, period: period).peak)
        let strong = percentile(low, 90)
        var xs: [Double] = [], ys: [Double] = [], weights: [Double] = []
        for _ in 0..<3 {
            xs = []; ys = []; weights = []
            let beats = Int((Double(low.count) - phase) / period)
            let reach = Int(period * 0.12)
            for n in 0..<max(0, beats) {
                let centre = Int(phase + Double(n) * period)
                guard centre - reach >= 0, centre + reach + 1 < low.count else { continue }
                var top = centre - reach
                for i in (centre - reach)...(centre + reach) where low[i] > low[top] { top = i }
                if low[top] > strong {
                    xs.append(Double(n))
                    ys.append(Double(top))
                    weights.append(Double(low[top]))
                }
            }
            guard xs.count >= 16, let line = weightedLine(xs, ys, weights) else { break }
            period = line.slope
            phase = line.intercept
        }
        guard period > 0 else { return nil }
        var fitted = hopsPerSecond * 60 / period
        if abs(fitted - fitted.rounded()) < 0.06 { fitted = fitted.rounded() }
        var drift = 0.0
        if xs.count >= 16 {
            let residuals = zip(xs, ys).map { Float(abs($1 - ($0 * period + phase)) / hopsPerSecond * 1000) }
            drift = Double(percentile(residuals, 90))
        }
        return (fitted, phase / hopsPerSecond, drift)
    }

    private static func weightedLine(_ xs: [Double], _ ys: [Double], _ weights: [Double]) -> (slope: Double, intercept: Double)? {
        var sw = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for i in xs.indices {
            sw += weights[i]; sx += weights[i] * xs[i]; sy += weights[i] * ys[i]
            sxx += weights[i] * xs[i] * xs[i]; sxy += weights[i] * xs[i] * ys[i]
        }
        let d = sw * sxx - sx * sx
        guard d != 0 else { return nil }
        let slope = (sw * sxy - sx * sy) / d
        return (slope, (sy - slope * sx) / sw)
    }

    /// Where a kick's attack really is against the fitted grid, in seconds: the median, across the track, of where
    /// its band first reaches half that kick's peak. Hops are too coarse to say this on their own.
    private static func attackOffset(_ drums: PCM16Stereo, bpm: Double, first: Double) -> Double {
        let beat = 60 / bpm
        let reach = Int(0.2 * beat * rate)
        guard reach > 0 else { return 0 }
        var offsets: [Float] = []
        var window = [Float](repeating: 0, count: reach * 2)
        let data = drums.data
        var n = 0
        while true {
            let centre = Int((first + Double(n) * beat) * rate)
            n += 1
            if centre + reach >= drums.frames { break }
            guard centre - reach >= 0 else { continue }
            var filter = Biquad.lowpass(150, sampleRate: rate)
            // The filter settles over the first part of the window, ahead of where the attack can be.
            for i in 0..<(reach * 2) {
                let j = centre - reach + i
                window[i] = abs(filter.process((Float(data[j * 2]) + Float(data[j * 2 + 1])) / (2 * PCM16Stereo.stemHeadroom * 32768)))
            }
            let peak = window.max() ?? 0
            guard peak > 0.03, let at = window.firstIndex(where: { $0 >= peak / 2 }) else { continue }
            offsets.append(Float(Double(at - reach) / rate))
        }
        return offsets.count >= 16 ? Double(percentile(offsets, 50)) : 0
    }

    // MARK: Downbeat

    /// Which beat of four is the 1. Several weak clues add up: harmony and arrangement change on it, the clap sits
    /// on 2 and 4, and club tracks tend to start on a bar line. Agrees with Beat This on 15 of 16 test tracks.
    private static func findDownbeat(levelDB: [[Float]], kickDB: [Float], chroma: [[Float]], drums: PCM16Stereo, edges: [Int]) -> Int {
        var scores = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        let beats = kickDB.count

        // Chords and bass notes change on the 1.
        let sizes = chroma.map { Float(vDSP.sumOfSquares($0)).squareRoot() }
        var weight = [Float](repeating: 0, count: beats), flux = weight
        for b in 1..<beats {
            weight[b] = min(sizes[b], sizes[b - 1])
            if sizes[b] > 0, sizes[b - 1] > 0 { flux[b] = 1 - vDSP.dot(chroma[b], chroma[b - 1]) / (sizes[b] * sizes[b - 1]) }
        }
        let weightTop = percentile(weight, 95) + 1e-9
        for b in 0..<beats { scores[0][b % 4] += flux[b] * min(weight[b] / weightTop, 1) }

        // Stems come and go on the 1: the bar after each beat against the bar before it.
        let features = (0..<beats).map { b in (0..<4).map { clamp(levelDB[$0][b]) } + [clamp(kickDB[b])] }
        let sharp = novelty(features, reach: 4)
        for b in 0..<beats { scores[1][b % 4] += sharp[b] * sharp[b] }

        // The clap: the drums are brightest right on 2 and 4. It can't tell 1 from 3.
        let claps = clapLevels(drums, edges: edges)
        var byPhase = [[Float]](repeating: [], count: 4)
        for b in 0..<beats { byPhase[b % 4].append(claps[b]) }
        let medians = byPhase.map { percentile($0, 50) }
        for p in 0..<4 { scores[2][p] = -(medians[p] + medians[(p + 2) % 4]) }

        // The first beat with a real kick on it.
        let kickTop = percentile(kickDB, 90)
        if let firstKick = kickDB.firstIndex(where: { $0 > kickTop - 10 }) { scores[3][firstKick % 4] = 1 }

        // Equal votes, each scaled to its own spread.
        var total = [Float](repeating: 0, count: 4)
        for clue in scores {
            let mean = clue.reduce(0, +) / 4
            let spread = (clue.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 4).squareRoot() + 1e-9
            for p in 0..<4 { total[p] += (clue[p] - mean) / spread }
        }
        return total.indices.max { total[$0] < total[$1] } ?? 0
    }

    private static func clapLevels(_ drums: PCM16Stereo, edges: [Int]) -> [Float] {
        var out = [Float](repeating: 0, count: edges.count - 1)
        let reach = Int(0.07 * rate), data = drums.data
        var filter = Biquad.highpass(1500, sampleRate: rate)
        var position = 0
        for b in 0..<(edges.count - 1) {
            let from = max(0, edges[b] - reach / 4), to = min(drums.frames, edges[b] + reach)
            var energy: Float = 0
            // The filter runs on through the track, so it's settled whenever it's listened to.
            while position < to {
                let y = filter.process((Float(data[position * 2]) + Float(data[position * 2 + 1])) / (2 * PCM16Stereo.stemHeadroom * 32768))
                if position >= from { energy += y * y }
                position += 1
            }
            out[b] = 10 * log10(energy + 1e-9)
        }
        return out
    }

    // MARK: Levels and notes

    /// Mean power of a stem in each span between edges, optionally through a filter.
    private static func beatPower(_ stem: PCM16Stereo, edges: [Int], filter: Biquad? = nil) -> [Float] {
        var out = [Float](repeating: 0, count: edges.count - 1)
        var filter = filter
        let data = stem.data, scale = 1 / (2 * PCM16Stereo.stemHeadroom * 32768)
        var position = 0
        for b in 0..<(edges.count - 1) {
            let from = max(0, edges[b]), to = min(stem.frames, edges[b + 1])
            guard to > from else { continue }
            var sum: Float = 0
            if filter != nil {
                while position < to {
                    let y = filter!.process((Float(data[position * 2]) + Float(data[position * 2 + 1])) * scale)
                    if position >= from { sum += y * y }
                    position += 1
                }
            } else {
                for i in from..<to {
                    let x = (Float(data[i * 2]) + Float(data[i * 2 + 1])) * scale
                    sum += x * x
                }
            }
            out[b] = sum / Float(to - from)
        }
        return out
    }

    /// Pitch-class energy in each beat, from 8192-point spectra of these stems added together.
    private static func chroma(of stems: [PCM16Stereo], edges: [Int]) -> [[Float]] {
        let n = 8192, hopSize = 2048, log2n = vDSP_Length(13)
        var out = [[Float]](repeating: [Float](repeating: 0, count: 12), count: edges.count - 1)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return out }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var pitchClass = [Int](repeating: -1, count: n / 2)
        for k in 1..<(n / 2) {
            let frequency = Double(k) * rate / Double(n)
            guard frequency >= 65, frequency <= 2100 else { continue }
            pitchClass[k] = (Int((12 * log2(frequency / 440)).rounded()) + 9 + 1200) % 12
        }
        var frame = [Float](repeating: 0, count: n), real = [Float](repeating: 0, count: n / 2), imag = real, mags = real
        var beat = 0
        var start = 0
        let frames = stems[0].frames, scale = 1 / (2 * PCM16Stereo.stemHeadroom * 32768)
        while start + n <= frames {
            let centre = start + n / 2
            while beat < edges.count - 1, edges[beat + 1] <= centre { beat += 1 }
            if beat >= edges.count - 1 { break }
            if edges[beat] <= centre {
                for i in 0..<n {
                    var x: Float = 0
                    for stem in stems { x += Float(stem.data[(start + i) * 2]) + Float(stem.data[(start + i) * 2 + 1]) }
                    frame[i] = x * scale * window[i]
                }
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
                for k in 1..<(n / 2) where pitchClass[k] >= 0 { out[beat][pitchClass[k]] += mags[k] }
            }
            start += hopSize
        }
        return out
    }

    private static func detectKey(_ chroma: [[Float]]) -> (root: Int, minor: Bool) {
        let major: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let total = sum(chroma[...])
        func correlation(_ a: [Float], _ b: [Float]) -> Float {
            let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
            var ab: Float = 0, aa: Float = 0, bb: Float = 0
            for i in 0..<12 { ab += (a[i] - ma) * (b[i] - mb); aa += (a[i] - ma) * (a[i] - ma); bb += (b[i] - mb) * (b[i] - mb) }
            return ab / max((aa * bb).squareRoot(), 1e-9)
        }
        var best = (score: -Float.infinity, root: 0, minor: false)
        for root in 0..<12 {
            for (profile, isMinor) in [(major, false), (minor, true)] {
                let score = correlation(total, (0..<12).map { profile[($0 - root + 12) % 12] })
                if score > best.score { best = (score, root, isMinor) }
            }
        }
        return (best.root, best.minor)
    }

    // MARK: Small helpers

    private static func decibels(_ power: Float) -> Float { 10 * log10(power + 1e-10) }
    private static func clamp(_ db: Float) -> Float { max(-60, min(0, db)) }

    private static func sum(_ rows: ArraySlice<[Float]>) -> [Float] {
        var out = [Float](repeating: 0, count: 12)
        for row in rows { for i in 0..<12 { out[i] += row[i] } }
        return out
    }

    private static func percentile(_ values: [Float], _ p: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = p / 100 * Float(sorted.count - 1)
        let low = Int(position), high = min(low + 1, sorted.count - 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Float(low))
    }

    /// Distance between the `reach` steps before and after each step.
    private static func novelty(_ features: [[Float]], reach: Int) -> [Float] {
        let n = features.count
        var out = [Float](repeating: 0, count: n)
        guard n > reach * 2, let width = features.first?.count else { return out }
        for i in reach..<(n - reach) {
            var total: Float = 0
            for f in 0..<width {
                var before: Float = 0, after: Float = 0
                for j in (i - reach)..<i { before += features[j][f] }
                for j in i..<(i + reach) { after += features[j][f] }
                let difference = (after - before) / Float(reach)
                total += difference * difference
            }
            out[i] = total.squareRoot()
        }
        return out
    }
}
