import SwiftUI

/// A professional instrument: rekordbox's black screens set into a matte control surface, with a
/// single blue for anything that's on. Type is small and precise, as if printed on the panel.
enum Theme {
    // MARK: Surfaces

    static let screen = Color(red: 0.012, green: 0.013, blue: 0.016)
    static let chassis = Color(red: 0.03, green: 0.031, blue: 0.035)
    static let panelTop = Color(red: 0.118, green: 0.12, blue: 0.128)
    static let panelBottom = Color(red: 0.075, green: 0.077, blue: 0.083)
    /// Fine lines printed on the panel.
    static let silk = Color.white.opacity(0.14)
    static let hairline = Color.white.opacity(0.08)

    // MARK: Text

    static let textPrimary = Color(white: 0.94)
    static let textSecondary = Color(white: 0.64)
    static let textTertiary = Color(white: 0.42)
    /// Legends printed on the panel.
    static let legend = Color(white: 0.7)

    // MARK: Colour

    /// The "on" colour: SYNC, Q, key lock, headphone cue, the jog ring.
    static let accent = Color(red: 0.13, green: 0.52, blue: 1.0)
    static let play = Color(red: 0.2, green: 0.88, blue: 0.4)
    static let cue = Color(red: 1.0, green: 0.6, blue: 0.08)
    static let loop = Color(red: 1.0, green: 0.54, blue: 0.04)
    static let danger = Color(red: 1.0, green: 0.2, blue: 0.16)
    static let warn = Color(red: 1.0, green: 0.76, blue: 0.1)

    // rekordbox's 3-band waveform colours
    static let waveLow = Color(red: 0.07, green: 0.3, blue: 1.0)
    static let waveMid = Color(red: 0.98, green: 0.58, blue: 0.13)
    static let waveHigh = Color(red: 1.0, green: 0.96, blue: 0.9)

    // rekordbox's default hot cue colours, A–H
    static let hotCueColors: [Color] = [
        Color(red: 0.96, green: 0.17, blue: 0.27),
        Color(red: 0.14, green: 0.5, blue: 1.0),
        Color(red: 0.16, green: 0.84, blue: 0.3),
        Color(red: 0.62, green: 0.3, blue: 1.0),
        Color(red: 0.1, green: 0.8, blue: 0.72),
        Color(red: 1.0, green: 0.48, blue: 0.06),
        Color(red: 0.94, green: 0.3, blue: 0.72),
        Color(red: 0.98, green: 0.82, blue: 0.08),
    ]
    static let hotCueLetters = ["A", "B", "C", "D", "E", "F", "G", "H"]

    /// Camelot wheel colours, the way key charts print them, so compatible keys sit near each other.
    static func keyColor(_ code: String?) -> Color {
        guard let code, let (number, minor) = Camelot.parse(code) else { return textSecondary }
        let hue = (Double(number - 1) / 12 + 0.47).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: minor ? 0.62 : 0.5, brightness: minor ? 1.0 : 0.96)
    }

    /// A paper label for a record without artwork, chosen from its title so it's always the same.
    static func label(for title: String) -> Color {
        var hash: UInt64 = 5381
        for byte in title.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let palette: [Color] = [
            Color(red: 0.86, green: 0.25, blue: 0.2), Color(red: 0.14, green: 0.45, blue: 0.86),
            Color(red: 0.9, green: 0.62, blue: 0.12), Color(red: 0.2, green: 0.62, blue: 0.5),
            Color(red: 0.5, green: 0.3, blue: 0.82), Color(red: 0.82, green: 0.3, blue: 0.55),
        ]
        return palette[Int(hash % UInt64(palette.count))]
    }

    /// The average colour of an image, for tinting the vinyl to suit the artwork.
    static func dominantColor(of image: CGImage) -> SIMD4<Float> {
        var pixel = [UInt8](repeating: 0, count: 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { return .zero }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return SIMD4(Float(pixel[0]) / 255, Float(pixel[1]) / 255, Float(pixel[2]) / 255, 1)
    }

    // MARK: Type

    /// Legends printed on the panel: a technical grotesque, tracked out slightly.
    static func silk(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size) }

    /// Readouts on the screens: numbers that hold their position as they change.
    static func digits(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size).monospacedDigit() }

    /// Track titles and browser text, which should read as native.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    // MARK: Motion

    /// Keys and pads going down and coming back: quick, with a tiny bit of life.
    static let press = Animation.spring(response: 0.16, dampingFraction: 0.62)
    /// Panels moving, sheets of the interface sliding in and out.
    static let panel = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// A control springing home after a double-tap.
    static let home = Animation.spring(response: 0.3, dampingFraction: 0.68)
}

/// Pre-rendered artwork for hardware parts. Each part is drawn once, with all the blur and shading
/// it likes, and after that it's a plain bitmap the GPU can composite for free. That's how control
/// surfaces get to be this detailed without costing anything while the app runs.
@MainActor
enum Baked {
    private static var cache: [String: UIImage] = [:]

    static func image<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> UIImage {
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: content())
        renderer.scale = 3
        renderer.isOpaque = false
        let image = renderer.uiImage ?? UIImage()
        cache[key] = image
        return image
    }
}

/// Fine film grain, tiled over a panel at low opacity, so large areas read as a material.
enum PanelGrain {
    @MainActor static let image: UIImage = {
        let size = 128
        var bytes = [UInt8](repeating: 0, count: size * size)
        var seed: UInt32 = 0x1234_5678
        for i in 0..<bytes.count {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[i] = UInt8((seed >> 24) & 0xFF)
        }
        let context = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return UIImage(cgImage: context.makeImage()!, scale: 3, orientation: .up)
    }()
}

extension View {
    /// A section of the control surface: matte and lit softly from above, with a milled edge.
    func controlSurface(cornerRadius: CGFloat = 7) -> some View {
        modifier(ControlSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// A black screen set into the surface, under glass.
    func displayWell(cornerRadius: CGFloat = 5) -> some View {
        modifier(DisplayWellModifier(cornerRadius: cornerRadius))
    }

    /// Text styled as if printed on the panel.
    func silk(_ size: CGFloat = 8.5, color: Color = Theme.legend, tracking: CGFloat = 0.55) -> some View {
        font(Theme.silk(size)).tracking(tracking).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}

private struct ControlSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(LinearGradient(colors: [Theme.panelTop, Theme.panelBottom], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Image(uiImage: PanelGrain.image).resizable(resizingMode: .tile).opacity(0.05).blendMode(.overlay)
                            .clipShape(shape)
                    }
            }
            .overlay {
                // The milled edge: lit along the top, falling off down the sides.
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.17), .white.opacity(0.03), .black.opacity(0.4)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
    }
}

private struct DisplayWellModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Theme.screen))
            .overlay {
                // A recess: dark along the top inside edge, a sliver of light under the bottom edge.
                shape.strokeBorder(LinearGradient(colors: [.black, .black.opacity(0.7), .white.opacity(0.13)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            }
            .clipShape(shape)
    }
}

/// The Cheeks mark: a record with a marker on it.
struct CheeksMark: View {
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.textPrimary, lineWidth: size * 0.12)
            Circle().fill(Theme.accent).frame(width: size * 0.34, height: size * 0.34)
            Capsule().fill(Theme.textPrimary)
                .frame(width: size * 0.1, height: size * 0.28)
                .offset(y: -size * 0.28)
                .rotationEffect(.degrees(38))
        }
        .frame(width: size, height: size)
    }
}
