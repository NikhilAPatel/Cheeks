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
        let long = "Crossfader to the middle. Auto DJ is waiting for the stems. If this track ends first, deck 2 starts."
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
