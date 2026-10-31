import XCTest

/// Holds the app in each state for `tools/measure-cpu.sh` to measure from outside. Opt-in, as it
/// takes minutes and checks nothing itself: run it with TEST_RUNNER_CHEEKS_UI_MEASURE=/path/to/file.
final class MeasureStates: CheeksUITestCase {
    private func enter(_ state: String, seconds: UInt32 = 50) {
        if let path = ProcessInfo.processInfo.environment["CHEEKS_UI_MEASURE"] {
            try? state.write(toFile: path, atomically: true, encoding: .utf8)
        }
        sleep(seconds)
    }

    func testHoldStates() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CHEEKS_UI_MEASURE"] == nil)
        enter("idle", seconds: 40)
        openBrowser()
        let loadOne = app.buttons.matching(NSPredicate(format: "label == '1'"))
        let loadTwo = app.buttons.matching(NSPredicate(format: "label == '2'"))
        waitFor(loadOne.firstMatch, seconds: 30)
        press(loadOne.element(boundBy: 0))
        sleep(2)
        press(loadTwo.element(boundBy: 1))
        closeBrowser()
        sleep(8)
        enter("two loaded, paused")
        let plays = app.buttons.matching(NSPredicate(format: "label == 'Play'"))
        press(plays.element(boundBy: 0))
        enter("one playing")
        press(app.buttons.matching(NSPredicate(format: "label == 'Play'")).firstMatch)
        let syncs = app.buttons.matching(NSPredicate(format: "label == 'BEAT SYNC'"))
        press(syncs.element(boundBy: 1))
        enter("both playing, synced, stretched")
        try? "done".write(toFile: ProcessInfo.processInfo.environment["CHEEKS_UI_MEASURE"]!, atomically: true, encoding: .utf8)
    }
}
