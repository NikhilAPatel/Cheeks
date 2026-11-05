import XCTest
@testable import Cheeks

final class RendererTests: XCTestCase {
    /// Left channel holds each frame's index (mod 30000), so output reveals where the playhead read.
    private func makeRenderer(frames: Int = 200_000) -> DeckRenderer {
        let renderer = DeckRenderer(sampleRate: AudioConfig.sampleRate)
        let pcm = PCM16Stereo(frames: frames)
        for i in 0..<frames { pcm.data[i * 2] = Int16(i % 30_000) }
        renderer.setSources([pcm])
        return renderer
    }

    func testPlaysForwardAtUnitRate() {
        let r = makeRenderer()
        r.playhead = 100
        r.isPlaying = true
        let out = r.renderOffline(frames: 512)
        XCTAssertEqual(r.playhead, 612, accuracy: 0.0001)
        // Past the fade-in that stops the start from clicking.
        XCTAssertEqual(out.left[300] * 32768, 400, accuracy: 0.01)
    }

    func testPausedIsSilentAndStill() {
        let r = makeRenderer()
        r.playhead = 500
        let out = r.renderOffline(frames: 256)
        XCTAssertEqual(r.playhead, 500)
        XCTAssertEqual(out.left.max(), 0)
    }

    func testLoopWrapsSampleAccurately() {
        let r = makeRenderer()
        r.loopStart = 1000
        r.loopEnd = 2000
        r.loopActive = true
        r.playhead = 1500
        r.isPlaying = true
        _ = r.renderOffline(frames: 5000)
        XCTAssertEqual(r.playhead, 1500, accuracy: 0.0001)
    }

    func testSlipResumesWhereTrackWouldHaveBeen() {
        let r = makeRenderer()
        r.playhead = 1000
        r.isPlaying = true
        r.engageSlip()
        r.loopStart = 1000
        r.loopEnd = 1500
        r.loopActive = true
        _ = r.renderOffline(frames: 4000)
        r.loopActive = false
        r.releaseSlip()
        XCTAssertEqual(r.playhead, 5000, accuracy: 0.0001)
    }

    func testScratchChasesTarget() {
        let r = makeRenderer()
        r.playhead = 10_000
        r.beginScratch()
        r.scratchTarget += 4410 // move the "record" 0.1 s forward
        _ = r.renderOffline(frames: 44_100)
        XCTAssertEqual(r.playhead, 14_410, accuracy: 1)
        r.scratchTarget -= 8820 // and back 0.2 s
        _ = r.renderOffline(frames: 44_100)
        XCTAssertEqual(r.playhead, 5590, accuracy: 1)
    }

    func testStopsAtEndOfTrack() {
        let r = makeRenderer(frames: 1000)
        r.playhead = 900
        r.isPlaying = true
        _ = r.renderOffline(frames: 512)
        XCTAssertFalse(r.isPlaying)
        XCTAssertTrue(r.reachedEnd)
    }

    func testMutedStemIsRemoved() {
        let r = DeckRenderer(sampleRate: AudioConfig.sampleRate)
        let values: [Int16] = [1000, 2000, 4000, 8000]
        let stems = values.map { v -> PCM16Stereo in
            let pcm = PCM16Stereo(frames: 50_000)
            for i in 0..<50_000 { pcm.data[i * 2] = v; pcm.data[i * 2 + 1] = v }
            return pcm
        }
        r.setSources(stems)
        r.isPlaying = true
        r.setStemGain(2, 0) // mute the 4000 stem
        let out = r.renderOffline(frames: 20_000)
        // Stems are stored with headroom, so the renderer scales them back up.
        XCTAssertEqual(out.left.last! * 32768 * PCM16Stereo.stemHeadroom, 11_000, accuracy: 1)
    }
}

@MainActor
final class DeckTests: XCTestCase {
    private func makeDeck(_ index: Int, bpm: Double, firstBeat: Double = 0, at seconds: Double) -> Deck {
        let deck = Deck(index: index)
        deck.renderer.setSources([PCM16Stereo(frames: Int(AudioConfig.sampleRate * 120))])
        deck.track = Track(id: UUID(), title: "Test", artist: "", fileName: "none", bpm: bpm, firstBeat: firstBeat)
        deck.seek(to: seconds)
        return deck
    }

    /// Pressing the range key on a deck synced beyond the new range pinned the cap, and its next touch jumped the live tempo to
    /// that range's edge: 129.53 to 159.80 BPM for a first-time user, twice.
    func testARangeTooNarrowForTheTempoIsPassedOver() {
        let deck = makeDeck(0, bpm: 170, at: 0)
        var said: (String, StatusKind)?
        deck.onMessage = { said = ($0, $1) }
        deck.setTempo(-23.8)
        XCTAssertEqual(deck.tempoRange, 100, "It widens to hold it")
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 100, "Nothing narrower can")
        XCTAssertEqual(deck.tempo, -23.8)
        XCTAssertEqual(said?.0, "Deck 1's 23.8% from its own speed, so it needs WIDE.")
        XCTAssertEqual(said?.1, .refused)
        deck.setTempo(-12)
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 16, "It goes round what fits")
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 100)
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 16, "And skips what doesn't")
        deck.setTempo(0)
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 100)
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 6, "All of them, at its own speed")
    }

    /// Left on WIDE by a sync, an 18 pt nudge on the next track was +45%.
    func testARangeWidenedForOneTrackGoesBackWhenItsOver() {
        let deck = makeDeck(0, bpm: 170, at: 0)
        XCTAssertEqual(deck.tempoRange, 10)
        deck.setTempo(-23.8)
        XCTAssertEqual(deck.tempoRange, 100)
        deck.resetTempo()
        XCTAssertEqual(deck.tempo, 0)
        XCTAssertEqual(deck.tempoRange, 10, "What was chosen")
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 16)
        deck.stepTempoRange()
        XCTAssertEqual(deck.tempoRange, 100)
        deck.resetTempo()
        XCTAssertEqual(deck.tempoRange, 100, "Someone chose WIDE, and it stays")
    }

    func testTimeLeftAllowsForTheTempo() {
        let deck = makeDeck(0, bpm: 170, at: 0)
        let whole = deck.timeLeft
        XCTAssertEqual(whole, deck.duration, accuracy: 0.01)
        deck.setTempo(-20)
        XCTAssertEqual(deck.timeLeft, whole / 0.8, accuracy: 0.01, "Slower takes longer")
        XCTAssertEqual(Format.toGo(61), "-01:01.0")
        XCTAssertEqual(Format.toGo(0), "00:00.0", "There's nothing to take away")
    }

    /// The pad lights, and nothing changes until the split's done. A first-time user thought it was broken.
    func testAStemPadSaysItsWaitingForTheSplit() {
        let deck = makeDeck(0, bpm: 124, at: 0)
        var said: String?
        deck.onMessage = { message, _ in said = message }
        deck.stemStatus = .separating(0.24)
        deck.toggleStem(.vocals)
        XCTAssertEqual(said, "That happens when the split's done. It's at 24%.")
        said = nil
        deck.toggleStem(.vocals)
        XCTAssertNil(said, "Everything's back on, and that's what's already heard")
        deck.setStems([.drums, .bass])
        XCTAssertEqual(said, "That happens when the split's done. It's at 24%.")
        said = nil
        deck.stemStatus = .ready("AI")
        deck.setStems([.drums])
        XCTAssertNil(said, "It's just happened")
    }

    func testTheFirstMemoryCueSaysItMovesWhereTheTrackLoads() {
        let deck = makeDeck(0, bpm: 124, at: 8)
        var said: String?, undo: (@MainActor () -> Void)?
        deck.offerUndo = { said = $0; undo = $2 }
        var kind: StatusKind?
        deck.offerUndo = { said = $0; kind = $1; undo = $2 }
        deck.saveMemoryCueHere()
        XCTAssertEqual(said, "Memory cue saved. The track loads here now.")
        XCTAssertEqual(kind, .done, "Good news, with no bin beside it")
        XCTAssertEqual(deck.track?.memoryCues.count, 1)
        undo?()
        XCTAssertEqual(deck.track?.memoryCues.count, 0, "And it can be taken back")
    }

    /// A deck that stopped with 0.05 to 0.1 s left read -00:00.0, in red.
    func testTimeLeftHasNoMinusWithNothingToTakeAway() {
        XCTAssertEqual(Format.toGo(0), "00:00.0")
        XCTAssertEqual(Format.toGo(0.07), "00:00.0")
        XCTAssertEqual(Format.toGo(0.1), "-00:00.1")
        XCTAssertEqual(Format.toGo(65.26), "-01:05.2")
        XCTAssertEqual(Format.toGo(.infinity), "--:--.-")
    }

    func testHalvingTheReadingSaysItIsntASpeedChange() {
        let deck = makeDeck(0, bpm: 126, at: 8)
        var said: (String, StatusKind)?
        deck.onMessage = { said = ($0, $1) }
        deck.scaleBPM(0.5)
        XCTAssertEqual(said?.0, "Deck 1's track reads 63 BPM now. Its speed hasn't changed.")
        XCTAssertEqual(deck.tempo, 0, accuracy: 0.001)
    }

    func testSyncMatchesTempoAndPhase() {
        let master = makeDeck(0, bpm: 128, firstBeat: 0.11, at: 10.3)
        let deck = makeDeck(1, bpm: 125, firstBeat: 0.42, at: 20.0)
        deck.sync(to: master)
        XCTAssertEqual(deck.effectiveBPM, 128, accuracy: 0.0001)
        XCTAssertEqual(deck.phaseOffset(to: master), 0, accuracy: 0.001)
        XCTAssertTrue(deck.syncOn)
    }

    /// Round 12: a first-time user's whole first mix was a beat out, with SYNC on and the marker green.
    func testADeckStartedWithSyncOnStartsInBar() {
        for offset in [0.0, 0.5, 1.0, 1.5, 3.2] {
            let master = makeDeck(0, bpm: 128, firstBeat: 0.11, at: 10.3)
            let deck = makeDeck(1, bpm: 125, firstBeat: 0.42, at: 20 + offset)
            deck.syncLeader = { master }
            master.play()
            deck.sync(to: master)
            deck.play()
            let theirs = master.beatPosition(master.renderer.playhead)
            let mine = deck.beatPosition(deck.renderer.playhead)
            var apart = (theirs - mine).truncatingRemainder(dividingBy: 4)
            if apart > 2 { apart -= 4 }
            if apart < -2 { apart += 4 }
            XCTAssertEqual(apart, 0, accuracy: 0.01, "Starting from \(20 + offset) s")
        }
    }

    func testADeckStartedInBarDoesntGoBackPastTheStart() {
        let master = makeDeck(0, bpm: 120, firstBeat: 0, at: 1.5)
        let deck = makeDeck(1, bpm: 120, firstBeat: 0, at: 0)
        deck.syncLeader = { master }
        master.play()
        deck.sync(to: master)
        deck.play()
        XCTAssertGreaterThanOrEqual(deck.renderer.playhead, 0)
        XCTAssertLessThan(deck.renderer.playhead / deck.sampleRate, 2.1)
    }

    func testAPlayingDeckOnlyMovesToTheNearestBeat() {
        let master = makeDeck(0, bpm: 120, firstBeat: 0, at: 10)
        let deck = makeDeck(1, bpm: 120, firstBeat: 0, at: 11)
        master.play()
        deck.play()
        deck.syncLeader = { master }
        deck.sync(to: master)
        XCTAssertEqual(deck.renderer.playhead / deck.sampleRate, 11, accuracy: 0.26, "People may be hearing it")
    }

    func testStartingWithSyncOffLeavesItWhereItIs() {
        let master = makeDeck(0, bpm: 120, firstBeat: 0, at: 10)
        let deck = makeDeck(1, bpm: 120, firstBeat: 0, at: 11)
        deck.syncLeader = { master }
        master.play()
        deck.play()
        XCTAssertEqual(deck.renderer.playhead / deck.sampleRate, 11, accuracy: 0.001)
    }

    func testStemsCountAsAlteredUntilAllAreBackAtFullLevel() {
        let deck = makeDeck(0, bpm: 128, at: 5)
        XCTAssertFalse(deck.stemsAltered)
        deck.stemsOn[1] = false
        XCTAssertTrue(deck.stemsAltered)
        deck.stemsOn[1] = true
        deck.stemLevels[2] = 0.5
        XCTAssertTrue(deck.stemsAltered)
        deck.stemLevels[2] = 1
        XCTAssertFalse(deck.stemsAltered)
    }

    func testAChannelMeterFollowsTrimButNotTheFader() throws {
        let dj = DJEngine(library: Library())
        dj.stopRealtimeForTesting()
        let deck = dj.decks[0]
        deck.renderer.setSources([PCM16Stereo(frames: 441_000)])
        deck.setAutoGainForTesting(loudness: nil)
        dj.updateVolumes()
        XCTAssertEqual(deck.channelTrim, 1, accuracy: 0.001)
        deck.trim = 0.5
        XCTAssertEqual(deck.channelTrim, pow(10, 6.0 / 20), accuracy: 0.001, "TRIM moves it: half way up is +6 dB")
        deck.trim = 0
        deck.fader = 0.2
        XCTAssertEqual(deck.channelTrim, 1, accuracy: 0.001, "The fader doesn't, as on a real mixer")
        deck.setAutoGainForTesting(loudness: Deck.targetLoudness + 3)
        dj.updateVolumes()
        XCTAssertEqual(deck.channelTrim, pow(10, -3.0 / 20), accuracy: 0.001, "A loud track's loudness matching counts")
    }

    func testSyncUsesHalfTimeWhenCloser() {
        let master = makeDeck(0, bpm: 140, at: 5)
        let deck = makeDeck(1, bpm: 72, at: 5)
        deck.sync(to: master)
        XCTAssertEqual(deck.effectiveBPM, 70, accuracy: 0.0001)
    }

    func testQuantizedLoopStartsOnBeat() {
        let deck = makeDeck(0, bpm: 120, firstBeat: 0.25, at: 10.4) // beats every 0.5 s from 0.25
        deck.setLoop(beats: 4, resizeExisting: false)
        XCTAssertEqual(deck.renderer.loopStart / deck.sampleRate, 10.25, accuracy: 0.0001)
        XCTAssertEqual(deck.renderer.loopEnd / deck.sampleRate, 12.25, accuracy: 0.0001)
        XCTAssertTrue(deck.loopActive)
    }

    func testHotCueSetsOnNearestBeatThenJumps() {
        let deck = makeDeck(0, bpm: 120, at: 30.1)
        deck.hotCue(0)
        XCTAssertEqual(deck.track?.hotCues[0] ?? -1, 30.0, accuracy: 0.0001)
        deck.seek(to: 50)
        deck.hotCue(0)
        XCTAssertEqual(deck.position, 30.0, accuracy: 0.0001)
        XCTAssertTrue(deck.isPlaying)
    }

    func testBeatJumpMovesLoopToo() {
        let deck = makeDeck(0, bpm: 120, at: 10)
        deck.setLoop(beats: 2, resizeExisting: false)
        deck.beatJump(4)
        XCTAssertEqual(deck.position, 12, accuracy: 0.0001)
        XCTAssertEqual(deck.renderer.loopStart / deck.sampleRate, 12, accuracy: 0.0001)
    }

    func testPressingPlayWhileHoldingCueKeepsPlaying() {
        let deck = makeDeck(0, bpm: 120, at: 10)
        deck.cueDown() // paused: sets the cue here and previews
        XCTAssertTrue(deck.isPlaying)
        deck.togglePlay()
        deck.cueUp()
        XCTAssertTrue(deck.isPlaying, "PLAY during a cue preview must latch playback, as on a club deck")
    }

    func testRollingTwoPadsReturnsToTheFirstPadsReturnPoint() {
        let deck = makeDeck(0, bpm: 120, at: 10)
        deck.play()
        _ = deck.renderer.renderOffline(frames: 4410)
        deck.rollBegin(0.25)
        _ = deck.renderer.renderOffline(frames: 4410)
        deck.rollBegin(0.5)
        _ = deck.renderer.renderOffline(frames: 4410)
        deck.rollEnd()
        XCTAssertTrue(deck.renderer.loopActive, "Letting go of one pad leaves the other rolling")
        _ = deck.renderer.renderOffline(frames: 4410)
        deck.rollEnd()
        _ = deck.renderer.renderOffline(frames: 512)
        // 10 s, plus everything rendered, as if the rolls had never happened.
        let expected = 10 * AudioConfig.sampleRate + 4 * 4410 + 512
        XCTAssertEqual(deck.renderer.playhead, expected, accuracy: 300)
        XCTAssertFalse(deck.renderer.loopActive)
    }

    func testGridEditing() {
        let deck = makeDeck(0, bpm: 64, firstBeat: 0.1, at: 9.0)
        deck.scaleBPM(2)
        XCTAssertEqual(deck.bpm, 128, accuracy: 0.0001)
        deck.quantize = false
        deck.setDownbeatHere()
        let bar = 4 * 60 / 128.0
        let offset = (9.0 - deck.track!.firstBeat).truncatingRemainder(dividingBy: bar)
        XCTAssertTrue(offset < 0.0001 || bar - offset < 0.0001)
    }
}
