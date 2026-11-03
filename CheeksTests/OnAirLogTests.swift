import XCTest
@testable import Cheeks

final class OnAirLogTests: XCTestCase {
    private let a = UUID(), b = UUID()
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Plays this for this long, and says how many lines it earned.
    private func play(_ log: inout OnAirLog, deck: Int, _ track: UUID, from: Double, for seconds: Double) -> Int {
        var lines = 0
        for t in stride(from: from, to: from + seconds, by: 1) {
            if log.update(deck: deck, track: track, audible: true, now: start + t) != nil { lines += 1 }
        }
        return lines
    }

    private func stop(_ log: inout OnAirLog, deck: Int, _ track: UUID, at t: Double) {
        _ = log.update(deck: deck, track: track, audible: false, now: start + t)
    }

    func testItTakesTenSeconds() {
        var log = OnAirLog()
        XCTAssertEqual(play(&log, deck: 0, a, from: 0, for: 9), 0)
        XCTAssertEqual(play(&log, deck: 0, a, from: 9, for: 5), 1, "And it's only the one line")
    }

    func testItSaysWhenItBecameAudible() {
        var log = OnAirLog()
        _ = play(&log, deck: 0, a, from: 100, for: 5)
        XCTAssertEqual(log.update(deck: 0, track: a, audible: true, now: start + 111), start + 100)
    }

    func testAShortBurstDoesntCount() {
        var log = OnAirLog()
        XCTAssertEqual(play(&log, deck: 0, a, from: 0, for: 5), 0)
        stop(&log, deck: 0, a, at: 5)
        XCTAssertEqual(play(&log, deck: 0, a, from: 6, for: 5), 0, "Starting again starts the count again")
    }

    /// What the hands-on test found: a track going back on air on the same deck was left out, so the one before it seemed
    /// to run on for 11 minutes.
    func testGoingBackToATrackGetsAnotherLine() {
        var log = OnAirLog()
        XCTAssertEqual(play(&log, deck: 1, a, from: 0, for: 15), 1)
        stop(&log, deck: 1, a, at: 15)
        XCTAssertEqual(play(&log, deck: 0, b, from: 16, for: 15), 1)
        stop(&log, deck: 0, b, at: 31)
        XCTAssertEqual(play(&log, deck: 1, a, from: 32, for: 15), 1)
    }

    func testStoppingAndStartingIsOnePlay() {
        var log = OnAirLog()
        XCTAssertEqual(play(&log, deck: 0, a, from: 0, for: 15), 1)
        stop(&log, deck: 0, a, at: 15)
        XCTAssertEqual(play(&log, deck: 0, a, from: 16, for: 15), 0)
    }

    func testTwoDecksOverlappingGetALineEach() {
        var log = OnAirLog()
        XCTAssertEqual(play(&log, deck: 0, a, from: 0, for: 15), 1)
        XCTAssertEqual(play(&log, deck: 1, b, from: 15, for: 15), 1)
        XCTAssertEqual(play(&log, deck: 0, a, from: 30, for: 15), 0, "It never left, so it's still the same play")
    }

    func testTheSameTrackMovingDeckIsOnePlayIfNothingCameBetween() {
        var log = OnAirLog()
        XCTAssertEqual(play(&log, deck: 0, a, from: 0, for: 15), 1)
        stop(&log, deck: 0, a, at: 15)
        XCTAssertEqual(play(&log, deck: 1, a, from: 16, for: 15), 0)
    }
}
