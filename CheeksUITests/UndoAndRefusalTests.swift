import XCTest

final class UndoAndRefusalTests: CheeksUITestCase {
    /// Sets hot cue A if needed, deletes it, and returns the Undo button.
    private func deleteHotCue() -> XCUIElement {
        let hotCue = button("Hot cue A")
        if !hotCue.exists {
            let setCue = button("Set hot cue A")
            waitFor(setCue)
            press(setCue)
        }
        waitFor(hotCue)
        press(button("DEL"))
        press(hotCue)
        let undo = app.buttons["Undo"].firstMatch
        waitFor(undo, seconds: 3)
        return undo
    }

    private func attempt(_ name: String, _ tapIt: (XCUIElement) -> Void) {
        let undo = deleteHotCue()
        let frame = undo.frame
        tapIt(undo)
        sleep(1)
        print("UITEST: \(name): frame \(frame), capsule gone \(!app.buttons["Undo"].exists), cue back \(button("Hot cue A").exists)")
        if !button("Hot cue A").exists {
            // Leave it so the next attempt can run: the capsule goes by itself.
            sleep(6)
        }
    }

    func testUndoVariations() throws {
        loadDeck1()
        attempt("paused, tap") { $0.tap() }
        attempt("paused, 0.25 s press") { self.press($0, seconds: 0.25) }
        attempt("paused, 0.01 s press") { self.press($0, seconds: 0.01) }
        press(button("Play"))
        sleep(2)
        screenshot("d3-playing")
        attempt("playing, tap") { $0.tap() }
        attempt("playing, 0.25 s press") { self.press($0, seconds: 0.25) }
        attempt("playing, 0.12 s press") { self.press($0, seconds: 0.12) }
        attempt("playing, 0.01 s press") { self.press($0, seconds: 0.01) }
        press(button("Pause"))
    }
}
