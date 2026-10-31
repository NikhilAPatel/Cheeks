import SwiftUI

/// The printed scale and the slot a fader runs in. Drawn once per size.
struct FaderTrack: View {
    var vertical = true
    var ticks: Int
    /// Distance from each end to the first and last tick: half the cap's length.
    var inset: CGFloat
    /// Which ticks are printed long (for example the centre of a tempo fader).
    var majorEvery: Int
    var slotWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let length = (vertical ? size.height : size.width) - inset * 2
            let across = vertical ? size.width : size.height
            for i in 0...ticks {
                let along = inset + CGFloat(i) / CGFloat(ticks) * length
                let major = i % majorEvery == 0
                let span = min(across, major ? across * 0.92 : across * 0.68)
                let weight: CGFloat = major ? 0.9 : 0.6
                let rect = vertical
                    ? CGRect(x: (across - span) / 2, y: along - weight / 2, width: span, height: weight)
                    : CGRect(x: along - weight / 2, y: (across - span) / 2, width: weight, height: span)
                context.fill(Path(rect), with: .color(.white.opacity(major ? 0.34 : 0.15)))
            }
            // The slot: cut through the panel, shaded inside, with a sliver of light on its lower lip.
            let slot = vertical
                ? CGRect(x: (across - slotWidth) / 2, y: inset - 4, width: slotWidth, height: length + 8)
                : CGRect(x: inset - 4, y: (across - slotWidth) / 2, width: length + 8, height: slotWidth)
            let path = Path(roundedRect: slot, cornerRadius: slotWidth / 2)
            context.fill(path, with: .color(.black))
            context.stroke(path, with: .linearGradient(Gradient(colors: [.black, .white.opacity(0.2)]),
                                                       startPoint: CGPoint(x: slot.minX, y: slot.minY),
                                                       endPoint: vertical ? CGPoint(x: slot.maxX, y: slot.minY) : CGPoint(x: slot.minX, y: slot.maxY)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// A moulded fader cap: grip ridges either side of a coloured index line.
struct FaderCap: View {
    var color: Color = .white
    var vertical = true
    var width: CGFloat
    var length: CGFloat

    var body: some View {
        // The artwork has a 6 pt margin for its shadow. It's drawn with that margin and takes up
        // space without it, so the cap's own centre is where the fader's value says.
        Image(uiImage: artwork)
            .resizable()
            .frame(width: (vertical ? width : length) + 12, height: (vertical ? length : width) + 12)
            .padding(-6)
            .allowsHitTesting(false)
    }

    private var artwork: UIImage {
        let w = vertical ? width : length, h = vertical ? length : width
        return Baked.image("cap-\(color.description)-\(vertical)-\(width)-\(length)") {
            let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            ZStack {
                shape.fill(Color.black.opacity(0.9)).blur(radius: 2.5).offset(y: 2).frame(width: w, height: h)
                shape.fill(LinearGradient(colors: [Color(white: 0.31), Color(white: 0.145), Color(white: 0.22)],
                                          startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing))
                    .frame(width: w, height: h)
                Canvas { context, size in
                    let along = vertical ? size.height : size.width
                    let across = vertical ? size.width : size.height
                    let spacing: CGFloat = 2
                    let count = Int(along / 2 / spacing) - 1
                    for side in [-1.0, 1.0] {
                        for i in 1...max(1, count) {
                            let at = along / 2 + CGFloat(side) * CGFloat(i) * spacing + (side > 0 ? 1 : -1)
                            let rect = vertical
                                ? CGRect(x: 2, y: at - 0.4, width: across - 4, height: 0.8)
                                : CGRect(x: at - 0.4, y: 2, width: 0.8, height: across - 4)
                            context.fill(Path(rect), with: .color(.black.opacity(0.42)))
                            let highlight = vertical
                                ? CGRect(x: 2, y: at + 0.4, width: across - 4, height: 0.4)
                                : CGRect(x: at + 0.4, y: 2, width: 0.4, height: across - 4)
                            context.fill(Path(highlight), with: .color(.white.opacity(0.1)))
                        }
                    }
                    let line = vertical
                        ? CGRect(x: 1, y: along / 2 - 0.9, width: across - 2, height: 1.8)
                        : CGRect(x: along / 2 - 0.9, y: 1, width: 1.8, height: across - 2)
                    context.fill(Path(line), with: .color(color))
                }
                .frame(width: w, height: h)
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
                    .frame(width: w, height: h)
            }
            .frame(width: w + 12, height: h + 12)
        }
    }
}

/// A vertical channel fader, 0...1.
struct ChannelFader: View {
    @Binding var value: Float
    var color: Color = .white
    var label: String = "Channel fader"

    @State private var dragStart: Float?
    private let capLength: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let travel = max(1, h - capLength)
            ZStack(alignment: .top) {
                FaderTrack(vertical: true, ticks: 10, inset: capLength / 2, majorEvery: 5)
                FaderCap(color: color, vertical: true, width: min(30, geo.size.width), length: capLength)
                    .offset(y: (1 - CGFloat(value)) * travel)
            }
            .overlay {
                TouchSurface(onDown: { _ in
                    dragStart = value
                    Haptics.shared.grab()
                }, onMove: { _, translation in
                    guard let dragStart else { return }
                    let next = min(1, max(0, dragStart + Float(-translation.height / travel)))
                    if next != value, next == 0 || next == 1 { Haptics.shared.endStop() }
                    value = next
                }, onUp: { dragStart = nil }, onDoubleTap: {
                    Haptics.shared.detent()
                    withAnimation(Theme.home) { value = 0.85 }
                })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            value = min(1, max(0, value + (direction == .increment ? 0.05 : -0.05)))
        }
    }
}

/// The horizontal crossfader, -1...1. It clicks through centre and double-tap springs it back.
struct CrossfaderControl: View {
    @Binding var value: Float

    @State private var dragStart: Float?
    @State private var inCentre = false
    private let capLength: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - capLength)
            ZStack(alignment: .leading) {
                FaderTrack(vertical: false, ticks: 10, inset: capLength / 2, majorEvery: 5)
                FaderCap(color: .white, vertical: false, width: min(26, geo.size.height), length: capLength)
                    .offset(x: CGFloat((value + 1) / 2) * travel)
            }
            .frame(maxHeight: .infinity)
            .overlay {
                TouchSurface(onDown: { _ in
                    dragStart = value
                    Haptics.shared.grab()
                }, onMove: { _, translation in
                    guard let dragStart else { return }
                    var next = min(1, max(-1, dragStart + Float(translation.width / travel) * 2))
                    // Catches within 3 pt either side, so it can be found by feel.
                    let near = abs(next) < Float(6 / travel)
                    if near {
                        next = 0
                        if !inCentre { Haptics.shared.detent() }
                    }
                    inCentre = near
                    if next != value, abs(next) == 1 { Haptics.shared.endStop() }
                    value = next
                }, onUp: { dragStart = nil }, onDoubleTap: {
                    Haptics.shared.detent()
                    withAnimation(Theme.home) { value = 0 }
                })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crossfader")
        .accessibilityValue(value == 0 ? "Centre" : (value < 0 ? "Towards deck 1" : "Towards deck 2"))
        .accessibilityAdjustableAction { direction in
            value = min(1, max(-1, value + (direction == .increment ? 0.1 : -0.1)))
        }
    }
}

/// The tempo fader: down is faster, like a CDJ. It has a centre click at 0%, an LED that lights
/// when it's dead on, and fine control if you slide sideways off it.
struct TempoFader: View {
    let deck: Deck
    @State private var dragStart: Double?
    @State private var inCentre = false
    private let capLength: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let travel = max(1, h - capLength)
            let fraction = (deck.tempoRatioPercent / deck.tempoRange + 1) / 2 // 0 top … 1 bottom
            ZStack(alignment: .top) {
                FaderTrack(vertical: true, ticks: 20, inset: capLength / 2, majorEvery: 5, slotWidth: 4.5)
                // Centre LED
                Capsule().fill(deck.tempoRatioPercent == 0 ? Theme.play : Theme.play.opacity(0.18))
                    .frame(width: 3, height: 3)
                    .offset(x: -geo.size.width / 2 + 3, y: h / 2 - 1.5)
                FaderCap(color: deck.syncOn ? Theme.accent : .white, vertical: true, width: min(32, geo.size.width), length: capLength)
                    .offset(y: CGFloat(min(1, max(0, fraction))) * travel)
                    .animation(deck.syncOn ? Theme.panel : nil, value: deck.tempoRatioPercent)
            }
            .overlay {
                TouchSurface(onDown: { _ in
                    dragStart = deck.tempoRatioPercent
                    Haptics.shared.grab()
                }, onMove: { _, translation in
                    guard let dragStart else { return }
                    let fine = Double(max(0.15, 1 - abs(translation.width) / 120))
                    var next = dragStart + Double(translation.height / travel) * deck.tempoRange * 2 * fine
                    next = min(deck.tempoRange, max(-deck.tempoRange, next))
                    let near = abs(next) < deck.tempoRange * 0.012
                    if near {
                        next = 0
                        if !inCentre { Haptics.shared.detent() }
                    }
                    inCentre = near
                    deck.setTempoManually(next)
                }, onUp: { dragStart = nil }, onDoubleTap: {
                    Haptics.shared.detent()
                    deck.setTempoManually(0)
                })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue(String(format: "%+.1f percent", deck.tempoRatioPercent))
        .accessibilityAdjustableAction { direction in
            deck.setTempoManually(min(deck.tempoRange, max(-deck.tempoRange, deck.tempoRatioPercent + (direction == .increment ? 0.5 : -0.5))))
        }
    }
}
