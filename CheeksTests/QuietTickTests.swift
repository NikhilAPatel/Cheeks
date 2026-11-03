import Observation
import XCTest
@testable import Cheeks

/// A tick runs 30 times a second. Anything it "changes" with no real change has everything looking at it redraw all the time,
/// which is how a screen with nothing moving came to take 15% of a core.
@MainActor
final class QuietTickTests: XCTestCase {
    func testADeckAtRestChangesNothing() {
        let deck = Deck(index: 0)
        var changed = false
        withObservationTracking {
            _ = deck.activeFX
            _ = deck.fxOn
            _ = deck.echoingOut
            _ = deck.isPlaying
            _ = deck.loopActive
            _ = deck.loopArmed
            _ = deck.loopMarks
            _ = deck.clockTenths
            _ = deck.stemStatus
        } onChange: {
            changed = true
        }
        for _ in 0..<5 { deck.tick() }
        XCTAssertFalse(changed)
    }

    func testAnEngineAtRestChangesNothingOnItsDecks() {
        let dj = DJEngine(library: Library())
        dj.stopRealtimeForTesting()
        var changed = false
        withObservationTracking {
            for deck in dj.decks {
                _ = deck.activeFX
                _ = deck.padMode
                _ = deck.shift
            }
            _ = dj.limiterWorking
            _ = dj.masterIndex
            _ = dj.sampler.sounding
            _ = dj.autoDJ.phase
        } onChange: {
            changed = true
        }
        for _ in 0..<5 { dj.tickForTesting() }
        XCTAssertFalse(changed)
    }
}
