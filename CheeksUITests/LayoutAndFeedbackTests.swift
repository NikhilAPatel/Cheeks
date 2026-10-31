import XCTest

final class LayoutAndFeedbackTests: CheeksUITestCase {
    private func anyElement(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func testTheKeyboardLeavesTheMixerAlone() throws {
        openBrowser()
        let trim = anyElement("Trim")
        waitFor(trim)
        let before = trim.frame
        let search = app.textFields.firstMatch
        waitFor(search)
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        screenshot("keyboard-up")
        print("UITEST: trim before \(before), with keyboard \(trim.frame)")
        XCTAssertEqual(trim.frame.minY, before.minY, accuracy: 1, "The mixer mustn't move")
        XCTAssertTrue(search.isHittable, "and the search field has to stay above the keyboard")
        // Get rid of the keyboard for whatever runs next.
        app.typeText("\n")
        closeBrowser()
    }

    func testStoppingARecordingOffersBothAnswers() throws {
        press(button("Record"))
        sleep(2)
        press(button("Stop recording"))
        let keep = app.buttons["Keep recording"]
        waitFor(keep, seconds: 3)
        XCTAssertTrue(app.buttons["Stop and save"].exists)
        screenshot("stop-recording")
        keep.tap()
        sleep(1)
        XCTAssertTrue(button("Stop recording").exists, "Keep recording keeps recording")
        press(button("Stop recording"))
        waitFor(app.buttons["Stop and save"], seconds: 3)
        app.buttons["Stop and save"].tap()
        sleep(1)
        XCTAssertTrue(button("Record").exists)
    }

    func testASoloPadLightsWhileItsSoloed() throws {
        loadDeck1()
        let tab = button("Stems pads")
        waitFor(tab)
        press(tab)
        let solo = button("Solo Drums")
        waitFor(solo)
        XCTAssertFalse(solo.isSelected)
        press(solo)
        sleep(1)
        XCTAssertTrue(solo.isSelected, "The pad shows it's soloed")
        screenshot("solo-lit")
        press(solo)
        sleep(1)
        XCTAssertFalse(solo.isSelected, "and stops when it's let go")
        press(button("Cue pads"))
    }

    func testTheDepthBarCanBeDragged() throws {
        loadDeck1()
        let tab = button("Fx pads")
        waitFor(tab)
        press(tab)
        let depth = anyElement("Depth")
        waitFor(depth)
        let before = depth.value as? String ?? ""
        let start = depth.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: depth.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        sleep(1)
        let after = depth.value as? String ?? ""
        print("UITEST: depth \(before) to \(after), frame \(depth.frame)")
        XCTAssertNotEqual(before, after, "Dragging the bar should change the depth")
        press(button("Cue pads"))
    }

    func testTheHeaderBPMFollowsTheTempo() throws {
        loadDeck1()
        let grid = button("Beat grid")
        let tempo = anyElement("Tempo")
        waitFor(grid)
        waitFor(tempo)
        func bpm() -> Double { Double((grid.value as? String ?? "").replacingOccurrences(of: " BPM", with: "")) ?? 0 }
        func percent() -> Double { Double((tempo.value as? String ?? "").replacingOccurrences(of: " percent", with: "")) ?? 0 }
        let bpmBefore = bpm(), percentBefore = percent()
        XCTAssertGreaterThan(bpmBefore, 0)
        let middle = tempo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: tempo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)))
        sleep(1)
        print("UITEST: \(bpmBefore) BPM at \(percentBefore)% to \(bpm()) BPM at \(percent())%")
        XCTAssertNotEqual(percent(), percentBefore, "The fader should have moved")
        XCTAssertEqual(bpm() / bpmBefore, (100 + percent()) / (100 + percentBefore), accuracy: 0.0015)
        screenshot("header-bpm-moved")
        press(grid)
        sleep(1)
        screenshot("header-bpm-menu")
    }

    func testSlidingOnALatchedEffectLeavesItOn() throws {
        loadDeck1()
        press(button("Fx pads"))
        let echo = button("Echo")
        waitFor(echo)
        press(echo)
        sleep(1)
        XCTAssertTrue(echo.isSelected, "A quick tap latches it")
        echo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: echo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.5)))
        sleep(1)
        XCTAssertTrue(echo.isSelected, "Sliding on it adjusts it, and it stays on")
        press(echo)
        sleep(1)
        XCTAssertFalse(echo.isSelected, "A plain tap still lets it go")
        press(button("Cue pads"))
    }

    func testASliceLeavesNothingForTheSamplerToGrab() throws {
        loadDeck1()
        press(button("Slicer pads"))
        let slice = button("Slice 3")
        waitFor(slice)
        slice.press(forDuration: 1)
        sleep(1)
        press(button("Pause"))
        press(button("Sample pads"))
        waitFor(button("SET"))
        press(button("SET"))
        press(button("Clap"))
        waitFor(app.buttons["Record the Master"], seconds: 5)
        XCTAssertFalse(app.buttons["Grab Deck 1's Loop"].exists, "There's no loop on deck 1 to grab")
        screenshot("sampler-sheet-after-slice")
    }

    func testPadsAndLayoutForALook() throws {
        loadDeck1()
        screenshot("decks-full")
        press(button("Sample pads"))
        sleep(1)
        press(button("Clap"))
        screenshot("sampler-after-tap")
        press(button("Cue pads"))
        openBrowser()
        screenshot("browser-full")
        closeBrowser()
    }
}
