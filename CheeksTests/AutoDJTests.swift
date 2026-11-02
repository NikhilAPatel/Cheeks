import XCTest
@testable import Cheeks

/// Auto DJ from the button to the end of the move, on synthetic stems, through the real engine rendered by hand.
@MainActor
final class AutoDJTests: XCTestCase {
    private func map(bpm: Double = 124, firstBar: Double = 0.5, bars: Int = 96) throws -> (stems: [PCM16Stereo], map: TrackMap) {
        let stems = Synth.clubStems(bpm: bpm, firstBar: firstBar, bars: bars)
        return (stems, try XCTUnwrap(TrackMapper.map(stems: stems)))
    }

    private func put(_ loaded: (stems: [PCM16Stereo], map: TrackMap), on deck: Deck, name: String, id: UUID = UUID()) {
        deck.renderer.setSources(loaded.stems)
        deck.track = Track(id: id, title: name, artist: "", fileName: "none", duration: Double(loaded.stems[0].frames) / Synth.sampleRate, bpm: loaded.map.bpm, firstBeat: loaded.map.firstBar)
        deck.trackMap = loaded.map
    }

    private func makeEngine() -> DJEngine {
        let dj = DJEngine(library: Library())
        dj.stopRealtimeForTesting()
        return dj
    }

    private func ready(bpmB: Double = 124) throws -> DJEngine {
        let dj = makeEngine()
        put(try map(), on: dj.decks[0], name: "A")
        put(try map(bpm: bpmB, firstBar: 0.2), on: dj.decks[1], name: "B")
        dj.decks[0].seek(to: dj.decks[0].trackMap!.seconds(atBar: 24) * Synth.sampleRate)
        dj.decks[0].play()
        return dj
    }

    /// Lets planning finish and runs the engine until `done`, or fails after a few minutes of audio.
    private func run(_ dj: DJEngine, until done: () -> Bool, seconds: Double = 240) async throws {
        var left = seconds
        while !done(), left > 0 {
            _ = dj.renderOffline(frames: 4410)
            dj.tickForTesting()
            left -= 0.1
            await Task.yield()
            if case .planning = dj.autoDJ.phase { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        XCTAssertTrue(done(), "Didn't get there in \(seconds) s of audio. Phase: \(dj.autoDJ.phase), said: \(dj.statusMessage ?? "nothing")")
    }

    // MARK: Saying no

    func testNeedsADeckPlaying() throws {
        let dj = makeEngine()
        put(try map(), on: dj.decks[0], name: "A")
        put(try map(), on: dj.decks[1], name: "B")
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(dj.statusKind, .refused)
    }

    func testNeedsTheOtherDeckStopped() throws {
        let dj = try ready()
        dj.decks[1].play()
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(dj.statusKind, .refused)
    }

    func testNeedsSomethingToBringIn() throws {
        let dj = makeEngine()
        put(try map(), on: dj.decks[0], name: "A")
        dj.decks[0].play()
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(dj.statusKind, .refused)
    }

    func testWaitsForStemsThatAreOnTheirWay() throws {
        let dj = try ready()
        dj.decks[1].trackMap = nil
        dj.decks[1].stemStatus = .separating(nil)
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .waitingForStems)
        dj.decks[1].stemStatus = .unavailable
        dj.autoDJ.tick()
        XCTAssertEqual(dj.autoDJ.phase, .idle, "They're not coming after all")
        XCTAssertEqual(dj.statusKind, .refused)
    }

    // MARK: The whole thing

    func testPerformsATransitionAndHandsTheDecksBackClean() async throws {
        let dj = try ready(bpmB: 120)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { if case .armed = dj.autoDJ.phase { return true } else { return false } }
        XCTAssertEqual(b.effectiveBPM, a.effectiveBPM, accuracy: 0.01, "The new track comes in at the old one's tempo")
        XCTAssertFalse(b.renderer.isPlaying, "Not until its moment")
        try await run(dj) { if case .running = dj.autoDJ.phase { return true } else { return false } }
        try await run(dj) { dj.autoDJ.phase == .idle }

        XCTAssertFalse(a.isPlaying, "The old track's stopped")
        XCTAssertTrue(b.isPlaying, "The new one's playing")
        XCTAssertEqual(dj.statusKind, .done)
        for deck in [a, b] {
            XCTAssertEqual(deck.stemLevels, [1, 1, 1, 1], "Deck \(deck.index + 1) stems")
            XCTAssertEqual(deck.stemsOn, [true, true, true, true])
            XCTAssertEqual(deck.eqLow, 0, "Deck \(deck.index + 1) EQ")
            XCTAssertEqual(deck.filter, 0, "Deck \(deck.index + 1) filter")
            XCTAssertFalse(deck.renderer.loopActive, "Deck \(deck.index + 1) loop")
            XCTAssertFalse(cheeks_deck_source_cut(deck.renderer.handle), "Deck \(deck.index + 1) isn't left cut")
        }
        XCTAssertFalse(cheeks_engine_auto_running(dj.coreForTesting))
        // And the new track is really audible afterwards.
        let out = dj.renderOffline(frames: 44_100)
        XCTAssertGreaterThan(out.left.map { abs($0) }.max() ?? 0, 0.1)
    }

    func testPressingWhileItWaitsCallsItOff() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { if case .armed = dj.autoDJ.phase { return true } else { return false } }
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting))
        XCTAssertTrue(dj.decks[0].isPlaying, "The old track just carries on")
        XCTAssertFalse(dj.decks[1].renderer.isPlaying)
    }

    func testPressingMidMoveLeavesTheDecksToYou() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { if case .running = dj.autoDJ.phase { return true } else { return false } }
        dj.autoDJ.press()
        _ = dj.renderOffline(frames: 4410)
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(cheeks_engine_auto_running(dj.coreForTesting))
    }

    func testMovingTheDeckAwayCallsItOff() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { if case .armed = dj.autoDJ.phase { return true } else { return false } }
        let a = dj.decks[0]
        a.seek(to: (a.track!.duration - 20) * Synth.sampleRate)
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 3)
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting))
    }

    func testLoadingAnotherTrackCallsItOff() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { if case .armed = dj.autoDJ.phase { return true } else { return false } }
        put(try map(bpm: 118, firstBar: 0.3), on: dj.decks[1], name: "C")
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting), "Nothing should start the new track at the old plan's place")
    }

    func testStartingTheWaitingDeckCallsItOff() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { if case .armed = dj.autoDJ.phase { return true } else { return false } }
        dj.decks[1].play()
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting))
        XCTAssertTrue(dj.decks[1].isPlaying, "It's theirs now")
    }

    func testTouchingAKnobTakesItBack() {
        let dj = makeEngine()
        var steps = [CheeksAutoStep()]
        steps[0].kind = Int32(CheeksAutoEQ.rawValue)
        steps[0].deck = 0
        steps[0].endBeat = 100
        steps[0].from = 1
        steps[0].to = 0
        XCTAssertTrue(cheeks_engine_auto_load(dj.coreForTesting, &steps, 1, 22_050, 100))
        cheeks_engine_auto_start(dj.coreForTesting, 0)
        _ = dj.renderOffline(frames: 44_100)
        let moved = cheeks_engine_auto_value(dj.coreForTesting, 0, Int32(CheeksAutoEQ.rawValue), 0)
        XCTAssertLessThan(moved, 1, "The score's moving it")
        dj.decks[0].followAuto(CheeksAutoEQ, index: 0, value: moved)
        _ = dj.renderOffline(frames: 4410)
        XCTAssertLessThan(cheeks_engine_auto_value(dj.coreForTesting, 0, Int32(CheeksAutoEQ.rawValue), 0), moved, "Following it on screen isn't taking it")
        dj.decks[0].eqLow = 0.2
        let taken = cheeks_engine_auto_value(dj.coreForTesting, 0, Int32(CheeksAutoEQ.rawValue), 0)
        _ = dj.renderOffline(frames: 44_100)
        XCTAssertEqual(cheeks_engine_auto_value(dj.coreForTesting, 0, Int32(CheeksAutoEQ.rawValue), 0), taken, "A hand on it stops the score")
    }

    // MARK: A whole mix

    /// An engine whose decks load these tracks straight from memory, without any files.
    private func engine(loading tracks: [UUID: (stems: [PCM16Stereo], map: TrackMap)]) -> DJEngine {
        let dj = makeEngine()
        dj.autoDJ.loadTrack = { [unowned self] id, deck in
            guard let loaded = tracks[id] else { return nil }
            self.put(loaded, on: deck, name: "\(id)", id: id)
            return "\(id)"
        }
        return dj
    }

    func testMixesThroughAListAndStopsAtTheEnd() async throws {
        let ids = [UUID(), UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map(bpm: 122, firstBar: 0.2), ids[2]: try map(bpm: 125, firstBar: 0.3)])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        XCTAssertEqual(dj.decks[0].track?.id, ids[0], "It starts from the top")
        try await run(dj, until: { dj.decks[0].isPlaying && dj.decks[1].track?.id == ids[1] }, seconds: 5)
        XCTAssertTrue(dj.autoDJ.legend.hasPrefix("MIX"))

        try await run(dj, until: { if case .armed = dj.autoDJ.phase { return true } else { return false } }, seconds: 30)
        let map = try XCTUnwrap(dj.decks[0].trackMap)
        let exit = try XCTUnwrap(cheeks_engine_auto_armed(dj.coreForTesting) ? dj.decks[0].position : nil)
        XCTAssertLessThan(exit, map.seconds(atBar: TransitionPlanner.setExit(in: map)), "It hasn't left yet")
        XCTAssertFalse(dj.decks[1].renderer.isPlaying)

        // First move, then the third track arrives on the deck that's just been freed.
        try await run(dj, until: { dj.decks[1].isPlaying && !dj.decks[0].isPlaying && dj.decks[0].track?.id == ids[2] }, seconds: 400)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 1)
        // Second move, leaving nothing in the queue.
        try await run(dj, until: { dj.decks[0].isPlaying && !dj.decks[1].isPlaying }, seconds: 400)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 0)
        XCTAssertEqual(dj.autoDJ.mixSet?.queue, [])
        // And the last track plays out.
        try await run(dj, until: { dj.autoDJ.mixSet == nil }, seconds: 400)
        XCTAssertEqual(dj.statusKind, .done)
        XCTAssertFalse(dj.autoDJ.isActive)
    }

    func testAMixMindsLandingLateInTheNextTrack() {
        func cost(entry: Int, move: TransitionMove = .echoDrop, swap: Int = 16) -> Double {
            TransitionChoice.lateLanding(TransitionPlan(move: move, exit: 40, entry: entry, swap: swap, score: 1), barsInNext: 100)
        }
        XCTAssertEqual(cost(entry: 8), 0, "Early on, it doesn't matter")
        XCTAssertEqual(cost(entry: 40), 0)
        XCTAssertEqual(cost(entry: 64), 1.44, accuracy: 0.001)
        XCTAssertGreaterThan(cost(entry: 80), cost(entry: 64))
        // It goes by when the new track takes over, which for a blend is after the overlap.
        XCTAssertEqual(cost(entry: 32, move: .bassSwap, swap: 16), 0.96, accuracy: 0.001)
    }

    func testAMixCarriesOnFromWhatsPlaying() throws {
        let ids = [UUID(), UUID(), UUID()]
        let dj = engine(loading: [ids[1]: try map(), ids[2]: try map()])
        put(try map(), on: dj.decks[1], name: "Playing", id: ids[0])
        dj.decks[1].play()
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 1)
        XCTAssertEqual(dj.autoDJ.mixSet?.queue, [ids[1], ids[2]], "What's playing isn't played again")
        dj.autoDJ.tick()
        XCTAssertEqual(dj.decks[0].track?.id, ids[1])
    }

    func testAMixNeedsSomethingToMixInto() throws {
        let dj = engine(loading: [:])
        dj.autoDJ.startSet(named: "Tonight", tracks: [UUID()])
        XCTAssertNil(dj.autoDJ.mixSet)
        XCTAssertEqual(dj.statusKind, .refused)

        let id = UUID()
        put(try map(), on: dj.decks[0], name: "Playing", id: id)
        dj.decks[0].play()
        dj.autoDJ.startSet(named: "Tonight", tracks: [id])
        XCTAssertNil(dj.autoDJ.mixSet, "It's the last one on the list")
        XCTAssertEqual(dj.statusKind, .refused)
    }

    func testPressingTheKeyStopsAMix() async throws {
        let ids = [UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map()])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { if case .armed = dj.autoDJ.phase { return true } else { return false } }, seconds: 30)
        dj.autoDJ.press()
        XCTAssertNil(dj.autoDJ.mixSet)
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting))
        XCTAssertTrue(dj.decks[0].isPlaying, "The track playing just carries on")
    }

    func testLoadingSomethingElseStopsAMix() async throws {
        let ids = [UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map()])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { if case .armed = dj.autoDJ.phase { return true } else { return false } }, seconds: 30)
        put(try map(bpm: 118, firstBar: 0.3), on: dj.decks[1], name: "Mine")
        dj.tickForTesting()
        XCTAssertNil(dj.autoDJ.mixSet)
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting))
    }

    func testStoppingTheDeckStopsAMix() async throws {
        let ids = [UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map()])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { dj.decks[1].track?.id == ids[1] }, seconds: 5)
        dj.decks[1].trackMap = nil
        dj.decks[1].stemStatus = .tooLong
        dj.autoDJ.stopForTesting()
        dj.decks[0].pause()
        dj.tickForTesting()
        XCTAssertNil(dj.autoDJ.mixSet)
        XCTAssertNotEqual(dj.statusKind, .done)
    }

    /// With no map there's nothing to plan from, but the music still mustn't stop.
    func testTheNextTrackStartsWhenTheLastRunsOutWithoutAWayIn() async throws {
        let ids = [UUID(), UUID()]
        var dj: DJEngine!
        let first = try map(bars: 40), second = try map()
        dj = engine(loading: [ids[0]: first, ids[1]: second])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { dj.decks[1].track?.id == ids[1] }, seconds: 5)
        dj.autoDJ.stopForTesting()
        dj.decks[1].trackMap = nil
        dj.decks[1].stemStatus = .tooLong
        dj.decks[0].seek(to: (dj.decks[0].track!.duration - 2) * Synth.sampleRate)
        try await run(dj, until: { dj.decks[1].isPlaying }, seconds: 20)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 1)
        XCTAssertEqual(dj.statusKind, .info)
    }

    // MARK: Plans

    func testASetLeavesLateAndAButtonLeavesSoon() throws {
        let track = try map(bars: 120).map
        let exit = TransitionPlanner.setExit(in: track)
        XCTAssertGreaterThan(exit, 120 / 2, "A track gets its time in a set")
        XCTAssertLessThan(exit + 16, 120, "With room left for a move")
    }

    func testAKeyShiftMovesTheNotesAPlanHears() throws {
        var track = try map().map
        var note = [Float](repeating: 0, count: 12)
        note[3] = 1
        track.harmony = [note]
        track.vocalNotes = [note]
        XCTAssertEqual(track.heard(shiftedBy: 2).harmony[0][5], 1)
        XCTAssertEqual(track.heard(shiftedBy: -1).vocalNotes[0][2], 1)
        XCTAssertEqual(track.heard(shiftedBy: 0).harmony[0][3], 1)
    }

    /// The bass swap's moment: everything stops for a beat, and the new track lands whole.
    func testABassSwapBreathesBeforeItLands() throws {
        let a = try map(), b = try map(firstBar: 0.1)
        let plan = TransitionPlan(move: .bassSwap, exit: 32, entry: 16, swap: 16, score: 1)
        let score = TransitionScore(plan: plan, a: .init(deck: 0, map: a.map, rate: 1, lag: 0), b: .init(deck: 1, map: b.map, rate: 1, lag: 0))
        var out: [Float] = []
        let review = try XCTUnwrap(TransitionAudition.review(score, stemsA: a.stems, stemsB: b.stems, levelA: 0.7, levelB: 0.7, listen: { left, _ in out += left }))
        func level(_ beat: Double) -> Float {
            // Beat 0 of the score comes four bars into the render, and the score's own start is on top of that.
            let from = Int((16 + beat) * score.framesPerBeat), to = from + Int(score.framesPerBeat)
            let part = out[from..<min(out.count, to)]
            return (part.reduce(0) { $0 + $1 * $1 } / Float(max(part.count, 1))).squareRoot()
        }
        let swapAt = score.start + 64
        let air = level(swapAt - 1), landing = level(swapAt)
        XCTAssertGreaterThan(landing, 0.03, "The new track's there")
        XCTAssertLessThan(air, landing * 0.4, "Air \(20 * log10(air / landing)) dB against the landing")
        XCTAssertFalse(review.problems.contains("hole in the middle"), "A breath isn't a hole")
    }

    func testEveryMoveStaysInRange() throws {
        let a = try map(), b = try map(bpm: 122, firstBar: 0.1)
        let plans = TransitionPlanner.plans(from: a.map, to: b.map, playingBPM: 124, earliest: 16)
        XCTAssertFalse(plans.isEmpty)
        for plan in plans {
            XCTAssertGreaterThanOrEqual(plan.exit, 16, "Nothing starts before it can")
            XCTAssertLessThanOrEqual(abs(plan.shift), 1, "DJs rarely shift a track further")
            XCTAssertTrue(plan.exit < a.map.barCount && plan.entry < b.map.barCount)
        }
    }

    func testTooFarApartOnlyCuts() throws {
        let a = try map(), b = try map(bpm: 150, firstBar: 0.1)
        let plans = TransitionPlanner.plans(from: a.map, to: b.map, playingBPM: 124, earliest: 16)
        XCTAssertTrue(plans.allSatisfy { [.loopDrop, .echoDrop, .brakeDrop].contains($0.move) }, "A \(plans.first?.move.title ?? "") would overlap two tempos")
    }

    func testAgreementReadsLikeMusic() {
        var chord = [Float](repeating: 0, count: 12)
        for note in [0, 3, 7] { chord[note] = 1 }
        XCTAssertGreaterThan(TransitionPlanner.consonance(chord, chord), 0.9)
        XCTAssertLessThan(TransitionPlanner.consonance(chord, chord, shift: 1), -0.5, "A semitone apart clashes")
        XCTAssertEqual(TransitionPlanner.consonance(chord, [Float](repeating: 1, count: 12)), 0, accuracy: 0.01, "Nothing to agree with")
    }

    /// A drop's first kick has to arrive whole, on a stretched deck too. Stems go in ahead of the stretcher, and this
    /// used to lose the first kick altogether, 60 dB down.
    func testADropsFirstKickArrivesOnAStretchedDeck() throws {
        let a = try map(), b = try map(bpm: 120, firstBar: 0.1)
        let plan = TransitionPlan(move: .echoDrop, exit: 32, entry: 16, score: 1)
        let rate = 124.0 / 120
        let deckA = DeckRenderer(sampleRate: Synth.sampleRate), deckB = DeckRenderer(sampleRate: Synth.sampleRate)
        deckA.setSources(a.stems)
        deckB.setSources(b.stems)
        var handles: [OpaquePointer?] = [deckA.handle, deckB.handle]
        let core = try XCTUnwrap(handles.withUnsafeMutableBufferPointer { cheeks_engine_create(Synth.sampleRate, $0.baseAddress, 2) })
        defer { cheeks_engine_destroy(core) }
        cheeks_engine_set_channel(core, 0, 0, 1, 0)
        cheeks_engine_set_channel(core, 1, 1, 1, 0)
        cheeks_deck_set_tempo(deckB.handle, rate, true, 0)
        let score = TransitionScore(plan: plan, a: .init(deck: 0, map: a.map, rate: 1, lag: 0),
                                    b: .init(deck: 1, map: b.map, rate: rate, lag: cheeks_deck_stem_lag(deckB.handle, rate)))
        let steps = score.steps
        XCTAssertTrue(steps.withUnsafeBufferPointer { cheeks_engine_auto_load(core, $0.baseAddress, Int32($0.count), score.framesPerBeat, score.length) })
        cheeks_deck_seek(deckA.handle, score.armFrame)
        cheeks_deck_set_playing(deckA.handle, true)
        cheeks_engine_auto_start(core, 0)
        let blocks = Int((score.start + 8) * score.framesPerBeat) / 256
        var out: [Float] = []
        var left = [Float](repeating: 0, count: 256), right = left
        for _ in 0..<blocks {
            left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in cheeks_engine_render(core, l.baseAddress!, r.baseAddress!, 256) } }
            out += left
        }
        func kick(_ beat: Double) -> Float {
            let from = Int((score.start + beat) * score.framesPerBeat) - 200, to = from + Int(0.25 * score.framesPerBeat)
            return out[from..<to].map { abs($0) }.max() ?? 0
        }
        let first = kick(0), later = kick(4)
        XCTAssertGreaterThan(later, 0.05, "The new track's playing")
        XCTAssertGreaterThan(first, later * 0.7, "First kick \(20 * log10(first / later)) dB against a later one")
    }
}
