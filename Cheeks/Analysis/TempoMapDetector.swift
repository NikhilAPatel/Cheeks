import Foundation

/// Finds tempo changes in tracks that weren't played to a click. A beat tracker follows the music
/// beat by beat, and if the beats it finds wander away from a steady grid, the result becomes the
/// track's tempo map. Almost everything produced stays on one tempo, and a steady grid is better
/// for those, so this has to be sure before it says anything.
enum TempoMapDetector {
    /// Smoothed beats must wander this far from a steady grid (seconds)…
    private static let wanderThreshold = 0.04
    /// …and the tempo really has to move by this much over the track (BPM between the 10th and 90th percentile).
    private static let spreadThreshold = 0.8
    private static let beatsPerMarker = 4

    /// `onset` is the onset strength per frame, at `fps` frames a second. Returns nil for a steady track.
    static func detect(onset: [Float], fps: Double, bpm: Double) -> [TempoMarker]? {
        guard bpm > 0 else { return nil }
        let beats = trackBeats(onset: onset, period: 60 * fps / bpm)
        guard beats.count >= 32 else { return nil }

        // Only beats with something happening on them count. Through a breakdown the tracker is
        // guessing, and its guesses creep because it can only move in whole frames.
        let strengths = beats.map { onset[$0] }
        let threshold = strengths.sorted()[strengths.count / 2] * 0.5
        let confirmed = beats.indices.filter { strengths[$0] > threshold && strengths[$0] > 0 }
        guard confirmed.count >= 24 else { return nil }

        // Each beat's distance from the best steady grid through them all.
        let times = beats.map { Double($0) / fps }
        let line = fitLine(confirmed.map { (Double($0), times[$0]) })
        let residual = beats.indices.map { times[$0] - (line.intercept + line.slope * Double($0)) }
        let smoothed = smooth(residual, confirmed: confirmed, radius: 8)
        guard let wander = smoothed.map(abs).max(), wander >= wanderThreshold else { return nil }

        // Marks every bar through the smoothed beats, so a drummer's small push and pull doesn't
        // turn into tempo changes.
        let steady = beats.indices.map { line.intercept + line.slope * Double($0) + smoothed[$0] }
        let downbeat = strongestBarPhase(confirmed: confirmed, strengths: strengths)
        var markers: [TempoMarker] = []
        var i = downbeat
        while i + beatsPerMarker < steady.count {
            let span = steady[i + beatsPerMarker] - steady[i]
            guard span > 0 else { return nil }
            markers.append(TempoMarker(time: steady[i], bpm: 60 * Double(beatsPerMarker) / span))
            i += beatsPerMarker
        }
        guard let last = markers.last, i < steady.count else { return nil }
        markers.append(TempoMarker(time: steady[i], bpm: last.bpm))
        guard markers.count >= 4 else { return nil }

        let sorted = markers.map(\.bpm).sorted()
        let spread = sorted[sorted.count * 9 / 10] - sorted[sorted.count / 10]
        return spread >= spreadThreshold ? markers : nil
    }

    /// The tempo a track with these markers is mostly at.
    static func typicalBPM(_ markers: [TempoMarker]) -> Double {
        let sorted = markers.map(\.bpm).sorted()
        return (sorted[sorted.count / 2] * 100).rounded() / 100
    }

    /// Ellis's dynamic-programming beat tracker: the best chain of onsets, where each step costs
    /// more the further it is from the expected beat length.
    private static func trackBeats(onset: [Float], period: Double) -> [Int] {
        let n = onset.count
        guard n > Int(period * 4), period >= 4 else { return [] }
        let deviation = onset.reduce(0) { $0 + $1 * $1 } / Float(n)
        let scale = max(deviation.squareRoot(), 1e-6)
        let shortest = max(1, Int((period * 0.8).rounded(.down))), longest = Int((period * 1.25).rounded(.up))
        var penalty = [Float](repeating: 0, count: longest + 1)
        for lag in shortest...longest {
            let ratio = log(Double(lag) / period)
            penalty[lag] = Float(-60 * ratio * ratio)
        }
        var score = [Float](repeating: 0, count: n)
        var previous = [Int32](repeating: -1, count: n)
        for t in 0..<n {
            var best: Float = 0
            var from: Int32 = -1
            if t >= shortest {
                for lag in shortest...min(longest, t) {
                    let candidate = score[t - lag] + penalty[lag]
                    if candidate > best || from < 0 {
                        best = candidate
                        from = Int32(t - lag)
                    }
                }
            }
            score[t] = onset[t] / scale + (best > 0 ? best : 0)
            previous[t] = best > 0 ? from : -1
        }
        // Finish on the best beat in the last two beat-lengths of the track.
        var t = (max(0, n - Int(period * 2))..<n).max { score[$0] < score[$1] } ?? n - 1
        var chain: [Int] = []
        while t >= 0 {
            chain.append(t)
            t = Int(previous[t])
        }
        return chain.reversed()
    }

    private static func fitLine(_ points: [(Double, Double)]) -> (intercept: Double, slope: Double) {
        let n = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.0 } / n, meanY = points.reduce(0) { $0 + $1.1 } / n
        var top = 0.0, bottom = 0.0
        for (x, y) in points {
            top += (x - meanX) * (y - meanY)
            bottom += (x - meanX) * (x - meanX)
        }
        let slope = bottom > 0 ? top / bottom : 0
        return (meanY - slope * meanX, slope)
    }

    /// A moving median over the confirmed beats, with straight lines across the gaps between them.
    private static func smooth(_ values: [Double], confirmed: [Int], radius: Int) -> [Double] {
        var knots: [(Int, Double)] = []
        for (position, index) in confirmed.enumerated() {
            let window = confirmed[max(0, position - radius)...min(confirmed.count - 1, position + radius)]
            let sorted = window.map { values[$0] }.sorted()
            knots.append((index, sorted[sorted.count / 2]))
        }
        var out = [Double](repeating: 0, count: values.count)
        var k = 0
        for i in values.indices {
            while k + 1 < knots.count && knots[k + 1].0 <= i { k += 1 }
            if i <= knots[0].0 {
                out[i] = knots[0].1
            } else if k + 1 < knots.count {
                let (a, va) = knots[k], (b, vb) = knots[k + 1]
                out[i] = va + (vb - va) * Double(i - a) / Double(b - a)
            } else {
                out[i] = knots[k].1
            }
        }
        return out
    }

    /// Which of the first four beats starts a bar: bars start where the biggest changes land.
    private static func strongestBarPhase(confirmed: [Int], strengths: [Float]) -> Int {
        var totals = [Float](repeating: 0, count: 4)
        for i in confirmed { totals[i % 4] += strengths[i] }
        return totals.indices.max { totals[$0] < totals[$1] } ?? 0
    }
}
