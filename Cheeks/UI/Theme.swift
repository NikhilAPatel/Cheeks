import SwiftUI

enum Theme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let panel = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let raised = Color(red: 0.15, green: 0.15, blue: 0.18)
    static let stroke = Color.white.opacity(0.08)
    static let dim = Color.white.opacity(0.5)

    static let deckColors = [Color(red: 0.18, green: 0.62, blue: 1.0), Color(red: 1.0, green: 0.42, blue: 0.22)]
    static let play = Color(red: 0.2, green: 0.9, blue: 0.4)
    static let cue = Color(red: 1.0, green: 0.68, blue: 0.1)
    static let loop = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let sync = Color(red: 0.35, green: 0.75, blue: 1.0)

    // rekordbox-style 3-band waveform colors
    static let waveLow = Color(red: 0.12, green: 0.35, blue: 1.0)
    static let waveMid = Color(red: 1.0, green: 0.62, blue: 0.15)
    static let waveHigh = Color.white

    static let hotCueColors: [Color] = [
        Color(red: 0.2, green: 0.85, blue: 0.35),
        Color(red: 1.0, green: 0.25, blue: 0.3),
        Color(red: 0.3, green: 0.55, blue: 1.0),
        Color(red: 1.0, green: 0.75, blue: 0.1),
        Color(red: 0.75, green: 0.35, blue: 1.0),
        Color(red: 0.1, green: 0.85, blue: 0.85),
        Color(red: 1.0, green: 0.45, blue: 0.75),
        Color(red: 1.0, green: 0.5, blue: 0.1),
    ]
    static let hotCueLetters = ["A", "B", "C", "D", "E", "F", "G", "H"]
}

/// A flat, pressable DJ-style button that reports press and release separately.
struct PadButton<Label: View>: View {
    var color: Color = .white
    var lit = false
    var cornerRadius: CGFloat = 6
    var onPress: @MainActor () -> Void
    var onRelease: @MainActor () -> Void = {}
    @ViewBuilder var label: () -> Label

    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(lit ? color.opacity(pressed ? 1 : 0.85) : (pressed ? color.opacity(0.35) : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(lit ? color : color.opacity(0.35), lineWidth: 1))
            .overlay(label().foregroundStyle(lit ? Color.black : color).padding(2))
            .scaleEffect(pressed ? 0.96 : 1)
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
        self.label = { Text(title).font(.system(size: 12, weight: .bold, design: .rounded)) }
    }
}
