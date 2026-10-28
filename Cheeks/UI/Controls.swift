import SwiftUI

/// Rotary knob: drag up/down to turn, double-tap to reset.
struct Knob: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -1...1
    var defaultValue: Float = 0
    var label: String
    var color: Color = .white
    var size: CGFloat = 38

    @State private var dragStart: Float?

    private var fraction: CGFloat { CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) }
    private var defaultFraction: CGFloat { CGFloat((defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(Theme.raised)
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(3)
                Circle()
                    .trim(from: min(fraction, defaultFraction) * 0.75, to: max(fraction, defaultFraction) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(3)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: size * 0.3)
                    .offset(y: -size * 0.2)
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
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
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
            let capH: CGFloat = 26
            let y = (1 - CGFloat(value)) * (h - capH)
            ZStack(alignment: .top) {
                Capsule().fill(Color.black.opacity(0.6)).frame(width: 5).frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().fill(color).frame(height: 2))
                    .frame(height: capH)
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
            let capW: CGFloat = 30
            let x = CGFloat((value + 1) / 2) * (w - capW)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.6)).frame(height: 5)
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 14).offset(x: w / 2)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.45)], startPoint: .leading, endPoint: .trailing))
                    .overlay(Rectangle().fill(Color.white).frame(width: 2))
                    .frame(width: capW)
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

/// Segmented LED level meter.
struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            let segments = 14
            let lit = Int((min(1, level).squareRoot() * Float(segments)).rounded())
            VStack(spacing: 1.5) {
                ForEach((0..<segments).reversed(), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < lit ? color(for: i, of: segments) : Color.white.opacity(0.07))
                }
            }
            .frame(width: geo.size.width)
        }
    }

    private func color(for i: Int, of n: Int) -> Color {
        if i >= n - 2 { return .red }
        if i >= n - 4 { return .orange }
        return .green
    }
}

/// Small rounded toggle-style button used across decks and mixer.
struct ToggleChip: View {
    var title: String
    var isOn: Bool
    var color: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .frame(minWidth: 34, minHeight: 22)
                .foregroundStyle(isOn ? Color.black : color)
                .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? color : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
