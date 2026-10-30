import MetalKit
import QuartzCore
import SwiftUI
import UIKit

/// Draws everything that moves on screen. One display link, one command buffer per frame; each
/// view skips its draw when nothing it shows has changed, so an idle screen uses almost no power.
///
/// SwiftUI never redraws for any of this: the playhead isn't observed, so the rest of the
/// interface only updates when a control really changes.
@MainActor
final class LiveRenderer {
    static let shared = LiveRenderer()

    let device: MTLDevice
    let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private let views = NSHashTable<LiveView>.weakObjects()
    private var link: CADisplayLink?

    /// Seconds per host-clock tick, for placing the playhead between audio callbacks.
    let secondsPerTick: Double
    /// True while something's moving, which unlocks the display's highest refresh rate.
    var isBusy: () -> Bool = { false }
    /// Set by the snapshot test: views render into images rather than to the screen.
    var captureMode = false

    lazy var blackTexture: MTLTexture = solidTexture(red: 0, green: 0, blue: 0, alpha: 0)
    /// A row of the hot cue letters A–H, for the flags on the waveforms.
    lazy var cueLetters: MTLTexture = makeCueLetters()

    private init() {
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        secondsPerTick = Double(base.numer) / Double(base.denom) * 1e-9
    }

    func pipeline(fragment: String) -> MTLRenderPipelineState {
        if let existing = pipelines[fragment] { return existing }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let state = try! device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[fragment] = state
        return state
    }

    func register(_ view: LiveView) {
        views.add(view)
        if link == nil {
            let newLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
    }

    func unregister(_ view: LiveView) {
        views.remove(view)
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard !captureMode else { return }
        updateFrameRate(link)
        guard let buffer = queue.makeCommandBuffer() else { return }
        let now = mach_absolute_time()
        var drew = false
        for view in views.allObjects where view.window != nil && !view.isHidden {
            guard view.update(hostTime: now),
                  let drawable = view.metalLayer.nextDrawable() else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { continue }
            view.encode(encoder)
            encoder.endEncoding()
            buffer.present(drawable)
            drew = true
        }
        if drew { buffer.commit() }
    }

    private func updateFrameRate(_ link: CADisplayLink) {
        // Hot or in Low Power Mode, drop to 60 and stay cool; a set can run for hours.
        let constrained = ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        let preferred: Float = isBusy() ? (constrained ? 60 : 120) : 30
        if link.preferredFrameRateRange.preferred != preferred {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(preferred, 60), maximum: max(preferred, 60), preferred: preferred)
        }
    }

    // MARK: Snapshot capture

    /// Metal layers don't appear in `drawHierarchy`, so for snapshots each view is drawn into an
    /// image, which is laid over it.
    func captureForSnapshot() {
        let now = mach_absolute_time()
        for view in views.allObjects where view.window != nil {
            view.forceRedraw()
            _ = view.update(hostTime: now)
            view.captureOverlay()
        }
    }

    // MARK: Textures

    func solidTexture(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let texture = device.makeTexture(descriptor: descriptor)!
        let bytes = [red, green, blue, alpha]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 4)
        return texture
    }

    func texture(from image: CGImage) -> MTLTexture? {
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(cgImage: image, options: [.SRGB: false, .generateMipmaps: false, .textureStorageMode: MTLStorageMode.shared.rawValue])
    }

    private func makeCueLetters() -> MTLTexture {
        let cell = CGSize(width: 36, height: 33)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cell.width * 8, height: cell.height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return format
        }())
        let image = renderer.image { _ in
            let font = UIFont.systemFont(ofSize: 25, weight: .heavy)
            for (i, letter) in Theme.hotCueLetters.enumerated() {
                let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: UIColor.white])
                let size = text.size()
                text.draw(at: CGPoint(x: cell.width * CGFloat(i) + (cell.width - size.width) / 2, y: (cell.height - size.height) / 2))
            }
        }
        return texture(from: image.cgImage!) ?? blackTexture
    }
}

/// A view whose contents are drawn by `LiveRenderer`. Subclasses fill in `update` and `encode`.
class LiveView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var overlay: CALayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        metalLayer.device = LiveRenderer.shared.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.maximumDrawableCount = 3
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            metalLayer.contentsScale = window?.screen.scale ?? 3
            updateDrawableSize()
            LiveRenderer.shared.register(self)
        } else {
            LiveRenderer.shared.unregister(self)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = metalLayer.contentsScale
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            forceRedraw()
            drawableSizeChanged()
        }
    }

    var drawablePixels: SIMD2<Float> {
        SIMD2(Float(metalLayer.drawableSize.width), Float(metalLayer.drawableSize.height))
    }

    func drawableSizeChanged() {}

    /// Refreshes uniforms. Returns true when the view needs drawing this frame.
    func update(hostTime: UInt64) -> Bool { false }

    /// Encodes the draw, after `update` said it needs one.
    func encode(_ encoder: MTLRenderCommandEncoder) {}

    /// Makes the next `update` return true.
    func forceRedraw() {}

    // MARK: Snapshot capture

    func captureOverlay() {
        let renderer = LiveRenderer.shared
        let width = Int(metalLayer.drawableSize.width), height = Int(metalLayer.drawableSize.height)
        guard width > 1, height > 1 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = renderer.device.makeTexture(descriptor: descriptor),
              let buffer = renderer.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(encoder)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
              let image = context.makeImage() else { return }
        let target = overlay ?? CALayer()
        target.contents = image
        target.frame = bounds
        target.contentsScale = metalLayer.contentsScale
        if overlay == nil {
            layer.addSublayer(target)
            overlay = target
        }
    }
}

/// Compares two values byte for byte, for skipping frames where a view's uniforms didn't change.
func bytesEqual<T>(_ a: T, _ b: T) -> Bool {
    withUnsafeBytes(of: a) { x in withUnsafeBytes(of: b) { y in memcmp(x.baseAddress, y.baseAddress, x.count) == 0 } }
}

extension Color {
    /// The colour's sRGB components, for handing to a shader.
    var simd: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
