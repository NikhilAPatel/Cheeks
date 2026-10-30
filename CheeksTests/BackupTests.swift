import XCTest
@testable import Cheeks

@MainActor
final class BackupTests: XCTestCase {
    /// A library that doesn't start with whatever the test host saved earlier.
    private func emptyLibrary() -> Library {
        let library = Library()
        library.tracks = []
        library.playlists = []
        library.missingFiles = []
        return library
    }

    private func preparedTrack(name: String, id: UUID = UUID()) -> Track {
        var track = Track(id: id, title: name, artist: "Artist", fileName: "\(id.uuidString).mp3", originalFileName: name + ".mp3",
                          duration: 200, bpm: 128, firstBeat: 0.25, key: "8A", loudness: -9)
        track.hotCues = [0: 10, 3: 40]
        track.hotCueInfo = [0: HotCueInfo(name: "Drop", color: CueColor(red: 1, green: 0, blue: 0))]
        track.memoryCues = [MemoryCue(time: 5, name: "In")]
        track.savedLoops = [SavedLoop(start: 8, end: 12, activeOnLoad: true)]
        return track
    }

    func testRestoringOntoAFreshInstallBringsEverythingBackByFileName() throws {
        let original = emptyLibrary()
        original.tracks = [preparedTrack(name: "One"), preparedTrack(name: "Two")]
        original.playlists = [Playlist(id: UUID(), name: "Friday", trackIDs: [original.tracks[1].id, original.tracks[0].id])]
        let data = try original.backupData()

        // The music was imported again, so the same files now have different IDs and no cues.
        let fresh = emptyLibrary()
        fresh.tracks = [Track(id: UUID(), title: "One", artist: "", fileName: "a.mp3", originalFileName: "one.MP3", duration: 200)]
        let localID = fresh.tracks[0].id

        let result = try fresh.restore(from: data)
        XCTAssertEqual(result.matched, 1)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.playlists, 1)

        let one = try XCTUnwrap(fresh.track(localID))
        XCTAssertEqual(one.fileName, "a.mp3", "It keeps pointing at the file that's actually here")
        XCTAssertEqual(one.bpm, 128)
        XCTAssertEqual(one.hotCues[3], 40)
        XCTAssertEqual(one.hotCueInfo[0]?.name, "Drop")
        XCTAssertEqual(one.memoryCues.first?.name, "In")
        XCTAssertEqual(one.savedLoops.first?.activeOnLoad, true)

        let two = try XCTUnwrap(fresh.tracks.first { $0.title == "Two" })
        XCTAssertTrue(fresh.isMissing(two), "Its file hasn't been imported yet")
        XCTAssertEqual(fresh.playlists.first?.trackIDs, [two.id, localID], "Playlists follow the new IDs")
    }

    func testRestoringTwiceDoesNotDuplicate() throws {
        let library = emptyLibrary()
        library.tracks = [preparedTrack(name: "One")]
        library.playlists = [Playlist(id: UUID(), name: "Friday", trackIDs: [library.tracks[0].id])]
        let data = try library.backupData()
        try library.restore(from: data)
        try library.restore(from: data)
        XCTAssertEqual(library.tracks.count, 1)
        XCTAssertEqual(library.playlists.count, 1)
    }

    func testABackupOfAnOlderLibraryStillRestores() throws {
        let id = UUID()
        let json = """
        {"version":1,"exported":"2026-01-01T00:00:00Z","playlists":[],
         "tracks":[{"id":"\(id.uuidString)","title":"Old","artist":"","fileName":"x.mp3","memoryCue":3.5,"hotCues":{"1":9}}]}
        """
        let library = emptyLibrary()
        try library.restore(from: Data(json.utf8))
        XCTAssertEqual(library.track(id)?.memoryCue, 3.5)
        XCTAssertEqual(library.track(id)?.hotCues[1], 9)
    }

    func testSomethingElseIsRefusedAndChangesNothing() {
        let library = emptyLibrary()
        library.tracks = [preparedTrack(name: "One")]
        XCTAssertThrowsError(try library.restore(from: Data("{\"not\":\"a backup\"}".utf8)))
        XCTAssertEqual(library.tracks.count, 1)
    }

    func testImportingTheFileBringsAMissingTrackBack() throws {
        let library = emptyLibrary()
        let id = UUID()
        let name = "relink-\(id.uuidString).mp3"
        var track = Track(id: id, title: "Back", artist: "", fileName: "gone-\(id.uuidString).mp3", originalFileName: name, bpm: 124)
        track.hotCues = [2: 30]
        library.tracks = [track]
        library.refreshMissingFiles()
        XCTAssertTrue(library.isMissing(track))

        let file = FileManager.default.temporaryDirectory.appending(path: name)
        try Data(repeating: 1, count: 128).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        library.importFile(at: file)

        XCTAssertEqual(library.tracks.count, 1, "No duplicate: it's the same track")
        let back = try XCTUnwrap(library.track(id))
        XCTAssertFalse(library.isMissing(back))
        XCTAssertEqual(back.hotCues[2], 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: back).path))
        try? FileManager.default.removeItem(at: library.url(for: back))
    }

    func testAMissingTrackIsRefusedAtTheDeck() {
        let library = emptyLibrary()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        let track = Track(id: UUID(), title: "Gone", artist: "", fileName: "gone.mp3", bpm: 120)
        library.tracks = [track]
        library.refreshMissingFiles()
        XCTAssertFalse(dj.load(track, onto: dj.decks[0]))
        XCTAssertNil(dj.decks[0].track)
        XCTAssertNotNil(dj.statusMessage)
    }

    func testAutomaticBackupsArePrunedToTheNewestFourteen() throws {
        let library = emptyLibrary()
        library.tracks = [preparedTrack(name: "One")]
        let manager = FileManager.default
        for old in (try? manager.contentsOfDirectory(at: Library.backupDirectory, includingPropertiesForKeys: nil)) ?? [] {
            try? manager.removeItem(at: old)
        }
        var day = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<20 {
            library.writeAutomaticBackup(now: day)
            library.writeAutomaticBackup(now: day) // only once a day
            day.addTimeInterval(86_400)
        }
        let files = try manager.contentsOfDirectory(at: Library.backupDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 14)
    }

    func testCatchingUpOnAnalysisWaitsWhileTheDecksAreBusy() {
        let library = emptyLibrary()
        var busy = true
        library.isBusy = { busy }
        let track = Track(id: UUID(), title: "Old", artist: "", fileName: "none.mp3", bpm: 120)
        library.tracks = [track]
        library.enqueueCatchUp(track.id)
        XCTAssertNil(library.analyzing, "It waits while a deck's playing")
        busy = false
        library.enqueueCatchUp(track.id)
        XCTAssertEqual(library.analyzing, track.id, "And gets on with it when there isn't")
    }
}
