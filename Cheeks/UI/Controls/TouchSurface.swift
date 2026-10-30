import SwiftUI
import UIKit

/// Direct multitouch for performance controls. Each control is its own UIView, so any number of
/// them can be held at once (CUE with a pad, two faders and a jog), and a press registers on the
/// finger's first contact with none of the delay a gesture recognizer adds to tell taps from drags.
struct TouchSurface: UIViewRepresentable {
    var onDown: (@MainActor (CGPoint) -> Void)?
    /// Location, and translation from where the touch began.
    var onMove: (@MainActor (CGPoint, CGSize) -> Void)?
    var onUp: (@MainActor () -> Void)?
    var onDoubleTap: (@MainActor () -> Void)?
    /// Called instead of `onDown` for the second touch of a double tap, when one is set.
    var circular = false

    func makeUIView(context: Context) -> TouchSurfaceView { TouchSurfaceView() }

    func updateUIView(_ view: TouchSurfaceView, context: Context) {
        view.onDown = onDown
        view.onMove = onMove
        view.onUp = onUp
        view.onDoubleTap = onDoubleTap
        view.circular = circular
    }
}

final class TouchSurfaceView: UIView {
    var onDown: (@MainActor (CGPoint) -> Void)?
    var onMove: (@MainActor (CGPoint, CGSize) -> Void)?
    var onUp: (@MainActor () -> Void)?
    var onDoubleTap: (@MainActor () -> Void)?
    var circular = false

    private var active: UITouch?
    private var start: CGPoint = .zero
    private var lastTapTime: TimeInterval = 0
    private var lastTapPoint: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard circular else { return super.point(inside: point, with: event) }
        return hypot(point.x - bounds.midX, point.y - bounds.midY) <= max(bounds.width, bounds.height) / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard active == nil, let touch = touches.first else { return }
        active = touch
        let point = touch.location(in: self)
        start = point
        let isDouble = touch.timestamp - lastTapTime < 0.3 && hypot(point.x - lastTapPoint.x, point.y - lastTapPoint.y) < 30
        lastTapTime = touch.timestamp
        lastTapPoint = point
        if isDouble, let onDoubleTap {
            lastTapTime = 0
            onDoubleTap()
        }
        onDown?(point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active, touches.contains(active) else { return }
        let point = active.location(in: self)
        onMove?(point, CGSize(width: point.x - start.x, height: point.y - start.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        guard let active, touches.contains(active) else { return }
        self.active = nil
        onUp?()
    }
}
