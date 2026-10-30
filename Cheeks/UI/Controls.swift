import SwiftUI

/// Rotary knob: drag up/down to turn, double-tap to reset.
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
                // Value arc drawn from the default position, like rekordbox's knobs
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: min(fraction, defaultFraction) * 0.75, to: max(fraction, defaultFraction) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 2))
                    .rotationEffect(.degrees(135))
                // Detent mark at the default position
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1, height: size * 0.1)
                    .offset(y: -size * 0.5 + size * 0.05)
                    .rotationEffect(.degrees(-135 + Double(defaultFraction) * 270))
                Circle()
                    .fill(Color(white: 0.19))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(size * 0.17)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 1.5, height: size * 0.22)
                    .offset(y: -size * 0.19)
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
                    .font(Theme.legend(9))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Faint printed scale beside a fader slot.
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
                let span = min(across, major ? 20 : 12)
                let rect = vertical
                    ? CGRect(x: (across - span) / 2, y: along - 0.5, width: span, height: 1)
                    : CGRect(x: along - 0.5, y: (across - span) / 2, width: 1, height: span)
                context.fill(Path(rect), with: .color(.white.opacity(major ? 0.2 : 0.1)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Flat fader cap with a centre line.
struct FaderCap: View {
    var color: Color = .black
    var vertical = true

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(white: 0.82))
            .overlay {
                if vertical {
                    Rectangle().fill(color).frame(height: 2)
                } else {
                    Rectangle().fill(color).frame(width: 2)
                }
            }
    }
}

/// Vertical fader (0...1), e.g. a channel fader.
struct VerticalFader: View {
    @Binding var value: Float
    var color: Color = .black
    @State private var dragStart: Float?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let capH: CGFloat = 16
            let y = (1 - CGFloat(value)) * (h - capH)
            ZStack(alignment: .top) {
                FaderScale(ticks: 10, inset: capH / 2, vertical: true)
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 2).frame(maxWidth: .infinity)
                FaderCap(color: color, vertical: true)
                    .frame(width: min(28, geo.size.width), height: capH)
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
            let capW: CGFloat = 14
            let x = CGFloat((value + 1) / 2) * (w - capW)
            ZStack(alignment: .leading) {
                FaderScale(ticks: 8, inset: capW / 2, vertical: false)
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 2)
                FaderCap(vertical: false)
                    .frame(width: capW, height: min(24, geo.size.height))
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

/// Segmented LED level meter, vertical or horizontal.
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
                    Rectangle()
                        .fill(i < lit ? color(for: i, of: segments) : Color.white.opacity(0.08))
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

/// Flat toggle button: grey when off, filled blue (or `color`) when on.
struct ToggleChip: View {
    var title: String
    var isOn: Bool
    var color: Color = Theme.accent
    var height: CGFloat = 26
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.legend(11, .semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: 36, minHeight: height)
                .foregroundStyle(isOn ? Color.white : Theme.dim)
                .background(RoundedRectangle(cornerRadius: 3).fill(isOn ? color : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// rekordbox's round CUE and PLAY buttons: an outlined circle that fills in when lit.
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
            .fill(lit ? color.opacity(0.22) : (pressed ? color.opacity(0.15) : Color.black))
            .overlay(Circle().stroke(color.opacity(lit ? 1 : 0.7), lineWidth: lit ? 2.5 : 1.5).padding(1.25))
            .overlay(label().foregroundStyle(color))
            .aspectRatio(1, contentMode: .fit)
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
