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

    /// Upright on the folded Duo, `Done` and the title went on scrolling, leaving only a swipe down to get out.
    func testSettingsKeepsItsDoneWhenItScrolls() throws {
        for way in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = way
            sleep(2)
            press(button("Settings"))
            let done = app.buttons["Done"].firstMatch
            waitFor(done)
            let list = app.collectionViews.firstMatch
            waitFor(list)
            list.swipeUp()
            list.swipeUp()
            sleep(2)
            screenshot("settings-scrolled-\(way == .portrait ? "upright" : "side")")
            XCTAssertTrue(done.exists && done.isHittable, "\(way == .portrait ? "Upright" : "On its side"), Done should still be there")
            done.tap()
            sleep(1)
        }
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

    /// It's as tall as what's in it now, so what's at the bottom of it has to fit. And `SPLIT` was left on for 22 minutes, with
    /// nothing outside the sheet to say so.
    func testTheMixerSheetFitsAndSplitShowsOutsideIt() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            press(button("More mixer controls"))
            let last = app.staticTexts["The key with the arrows chooses what each deck's fourth knob does."]
            waitFor(last)
            press(button("SPLIT"))
            sleep(1)
            screenshot("mixer-sheet-split-\(orientation.rawValue)")
            let window = app.windows.firstMatch.frame
            XCTAssertLessThanOrEqual(last.frame.maxY, window.maxY - 8, "Its last line should be on the screen")
            // On its side it filled the screen, with half of that empty and none of the waveforms showing.
            let heading = app.staticTexts["Mixer"].firstMatch
            print("UITEST: mixer sheet starts at \(heading.frame.minY) of \(window.height), upright: \(orientation == .portrait)")
            XCTAssertGreaterThan(heading.frame.minY, 60, "It should leave what's above it showing")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
            screenshot("mixer-key-split-\(orientation.rawValue)")
            press(button("More mixer controls"))
            waitFor(last)
            press(button("SPLIT"))
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

    /// The one thing in that menu someone's there for in a hurry, and on a phone on its side it was below the fold.
    func testBackToItsOwnSpeedIsAtTheTopOfItsMenu() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        loadDeck1()
        press(button("Show jog, deck 1"))
        sleep(1)
        let fader = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Tempo'")).firstMatch
        waitFor(fader)
        let cap = fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        cap.press(forDuration: 0.05, thenDragTo: cap.withOffset(CGVector(dx: 0, dy: 20)), withVelocity: .default, thenHoldForDuration: 0.1)
        sleep(1)
        button("Beat grid").tap()
        let back = app.buttons["Back to Its Own Speed"].firstMatch
        waitFor(back, seconds: 3)
        screenshot("bpm-menu")
        XCTAssertTrue(back.isHittable, "It should be there without scrolling")
        XCTAssertLessThan(back.frame.minY, app.buttons["Double the Reading"].firstMatch.frame.minY)
        back.tap()
        sleep(1)
        press(button("Show pads, deck 1"))
    }

    /// A first-time user held a row in their playlist and dragged it. It lifted, and nothing changed.
    func testSeveralTracksCanGoInAPlaylistAtOnce() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        openBrowser()
        let rows = app.collectionViews.firstMatch.cells
        waitFor(rows.firstMatch)
        XCTAssertGreaterThanOrEqual(rows.count, 2, "It takes two")
        rows.element(boundBy: 0).press(forDuration: 1.2)
        let several = app.buttons["Choose Several"].firstMatch
        waitFor(several, seconds: 3)
        several.tap()
        let done = button("Done choosing")
        waitFor(done, seconds: 3)
        sleep(1)
        XCTAssertTrue(app.staticTexts["1 track chosen."].exists, "The row it came from is the first one in")
        screenshot("several-one")
        // Anywhere on a row but its load keys.
        rows.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["2 tracks chosen."].exists)
        screenshot("several-two")
        // And into a new playlist, which opens with them in it.
        let add = button("Add to")
        press(add)
        let new = app.buttons["New Playlist…"].firstMatch
        waitFor(new, seconds: 3)
        new.tap()
        let name = app.alerts.textFields.firstMatch
        waitFor(name, seconds: 3)
        name.typeText("Several test")
        app.alerts.buttons["Create"].tap()
        sleep(1)
        XCTAssertFalse(done.exists, "It's over")
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(app.staticTexts["Added 2 tracks to Several test."].exists)
        screenshot("several-added")
        // A slip here would be a lot to take out one at a time.
        press(button("Undo"))
        sleep(1)
        XCTAssertEqual(rows.count, 0, "They've gone from the playlist")
    }

    func testAPlaylistsRowsCanBeDraggedIntoAnotherOrder() throws {
        guard app.windows.firstMatch.frame.width < 900 else { throw XCTSkip("This screen uses the full layout") }
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        defer { XCUIDevice.shared.orientation = .landscapeLeft }
        openBrowser()
        let menu = button("Playlists")
        press(menu)
        let new = app.buttons["New playlist…"].firstMatch
        waitFor(new, seconds: 3)
        new.tap()
        let name = app.alerts.textFields.firstMatch
        waitFor(name, seconds: 3)
        name.typeText("Order test")
        app.alerts.buttons["Create"].tap()
        sleep(1)

        // Two tracks into it.
        press(menu)
        let all = app.buttons["All Tracks"].firstMatch
        waitFor(all, seconds: 3)
        all.tap()
        sleep(1)
        let rows = app.collectionViews.firstMatch.cells
        waitFor(rows.firstMatch)
        XCTAssertGreaterThanOrEqual(rows.count, 2, "It takes two")
        for row in 0..<2 {
            rows.element(boundBy: row).press(forDuration: 1.2)
            let add = app.buttons["Add to Playlist"].firstMatch
            waitFor(add, seconds: 3)
            add.tap()
            let target = app.buttons["Order test"].firstMatch
            waitFor(target, seconds: 3)
            target.tap()
            sleep(1)
        }

        press(menu)
        let playlist = app.buttons["Order test"].firstMatch
        waitFor(playlist, seconds: 3)
        playlist.tap()
        sleep(1)
        func titles() -> [String] {
            (0..<rows.count).map { row in rows.element(boundBy: row).staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "|") }
        }
        let before = titles()
        XCTAssertEqual(before.count, 2)
        rows.element(boundBy: 0).press(forDuration: 1.2)
        let change = app.buttons["Change the Order"].firstMatch
        waitFor(change, seconds: 3)
        screenshot("playlist-row-menu")
        change.tap()
        let done = button("Done changing the order")
        waitFor(done, seconds: 3)
        sleep(1)
        screenshot("playlist-handles")
        // The handles are at the end of each row.
        let handle = rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.925, dy: 0.5))
        handle.press(forDuration: 0.4, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: 70)), withVelocity: XCUIGestureVelocity(60), thenHoldForDuration: 0.5)
        sleep(1)
        screenshot("playlist-dragged")
        XCTAssertEqual(titles(), Array(before.reversed()), "The dragged row should have changed places")
        press(done)
        sleep(1)
        XCTAssertFalse(done.exists, "It's over")

        // Sliding from a hold lands here, trying to drag a row. It went with no word and no way back.
        let reordered = titles()
        rows.element(boundBy: 0).press(forDuration: 1.2)
        let remove = app.buttons["Remove from Playlist"].firstMatch
        waitFor(remove, seconds: 3)
        remove.tap()
        sleep(1)
        XCTAssertEqual(rows.count, 1)
        screenshot("playlist-removed")
        press(button("Undo"))
        sleep(1)
        XCTAssertEqual(titles(), reordered, "It's back where it was")

        press(menu)
        let delete = app.buttons["Delete Playlist"].firstMatch
        waitFor(delete, seconds: 3)
        delete.tap()
        sleep(1)
        closeBrowser()
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
