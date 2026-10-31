import XCTest

/// Drives the real app with real touch events, the way a finger would, through the system's event
/// path rather than calling into the app. Tracks have to be in the app's Documents folder first:
/// `tools/ui-tests.sh` does that and runs these.
class CheeksUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        // The app's landscape only. A simulator that thinks it's upright reports frames sideways.
        if app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(1)
        }
        // The sampler's sounds and the launch sweep settle down in the first moments.
        sleep(2)
    }

    func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    /// A press long enough for anything to register, rather than the 10 ms tap XCTest defaults to.
    func press(_ element: XCUIElement, seconds: TimeInterval = 0.12) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: seconds)
    }

    func waitFor(_ element: XCUIElement, seconds: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: seconds), "\(element) never appeared", file: file, line: line)
    }

    /// Saves what's on screen where the script can find it, if it asked for that.
    func screenshot(_ name: String) {
        // The window rather than the main screen: on the Duo, that's the cover screen, which is off.
        let png = app.windows.firstMatch.screenshot().pngRepresentation
        if let directory = ProcessInfo.processInfo.environment["CHEEKS_UI_SHOTS"] {
            try? png.write(to: URL(filePath: directory).appending(path: name + ".png"))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Opens the browser if it isn't open.
    func openBrowser() {
        if !app.staticTexts["IMPORT"].exists && !app.buttons["IMPORT"].exists {
            press(button("Browser"))
        }
        sleep(1)
    }

    func closeBrowser() {
        press(button("Browser"))
        sleep(1)
    }

    /// Makes sure deck 1 has a track on it, stopped, with an empty hot cue A.
    func loadDeck1() {
        openBrowser()
        let loadKeys = app.buttons.matching(NSPredicate(format: "label == '1'"))
        waitFor(loadKeys.firstMatch, seconds: 30)
        press(loadKeys.firstMatch)
        closeBrowser()
        sleep(1)
    }
}
