import SwiftUI
import XCTest
@testable import Cheeks

/// Every knob, key and fader cap is drawn once. It has to be real pixels by the time it's handed back: an image that's
/// still to be drawn on the GPU was what held the app up for about 20 s when it first opened on a phone.
@MainActor
final class BakedPartTests: XCTestCase {
    private func pixels(_ image: UIImage) throws -> (bytes: UnsafePointer<UInt8>, width: Int, height: Int, perRow: Int, keep: CFData) {
        let cg = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cg.dataProvider?.data)
        return (CFDataGetBytePtr(data), cg.width, cg.height, cg.bytesPerRow, data)
    }

    func testAPartIsRealPixelsAtThreeTimesItsSize() throws {
        let image = Baked.image("test-solid-\(UUID())") { Color(red: 1, green: 0, blue: 0).frame(width: 10, height: 10) }
        XCTAssertEqual(image.scale, 3)
        let got = try pixels(image)
        XCTAssertEqual(got.width, 30)
        XCTAssertEqual(got.height, 30)
        let middle = got.bytes + 15 * got.perRow + 15 * 4
        XCTAssertGreaterThan(middle[2], 200, "Red")
        XCTAssertLessThan(middle[0], 30, "Blue")
        XCTAssertEqual(middle[3], 255, "Solid")
        withExtendedLifetime(got.keep) {}
    }

    func testAPartIsTheRightWayUp() throws {
        let image = Baked.image("test-upright-\(UUID())") {
            VStack(spacing: 0) {
                Color(red: 1, green: 0, blue: 0).frame(width: 10, height: 5)
                Color(red: 0, green: 0, blue: 1).frame(width: 10, height: 5)
            }
        }
        let got = try pixels(image)
        XCTAssertGreaterThan((got.bytes + 2 * got.perRow + 15 * 4)[2], 200, "Red's on top")
        XCTAssertGreaterThan((got.bytes + 27 * got.perRow + 15 * 4)[0], 200, "Blue's underneath")
        withExtendedLifetime(got.keep) {}
    }

    func testABlurStillGlows() throws {
        let image = Baked.image("test-glow-\(UUID())") {
            Color.white.frame(width: 10, height: 10).blur(radius: 4).padding(10).frame(width: 30, height: 30)
        }
        let got = try pixels(image)
        // Just outside the square, where only the blur can reach.
        let outside = got.bytes + 45 * got.perRow + 25 * 4
        XCTAssertGreaterThan(outside[3], 10, "The glow's what a lit key is made of")
        withExtendedLifetime(got.keep) {}
    }

    func testPartsTakeNoTime() {
        let started = CACurrentMediaTime()
        for i in 0..<60 {
            _ = Baked.image("test-speed-\(i)-\(UUID())") {
                RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44).blur(radius: 2)
            }
        }
        XCTAssertLessThan(CACurrentMediaTime() - started, 3, "It's a few milliseconds each, and the screen builds dozens of them at launch")
    }
}
