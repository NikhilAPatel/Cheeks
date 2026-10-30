import SwiftUI

/// Zoomed, scrolling 3-band waveform centred on the playhead, with beat grid, cues and loop.
/// Drag to scratch/scrub, pinch to zoom.
struct ScrollingWaveform: View {
    let deck: Deck
    @State private var secondsVisible: Double = 8
    @State private var zoomBase: Double?
    @State private var lastDragX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            // 60 fps is plenty for a scrolling waveform and halves the work on 120 Hz screens.
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                Canvas { context, size in
                    draw(&context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        let pxPerSecond = geo.size.width / secondsVisible
                        if lastDragX == nil {
                            deck.scratchBegin()
                            lastDragX = g.startLocation.x
                        }
                        let dx = g.location.x - (lastDragX ?? g.location.x)
                        lastDragX = g.location.x
                        deck.scratchMove(seconds: -Double(dx) / pxPerSecond)
                    }
                    .onEnded { _ in
                        lastDragX = nil
                        deck.scratchEnd()
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { g in
                        if zoomBase == nil { zoomBase = secondsVisible }
                        secondsVisible = min(32, max(2, zoomBase! / g.magnification))
                    }
                    .onEnded { _ in zoomBase = nil }
            )
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, midY = h / 2
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.well))
        guard let wave = deck.waveform, deck.isLoaded else { return }

        let sr = deck.sampleRate
        let pos = deck.position
        let pxPerSecond = w / secondsVisible
        let start = pos - secondsVisible / 2
        func x(_ t: Double) -> CGFloat { CGFloat((t - start) * pxPerSecond) }

        // Loop region
        let r = deck.renderer
        if r.loopActive {
            let x0 = x(r.loopStart / sr), x1 = x(r.loopEnd / sr)
            context.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: h)), with: .color(Theme.loop.opacity(0.18)))
        }

        // Waveform: low (blue) outermost, mid (amber), high (white) innermost, each a smooth
        // mirrored envelope through the bin peaks rather than blocky bars
        let bps = WaveformData.binsPerSecond
        let firstBin = max(0, Int(start * bps))
        let lastBin = min(wave.count - 1, Int((start + secondsVisible) * bps) + 1)
        if firstBin < lastBin {
            func envelope(_ values: [UInt8], _ scale: CGFloat) -> Path {
                var top: [CGPoint] = [], bottom: [CGPoint] = []
                top.reserveCapacity(lastBin - firstBin + 1)
                bottom.reserveCapacity(lastBin - firstBin + 1)
                for b in firstBin...lastBin {
                    let bx = x(Double(b) / bps)
                    let v = CGFloat(values[b]) / 255 * (midY - 1) * scale
                    top.append(CGPoint(x: bx, y: midY - v))
                    bottom.append(CGPoint(x: bx, y: midY + v))
                }
                var path = Path()
                path.addLines(top + bottom.reversed())
                path.closeSubpath()
                return path
            }
            context.fill(envelope(wave.low, 1), with: .color(Theme.waveLow))
            context.fill(envelope(wave.mid, 0.8), with: .color(Theme.waveMid))
            context.fill(envelope(wave.high, 0.55), with: .color(Theme.waveHigh))
        }

        // Beat grid as rekordbox draws it: faint lines on every beat, red marks top and bottom on each bar
        if deck.bpm > 0 {
            let beat = 60 / deck.bpm
            let first = deck.track?.firstBeat ?? 0
            var k = ((start - first) / beat).rounded(.up)
            var beats = Path(), bars = Path()
            while first + k * beat < start + secondsVisible {
                let bx = x(first + k * beat)
                beats.addRect(CGRect(x: bx, y: 0, width: 1, height: h))
                if (Int(k) % 4 + 4) % 4 == 0 {
                    bars.move(to: CGPoint(x: bx - 4, y: 0))
                    bars.addLine(to: CGPoint(x: bx + 4, y: 0))
                    bars.addLine(to: CGPoint(x: bx, y: 6))
                    bars.move(to: CGPoint(x: bx - 4, y: h))
                    bars.addLine(to: CGPoint(x: bx + 4, y: h))
                    bars.addLine(to: CGPoint(x: bx, y: h - 6))
                }
                k += 1
            }
            context.fill(beats, with: .color(.white.opacity(0.22)))
            context.fill(bars, with: .color(.red))
        }

        // Hot cues and cue point
        for (slot, time) in deck.track?.hotCues ?? [:] {
            let cx = x(time)
            guard cx > -20, cx < w + 20 else { continue }
            let color = Theme.hotCueColors[slot % 8]
            context.fill(Path(CGRect(x: cx, y: 0, width: 1.5, height: h)), with: .color(color))
            context.fill(Path(roundedRect: CGRect(x: cx, y: 0, width: 13, height: 13), cornerRadius: 2), with: .color(color))
            context.draw(Text(Theme.hotCueLetters[slot % 8]).font(.system(size: 9, weight: .heavy)).foregroundStyle(.black),
                         at: CGPoint(x: cx + 6.5, y: 6.5))
        }
        let cueX = x(deck.cuePoint)
        var tri = Path()
        tri.move(to: CGPoint(x: cueX - 6, y: h))
        tri.addLine(to: CGPoint(x: cueX + 6, y: h))
        tri.addLine(to: CGPoint(x: cueX, y: h - 8))
        context.fill(tri, with: .color(Theme.cue))

        // Playhead, with the bar and beat it's on (rekordbox shows its bar count in blue here)
        context.fill(Path(CGRect(x: w / 2 - 1, y: 0, width: 2, height: h)), with: .color(.white))
        if deck.bpm > 0 {
            let beats = (pos - (deck.track?.firstBeat ?? 0)) / (60 / deck.bpm)
            if beats >= 0 {
                let label = "\(Int(beats / 4) + 1).\(Int(beats.truncatingRemainder(dividingBy: 4)) + 1) Bars"
                context.draw(Text(label).font(Theme.readout(10, .semibold)).foregroundStyle(Theme.accent),
                             at: CGPoint(x: w / 2 - 4, y: 8), anchor: .trailing)
            }
        }
    }
}

/// Whole-track overview with progress, cues and needle search (tap/drag to jump).
struct OverviewWaveform: View {
    let deck: Deck

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1.0 / 15)) { _ in
                Canvas { context, size in draw(&context, size: size) }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    guard deck.isLoaded else { return }
                    let fraction = min(1, max(0, g.location.x / geo.size.width))
                    deck.seek(to: Double(fraction) * deck.duration)
                }
            )
        }
    }

    /// rekordbox's overview: a one-sided 3-band waveform, grey where it has played,
    /// with lettered hot cue flags along the top and the memory cue as a red marker.
    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.well))
        guard let wave = deck.waveform, deck.isLoaded, wave.count > 0 else { return }
        let flag: CGFloat = 10
        let base = size.height, height = size.height - flag
        let columns = max(1, Int(size.width))
        let binsPerColumn = max(1, wave.count / columns)
        let progress = deck.position / max(deck.duration, 0.001)
        var played = Path(), low = Path(), mid = Path(), high = Path()
        func bar(_ x: CGFloat, _ value: UInt8, _ scale: CGFloat) -> CGRect {
            let hgt = max(1, CGFloat(value) / 255 * height * scale)
            return CGRect(x: x, y: base - hgt, width: 1, height: hgt)
        }
        for c in 0..<columns {
            let start = c * binsPerColumn
            guard start < wave.count else { break }
            var l: UInt8 = 0, m: UInt8 = 0, hi: UInt8 = 0
            for b in start..<min(start + binsPerColumn, wave.count) {
                l = max(l, wave.low[b])
                m = max(m, wave.mid[b])
                hi = max(hi, wave.high[b])
            }
            let x = CGFloat(c)
            if Double(c) / Double(columns) < progress {
                played.addRect(bar(x, max(l, m, hi), 1))
            } else {
                low.addRect(bar(x, l, 1))
                mid.addRect(bar(x, m, 0.8))
                high.addRect(bar(x, hi, 0.55))
            }
        }
        context.fill(played, with: .color(Color(white: 0.4)))
        context.fill(low, with: .color(Theme.waveLow))
        context.fill(mid, with: .color(Theme.waveMid))
        context.fill(high, with: .color(Theme.waveHigh))

        for (slot, time) in deck.track?.hotCues ?? [:] {
            let cx = CGFloat(time / deck.duration) * size.width
            let color = Theme.hotCueColors[slot % 8]
            context.fill(Path(CGRect(x: cx, y: 0, width: 1, height: size.height)), with: .color(color))
            context.fill(Path(CGRect(x: cx, y: 0, width: 10, height: flag)), with: .color(color))
            context.draw(Text(Theme.hotCueLetters[slot % 8]).font(.system(size: 8, weight: .bold)).foregroundStyle(.white),
                         at: CGPoint(x: cx + 5, y: flag / 2))
        }
        if let memory = deck.track?.memoryCue {
            let mx = CGFloat(memory / deck.duration) * size.width
            var tri = Path()
            tri.move(to: CGPoint(x: mx - 4, y: 0))
            tri.addLine(to: CGPoint(x: mx + 4, y: 0))
            tri.addLine(to: CGPoint(x: mx, y: 6))
            context.fill(tri, with: .color(.red))
        }
        let px = CGFloat(min(1, progress)) * size.width
        context.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
    }
}
