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

    /// Round 15: a sheet's own drag took the touch after about 10 pt, so 120 pt on MASTER moved it nothing at all, and these
    /// are the only TRIM and MASTER a phone has. Down is the sheet's way of closing, so that's the hard direction.
    func testTheMixerSheetsKnobsTurn() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            press(button("More mixer controls"))
            XCTAssertTrue(app.staticTexts["Mixer"].waitForExistence(timeout: 3))
            sleep(1)
            for name in ["Master", "Trim 1", "Trim 2", "Level"] {
                let knob = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
                waitFor(knob)
                let before = percent(knob)
                // Whichever way it has room, as they stay where the last pass left them.
                let drag = before > 50 ? 60.0 : -60.0
                let from = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: drag)), withVelocity: .default, thenHoldForDuration: 0.1)
                usleep(300_000)
                print("UITEST: \(orientation.rawValue) \(name) \(before) to \(percent(knob))")
                XCTAssertGreaterThan(abs(percent(knob) - before), 15, "\(name) should turn with the finger")
                XCTAssertTrue(app.staticTexts["Mixer"].exists, "and the sheet should stay put")
            }
            screenshot("mixer-sheet-\(orientation.rawValue)")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }
    }

    /// Round 17: on its side it was 39 pt too tall, so a flick moved its rows under a finger, and that cost a first-time user
    /// two wrong rows, one of which recorded over a pad.
    func testTheSamplersSheetFitsOnItsSide() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        for _ in 0..<4 {
            press(button("More pad pages"))
            usleep(300_000)
            if button("SET").exists { break }
        }
        press(button("SET"))
        usleep(300_000)
        press(button("Air Horn"))
        let footer = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Samples can be'")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 3), "The pad's sheet should open")
        sleep(1)
        screenshot("sampler-sheet-landscape")
        let window = app.windows.firstMatch.frame
        print("UITEST: sampler sheet's last line ends at \(footer.frame.maxY) of \(window.height)")
        XCTAssertLessThanOrEqual(footer.frame.maxY, window.height, "Everything in it should be on the screen without scrolling")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
    }

    private func percent(_ knob: XCUIElement) -> Int {
        Int((knob.value as? String)?.split(separator: " ").first ?? "") ?? -1
    }

    /// The note says a playlist can be renamed, and held upright there's no sidebar to hold it in. Holding it in the menu just chose it.
    func testHeldUprightAPlaylistCanStillBeRenamedAndDeleted() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        openBrowser()
        let menu = button("Playlists")
        press(menu)
        let new = app.buttons["New playlist…"].firstMatch
        waitFor(new, seconds: 3)
        XCTAssertFalse(app.buttons["Rename Playlist"].exists, "With All Tracks showing there's nothing to rename")
        new.tap()
        let name = app.alerts.textFields.firstMatch
        waitFor(name, seconds: 3)
        name.typeText("Upright test")
        app.alerts.buttons["Create"].tap()
        sleep(1)

        press(menu)
        let rename = app.buttons["Rename Playlist"].firstMatch
        waitFor(rename, seconds: 3)
        screenshot("phone-upright-playlist-menu")
        rename.tap()
        let newName = app.alerts.textFields.firstMatch
        waitFor(newName, seconds: 3)
        XCTAssertEqual(newName.value as? String, "Upright test")
        app.alerts.buttons["Cancel"].tap()
        sleep(1)

        press(menu)
        let delete = app.buttons["Delete Playlist"].firstMatch
        waitFor(delete, seconds: 3)
        delete.tap()
        sleep(1)
        press(menu)
        waitFor(new, seconds: 3)
        XCTAssertFalse(app.buttons["Upright test"].exists, "It's gone")
        XCTAssertFalse(app.buttons["Rename Playlist"].exists, "And it's back on All Tracks")
        app.tap()
        sleep(1)
        closeBrowser()
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
