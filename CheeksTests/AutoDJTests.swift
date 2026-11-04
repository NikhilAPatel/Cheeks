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

    private func ready(bpmB: Double = 124, only move: TransitionMove? = nil) throws -> DJEngine {
        let dj = makeEngine()
        if let move { dj.autoDJ.leavesOut = Set(TransitionMove.allCases).subtracting([move]) }
        put(try map(), on: dj.decks[0], name: "A")
        put(try map(bpm: bpmB, firstBar: 0.2), on: dj.decks[1], name: "B")
        dj.decks[0].seek(to: dj.decks[0].trackMap!.seconds(atBar: 24))
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
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(cheeks_engine_auto_running(dj.coreForTesting))
    }

    func testMovingTheDeckAwayCallsItOff() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { if case .armed = dj.autoDJ.phase { return true } else { return false } }
        let a = dj.decks[0]
        a.seek(to: a.track!.duration - 20)
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

    // MARK: Either way round

    /// The score names real decks, so the audition has to have each track on that deck to hear what'll happen.
    func testAnAuditionHearsTheSameFromEitherDeck() throws {
        let a = try map(), b = try map(bpm: 122, firstBar: 0.2)
        let plans = TransitionPlanner.plans(from: a.map, to: b.map, playingBPM: 124, earliest: 16)
        let rate = 124.0 / b.map.bpm
        for move in [TransitionMove.loopDrop, .bassSwap, .echoDrop] {
            let plan = try XCTUnwrap(plans.first { $0.move == move }, "\(move)")
            func heard(_ deckA: Int32, _ deckB: Int32) throws -> (review: TransitionAudition.Review, peaks: [Float]) {
                let score = TransitionScore(plan: plan, a: .init(deck: deckA, map: a.map, rate: 1, lag: 0), b: .init(deck: deckB, map: b.map, rate: rate, lag: 0))
                var peaks: [Float] = []
                let review = TransitionAudition.review(score, stemsA: a.stems, stemsB: b.stems, levelA: 0.7, levelB: 0.7, listen: { left, _ in
                    peaks.append(left.reduce(0) { max($0, abs($1)) })
                })
                return (try XCTUnwrap(review), peaks)
            }
            let fromOne = try heard(0, 1), fromTwo = try heard(1, 0)
            XCTAssertEqual(fromOne.review.problems, fromTwo.review.problems, "\(move)")
            XCTAssertEqual(fromOne.review.change, fromTwo.review.change, accuracy: 0.1, "\(move)")
            XCTAssertEqual(fromOne.peaks.count, fromTwo.peaks.count)
            let worst = zip(fromOne.peaks, fromTwo.peaks).map { abs($0 - $1) }.max() ?? 1
            XCTAssertLessThan(worst, 0.05, "\(move) sounds different from the other deck")
        }
    }

    func testAMoveFromDeckTwoEndsRight() async throws {
        let dj = makeEngine()
        let a = dj.decks[1], b = dj.decks[0]
        put(try map(), on: a, name: "A")
        put(try map(bpm: 120, firstBar: 0.2), on: b, name: "B")
        a.seek(to: a.trackMap!.seconds(atBar: 24))
        a.play()
        dj.autoDJ.press()
        try await run(dj) { dj.autoDJ.isActive && dj.autoDJ.phase != .planning && dj.autoDJ.phase != .waitingForStems }
        XCTAssertNotEqual(dj.autoDJ.phase, .idle, "It found a way: \(dj.statusMessage ?? "")")
        try await run(dj) { if case .running = dj.autoDJ.phase { return true } else { return false } }
        try await run(dj) { dj.autoDJ.phase == .idle }
        XCTAssertFalse(a.isPlaying, "The old track's stopped")
        XCTAssertTrue(b.isPlaying, "The new one's playing")
        XCTAssertEqual(dj.statusKind, .done)
        XCTAssertEqual(b.stemLevels, [1, 1, 1, 1])
        let out = dj.renderOffline(frames: 44_100)
        XCTAssertGreaterThan(out.left.map { abs($0) }.max() ?? 0, 0.1)
    }

    // MARK: When nothing else will do

    func testWithNothingElseItEchoesOutToWhereTheBeatComesIn() throws {
        let a = try map(), b = try map(bpm: 122, firstBar: 0.2)
        var choice = TransitionChoice(mapA: a.map, mapB: b.map, stemsA: a.stems, stemsB: b.stems, levelA: 0.7, levelB: 0.7, earliest: 32,
                                      avoid: Set(TransitionMove.allCases))
        XCTAssertNil(choice.choose(), "It doesn't settle unless it's told to")
        choice.fallsBackToEchoOut = true
        let score = try XCTUnwrap(choice.choose())
        XCTAssertEqual(score.plan.move, .echoDrop)
        XCTAssertLessThan(score.plan.entry, b.map.barCount / 3, "Near the top")
        XCTAssertTrue(b.map.hasKick[score.plan.entry], "With a beat")
        XCTAssertEqual(score.b.rate, 1, "At its own tempo, as nothing overlaps")
        XCTAssertGreaterThanOrEqual(score.plan.exit, 32)
    }

    func testPressingAutoWithNoGoodPlanStillMixes() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.leavesOut = Set(TransitionMove.allCases)
        dj.autoDJ.press()
        try await run(dj) { self.isArmed(dj) }
        XCTAssertEqual(dj.autoDJ.phase, .armed(.echoDrop))
        try await run(dj) { b.renderer.isPlaying }
        XCTAssertLessThan(b.position, b.trackMap!.seconds(atBar: b.trackMap!.barCount / 3), "Near the top of the track")
        try await run(dj) { dj.autoDJ.phase == .idle }
        XCTAssertFalse(a.isPlaying)
        XCTAssertTrue(b.isPlaying)
        XCTAssertEqual(dj.statusKind, .done)
    }

    func testAMixLooksEverywhereThenEchoesOutFromWhereItWouldHaveLeft() async throws {
        let ids = [UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map(bpm: 122, firstBar: 0.2)])
        dj.autoDJ.leavesOut = Set(TransitionMove.allCases)
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { self.isArmed(dj) }, seconds: 30)
        XCTAssertEqual(dj.autoDJ.phase, .armed(.echoDrop))
        XCTAssertEqual(dj.autoDJ.mixSet?.lastResort, true)
        XCTAssertGreaterThan(dj.autoDJ.barsToGo, 16, "The track still gets its time")
        try await run(dj, until: { dj.decks[1].isPlaying && !dj.decks[0].isPlaying }, seconds: 400)
        XCTAssertEqual(dj.statusKind, .done)
        XCTAssertEqual(dj.autoDJ.mixSet?.lastResort, false, "The next pair starts afresh")
    }

    // MARK: Taking over

    private func isRunning(_ dj: DJEngine) -> Bool { if case .running = dj.autoDJ.phase { return true } else { return false } }
    private func isArmed(_ dj: DJEngine) -> Bool { if case .armed = dj.autoDJ.phase { return true } else { return false } }

    private func peak(_ dj: DJEngine, frames: Int = 44_100) -> Float {
        dj.renderOffline(frames: frames).left.map { abs($0) }.max() ?? 0
    }

    private func XCTAssertClean(_ deck: Deck, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(deck.stemLevels, [1, 1, 1, 1], "Stems", file: file, line: line)
        XCTAssertEqual(deck.stemsOn, [true, true, true, true], "Stems", file: file, line: line)
        XCTAssertEqual([deck.eqLow, deck.eqMid, deck.eqHigh], [0, 0, 0], "EQ", file: file, line: line)
        XCTAssertEqual(deck.filter, 0, "Filter", file: file, line: line)
        XCTAssertFalse(deck.renderer.loopActive, "Loop", file: file, line: line)
        XCTAssertFalse(cheeks_deck_source_cut(deck.renderer.handle), "Cut", file: file, line: line)
    }

    func testCallingItOffPutsTheWaitingDeckBack() async throws {
        let dj = try ready(bpmB: 120)
        let b = dj.decks[1]
        b.setTempo(1.5)
        b.keyLock = false
        b.eqHigh = -0.3
        b.filter = 0.2
        b.fader = 0.3
        dj.crossfader = -0.5
        dj.colorFX = .dubEcho
        dj.autoDJ.press()
        try await run(dj) { self.isArmed(dj) }
        XCTAssertNotEqual(b.tempo, 1.5, "It's ready for the move")
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(b.tempo, 1.5)
        XCTAssertFalse(b.keyLock)
        XCTAssertEqual(b.eqHigh, -0.3)
        XCTAssertEqual(b.filter, 0.2)
        XCTAssertEqual(b.fader, 0.3)
        XCTAssertEqual(dj.crossfader, -0.5)
        XCTAssertEqual(b.colorFX, .dubEcho)
        XCTAssertEqual(dj.decks[0].colorFX, .dubEcho)
    }

    func testAChangeDuringTheCountdownSurvivesCallingItOff() async throws {
        let dj = try ready(bpmB: 120)
        let b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isArmed(dj) }
        b.setTempoManually(3)
        b.eqMid = 0.4
        dj.autoDJ.press()
        XCTAssertEqual(b.tempo, 3, "That one's theirs")
        XCTAssertEqual(b.eqMid, 0.4, "That one's theirs")
    }

    /// The core stops reporting a control once someone's taken it, and showing the old report would take it back.
    func testAControlTakenFromTheScoreStaysWhereItsPut() async throws {
        let dj = try ready()
        let b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && b.stemLevels[Stem.drums.rawValue] == 0 }
        b.stemLevels[Stem.drums.rawValue] = 0.6
        for _ in 0..<5 {
            _ = dj.renderOffline(frames: 4410)
            dj.tickForTesting()
        }
        XCTAssertEqual(b.stemLevels[Stem.drums.rawValue], 0.6)
    }

    func testAMoveEndsWithTheOldDeckNeutralAndTheNewOneAsItsBeenSet() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) }
        a.eqHigh = -0.5
        a.eqLow = -0.5
        b.eqHigh = -0.4
        b.stemLevels[Stem.melody.rawValue] = 0.6
        try await run(dj) { dj.autoDJ.phase == .idle }
        XCTAssertEqual(dj.statusKind, .done)
        XCTAssertClean(a)
        XCTAssertEqual(b.eqHigh, -0.4, "People are hearing that one, and it's theirs")
        XCTAssertEqual(b.stemLevels[Stem.melody.rawValue], 0.6, "People are hearing that one, and it's theirs")
        XCTAssertEqual(b.stemLevels[Stem.vocals.rawValue], 1, "What nobody touched comes back")
    }

    /// Nobody's heard the new deck yet, so it needn't be left quiet, or at the plan's tempo.
    func testStoppingBeforeTheNewDeckStartsLeavesItReady() async throws {
        let dj = try ready(bpmB: 120, only: .loopDrop)
        let a = dj.decks[0], b = dj.decks[1]
        b.setTempo(1.5)
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) }
        _ = dj.renderOffline(frames: 4410)
        dj.tickForTesting()
        XCTAssertFalse(b.renderer.isPlaying)
        dj.autoDJ.press()
        _ = dj.renderOffline(frames: 4410)
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertTrue(a.isPlaying, "The old track's carrying on")
        XCTAssertEqual(b.stemLevels, [1, 1, 1, 1])
        XCTAssertEqual(b.tempo, 1.5)
        b.play()
        XCTAssertGreaterThan(peak(dj), 0.1)
    }

    /// With the new deck playing and quiet, its stems are down and can be seen to be, and it's easy to bring them back.
    func testStoppingPartWayLeavesTheStemsWithinReach() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { b.renderer.isPlaying }
        dj.autoDJ.press()
        _ = dj.renderOffline(frames: 4410)
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertTrue(b.isPlaying, "It's left playing")
        XCTAssertEqual(b.stemLevels, [0, 0, 0, 0], "and quiet, as it was")
        XCTAssertFalse(b.stemIsHeard(.drums), "which shows")
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped. The decks are yours.")
        a.pause()
        a.stemsOn = [false, false, false, false]
        _ = dj.renderOffline(frames: 44_100)
        XCTAssertLessThan(peak(dj, frames: 8820), 0.01, "Only the new deck's left, and it's quiet")
        b.setStems(Set(Stem.allCases))
        XCTAssertEqual(b.stemLevels, [1, 1, 1, 1])
        _ = dj.renderOffline(frames: 4410)
        XCTAssertGreaterThan(peak(dj), 0.1, "ALL brings it back")
    }

    /// The score's effects and noise aren't on the screen, so they have to go with it.
    func testStoppingLeavesNothingYouCantSee() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && cheeks_engine_auto_beat(dj.coreForTesting) > 8 + 52 }
        dj.autoDJ.press()
        _ = dj.renderOffline(frames: 4410)
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        a.stemsOn = [false, false, false, false]
        _ = dj.renderOffline(frames: 44_100 * 6)
        XCTAssertLessThan(peak(dj), 0.001, "Nothing but the stems was making a sound")
    }

    func testPressingOnceTheNewTrackIsOnJustEndsIt() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && b.stemLevels[Stem.drums.rawValue] == 0 }
        try await run(dj) { b.stemLevels[Stem.drums.rawValue] == 1 }
        dj.autoDJ.press()
        _ = dj.renderOffline(frames: 4410)
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertFalse(a.isPlaying, "It was on its way out")
        XCTAssertTrue(b.isPlaying)
        XCTAssertClean(a)
        XCTAssertClean(b)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped. Deck 2 is on.")
        XCTAssertNil(dj.rateAction, "It didn't get to the end")
    }

    func testCueOnTheNewDeckMidMoveLeavesTheOldOnePlaying() async throws {
        for move in [TransitionMove.loopDrop, .bassSwap] {
            let dj = try ready(bpmB: 120, only: move)
            let a = dj.decks[0], b = dj.decks[1]
            b.setTempo(1.5)
            dj.autoDJ.press()
            try await run(dj) { b.renderer.isPlaying }
            // Long enough for it to be the deck stopping that's noticed, and short of the handover.
            _ = dj.renderOffline(frames: 44_100)
            dj.tickForTesting()
            XCTAssertEqual(dj.autoDJ.phase, .running(move))
            b.cueDown()
            b.cueUp()
            try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 2)
            XCTAssertTrue(a.isPlaying, "\(move): the old track's still what's playing")
            XCTAssertFalse(b.isPlaying, "\(move)")
            XCTAssertNotEqual(dj.statusKind, .done, "\(move): it didn't work")
            XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 2 was stopped. Deck 1 carries on.")
            XCTAssertNil(dj.rateAction, "\(move)")
            XCTAssertClean(a)
            XCTAssertClean(b)
            XCTAssertEqual(b.tempo, 1.5, "\(move): nobody heard it, so it's as it was")
            XCTAssertGreaterThan(peak(dj), 0.1, "\(move): and it can be heard")
        }
    }

    func testStoppingTheOldDeckBringsTheNewOneInNow() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) }
        XCTAssertFalse(b.renderer.isPlaying, "It hasn't got there yet")
        a.pause()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 2)
        XCTAssertTrue(b.isPlaying)
        XCTAssertFalse(a.isPlaying)
        XCTAssertClean(a)
        XCTAssertClean(b)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 1 was stopped. Deck 2 is on.")
        XCTAssertGreaterThan(b.position, 1, "From where the plan had it coming in, not the top of the track")
        XCTAssertGreaterThan(peak(dj), 0.1, "No waiting in silence")
    }

    func testStoppingTheNewDeckOnceItsOnStopsEverything() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && b.stemLevels[Stem.drums.rawValue] == 0 }
        try await run(dj) { b.stemLevels[Stem.drums.rawValue] == 1 }
        b.pause()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 2)
        XCTAssertFalse(a.isPlaying)
        XCTAssertFalse(b.isPlaying)
        XCTAssertNotEqual(dj.statusKind, .done)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 2 was stopped. Deck 1 has stopped too.")
        XCTAssertClean(a)
        XCTAssertClean(b)
    }

    func testAutoTakesARunningLoopOff() async throws {
        let dj = try ready()
        let a = dj.decks[0]
        let frame = a.renderer.playhead
        a.renderer.setLoop(start: frame, end: frame + 2 * Synth.sampleRate, active: true)
        a.loopActive = true
        dj.autoDJ.press()
        XCTAssertFalse(a.renderer.loopActive, "It'd never get to its moment")
        try await run(dj) { self.isRunning(dj) }
    }

    func testALoopSetDuringTheCountdownCallsItOff() async throws {
        let dj = try ready()
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isArmed(dj) }
        let frame = a.renderer.playhead
        a.renderer.setLoop(start: frame, end: frame + 2 * Synth.sampleRate, active: true)
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 1 is in a loop.")
        XCTAssertFalse(cheeks_engine_auto_armed(dj.coreForTesting))
    }

    func testPressingAgainAfterStoppingStartsOverClean() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && cheeks_engine_auto_beat(dj.coreForTesting) > 8 + 50 }
        dj.autoDJ.press()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertTrue(a.renderer.loopActive, "It's left as it was")
        XCTAssertNotEqual(a.filter, 0, "It's left as it was")
        dj.autoDJ.press()
        XCTAssertFalse(a.renderer.loopActive)
        XCTAssertEqual(a.filter, 0)
        XCTAssertEqual(a.eqLow, 0)
        XCTAssertEqual(a.stemLevels, [1, 1, 1, 1])
        try await run(dj) { self.isRunning(dj) }
    }

    func testPressingAgainClearsWhatAStoppedMoveLeftOnTheNewDeckToo() async throws {
        let dj = try ready(only: .bassSwap)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        // Both playing, and the new deck's still on what the score gave it.
        try await run(dj) { self.isRunning(dj) && b.renderer.isPlaying && b.stemLevels != [1, 1, 1, 1] }
        dj.autoDJ.press()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped. The decks are yours.")
        XCTAssertNotEqual(b.stemLevels, [1, 1, 1, 1], "It's left as it was")
        a.pause()
        dj.tickForTesting()
        dj.autoDJ.press()
        XCTAssertEqual(b.stemLevels, [1, 1, 1, 1], "Otherwise it mixes out of a deck that's still on drums alone")
        XCTAssertEqual(b.eqLow, 0)
        XCTAssertEqual(b.eqMid, 0)
        XCTAssertEqual(b.eqHigh, 0)
    }

    /// Round 10: stopping a move and then the old deck left 8 s of nothing at all, with PLAY lit.
    func testStoppingTheOldDeckAfterAStoppedMoveBringsTheNewOneIn() async throws {
        let dj = try ready(only: .bassSwap)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && b.renderer.isPlaying && b.stemLevels != [1, 1, 1, 1] }
        dj.autoDJ.press()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertNotEqual(b.stemLevels, [1, 1, 1, 1], "Left as it was, while the old deck's still what people hear")
        a.pause()
        dj.tickForTesting()
        XCTAssertEqual(b.stemLevels, [1, 1, 1, 1])
        XCTAssertEqual(b.eqLow, 0)
        XCTAssertEqual(dj.statusMessage, "Deck 2 is on.")
    }

    /// Round 10: a move's tempo stayed on the old deck, and went on to the next track loaded there.
    func testTheOldDeckGoesBackToItsOwnSpeedOnceItsStopped() async throws {
        let dj = try ready(only: .echoDrop)
        let a = dj.decks[0], b = dj.decks[1]
        a.setTempo(2)
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) }
        try await run(dj) { dj.autoDJ.phase == .idle }
        XCTAssertFalse(a.isPlaying)
        XCTAssertTrue(b.isPlaying)
        XCTAssertEqual(a.tempo, 0, "Nobody chose that for what's next")
    }

    func testTheKeySaysHowFarTheStemsHaveGot() throws {
        let dj = try ready()
        dj.decks[1].trackMap = nil
        dj.decks[1].stemStatus = .separating(0.42)
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .waitingForStems)
        XCTAssertEqual(dj.autoDJ.legend, "AUTO 42%")
        dj.decks[1].stemStatus = .separating(nil)
        XCTAssertEqual(dj.autoDJ.legend, "AUTO 0%")
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.legend, "AUTO")
    }

    func testMixTellsYouToStopADeckWithoutPromisingWhatsNext() throws {
        let dj = try ready()
        dj.decks[1].play()
        dj.autoDJ.startSet(named: "All", tracks: [UUID(), UUID()])
        XCTAssertNil(dj.autoDJ.mixSet)
        XCTAssertEqual(dj.statusMessage, "A mix carries on from one playing deck. Stop the other.")
    }

    func testTheLastTrackOfAMixDoesntReadAsWaiting() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        b.track = nil
        b.trackMap = nil
        dj.autoDJ.startSet(named: "Set", tracks: [try XCTUnwrap(a.track?.id), UUID()])
        XCTAssertNotNil(dj.autoDJ.mixSet)
        for _ in 0..<3 { dj.tickForTesting() }
        XCTAssertEqual(dj.autoDJ.legend, "MIX", "Nothing's left to plan for")
        XCTAssertEqual(dj.statusMessage, "That's the last track in Set. The mix ends with it.")
    }

    func testACrossfaderAPlanMovesSaysSo() async throws {
        let dj = try ready(only: .echoDrop)
        dj.crossfader = -1
        dj.autoDJ.press()
        try await run(dj) { self.isArmed(dj) }
        XCTAssertEqual(dj.crossfader, 0)
        XCTAssertTrue(dj.statusMessage?.hasSuffix("Crossfader to the middle, to hear both.") == true, dj.statusMessage ?? "nothing")
    }

    /// Round 11: EXIT during a Loop build looked as if it had worked, and the score's next loop took the deck back with no word.
    func testLeavingTheScoresLoopHandsTheDecksBack() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && a.renderer.loopActive }
        a.exitLoop()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 1's loop was changed. The decks are yours.")
        XCTAssertTrue(a.isPlaying)
        XCTAssertFalse(a.renderer.loopActive)
        XCTAssertFalse(b.renderer.isPlaying, "Nobody's heard it")
        let there = a.position
        _ = dj.renderOffline(frames: 44_100 * 20)
        dj.tickForTesting()
        XCTAssertEqual(a.position, there + 20, accuracy: 1.5, "And nothing takes it back")
        XCTAssertFalse(a.renderer.loopActive)
    }

    func testMovingTheOldDeckDuringAMoveHandsItBack() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && a.renderer.loopActive }
        let there = a.trackMap!.seconds(atBar: 70)
        a.seek(to: there)
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 1 was moved. The decks are yours.")
        XCTAssertTrue(a.isPlaying)
        XCTAssertFalse(b.renderer.isPlaying, "Nobody's heard it")
        _ = dj.renderOffline(frames: 44_100)
        dj.tickForTesting()
        XCTAssertEqual(a.position, there + 1, accuracy: 1.5, "And nothing takes it back")
    }

    /// Round 12, on a first-time user's first press: the track ran out waiting, and left silence with the next one sitting ready.
    func testTheNextTrackStartsIfThisOneRunsOutWaitingForStems() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        b.trackMap = nil
        b.stemStatus = .separating(nil)
        b.fader = 0
        dj.crossfader = -1
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .waitingForStems)
        XCTAssertEqual(dj.statusMessage, "Auto DJ is waiting for the stems. If this track ends first, deck 2 starts.")
        a.seek(to: a.duration - 2)
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 5)
        XCTAssertFalse(a.isPlaying)
        XCTAssertTrue(b.isPlaying, "The music carries on")
        XCTAssertEqual(dj.statusMessage, "The stems didn't get there in time. Deck 2 just started.")
        XCTAssertGreaterThan(b.fader, 0.4, "And can be heard")
        XCTAssertEqual(dj.crossfader, 0)
    }

    func testStartingTheWaitingDeckYourselfCallsOffTheWait() throws {
        let dj = try ready()
        let b = dj.decks[1]
        b.trackMap = nil
        b.stemStatus = .separating(nil)
        dj.autoDJ.press()
        b.play()
        dj.autoDJ.tick()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertTrue(b.isPlaying, "It's theirs, and stems arriving won't stop it")
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: you started deck 2 yourself.")
    }

    func testTheMessageMovesOnOnceTheStemsAreReady() async throws {
        let dj = try ready()
        let b = dj.decks[1]
        let map = try XCTUnwrap(b.trackMap)
        b.trackMap = nil
        b.stemStatus = .separating(nil)
        dj.autoDJ.press()
        b.trackMap = map
        b.stemStatus = .ready("AI")
        dj.autoDJ.tick()
        XCTAssertEqual(dj.autoDJ.phase, .planning)
        XCTAssertEqual(dj.autoDJ.legend, "AUTO…")
        XCTAssertEqual(dj.statusMessage, "The stems are ready. Auto DJ is choosing a move.")
    }

    /// Too near the end for a move, and it's said so. Before, that was the last anyone heard of it.
    func testWithNoWayInTheNextTrackStartsAtTheEnd() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        a.seek(to: a.duration - 6)
        dj.autoDJ.press()
        try await run(dj, until: { dj.autoDJ.phase == .waitingForTheEnd || dj.autoDJ.phase == .idle }, seconds: 3)
        XCTAssertEqual(dj.statusMessage, "No clean way in from here. Deck 2 starts when this one ends.")
        XCTAssertTrue(dj.autoDJ.isActive, "The key stays lit, as there's something still to come")
        XCTAssertEqual(dj.autoDJ.legend, "AUTO…")
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 8)
        XCTAssertTrue(b.isPlaying)
        XCTAssertEqual(dj.statusMessage, "No clean way in. Deck 2 just started.")
    }

    func testWithNoWayInTheKeyStillCallsItOff() async throws {
        let dj = try ready()
        let a = dj.decks[0], b = dj.decks[1]
        a.seek(to: a.duration - 6)
        dj.autoDJ.press()
        try await run(dj, until: { dj.autoDJ.phase == .waitingForTheEnd || dj.autoDJ.phase == .idle }, seconds: 3)
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        _ = dj.renderOffline(frames: 44_100 * 8)
        dj.tickForTesting()
        XCTAssertFalse(b.isPlaying)
    }

    /// Round 12: "starting" came with the key still reading 3, as one went by the clock and the other by the move.
    func testTheKeyCountsDownToTheMoveAndThenSaysItsStarting() async throws {
        let dj = try ready(only: .loopDrop)
        let auto: AutoDJ = dj.autoDJ
        auto.press()
        try await run(dj) { self.isRunning(dj) }
        XCTAssertEqual(auto.legend, "AUTO \(TransitionScore.leadBars)", "The clock's running, and the move's still to come")
        XCTAssertFalse(dj.statusMessage?.contains("starting") == true, "\(dj.statusMessage ?? "")")
        try await run(dj, until: { auto.barsToGo == 0 }, seconds: 10)
        XCTAssertEqual(auto.legend, "AUTO")
        XCTAssertEqual(dj.statusMessage, "Loop build starting. Touch a control to take it back.")
    }

    /// RELOOP took a deck back a minute and a half, to a loop nobody set.
    func testAStoppedLoopBuildLeavesNoLoopToGoBackTo() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && a.renderer.loopActive }
        a.exitLoop()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        let there = a.position
        a.reloop()
        XCTAssertEqual(a.position, there, accuracy: 1, "It stays where it is")
        XCTAssertFalse(a.renderer.loopActive)
        XCTAssertEqual(dj.statusMessage, "There's no loop to go back to yet. Press a loop size, or IN and OUT.")
    }

    func testALoopSomeoneStaysInIsStillTheirs() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && a.renderer.loopActive }
        a.setLoop(beats: 8)
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertTrue(a.renderer.loopActive)
        XCTAssertGreaterThan(a.renderer.loopEnd, a.renderer.loopStart)
    }

    func testAFinishedLoopBuildLeavesNoLoopBehind() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && a.renderer.loopActive }
        try await run(dj, until: { dj.autoDJ.phase == .idle })
        XCTAssertEqual(a.renderer.loopEnd, a.renderer.loopStart, "Nobody set that")
    }

    func testRunningOutWhileWaitingForStemsSaysSo() throws {
        let dj = try ready()
        dj.decks[1].trackMap = nil
        dj.decks[1].stemStatus = .separating(nil)
        dj.autoDJ.press()
        XCTAssertEqual(dj.autoDJ.phase, .waitingForStems)
        dj.decks[0].pause()
        dj.autoDJ.tick()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 1 stopped before the stems were ready.")
    }

    func testPausingDuringTheCountdownSaysThat() async throws {
        let dj = try ready()
        dj.autoDJ.press()
        try await run(dj) { self.isArmed(dj) }
        dj.decks[0].pause()
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: deck 1 was stopped.")
    }

    func testLoadingTheNewDeckMidMoveLeavesTheOldOnePlayingClean() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0], b = dj.decks[1]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) && cheeks_engine_auto_beat(dj.coreForTesting) > 8 + 50 }
        XCTAssertTrue(a.renderer.loopActive)
        put(try map(bpm: 118, firstBar: 0.3), on: b, name: "C")
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertTrue(a.isPlaying)
        XCTAssertClean(a)
        XCTAssertEqual(dj.statusMessage, "Auto DJ stopped: the track changed. Deck 1 carries on.")
    }

    func testAnOldDecksReverseGoesWhenItStops() async throws {
        let dj = try ready(only: .loopDrop)
        let a = dj.decks[0]
        dj.autoDJ.press()
        try await run(dj) { self.isRunning(dj) }
        a.reverse = true
        try await run(dj) { dj.autoDJ.phase == .idle }
        XCTAssertFalse(a.reverse)
    }

    func testStemsThatAreAllTheWayDownComeBackWhenAskedFor() throws {
        let dj = makeEngine()
        let deck = dj.decks[0]
        put(try map(), on: deck, name: "A")
        deck.stemLevels = [0, 0, 0.5, 0]
        deck.toggleStem(.vocals)
        XCTAssertEqual(deck.stemLevels[Stem.vocals.rawValue], 1, "A tap brings it back")
        XCTAssertTrue(deck.stemIsHeard(.vocals))
        deck.toggleStem(.vocals)
        XCTAssertFalse(deck.stemIsHeard(.vocals), "And mutes it again")
        XCTAssertEqual(deck.stemLevels[Stem.vocals.rawValue], 1, "At the level it had")
        deck.toggleStem(Stem.allCases[2])
        XCTAssertEqual(deck.stemLevels[2], 0.5, "One that's only part way down keeps its level")
        XCTAssertFalse(deck.stemsOn[2], "And mutes")
        deck.stemLevels = [0, 0, 0, 0]
        deck.soloStem(.drums)
        XCTAssertTrue(deck.stemIsHeard(.drums), "A solo can be heard")
        deck.setStems([.vocals, .drums])
        XCTAssertEqual(deck.stemLevels[Stem.vocals.rawValue], 1)
        XCTAssertFalse(deck.stemIsHeard(.bass))
        deck.setStems(Set(Stem.allCases))
        XCTAssertEqual(deck.stemLevels, [1, 1, 1, 1])
        XCTAssertEqual(deck.stemsOn, [true, true, true, true])
    }

    /// Two touches in one event come in no particular order, and SLIP after REV used to mean no way back.
    func testSlipPressedAfterReverseStillComesBack() throws {
        let dj = makeEngine()
        let deck = dj.decks[0]
        put(try map(), on: deck, name: "A")
        deck.seek(to: 60)
        deck.play()
        _ = dj.renderOffline(frames: 4410)
        deck.reverse = true
        deck.slipMode = true
        _ = dj.renderOffline(frames: 44_100 * 2)
        deck.reverse = false
        _ = dj.renderOffline(frames: 4410)
        XCTAssertEqual(deck.position, 62.2, accuracy: 0.1, "It should be where the track had got to")
        deck.slipMode = false
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
        XCTAssertNotNil(dj.rateAction, "Loading the next track doesn't take the question away")
        // Second move, leaving nothing in the queue.
        try await run(dj, until: { dj.decks[0].isPlaying && !dj.decks[1].isPlaying }, seconds: 400)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 0)
        XCTAssertEqual(dj.autoDJ.mixSet?.queue, [])
        // And the last track plays out.
        try await run(dj, until: { dj.autoDJ.mixSet == nil }, seconds: 400)
        XCTAssertEqual(dj.statusKind, .done)
        XCTAssertFalse(dj.autoDJ.isActive)
    }

    // MARK: Ratings

    private func temporaryRatings() -> TransitionRatings {
        TransitionRatings(url: FileManager.default.temporaryDirectory.appending(path: "ratings-\(UUID().uuidString).json"))
    }

    private func rating(_ move: TransitionMove, liked: Bool) -> TransitionRating {
        TransitionRating(move: move, from: "A", to: "B", liked: liked, at: Date())
    }

    func testAMoveAsksWhatYouThoughtAndRemembers() async throws {
        let dj = try ready(bpmB: 120)
        dj.autoDJ.ratings = temporaryRatings()
        XCTAssertNil(dj.rateAction, "Nothing to rate yet")
        dj.autoDJ.press()
        try await run(dj) { if case .running = dj.autoDJ.phase { return true } else { return false } }
        XCTAssertNil(dj.rateAction, "Not until it's over")
        try await run(dj) { dj.autoDJ.phase == .idle }
        XCTAssertEqual(dj.statusKind, .done)

        let action = try XCTUnwrap(dj.rateAction)
        action(false)
        XCTAssertEqual(dj.autoDJ.ratings.all.count, 1)
        XCTAssertEqual(dj.autoDJ.ratings.all.last?.liked, false)
        XCTAssertNil(dj.rateAction, "It's been answered")
        XCTAssertEqual(dj.statusMessage, "Got it. Less like that.")
    }

    func testAnotherMessageTakesTheRatingAway() throws {
        let dj = try ready(bpmB: 120)
        dj.say("Echo throw done. Deck 2 is on.", .done)
        dj.rateAction = { _ in }
        dj.say("Something else happened.", .info)
        XCTAssertNil(dj.rateAction)
    }

    func testRatingsAreKept() {
        let url = FileManager.default.temporaryDirectory.appending(path: "ratings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = TransitionRatings(url: url)
        first.add(rating(.loopDrop, liked: true))
        first.add(rating(.brakeDrop, liked: false))
        XCTAssertEqual(TransitionRatings(url: url).all, first.all)
    }

    func testABadRatingsFileIsNoRatings() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ratings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(TransitionRatings(url: url).all, [])
    }

    func testRatingsLeanOnAMoveWithoutDecidingIt() {
        XCTAssertEqual(TransitionRatings.taste(from: []), [:])
        func taste(_ pattern: [Bool]) -> Double {
            TransitionRatings.taste(from: pattern.map { rating(.echoDrop, liked: $0) })[.echoDrop] ?? 0
        }
        XCTAssertEqual(taste([false]), -0.2, accuracy: 0.001, "One press doesn't decide much")
        XCTAssertEqual(taste([true]), 0.2, accuracy: 0.001)
        XCTAssertEqual(taste([true, false]), 0, accuracy: 0.001)
        XCTAssertLessThan(taste(Array(repeating: false, count: 6)), taste([false]))
        XCTAssertGreaterThanOrEqual(taste(Array(repeating: false, count: 200)), -0.6)

        // A change of mind shows, because only the latest count.
        let oldThenNew = Array(repeating: false, count: 40) + Array(repeating: true, count: 20)
        XCTAssertGreaterThan(taste(oldThenNew), 0.5)

        // And one move's ratings say nothing about another's.
        XCTAssertNil(TransitionRatings.taste(from: [rating(.loopDrop, liked: false)])[.echoDrop])
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
        dj.decks[0].seek(to: dj.decks[0].track!.duration - 2)
        try await run(dj, until: { dj.decks[1].isPlaying }, seconds: 20)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 1)
        XCTAssertEqual(dj.statusKind, .info)
    }

    func testStoppingAMixMidMoveSaysSo() async throws {
        let ids = [UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map(bpm: 122, firstBar: 0.2)])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { self.isRunning(dj) }, seconds: 300)
        dj.autoDJ.press()
        try await run(dj, until: { dj.autoDJ.phase == .idle }, seconds: 1)
        XCTAssertNil(dj.autoDJ.mixSet)
        XCTAssertTrue(dj.statusMessage?.hasPrefix("Mix off.") == true, dj.statusMessage ?? "")
    }

    func testAMixWaitsForALoopSetDuringTheCountdown() async throws {
        let ids = [UUID(), UUID()]
        let dj = engine(loading: [ids[0]: try map(), ids[1]: try map(bpm: 122, firstBar: 0.2)])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { self.isArmed(dj) }, seconds: 30)
        let a = dj.decks[0], frame = a.renderer.playhead
        a.renderer.setLoop(start: frame, end: frame + 2 * Synth.sampleRate, active: true)
        a.loopActive = true
        dj.tickForTesting()
        XCTAssertEqual(dj.autoDJ.phase, .idle)
        XCTAssertNotNil(dj.autoDJ.mixSet, "Holding a track longer isn't stopping the mix")
        XCTAssertEqual(dj.statusMessage, "The mix will carry on when deck 1's loop ends.")
        for _ in 0..<20 {
            _ = dj.renderOffline(frames: 4410)
            dj.tickForTesting()
        }
        XCTAssertEqual(dj.autoDJ.phase, .idle, "It doesn't plan while it's held")
        a.exitLoop()
        try await run(dj, until: { self.isArmed(dj) }, seconds: 5)
    }

    /// A long fade into silence isn't worth waiting for, and the message saying why stays up.
    func testAMixDoesntSitThroughAFadeIntoSilence() async throws {
        let ids = [UUID(), UUID(), UUID()]
        let first = try map(bars: 40)
        let silence = Int(4 * Synth.sampleRate)
        for stem in first.stems {
            (stem.data + (stem.frames - silence) * 2).update(repeating: 0, count: silence * 2)
        }
        let dj = engine(loading: [ids[0]: first, ids[1]: try map(), ids[2]: try map(bpm: 125, firstBar: 0.3)])
        dj.autoDJ.startSet(named: "Tonight", tracks: ids)
        try await run(dj, until: { dj.decks[1].track?.id == ids[1] }, seconds: 5)
        dj.autoDJ.stopForTesting()
        let end = dj.decks[0].track!.duration
        dj.decks[0].seek(to: end - 6)
        try await run(dj, until: { dj.decks[1].isPlaying }, seconds: 5)
        XCTAssertEqual(dj.decks[0].position, end - 4, accuracy: 0.2, "It goes as soon as there's nothing left to hear")
        XCTAssertFalse(dj.decks[0].isPlaying)
        XCTAssertEqual(dj.autoDJ.mixSet?.onAir, 1)
        XCTAssertEqual(dj.statusMessage, "No clean way in. Deck 2 just started.")
        try await run(dj, until: { dj.decks[0].track?.id == ids[2] }, seconds: 2)
        for _ in 0..<5 { dj.tickForTesting() }
        XCTAssertEqual(dj.statusMessage, "No clean way in. Deck 2 just started.", "Up next doesn't cover it")
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
