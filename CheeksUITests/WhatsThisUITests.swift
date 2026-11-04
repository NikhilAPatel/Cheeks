import XCTest

/// `?` on the top bar: touching a control says what it does, and doesn't do it.
final class WhatsThisUITests: CheeksUITestCase {
    private static let missing = "There's no note on this one yet."
    private var helpKey: XCUIElement { button("What does this do?") }
    private var note: XCUIElement { app.descendants(matching: .any)["whatsThisNote"].firstMatch }

    /// One look at the whole screen. Asking each element in turn takes minutes on a phone.
    private func buttonsOnScreen() throws -> [String] {
        let window = app.windows.firstMatch.frame
        var found = [String]()
        func walk(_ element: XCUIElementSnapshot) {
            if element.elementType == .button, !element.label.isEmpty, !element.frame.isEmpty, window.intersects(element.frame) {
                found.append(element.label)
            }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        return found
    }

    private func showKeysBesideJog() {
        let jog = button("Show jog, deck 1")
        if jog.exists {
            press(jog)
            usleep(300_000)
        }
    }

    func testAskingAboutAControlDoesntPressIt() throws {
        loadDeck1()
        showKeysBesideJog()
        let slip = button("SLIP")
        waitFor(slip)
        let wasOn = slip.isSelected

        press(helpKey)
        waitFor(note)
        XCTAssertTrue(note.label.contains("Press ? again"), note.label)
        screenshot("whats-this-opening")

        press(slip)
        usleep(300_000)
        print("UITEST: note says \(note.label)")
        XCTAssertTrue(note.label.contains("keeps running"), note.label)
        XCTAssertEqual(slip.isSelected, wasOn, "Asking about SLIP doesn't change it")
        screenshot("whats-this-slip")

        // The biggest thing it could get wrong: a deck that starts because someone asked what PLAY is.
        press(button("Play"))
        usleep(300_000)
        XCTAssertTrue(note.label.contains("Starts and stops"), note.label)
        XCTAssertTrue(button("Play").exists, "Asking about PLAY doesn't start the deck")
        XCTAssertFalse(button("Pause").exists)

        press(helpKey)
        usleep(500_000)
        XCTAssertFalse(note.exists, "Pressing it again goes back to mixing")
        press(slip)
        usleep(300_000)
        XCTAssertNotEqual(slip.isSelected, wasOn, "And the key's a key again")
        press(slip)
    }

    /// The first time someone's likely to wonder, nothing's loaded yet.
    func testAnEmptyDeckStillExplainsItself() throws {
        press(helpKey)
        waitFor(note)
        let crossfader = app.descendants(matching: .any)["Crossfader"].firstMatch
        waitFor(crossfader)
        press(crossfader)
        usleep(300_000)
        XCTAssertTrue(note.label.contains("Slides the mix"), note.label)
        press(button("Cue"))
        usleep(300_000)
        XCTAssertTrue(note.label.contains("marks this spot"), "An empty deck explains CUE rather than asking for a track: \(note.label)")
        press(helpKey)
    }

    func testPagesStillChangeAndSayWhatTheyAre() throws {
        press(helpKey)
        waitFor(note)
        press(button("Fx pads"))
        usleep(300_000)
        XCTAssertTrue(note.label.contains("Twelve effects"), note.label)
        waitFor(button("Echo"), seconds: 3)
        press(button("Echo"))
        usleep(300_000)
        XCTAssertTrue(note.label.contains("Repeats what's playing"), note.label)
        press(button("Cue pads"))
        press(helpKey)
    }

    func testTheBrowserExplainsItselfToo() throws {
        press(helpKey)
        waitFor(note)
        press(button("Browser"))
        sleep(1)
        XCTAssertTrue(note.label.contains("Your music"), note.label)
        let next = button("Best next first")
        waitFor(next)
        let wasOn = next.isSelected
        press(next)
        usleep(300_000)
        XCTAssertTrue(note.label.contains("good order"), note.label)
        XCTAssertEqual(next.isSelected, wasOn, "Asking about NEXT doesn't reorder the list")
        screenshot("whats-this-browser")
        press(button("Browser"))
        sleep(1)
        press(helpKey)
    }

    /// Everything you can press, on every page: each one has a note, and none of them starts the deck.
    func testEveryControlOnEveryPageHasANote() throws {
        loadDeck1()
        press(helpKey)
        waitFor(note)
        var asked = Set<String>()
        var missing = [String]()

        func askEverythingOnScreen() throws {
            for label in try buttonsOnScreen() {
                // These still do what they do, which is go somewhere.
                let goesSomewhere = label.hasSuffix(" pads") || ["Browser", "What does this do?", "More mixer controls", "More pad pages"].contains(label)
                    || label.hasPrefix("Show ")
                if goesSomewhere || !asked.insert(label).inserted { continue }
                press(button(label), seconds: 0.05)
                if note.label.contains(Self.missing) { missing.append(label) }
            }
        }

        try askEverythingOnScreen()
        for page in ["Mem pads", "Loop pads", "Roll pads", "Slicer pads", "Jump pads", "Stems pads", "Fx pads", "Sample pads"] {
            let tab = button(page)
            if tab.exists {
                press(tab)
                usleep(200_000)
                try askEverythingOnScreen()
            }
        }
        for _ in 0..<4 {
            let more = button("More pad pages")
            if more.exists {
                press(more)
                usleep(200_000)
                try askEverythingOnScreen()
            }
        }
        let jog = button("Show jog, deck 1")
        if jog.exists {
            press(jog)
            usleep(200_000)
            try askEverythingOnScreen()
        }

        // Knobs and faders aren't buttons.
        for name in ["Hi", "Mid", "Low", "Crossfader", "Channel 1 fader", "Tempo", "Jog wheel"] {
            let element = app.descendants(matching: .any)[name].firstMatch
            guard element.exists, element.isHittable else { continue }
            asked.insert(name)
            press(element, seconds: 0.05)
            if note.label.contains(Self.missing) { missing.append(name) }
        }

        print("UITEST: asked about \(asked.count) controls: \(asked.sorted().joined(separator: ", "))")
        print("UITEST: no note on \(missing)")
        XCTAssertEqual(missing, [], "No note on these")
        XCTAssertGreaterThan(asked.count, 30, "It should have found most of the screen")
        XCTAssertTrue(button("Play").exists, "None of that started the deck")
        press(helpKey)
    }
}
