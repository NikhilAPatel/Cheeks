import XCTest

final class MeterTests: CheeksUITestCase {
    /// With nothing playing, opening and closing the browser mustn't move the master meters.
    func testMetersStayDownWhenTheBrowserOpensAndCloses() throws {
        sleep(3) // past the launch sweep
        for step in 0..<4 {
            press(button("Browser"))
            // The sweep this guards against peaks about half a second after the view's built.
            usleep(450_000)
            screenshot("meters-\(step)")
            sleep(1)
        }
    }
}
