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

    func testALoopBehindTheCueDoesntPullTheDeckBack() {
        let deck = makeDeck(at: 50)
        deck.cuePoint = 50
        deck.updateTrack { $0.savedLoops = [SavedLoop(start: 10, end: 12, activeOnLoad: true)] }
        deck.armSavedLoops()
        XCTAssertFalse(deck.loopActive, "The deck's past it, so the loop's left set but off")
        deck.play()
        _ = deck.renderer.renderOffline(frames: Int(sr))
        XCTAssertEqual(deck.position, 51, accuracy: 0.05, "and the deck carries on from where it loaded")
        XCTAssertEqual(deck.renderer.loopStart / sr, 10, accuracy: 0.001, "RELOOP can still get to it")
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

    func testARollLeavesTheLoopKeyWhereItWas() {
        let deck = makeDeck()
        deck.play()
        deck.loopBeats = 32
        deck.rollBegin(1.0 / 8)
        XCTAssertEqual(deck.loopBeats, 1.0 / 8)
        deck.rollEnd()
        XCTAssertEqual(deck.loopBeats, 32)
    }

    func testPressingINIsRememberedUntilOUT() {
        let deck = makeDeck()
        deck.loopIn()
        XCTAssertTrue(deck.loopInSet)
        deck.seek(to: 14)
        _ = deck.renderer.renderOffline(frames: 256)
        deck.loopOut()
        XCTAssertFalse(deck.loopInSet)
        XCTAssertTrue(deck.loopActive)
    }

    // MARK: FX chain, on the deck

    func testEffectsChainUpToThreeAndTheOldestMakesWay() {
        let deck = makeDeck()
        deck.play()
        deck.fxEngage(.echo)
        deck.fxEngage(.flanger)
        deck.fxEngage(.gate)
        XCTAssertEqual(deck.activeFX.map(\.effect), [.echo, .flanger, .gate])
        XCTAssertEqual(Set(deck.activeFX.compactMap(\.link)).count, 3, "Each in its own link")
        deck.fxEngage(.crush)
        XCTAssertEqual(deck.activeFX.map(\.effect), [.flanger, .gate, .crush], "The one on longest gave way")
        XCTAssertEqual(deck.fxType, .crush)

        deck.fxRelease(.gate)
        XCTAssertFalse(deck.isFXOn(.gate))
        XCTAssertEqual(deck.activeFX.count, 2)
        deck.fxEngage(.reverb)
        XCTAssertEqual(Set(deck.activeFX.compactMap(\.link)).count, 3, "A free link gets used, not a busy one")
        deck.fxRelease()
        XCTAssertTrue(deck.activeFX.isEmpty)
        XCTAssertFalse(deck.fxOn)
    }

    func testControlsChangeTheEffectTheyreShowing() {
        let deck = makeDeck()
        deck.fxDepth = 0.2
        deck.fxEngage(.echo)
        deck.fxDepth = 0.9
        deck.fxEngage(.gate)
        deck.fxDepth = 0.4
        XCTAssertEqual(deck.activeFX.first { $0.effect == .echo }?.depth, 0.9, "Changing the gate left the echo alone")
        XCTAssertEqual(deck.activeFX.first { $0.effect == .gate }?.depth, 0.4)
        deck.focusFX(.echo)
        XCTAssertEqual(deck.fxDepth, 0.9, "Going back to the echo shows its setting")
        XCTAssertEqual(deck.activeFX.first { $0.effect == .gate }?.depth, 0.4, "and didn't change the gate")
    }

    func testTransportEffectsDontTakeALink() {
        let deck = makeDeck()
        deck.play()
        _ = deck.renderer.renderOffline(frames: 256)
        deck.fxEngage(.brake)
        XCTAssertNil(deck.activeFX.first?.link)
        _ = deck.renderer.renderOffline(frames: Int(sr * 3))
        deck.tick()
        XCTAssertFalse(deck.isFXOn(.brake), "It lets go once the deck's stopped")
        XCTAssertFalse(deck.isPlaying)
    }

    func testEchoOutWaitsForABeatAndComesBack() {
        let deck = makeDeck()
        deck.play()
        _ = deck.renderer.renderOffline(frames: 256)
        deck.toggleEchoOut()
        XCTAssertTrue(deck.echoingOut)
        XCTAssertTrue(deck.renderer.sourceCut)
        _ = deck.renderer.renderOffline(frames: Int(sr * 0.1))
        deck.toggleEchoOut()
        XCTAssertFalse(deck.echoingOut)
        XCTAssertFalse(deck.renderer.sourceCut)
    }

    func testStoppingTheDeckEndsAnEchoOut() {
        let deck = makeDeck()
        deck.play()
        _ = deck.renderer.renderOffline(frames: 256)
        deck.toggleEchoOut()
        deck.pause()
        XCTAssertFalse(deck.echoingOut)
        XCTAssertFalse(deck.renderer.sourceCut, "Playing again mustn't come back silent")
    }

    func testEchoOutNeedsAPlayingDeck() {
        let deck = makeDeck()
        var said: [(String, StatusKind)] = []
        deck.onMessage = { said.append(($0, $1)) }
        deck.toggleEchoOut()
        XCTAssertFalse(deck.echoingOut)
        XCTAssertEqual(said.first?.1, .refused, "It says why")
    }

    // MARK: Edits have to reach the library

    private func deckInLibrary() -> (Deck, Library) {
        let library = Library()
        library.playlists = []
        library.missingFiles = []
        let deck = makeDeck()
        library.tracks = [deck.track!]
        deck.library = library
        return (deck, library)
    }

    func testDeletingAJustSavedMemoryCueRemovesItFromTheLibrary() {
        let (deck, library) = deckInLibrary()
        let id = deck.track!.id
        deck.saveMemoryCue(at: 12)
        XCTAssertEqual(deck.track?.memoryCues.map(\.id), library.track(id)?.memoryCues.map(\.id), "It's the same cue in both")
        deck.delete(deck.memoryItems[0])
        XCTAssertEqual(library.track(id)?.memoryCues.count, 0)
    }

    func testUndoingADeleteBringsBackOneCue() {
        let (deck, library) = deckInLibrary()
        let id = deck.track!.id
        var undo: (() -> Void)?
        deck.offerUndo = { _, action in undo = action }
        deck.saveMemoryCue(at: 12)
        deck.delete(deck.memoryItems[0])
        undo?()
        XCTAssertEqual(library.track(id)?.memoryCues.count, 1)
        XCTAssertEqual(deck.track?.memoryCues.count, 1)
    }

    func testTheOnAtLoadSwitchReachesALoopSavedSinceTheTrackLoaded() {
        let (deck, library) = deckInLibrary()
        let id = deck.track!.id
        deck.setLoop(beats: 4, resizeExisting: false)
        deck.saveCurrentLoop()
        let loop = deck.track!.savedLoops[0]
        // What the list's switch does.
        deck.updateTrack { t in
            for i in t.savedLoops.indices { t.savedLoops[i].activeOnLoad = t.savedLoops[i].id == loop.id }
        }
        XCTAssertEqual(library.track(id)?.savedLoops.first?.activeOnLoad, true)
    }

    func testTheSameTrackOnBothDecksStaysInStep() {
        let library = Library()
        library.playlists = []
        library.missingFiles = []
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        let track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: 120, bpm: 120, firstBeat: 0)
        library.tracks = [track]
        for deck in dj.decks {
            deck.renderer.setSources([PCM16Stereo(frames: Int(sr * 120))])
            deck.track = track
        }
        dj.decks[1].saveMemoryCue(at: 12)
        XCTAssertEqual(dj.decks[0].track?.memoryCues.count, 1, "A cue made on one deck shows on the other")
        dj.decks[1].scaleBPM(2)
        XCTAssertEqual(dj.decks[0].bpm, 240, accuracy: 0.001, "and so does a change to the grid")
    }

    // MARK: Rolls and slices borrow the loop

    func testARollLeavesNoLoopBehind() {
        let deck = makeDeck()
        var messages: [String] = []
        deck.onMessage = { text, _ in messages.append(text) }
        deck.play()
        deck.rollBegin(1.0 / 16)
        _ = deck.renderer.renderOffline(frames: 2048)
        deck.rollEnd()
        XCTAssertFalse(deck.renderer.loopEnd > deck.renderer.loopStart, "There's no loop to find afterwards")
        deck.saveCurrentLoop()
        XCTAssertEqual(deck.track?.savedLoops.count, 0)
        XCTAssertEqual(messages, ["Set a loop first, then save it."])
    }

    func testASliceLeavesNoLoopBehind() {
        let deck = makeDeck()
        deck.play()
        deck.sliceBegin(2)
        _ = deck.renderer.renderOffline(frames: 2048)
        deck.sliceEnd()
        XCTAssertFalse(deck.renderer.loopEnd > deck.renderer.loopStart)
        XCTAssertFalse(deck.loopActive)
    }

    func testARollGivesBackTheLoopThatWasSet() {
        let deck = makeDeck()
        deck.setLoop(beats: 4, resizeExisting: false)
        let start = deck.renderer.loopStart, end = deck.renderer.loopEnd
        deck.exitLoop()
        deck.rollBegin(1.0 / 4)
        deck.rollEnd()
        XCTAssertEqual(deck.renderer.loopStart, start)
        XCTAssertEqual(deck.renderer.loopEnd, end, "RELOOP still has the loop you set")
        XCTAssertFalse(deck.renderer.loopActive)
        XCTAssertEqual(deck.loopBeats, 4)
    }

    func testARollKeepsAWaitingIN() {
        let deck = makeDeck()
        deck.loopIn()
        let start = deck.renderer.loopStart
        deck.rollBegin(1.0 / 4)
        deck.rollEnd()
        XCTAssertTrue(deck.loopInSet)
        XCTAssertEqual(deck.renderer.loopStart, start)
    }

    func testAManualLoopShowsItsLengthAndTheKeyGoesBackAfterwards() {
        let deck = makeDeck(at: 10)
        deck.quantize = false
        deck.loopBeats = 8
        deck.loopIn()
        deck.seek(to: 12.5) // 5 beats at 120
        _ = deck.renderer.renderOffline(frames: 256)
        deck.loopOut()
        XCTAssertEqual(deck.loopBeats, 5, accuracy: 0.05, "The key shows this loop's length")
        deck.exitLoop()
        XCTAssertEqual(deck.loopBeats, 8, "and goes back to the length you'd chosen")
        deck.reloop()
        XCTAssertEqual(deck.loopBeats, 5, accuracy: 0.05, "and shows it again when the loop comes back")
        deck.exitLoop()
        XCTAssertEqual(deck.loopBeats, 8)
    }
}
