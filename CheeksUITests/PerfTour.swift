import XCTest

/// A walk round the app for `tools/perf-tour.sh`, which seeds a big library and reads the app's own log of freezes, CPU
/// and memory afterwards. Opt-in, as it takes minutes and checks little itself. It only needs the app to get there.
final class PerfTour: CheeksUITestCase {
    private var logPath: String? { ProcessInfo.processInfo.environment["CHEEKS_UI_PERF"] }

    override var launchEnvironment: [String: String] {
        logPath.map { ["CHEEKS_LAUNCH_LOG": $0] } ?? [:]
    }

    /// Marks in the app's log what's about to happen, so a freeze can be matched to it.
    private func step(_ name: String) {
        guard let logPath, let file = fopen(logPath, "a") else { return }
        fputs("STEP:  \(name)\n", file)
        fclose(file)
    }

    func testTour() throws {
        try XCTSkipIf(logPath == nil)
        step("resting, nothing loaded")
        sleep(6)

        step("open the browser")
        openBrowser()
        waitFor(app.collectionViews.firstMatch, seconds: 30)
        // With a sidebar beside it, the track list's the second one.
        let list = app.collectionViews.count > 1 ? app.collectionViews.element(boundBy: 1) : app.collectionViews.firstMatch
        step("scroll the list, flicking")
        for _ in 0..<6 { list.swipeUp(velocity: .fast) }
        for _ in 0..<6 { list.swipeDown(velocity: .fast) }
        sleep(1)

        step("sort by BPM")
        press(app.buttons["BPM"].firstMatch)
        sleep(1)
        step("sort by title")
        press(app.buttons["TITLE"].firstMatch)
        sleep(1)
        step("back to the list's own order")
        press(app.buttons["TITLE"].firstMatch)
        usleep(500_000)
        press(app.buttons["TITLE"].firstMatch)
        sleep(1)

        step("search, typing")
        let search = app.textFields.firstMatch
        search.tap()
        search.typeText("track 19")
        sleep(1)
        step("clear the search")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "\n")
        sleep(1)

        step("load a real track on each deck")
        search.tap()
        search.typeText("e\n")
        sleep(1)
        let one = app.buttons.matching(NSPredicate(format: "label == '1'")).firstMatch
        let two = app.buttons.matching(NSPredicate(format: "label == '2'")).element(boundBy: 1)
        press(one)
        sleep(3)
        press(two)
        sleep(3)

        step("NEXT on, with a deck loaded")
        press(button("Best next first"))
        sleep(2)
        step("scroll with NEXT on")
        for _ in 0..<4 { list.swipeUp(velocity: .fast) }
        sleep(1)
        step("NEXT off")
        press(button("Best next first"))
        sleep(1)

        step("close the browser")
        closeBrowser()
        sleep(2)

        step("play both, resting")
        for play in app.buttons.matching(NSPredicate(format: "label == 'Play'")).allElementsBoundByIndex.prefix(2) where play.isHittable { press(play) }
        sleep(10)

        step("through the pad pages")
        for page in ["LOOP", "ROLL", "STEMS", "FX", "CUE"] {
            let tab = app.staticTexts[page].firstMatch
            if tab.exists { press(tab) }
            usleep(500_000)
        }
        for _ in 0..<4 {
            let more = button("More pad pages")
            if more.exists { press(more) }
            usleep(500_000)
        }

        step("browser open and closed while playing")
        for _ in 0..<3 {
            press(button("Browser"))
            sleep(1)
            press(button("Browser"))
            sleep(1)
        }

        step("settings, while playing")
        let gear = button("Settings")
        if gear.exists {
            press(gear)
            sleep(2)
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        }

        step("resting at the end, playing")
        sleep(10)
        step("done")
    }
}
