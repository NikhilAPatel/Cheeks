import Metal
import SwiftUI
import UIKit

/// The jog wheel: a real platter under your finger.
///
/// Touches go straight to the audio core from UIKit, with every coalesced sample the screen
/// reports, so the record follows your hand as closely as the hardware allows. The platter
/// scratches (or scrubs when paused), the outer ring bends pitch, and you can feel the beat grid
/// go past under your finger.
final class JogLiveView: LiveView {
    private let deck: Deck
    private var uniforms = JogUniforms()
    private var lastDrawn = JogUniforms()
    private var needsDraw = true
    private var base: MTLTexture?
    private var artTexture: MTLTexture?
    private var artOwner: CGImage?
    private var wakeStart: CFTimeInterval = 0
    private var trackOwner: UUID?

    // Touch
    private enum Mode { case scratch, bend }
    private var mode: Mode?
    private var activeTouch: UITouch?
    private var lastAngle: Double = 0
    private var touchPlatter: Float = 0
    private var touchRing: Float = 0
    private var hapticAngle: Double = 0
    private var lastBeatIndex: Int?

    /// One platter revolution = 1.8 s of audio (33⅓ rpm).
    static let secondsPerTurn = 1.8

    init(deck: Deck) {
        self.deck = deck
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        // Only the first time: closing the browser builds a new jog, and that isn't the deck waking up.
        wakeStart = LiveRenderer.shared.launchTime
        uniforms.ledColor = Theme.accent.simd
    }

    override func forceRedraw() { needsDraw = true }

    override func drawableSizeChanged() { base = nil }

    /// Everything that never moves is rendered once, at this size, so each frame only has to
    /// composite it with the parts that turn.
    private func bakeBase() {
        let renderer = LiveRenderer.shared
        let width = Int(metalLayer.drawableSize.width), height = Int(metalLayer.drawableSize.height)
        guard width > 1, height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = renderer.device.makeTexture(descriptor: descriptor),
              let buffer = renderer.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = uniforms
        u.size = drawablePixels
        encoder.setRenderPipelineState(renderer.pipeline(fragment: "jog_bake_fragment"))
        withUnsafeBytes(of: &u) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        base = texture
    }

    override func update(hostTime: UInt64) -> Bool {
        let renderer = LiveRenderer.shared
        if base == nil { bakeBase() }
        let now = CACurrentMediaTime()
        var u = uniforms
        u.size = drawablePixels
        u.scale = Float(metalLayer.contentsScale)

        if trackOwner != deck.track?.id {
            trackOwner = deck.track?.id
            if trackOwner != nil { wakeStart = now }
            u.labelColor = Theme.label(for: deck.track?.title ?? "").simd
        }
        if artOwner !== deck.artwork {
            artOwner = deck.artwork
            artTexture = deck.artwork.flatMap(renderer.texture(from:))
            u.vinylTint = deck.artwork.map(Theme.dominantColor(of:)) ?? .zero
        }

        let loaded = deck.isLoaded
        u.loaded = loaded ? 1 : 0
        u.hasArt = artTexture != nil ? 1 : 0
        u.artDim = artTexture != nil ? 0.62 : 0.8
        let frame = deck.heardFrame(hostTime: hostTime, secondsPerTick: renderer.secondsPerTick, outputLatency: deck.outputLatency)
        let position = frame / deck.sampleRate
        let turns = position / Self.secondsPerTurn
        u.rotation = Float((turns - floor(turns)) * 2 * .pi)
        let duration = deck.duration
        u.progress = loaded && duration > 0 ? Float(min(1, position / duration)) : 0

        let remaining = duration - position
        if loaded && deck.isPlaying && remaining < 30 && duration > 30 {
            u.warn = Float(0.5 + 0.5 * sin(now * 6))
        } else {
            u.warn = 0
        }
        // Eased, so the lighting responds to a touch the way a real backlight does.
        let easing: Float = 0.3
        touchPlatter += ((mode == .scratch ? 1 : 0) - touchPlatter) * easing
        touchRing += ((mode == .bend ? 1 : 0) - touchRing) * easing
        if touchPlatter < 0.004 { touchPlatter = 0 }
        if touchRing < 0.004 { touchRing = 0 }
        u.touchPlatter = touchPlatter
        u.touchRing = touchRing

        let cueOffset = deck.cuePoint - position
        u.cueAngle = loaded && abs(cueOffset) < Self.secondsPerTurn ? Float(cueOffset / Self.secondsPerTurn * 2 * .pi) : 99
        let r = deck.renderer
        if r.loopActive, r.loopEnd > r.loopStart, (r.loopEnd - r.loopStart) / deck.sampleRate < Self.secondsPerTurn {
            u.loopFrom = Float((r.loopStart / deck.sampleRate - position) / Self.secondsPerTurn * 2 * .pi)
            u.loopTo = Float((r.loopEnd / deck.sampleRate - position) / Self.secondsPerTurn * 2 * .pi)
        } else {
            u.loopFrom = 99
            u.loopTo = 99
        }
        if deck.isPlaying, deck.bpm > 0 {
            let beats = deck.beatPosition(position * deck.sampleRate)
            u.beatPulse = Float(exp(-(beats - floor(beats)) * 4))
        } else {
            u.beatPulse = 0
        }
        u.wake = UIAccessibility.isReduceMotionEnabled || renderer.captureMode ? 1 : Float(min(1, (now - wakeStart) / 0.9))

        uniforms = u
        if !needsDraw && bytesEqual(u, lastDrawn) { return false }
        lastDrawn = u
        needsDraw = false
        return true
    }

    override func encode(_ encoder: MTLRenderCommandEncoder) {
        let renderer = LiveRenderer.shared
        encoder.setRenderPipelineState(renderer.pipeline(fragment: "jog_fragment"))
        withUnsafeBytes(of: &uniforms) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.setFragmentTexture(base ?? renderer.blackTexture, index: 0)
        encoder.setFragmentTexture(artTexture ?? renderer.blackTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: Touch

    private func angle(of point: CGPoint) -> Double {
        atan2(Double(point.y - bounds.midY), Double(point.x - bounds.midX))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Only the circle is live, so the keys in the corners stay easy to hit.
        hypot(point.x - bounds.midX, point.y - bounds.midY) <= bounds.width / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        let point = touch.location(in: self)
        let distance = hypot(point.x - bounds.midX, point.y - bounds.midY) / (bounds.width / 2)
        // The metal ring bends a playing deck; everywhere else (and always when paused) is the record.
        mode = distance > 0.81 && deck.isPlaying ? .bend : .scratch
        lastAngle = angle(of: point)
        hapticAngle = 0
        lastBeatIndex = nil
        if mode == .scratch { deck.scratchBegin() }
        Haptics.shared.grab()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        // Every sample the screen captured since the last frame, so fast scratches stay accurate.
        for sample in event?.coalescedTouches(for: activeTouch) ?? [activeTouch] {
            let current = angle(of: sample.location(in: self))
            var delta = current - lastAngle
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            lastAngle = current
            let seconds = delta / (2 * .pi) * Self.secondsPerTurn
            if mode == .scratch {
                deck.scratchMove(seconds: seconds)
            } else {
                deck.bend(seconds: seconds * 0.6)
            }
            hapticAngle += delta
        }
        feelMovement()
    }

    /// Fine ticks as the platter turns, with stronger ones as you cross each beat and bar.
    private func feelMovement() {
        if mode == .scratch, deck.bpm > 0 {
            let beats = deck.beatPosition(deck.renderer.scratchTarget)
            let index = Int(floor(beats))
            if let last = lastBeatIndex, last != index {
                Haptics.shared.beat(isBar: (index % 4 + 4) % 4 == 0)
                hapticAngle = 0
            }
            lastBeatIndex = index
        }
        let step = 2 * Double.pi / 48
        if abs(hapticAngle) >= step {
            hapticAngle = 0
            Haptics.shared.platterTick()
        }
    }

    private func finish() {
        if mode == .scratch { deck.scratchEnd() }
        if mode != nil { Haptics.shared.release() }
        mode = nil
        activeTouch = nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeTouch, touches.contains(activeTouch) { finish() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeTouch, touches.contains(activeTouch) { finish() }
    }
}

struct JogPlatter: UIViewRepresentable {
    let deck: Deck
    func makeUIView(context: Context) -> JogLiveView { JogLiveView(deck: deck) }
    func updateUIView(_ view: JogLiveView, context: Context) {}
}
