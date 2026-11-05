import XCTest

final class RecordingsTests: CheeksUITestCase {
    /// Plays the first recording. `tools/ui-tests.sh` can't see the app's log, so the script checks it afterwards.
    func testARecordingPlaysAndStops() throws {
        press(button("Recordings"))
        // Named, because the deck's own Play key is behind the sheet.
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play Mix'")).firstMatch
        try XCTSkipUnless(play.waitForExistence(timeout: 5), "No recordings on this simulator")
        print("UITEST: pressing play at \(Date())")
        play.tap()
        let pause = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pause Mix'")).firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 3), "The button should show it's playing")
        screenshot("recordings-playing")
        pause.tap()
        sleep(1)
        print("UITEST: finished at \(Date())")
    }

    /// A grey button with no reason cost a first-time user about 11 minutes, on and off.
    func testARecordingWontPlayOverTheMixAndSaysWhy() throws {
        loadDeck1()
        // One to play, on a simulator that may have none.
        press(button("Record"))
        sleep(2)
        press(button("Stop recording"))
        let save = app.alerts.buttons["Stop and save"]
        waitFor(save)
        save.tap()
        sleep(3)

        press(button("Play"))
        sleep(1)
        press(button("Recordings"))
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play Mix'")).firstMatch
        waitFor(play)
        let reason = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Stop both decks'")).firstMatch
        XCTAssertTrue(reason.exists, "The reason should be there before anyone has to ask")
        XCTAssertTrue(play.isEnabled, "A press gets a reply, so it isn't disabled")
        screenshot("recordings-deck-playing")
        play.tap()
        sleep(1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pause Mix'")).firstMatch.exists, "It would play over the mix")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        press(button("Pause"))
        sleep(1)

        press(button("Recordings"))
        waitFor(play)
        XCTAssertFalse(reason.exists, "With the decks stopped there's nothing to explain")
        play.tap()
        let pause = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pause Mix'")).firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        app.buttons["Done"].firstMatch.tap()
    }
}
