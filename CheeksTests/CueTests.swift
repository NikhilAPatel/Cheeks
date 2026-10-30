import XCTest
@testable import Cheeks

/// Memory cues, saved loops and hot loops on a real deck.
@MainActor
final class CueTests: XCTestCase {
    private let sr = AudioConfig.sampleRate

    private func makeDeck(at seconds: Double = 10) -> Deck {
        let deck = Deck(index: 0)
        deck.renderer.setSources([PCM16Stereo(frames: Int(sr * 120))])
        deck.track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: 120, bpm: 120, firstBeat: 0)
        deck.seek(to: seconds)
        _ = deck.renderer.renderOffline(frames: 256)
        return deck
    }

    func testSavingAMemoryCueAtTheCuePointAndCallingItBack() {
        let deck = makeDeck()
        deck.cuePoint = 10
        deck.saveMemoryCueHere()
        deck.saveMemoryCueHere()
        XCTAssertEqual(deck.track?.memoryCues.count, 1, "The same spot isn't saved twice")
        deck.seek(to: 40)
        deck.cuePoint = 40
        deck.saveMemoryCueHere()
        XCTAssertEqual(deck.memoryItems.map(\.time), [10, 40])
        XCTAssertEqual(deck.track?.memoryCue, 10, "The earliest is where the track loads")

        deck.recall(deck.track!.memoryCues[0])
        _ = deck.renderer.renderOffline(frames: 256)
        XCTAssertEqual(deck.position, 10, accuracy: 0.01)
        XCTAssertEqual(deck.cuePoint, 10)
    }

    func testSavingALoopAndCallingItBackFromSomewhereElse() {
        let deck = makeDeck()
        deck.saveCurrentLoop()
        XCTAssertEqual(deck.track?.savedLoops.count, 0, "No loop set, nothing to save")
        deck.setLoop(beats: 4, resizeExisting: false)
        deck.saveCurrentLoop()
        deck.saveCurrentLoop()
        XCTAssertEqual(deck.track?.savedLoops.count, 1, "The same loop isn't saved twice")
        let saved = deck.track!.savedLoops[0]
        XCTAssertEqual(saved.end - saved.start, 2, accuracy: 0.001)
        deck.exitLoop()
        deck.seek(to: 60)
        _ = deck.renderer.renderOffline(frames: 256)

        deck.recall(saved)
        XCTAssertTrue(deck.loopActive)
        XCTAssertTrue(deck.isPlaying)
        let out = deck.renderer.renderOffline(frames: Int(sr * 3))
        XCTAssertEqual(out.left.count, Int(sr * 3))
        XCTAssertGreaterThanOrEqual(deck.position, saved.start - 0.01)
        XCTAssertLessThan(deck.position, saved.end + 0.01, "It stays in the loop")

        deck.recall(saved)
        XCTAssertFalse(deck.loopActive, "Calling up the same loop again leaves it")
    }

    func testALoopWithOnAtLoadIsWaitingWhenTheTrackComesUp() {
        let deck = makeDeck(at: 0)
        deck.updateTrack { $0.savedLoops = [SavedLoop(start: 1, end: 2, activeOnLoad: true)] }
        deck.armSavedLoops()
        XCTAssertTrue(deck.loopActive)
        deck.play()
        _ = deck.renderer.renderOffline(frames: Int(sr * 0.5))
        XCTAssertEqual(deck.position, 0.5, accuracy: 0.02, "It plays up to the loop rather than jumping to it")
        _ = deck.renderer.renderOffline(frames: Int(sr * 4))
        XCTAssertGreaterThanOrEqual(deck.position, 1)
        XCTAssertLessThan(deck.position, 2.01, "And it holds there")
    }

    func testAHotLoopPadLoopsAndLetsGo() {
        let deck = makeDeck()
        deck.quantize = false
        deck.updateTrack { t in
            t.hotCues[2] = 30
            t.hotCueInfo[2] = HotCueInfo(loopEnd: 31)
        }
        deck.hotCue(2)
        XCTAssertTrue(deck.loopActive)
        _ = deck.renderer.renderOffline(frames: Int(sr * 3))
        XCTAssertGreaterThanOrEqual(deck.position, 30)
        XCTAssertLessThan(deck.position, 31.01)
        deck.hotCue(2)
        XCTAssertFalse(deck.loopActive)
    }

    func testDeletingWithDELCanBeUndone() {
        let deck = makeDeck()
        var undo: (@MainActor () -> Void)?
        deck.offerUndo = { _, action in undo = action }
        deck.updateTrack { $0.memoryCues = [MemoryCue(time: 5, name: "Keep")] }
        deck.shift = true
        deck.pressMemory(deck.memoryItems[0])
        XCTAssertFalse(deck.shift)
        XCTAssertTrue(deck.memoryItems.isEmpty)
        undo?()
        XCTAssertEqual(deck.track?.memoryCues.first?.name, "Keep")
    }

    func testDeletingAHotCueBringsItsNameBackOnUndo() {
        let deck = makeDeck()
        var undo: (@MainActor () -> Void)?
        deck.offerUndo = { _, action in undo = action }
        deck.updateTrack { t in
            t.hotCues[0] = 5
            t.hotCueInfo[0] = HotCueInfo(name: "Drop")
        }
        deck.shift = true
        deck.hotCue(0)
        XCTAssertNil(deck.track?.hotCues[0])
        XCTAssertNil(deck.track?.hotCueInfo[0])
        undo?()
        XCTAssertEqual(deck.track?.hotCueInfo[0]?.name, "Drop")
    }

    func testPagesCoverEverythingSaved() {
        let deck = makeDeck()
        deck.updateTrack { t in t.memoryCues = (0..<11).map { MemoryCue(time: Double($0)) } }
        XCTAssertEqual(deck.memoryPageCount, 2)
        deck.memoryPage = 1
        deck.updateTrack { $0.memoryCues = [] }
        deck.delete(.cue(MemoryCue(time: 99)))
        XCTAssertEqual(deck.memoryPage, 0, "A page that no longer exists doesn't stay selected")
    }
}
