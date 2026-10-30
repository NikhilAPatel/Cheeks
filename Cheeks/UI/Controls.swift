import SwiftUI

/// DJM-style rotary knob: knurled skirt, domed cap, white pointer, and an LED arc lit from the
/// default position. Drag up/down to turn, double-tap to reset.
struct Knob: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -1...1
    var defaultValue: Float = 0
    var label: String
    var color: Color = Theme.accent
    var size: CGFloat = 38

    @State private var dragStart: Float?

    private var fraction: CGFloat { CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) }
    private var defaultFraction: CGFloat { CGFloat((defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // LED arc: unlit segments stay faintly visible, like real LEDs
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: min(fraction, defaultFraction) * 0.75, to: max(fraction, defaultFraction) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: color.opacity(0.8), radius: 2)
                // Detent mark at the default position
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 1, height: size * 0.08)
                    .offset(y: -size * 0.5 + size * 0.04)
                    .rotationEffect(.degrees(-135 + Double(defaultFraction) * 270))
                // Knurled skirt
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.22), Color(white: 0.06)], center: UnitPoint(x: 0.4, y: 0.35),
                                         startRadius: 0, endRadius: size * 0.4))
                    .overlay(Circle().stroke(Color.white.opacity(0.13), style: StrokeStyle(lineWidth: 1.5, dash: [1, 1.4])).padding(1))
                    .shadow(color: .black.opacity(0.85), radius: 2, y: 1.5)
                    .padding(size * 0.14)
                // Domed cap
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
                    .padding(size * 0.26)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: size * 0.26)
                    .offset(y: -size * 0.21)
                    .rotationEffect(.degrees(-135 + Double(fraction) * 270))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let span = range.upperBound - range.lowerBound
                        let delta = Float(-g.translation.height / 140) * span
                        value = min(range.upperBound, max(range.lowerBound, dragStart! + delta))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            if !label.isEmpty {
                Text(label)
                    .font(Theme.legend(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Printed scale beside a fader slot.
struct FaderScale: View {
    var ticks: Int
    /// Distance from each end to the first and last tick (half the cap's length).
    var inset: CGFloat
    var vertical: Bool

    var body: some View {
        Canvas { context, size in
            let length = (vertical ? size.height : size.width) - inset * 2
            let across = vertical ? size.width : size.height
            for i in 0...ticks {
                let along = inset + CGFloat(i) / CGFloat(ticks) * length
                let major = i == 0 || i == ticks || i * 2 == ticks
                let span = min(across, major ? 24 : 16)
                let rect = vertical
                    ? CGRect(x: (across - span) / 2, y: along - 0.5, width: span, height: 1)
                    : CGRect(x: along - 0.5, y: (across - span) / 2, width: 1, height: span)
                context.fill(Path(rect), with: .color(.white.opacity(major ? 0.3 : 0.14)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The recessed slot a fader runs in.
struct FaderSlot: View {
    var vertical = true

    var body: some View {
        Capsule()
            .fill(Color.black)
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.14)],
                                                           startPoint: vertical ? .leading : .top,
                                                           endPoint: vertical ? .trailing : .bottom), lineWidth: 1))
            .frame(width: vertical ? 5 : nil, height: vertical ? nil : 5)
    }
}

/// Moulded fader cap: grip ridges either side of a coloured index line.
struct FaderCap: View {
    var color: Color = .white
    var vertical = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        shape
            .fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.17), Color(white: 0.24)],
                                 startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing))
            .overlay {
                let ridges = vertical ? AnyLayout(VStackLayout(spacing: 2.5)) : AnyLayout(HStackLayout(spacing: 2.5))
                ridges {
                    ForEach(0..<2, id: \.self) { _ in ridge }
                    Rectangle().fill(color).frame(width: vertical ? nil : 2, height: vertical ? 2 : nil)
                        .shadow(color: color.opacity(0.6), radius: 1.5)
                    ForEach(0..<2, id: \.self) { _ in ridge }
                }
                .padding(vertical ? .horizontal : .vertical, 3)
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.6)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.85), radius: 3, y: 2)
    }

    private var ridge: some View {
        Rectangle().fill(Color.black.opacity(0.45))
            .frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
    }
}

/// Vertical fader (0...1), e.g. a channel fader.
struct VerticalFader: View {
    @Binding var value: Float
    var color: Color = .white
    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let capH: CGFloat = 24
            let y = (1 - CGFloat(value)) * (h - capH)
            ZStack(alignment: .top) {
                FaderScale(ticks: 10, inset: capH / 2, vertical: true)
                FaderSlot().padding(.vertical, capH / 2 - 3).frame(maxWidth: .infinity)
                FaderCap(color: color, vertical: true)
                    .frame(width: min(30, geo.size.width), height: capH)
                    .offset(y: y)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let delta = Float(-g.translation.height / (h - capH))
                        value = min(1, max(0, dragStart! + delta))
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
    }
}

/// Horizontal crossfader (-1...1).
struct Crossfader: View {
    @Binding var value: Float
    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let capW: CGFloat = 22
            let x = CGFloat((value + 1) / 2) * (w - capW)
            ZStack(alignment: .leading) {
                FaderScale(ticks: 8, inset: capW / 2, vertical: false)
                FaderSlot(vertical: false).padding(.horizontal, capW / 2 - 3)
                FaderCap(vertical: false)
                    .frame(width: capW, height: min(28, geo.size.height))
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let delta = Float(g.translation.width / (w - capW)) * 2
                        value = min(1, max(-1, dragStart! + delta))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}

/// Segmented LED level meter, vertical or horizontal. Unlit LEDs stay faintly visible.
struct LevelMeter: View {
    var level: Float
    var horizontal = false

    var body: some View {
        GeometryReader { geo in
            let segments = horizontal ? 30 : 24
            let lit = Int((min(1, level).squareRoot() * Float(segments)).rounded())
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
            layout {
                ForEach(horizontal ? Array(0..<segments) : Array((0..<segments).reversed()), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(color(for: i, of: segments).opacity(i < lit ? 1 : 0.14))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func color(for i: Int, of n: Int) -> Color {
        if i >= n - 3 { return .red }
        if i >= n - 7 { return .orange }
        return .green
    }
}

/// A deck's channel level, observed on its own so the meter can update without redrawing its neighbours.
struct DeckLevelMeter: View {
    let deck: Deck
    var horizontal = false

    var body: some View {
        LevelMeter(level: deck.level, horizontal: horizontal)
    }
}

/// Toggle key: dark when off, lit blue (or `color`) when on.
struct ToggleChip: View {
    var title: String
    var isOn: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 26
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.legend(10.5, .semibold))
                .tracking(0.4)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(minWidth: 36, minHeight: height)
                .foregroundStyle(isOn ? Color.white : Theme.dim)
                .background(KeyCap(color: color, lit: isOn))
        }
        .buttonStyle(.plain)
    }
}

/// DDJ-style round transport button: a rubber dome with an LED ring and legend that light up.
/// Reports press and release separately, like `PadButton`.
struct RoundButton<Label: View>: View {
    var color: Color
    var lit = false
    var onPress: @MainActor () -> Void
    var onRelease: @MainActor () -> Void = {}
    @ViewBuilder var label: () -> Label

    @State private var pressed = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: pressed ? 0.26 : 0.2), Color(white: 0.06)],
                                 center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: 46))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.7)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(Circle().stroke(color.opacity(lit ? 1 : 0.28), lineWidth: lit ? 2.5 : 1.5).padding(4)
                .shadow(color: lit ? color.opacity(0.9) : .clear, radius: 4))
            .shadow(color: lit ? color.opacity(0.45) : .black.opacity(0.8), radius: lit ? 9 : 3, y: lit ? 0 : 2)
            .overlay(label()
                .foregroundStyle(lit ? color : color.opacity(0.5))
                .shadow(color: lit ? color.opacity(0.9) : .clear, radius: 4))
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(pressed ? 0.97 : 1)
            .contentShape(Circle())
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
