import Accelerate
import Foundation

/// Works out a song's structure: where the intro, verses, build-ups, choruses, breakdowns and outro
/// are. It looks at each bar's loudness, bass, brightness, busyness and harmony, finds the bars where
/// the music changes most, then names each section by how big it is compared to the rest of the song.
enum PhraseAnalyzer {
    /// What analysis collects in its one pass over the audio.
    struct Input {
        /// Energy of the mono mix and its <150 Hz band per frame.
        var energyFull: [Float]
        var energyLow: [Float]
        var onset: [Float]
        var framesPerSecond: Double
        /// Peak of the high band in each waveform bin.
        var high: [Float]
        var highBinsPerSecond: Double
        /// The mono mix at a low sample rate, for harmony.
        var signal: [Float]
        var signalRate: Double
        var duration: Double
    }

    private struct Bar {
        var start: Double
        var energy: Float = 0
        var bass: Float = 0
        var bright: Float = 0
        var busy: Float = 0
        var chroma = [Float](repeating: 0, count: 12)
    }

    static func analyze(_ input: Input, grid: BeatGrid) -> [Phrase]? {
        let bars = measure(input, grid: grid)
        guard bars.count >= 8 else { return nil }
        let features = normalized(bars)
        let boundaries = mergeLookalikes(findBoundaries(features), features: features)
        return label(bars: bars, boundaries: boundaries)
    }

    // MARK: Measuring each bar

    private static func measure(_ input: Input, grid: BeatGrid) -> [Bar] {
        // Bars count from the grid. Anything before the first whole bar joins it.
        let firstBeat = (grid.beat(at: 0) / 4).rounded(.down) * 4
        var starts: [Double] = []
        var beat = firstBeat + 4
        while true {
            let time = grid.seconds(atBeat: beat)
            if time >= input.duration - 1 { break }
            starts.append(starts.isEmpty ? 0 : time)
            beat += 4
        }
        guard starts.count >= 2 else { return [] }
        var bars = starts.map { Bar(start: $0) }
        let chroma = chromagram(input.signal, rate: input.signalRate)
        for i in bars.indices {
            let from = bars[i].start, to = i + 1 < bars.count ? bars[i + 1].start : input.duration
            bars[i].energy = sqrtMean(input.energyFull, from: from, to: to, perSecond: input.framesPerSecond)
            bars[i].bass = sqrtMean(input.energyLow, from: from, to: to, perSecond: input.framesPerSecond)
            bars[i].busy = mean(input.onset, from: from, to: to, perSecond: input.framesPerSecond)
            bars[i].bright = mean(input.high, from: from, to: to, perSecond: input.highBinsPerSecond)
            let a = Int(from * chroma.perSecond), b = Int(to * chroma.perSecond)
            var total = [Float](repeating: 0, count: 12)
            var count: Float = 0
            for f in a..<min(b, chroma.frames.count) where f >= 0 {
                vDSP_vadd(total, 1, chroma.frames[f], 1, &total, 1, 12)
                count += 1
            }
            if count > 0 {
                var length: Float = 0
                vDSP_svesq(total, 1, &length, 12)
                let divisor = max(length.squareRoot(), 1e-6)
                bars[i].chroma = total.map { $0 / divisor }
            }
        }
        return bars
    }

    private static func range(_ count: Int, from: Double, to: Double, perSecond: Double) -> Range<Int>? {
        let a = max(0, Int(from * perSecond)), b = min(count, Int(to * perSecond))
        return a < b ? a..<b : nil
    }

    private static func mean(_ x: [Float], from: Double, to: Double, perSecond: Double) -> Float {
        guard let r = range(x.count, from: from, to: to, perSecond: perSecond) else { return 0 }
        return x[r].reduce(0, +) / Float(r.count)
    }

    private static func sqrtMean(_ x: [Float], from: Double, to: Double, perSecond: Double) -> Float {
        mean(x, from: from, to: to, perSecond: perSecond).squareRoot()
    }

    /// Pitch-class energy every 2048 samples, from a short FFT.
    private static func chromagram(_ signal: [Float], rate: Double) -> (frames: [[Float]], perSecond: Double) {
        let log2n: vDSP_Length = 12
        let n = 1 << Int(log2n)
        let hop = n / 2
        let perSecond = rate / Double(hop)
        guard signal.count > n, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return ([], perSecond) }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var pitchClass = [Int](repeating: -1, count: n / 2)
        for k in 1..<(n / 2) {
            let frequency = Double(k) * rate / Double(n)
            guard frequency >= 110, frequency <= 2000 else { continue }
            let midi = 69 + 12 * log2(frequency / 440)
            pitchClass[k] = ((Int(midi.rounded()) % 12) + 12) % 12
        }
        var frames: [[Float]] = []
        frames.reserveCapacity(signal.count / hop)
        var frame = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: n / 2), imaginary = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)
        var start = 0
        while start + n <= signal.count {
            signal.withUnsafeBufferPointer { vDSP_vmul($0.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(n)) }
            real.withUnsafeMutableBufferPointer { rp in
                imaginary.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
                }
            }
            var chroma = [Float](repeating: 0, count: 12)
            for k in 1..<(n / 2) where pitchClass[k] >= 0 { chroma[pitchClass[k]] += magnitudes[k].squareRoot() }
            frames.append(chroma)
            start += hop
        }
        return (frames, perSecond)
    }

    // MARK: Finding where the music changes

    /// Each bar as a vector: the levels on a shared scale, so a change in any of them counts.
    private static func normalized(_ bars: [Bar]) -> [[Float]] {
        func scaled(_ values: [Float]) -> [Float] {
            let mean = values.reduce(0, +) / Float(values.count)
            let deviation = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)).squareRoot()
            // A level that barely moves shouldn't get stretched until its noise looks like structure.
            return values.map { ($0 - mean) / max(deviation, abs(mean) * 0.2, 1e-5) }
        }
        let energy = scaled(bars.map(\.energy)), bass = scaled(bars.map(\.bass))
        let bright = scaled(bars.map(\.bright)), busy = scaled(bars.map(\.busy))
        return bars.indices.map { i in
            [energy[i], bass[i], bright[i], busy[i] * 0.7] + bars[i].chroma.map { $0 * 1.2 }
        }
    }

    /// Foote's novelty: a checkerboard slid along the diagonal of the bars' similarity to each other
    /// scores highest where the bars before are alike, the bars after are alike, and the two differ.
    private static func findBoundaries(_ features: [[Float]]) -> [Int] {
        let n = features.count
        let radius = min(8, max(2, n / 4))
        func distance(_ a: Int, _ b: Int) -> Float {
            var total: Float = 0
            for d in features[a].indices {
                let delta = features[a][d] - features[b][d]
                total += delta * delta
            }
            return total.squareRoot()
        }
        var novelty = [Float](repeating: 0, count: n)
        for centre in 1..<n {
            var score: Float = 0, weightSum: Float = 0
            for x in -radius..<radius {
                for y in -radius..<radius {
                    let a = centre + x, b = centre + y
                    guard a >= 0, b >= 0, a < n, b < n, a < b else { continue }
                    let taper = Float(exp(-(Double(x * x + y * y)) / Double(radius * radius)))
                    // Bars on opposite sides of the centre count for; bars on the same side against.
                    let across = (x < 0) != (y < 0)
                    score += (across ? 1 : -1) * distance(a, b) * taper
                    weightSum += taper
                }
            }
            novelty[centre] = weightSum > 0 ? max(0, score / weightSum) : 0
        }

        // Music is built in fours and eights, counted from wherever the song's phrases begin.
        var phaseScore = [Float](repeating: 0, count: 8)
        for i in 0..<n { phaseScore[i % 8] += novelty[i] }
        let phase = phaseScore.indices.max { phaseScore[$0] < phaseScore[$1] } ?? 0
        let weighted = novelty.indices.map { i -> Float in
            let offset = (i - phase + 800) % 8
            return novelty[i] * (offset == 0 ? 1.5 : offset == 4 ? 1.25 : 1)
        }
        let mean = weighted.reduce(0, +) / Float(n)
        let deviation = (weighted.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(n)).squareRoot()
        let threshold = mean + 0.5 * deviation

        // Strongest first, keeping at least four bars between boundaries.
        var chosen: [Int] = []
        for i in weighted.indices.sorted(by: { weighted[$0] > weighted[$1] }) where weighted[i] > threshold && i >= 4 && i <= n - 4 {
            if chosen.allSatisfy({ abs($0 - i) >= 4 }) { chosen.append(i) }
        }
        return chosen.sorted()
    }

    /// Drops any boundary where the music on each side comes out much the same after all.
    private static func mergeLookalikes(_ boundaries: [Int], features: [[Float]]) -> [Int] {
        var kept = boundaries
        var changed = true
        while changed {
            changed = false
            let edges = [0] + kept + [features.count]
            var closest: (index: Int, distance: Float)?
            for i in kept.indices {
                let before = meanVector(features[edges[i]..<edges[i + 1]])
                let after = meanVector(features[edges[i + 1]..<edges[i + 2]])
                let distance = zip(before, after).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
                if closest == nil || distance < closest!.distance { closest = (i, distance) }
            }
            if let closest, closest.distance < minimumSectionDifference {
                kept.remove(at: closest.index)
                changed = true
            }
        }
        return kept
    }

    /// How different two neighbouring sections have to be, on the features' shared scale.
    private static let minimumSectionDifference: Float = 0.7

    private static func meanVector(_ rows: ArraySlice<[Float]>) -> [Float] {
        guard let first = rows.first else { return [] }
        var total = [Float](repeating: 0, count: first.count)
        for row in rows { for d in row.indices { total[d] += row[d] } }
        return total.map { $0 / Float(rows.count) }
    }

    // MARK: Naming the sections

    private static func label(bars: [Bar], boundaries: [Int]) -> [Phrase] {
        let edges = [0] + boundaries + [bars.count]
        // "Size": how much of a wall of sound this is. Bass and busyness matter as much as loudness.
        func size(_ range: Range<Int>) -> Float {
            let slice = bars[range]
            let count = Float(slice.count)
            return slice.reduce(0) { $0 + $1.energy } / count + 0.7 * slice.reduce(0) { $0 + $1.bass } / count
                + 0.5 * slice.reduce(0) { $0 + $1.bright } / count
        }
        let sections = zip(edges, edges.dropFirst()).map { $0..<$1 }
        let sizes = sections.map(size)
        guard let smallest = sizes.min(), let largest = sizes.max(), largest > smallest else {
            return [Phrase(start: 0, kind: .chorus)]
        }
        // Measured against the body of the song. A fade-out is far quieter than anything else, and
        // would make the whole of the rest look equally big. Sections only a little apart are just
        // the same level, which the floor allows for.
        let body = sizes.count > 2 ? sizes.dropFirst().dropLast() : sizes[...]
        let floor = min(body.min() ?? smallest, largest * 0.8)
        let isBig = sizes.map { ($0 - floor) / (largest - floor) >= 0.72 }
        // A breakdown takes the low end away; a verse is smaller than a chorus but its kick keeps going.
        let lowEnd = sections.map { range -> Float in bars[range].reduce(0) { $0 + $1.bass } / Float(range.count) }
        let fullest = max(lowEnd.max() ?? 0, 1e-6)
        let firstBig = isBig.firstIndex(of: true) ?? 0, lastBig = isBig.lastIndex(of: true) ?? sections.count - 1

        var kinds = [Phrase.Kind](repeating: .verse, count: sections.count)
        for i in sections.indices {
            let climbing = rising(bars[sections[i]])
            if isBig[i] {
                kinds[i] = .chorus
            } else if i == 0 {
                kinds[i] = .intro
            } else if i + 1 < sections.count, isBig[i + 1], climbing {
                kinds[i] = .up
            } else if i < firstBig {
                kinds[i] = .intro
            } else if i > lastBig {
                kinds[i] = .outro
            } else {
                kinds[i] = lowEnd[i] / fullest < 0.3 ? .down : .verse
            }
        }

        var phrases: [Phrase] = []
        for (i, section) in sections.enumerated() where phrases.last?.kind != kinds[i] {
            phrases.append(Phrase(start: bars[section.lowerBound].start, kind: kinds[i]))
        }
        return phrases
    }

    /// Whether a section is building: its second half is well above its first, or it keeps getting brighter.
    private static func rising(_ bars: ArraySlice<Bar>) -> Bool {
        guard bars.count >= 4 else { return false }
        let middle = bars.startIndex + bars.count / 2
        func average(_ slice: ArraySlice<Bar>, _ value: (Bar) -> Float) -> Float {
            slice.reduce(0) { $0 + value($1) } / Float(max(1, slice.count))
        }
        let first = bars[bars.startIndex..<middle], second = bars[middle..<bars.endIndex]
        let louder = average(second, \.energy) > average(first, \.energy) * 1.08
        let brighter = average(second, \.bright) > average(first, \.bright) * 1.15
        return louder || brighter
    }
}
