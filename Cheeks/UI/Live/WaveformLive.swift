import Metal
import SwiftUI
import UIKit

/// How the waveforms are shown. Both decks share it, so beats line up on screen when they're matched.
@MainActor
final class WaveformDisplay {
    static let shared = WaveformDisplay()
    /// Seconds of real time visible across the view.
    var secondsVisible: Double = 8
    /// 0 = rekordbox 3-band, 1 = RGB.
    var colorStyle: Int32 = Int32(UserDefaults.standard.integer(forKey: "waveformStyle")) {
        didSet { UserDefaults.standard.set(Int(colorStyle), forKey: "waveformStyle") }
    }
    /// Where the playhead sits across the view. Off-centre, so more of what's coming is visible,
    /// and clear of the Duo's centre crease.
    static let playheadFraction: Float = 0.36
}

/// Packs waveform bins into a texture for the shader: 4 channels per bin, one row of the atlas per
/// `WAVE_ROW_WIDTH` bins, followed by max-pooled copies for zoomed-out views, so nothing shimmers.
struct WaveAtlas {
    let texture: MTLTexture
    let levelRow: [Int32]
    let levelCount: [Int32]

    @MainActor
    init?(channels: [[UInt8]]) {
        let count = channels.first?.count ?? 0
        guard count > 0 else { return nil }
        let rowWidth = Int(WAVE_ROW_WIDTH), levels = Int(WAVE_LEVELS)
        var data: [[UInt8]] = []
        var interleaved = [UInt8](repeating: 0, count: count * 4)
        for c in 0..<4 {
            guard c < channels.count else { continue }
            let source = channels[c]
            for i in 0..<count { interleaved[i * 4 + c] = source[i] }
        }
        data.append(interleaved)
        for _ in 1..<levels {
            let previous = data.last!
            let n = previous.count / 4
            let half = (n + 1) / 2
            var next = [UInt8](repeating: 0, count: half * 4)
            for i in 0..<half {
                for c in 0..<4 {
                    let a = previous[i * 8 + c]
                    let b = i * 2 + 1 < n ? previous[i * 8 + 4 + c] : a
                    next[i * 4 + c] = max(a, b)
                }
            }
            data.append(next)
        }
        var rows: [Int32] = []
        var counts: [Int32] = []
        var totalRows = 0
        for level in data {
            rows.append(Int32(totalRows))
            let n = level.count / 4
            counts.append(Int32(n))
            totalRows += (n + rowWidth - 1) / rowWidth
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: rowWidth, height: max(1, totalRows), mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = LiveRenderer.shared.device.makeTexture(descriptor: descriptor) else { return nil }
        for (l, level) in data.enumerated() {
            let n = level.count / 4
            level.withUnsafeBytes { raw in
                var row = 0
                var start = 0
                while start < n {
                    let width = min(rowWidth, n - start)
                    texture.replace(region: MTLRegionMake2D(0, Int(rows[l]) + row, width, 1), mipmapLevel: 0,
                                    withBytes: raw.baseAddress! + start * 4, bytesPerRow: rowWidth * 4)
                    start += width
                    row += 1
                }
            }
        }
        self.texture = texture
        levelRow = rows
        levelCount = counts
    }
}

/// A song's sections as a strip of colour along the track, for the shaders to look up.
@MainActor
enum PhraseStripTexture {
    private static let width = 2048

    static func make(phrases: [Phrase], duration: Double) -> MTLTexture? {
        guard !phrases.isEmpty, duration > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * 4)
        for (i, phrase) in phrases.enumerated() {
            let end = i + 1 < phrases.count ? phrases[i + 1].start : duration
            let color = Theme.phraseColor(phrase.kind).simd
            let from = max(0, Int(phrase.start / duration * Double(width)))
            let to = min(width, Int((end / duration * Double(width)).rounded(.up)))
            guard from < to else { continue }
            for x in from..<to {
                bytes[x * 4] = UInt8(color.x * 255)
                bytes[x * 4 + 1] = UInt8(color.y * 255)
                bytes[x * 4 + 2] = UInt8(color.z * 255)
                bytes[x * 4 + 3] = 255
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = LiveRenderer.shared.device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }
}

extension Deck {
    /// Memory cues and saved loops for the shaders: start, and end for a loop or -1 for a cue.
    var liveMarks: [SIMD4<Float>] {
        guard let track else { return [.zero] }
        var marks: [SIMD4<Float>] = []
        for cue in track.memoryCues.prefix(Int(WAVE_MAX_MARKS) / 2) { marks.append(SIMD4(Float(cue.time), -1, 0, 0)) }
        for loop in track.savedLoops.prefix(Int(WAVE_MAX_MARKS) / 2) { marks.append(SIMD4(Float(loop.start), Float(loop.end), 0, 0)) }
        return marks.isEmpty ? [.zero] : marks
    }

    var liveMarkCount: Int32 {
        guard let track else { return 0 }
        return Int32(min(track.memoryCues.count, Int(WAVE_MAX_MARKS) / 2) + min(track.savedLoops.count, Int(WAVE_MAX_MARKS) / 2))
    }
}

/// The scrolling waveform. Drag it to scratch through the track, pinch to zoom, double-tap to reset zoom.
final class WaveformLiveView: LiveView {
    private let deck: Deck
    private var uniforms = WaveUniforms()
    private var lastDrawn = WaveUniforms()
    private var lastCues: [SIMD4<Float>] = []
    private var cues: [SIMD4<Float>] = []
    private var sections: [SIMD4<Float>] = [.zero]
    private var lastSections: [SIMD4<Float>] = []
    private var marks: [SIMD4<Float>] = [.zero]
    private var lastMarks: [SIMD4<Float>] = []
    private var needsDraw = true

    private var atlasOwner: Int = -1
    private var bands: WaveAtlas?
    private var stems: WaveAtlas?
    private var stemsOwner: Int = -1
    private var phraseStrip: MTLTexture?
    private var phrasesOwner: [Phrase]?

    private var revealStart: CFTimeInterval = 0
    private var stemBlend: Float = 0
    private var stemGains = SIMD4<Float>(repeating: 1)
    private var lastFrameTime: CFTimeInterval = 0

    private var dragLastX: CGFloat?
    private var zoomBase: Double?
    private var lastBeatIndex: Int?

    init(deck: Deck) {
        self.deck = deck
        super.init(frame: .zero)
        metalLayer.isOpaque = true
        isOpaque = true
        uniforms.lowColor = Theme.waveLow.simd
        uniforms.midColor = Theme.waveMid.simd
        uniforms.highColor = Theme.waveHigh.simd
        withUnsafeMutablePointer(to: &uniforms.stemColors) { tuple in
            tuple.withMemoryRebound(to: SIMD4<Float>.self, capacity: 4) { colors in
                for stem in Stem.allCases { colors[stem.rawValue] = stem.color.simd }
            }
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isMultipleTouchEnabled = true
    }

    override func forceRedraw() { needsDraw = true }

    override func update(hostTime: UInt64) -> Bool {
        let renderer = LiveRenderer.shared
        let display = WaveformDisplay.shared
        let now = CACurrentMediaTime()
        let dt = lastFrameTime == 0 ? 1.0 / 60 : min(0.1, now - lastFrameTime)
        lastFrameTime = now

        if atlasOwner != deck.waveRevision {
            atlasOwner = deck.waveRevision
            bands = deck.waveform.flatMap { WaveAtlas(channels: [$0.low, $0.mid, $0.high]) }
            revealStart = bands == nil ? 0 : now
            lastBeatIndex = nil
        }
        if stemsOwner != deck.stemWaveRevision {
            stemsOwner = deck.stemWaveRevision
            stems = deck.stemWaveform.flatMap { WaveAtlas(channels: $0.levels) }
        }

        if phrasesOwner != deck.track?.phrases {
            phrasesOwner = deck.track?.phrases
            phraseStrip = phrasesOwner.flatMap { PhraseStripTexture.make(phrases: $0, duration: deck.duration) }
        }

        var u = uniforms
        u.size = drawablePixels
        u.scale = Float(metalLayer.contentsScale)
        u.hasPhrases = phraseStrip == nil ? 0 : 1
        let loaded = bands != nil && deck.isLoaded
        u.loaded = loaded ? 1 : 0
        u.colorStyle = display.colorStyle
        let width = Double(u.size.x)
        u.playheadX = u.size.x * WaveformDisplay.playheadFraction

        let sr = deck.sampleRate
        let position = deck.heardFrame(hostTime: hostTime, secondsPerTick: renderer.secondsPerTick, outputLatency: deck.outputLatency) / sr
        // Time on screen is real time, so a deck playing faster is drawn compressed. That's what
        // makes matched beats line up between the two waveforms.
        let secondsPerPixel = display.secondsVisible * deck.tempoRatio / width
        u.secondsPerPixel = Float(secondsPerPixel)
        u.startSeconds = Float(position - Double(u.playheadX) * secondsPerPixel)
        u.position = Float(position)
        u.duration = Float(deck.duration)
        u.binsPerSecond = Float(WaveformData.binsPerSecond)
        u.binsPerPixel = Float(secondsPerPixel * WaveformData.binsPerSecond)
        u.level = Int32(max(0, min(Int(WAVE_LEVELS) - 1, Int(ceil(log2(max(1, Double(u.binsPerPixel))))))))
        if let bands {
            withUnsafeMutablePointer(to: &u.levelRow) { $0.withMemoryRebound(to: Int32.self, capacity: Int(WAVE_LEVELS)) { p in
                for i in 0..<Int(WAVE_LEVELS) { p[i] = bands.levelRow[i] }
            } }
            withUnsafeMutablePointer(to: &u.levelCount) { $0.withMemoryRebound(to: Int32.self, capacity: Int(WAVE_LEVELS)) { p in
                for i in 0..<Int(WAVE_LEVELS) { p[i] = bands.levelCount[i] }
            } }
        }

        // The tempo sections on screen, for the beat lines. Almost always just one.
        if let grid = deck.grid {
            let span = (Double(u.startSeconds), Double(u.startSeconds) + width * secondsPerPixel)
            sections = Self.visibleSections(grid, from: span.0, to: span.1)
        } else {
            sections = [.zero]
        }
        u.sectionCount = deck.grid == nil ? 0 : Int32(sections.count)
        let r = deck.renderer
        let hasLoop = r.loopEnd > r.loopStart
        // After IN and before OUT, a loop too short to see leaves just its start line.
        u.loopStart = hasLoop || deck.loopInSet ? Float(r.loopStart / sr) : -1
        u.loopEnd = hasLoop ? Float(r.loopEnd / sr) : deck.loopInSet ? Float(r.loopStart / sr) + 0.001 : -1
        u.loopActive = r.loopActive ? 1 : 0
        u.cuePoint = Float(deck.cuePoint)
        marks = deck.liveMarks
        u.markCount = deck.liveMarkCount

        var newCues = [SIMD4<Float>](repeating: .zero, count: Int(WAVE_MAX_CUES) * 2)
        var count = 0
        if let hotCues = deck.track?.hotCues {
            for (slot, time) in hotCues.sorted(by: { $0.key < $1.key }) where count < Int(WAVE_MAX_CUES) {
                let color = deck.hotCueColor(slot).simd
                newCues[count] = SIMD4(Float(time), color.x, color.y, color.z)
                newCues[Int(WAVE_MAX_CUES) + count] = SIMD4(Float(slot % 8), 0, 0, 0)
                count += 1
            }
        }
        cues = newCues
        u.cueCount = Int32(count)

        // Load-in, and the stems colours easing in and out.
        let reveal = revealStart == 0 ? 1 : min(1, (now - revealStart) / 0.5)
        u.reveal = UIAccessibility.isReduceMotionEnabled || renderer.captureMode ? 1 : Float(1 - pow(1 - reveal, 3))
        let wantStems: Float = deck.padMode == .stems && stems != nil ? 1 : 0
        stemBlend += (wantStems - stemBlend) * Float(min(1, dt * 10))
        if abs(wantStems - stemBlend) < 0.005 || renderer.captureMode { stemBlend = wantStems }
        u.stemBlend = stemBlend
        for stem in 0..<4 {
            let target = deck.stemsOn[stem] ? deck.stemLevels[stem] : 0
            stemGains[stem] += (target - stemGains[stem]) * Float(min(1, dt * 14))
            if abs(target - stemGains[stem]) < 0.004 || renderer.captureMode { stemGains[stem] = target }
        }
        u.stemGains = stemGains

        if deck.isPlaying, deck.bpm > 0 {
            let beats = deck.beatPosition(position * sr)
            u.beatPulse = Float(exp(-(beats - floor(beats)) * 5))
        } else {
            u.beatPulse = 0
        }

        uniforms = u
        // Skip the draw if nothing changed: a paused deck costs no GPU time at all.
        if !needsDraw && bytesEqual(u, lastDrawn) && cues == lastCues && sections == lastSections && marks == lastMarks { return false }
        lastDrawn = u
        lastCues = cues
        lastSections = sections
        lastMarks = marks
        needsDraw = false
        return true
    }

    /// Time, beat and seconds per beat of each section on screen. When a very busy tempo map has
    /// more than the shader takes, some are skipped, which can't be seen at this scale.
    static func visibleSections(_ grid: BeatGrid, from: Double, to: Double) -> [SIMD4<Float>] {
        let first = grid.sectionIndex(at: from), last = grid.sectionIndex(at: to)
        let count = last - first + 1
        let stride = max(1, (count + Int(WAVE_MAX_SECTIONS) - 2) / (Int(WAVE_MAX_SECTIONS) - 1))
        var out: [SIMD4<Float>] = []
        var i = first
        while i <= last {
            let s = grid.sections[i]
            out.append(SIMD4(Float(s.time), Float(s.beat), Float(s.secondsPerBeat), 0))
            i += stride
        }
        return out
    }

    override func encode(_ encoder: MTLRenderCommandEncoder) {
        let renderer = LiveRenderer.shared
        encoder.setRenderPipelineState(renderer.pipeline(fragment: "waveform_fragment"))
        withUnsafeBytes(of: &uniforms) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        cues.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        sections.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        marks.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 3) }
        encoder.setFragmentTexture(bands?.texture ?? renderer.blackTexture, index: 0)
        encoder.setFragmentTexture(stems?.texture ?? renderer.blackTexture, index: 1)
        encoder.setFragmentTexture(renderer.cueLetters, index: 2)
        encoder.setFragmentTexture(phraseStrip ?? renderer.blackTexture, index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: Touch

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard deck.isLoaded else { return }
        let x = gesture.location(in: self).x
        switch gesture.state {
        case .began:
            deck.scratchBegin()
            dragLastX = x
            lastBeatIndex = nil
            Haptics.shared.grab()
        case .changed:
            let previous = dragLastX ?? x
            dragLastX = x
            let seconds = -Double(x - previous) * WaveformDisplay.shared.secondsVisible * deck.tempoRatio / Double(max(bounds.width, 1))
            deck.scratchMove(seconds: seconds)
            feelBeats()
        default:
            dragLastX = nil
            deck.scratchEnd()
            Haptics.shared.release()
        }
    }

    /// While the waveform is being moved by hand, the beat grid is something you can feel.
    private func feelBeats() {
        guard deck.bpm > 0 else { return }
        let beats = deck.beatPosition(deck.renderer.scratchTarget)
        let index = Int(floor(beats))
        if let last = lastBeatIndex, last != index {
            Haptics.shared.beat(isBar: (index % 4 + 4) % 4 == 0)
        }
        lastBeatIndex = index
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        let display = WaveformDisplay.shared
        switch gesture.state {
        case .began:
            zoomBase = display.secondsVisible
        case .changed:
            let wanted = (zoomBase ?? 8) / Double(max(gesture.scale, 0.01))
            let clamped = min(32, max(2, wanted))
            // A soft stop at each end of the zoom range.
            if clamped != display.secondsVisible && (clamped == 2 || clamped == 32) { Haptics.shared.detent() }
            display.secondsVisible = clamped
        default:
            zoomBase = nil
        }
    }

    @objc private func resetZoom() {
        WaveformDisplay.shared.secondsVisible = 8
        Haptics.shared.detent()
    }
}

struct ScrollingWaveform: UIViewRepresentable {
    let deck: Deck
    func makeUIView(context: Context) -> WaveformLiveView { WaveformLiveView(deck: deck) }
    func updateUIView(_ view: WaveformLiveView, context: Context) {}
}

// MARK: Overview

/// The whole track, full width. Touch it anywhere to needle-search.
final class OverviewLiveView: LiveView {
    private let deck: Deck
    private var uniforms = OverviewUniforms()
    private var lastDrawn = OverviewUniforms()
    private var cues: [SIMD4<Float>] = []
    private var lastCues: [SIMD4<Float>] = []
    private var marks: [SIMD4<Float>] = [.zero]
    private var lastMarks: [SIMD4<Float>] = []
    private var needsDraw = true
    private var columns: MTLTexture?
    private var owner = -1
    private var phraseStrip: MTLTexture?
    private var phrasesOwner: [Phrase]?
    private var hover: Float = 0
    private var touching = false

    init(deck: Deck) {
        self.deck = deck
        super.init(frame: .zero)
        metalLayer.isOpaque = true
        isOpaque = true
        uniforms.lowColor = Theme.waveLow.simd
        uniforms.midColor = Theme.waveMid.simd
        uniforms.highColor = Theme.waveHigh.simd
    }

    override func forceRedraw() { needsDraw = true }

    private func makeColumns(_ wave: WaveformData) -> MTLTexture? {
        let width = min(2048, max(1, wave.count))
        var bytes = [UInt8](repeating: 0, count: width * 4)
        let perColumn = max(1, wave.count / width)
        for c in 0..<width {
            let start = c * wave.count / width
            var low: UInt8 = 0, mid: UInt8 = 0, high: UInt8 = 0
            for b in start..<min(start + perColumn, wave.count) {
                low = max(low, wave.low[b])
                mid = max(mid, wave.mid[b])
                high = max(high, wave.high[b])
            }
            bytes[c * 4] = low
            bytes[c * 4 + 1] = mid
            bytes[c * 4 + 2] = high
            bytes[c * 4 + 3] = 255
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = LiveRenderer.shared.device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }

    override func update(hostTime: UInt64) -> Bool {
        if owner != deck.waveRevision {
            owner = deck.waveRevision
            columns = deck.waveform.flatMap(makeColumns)
        }
        if phrasesOwner != deck.track?.phrases {
            phrasesOwner = deck.track?.phrases
            phraseStrip = phrasesOwner.flatMap { PhraseStripTexture.make(phrases: $0, duration: deck.duration) }
        }
        var u = uniforms
        u.hasPhrases = phraseStrip == nil ? 0 : 1
        u.size = drawablePixels
        u.scale = Float(metalLayer.contentsScale)
        let loaded = columns != nil && deck.isLoaded
        let duration = loaded ? deck.duration : 0
        u.duration = Float(duration)
        let position = deck.position
        // Coarse steps are enough at this scale, and they let most frames skip the draw.
        u.progress = duration > 0 ? (Float(position / duration) * u.size.x).rounded() / max(u.size.x, 1) : 0
        let remaining = duration - position
        let blink = deck.isPlaying && remaining < 30 && duration > 30 ? (sin(CACurrentMediaTime() * 6) * 0.5 + 0.5) : 0
        u.warn = Float(blink)
        let r = deck.renderer
        let hasLoop = r.loopEnd > r.loopStart
        u.loopStart = hasLoop || deck.loopInSet ? Float(r.loopStart / deck.sampleRate) : -1
        u.loopEnd = hasLoop ? Float(r.loopEnd / deck.sampleRate) : deck.loopInSet ? Float(r.loopStart / deck.sampleRate) + 0.001 : -1
        u.loopActive = r.loopActive ? 1 : 0
        marks = deck.liveMarks
        u.markCount = deck.liveMarkCount
        u.cuePoint = Float(deck.cuePoint)
        hover += ((touching ? 1 : 0) - hover) * 0.25
        if abs((touching ? 1 : 0) - hover) < 0.01 { hover = touching ? 1 : 0 }
        u.hover = hover

        var newCues: [SIMD4<Float>] = []
        for (slot, time) in (deck.track?.hotCues ?? [:]).sorted(by: { $0.key < $1.key }) {
            let color = deck.hotCueColor(slot).simd
            newCues.append(SIMD4(Float(time), color.x, color.y, color.z))
        }
        u.cueCount = Int32(newCues.count)
        if newCues.isEmpty { newCues = [.zero] }
        cues = newCues
        uniforms = u
        if !needsDraw && bytesEqual(u, lastDrawn) && cues == lastCues && marks == lastMarks { return false }
        lastDrawn = u
        lastCues = cues
        lastMarks = marks
        needsDraw = false
        return true
    }

    override func encode(_ encoder: MTLRenderCommandEncoder) {
        let renderer = LiveRenderer.shared
        encoder.setRenderPipelineState(renderer.pipeline(fragment: "overview_fragment"))
        withUnsafeBytes(of: &uniforms) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        cues.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        marks.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        encoder.setFragmentTexture(columns ?? renderer.blackTexture, index: 0)
        encoder.setFragmentTexture(renderer.cueLetters, index: 1)
        encoder.setFragmentTexture(phraseStrip ?? renderer.blackTexture, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private func needle(_ touches: Set<UITouch>) {
        guard deck.isLoaded, let touch = touches.first else { return }
        let fraction = min(1, max(0, touch.location(in: self).x / max(bounds.width, 1)))
        deck.seek(to: Double(fraction) * deck.duration)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touching = true
        Haptics.shared.grab()
        needle(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { needle(touches) }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touching = false }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touching = false }
}

struct OverviewWaveform: UIViewRepresentable {
    let deck: Deck
    func makeUIView(context: Context) -> OverviewLiveView { OverviewLiveView(deck: deck) }
    func updateUIView(_ view: OverviewLiveView, context: Context) {}
}

// MARK: Beat and phase strip

/// Four beat blocks per deck and a centre scale showing how far apart the decks are.
final class PhaseLiveView: LiveView {
    private let decks: [Deck]
    private let positions: @MainActor () -> [Double]
    private var uniforms = PhaseUniforms()
    private var lastDrawn = PhaseUniforms()
    private var needsDraw = true

    init(decks: [Deck], positions: @escaping @MainActor () -> [Double]) {
        self.decks = decks
        self.positions = positions
        super.init(frame: .zero)
        metalLayer.isOpaque = true
        isOpaque = true
        isUserInteractionEnabled = false
        uniforms.accent = Theme.accent.simd
    }

    override func forceRedraw() { needsDraw = true }

    private func beat(_ deck: Deck) -> Float {
        guard deck.isLoaded, deck.bpm > 0 else { return -1 }
        let renderer = LiveRenderer.shared
        let frame = deck.heardFrame(hostTime: mach_absolute_time(), secondsPerTick: renderer.secondsPerTick, outputLatency: deck.outputLatency)
        let beats = deck.beatPosition(frame)
        return Float((beats.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4))
    }

    override func update(hostTime: UInt64) -> Bool {
        var u = uniforms
        u.size = drawablePixels
        u.scale = Float(metalLayer.contentsScale)
        let a = decks[0], b = decks[1]
        u.beatA = beat(a)
        u.beatB = beat(b)
        u.activeA = a.isPlaying ? 1 : 0
        u.activeB = b.isPlaying ? 1 : 0
        let frames = positions()
        u.offsetBeats = Float(b.phaseOffset(to: a, frame: frames[1], masterFrame: frames[0]))
        uniforms = u
        if !needsDraw && bytesEqual(u, lastDrawn) { return false }
        lastDrawn = u
        needsDraw = false
        return true
    }

    override func encode(_ encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(LiveRenderer.shared.pipeline(fragment: "phase_fragment"))
        withUnsafeBytes(of: &uniforms) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

struct PhaseStrip: UIViewRepresentable {
    let decks: [Deck]
    let positions: @MainActor () -> [Double]
    func makeUIView(context: Context) -> PhaseLiveView { PhaseLiveView(decks: decks, positions: positions) }
    func updateUIView(_ view: PhaseLiveView, context: Context) {}
}

// MARK: Meters

/// A segmented LED meter. Reads its levels from a closure each frame, so meters never touch SwiftUI.
final class MeterLiveView: LiveView {
    private let read: @MainActor () -> [Float]
    private var uniforms = MeterUniforms()
    private var lastDrawn = MeterUniforms()
    private var needsDraw = true
    private var eased: [Float]
    private var peaks: [Float]
    private var holds: [Double]
    private var last: CFTimeInterval = 0
    /// How long the meters run up and back when the app starts, like hardware powering on.
    static let sweepSeconds: CFTimeInterval = 1.1

    init(bars: Int, vertical: Bool = true, read: @escaping @MainActor () -> [Float]) {
        self.read = read
        eased = Array(repeating: 0, count: bars)
        peaks = Array(repeating: 0, count: bars)
        holds = Array(repeating: 0, count: bars)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        uniforms.bars = Int32(bars)
        uniforms.vertical = vertical ? 1 : 0
    }

    override func forceRedraw() { needsDraw = true }

    /// What the meter's showing, 0...1 per bar.
    var shownLevels: [Float] { eased }

    /// dB scale: -42 dB at the bottom, +3 dB at the top. 0 dBFS sits where the red begins.
    private func position(_ level: Float) -> Float {
        guard level > 0.0001 else { return 0 }
        return max(0, min(1, (20 * log10(level) + 42) / 45))
    }

    override func update(hostTime: UInt64) -> Bool {
        let now = CACurrentMediaTime()
        let dt = last == 0 ? 1.0 / 60 : min(0.1, now - last)
        last = now
        var u = uniforms
        u.size = drawablePixels
        u.scale = Float(metalLayer.contentsScale)
        let levels = read()
        withUnsafeMutablePointer(to: &u.levels) { lp in
            lp.withMemoryRebound(to: Float.self, capacity: 4) { l in
                withUnsafeMutablePointer(to: &u.peaks) { pp in
                    pp.withMemoryRebound(to: Float.self, capacity: 4) { p in
                        for i in 0..<min(levels.count, 4) {
                            var target = position(levels[i])
                            // Timed from launch, not from this view being built, because the mixer can
                            // be rebuilt at any time and a meter moving with no audio is a lie.
                            let age = now - LiveRenderer.shared.launchTime
                            if age < Self.sweepSeconds && !UIAccessibility.isReduceMotionEnabled && !LiveRenderer.shared.captureMode {
                                target = max(target, Float(sin(.pi * age / Self.sweepSeconds)))
                            }
                            // Fast attack, slow release, like real meter ballistics.
                            let rate: Float = target > eased[i] ? 1 : Float(min(1, dt * 7))
                            eased[i] += (target - eased[i]) * rate
                            if eased[i] < 0.004 { eased[i] = 0 }
                            if eased[i] >= peaks[i] {
                                peaks[i] = eased[i]
                                holds[i] = now
                            } else if now - holds[i] > 1.1 {
                                peaks[i] = max(eased[i], peaks[i] - Float(dt) * 0.5)
                            }
                            l[i] = (eased[i] * 90).rounded() / 90
                            p[i] = (peaks[i] * 90).rounded() / 90
                        }
                    }
                }
            }
        }
        uniforms = u
        if !needsDraw && bytesEqual(u, lastDrawn) { return false }
        lastDrawn = u
        needsDraw = false
        return true
    }

    override func encode(_ encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(LiveRenderer.shared.pipeline(fragment: "meter_fragment"))
        withUnsafeBytes(of: &uniforms) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

struct LEDMeter: UIViewRepresentable {
    var bars = 1
    var vertical = true
    let read: @MainActor () -> [Float]
    func makeUIView(context: Context) -> MeterLiveView { MeterLiveView(bars: bars, vertical: vertical, read: read) }
    func updateUIView(_ view: MeterLiveView, context: Context) {}
}
