import XCTest
@testable import Cheeks

final class SetOrderTests: XCTestCase {
    private struct Song {
        var name: String
        var bpm: Double?
        var key: String?
    }

    /// A mix's first choice was the track it had faded out 40 s before, as close in tempo as can be.
    func testWhatsBeenHeardGoesLast() {
        let songs = [Song(name: "just played", bpm: 124, key: "8A"), Song(name: "further off", bpm: 128, key: "9A"), Song(name: "far off", bpm: 131, key: "3B"), Song(name: "played before", bpm: 125, key: "8A")]
        let heard: Set<String> = ["just played", "played before"]
        let order = SetOrder.order(songs, from: SetOrder.Place(bpm: 124, key: "8A"), heard: { heard.contains($0.name) }, bpm: \.bpm, key: \.key).map(\.name)
        XCTAssertEqual(Array(order.prefix(2)), ["further off", "far off"])
        XCTAssertEqual(Set(order.suffix(2)), heard, "Still there, when there's nothing else")
    }

    private func names(_ songs: [Song], from start: SetOrder.Place?) -> [String] {
        SetOrder.order(songs, from: start, bpm: \.bpm, key: \.key).map(\.name)
    }

    func testATrackThatMatchesFitsBest() {
        let place = SetOrder.Place(bpm: 124, key: "8A")
        let match = SetOrder.fit(from: place, bpm: 124, key: "8A")
        XCTAssertEqual(match, 1, accuracy: 0.001)
        XCTAssertGreaterThan(match, SetOrder.fit(from: place, bpm: 130, key: "8A"), "Further off in tempo")
        XCTAssertGreaterThan(match, SetOrder.fit(from: place, bpm: 124, key: "3B"), "A clashing key")
        XCTAssertGreaterThan(SetOrder.fit(from: place, bpm: 124, key: "9A"), SetOrder.fit(from: place, bpm: 124, key: "3B"), "Next door on the wheel")
    }

    func testASemitonesShiftCountsForSomething() {
        let place = SetOrder.Place(bpm: 124, key: "8A")
        // 3A is a semitone from 8A, seven steps round the wheel. 5A isn't within a semitone of anything next to 8A.
        let shifted = SetOrder.fit(from: place, bpm: 124, key: "3A")
        XCTAssertGreaterThan(shifted, SetOrder.fit(from: place, bpm: 124, key: "5A"))
        XCTAssertLessThan(shifted, SetOrder.fit(from: place, bpm: 124, key: "8A"))
    }

    func testTooFarToStretchScoresNothingForTempo() {
        let place = SetOrder.Place(bpm: 124, key: nil)
        XCTAssertEqual(SetOrder.fit(from: place, bpm: 150, key: nil), 0.2, accuracy: 0.001, "No tempo, and half for the key it doesn't know")
    }

    func testWhatIsntKnownNeitherWinsNorLoses() {
        let place = SetOrder.Place(bpm: 124, key: "8A")
        let unknown = SetOrder.fit(from: place, bpm: nil, key: nil)
        XCTAssertLessThan(unknown, SetOrder.fit(from: place, bpm: 124, key: "8A"))
        XCTAssertGreaterThan(unknown, SetOrder.fit(from: place, bpm: 150, key: "3B"))
    }

    func testPicksTheBestFirstFromWhatsPlaying() {
        let songs = [Song(name: "far", bpm: 150, key: "3B"), Song(name: "near", bpm: 125, key: "8A"), Song(name: "close", bpm: 128, key: "9A")]
        XCTAssertEqual(names(songs, from: .init(bpm: 124, key: "8A")), ["near", "close", "far"])
    }

    func testKeyFollowsTheChainButTempoStaysWhileItCan() {
        // From 8A, 9A's next door, and only from there is 10A next door. The tempo stays at 124 throughout.
        let songs = [Song(name: "ten", bpm: 124, key: "10A"), Song(name: "nine", bpm: 126, key: "9A"), Song(name: "eleven", bpm: 124, key: "11A")]
        XCTAssertEqual(names(songs, from: .init(bpm: 124, key: "8A")), ["nine", "ten", "eleven"])
    }

    func testATrackTooFarAwaySetsTheNewTempo() {
        let songs = [Song(name: "fast", bpm: 150, key: nil), Song(name: "fast too", bpm: 151, key: nil), Song(name: "slow", bpm: 100, key: nil)]
        XCTAssertEqual(names(songs, from: .init(bpm: 150, key: nil)).prefix(2), ["fast", "fast too"])
        // Nothing's close to 100, so what follows it is taken from wherever the chain has reached.
        XCTAssertEqual(names([Song(name: "a", bpm: 100, key: nil), Song(name: "b", bpm: 150, key: nil), Song(name: "c", bpm: 151, key: nil)], from: .init(bpm: 149, key: nil)), ["b", "c", "a"])
    }

    func testWithNowhereToStartTheFirstStaysFirst() {
        let songs = [Song(name: "one", bpm: 150, key: nil), Song(name: "two", bpm: 124, key: nil), Song(name: "three", bpm: 151, key: nil)]
        XCTAssertEqual(names(songs, from: nil), ["one", "three", "two"])
    }

    func testTiesKeepTheListsOrder() {
        let songs = [Song(name: "a", bpm: 124, key: "8A"), Song(name: "b", bpm: 124, key: "8A"), Song(name: "c", bpm: 124, key: "8A")]
        XCTAssertEqual(names(songs, from: .init(bpm: 124, key: "8A")), ["a", "b", "c"])
    }

    func testAHugeListKeepsEverythingAndDoesntHang() {
        let songs = (0..<2000).map { Song(name: "\($0)", bpm: 120 + Double($0 % 12), key: "\($0 % 12 + 1)A") }
        let start = Date()
        let out = names(songs, from: .init(bpm: 124, key: "8A"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "It runs on the main thread, in an unoptimised build here")
        XCTAssertEqual(Set(out).count, 2000, "Nothing's lost past the end of the chain")
        let chain = Set(out.prefix(300))
        XCTAssertEqual(Array(out.suffix(1700)), songs.map(\.name).filter { !chain.contains($0) }, "What's left stays in the list's order")
    }

    func testTheTableAgreesWithTheRules() {
        // The long way and the lookup have to give the same answer, on every pair of keys.
        let keys = (1...12).flatMap { ["\($0)A", "\($0)B"] }
        for from in keys {
            let songs = keys.map { Song(name: $0, bpm: nil, key: $0) }
            let best = names(songs, from: .init(bpm: nil, key: from))[0]
            let top = keys.map { SetOrder.fit(from: .init(bpm: nil, key: from), bpm: nil, key: $0) }.max()
            XCTAssertEqual(SetOrder.fit(from: .init(bpm: nil, key: from), bpm: nil, key: best), top, "From \(from)")
        }
    }
}
