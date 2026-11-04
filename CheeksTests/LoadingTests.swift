import AVFoundation
import XCTest
@testable import Cheeks

/// PLAY and CUE pressed while a track's loading, through the deck's own load of a real file.
@MainActor
final class LoadingTests: XCTestCase {
    private var files: [URL] = []
    private var preparedStems: Any?

    override func setUp() async throws {
        // Nothing here's about stems, and a split would only slow it down.
        preparedStems = UserDefaults.standard.object(forKey: "prepareStemsOnLoad")
        UserDefaults.standard.set(false, forKey: "prepareStemsOnLoad")
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(preparedStems, forKey: "prepareStemsOnLoad")
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func makeDeck() -> (Deck, Library) {
        let library = Library()
        library.tracks = []
        library.playlists = []
        library.missingFiles = []
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        decksKeptAlive.append(dj)
        return (dj.decks[0], library)
    }
    private var decksKeptAlive: [DJEngine] = []

    /// A short file in the library's folder.
    private func makeTrack(in library: Library, seconds: Double = 3) throws -> Track {
        let id = UUID()
        let fileName = "\(id.uuidString).wav"
        let url = LibraryFiles.musicDirectory.appending(path: fileName)
        files.append(url)
        let sr = AudioConfig.sampleRate
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2))
        let audio = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * sr)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let v = 0.3 * Float(sin(2 * .pi * 110 * Double(i) / sr))
            buffer.floatChannelData![0][i] = v
            buffer.floatChannelData![1][i] = v
        }
        try audio.write(from: buffer)
        let track = Track(id: id, title: "Test", artist: "", fileName: fileName, duration: seconds, bpm: 120, firstBeat: 0, key: "8A", loudness: -11)
        library.tracks.append(track)
        return track
    }

    private func finishLoading(_ deck: Deck) async throws {
        for _ in 0..<500 where deck.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(deck.isLoading, "The load never finished")
    }

    func testPlayDuringALoadStartsTheDeckOnceItsReady() async throws {
        let (deck, library) = makeDeck()
        deck.load(try makeTrack(in: library))
        XCTAssertTrue(deck.isLoading)
        deck.togglePlay()
        XCTAssertFalse(deck.isPlaying, "There's nothing to play yet")
        XCTAssertTrue(deck.isPlayingOrAboutTo, "So PLAY shows it was heard")

        try await finishLoading(deck)
        XCTAssertTrue(deck.isPlaying)
        XCTAssertTrue(deck.renderer.isPlaying)
        XCTAssertFalse(deck.startsWhenLoaded)
    }

    /// Round 10: a track read 166.02 on a stopped deck, from a tempo left by the last one, which nobody had chosen.
    func testANewTrackStartsAtItsOwnSpeed() async throws {
        let (deck, library) = makeDeck()
        deck.setTempo(-2.34)
        deck.keyShift = 1
        let track = try makeTrack(in: library)
        deck.load(track)
        try await finishLoading(deck)
        XCTAssertEqual(deck.tempo, 0)
        XCTAssertEqual(deck.keyShift, 0)
    }

    func testALoadWithNoPressStaysStopped() async throws {
        let (deck, library) = makeDeck()
        deck.load(try makeTrack(in: library))
        XCTAssertFalse(deck.isPlayingOrAboutTo)
        try await finishLoading(deck)
        XCTAssertFalse(deck.isPlaying)
    }

    func testPlayPressedAgainDuringALoadTakesItBack() async throws {
        let (deck, library) = makeDeck()
        deck.load(try makeTrack(in: library))
        deck.togglePlay()
        deck.togglePlay()
        XCTAssertFalse(deck.isPlayingOrAboutTo)
        try await finishLoading(deck)
        XCTAssertFalse(deck.isPlaying)
    }

    func testCueDuringALoadTakesItBack() async throws {
        let (deck, library) = makeDeck()
        deck.load(try makeTrack(in: library))
        deck.togglePlay()
        deck.cueDown()
        deck.cueUp()
        XCTAssertFalse(deck.isPlayingOrAboutTo)
        try await finishLoading(deck)
        XCTAssertFalse(deck.isPlaying)
    }

    func testANewLoadForgetsAPressMeantForTheLastOne() async throws {
        let (deck, library) = makeDeck()
        deck.load(try makeTrack(in: library))
        deck.togglePlay()
        let second = try makeTrack(in: library)
        deck.load(second)
        XCTAssertFalse(deck.isPlayingOrAboutTo)
        try await finishLoading(deck)
        XCTAssertEqual(deck.track?.id, second.id)
        XCTAssertFalse(deck.isPlaying)
    }

    func testAFileThatWontOpenForgetsThePress() async throws {
        let (deck, library) = makeDeck()
        let gone = Track(id: UUID(), title: "Gone", artist: "", fileName: "\(UUID().uuidString).wav", duration: 3, bpm: 120, firstBeat: 0, key: "8A", loudness: -11)
        library.tracks.append(gone)
        deck.load(gone)
        deck.togglePlay()
        try await finishLoading(deck)
        XCTAssertNotNil(deck.loadError)
        XCTAssertFalse(deck.isPlayingOrAboutTo)
    }
}
