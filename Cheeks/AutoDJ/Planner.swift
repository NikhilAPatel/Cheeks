import Foundation

/// The moves Auto DJ knows. Each keeps the same rules: one bassline at a time, handed over on a downbeat; one kick at
/// a time; two vocals never overlap; harmony only overlaps when the parts agree. A move that overlaps nothing works
/// between any two tracks. Tuned by ear in `tools/autodj/`, where they were written first.
enum TransitionMove: String, CaseIterable, Codable {
    case bassSwap, loopDrop, echoDrop, brakeDrop, vocalTease, acapellaRide

    var title: String {
        switch self {
        case .bassSwap: "Bass swap"
        case .loopDrop: "Loop build"
        case .echoDrop: "Echo throw"
        case .brakeDrop: "Brake drop"
        case .vocalTease: "Vocal tease"
        case .acapellaRide: "Vocal ride"
        }
    }

    /// Bars from `exit` to when the new track has taken over, and the audition checks a drop there.
    func bars(swap: Int) -> (total: Int, landing: Int?) {
        switch self {
        case .bassSwap: (swap + 16, nil)
        case .loopDrop: (16, 16)
        case .echoDrop, .brakeDrop: (0, 0)
        case .vocalTease: (8, 8)
        case .acapellaRide: (8, 0)
        }
    }
}

/// One way of doing a transition: which move, and where in each track.
struct TransitionPlan: Hashable {
    var move: TransitionMove
    /// The bar of the outgoing track the move starts from.
    var exit: Int
    /// The bar of the incoming track that lines up with `exit`. For a tease it's where the drop lands, 8 bars later.
    var entry: Int
    /// Bars of overlap before a bass swap's handover.
    var swap = 16
    /// Semitones to move the incoming track. DJs rarely go past one.
    var shift = 0
    /// Whether the two tracks' harmony can overlap.
    var harmonyAgrees = false
    var score: Double
}

/// What the planner reads off a track's map.
struct PlannerTrack {
    let map: TrackMap
    let bars: Int
    let top: Float
    let lines: [Int]

    private static let melody = Stem.melody.rawValue, bass = Stem.bass.rawValue

    init(_ map: TrackMap) {
        self.map = map
        bars = map.barCount
        let sorted = map.energy.sorted()
        top = sorted.isEmpty ? 0 : sorted[Int(Float(sorted.count - 1) * 0.9)]
        var all = Set(map.boundaries.filter { $0 >= 0 && $0 < map.barCount })
        for line in stride(from: map.lattice % 8, to: map.barCount, by: 8) { all.insert(line) }
        lines = all.sorted()
    }

    private func mean(_ values: [Bool], _ from: Int, _ to: Int) -> Double {
        let a = max(0, from), b = min(bars, to)
        guard b > a else { return 0 }
        return Double(values[a..<b].filter { $0 }.count) / Double(b - a)
    }

    func kick(_ from: Int, _ to: Int) -> Double { mean(map.hasKick, from, to) }
    func bass(_ from: Int, _ to: Int) -> Double { mean(map.on[Self.bass], from, to) }
    func melody(_ from: Int, _ to: Int) -> Double { mean(map.on[Self.melody], from, to) }

    func singing(_ from: Int, _ to: Int) -> Double {
        let a = max(0, from), b = min(bars, to)
        guard b > a else { return 0 }
        return Double(map.vocal[a..<b].reduce(0, +)) / Double(b - a)
    }

    func level(_ from: Int, _ to: Int) -> Double {
        let a = max(0, from), b = min(bars, to)
        guard b > a else { return 0 }
        return Double(map.energy[a..<b].reduce(0, +) / Float(b - a) - top)
    }

    /// How firmly a bar sits on the phrase structure: 16 bars, then 8, then a change in the music.
    func strength(_ bar: Int) -> Double {
        let offset = ((bar - map.lattice) % 16 + 16) % 16
        if offset == 0 { return 1 }
        if offset == 8 { return 0.7 }
        return map.boundaries.contains(bar) ? 0.45 : 0.25
    }

    func isFull(_ from: Int, _ to: Int) -> Bool { kick(from, to) > 0.8 && bass(from, to) > 0.6 }

    /// A drop: the full band at full size, straight after something smaller. Nothing else is worth building to, and
    /// a quiet intro after a big build is a let-down however clean the cut is.
    func dropQuality(_ bar: Int) -> Double {
        guard isFull(bar, bar + 8) else { return 0 }
        let size = max(0, min(1, (level(bar, bar + 8) + 3) / 3))
        guard size > 0, melody(bar, bar + 8) >= 0.5 else { return 0 }
        if bar < 2 { return 0.35 * size }
        let before = kick(bar - 8, bar) * 0.5 + bass(bar - 8, bar) * 0.5
        let lift = max(0, min(1, (level(bar, bar + 8) - level(bar - 8, bar)) / 6))
        return size * (0.4 + 0.3 * (1 - before) + 0.3 * lift)
    }

    /// Coming in late throws most of the track away.
    func early(_ bar: Int) -> Double { max(0, min(1, 1 - Double(bar) / (Double(bars) * 0.5))) }
}

enum TransitionPlanner {
    /// DJs stay within 5% for 86% of tracks and 10% for 94.5% (Kim et al., ISMIR 2020).
    static let maxStretch = 0.08
    /// How much agreement it takes before two parts may overlap.
    static let agreement = 0.2

    /// How well two pitch classes sit together, by interval in semitones.
    private static let intervals: [Double] = [1, -1, 0.1, 0.5, 0.5, 0.6, -0.6, 0.8, 0.5, 0.5, 0.1, -0.2]

    /// How well two pitch-class profiles agree, with y moved up `shift` semitones. Two flat profiles score 0, and a
    /// strong profile against itself scores about 1, so a score means the same on any track.
    static func consonance(_ x: [Float], _ y: [Float], shift: Int = 0) -> Double {
        func spread(_ values: [Float]) -> [Double] {
            let total = Double(values.reduce(0) { $0 + max($1, 0) }) + 1e-9
            return values.map { Double(max($0, 0)) / total - 1.0 / 12 }
        }
        let a = spread(x), b = spread((0..<12).map { y[(($0 - shift) % 12 + 12) % 12] })
        var sum = 0.0
        for i in 0..<12 { for j in 0..<12 { sum += a[i] * intervals[((j - i) % 12 + 12) % 12] * b[j] } }
        let size = (a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }).squareRoot() + 1e-9
        return sum / size / 1.9
    }

    /// Bar by bar, weighted to the bars where both parts are actually sounding.
    private static func barConsonance(_ xs: ArraySlice<[Float]>, _ ys: ArraySlice<[Float]>, shift: Int = 0) -> Double {
        var total = 0.0, weights = 0.0
        for (x, y) in zip(xs, ys) {
            let size = { (v: [Float]) in Double(v.reduce(0) { $0 + $1 * $1 }).squareRoot() }
            let weight = min(size(x), size(y)) + 1e-9
            total += consonance(x, y, shift: shift) * weight
            weights += weight
        }
        return weights > 0 ? total / weights : 0
    }

    private static func slice(_ rows: [[Float]], _ from: Int, _ to: Int) -> ArraySlice<[Float]> {
        rows[max(0, min(rows.count, from))..<max(0, min(rows.count, to))]
    }

    /// The best agreement between two parts, allowing a semitone of shift, which has to earn its artefacts.
    private static func agreementBetween(_ xs: ArraySlice<[Float]>, _ ys: ArraySlice<[Float]>) -> (value: Double, shift: Int) {
        var best = (value: barConsonance(xs, ys), shift: 0)
        for shift in [1, -1] {
            let value = barConsonance(xs, ys, shift: shift)
            if value > best.value + 0.15, value > 0.25 { best = (value, shift) }
        }
        return best
    }

    /// Every way of doing the transition that keeps the rules, best first. `earliest` is the first bar of the outgoing
    /// track the move could start on, and sooner is better, because someone just pressed a button.
    static func plans(from outgoing: TrackMap, to incoming: TrackMap, playingBPM: Double, earliest: Int) -> [TransitionPlan] {
        let a = PlannerTrack(outgoing), b = PlannerTrack(incoming)
        let stretch = abs(playingBPM / incoming.bpm - 1)
        // Outside this a move can't overlap anything, and the new track lands at its own tempo.
        let cutsOnly = stretch > maxStretch || !outgoing.isSteady || !incoming.isSteady
        var out: [TransitionPlan] = []

        func soon(_ bar: Int) -> Double { max(0, min(1, 1 - Double(bar - earliest) / 64)) }

        // Leave from a full section: leaving from a breakdown means the track was already gone.
        for exit in a.lines where exit >= earliest && a.level(exit - 8, exit) > -3 {
            let exitFit = a.strength(exit) * 0.5 + soon(exit) * 0.5
            for entry in b.lines {
                let enterFit = b.strength(entry)
                let drop = b.dropQuality(entry)

                // Moves that land on a drop don't overlap anything, so they don't ask about harmony.
                if drop > 0, entry + 32 < b.bars {
                    let full = max(0, min(1, (a.level(exit - 8, exit) + 8) / 8))
                    let common = 1.2 * exitFit + 1.5 * drop + b.early(entry) + 0.5 * enterFit + 0.6 * full - stretch * 3
                    if exit + 16 < a.bars, a.isFull(exit, exit + 4) {
                        // The owner's favourite so far, for the beat of air before the drop.
                        out.append(TransitionPlan(move: .loopDrop, exit: exit, entry: entry, score: common + 0.35))
                    }
                    if a.isFull(exit - 4, exit) {
                        out.append(TransitionPlan(move: .echoDrop, exit: exit, entry: entry, score: common + 0.05))
                        // Too jarring when there's a smoother way, so it's for tracks nothing else can join.
                        if cutsOnly { out.append(TransitionPlan(move: .brakeDrop, exit: exit, entry: entry, score: common - 0.1)) }
                    }
                }
                if cutsOnly { continue }

                // The blend: overlap, a handover on a line in both tracks, then 16 more bars.
                for swap in [16, 8] {
                    let handA = exit + swap, handB = entry + swap
                    guard handA + 16 < a.bars + 8, handB + 16 < b.bars, b.isFull(handB, handB + 8),
                          a.strength(handA) >= 0.45, b.strength(handB) >= 0.45 else { continue }
                    let first = agreementBetween(slice(outgoing.harmony, exit, handA), slice(incoming.harmony, entry, handB))
                    let second = agreementBetween(slice(outgoing.harmony, handA, handA + 8), slice(incoming.harmony, handB, handB + 8))
                    let harmony = (first.value + second.value) / 2
                    let arrives = b.strength(handB) * 0.6 + b.dropQuality(handB) * 0.4
                    let leaving = 1 - a.singing(handA, handA + 8)
                    let score = 1.2 * exitFit + arrives + b.early(entry) + 0.8 * leaving + 1.2 * harmony - stretch * 3 + (swap == 16 ? 0.1 : 0)
                    out.append(TransitionPlan(move: .bassSwap, exit: exit, entry: entry, swap: swap, shift: first.shift,
                                              harmonyAgrees: harmony > agreement, score: score))
                }

                // The tease: the new vocal over the old instrumental for 8 bars, and the new track's drop right after.
                if drop > 0, entry >= 8, b.singing(entry - 8, entry) > 0.35, exit + 8 < a.bars, a.isFull(exit, exit + 8) {
                    let fit = agreementBetween(slice(outgoing.harmony, exit, exit + 8), slice(incoming.vocalNotes, entry - 8, entry))
                    if fit.value > agreement {
                        let score = 1.2 * exitFit + 1.2 * drop + b.early(entry) + 1.5 * fit.value + 0.5 * b.singing(entry - 8, entry) + 0.3
                        out.append(TransitionPlan(move: .vocalTease, exit: exit, entry: entry, shift: fit.shift, harmonyAgrees: true, score: score))
                    }
                }

                // The ride: the old vocal over the new instrumental for 8 bars.
                if b.isFull(entry, entry + 8), exit + 8 < a.bars, a.singing(exit, exit + 8) > 0.35, b.singing(entry, entry + 8) < 0.5 {
                    let fit = agreementBetween(slice(incoming.harmony, entry, entry + 8), slice(outgoing.vocalNotes, exit, exit + 8))
                    if fit.value > agreement {
                        let score = 1.2 * exitFit + b.early(entry) + 1.5 * fit.value + 0.6 * a.singing(exit, exit + 8) + 0.6 * drop + 0.5 * enterFit + 0.3
                        // Here it's the vocal that moved to fit, so the track that actually moves goes the other way.
                        out.append(TransitionPlan(move: .acapellaRide, exit: exit, entry: entry, shift: -fit.shift, harmonyAgrees: true, score: score))
                    }
                }
            }
        }
        return out.sorted { $0.score > $1.score }
    }

    /// The best few of each move, to audition, best first overall.
    static func shortlist(_ plans: [TransitionPlan], perMove: Int = 3) -> [TransitionPlan] {
        var counts: [TransitionMove: Int] = [:]
        var seen = Set<[Int]>()
        var out: [TransitionPlan] = []
        for plan in plans {
            let key = [TransitionMove.allCases.firstIndex(of: plan.move) ?? 0, plan.exit, plan.entry, plan.swap]
            guard seen.insert(key).inserted, counts[plan.move, default: 0] < perMove else { continue }
            counts[plan.move, default: 0] += 1
            out.append(plan)
        }
        return out
    }
}
