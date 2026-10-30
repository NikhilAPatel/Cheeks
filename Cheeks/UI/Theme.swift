import SwiftUI

/// rekordbox's screens set into a Pioneer-style control surface: black recessed displays for
/// waveforms and track info, top-lit bevelled keys and pads that glow when on, and one blue for
/// anything that's switched on.
enum Theme {
    static let background = Color.black
    static let panel = Color(white: 0.085)
    /// The control surface: dark panel, lit slightly from the top like hardware under a booth light.
    static let surface = LinearGradient(colors: [Color(white: 0.125), Color(white: 0.075)], startPoint: .top, endPoint: .bottom)
    /// Unlit buttons and pad rows.
    static let raised = Color(white: 0.16)
    /// Waveforms and the jog displays.
    static let well = Color.black
    static let stroke = Color.white.opacity(0.1)
    /// 1 px edge on buttons and pads, so they read as crisp keys rather than flat tiles.
    static let edge = Color.white.opacity(0.07)
    static let dim = Color(white: 0.6)
    static let faint = Color(white: 0.32)

    /// rekordbox's "on" blue: SYNC, Q, MT, headphone CUE, FX assign, the jog ring.
    static let accent = Color(red: 0.13, green: 0.47, blue: 1.0)
    /// Like rekordbox, both decks share one colour; the deck number tells them apart.
    static let deckColors = [accent, accent]
    static let play = Color(red: 0.25, green: 0.85, blue: 0.35)
    static let cue = Color(red: 1.0, green: 0.62, blue: 0.1)
    static let loop = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let sync = accent

    // rekordbox 3-band waveform colours
    static let waveLow = Color(red: 0.12, green: 0.38, blue: 1.0)
    static let waveMid = Color(red: 0.95, green: 0.6, blue: 0.2)
    static let waveHigh = Color(red: 1.0, green: 0.95, blue: 0.88)

    // rekordbox's default hot cue colours, A–H
    static let hotCueColors: [Color] = [
        Color(red: 0.92, green: 0.2, blue: 0.27),
        Color(red: 0.2, green: 0.5, blue: 1.0),
        Color(red: 0.25, green: 0.8, blue: 0.3),
        Color(red: 0.6, green: 0.35, blue: 0.95),
        Color(red: 0.2, green: 0.75, blue: 0.5),
        Color(red: 1.0, green: 0.5, blue: 0.1),
        Color(red: 0.25, green: 0.45, blue: 0.95),
        Color(red: 0.95, green: 0.8, blue: 0.1),
    ]
    static let hotCueLetters = ["A", "B", "C", "D", "E", "F", "G", "H"]

    /// Small caps legend, as printed under rekordbox's controls.
    static func legend(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// Readouts (BPM, times, percentages): proportional figures that don't jitter.
    static func readout(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// Hardware key face: a top-lit cap with a bevelled edge. Lit keys glow in their colour, like
/// backlit rubber; pressing an unlit key tints it.
struct KeyCap: View {
    var color: Color = .white
    var lit = false
    var pressed = false
    var cornerRadius: CGFloat = 4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        ZStack {
            if lit {
                shape.fill(color.opacity(pressed ? 1 : 0.88))
                shape.fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))
            } else {
                shape.fill(LinearGradient(colors: [Color(white: pressed ? 0.27 : 0.21), Color(white: pressed ? 0.18 : 0.135)],
                                          startPoint: .top, endPoint: .bottom))
                if pressed { shape.fill(color.opacity(0.2)) }
            }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(lit ? 0.4 : 0.14), .black.opacity(0.55)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: lit ? color.opacity(0.6) : .black.opacity(0.75), radius: lit ? 6 : 1.5, y: lit ? 0 : 1)
    }
}

extension View {
    /// A recessed black display set into the surface (waveforms, track info, jog screens).
    func displayWell(cornerRadius: CGFloat = 4) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    /// A section of the control surface, with a faint highlight along its top edge.
    func controlSurface(cornerRadius: CGFloat = 6) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// A pressable hardware key that reports press and release separately (pads, loop controls).
struct PadButton<Label: View>: View {
    var color: Color = .white
    var lit = false
    var cornerRadius: CGFloat = 4
    var onPress: @MainActor () -> Void
    var onRelease: @MainActor () -> Void = {}
    @ViewBuilder var label: () -> Label

    @State private var pressed = false

    var body: some View {
        KeyCap(color: color, lit: lit, pressed: pressed, cornerRadius: cornerRadius)
            .overlay(label().foregroundStyle(lit ? Color.black : color).padding(2))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onRelease()
                    }
            )
    }
}

extension PadButton where Label == Text {
    init(_ title: String, color: Color = .white, lit: Bool = false, onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void = {}) {
        self.color = color
        self.lit = lit
        self.onPress = onPress
        self.onRelease = onRelease
        self.label = { Text(title).font(Theme.legend(11, .semibold)) }
    }
}
