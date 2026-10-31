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
}
