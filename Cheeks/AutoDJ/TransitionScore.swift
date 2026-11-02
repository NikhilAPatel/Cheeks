import Foundation

/// A transition written out as moves on the mix clock, ready for the audio core to play.
///
/// Mix beats run at the outgoing deck's playing tempo. Beat 0 is `leadBars` ahead of where the move starts, which is
/// when the core's clock starts, and it's what gives a stretched incoming deck time to settle before it's heard.
struct TransitionScore {
    /// Everything about a deck the score needs to know.
    struct Side {
        var deck: Int32
        var map: TrackMap
        /// Frames of this deck per frame of the clock.
        var rate: Double
        /// Seconds between a stem or FX change on this deck and hearing it.
        var lag: Double
        func frame(atBar bar: Int) -> Double { map.seconds(atBar: bar) * AudioConfig.sampleRate }
    }

    static let leadBars = 2
    /// Seconds for a stem's gain to be mostly open after a step.
    private static let gainOpening = 0.03

    let plan: TransitionPlan
    let a: Side, b: Side
    let framesPerBeat: Double
    private(set) var steps: [CheeksAutoStep] = []
    /// When the move starts, in mix beats.
    let start: Double
    /// When the move's over, in mix beats.
    private(set) var length: Double = 0
    /// Where a drop lands, in mix beats, for the audition to check.
    private(set) var landing: Double?
    /// The beat a deliberate breath ends on, so the audition doesn't take the bar before it for a hole.
    private(set) var breath: Double?

    init(plan: TransitionPlan, a: Side, b: Side) {
        self.plan = plan
        self.a = a
        self.b = b
        framesPerBeat = a.map.barSeconds / 4 * AudioConfig.sampleRate / max(a.rate, 0.01)
        start = Double(Self.leadBars * 4)
        write()
    }

    /// The outgoing deck's frame where the clock starts.
    var armFrame: Double { a.frame(atBar: plan.exit - Self.leadBars) }

    // MARK: Writing moves

    private static func step(_ kind: CheeksAutoKind, deck: Int32, at beat: Double) -> CheeksAutoStep {
        var s = CheeksAutoStep()
        s.startBeat = beat
        s.endBeat = beat
        s.deck = deck
        s.kind = Int32(kind.rawValue)
        s.c = 1
        return s
    }

    /// How early a change has to go in on this side to be heard on time.
    private func early(_ side: Side) -> Double { side.lag * AudioConfig.sampleRate / framesPerBeat }

    private mutating func ramp(_ kind: CheeksAutoKind, _ side: Side, _ index: Int, _ from: Double, _ to: Double, _ begin: Double, _ end: Double, curve: Int32 = 0) {
        var s = Self.step(kind, deck: side.deck, at: begin)
        s.endBeat = end
        s.index = Int32(index)
        s.from = Float(from)
        s.to = Float(to)
        s.curve = curve
        steps.append(s)
    }

    /// A stem's level over a span. These go in ahead of the stretcher, so they're sent early.
    private mutating func stem(_ side: Side, _ stem: Stem, _ from: Double, _ to: Double, _ begin: Double, _ end: Double, curve: Int32 = 0) {
        let lead = early(side)
        ramp(CheeksAutoStem, side, stem.rawValue, from, to, max(0, begin - lead), max(0, end - lead), curve: curve)
    }

    /// A stem going straight to a level on this beat. Its gain takes a moment to open, so it goes in that bit earlier.
    private mutating func stem(_ side: Side, _ stem: Stem, to value: Double, at beat: Double) {
        let at = max(0, beat - early(side) - Self.gainOpening * AudioConfig.sampleRate / framesPerBeat)
        ramp(CheeksAutoStem, side, stem.rawValue, value, value, at, at)
    }

    private mutating func low(_ side: Side, to value: Double, at beat: Double) { ramp(CheeksAutoEQ, side, 0, value, value, beat, beat) }

    private mutating func fire(_ kind: CheeksAutoKind, _ side: Side, at beat: Double, a first: Double = 0, b second: Double = 0, c third: Double = 1) {
        var s = Self.step(kind, deck: side.deck, at: beat)
        s.a = first
        s.b = second
        s.c = third
        steps.append(s)
    }

    private mutating func effect(_ side: Side, _ type: CheeksFXType, beats: Double, depth: Double, at beat: Double) {
        var s = Self.step(CheeksAutoFX, deck: side.deck, at: max(0, beat - early(side)))
        s.effect = Int32(type.rawValue)
        s.a = beats
        s.to = Float(depth)
        steps.append(s)
    }

    /// Silences the incoming deck and starts it in time, so its stretcher's settled by the time it's heard.
    private mutating func prime(entry: Int, landing beat: Double) {
        for stem in Stem.allCases { self.stem(b, stem, to: 0, at: 0) }
        // A track can't start before its first bar.
        let lead = Double(min(Self.leadBars, entry) * 4)
        fire(CheeksAutoStart, b, at: max(0, beat - lead), a: b.frame(atBar: entry), b: beat, c: b.rate)
    }

    private mutating func write() {
        switch plan.move {
        case .bassSwap: writeBassSwap()
        case .loopDrop: writeLoopDrop()
        case .echoDrop: writeEchoDrop()
        case .brakeDrop: writeBrakeDrop()
        case .vocalTease: writeVocalTease()
        case .acapellaRide: writeRide()
        }
    }

    /// The club blend, with a moment in it. The new track's hats creep in, and its melody slides under if the two agree.
    /// Then the old track rises out of its last four bars with its low end gone for the last one, everything stops for
    /// one beat, and the new track lands whole on the downbeat. Without that moment it was pleasant but plain: the owner
    /// heard "a normal crossfade", and a beat of air was what they loved about the loop build.
    private mutating func writeBassSwap() {
        let t = start, swapAt = t + Double(plan.swap * 4), air = swapAt - 1, end = swapAt + 32
        // A ramp that's still going would overrule the jump at the air, so they finish just ahead of it.
        let readyForAir = air - 0.25
        let bar = Double(plan.exit + plan.swap - 2)
        let singing = Int(bar) >= 0 && Int(bar) + 2 <= a.map.vocal.count && a.map.vocal[Int(bar)..<Int(bar) + 2].reduce(0, +) > 0.7
        breath = swapAt
        prime(entry: plan.entry, landing: t)
        low(b, to: 0, at: 0)
        stem(b, .drums, 0, 0.9, t, t + Double(plan.swap * 2), curve: 1)
        if plan.harmonyAgrees {
            stem(b, .melody, 0, 0.65, t + Double(plan.swap * 2), readyForAir, curve: 1)
            stem(a, .melody, 1, 0.75, t + Double(plan.swap * 2), readyForAir)
        }
        // The rise.
        ramp(CheeksAutoFilter, a, 0, 0, 0.25, swapAt - 16, readyForAir, curve: 1)
        ramp(CheeksAutoColor, a, Int(CheeksColorNoise.rawValue), 0, 0.4, swapAt - 16, air, curve: 1)
        low(a, to: 0, at: swapAt - 4)
        if singing { effect(a, CheeksFXEcho, beats: 0.75, depth: 0.7, at: air - 1) }
        // The air.
        for s in Stem.allCases { stem(a, s, to: 0, at: air) }
        for s in [Stem.drums, .melody] { stem(b, s, to: 0, at: air) }
        ramp(CheeksAutoColor, a, Int(CheeksColorNoise.rawValue), 0, 0, air, air)
        // The landing. A sung line has gone up the echo, and otherwise the old hats see the new track in.
        low(b, to: 1, at: swapAt)
        for s in Stem.allCases { stem(b, s, to: 1, at: swapAt) }
        if !singing { stem(a, .drums, 0.7, 0, swapAt, end, curve: 3) }
        ramp(CheeksAutoFilter, a, 0, 0.25, 0.35, swapAt, end)
        ramp(CheeksAutoLevel, a, 0, 1, 0, swapAt + 8, end)
        fire(CheeksAutoStop, a, at: end)
        length = end
    }

    /// The build. The old track folds into smaller and smaller loops while it thins and rises, breathes for one beat,
    /// and the new track's drop lands. It needs nothing to agree.
    private mutating func writeLoopDrop() {
        let t = start, bar = a.map.barSeconds * AudioConfig.sampleRate, from = a.frame(atBar: plan.exit)
        let drop = t + 64
        landing = drop
        prime(entry: plan.entry, landing: drop)
        // 4 bars as played, then the loop: 4, 2+2, 1+1, 1/2+1/2, 1/4 x 4.
        for (beat, size) in [(0.02, 4.0), (32.02, 2.0), (48.02, 1.0), (56.02, 0.5), (60.02, 0.25)] {
            fire(CheeksAutoLoop, a, at: t + beat, a: from, b: from + size * bar)
        }
        stem(a, .bass, 1, 0, t + 32, drop - 1, curve: 2)
        ramp(CheeksAutoFilter, a, 0, 0, 0.55, t + 16, drop - 1, curve: 1)
        low(a, to: 0, at: t + 48)
        effect(a, CheeksFXReverb, beats: 2, depth: 0.55, at: t + 48)
        ramp(CheeksAutoColor, a, Int(CheeksColorNoise.rawValue), 0, 0.6, t + 32, drop - 1, curve: 1)
        fire(CheeksAutoCut, a, at: max(0, drop - 1 - early(a)))
        ramp(CheeksAutoColor, a, Int(CheeksColorNoise.rawValue), 0, 0, drop - 1, drop - 1)
        for s in Stem.allCases { stem(b, s, to: 1, at: drop) }
        ramp(CheeksAutoLevel, a, 0, 1, 0, drop, drop + 16, curve: 3)
        fire(CheeksAutoStop, a, at: drop + 16)
        length = drop + 16
    }

    /// The throw. The last beats go into an echo, the track cuts, and the new one lands under the repeats.
    private mutating func writeEchoDrop() {
        let t = start
        landing = t
        prime(entry: plan.entry, landing: t)
        effect(a, CheeksFXEcho, beats: 0.75, depth: 0.8, at: t - 2)
        fire(CheeksAutoCut, a, at: max(0, t - early(a)))
        for s in Stem.allCases { stem(b, s, to: 1, at: t) }
        ramp(CheeksAutoLevel, a, 0, 1, 0, t + 8, t + 32)
        fire(CheeksAutoStop, a, at: t + 32)
        length = t + 32
    }

    /// The stop. The platter dies over a bar and the new track slams in. Tempo and key don't matter at all.
    private mutating func writeBrakeDrop() {
        let t = start
        landing = t
        prime(entry: plan.entry, landing: t)
        fire(CheeksAutoBrake, a, at: t - 4, a: 4 * framesPerBeat)
        for s in Stem.allCases { stem(b, s, to: 1, at: t) }
        fire(CheeksAutoStop, a, at: t + 4)
        length = t + 4
    }

    /// The tease. The new track's vocal rides over the old track's instrumental for a phrase, so the crowd hears what's
    /// coming before its beat arrives.
    private mutating func writeVocalTease() {
        let t = start, drop = t + 32
        landing = drop
        prime(entry: plan.entry - 8, landing: t)
        stem(a, .vocals, 1, 0, t - 2, t)
        stem(b, .vocals, 0, 1, t - 2, t + 1)
        stem(a, .bass, to: 0, at: drop - 2)
        for s in [Stem.melody, .bass, .drums] { stem(b, s, to: 1, at: drop) }
        for s in [Stem.melody, .drums] { stem(a, s, to: 0, at: drop) }
        fire(CheeksAutoStop, a, at: drop + 4)
        length = drop + 4
    }

    /// The ride. On a downbeat the whole track changes under the singer: the old vocal carries on over the new track's
    /// instrumental, then gets thrown into an echo.
    private mutating func writeRide() {
        let t = start, end = t + 32
        landing = t
        prime(entry: plan.entry, landing: t)
        stem(a, .bass, 1, 0, t - 1, t - 0.75)
        for s in [Stem.melody, .drums] { stem(a, s, to: 0, at: t) }
        for s in [Stem.melody, .bass, .drums] { stem(b, s, to: 1, at: t) }
        effect(a, CheeksFXEcho, beats: 0.75, depth: 0.8, at: end - 2)
        fire(CheeksAutoCut, a, at: max(0, end - early(a)))
        stem(b, .vocals, 0, 1, end, end + 2)
        ramp(CheeksAutoLevel, a, 0, 1, 0, end + 8, end + 24)
        fire(CheeksAutoStop, a, at: end + 24)
        length = end + 24
    }
}

/// Picks the best plan between two decks that passes its audition. Everything's copied in, as it runs off the main thread.
struct TransitionChoice {
    var mapA: TrackMap, mapB: TrackMap
    var stemsA: [PCM16Stereo], stemsB: [PCM16Stereo]
    var deckA: Int32 = 0, deckB: Int32 = 1
    var rateA = 1.0
    var levelA: Float, levelB: Float
    var lagA = 0.0, lagB = 0.0
    /// The incoming deck's stem lag when a key shift puts the stretcher in the path.
    var lagShifted = 0.0
    /// The first bar of the outgoing track a move could start on.
    var earliest: Int
    /// The moves played lately, oldest first, so the same few don't keep coming up.
    var recentMoves: [TransitionMove] = []
    /// Moves not to use. A mix has no one there to take it back, so it leaves out what's only for when nothing else will do.
    var avoid: Set<TransitionMove> = []
    /// A mix gives each track its time, so a way in that leaves little of the new track counts against itself.
    var wantsTimeOnNext = false
    /// What each move gains or loses from how it's been rated.
    var taste: [TransitionMove: Double] = [:]

    var playingBPM: Double { mapA.bpm * rateA }

    /// How much each of the last few moves counts against playing it again, most recent first.
    private static let repeatPenalty = [0.3, 0.2, 0.1, 0.1]

    /// What a plan loses for handing over late in the new track: nothing in the first 40%, then more the later it gets.
    static func lateLanding(_ plan: TransitionPlan, barsInNext: Int) -> Double {
        let handover = plan.entry + plan.move.bars(swap: plan.swap).total
        return max(0, Double(handover) / Double(max(barsInNext, 1)) - 0.4) * 6
    }

    func choose(isCancelled: () -> Bool = { false }) -> TransitionScore? {
        var penalty: [TransitionMove: Double] = [:]
        for (move, amount) in zip(recentMoves.reversed(), Self.repeatPenalty) { penalty[move, default: 0] += amount }
        let plans = TransitionPlanner.plans(from: mapA, to: mapB, playingBPM: playingBPM, earliest: earliest)
            .filter { !avoid.contains($0.move) }
            .map { plan -> TransitionPlan in
                var plan = plan
                plan.score += (taste[plan.move] ?? 0) - (penalty[plan.move] ?? 0)
                if wantsTimeOnNext { plan.score -= Self.lateLanding(plan, barsInNext: mapB.barCount) }
                return plan
            }
            .sorted { $0.score > $1.score }
        // Too far apart to stretch, so the new track lands at its own tempo.
        let ownTempo = abs(playingBPM / mapB.bpm - 1) > TransitionPlanner.maxStretch
        let rateB = ownTempo ? 1 : playingBPM / mapB.bpm
        for plan in TransitionPlanner.shortlist(plans) {
            if isCancelled() { return nil }
            let score = TransitionScore(plan: plan,
                                        a: .init(deck: deckA, map: mapA, rate: rateA, lag: lagA),
                                        b: .init(deck: deckB, map: mapB, rate: rateB, lag: plan.shift != 0 ? lagShifted : (ownTempo ? 0 : lagB)))
            if TransitionAudition.review(score, stemsA: stemsA, stemsB: stemsB, levelA: levelA, levelB: levelB, isCancelled: isCancelled)?.passes == true {
                return score
            }
        }
        return nil
    }
}

/// Plays a score offline through a private copy of the engine, faster than real time, and checks what comes out. It
/// catches let-downs and holes without anyone having to listen, so the live decks never play one. It isn't taste.
enum TransitionAudition {
    struct Review {
        var passes: Bool
        var problems: [String]
        /// New track's level against the old one's, in dB.
        var change: Double
    }

    /// Bars of the old track to measure before the move, and of the new one after it.
    private static let settleBars = 4

    /// `levelA` and `levelB` are each channel's trim and fader together, as the live mixer has them.
    static func review(_ score: TransitionScore, stemsA: [PCM16Stereo], stemsB: [PCM16Stereo], levelA: Float, levelB: Float, isCancelled: () -> Bool = { false },
                       listen: (([Float], [Float]) -> Void)? = nil) -> Review? {
        let sr = AudioConfig.sampleRate
        let a = DeckRenderer(sampleRate: sr), b = DeckRenderer(sampleRate: sr)
        a.setSources(stemsA)
        b.setSources(stemsB)
        var handles: [OpaquePointer?] = [a.handle, b.handle]
        guard let core = handles.withUnsafeMutableBufferPointer({ pointer in cheeks_engine_create(sr, pointer.baseAddress, 2) }) else { return nil }
        defer { cheeks_engine_destroy(core) }
        cheeks_engine_set_channel(core, 0, levelA, 1, 0)
        cheeks_engine_set_channel(core, 1, levelB, 1, 0)
        cheeks_engine_set_master(core, 0.9, 0.8, 1, false)
        cheeks_deck_set_tempo(a.handle, score.a.rate, true, 0)
        cheeks_deck_set_tempo(b.handle, score.b.rate, true, Int32(score.plan.shift))
        for (renderer, side) in [(a, score.a), (b, score.b)] {
            cheeks_deck_set_grid(renderer.handle, side.map.barSeconds / 4 * sr, side.map.firstBar * sr)
        }
        let steps = score.steps
        let loaded = steps.withUnsafeBufferPointer { cheeks_engine_auto_load(core, $0.baseAddress, Int32($0.count), score.framesPerBeat, score.length) }
        guard loaded else { return nil }
        // From a little ahead of the move, to hear what it's coming from.
        let before = Double(settleBars * 4)
        let barFrames = score.framesPerBeat * 4
        cheeks_deck_seek(a.handle, score.armFrame - before * score.framesPerBeat * score.a.rate)
        cheeks_deck_set_playing(a.handle, true)
        let block = 256
        let leadBlocks = Int(before * score.framesPerBeat) / block
        let total = leadBlocks + Int((score.length + Double(settleBars * 4)) * score.framesPerBeat) / block
        var left = [Float](repeating: 0, count: block), right = left
        var limiter: Float = 0
        var filter = Biquad.highpass(60, sampleRate: sr)
        var energy: [Double] = []
        var running = 0.0, inBar = 0
        for n in 0..<total {
            if n == leadBlocks { cheeks_engine_auto_start(core, 0) }
            if n % 64 == 0, isCancelled() { return nil }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in cheeks_engine_render(core, l.baseAddress!, r.baseAddress!, Int32(block)) }
            }
            limiter = max(limiter, cheeks_engine_limiter_reduction(core))
            listen?(left, right)
            for i in 0..<block {
                let y = filter.process((left[i] + right[i]) / 2)
                running += Double(y * y)
            }
            inBar += block
            if Double(inBar) >= barFrames {
                energy.append(10 * log10(running / Double(inBar) + 1e-9))
                running = 0
                inBar = 0
            }
        }
        guard energy.count > settleBars + 2 else { return nil }
        func median(_ values: ArraySlice<Double>) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        }
        let was = median(energy[..<settleBars])
        let after = median(energy[(energy.count - settleBars)...])
        let middle = energy[settleBars..<(energy.count - settleBars)]
        var problems: [String] = []
        let change = after - was
        if change < -1.5 { problems.append("new track sits low") }
        if change > 3 { problems.append("new track jumps up") }
        if (middle.max() ?? was) - was > 3 { problems.append("bump in the middle") }
        let held = score.breath.map { settleBars + Int(($0 / 4).rounded()) - 1 }
        let lowest = middle.indices.filter { $0 != held }.map { middle[$0] }.min() ?? was
        if score.landing == nil, was - lowest > 5 { problems.append("hole in the middle") }
        if let landing = score.landing {
            let bar = settleBars + Int((landing / 4).rounded())
            if bar < energy.count, median(energy[bar..<min(energy.count, bar + 4)]) - was < -1.5 { problems.append("drop lands low") }
        }
        if limiter > 3 { problems.append("limiter pushed") }
        return Review(passes: problems.isEmpty, problems: problems, change: change)
    }
}
