import XCTest

final class UndoAndRefusalTests: CheeksUITestCase {
    /// Sets hot cue A if needed, deletes it, and returns the Undo button.
    private func deleteHotCue() -> XCUIElement {
        let hotCue = button("Hot cue A")
        if !hotCue.exists {
            let setCue = button("Set hot cue A")
            waitFor(setCue)
            press(setCue)
        }
        waitFor(hotCue)
        press(button("DEL"))
        press(hotCue)
        let undo = app.buttons["Undo"].firstMatch
        waitFor(undo, seconds: 3)
        return undo
    }

    func testUndoBringsADeletedHotCueBackWhetherPausedOrPlaying() throws {
        loadDeck1()
        for playing in [false, true] {
            if playing {
                press(button("Play"))
                sleep(1)
            }
            let undo = deleteHotCue()
            screenshot("undo-capsule-\(playing ? "playing" : "paused")")
            XCTAssertFalse(button("Hot cue A").exists, "It's deleted first")
            undo.tap()
            sleep(1)
            XCTAssertTrue(button("Hot cue A").exists, "The cue should be back")
            XCTAssertFalse(app.buttons["Undo"].exists, "and the capsule gone")
        }
        press(button("Pause"))
    }

    func testUndoTakesATouchJustPastItsEdge() throws {
        loadDeck1()
        let undo = deleteHotCue()
        undo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -4)).press(forDuration: 0.12)
        sleep(1)
        XCTAssertTrue(button("Hot cue A").exists, "4 pt above the key still counts")
    }

    func testTheCapsuleStaysClearOfTheMasterTempo() throws {
        loadDeck1()
        let undo = deleteHotCue()
        let master = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'MASTER'")).firstMatch
        waitFor(master)
        print("UITEST: master \(master.frame), undo \(undo.frame)")
        // The whole capsule sits to the right of the readout, whose number ends about 60 pt past its label.
        XCTAssertGreaterThan(undo.frame.minX, master.frame.maxX + 60)
        undo.tap()
    }

    func testPressingALoadKeyForAPlayingDeckSaysWhyNot() throws {
        loadDeck1()
        press(button("Play"))
        sleep(1)
        openBrowser()
        let keys = app.buttons.matching(NSPredicate(format: "label == '1'"))
        waitFor(keys.firstMatch)
        XCTAssertGreaterThanOrEqual(keys.count, 2, "Needs a second track to try loading")
        // Whichever row isn't the loaded track: the second key may be either, and neither should load.
        press(keys.element(boundBy: 1))
        let message = app.staticTexts["Deck 1 is playing. Stop it first."]
        XCTAssertTrue(message.waitForExistence(timeout: 2), "A refusal has to say why")
        screenshot("c5-refused")
        closeBrowser()
        press(button("Pause"))
    }
}
