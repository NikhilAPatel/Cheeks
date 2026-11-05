import SwiftUI
import XCTest
@testable import Cheeks

/// The small things hands-on round 13 found around the browser, the messages and a recording's playback.
@MainActor
final class BrowserAndRecordingTests: XCTestCase {
    private func track(_ id: UUID = UUID()) -> Track {
        Track(id: id, title: "T", artist: "", fileName: "none", duration: 60)
    }

    /// History has a track once for each time it was on air, and SwiftUI logged a fault for every row it had twice.
    func testARepeatedTrackGetsARowOfItsOwn() {
        let same = track(), other = track()
        let rows = BrowserView.Row.rows(of: [same, other, same], canRepeat: true)
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        XCTAssertEqual(rows.map(\.number), [0, 1, 2])
        XCTAssertEqual(rows.map(\.track.id), [same.id, other.id, same.id])
    }

    func testARowsIdentityFollowsItsTrackWhenTheListIsSorted() {
        let a = track(), b = track()
        let before = BrowserView.Row.rows(of: [a, b], canRepeat: false)
        let after = BrowserView.Row.rows(of: [b, a], canRepeat: false)
        XCTAssertEqual(before[0].id, after[1].id, "Or a row's state would stay where it was, on another track")
    }

    /// A long one stayed up about as long as a short one, and the end's usually the part you act on.
    func testALongMessageStaysUpLongEnoughToRead() {
        XCTAssertEqual(StatusCapsule.secondsUp("Mix off.", hasKeys: false), 5)
        XCTAssertEqual(StatusCapsule.secondsUp("Deleted hot cue A", hasKeys: true), 8)
        let long = "Moved the crossfader to the middle. Auto DJ is waiting for the stems. If this track finishes first, deck 2 starts."
        XCTAssertGreaterThan(StatusCapsule.secondsUp(long, hasKeys: false), 7)
    }

    func testRenamingAPlaylistKeepsItsTracks() throws {
        let library = Library()
        let added = UUID()
        let id = library.createPlaylist(named: "Friday")
        library.add(added, to: id)
        let playlist = try XCTUnwrap(library.playlists.first { $0.id == id })
        library.rename(playlist, to: "Saturday")
        XCTAssertEqual(library.playlists.first { $0.id == id }?.name, "Saturday")
        XCTAssertEqual(library.playlists.first { $0.id == id }?.trackIDs, [added])
        library.rename(playlist, to: "")
        XCTAssertEqual(library.playlists.first { $0.id == id }?.name, "Saturday", "A playlist needs a name")
        library.deletePlaylist(playlist)
    }

    /// "Analysing Fast Bird again." and never another word. This one has no file to read, so it's the way it can go wrong.
    func testReanalysingSaysHowItCameOut() async throws {
        let library = Library()
        let track = Track(id: UUID(), title: "Gone", artist: "", fileName: "not-there.mp3", duration: 1, bpm: 120)
        library.tracks.append(track)
        defer { library.tracks.removeAll { $0.id == track.id } }
        let heard = expectation(description: "It said")
        library.reanalyze(track) { done in
            XCTAssertNil(done)
            heard.fulfill()
        }
        await fulfillment(of: [heard], timeout: 20)
    }

    /// A first-time user held a row in their playlist and dragged it. It lifted, and nothing changed.
    /// No two closures compare as equal, so one on a row has SwiftUI rebuild every row showing whenever the browser changes at all:
    /// about 200 ms frozen on each open and close, with nothing to see but a slide that stuck.
    /// A row built with a modifier of our own at its top had the list build all 2,000 each time the browser opened or closed: about
    /// 200 ms frozen each way, in round 19's code, and nothing that looks at the screen could have said why.
    func testTheListOnlyBuildsTheRowsShowing() async throws {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        // Not saved: nothing here calls `library.update`, which is what writes the library to disk.
        let saved = library.tracks
        defer { library.tracks = saved }
        library.tracks = (0..<1000).map { Track(id: UUID(), title: "Track \($0)", artist: "", fileName: "none", duration: 1, bpm: 124) }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 667, height: 375)
        window.windowLevel = .alert + 1
        TrackRow.builtForTesting = 0
        window.rootViewController = UIHostingController(rootView: ContentView(showLibrary: true).environment(library).environment(dj))
        window.isHidden = false
        window.frame = CGRect(x: 0, y: 0, width: 667, height: 375)
        window.rootViewController?.view.frame = window.bounds
        window.rootViewController?.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(1))
        window.isHidden = true
        window.rootViewController = nil
        XCTAssertGreaterThan(TrackRow.builtForTesting, 0, "It has to have shown some")
        XCTAssertLessThan(TrackRow.builtForTesting, 100, "It built rows nobody can see")
    }

    func testATrackRowHoldsNoClosures() {
        let track = Track(id: UUID(), title: "A", artist: "", fileName: "none", duration: 1, bpm: 124)
        let row = TrackRow(track: track, referenceDeck: nil, playlistID: nil)
        let closures = Mirror(reflecting: row).children.filter { "\(type(of: $0.value))".contains("->") }.map { $0.label ?? "?" }
        XCTAssertEqual(closures, [], "These want to go in RowActions")
    }

    /// Saving's off the main thread now, so what's on disk has to be the last save, whichever way it went.
    func testTheLastSaveIsWhatsOnDisk() async throws {
        let library = Library()
        let tracks = library.tracks, playlists = library.playlists
        defer {
            library.tracks = tracks
            library.playlists = playlists
            library.saveNow()
        }
        library.playlists = [Playlist(id: UUID(), name: "First")]
        library.save()
        try await Task.sleep(for: .milliseconds(420))
        library.playlists = [Playlist(id: UUID(), name: "Second")]
        library.saveNow()
        let names = Library().playlists.map(\.name)
        XCTAssertTrue(names.contains("Second"), "\(names)")
        XCTAssertFalse(names.contains("First"), "\(names)")
    }

    func testSeveralTracksGoInAPlaylistInOrderAndOnlyOnce() {
        let library = Library()
        let playlist = library.createPlaylist(named: "Friday")
        defer { library.playlists.removeAll { $0.id == playlist } }
        let a = UUID(), b = UUID(), c = UUID()
        library.add(b, to: playlist)
        XCTAssertEqual(library.add([a, b, c, a], to: playlist), [a, c], "What's there stays where it is")
        XCTAssertEqual(library.playlists.first { $0.id == playlist }?.trackIDs, [b, a, c])
        XCTAssertEqual(library.add([a], to: playlist), [])
        XCTAssertEqual(library.add([a], to: UUID()), [], "There's no such playlist")
        library.remove([a, c], from: playlist)
        XCTAssertEqual(library.playlists.first { $0.id == playlist }?.trackIDs, [b])
    }

    func testAPlaylistsTracksCanBeMoved() throws {
        let library = Library()
        let ids = (0..<4).map { _ in UUID() }
        let id = library.createPlaylist(named: "Order")
        ids.forEach { library.add($0, to: id) }
        func order() -> [UUID]? { library.playlists.first { $0.id == id }?.trackIDs }
        library.move(ids[0], in: id, to: 2)
        XCTAssertEqual(order(), [ids[1], ids[0], ids[2], ids[3]], "Counted as the list is before it moves")
        library.move(ids[3], in: id, to: 0)
        XCTAssertEqual(order(), [ids[3], ids[1], ids[0], ids[2]])
        library.move(ids[1], in: id, to: 4)
        XCTAssertEqual(order(), [ids[3], ids[0], ids[2], ids[1]], "To the end")
        library.move(UUID(), in: id, to: 0)
        XCTAssertEqual(order(), [ids[3], ids[0], ids[2], ids[1]], "One that isn't on it stays off it")
        library.playlists.first { $0.id == id }.map(library.deletePlaylist)
    }

    /// "History 2026-11-04" was cut off in the sidebar as "History 202…", which leaves out the day.
    /// A tracklist read "Gepzene — Gepzene - Can't be Serious", and listed a track moved to 10A as 5A with its played tempo beside it.
    func testATracklistSaysWhatWasHeard() throws {
        let deck = Deck(index: 0)
        deck.track = Track(id: UUID(), title: "Gepzene - Can't be Serious", artist: "Gepzene", fileName: "none", duration: 1, bpm: 128, key: "5A")
        deck.keyShift = 7
        let entry = try XCTUnwrap(SetlistEntry(heardOn: deck, at: 12))
        XCTAssertEqual(entry.title, "Can't be Serious")
        XCTAssertEqual(entry.artist, "Gepzene")
        XCTAssertEqual(entry.key, Camelot.shifted("5A", by: 7))
        XCTAssertNotEqual(entry.key, "5A")
    }

    func testATitleKeepsWhatOnlyLooksLikeAnArtist() {
        func title(_ title: String, by artist: String) -> String {
            Track(id: UUID(), title: title, artist: artist, fileName: "none").titleWithoutArtist
        }
        XCTAssertEqual(title("Solo", by: "Solo"), "Solo")
        XCTAssertEqual(title("Solo Flight", by: "Solo"), "Solo Flight")
        XCTAssertEqual(title("Any - Thing", by: ""), "Any - Thing")
        XCTAssertEqual(title("SOLO – Flight", by: "Solo"), "Flight")
    }

    func testAHistoryPlaylistShowsADateThatFits() throws {
        let library = Library()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Playlist(id: UUID(), name: "History " + formatter.string(from: Date()), trackIDs: [])
        XCTAssertEqual(library.shownName(of: today), "History " + Date().formatted(.dateTime.month(.abbreviated).day()))
        XCTAssertLessThanOrEqual(library.shownName(of: today).count, 14)
        let old = Playlist(id: UUID(), name: "History 2020-03-07", trackIDs: [])
        XCTAssertTrue(library.shownName(of: old).contains("2020"), "It can't be mistaken for this year's")
        let mine = Playlist(id: UUID(), name: "Friday", trackIDs: [])
        XCTAssertEqual(library.shownName(of: mine), "Friday")
        let odd = Playlist(id: UUID(), name: "History of house", trackIDs: [])
        XCTAssertEqual(library.shownName(of: odd), "History of house")
    }

    /// Playing a recording had no time on it and no way to move through it, and its pause started it again from the top.
    func testARecordingPausesAndMoves() async throws {
        let frames = Int(AudioConfig.sampleRate) * 8
        let audio = PCM16Stereo(frames: frames)
        let url = FileManager.default.temporaryDirectory.appending(path: "recording-\(UUID()).caf")
        try audio.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = RecordingPlayer()
        func wait(_ what: String, until done: () -> Bool) async throws {
            for _ in 0..<100 where !done() { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(done(), what)
        }
        player.toggle(url)
        XCTAssertEqual(player.playing, url)
        try await wait("Its length is known") { player.duration > 7 }
        player.seek(to: 5)
        XCTAssertEqual(player.position, 5)
        try await wait("It carries on from there") { player.position >= 5 }
        player.toggle(url)
        XCTAssertTrue(player.isPaused)
        XCTAssertEqual(player.playing, url, "Paused, it's still the one that's showing")
        try await Task.sleep(for: .milliseconds(300))
        let held = player.position
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(player.position, held, accuracy: 0.05, "It's stopped where it was")
        XCTAssertGreaterThan(held, 4.5, "And not gone back to the top")
        player.toggle(url)
        XCTAssertFalse(player.isPaused)
        player.stop()
        XCTAssertNil(player.playing)
        XCTAssertEqual(player.position, 0)
    }
}
