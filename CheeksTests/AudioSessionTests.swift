import AVFoundation
import XCTest
@testable import Cheeks

/// What happens around the audio, which a hands-on round can't reach: a call, another app, an output going, the system's audio
/// restarting, the disk filling up. A notification's handler is called directly, as every engine still alive in the test process
/// would hear a real one, and start rendering.
@MainActor
final class AudioSessionTests: XCTestCase {
    private var engines: [DJEngine] = []
    private var files: [URL] = []

    override func tearDown() async throws {
        engines.forEach { $0.stopRealtimeForTesting() }
        Library.savesFailForTesting = false
        MemoryRoom.availableForTesting = nil
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func makeEngine() -> (DJEngine, Library) {
        let library = Library()
        library.tracks = []
        library.playlists = []
        library.missingFiles = []
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        dj.secondsBetweenAudioTries = 0.05
        engines.append(dj)
        return (dj, library)
    }

    private func wait(_ what: String, until done: () -> Bool) async throws {
        for _ in 0..<500 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(done(), what)
    }

    private var began: UInt { AVAudioSession.InterruptionType.began.rawValue }
    private var ended: UInt { AVAudioSession.InterruptionType.ended.rawValue }
    private var shouldResume: UInt { AVAudioSession.InterruptionOptions.shouldResume.rawValue }

    private func playingDeck(_ dj: DJEngine) -> Deck {
        let deck = dj.decks[0]
        deck.renderer.setSources([PCM16Stereo(frames: 44_100 * 60)])
        deck.play()
        return deck
    }

    func testACallSaysWhereTheSoundWentAndBringsItBack() async throws {
        let (dj, _) = makeEngine()
        let deck = playingDeck(dj)
        dj.interruptionChanged(type: began, options: nil)
        XCTAssertEqual(dj.engineError, "A call or another app has the sound. It comes back by itself, from where it stopped.")
        XCTAssertTrue(deck.isPlaying, "The deck isn't stopped, and carries on from where it was")

        dj.interruptionChanged(type: ended, options: shouldResume)
        try await wait("The sound's back", until: { dj.engineForTesting.isRunning && dj.engineError == nil })
        XCTAssertTrue(deck.isPlaying)
    }

    /// It came back on any end of an interruption, and took the sound off whatever was playing by then.
    func testWhatTookTheSoundKeepsItIfItHasntFinished() async throws {
        let (dj, _) = makeEngine()
        dj.isInTheBackground = { true }
        dj.interruptionChanged(type: began, options: nil)
        dj.interruptionChanged(type: ended, options: 0)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(dj.engineForTesting.isRunning, "Not from the background")
        XCTAssertNotNil(dj.engineError)

        // The scene coming back is what calls this.
        dj.isInTheBackground = { false }
        dj.startAudio()
        try await wait("Coming back takes it", until: { dj.engineForTesting.isRunning && dj.engineError == nil })
    }

    func testAnInterruptionEndingOnScreenBringsTheSoundBack() async throws {
        let (dj, _) = makeEngine()
        dj.isInTheBackground = { false }
        dj.interruptionChanged(type: began, options: nil)
        dj.interruptionChanged(type: ended, options: 0)
        try await wait("The sound's back", until: { dj.engineForTesting.isRunning && dj.engineError == nil })
    }

    /// Right after a call the session can say no for a moment. It said an OSStatus, once, and the sound stayed off.
    func testTheSoundKeepsTryingIfItWontStart() async throws {
        let (dj, _) = makeEngine()
        dj.isInTheBackground = { false }
        dj.audioStartsToFailForTesting = 3
        dj.startAudio()
        try await wait("It says why", until: { dj.engineError != nil })
        XCTAssertEqual(dj.engineError, "A call or another app has the sound. It comes back by itself, from where it stopped.")
        try await wait("And gets there", until: { dj.engineForTesting.isRunning && dj.engineError == nil })
        XCTAssertEqual(dj.audioStartsToFailForTesting, 0)
    }

    func testTheSoundDoesntKeepTryingFromTheBackground() async throws {
        let (dj, _) = makeEngine()
        dj.isInTheBackground = { true }
        dj.audioStartsToFailForTesting = 1
        dj.startAudio()
        try await wait("It says why", until: { dj.engineError != nil })
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(dj.engineForTesting.isRunning)
    }

    /// Without this it's silent until the app's reopened, with PLAY lit and everything looking fine.
    func testTheSystemsAudioRestartingBringsTheSoundBack() async throws {
        let (dj, _) = makeEngine()
        let deck = playingDeck(dj)
        let old = dj.engineForTesting
        dj.startAudio()
        try await wait("It's running", until: { old.isRunning })

        dj.rebuildAudio()
        XCTAssertFalse(dj.engineForTesting === old)
        try await wait("The new one's running", until: { dj.engineForTesting.isRunning })
        XCTAssertFalse(old.isRunning, "Two threads rendering one core would tear it apart")
        XCTAssertTrue(deck.isPlaying)
        let was = deck.position
        try await wait("And it's the core being rendered", until: { deck.position > was })
        XCTAssertNil(dj.engineError)
    }

    func testTheScreenStaysOnForASetAndGoesOffAfterIt() {
        let (dj, _) = makeEngine()
        let start = CACurrentMediaTime()
        dj.keepTheScreenOnForASet(now: start)
        XCTAssertTrue(dj.keepsTheScreenOn, "Just opened")
        dj.keepTheScreenOnForASet(now: start + 9 * 60)
        XCTAssertTrue(dj.keepsTheScreenOn, "Between tracks")
        dj.keepTheScreenOnForASet(now: start + 11 * 60)
        XCTAssertFalse(dj.keepsTheScreenOn, "Left on a table")
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)

        _ = playingDeck(dj)
        dj.keepTheScreenOnForASet(now: start + 12 * 60)
        XCTAssertTrue(dj.keepsTheScreenOn, "A set's started")
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        dj.keepTheScreenOnForASet(now: start + 300 * 60)
        XCTAssertTrue(dj.keepsTheScreenOn, "However long it runs")
        dj.decks[0].pause()
        dj.keepTheScreenOnForASet(now: start + 305 * 60)
        XCTAssertTrue(dj.keepsTheScreenOn)
        dj.keepTheScreenOnForASet(now: start + 311 * 60)
        XCTAssertFalse(dj.keepsTheScreenOn)
    }

    func testAnOutputGoingSaysWhereTheMusicIs() {
        let (dj, _) = makeEngine()
        dj.noticeOutputGone(nowOnSpeaker: true)
        XCTAssertNil(dj.statusMessage, "Nothing's playing, so nothing's come out of the speaker")
        _ = playingDeck(dj)
        dj.noticeOutputGone(nowOnSpeaker: false)
        XCTAssertNil(dj.statusMessage, "It went somewhere else, which someone chose")
        dj.noticeOutputGone(nowOnSpeaker: true)
        XCTAssertEqual(dj.statusMessage, "The output it was using has gone, so the music's coming out of this \(UIDevice.current.localizedModel).")
        XCTAssertTrue(dj.decks[0].isPlaying, "A speaker dropping out for a moment doesn't stop the set")
    }

    func testASaveThatFailsSaysSoOnce() async throws {
        let (dj, library) = makeEngine()
        Library.savesFailForTesting = true
        library.saveNow()
        try await wait("It says so", until: { dj.statusMessage != nil })
        XCTAssertEqual(dj.statusKind, .problem)
        XCTAssertTrue(dj.statusMessage?.contains("couldn't be saved") == true, dj.statusMessage ?? "")

        dj.statusMessage = nil
        library.saveNow()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(dj.statusMessage, "Everything that changes saves, so it doesn't say so each time")
    }

    // MARK: Importing

    private func wav(named name: String, frames: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name) \(UUID().uuidString).wav")
        files.append(url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 2))
        do {
            let audio = try AVAudioFile(forWriting: url, settings: format.settings)
            if frames > 0 {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
                buffer.frameLength = AVAudioFrameCount(frames)
                try audio.write(from: buffer)
            }
        }
        return url
    }

    private func notAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Not audio \(UUID().uuidString).mp3")
        files.append(url)
        try Data("this isn't audio".utf8).write(to: url)
        return url
    }

    /// It was added, sat in the list like any other track, and only said so when it was on a deck.
    func testWhatCantBeReadIsntImported() async throws {
        let (_, library) = makeEngine()
        for source in [try notAudio(), try wav(named: "Empty", frames: 0)] {
            guard case .failed = library.importFile(at: source) else { return XCTFail("\(source.lastPathComponent) went in") }
        }
        XCTAssertTrue(library.tracks.isEmpty)
    }

    func testPickedFilesComeInOffTheMainThreadAndSayWhatCameOfEach() async throws {
        let (_, library) = makeEngine()
        let good = try wav(named: "Good", frames: 4096)
        var seen: [(Int, Int)] = []
        let outcomes = await library.importFiles([good, try notAudio(), good]) { seen.append(($0, $1)) }
        XCTAssertFalse(Library.lastBroughtInOnTheMainThread)
        XCTAssertEqual(seen.map(\.0), [1, 2, 3])
        XCTAssertEqual(seen.map(\.1), [3, 3, 3])
        guard case .added(let id) = outcomes[0] else { return XCTFail("\(outcomes[0])") }
        files.append(LibraryFiles.musicDirectory.appending(path: "\(id.uuidString).wav"))
        guard case .failed = outcomes[1] else { return XCTFail("\(outcomes[1])") }
        guard case .alreadyThere(let again) = outcomes[2] else { return XCTFail("\(outcomes[2])") }
        XCTAssertEqual(again, id)
        XCTAssertEqual(library.tracks.map(\.id), [id])
    }

    // MARK: Memory

    private func trackInPlace(_ library: Library, frames: Int) throws -> Track {
        let id = UUID()
        let inPlace = LibraryFiles.musicDirectory.appending(path: "\(id.uuidString).wav")
        try FileManager.default.copyItem(at: try wav(named: "Short", frames: frames), to: inPlace)
        files.append(inPlace)
        let track = Track(id: id, title: "Short", artist: "", fileName: inPlace.lastPathComponent, duration: Double(frames) / AudioConfig.sampleRate, bpm: 120, firstBeat: 0, key: "8A", loudness: -11)
        library.tracks.append(track)
        return track
    }

    /// iOS kills the app outright for going over, with the music going.
    func testATrackThatWontFitInMemoryIsRefused() async throws {
        let (dj, library) = makeEngine()
        let deck = dj.decks[0]
        let track = try trackInPlace(library, frames: 44_100)
        MemoryRoom.availableForTesting = 100 << 20
        deck.load(track)
        try await wait("The load finished", until: { !deck.isLoading })
        XCTAssertEqual(deck.loadError, "This track's too long to fit in memory")
        XCTAssertFalse(deck.isLoaded)
    }

    func testStemsThatWontFitSaySoAndCanTryAgain() async throws {
        let prepared = UserDefaults.standard.object(forKey: "prepareStemsOnLoad")
        UserDefaults.standard.set(false, forKey: "prepareStemsOnLoad")
        defer { UserDefaults.standard.set(prepared, forKey: "prepareStemsOnLoad") }
        let (dj, library) = makeEngine()
        let deck = dj.decks[0]
        deck.load(try trackInPlace(library, frames: 44_100))
        try await wait("The load finished", until: { !deck.isLoading })

        // Enough for the stems, and not for the model that makes them.
        MemoryRoom.availableForTesting = 300 << 20
        deck.prepareStems()
        XCTAssertEqual(deck.stemStatus, .noRoom)
        XCTAssertEqual(dj.statusMessage, "There's no room in memory for this track's stems just now, so it plays whole.")
        deck.toggleStem(.drums)
        XCTAssertEqual(deck.stemsOn, [true, true, true, true], "A pad can't change what it can't do")

        MemoryRoom.availableForTesting = nil
        deck.prepareStems()
        XCTAssertNotEqual(deck.stemStatus, .noRoom, "The other deck may have let go of some")
        try await wait("It split", until: { if case .ready = deck.stemStatus { return true } else { return false } })
    }

    func testAPadOnATrackTooLongToSplitSaysSo() async throws {
        let (dj, _) = makeEngine()
        let deck = dj.decks[0]
        deck.stemStatus = .tooLong
        deck.toggleStem(.drums)
        XCTAssertEqual(dj.statusMessage, "This track's too long to split into stems.")
        XCTAssertEqual(deck.stemsOn, [true, true, true, true])
    }

    func testAFileWithNoAudioInItSaysSoOnTheDeck() async throws {
        let (dj, library) = makeEngine()
        let id = UUID()
        let source = try wav(named: "Empty", frames: 0)
        let inPlace = LibraryFiles.musicDirectory.appending(path: "\(id.uuidString).wav")
        try FileManager.default.copyItem(at: source, to: inPlace)
        files.append(inPlace)
        let track = Track(id: id, title: "Empty", artist: "", fileName: inPlace.lastPathComponent)
        library.tracks.append(track)
        let deck = dj.decks[0]
        deck.load(track)
        try await wait("The load finished", until: { !deck.isLoading })
        XCTAssertEqual(deck.loadError, "Couldn't open this file")
    }
}
