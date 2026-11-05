import SwiftUI
import XCTest
@testable import Cheeks

/// Every hands-on round ran at the system's default text size, and a lot of people's phones aren't.
@MainActor
final class TextSizeTests: XCTestCase {
    private func size(of view: some View, at text: DynamicTypeSize) -> CGSize {
        UIHostingController(rootView: view.dynamicTypeSize(text)).sizeThatFits(in: CGSize(width: 2000, height: 2000))
    }

    func testThePanelsLegendsStayTheSizeTheyWerePrinted() {
        for font in [Theme.silk(10), Theme.digits(10)] {
            let label = Text("MASTER 124.00").font(font)
            XCTAssertEqual(size(of: label, at: .large), size(of: label, at: .accessibility5))
            XCTAssertEqual(size(of: label, at: .large), size(of: label, at: .xSmall))
        }
    }

    /// Nothing's been laid out for less than the smallest phone, and the decks have fixed widths.
    func testAnIPadsWindowCantGetSmallerThanTheSmallestPhone() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        guard let restrictions = scene.sizeRestrictions else { throw XCTSkip("Only an iPad's windows can change size") }
        ScreenLayout.keepWindowsBigEnough()
        XCTAssertEqual(restrictions.minimumSize, CGSize(width: 375, height: 667))
    }
}
