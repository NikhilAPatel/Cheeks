import XCTest

/// Which list a mix is going through was only said once, in a message that goes away.
final class MixLineTests: CheeksUITestCase {
    func testTheBrowserKeepsShowingWhatsBeingMixed() throws {
        openBrowser()
        let loadKeys = app.buttons.matching(NSPredicate(format: "label == '1'"))
        waitFor(loadKeys.firstMatch, seconds: 30)
        press(button("Mix through this list"))
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Mixing through'")).firstMatch
        waitFor(line)
        // Well past the message, which says the same thing.
        sleep(12)
        XCTAssertTrue(line.exists, "It should still say so with the message gone")
        print("UITEST: \(line.label)")
        screenshot("mix-line")
        press(button("Stop the mix"))
        sleep(1)
        XCTAssertFalse(line.exists, "It's only there while a mix is on")
    }
}
