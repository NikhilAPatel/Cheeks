import SwiftUI

/// Touch jog wheel. Touching the platter scratches (vinyl mode); the outer ring bends pitch
/// while playing. When paused, any touch scrubs.
struct JogWheel: View {
    let deck: Deck
    @State private var lastAngle: Double?
    @State private var mode: Mode?

    private enum Mode { case scratch, bend }
    /// One platter revolution = 1.8 s of audio (33⅓ rpm).
    private let secondsPerTurn = 1.8

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                platter(size: size)
            }
            .frame(width: size, height: size)
            .position(center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dx = g.location.x - center.x, dy = g.location.y - center.y
                        let angle = Double(atan2(dy, dx)) * 180 / .pi
                        guard let last = lastAngle else {
                            let onPlatter = hypot(dx, dy) < size * 0.4
                            mode = onPlatter || !deck.isPlaying ? .scratch : .bend
                            if mode == .scratch { deck.scratchBegin() }
                            lastAngle = angle
                            return
                        }
                        var delta = angle - last
                        if delta > 180 { delta -= 360 }
                        if delta < -180 { delta += 360 }
                        lastAngle = angle
                        let seconds = delta / 360 * secondsPerTurn
                        if mode == .scratch {
                            deck.scratchMove(seconds: seconds)
                        } else {
                            deck.bend(seconds: seconds * 0.6)
                        }
                    }
                    .onEnded { _ in
                        if mode == .scratch { deck.scratchEnd() }
                        mode = nil
                        lastAngle = nil
                    }
            )
        }
    }

    private func platter(size: CGFloat) -> some View {
        let color = Theme.deckColors[deck.index]
        let rotation = deck.position / secondsPerTurn * 360
        let remaining = deck.duration - deck.position
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.2), Color(white: 0.06)], center: .center, startRadius: 0, endRadius: size / 2))
            Circle().stroke(color.opacity(mode == .bend ? 1 : 0.5), lineWidth: 4).padding(2)
            Circle()
                .fill(Color(white: mode == .scratch ? 0.2 : 0.12))
                .padding(size * 0.1)
            // grooves
            ForEach(1..<4) { i in
                Circle().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(size * (0.1 + CGFloat(i) * 0.07))
            }
            Capsule()
                .fill(Color.white)
                .frame(width: 4, height: size * 0.14)
                .offset(y: -size * 0.31)
                .rotationEffect(.degrees(rotation))
            VStack(spacing: 2) {
                Text(deck.isLoaded ? "-" + remaining.clockString : "--:--")
                    .font(.system(size: size * 0.11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(remaining < 30 && deck.isLoaded ? Color.red : Color.white)
                Text(deck.bpm > 0 ? String(format: "%.1f", deck.effectiveBPM) : "---.-")
                    .font(.system(size: size * 0.08, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}
