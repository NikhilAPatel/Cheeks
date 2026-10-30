import SwiftUI

// MARK: Key faces

/// The face of a hardware key, pre-rendered and stretched to fit (its corners never distort).
/// It sits slightly recessed in the panel. When it's lit it glows from within and throws a soft
/// bloom onto the surface around it.
struct KeyFace: View {
    var color: Color = Theme.accent
    var lit = false
    var pressed = false
    var cornerRadius: CGFloat = 5

    /// The transparent margin around the face that holds the bloom.
    private static let bleed: CGFloat = 10
    private static let core: CGFloat = 44

    var body: some View {
        let cap = Self.bleed + cornerRadius + 3
        Image(uiImage: artwork)
            .resizable(capInsets: EdgeInsets(top: cap, leading: cap, bottom: cap, trailing: cap), resizingMode: .stretch)
            .padding(-Self.bleed)
            .allowsHitTesting(false)
    }

    private var artwork: UIImage {
        let side = Self.core + Self.bleed * 2
        let key = "key-\(color.description)-\(lit)-\(pressed)-\(cornerRadius)"
        return Baked.image(key) {
            Self.face(color: color, lit: lit, pressed: pressed, cornerRadius: cornerRadius)
                .frame(width: Self.core, height: Self.core)
                .padding(Self.bleed)
                .frame(width: side, height: side)
        }
    }

    @ViewBuilder
    private static func face(color: Color, lit: Bool, pressed: Bool, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if lit {
                // Bloom thrown onto the panel.
                shape.fill(color).blur(radius: 6).opacity(pressed ? 0.8 : 0.55)
            }
            // The recess the key sits in.
            shape.fill(Color.black.opacity(0.85)).padding(-1)
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5).padding(-1.5)
            if lit {
                shape.fill(LinearGradient(colors: [color.opacity(1), color.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                // A hot core where the LED sits behind the rubber.
                shape.fill(RadialGradient(colors: [.white.opacity(pressed ? 0.4 : 0.14), .clear], center: .center, startRadius: 0, endRadius: 26))
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            } else {
                shape.fill(LinearGradient(colors: pressed
                    ? [Color(white: 0.145), Color(white: 0.115)]
                    : [Color(white: 0.2), Color(white: 0.125)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(pressed ? 0.08 : 0.2), .white.opacity(0.02), .black.opacity(0.4)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                if pressed { shape.fill(color.opacity(0.14)) }
            }
        }
    }
}

// MARK: Key

/// A hardware key. It acts on the finger's first contact, moves like a real key, and clicks.
struct Key<Label: View>: View {
    var color: Color = Theme.accent
    var lit = false
    var cornerRadius: CGFloat = 5
    var feel: KeyFeel = .key
    var isEnabled = true
    var accessibilityName: String = ""
    var onPress: @MainActor () -> Void
    var onRelease: @MainActor () -> Void = {}
    @ViewBuilder var label: () -> Label

    @State private var pressed = false

    var body: some View {
        label()
            .foregroundStyle(legendColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeyFace(color: color, lit: lit, pressed: pressed, cornerRadius: cornerRadius))
            .scaleEffect(pressed ? 0.955 : 1)
            .animation(Theme.press, value: pressed)
            .animation(.easeOut(duration: 0.12), value: lit)
            .opacity(isEnabled ? 1 : 0.4)
            .overlay {
                TouchSurface(onDown: { _ in
                    guard isEnabled else {
                        Haptics.shared.deny()
                        return
                    }
                    pressed = true
                    feel.down(willBeLit: !lit)
                    onPress()
                }, onUp: {
                    guard pressed else { return }
                    pressed = false
                    feel.up()
                    onRelease()
                })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction {
                onPress()
                onRelease()
            }
    }

    private var legendColor: Color {
        if !lit { return pressed ? Theme.textPrimary : Theme.legend }
        return .white
    }
}

extension Key where Label == KeyLegend {
    init(_ title: String, color: Color = Theme.accent, lit: Bool = false, size: CGFloat = 9.5, feel: KeyFeel = .key,
         isEnabled: Bool = true, onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void = {}) {
        self.init(color: color, lit: lit, feel: feel, isEnabled: isEnabled, accessibilityName: title, onPress: onPress, onRelease: onRelease) {
            KeyLegend(title: title, size: size)
        }
    }
}

struct KeyLegend: View {
    var title: String
    var size: CGFloat = 9.5

    var body: some View {
        Text(title)
            .font(Theme.silk(size))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
    }
}

/// What a key feels like under the finger.
enum KeyFeel {
    case key, toggle, pad, none

    @MainActor func down(willBeLit: Bool) {
        switch self {
        case .key: Haptics.shared.key()
        case .toggle: Haptics.shared.toggle(willBeLit)
        case .pad: Haptics.shared.pad()
        case .none: break
        }
    }

    @MainActor func up() {
        if self == .key { Haptics.shared.keyUp() }
    }
}

// MARK: Performance pads

/// An RGB performance pad: translucent rubber lit from behind. It stays softly lit in its colour,
/// flares when struck, then settles back, like a real pad.
struct Pad<Label: View>: View {
    var color: Color
    var lit = false
    var dimmed = false
    var accessibilityName: String = ""
    var onPress: @MainActor () -> Void
    var onRelease: @MainActor () -> Void = {}
    var onDrag: (@MainActor (CGSize) -> Void)?
    @ViewBuilder var label: () -> Label

    @State private var pressed = false
    @State private var flare: Double = 0

    var body: some View {
        ZStack {
            face
            label().foregroundStyle(lit ? Color.white : color.opacity(dimmed ? 0.5 : 0.9))
        }
        .scaleEffect(pressed ? 0.965 : 1)
        .animation(Theme.press, value: pressed)
        .overlay {
            TouchSurface(onDown: { _ in
                pressed = true
                Haptics.shared.pad()
                flare = 1
                withAnimation(.easeOut(duration: 0.34)) { flare = 0 }
                onPress()
            }, onMove: { _, translation in
                onDrag?(translation)
            }, onUp: {
                pressed = false
                onRelease()
            })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            onPress()
            onRelease()
        }
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            KeyFace(color: color, lit: lit, pressed: pressed, cornerRadius: 6)
            if lit {
                // The diffuser is brightest in the middle, where the LED is.
                Image(uiImage: Self.hotspot).resizable().blendMode(.plusLighter).opacity(0.09).clipShape(shape).allowsHitTesting(false)
            } else if !dimmed {
                shape.fill(color.opacity(0.09)).allowsHitTesting(false)
                shape.strokeBorder(color.opacity(0.22), lineWidth: 0.75).allowsHitTesting(false)
            }
            if flare > 0.001 {
                shape.fill(Color.white.opacity(flare * 0.55)).allowsHitTesting(false)
            }
        }
    }

    private static var hotspot: UIImage {
        Baked.image("pad-hotspot") {
            RadialGradient(colors: [.white, .white.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 40)
                .frame(width: 80, height: 60)
        }
    }
}

// MARK: Round transport buttons

/// CUE and PLAY: rubber domes in a polished metal bezel, with an LED ring that glows when lit.
struct TransportButton<Label: View>: View {
    var color: Color
    var lit = false
    var pulsing = false
    var accessibilityName: String
    var onPress: @MainActor () -> Void
    var onRelease: @MainActor () -> Void = {}
    @ViewBuilder var label: () -> Label

    @State private var pressed = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Image(uiImage: Self.artwork(color: color, lit: lit, pressed: pressed))
                    .resizable()
                    .frame(width: side * Self.outerScale, height: side * Self.outerScale)
                label()
                    .foregroundStyle(lit ? color : color.opacity(0.6))
                    .shadow(color: lit ? color : .clear, radius: 3)
            }
            .frame(width: side, height: side)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(Theme.press, value: pressed)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .overlay {
                TouchSurface(onDown: { _ in
                    pressed = true
                    Haptics.shared.pad()
                    onPress()
                }, onUp: {
                    pressed = false
                    Haptics.shared.keyUp()
                    onRelease()
                }, circular: true)
                .frame(width: side, height: side)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onPress()
            onRelease()
        }
    }

    private static var outerScale: CGFloat { 1.3 }

    private static func artwork(color: Color, lit: Bool, pressed: Bool) -> UIImage {
        let side: CGFloat = 78
        let scale = outerScale
        return Baked.image("transport-\(color.description)-\(lit)-\(pressed)") {
            ZStack {
                if lit {
                    Circle().fill(color).frame(width: side * 0.97, height: side * 0.97).blur(radius: 7).opacity(0.5)
                }
                // Contact shadow on the panel.
                Circle().fill(Color.black.opacity(0.7)).frame(width: side, height: side).blur(radius: 2).offset(y: 1)
                // Polished bezel, with circular highlights like spun metal.
                Circle()
                    .fill(AngularGradient(colors: [Color(white: 0.2), Color(white: 0.72), Color(white: 0.25), Color(white: 0.13),
                                                   Color(white: 0.3), Color(white: 0.62), Color(white: 0.22), Color(white: 0.15), Color(white: 0.2)],
                                          center: .center))
                    .frame(width: side, height: side)
                Circle().fill(Color.black).frame(width: side * 0.9, height: side * 0.9)
                // LED ring
                Circle()
                    .strokeBorder(color.opacity(lit ? 1 : 0.2), lineWidth: side * 0.035)
                    .frame(width: side * 0.86, height: side * 0.86)
                if lit {
                    Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: side * 0.012)
                        .frame(width: side * 0.845, height: side * 0.845)
                }
                // Rubber dome
                Circle()
                    .fill(RadialGradient(colors: pressed
                        ? [Color(white: 0.13), Color(white: 0.07)]
                        : [Color(white: 0.21), Color(white: 0.07)],
                                         center: UnitPoint(x: 0.42, y: 0.32), startRadius: 0, endRadius: side * 0.42))
                    .frame(width: side * 0.78, height: side * 0.78)
                if lit {
                    Circle().fill(RadialGradient(colors: [color.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: side * 0.38))
                        .frame(width: side * 0.78, height: side * 0.78)
                }
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.17), .clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                    .frame(width: side * 0.78, height: side * 0.78)
            }
            .frame(width: side * scale, height: side * scale)
        }
    }
}
