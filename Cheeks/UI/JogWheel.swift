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

    /// A rekordbox/CDJ jog display, scaled up to be the deck's main control. Everything that turns
    /// (ticks, platter marker, red dot) follows the playhead, so it spins with the music; the rim
    /// shows track progress, and the ring shows the cue point and loop when they're within a turn.
    /// Drawn in one Canvas because two of these redraw every frame.
    private func platter(size: CGFloat) -> some View {
        let position = deck.position
        let rotation = position / secondsPerTurn * 360
        let mode = self.mode
        let loaded = deck.isLoaded
        let remaining = deck.duration - position
        let progress = loaded ? min(1, position / max(deck.duration, 0.001)) : 0
        let cueOffset = deck.cuePoint - position
        let renderer = deck.renderer
        let loop = renderer.loopActive
            ? (start: renderer.loopStart / deck.sampleRate - position, end: renderer.loopEnd / deck.sampleRate - position) : nil
        let bpm = deck.bpm > 0 ? String(format: "%.2f", deck.effectiveBPM) : "--.--"
        let tempo = String(format: "%+.1f%%", deck.tempoRatioPercent)
        let range = deck.tempoRange >= 100 ? "WIDE" : "±\(Int(deck.tempoRange))"
        return Canvas { context, canvas in
            let r = min(canvas.width, canvas.height) / 2
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            func circle(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            }
            func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
                let a = (degrees - 90) * .pi / 180
                return CGPoint(x: c.x + CGFloat(cos(a)) * radius, y: c.y + CGFloat(sin(a)) * radius)
            }
            func arc(_ from: Double, _ to: Double, _ radius: CGFloat) -> Path {
                var path = Path()
                path.addArc(center: c, radius: radius, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
                return path
            }
            /// Where a time offset from the playhead sits on the turning ring.
            func angle(_ seconds: Double) -> Double { rotation + seconds / secondsPerTurn * 360 }

            // Outer ring (touch it to bend): a fine scale turning with the record
            context.fill(circle(r), with: .color(Color(white: mode == .bend ? 0.12 : 0.065)))
            context.stroke(circle(r - 0.5), with: .color(.white.opacity(0.55)), lineWidth: 1)
            var minor = Path(), major = Path()
            for i in 0..<120 {
                let a = Double(i) * 3 + rotation
                if i % 10 == 0 {
                    major.move(to: point(a, r * 0.865))
                    major.addLine(to: point(a, r * 0.935))
                } else {
                    minor.move(to: point(a, r * 0.895))
                    minor.addLine(to: point(a, r * 0.935))
                }
            }
            context.stroke(minor, with: .color(.white.opacity(0.2)), lineWidth: 1)
            context.stroke(major, with: .color(.white.opacity(0.6)), lineWidth: 1.5)

            // Track progress round the rim
            context.stroke(circle(r * 0.968), with: .color(.white.opacity(0.08)), lineWidth: 2)
            if progress > 0 {
                context.stroke(arc(0, 360 * progress, r * 0.968), with: .color(remaining < 30 ? .red : .white.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            // The blue jog ring, with the loop (orange) and cue point (orange tick) when within a turn,
            // and rekordbox's red position dot
            let ring = r * 0.82
            let ringWidth = max(4, r * 0.045)
            context.stroke(circle(ring), with: .color(Theme.accent.opacity(mode == .bend ? 1 : 0.85)), lineWidth: ringWidth)
            if let loop, loop.end - loop.start < secondsPerTurn {
                context.stroke(arc(angle(loop.start), angle(loop.end), ring), with: .color(Theme.loop.opacity(0.9)), lineWidth: ringWidth)
            }
            if loaded, abs(cueOffset) < secondsPerTurn {
                var tick = Path()
                tick.move(to: point(angle(cueOffset), ring - ringWidth))
                tick.addLine(to: point(angle(cueOffset), ring + ringWidth))
                context.stroke(tick, with: .color(Theme.cue), lineWidth: 2.5)
            }
            let dot = point(rotation, ring)
            let dotR = ringWidth * 0.85
            context.fill(Path(ellipseIn: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(.red))

            // Platter (touch it to scratch): vinyl grooves and a turning marker
            let platter = circle(ring - ringWidth / 2)
            context.fill(platter, with: .color(mode == .scratch ? Color(white: 0.11) : .black))
            var grooves = Path()
            for k in 0..<14 { grooves.addPath(circle(r * (0.46 + CGFloat(k) * 0.022))) }
            context.stroke(grooves, with: .color(.white.opacity(0.035)), lineWidth: 0.75)
            var marker = Path()
            marker.move(to: point(rotation, r * 0.6))
            marker.addLine(to: point(rotation, r * 0.76))
            context.stroke(marker, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(2, r * 0.018), lineCap: .round))

            // Centre readout: time left, BPM with small decimals like rekordbox, tempo and range
            let whole = bpm.prefix { $0 != "." }, fraction = bpm.drop { $0 != "." }
            context.draw(Text(loaded ? "-" + DeckInfo.tenths(remaining) : "--:--.-")
                            .font(Theme.readout(r * 0.075))
                            .foregroundStyle(loaded && remaining < 30 ? Color.red : Theme.dim),
                         at: CGPoint(x: c.x, y: c.y - r * 0.2))
            context.draw((Text(whole).font(Theme.readout(r * 0.2, .medium)) + Text(fraction).font(Theme.readout(r * 0.12, .medium)))
                            .foregroundStyle(deck.syncOn ? Theme.accent : Color.white),
                         at: CGPoint(x: c.x, y: c.y + r * 0.02))
            context.draw(Text("\(tempo)  \(range)")
                            .font(Theme.readout(r * 0.07))
                            .foregroundStyle(Theme.dim),
                         at: CGPoint(x: c.x, y: c.y + r * 0.2))
        }
        .frame(width: size, height: size)
    }
}
