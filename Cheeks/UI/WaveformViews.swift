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
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.panel))
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

        // Waveform: low (blue) outermost, mid (amber), high (white) innermost
        let bps = WaveformData.binsPerSecond
        let firstBin = max(0, Int(start * bps))
        let lastBin = min(wave.count - 1, Int((start + secondsVisible) * bps))
        if firstBin <= lastBin {
            var low = Path(), mid = Path(), high = Path()
            let binWidth = max(1, pxPerSecond / bps)
            for b in firstBin...lastBin {
                let bx = x(Double(b) / bps)
                let l = CGFloat(wave.low[b]) / 255 * midY
                let m = CGFloat(wave.mid[b]) / 255 * midY
                let hi = CGFloat(wave.high[b]) / 255 * midY
                low.addRect(CGRect(x: bx, y: midY - l, width: binWidth, height: l * 2))
                mid.addRect(CGRect(x: bx, y: midY - m * 0.8, width: binWidth, height: m * 1.6))
                high.addRect(CGRect(x: bx, y: midY - hi * 0.6, width: binWidth, height: hi * 1.2))
            }
            context.fill(low, with: .color(Theme.waveLow))
            context.fill(mid, with: .color(Theme.waveMid))
            context.fill(high, with: .color(Theme.waveHigh.opacity(0.9)))
        }

        // Beat grid (bar lines in red every 4 beats)
        if deck.bpm > 0 {
            let beat = 60 / deck.bpm
            let first = deck.track?.firstBeat ?? 0
            var k = ((start - first) / beat).rounded(.up)
            while first + k * beat < start + secondsVisible {
                let bx = x(first + k * beat)
                let isBar = (Int(k) % 4 + 4) % 4 == 0
                context.fill(Path(CGRect(x: bx, y: 0, width: isBar ? 1.5 : 1, height: isBar ? h : h * 0.12)),
                             with: .color(isBar ? .red.opacity(0.8) : .white.opacity(0.5)))
                k += 1
            }
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

        // Playhead
        context.fill(Path(CGRect(x: w / 2 - 1, y: 0, width: 2, height: h)), with: .color(.white))
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

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.5)))
        guard let wave = deck.waveform, deck.isLoaded, wave.count > 0 else { return }
        let columns = max(1, Int(size.width / 2))
        let binsPerColumn = max(1, wave.count / columns)
        let progress = deck.position / max(deck.duration, 0.001)
        let midY = size.height / 2
        var played = Path(), upcoming = Path()
        for c in 0..<columns {
            let start = c * binsPerColumn
            guard start < wave.count else { break }
            var peak: UInt8 = 0
            for b in start..<min(start + binsPerColumn, wave.count) {
                peak = max(peak, wave.low[b], wave.mid[b], wave.high[b])
            }
            let hgt = CGFloat(peak) / 255 * midY
            let rect = CGRect(x: CGFloat(c) * 2, y: midY - hgt, width: 1.5, height: max(1, hgt * 2))
            if Double(c) / Double(columns) < progress { played.addRect(rect) } else { upcoming.addRect(rect) }
        }
        context.fill(played, with: .color(Color.white.opacity(0.3)))
        context.fill(upcoming, with: .color(Theme.deckColors[deck.index].opacity(0.85)))

        for (slot, time) in deck.track?.hotCues ?? [:] {
            let cx = CGFloat(time / deck.duration) * size.width
            context.fill(Path(CGRect(x: cx, y: 0, width: 2, height: size.height)), with: .color(Theme.hotCueColors[slot % 8]))
        }
        let px = CGFloat(progress) * size.width
        context.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(.red))
    }
}
