import CoreHaptics
import UIKit

/// Everything you feel. Each kind of control has its own short, tuned tap, so the screen starts to
/// feel like hardware: keys click, knobs have a centre detent, and when you move a track by hand
/// you can feel each beat and bar go past under your finger.
///
/// Tuned on paper, since the Mac simulator has no Taptic Engine; see docs/COMPUTER_USE_TEST.md.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private enum Kind: CaseIterable {
        case key, keyUp, pad, toggleOn, toggleOff, grab, release, beat, bar, platter, detent, tick, stop, load, confirm, deny
    }

    /// The feel of each one: strength and sharpness. Longer gestures use the softer ones.
    private func parameters(_ kind: Kind) -> [(time: TimeInterval, intensity: Float, sharpness: Float)] {
        switch kind {
        case .key: [(0, 0.55, 0.85)]
        case .keyUp: [(0, 0.22, 0.6)]
        case .pad: [(0, 0.8, 0.55)]
        case .toggleOn: [(0, 0.6, 0.9)]
        case .toggleOff: [(0, 0.38, 0.6)]
        case .grab: [(0, 0.5, 0.3)]
        case .release: [(0, 0.25, 0.2)]
        case .beat: [(0, 0.55, 0.65)]
        case .bar: [(0, 0.95, 0.75)]
        case .platter: [(0, 0.16, 0.5)]
        case .detent: [(0, 0.7, 0.8)]
        case .tick: [(0, 0.2, 0.75)]
        case .stop: [(0, 0.5, 0.4)]
        case .load: [(0, 0.5, 0.3), (0.09, 0.8, 0.6)]
        case .confirm: [(0, 0.5, 0.7), (0.08, 0.75, 0.9)]
        case .deny: [(0, 0.7, 0.6), (0.07, 0.7, 0.6), (0.14, 0.7, 0.6)]
        }
    }

    private var engine: CHHapticEngine?
    private var players: [Kind: CHHapticPatternPlayer] = [:]
    private var lastFired: [Kind: TimeInterval] = [:]
    private var lastAnyContinuous: TimeInterval = 0
    private var running = false

    var isEnabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "hapticsEnabled") }
    }

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                DispatchQueue.main.async { self?.restart() }
            }
            engine.stoppedHandler = { [weak self] _ in
                DispatchQueue.main.async { self?.running = false }
            }
            self.engine = engine
            makePlayers()
            start()
        } catch {
            engine = nil
        }
    }

    private func makePlayers() {
        guard let engine else { return }
        players.removeAll()
        for kind in Kind.allCases {
            let events = parameters(kind).map { hit in
                CHHapticEvent(eventType: .hapticTransient,
                              parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: hit.intensity),
                                           CHHapticEventParameter(parameterID: .hapticSharpness, value: hit.sharpness)],
                              relativeTime: hit.time)
            }
            if let pattern = try? CHHapticPattern(events: events, parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                players[kind] = player
            }
        }
    }

    private func restart() {
        makePlayers()
        start()
    }

    /// Called when the app comes forward; the system stops the engine in the background.
    func start() {
        guard let engine, !running else { return }
        engine.start { [weak self] error in
            if error == nil { DispatchQueue.main.async { self?.running = true } }
        }
    }

    func stop() {
        engine?.stop()
        running = false
    }

    private func fire(_ kind: Kind, minimumInterval: TimeInterval = 0) {
        guard isEnabled, let player = players[kind] else { return }
        let now = CACurrentMediaTime()
        // The Taptic Engine blurs taps that are too close together, so fast gestures are thinned out.
        if minimumInterval > 0, let last = lastFired[kind], now - last < minimumInterval { return }
        lastFired[kind] = now
        if !running { start() }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    // MARK: Vocabulary

    /// A key going down.
    func key() { fire(.key) }
    /// A key coming back up, which is lighter, like the end of a real click.
    func keyUp() { fire(.keyUp, minimumInterval: 0.02) }
    /// A performance pad: a firmer, duller thump than a key.
    func pad() { fire(.pad) }
    func toggle(_ on: Bool) { fire(on ? .toggleOn : .toggleOff) }
    /// A finger landing on the platter or a waveform.
    func grab() { fire(.grab, minimumInterval: 0.03) }
    func release() { fire(.release, minimumInterval: 0.03) }
    /// A beat or bar going past while moving a track by hand. Bars are stronger, so you can count them.
    func beat(isBar: Bool) { isBar ? fire(.bar, minimumInterval: 0.03) : fire(.beat, minimumInterval: 0.045) }
    /// The fine ridges of the platter.
    func platterTick() { fire(.platter, minimumInterval: 0.022) }
    /// A knob or fader settling into its centre position.
    func detent() { fire(.detent, minimumInterval: 0.05) }
    /// Fine steps on a knob or fader.
    func tick() { fire(.tick, minimumInterval: 0.03) }
    /// Reaching the end of a fader's or knob's travel.
    func endStop() { fire(.stop, minimumInterval: 0.08) }
    /// A track landing on a deck.
    func load() { fire(.load) }
    /// Something worked: sync locked, a cue saved, a recording started.
    func confirm() { fire(.confirm) }
    /// Not allowed, such as loading onto a playing deck.
    func deny() { fire(.deny) }
}
