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
            // Only what moves is redrawn every frame; the gradients and the shadow are drawn once.
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                movingParts(size: size)
            }
            .background(fixedParts(size: size))
            .background(Circle().fill(Color.black).shadow(color: .black.opacity(0.85), radius: 7, y: 4))
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

    /// The parts of the wheel that don't move: housing, brushed-metal grip ring, LED ring glow,
    /// vinyl platter and the jog display's bezel. Redrawn only when a touch changes the lighting.
    private func fixedParts(size: CGFloat) -> some View {
        let mode = self.mode
        return Canvas { context, canvas in
            let g = JogGeometry(canvas)
            let r = g.r, c = g.c

            // Housing: a bevelled well the wheel sits in
            context.fill(g.circle(r), with: .linearGradient(Gradient(colors: [Color(white: 0.02), Color(white: 0.2)]),
                                                            startPoint: CGPoint(x: c.x - r, y: c.y - r), endPoint: CGPoint(x: c.x + r, y: c.y + r)))

            // Grip ring (touch it to bend): brushed metal lit from the top left
            let metal = mode == .bend ? [0.75, 0.38, 0.62, 0.3, 0.7, 0.36, 0.58, 0.32, 0.75] : [0.62, 0.26, 0.5, 0.2, 0.58, 0.24, 0.46, 0.22, 0.62]
            context.fill(g.ring(g.gripOuter, g.gripInner),
                         with: .conicGradient(Gradient(colors: metal.map { Color(white: $0) }), center: c, angle: .degrees(-40)),
                         style: FillStyle(eoFill: true))
            context.stroke(g.circle(g.gripOuter), with: .color(.white.opacity(0.35)), lineWidth: 1)
            context.stroke(g.circle(g.gripInner), with: .color(.black.opacity(0.8)), lineWidth: 1.5)

            // Blue LED ring with a soft glow
            for (width, alpha) in [(g.ledWidth * 4, 0.1), (g.ledWidth * 2.2, 0.22), (g.ledWidth, 1.0)] {
                context.stroke(g.circle(g.led), with: .color(Theme.accent.opacity(alpha * (mode == .bend ? 1 : 0.85))), lineWidth: width)
            }

            // Platter (touch it to scratch): vinyl grooves and a fixed sheen
            let platter = g.circle(g.platter)
            context.fill(platter, with: .radialGradient(Gradient(colors: [Color(white: 0.13), Color(white: 0.03)]),
                                                        center: c, startRadius: 0, endRadius: g.platter))
            var grooves = Path()
            for k in 0..<22 { grooves.addPath(g.circle(r * 0.47 + CGFloat(k) * (g.platter - r * 0.49) / 22)) }
            context.stroke(grooves, with: .color(.white.opacity(0.04)), lineWidth: 0.75)
            context.fill(platter, with: .conicGradient(Gradient(colors: [.clear, .white.opacity(0.09), .clear, .clear, .white.opacity(0.07), .clear, .clear]),
                                                       center: c, angle: .degrees(-20)))
            if mode == .scratch { context.fill(platter, with: .color(Theme.accent.opacity(0.1))) }

            // Jog display: bezel, screen, and the progress ring's track
            context.fill(g.circle(g.bezel), with: .linearGradient(Gradient(colors: [Color(white: 0.32), Color(white: 0.08)]),
                                                                  startPoint: CGPoint(x: c.x, y: c.y - g.bezel), endPoint: CGPoint(x: c.x, y: c.y + g.bezel)))
            context.fill(g.circle(g.screen), with: .color(Theme.well))
            context.stroke(g.circle(g.screen - 4), with: .color(.white.opacity(0.08)), lineWidth: 2.5)
        }
        .frame(width: size, height: size)
    }

    /// The parts that move with the playhead, redrawn every frame: knurling, platter marker, red dot,
    /// the cue point and loop on the LED ring when they're within a turn, and the jog display's
    /// progress, time left, BPM and tempo.
    private func movingParts(size: CGFloat) -> some View {
        let position = deck.position
        let rotation = position / secondsPerTurn * 360
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
        let synced = deck.syncOn
        return Canvas { context, canvas in
            let g = JogGeometry(canvas)
            let r = g.r, c = g.c
            /// Where a time offset from the playhead sits on the turning ring.
            func angle(_ seconds: Double) -> Double { rotation + seconds / secondsPerTurn * 360 }

            var knurl = Path()
            for i in 0..<180 {
                let a = Double(i) * 2 + rotation
                knurl.move(to: g.point(a, g.gripInner + 1))
                knurl.addLine(to: g.point(a, g.gripOuter - 1))
            }
            context.stroke(knurl, with: .color(.black.opacity(0.4)), lineWidth: 0.8)

            if let loop, loop.end - loop.start < secondsPerTurn {
                context.stroke(g.arc(angle(loop.start), angle(loop.end), g.led), with: .color(Theme.loop), lineWidth: g.ledWidth * 1.4)
            }
            if loaded, abs(cueOffset) < secondsPerTurn {
                var tick = Path()
                tick.move(to: g.point(angle(cueOffset), g.led - g.ledWidth * 2))
                tick.addLine(to: g.point(angle(cueOffset), g.led + g.ledWidth * 2))
                context.stroke(tick, with: .color(Theme.cue), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            let dot = g.point(rotation, g.led)
            let dotR = g.ledWidth * 1.3
            context.fill(Path(ellipseIn: CGRect(x: dot.x - dotR * 2, y: dot.y - dotR * 2, width: dotR * 4, height: dotR * 4)),
                         with: .color(.red.opacity(0.25)))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - dotR, y: dot.y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(.red))

            var marker = Path()
            marker.move(to: g.point(rotation, r * 0.5))
            marker.addLine(to: g.point(rotation, g.platter - 4))
            context.stroke(marker, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: max(2.5, r * 0.02), lineCap: .round))

            if progress > 0 {
                context.stroke(g.arc(0, 360 * progress, g.screen - 4), with: .color(remaining < 30 ? .red : Theme.accent),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            let whole = bpm.prefix { $0 != "." }, fraction = bpm.drop { $0 != "." }
            context.draw(Text(loaded ? "-" + DeckInfo.tenths(remaining) : "--:--.-")
                            .font(Theme.readout(r * 0.07, .medium))
                            .foregroundStyle(loaded && remaining < 30 ? Color.red : Theme.dim),
                         at: CGPoint(x: c.x, y: c.y - r * 0.2))
            context.draw((Text(whole).font(Theme.readout(r * 0.19, .semibold)) + Text(fraction).font(Theme.readout(r * 0.11, .semibold)))
                            .foregroundStyle(synced ? Theme.accent : Color.white),
                         at: CGPoint(x: c.x, y: c.y + r * 0.01))
            context.draw(Text("\(tempo)  \(range)")
                            .font(Theme.readout(r * 0.066, .medium))
                            .foregroundStyle(Theme.dim),
                         at: CGPoint(x: c.x, y: c.y + r * 0.19))
        }
        .frame(width: size, height: size)
    }
}

/// Radii and drawing helpers shared by the jog wheel's fixed and moving layers.
private struct JogGeometry {
    let r: CGFloat
    let c: CGPoint

    init(_ canvas: CGSize) {
        r = min(canvas.width, canvas.height) / 2
        c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
    }

    var gripOuter: CGFloat { r * 0.965 }
    var gripInner: CGFloat { r * 0.855 }
    var led: CGFloat { r * 0.83 }
    var ledWidth: CGFloat { max(3, r * 0.03) }
    var platter: CGFloat { led - ledWidth * 1.2 }
    var bezel: CGFloat { r * 0.46 }
    var screen: CGFloat { r * 0.43 }

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

    func ring(_ outer: CGFloat, _ inner: CGFloat) -> Path {
        var path = circle(outer)
        path.addPath(circle(inner))
        return path
    }
}
