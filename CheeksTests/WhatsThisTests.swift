import XCTest
@testable import Cheeks

/// The notes `?` shows. `WhatsThisUITests` checks the real screens against them, and that asking doesn't act.
@MainActor
final class WhatsThisTests: XCTestCase {
    func testEveryPadPageAndEffectHasANote() {
        for mode in PadMode.allCases {
            XCTAssertNotNil(Explanations.named(mode.rawValue.capitalized + " pads"), mode.rawValue)
        }
        for effect in BeatFX.allCases {
            XCTAssertNotNil(Explanations.named(effect.rawValue.capitalized), effect.rawValue)
        }
    }

    /// The app announces these by name.
    func testEveryMoveHasANote() {
        for move in TransitionMove.allCases {
            XCTAssertNotNil(Explanations.named(move.title.uppercased()), move.title)
        }
    }

    func testAMixersSheetKeepsOneNoteOnScreen() {
        let help = WhatsThis()
        help.toggle()
        help.sheetOpened()
        XCTAssertTrue(help.isInSheet)
        help.note("SLIP")
        help.sheetClosed()
        XCTAssertFalse(help.isInSheet)
        XCTAssertEqual(help.shown, Explanations.opening, "What it said was about something that's gone")
    }

    /// Everything a first-time user couldn't work out by looking, in hands-on round 9.
    func testWhatRoundNineCouldntWorkOutHasANote() {
        let asked = ["Q", "SLIP", "KEY", "KEY SYNC", "MASTER", "Master volume", "BEAT JUMP", "Jump size", "Mem pads", "Slicer pads", "Roll pads", "Jump pads",
                     "DEL", "SPLIT", "CUE/MST", "LEVEL", "LIM", "Color effect", "Color knob", "Tempo range", "RELOOP", "Stem status", "Phase strip",
                     "Best next first", "FX stems", "Echo out", "Shorter"]
        for name in asked {
            XCTAssertNotNil(Explanations.named(name), name)
        }
    }

    /// A first-time user searched for "how do I" and "transition" and got nothing: it calls a transition a move.
    func testTheGuideCanBeSearchedInOrdinaryWords() {
        for words in ["how do I", "transition", "blend"] {
            XCTAssertFalse(Explanations.found(words).isEmpty, words)
        }
        XCTAssertEqual(Explanations.found("").count, Explanations.sections.count)
        XCTAssertTrue(Explanations.found("nothing says this").isEmpty)
    }

    func testNoTwoNotesClaimTheSameName() {
        var seen = Set<String>()
        for entry in Explanations.sections.flatMap(\.entries) {
            for name in entry.names.isEmpty ? [entry.title] : entry.names {
                XCTAssertTrue(seen.insert(name).inserted, "\(name) is on two notes")
            }
        }
    }

    /// The note has to fit a phone's screen beside what it's about, and be read mid-set.
    func testNotesAreShort() {
        for entry in Explanations.sections.flatMap(\.entries) {
            XCTAssertLessThanOrEqual(entry.text.count, 230, entry.title)
            XCTAssertFalse(entry.text.isEmpty, entry.title)
        }
    }

    func testTheNoteOnlyChangesWhileItsOn() {
        let help = WhatsThis()
        help.note("SLIP")
        XCTAssertEqual(help.shown, Explanations.opening, "With ? off, moving between pages says nothing")
        help.toggle()
        XCTAssertTrue(help.isOn)
        XCTAssertEqual(help.shown, Explanations.opening)
        help.note("SLIP")
        XCTAssertEqual(help.shown.title, "SLIP")
        help.toggle()
        XCTAssertFalse(help.isOn)
        XCTAssertEqual(help.shown, Explanations.opening, "It starts afresh next time")
    }

    func testANoteGoesWhereTheFingerWasnt() {
        let help = WhatsThis()
        help.toggle()
        help.explain("SLIP", at: CGPoint(x: 0.9, y: 0.2))
        XCTAssertEqual(help.touch, CGPoint(x: 0.9, y: 0.2))
    }

    func testANameThatsNotThereSaysSoRatherThanNothing() {
        let help = WhatsThis()
        help.toggle()
        help.explain("Something new", at: .zero)
        XCTAssertEqual(help.shown.text, Explanations.missing)
    }

    /// The capsule's time starts afresh when a message is said again, or one press in two looks ignored.
    func testTheSameWordsSaidAgainCountAsNew() {
        let dj = DJEngine(library: Library())
        let before = dj.statusSerial
        dj.say("There's no track on deck 1 yet.", .refused)
        let once = dj.statusSerial
        XCTAssertGreaterThan(once, before)
        dj.say("There's no track on deck 1 yet.", .refused)
        XCTAssertGreaterThan(dj.statusSerial, once)
    }

    func testACueThatCantBeHeardSaysSo() {
        let dj = DJEngine(library: Library())
        dj.splitCue = false
        dj.toggleCue(dj.decks[0])
        XCTAssertTrue(dj.decks[0].headphoneCue)
        XCTAssertEqual(dj.statusMessage, "You'll hear the cue with SPLIT on and a splitter cable.")
        dj.statusMessage = nil
        dj.toggleCue(dj.decks[0])
        XCTAssertFalse(dj.decks[0].headphoneCue)
        XCTAssertNil(dj.statusMessage, "Turning it off has nothing to explain")
        dj.splitCue = true
        dj.toggleCue(dj.decks[0])
        XCTAssertTrue(dj.decks[0].headphoneCue)
        XCTAssertNil(dj.statusMessage, "With SPLIT on, it can be heard")
    }
}
