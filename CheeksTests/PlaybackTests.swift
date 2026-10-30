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

    func testSyncMatchesTempoAndPhase() {
        let master = makeDeck(0, bpm: 128, firstBeat: 0.11, at: 10.3)
        let deck = makeDeck(1, bpm: 125, firstBeat: 0.42, at: 20.0)
        deck.sync(to: master)
        XCTAssertEqual(deck.effectiveBPM, 128, accuracy: 0.0001)
        XCTAssertEqual(deck.phaseOffset(to: master), 0, accuracy: 0.001)
        XCTAssertTrue(deck.syncOn)
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
        XCTAssertTrue(deck.isPlaying, "PLAY during a cue preview must latch playback, as on a CDJ")
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
