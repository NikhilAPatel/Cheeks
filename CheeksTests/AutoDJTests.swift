import XCTest
@testable import Cheeks

/// Auto DJ from the button to the end of the move, on synthetic stems, through the real engine rendered by hand.
@MainActor
final class AutoDJTests: XCTestCase {
    private func map(bpm: Double = 124, firstBar: Double = 0.5, bars: Int = 96) throws -> (stems: [PCM16Stereo], map: TrackMap) {
        let stems = Synth.clubStems(bpm: bpm, firstBar: firstBar, bars: bars)
        return (stems, try XCTUnwrap(TrackMapper.map(stems: stems)))
    }

    private func put(_ loaded: (stems: [PCM16Stereo], map: TrackMap), on deck: Deck, name: String) {
        deck.renderer.setSources(loaded.stems)
        deck.track = Track(id: UUID(), title: name, artist: "", fileName: "none", duration: Double(loaded.stems[0].frames) / Synth.sampleRate, bpm: loaded.map.bpm, firstBeat: loaded.map.firstBar)
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

    // MARK: Plans

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
