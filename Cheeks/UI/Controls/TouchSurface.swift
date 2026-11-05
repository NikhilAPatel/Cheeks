import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

private struct IsInASheetKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A control in a sheet has to keep its touch from the sheet's own drag.
    var isInASheet: Bool {
        get { self[IsInASheetKey.self] }
        set { self[IsInASheetKey.self] = newValue }
    }
}

/// Direct multitouch for performance controls. Each control is its own UIView, so any number of
/// them can be held at once (CUE with a pad, two faders and a jog), and a press registers on the
/// finger's first contact with none of the delay a gesture recognizer adds to tell taps from drags.
struct TouchSurface: UIViewRepresentable {
    @Environment(\.isOffstage) private var isOffstage
    @Environment(\.isInASheet) private var isInASheet
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
        view.holdsOffTheSheet = isInASheet
        // Out of sight has been let go, the same as a view that's gone. Not during this update, for the same reason.
        if isOffstage { DispatchQueue.main.async { view.letGo() } }
    }
}

/// Never recognises anything. It only sits there until the touch is over, and every other recogniser that would have this touch
/// has to wait for that. The touches themselves still go to the view.
private final class SheetHolder: UIGestureRecognizer {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool { true }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }
}

final class TouchSurfaceView: UIView {
    var onDown: (@MainActor (CGPoint) -> Void)?
    var onMove: (@MainActor (CGPoint, CGSize) -> Void)?
    var onUp: (@MainActor () -> Void)?
    var onDoubleTap: (@MainActor () -> Void)?
    var circular = false

    /// A sheet's drag takes any touch that's moved about 10 pt, and cancels it here. Round 15: 120 pt on MASTER moved it nothing,
    /// and a phone has no other TRIM or MASTER. Anything else a sheet's dragged by still drags it.
    var holdsOffTheSheet = false {
        didSet {
            guard holdsOffTheSheet != oldValue else { return }
            if holdsOffTheSheet { addGestureRecognizer(sheetHolder) } else { removeGestureRecognizer(sheetHolder) }
        }
    }
    private lazy var sheetHolder = SheetHolder()

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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(letGo), name: UIApplication.willResignActiveNotification, object: nil)
        } else {
            // Not during the update that's removing it, which may be SwiftUI's.
            DispatchQueue.main.async { self.letGo() }
        }
    }

    /// A finger that's no longer going to be heard from: its view has gone, or a call has come in.
    @objc func letGo() {
        guard active != nil else { return }
        active = nil
        onUp?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        guard let active, touches.contains(active) else { return }
        self.active = nil
        onUp?()
    }
}
