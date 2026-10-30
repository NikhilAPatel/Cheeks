import SwiftUI

/// A DJM-style rotary knob: a knurled rubber skirt and a satin cap with a white pointer, turning
/// over a printed scale. Only the skirt and pointer rotate; the light on the cap stays put, as it
/// would on real hardware.
///
/// Drag up or down to turn; move your finger sideways away from the knob for finer control, like
/// scrubbing in Music. It has a magnetic centre detent you can feel. Double-tap to spring home.
struct Knob: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -1...1
    var defaultValue: Float = 0
    var label: String
    var color: Color = Theme.accent
    var size: CGFloat = 38
    var scale: KnobScale = .bipolar
    /// Announced by VoiceOver in place of the raw number.
    var accessibilityUnit: String = ""

    @State private var dragStart: Float?
    @State private var engaged = false
    @State private var lastTickStep: Int?
    @State private var inDetent = false

    private var span: Float { range.upperBound - range.lowerBound }
    private func fraction(_ v: Float) -> CGFloat { CGFloat((v - range.lowerBound) / span) }
    private var angle: Double { -135 + Double(fraction(value)) * 270 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(uiImage: KnobArt.base(size: size, scale: scale))
                    .resizable()
                    .frame(width: size, height: size)
                valueArc
                Image(uiImage: KnobArt.rotor(size: size))
                    .resizable()
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(angle))
                Image(uiImage: KnobArt.cap(size: size))
                    .resizable()
                    .frame(width: size, height: size)
                    .allowsHitTesting(false)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .overlay {
                TouchSurface(onDown: { _ in
                    dragStart = value
                    engaged = true
                    lastTickStep = nil
                    Haptics.shared.grab()
                }, onMove: { _, translation in
                    turn(translation)
                }, onUp: {
                    dragStart = nil
                    engaged = false
                }, onDoubleTap: {
                    Haptics.shared.detent()
                    withAnimation(Theme.home) { value = defaultValue }
                }, circular: true)
                .padding(-3)
            }
            if !label.isEmpty {
                Text(label)
                    .silk(max(7.5, min(8.5, size * 0.21)))
                    .padding(.top, 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Level" : label.capitalized)
        .accessibilityValue(accessibilityDescription)
        .accessibilityAdjustableAction { direction in
            let step = span / 20
            let moved = direction == .increment ? value + step : value - step
            value = min(range.upperBound, max(range.lowerBound, moved))
        }
    }

    private var accessibilityDescription: String {
        let percent = Int((fraction(value) * 100).rounded())
        return accessibilityUnit.isEmpty ? "\(percent) percent" : "\(percent) \(accessibilityUnit)"
    }

    /// A thin lit arc from the detent to the pointer, so the setting reads from across the screen.
    private var valueArc: some View {
        let from = min(fraction(value), fraction(defaultValue)), to = max(fraction(value), fraction(defaultValue))
        return Circle()
            .trim(from: from * 0.75, to: to * 0.75)
            .stroke(color.opacity(engaged ? 1 : 0.92), style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
            .rotationEffect(.degrees(135))
            .padding(size * 0.045)
            .allowsHitTesting(false)
    }

    private func turn(_ translation: CGSize) {
        guard let dragStart else { return }
        // Sideways distance is a fine-control gear: the further away, the slower it turns.
        let fine = max(0.2, 1 - abs(translation.width) / 140)
        let pixelsForFullTurn = 150.0
        var next = dragStart + Float(-translation.height / pixelsForFullTurn * fine) * span
        next = min(range.upperBound, max(range.lowerBound, next))

        // The centre detent: the knob holds there until you've really moved off it.
        let detentWidth = span * 0.022
        let nearDetent = abs(next - defaultValue) < detentWidth && defaultValue > range.lowerBound && defaultValue < range.upperBound
        if nearDetent {
            next = defaultValue
            if !inDetent { Haptics.shared.detent() }
            inDetent = true
        } else {
            inDetent = false
        }
        if next != value, next == range.lowerBound || next == range.upperBound { Haptics.shared.endStop() }

        let step = Int(((next - range.lowerBound) / span * 24).rounded())
        if let lastTickStep, lastTickStep != step, !nearDetent { Haptics.shared.tick() }
        lastTickStep = step

        value = next
    }
}

enum KnobScale: String {
    /// A centre detent, with the printed scale showing both directions.
    case bipolar
    /// Zero to maximum.
    case unipolar
}

@MainActor
enum KnobArt {
    /// The printed scale and the shadow the knob throws on the panel.
    static func base(size: CGFloat, scale: KnobScale) -> UIImage {
        Baked.image("knob-base-\(size)-\(scale.rawValue)") {
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = canvas.width / 2
                // Faint track for the value arc.
                var track = Path()
                track.addArc(center: c, radius: r * 0.91, startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
                context.stroke(track, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: r * 0.1, lineCap: .round))
                // Printed ticks in the track
                let count = 10
                for i in 0...count {
                    let a = Angle.degrees(135 + Double(i) / Double(count) * 270).radians
                    let isMajor = i == 0 || i == count || i == count / 2
                    let inner = r * (isMajor ? 0.87 : 0.885), outer = r * (isMajor ? 0.97 : 0.945)
                    var tick = Path()
                    tick.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                    tick.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                    context.stroke(tick, with: .color(.white.opacity(isMajor ? 0.45 : 0.2)), lineWidth: isMajor ? 0.8 : 0.5)
                }
                // Contact shadow from the top-lit knob
                var shadow = context
                shadow.addFilter(.blur(radius: r * 0.07))
                let body = r * 0.76
                shadow.fill(Path(ellipseIn: CGRect(x: c.x - body, y: c.y - body + r * 0.05, width: body * 2, height: body * 2)), with: .color(.black.opacity(0.9)))
            }
            .frame(width: size, height: size)
        }
    }

    /// What turns: the knurled skirt and the pointer.
    static func rotor(size: CGFloat) -> UIImage {
        Baked.image("knob-rotor-\(size)") {
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = canvas.width / 2
                let skirt = r * 0.75
                context.fill(Path(ellipseIn: CGRect(x: c.x - skirt, y: c.y - skirt, width: skirt * 2, height: skirt * 2)), with: .color(Color(white: 0.085)))
                // Knurling
                let ridges = 28
                for i in 0..<ridges {
                    let a = Double(i) / Double(ridges) * 2 * .pi
                    var ridge = Path()
                    ridge.move(to: CGPoint(x: c.x + cos(a) * skirt * 0.86, y: c.y + sin(a) * skirt * 0.86))
                    ridge.addLine(to: CGPoint(x: c.x + cos(a) * skirt * 0.995, y: c.y + sin(a) * skirt * 0.995))
                    context.stroke(ridge, with: .color(.white.opacity(0.16)), lineWidth: max(0.6, r * 0.028))
                }
                // Pointer: runs across the skirt onto the cap, like a DJM knob
                var pointer = Path()
                pointer.move(to: CGPoint(x: c.x, y: c.y - skirt * 0.99))
                pointer.addLine(to: CGPoint(x: c.x, y: c.y - skirt * 0.46))
                context.stroke(pointer, with: .color(Color(white: 0.96)), style: StrokeStyle(lineWidth: max(1.5, r * 0.085), lineCap: .round))
            }
            .frame(width: size, height: size)
        }
    }

    /// The light on the cap, which stays still as the knob turns. The centre is left clear so the
    /// pointer shows through at its base.
    static func cap(size: CGFloat) -> UIImage {
        Baked.image("knob-cap-\(size)") {
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = canvas.width / 2
                let capR = r * 0.46
                let rect = CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)
                let circle = Path(ellipseIn: rect)
                context.fill(circle, with: .linearGradient(Gradient(colors: [Color(white: 0.28), Color(white: 0.13)]),
                                                           startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                // Satin sheen: a soft bright wedge from the top left.
                context.fill(circle, with: .conicGradient(Gradient(colors: [.clear, .white.opacity(0.22), .clear, .clear, .white.opacity(0.08), .clear]),
                                                          center: c, angle: .degrees(-85)))
                context.stroke(circle, with: .linearGradient(Gradient(colors: [.white.opacity(0.35), .black.opacity(0.5)]),
                                                             startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)), lineWidth: 0.75)
            }
            .frame(width: size, height: size)
        }
    }
}
