import XCTest

/// Every iPhone gets a compact layout, on its side or upright. This runs on a real iPhone simulator, turns it both ways,
/// and checks that everything you can press is really on the screen, on every pad page.
final class PhoneLayoutTests: CheeksUITestCase {
    private func assertEverythingFits(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        // A round key's touch area reaches a little past what it draws.
        let bounds = window.insetBy(dx: -3, dy: -3)
        let buttons = app.buttons.allElementsBoundByIndex
        XCTAssertGreaterThan(buttons.count, 10, "\(context): the controls should be there", file: file, line: line)
        for button in buttons where button.exists && button.isHittable {
            XCTAssertTrue(bounds.contains(button.frame), "\(context): \(button.label) at \(button.frame) is outside \(window)", file: file, line: line)
        }
    }

    private func checkEveryPage(_ name: String) {
        assertEverythingFits(name)
        screenshot("phone-\(name)-cue")
        for page in ["LOOP", "ROLL", "STEMS", "FX"] {
            let tab = app.staticTexts[page].firstMatch
            if tab.exists {
                press(tab)
                usleep(300_000)
                assertEverythingFits("\(name), \(page)")
            }
        }
        screenshot("phone-\(name)-fx")
        for _ in 0..<4 {
            let more = button("More pad pages")
            if more.exists {
                press(more)
                usleep(300_000)
                assertEverythingFits("\(name), more pages")
            }
        }
        let jog = button("Show jog, deck 1")
        if jog.exists {
            press(jog)
            usleep(300_000)
            assertEverythingFits("\(name), jog")
            // Both at once as well: upright, the second deck used to get pushed off the screen.
            press(button("Show jog, deck 2"))
            usleep(300_000)
            assertEverythingFits("\(name), both on the jog")
            screenshot("phone-\(name)-jog")
            press(button("Show pads, deck 2"))
            press(button("Show pads, deck 1"))
        }
        let more = button("More mixer controls")
        if more.exists {
            press(more)
            sleep(1)
            screenshot("phone-\(name)-mixer-sheet")
            XCTAssertTrue(app.staticTexts["Mixer"].waitForExistence(timeout: 3), "\(name): the mixer's other controls should open")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }
    }

    func testEverythingFitsBothWaysUp() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        checkEveryPage("landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.height, app.windows.firstMatch.frame.width, "The app should turn upright")
        checkEveryPage("portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "Turning it mustn't bring anything down")
    }

    func testTheBrowserFitsBothWaysUp() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            openBrowser()
            assertEverythingFits("browser, \(orientation.rawValue)")
            screenshot("phone-browser-\(orientation.rawValue)")
            closeBrowser()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
    }
}
