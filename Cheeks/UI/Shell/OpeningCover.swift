import SwiftUI

/// The launch screen's logo, in the same place, carried on until the first screen's built and then faded away, so
/// opening the app never shows a blank screen. The launch screen itself is `UILaunchScreen` in `Config/Info.plist`.
struct OpeningCover: View {
    var body: some View {
        // The whole lot ignores the safe area, or the logo's centred in that and sits higher than the launch screen's.
        Color("AccentColor")
            .overlay { Image("LaunchLogo").accessibilityHidden(true) }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
