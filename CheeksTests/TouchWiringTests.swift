import SwiftUI
import XCTest
@testable import Cheeks

/// Proves the controls work without needing fingers. The real screen is hosted at the Duo's size,
/// and hit-tested across a grid the way UIKit does for a touch. So anything found here is really
/// reachable, not covered by something else. Each control it finds is pressed and dragged through
/// the same callbacks a touch would call, and the test records what changed in the app.
@MainActor
final class TouchWiringTests: XCTestCase {
    private static let size = CGSize(width: 951, height: 669)
    private var window: UIWindow?

    /// Everything a control could change, by name, for comparing before and after a press.
    private func state(_ dj: DJEngine) -> [String: String] {
        var out: [String: String] = [
            "crossfader": "\(dj.crossfader)", "masterVolume": "\(dj.masterVolume)", "headphoneMix": "\(dj.headphoneMix)",
            "headphoneVolume": "\(dj.headphoneVolume)", "splitCue": "\(dj.splitCue)", "masterIndex": "\(dj.masterIndex)",
            "colorFX": dj.colorFX.rawValue,
        ]
        for deck in dj.decks {
            let d = "deck\(deck.index)."
            out[d + "isPlaying"] = "\(deck.isPlaying)"
            out[d + "quantize"] = "\(deck.quantize)"
            out[d + "slipMode"] = "\(deck.slipMode)"
            out[d + "keyLock"] = "\(deck.keyLock)"
            out[d + "reverse"] = "\(deck.reverse)"
            out[d + "syncOn"] = "\(deck.syncOn)"
            out[d + "headphoneCue"] = "\(deck.headphoneCue)"
            out[d + "trim"] = "\(deck.trim)"
            out[d + "eqHigh"] = "\(deck.eqHigh)"
            out[d + "eqMid"] = "\(deck.eqMid)"
            out[d + "eqLow"] = "\(deck.eqLow)"
            out[d + "filter"] = "\(deck.filter)"
            out[d + "fader"] = "\(deck.fader)"
            out[d + "tempo"] = "\(deck.tempoRatioPercent)"
            out[d + "tempoRange"] = "\(deck.tempoRange)"
            out[d + "padMode"] = deck.padMode.rawValue
            out[d + "shift"] = "\(deck.shift)"
            out[d + "loopActive"] = "\(deck.renderer.loopActive)"
            out[d + "loopBeats"] = "\(deck.loopBeats)"
            out[d + "jumpBeats"] = "\(deck.jumpBeats)"
            out[d + "keyShift"] = "\(deck.keyShift)"
            out[d + "hotCues"] = "\(deck.track?.hotCues.count ?? 0)"
            out[d + "memory"] = "\(deck.memoryItems.count)"
            out[d + "fxOn"] = "\(deck.fxOn)"
            out[d + "fxDepth"] = "\(deck.fxDepth)"
            out[d + "stems"] = "\(deck.stemsOn)"
            out[d + "stemLevels"] = "\(deck.stemLevels)"
            out[d + "position"] = "\(Int(deck.renderer.playhead / 44_100))"
        }
        return out
    }

    private func makeScreen() async throws -> (DJEngine, Library) {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        for deck in dj.decks {
            deck.renderer.setSources([PCM16Stereo(frames: 44_100 * 60)])
            deck.track = Track(id: UUID(), title: "T\(deck.index)", artist: "A", fileName: "none", duration: 60, bpm: 120 + Double(deck.index) * 4, firstBeat: 0.1, key: "8A")
            deck.seek(to: 20)
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: ContentView(opensBrowserWhenEmpty: false).environment(library).environment(dj))
        window.rootViewController = host
        window.frame = CGRect(origin: .zero, size: Self.size)
        window.isHidden = false
        window.frame = CGRect(origin: .zero, size: Self.size)
        host.view.frame = window.bounds
        self.window = window
        try await settle()
        return (dj, library)
    }

    private func settle(_ ms: Int = 120) async throws {
        window?.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(ms))
        window?.layoutIfNeeded()
    }

    /// Every touchable view on screen, found the way a real touch finds one, with a point inside it.
    private func controls(in rect: CGRect) -> [(view: TouchSurfaceView, point: CGPoint)] {
        guard let window else { return [] }
        var found: [ObjectIdentifier: (view: TouchSurfaceView, point: CGPoint)] = [:]
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let point = CGPoint(x: x, y: y)
                if let view = window.hitTest(point, with: nil) as? TouchSurfaceView, found[ObjectIdentifier(view)] == nil {
                    // Aim for its centre, which is what a finger would do.
                    let centre = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
                    found[ObjectIdentifier(view)] = (view, centre)
                }
                x += 6
            }
            y += 6
        }
        return Array(found.values)
    }

    /// Presses and drags a control through its touch callbacks. Returns the names of what changed.
    private func exercise(_ control: (view: TouchSurfaceView, point: CGPoint), dj: DJEngine) async throws -> Set<String> {
        let before = state(dj)
        let local = control.view.convert(control.point, from: window)
        control.view.onDown?(local)
        _ = dj.renderOffline(frames: 256)
        for step in 1...4 {
            // Diagonal, so horizontal controls like the crossfader move as well as vertical ones.
            let translation = CGSize(width: CGFloat(step) * 9, height: CGFloat(-step) * 9)
            control.view.onMove?(CGPoint(x: local.x + translation.width, y: local.y + translation.height), translation)
        }
        _ = dj.renderOffline(frames: 256)
        control.view.onUp?()
        _ = dj.renderOffline(frames: 256)
        let after = state(dj)
        return Set(after.keys.filter { after[$0] != before[$0] })
    }

    func testEveryControlOnTheDecksAndMixerIsReachableAndWorks() async throws {
        let (dj, _) = try await makeScreen()
        let found = controls(in: CGRect(x: 0, y: 200, width: Self.size.width, height: Self.size.height - 200))
        XCTAssertGreaterThan(found.count, 60, "Should find keys, knobs, faders and pads on both decks")

        var changed: Set<String> = []
        for control in found {
            changed.formUnion(try await exercise(control, dj: dj))
        }
        for name in ["isPlaying", "quantize", "slipMode", "keyLock", "reverse", "syncOn", "headphoneCue",
                     "trim", "eqHigh", "eqMid", "eqLow", "filter", "fader", "tempo", "tempoRange",
                     "padMode", "loopActive", "jumpBeats", "keyShift", "hotCues"] {
            XCTAssertTrue(changed.contains("deck0." + name), "No control on deck 1 changed \(name)")
            XCTAssertTrue(changed.contains("deck1." + name), "No control on deck 2 changed \(name)")
        }
        for name in ["crossfader", "masterVolume", "headphoneMix", "headphoneVolume", "splitCue", "colorFX"] {
            XCTAssertTrue(changed.contains(name), "No control changed \(name)")
        }
        window?.isHidden = true
    }

    func testEveryPadModeCanBePlayedWithoutCrashing() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.play()
        for mode in PadMode.allCases {
            deck.padMode = mode
            try await settle(60)
            // The lower-left part of the screen: this deck's control row, tabs and pads.
            let area = CGRect(x: 64, y: Self.size.height - 150, width: 320, height: 150)
            // Keep to pads and the control row: pressing a tab would leave this mode.
            let pads = controls(in: area).filter { $0.point.y > Self.size.height - 100 || $0.point.y < Self.size.height - 124 }
            XCTAssertGreaterThanOrEqual(pads.count, 8, "\(mode.rawValue) should show its pads")
            var changed: Set<String> = []
            for control in pads {
                deck.padMode = mode
                changed.formUnion(try await exercise(control, dj: dj))
            }
            // Effects that latch or stop the deck are put back so the next pad gets a fair run.
            deck.fxRelease()
            if !deck.isPlaying { deck.play() }
            switch mode {
            case .hotCue: XCTAssertTrue(changed.contains("deck0.hotCues"), "Hot cue pads set no cues")
            case .memory: XCTAssertTrue(changed.contains("deck0.memory"), "Save keys saved nothing")
            case .beatLoop: XCTAssertTrue(changed.contains("deck0.loopActive"), "Loop pads set no loop")
            case .beatJump: XCTAssertTrue(changed.contains("deck0.position"), "Jump pads didn't move the deck")
            case .stems: XCTAssertTrue(changed.contains("deck0.stems") || changed.contains("deck0.stemLevels"), "Stem pads did nothing")
            case .fx: XCTAssertTrue(changed.contains("deck0.fxDepth") || changed.contains("deck0.fxOn"), "FX pads did nothing")
            default: break
            }
        }
        window?.isHidden = true
    }

    func testTheJogAndWaveformsAreReachable() async throws {
        let (_, _) = try await makeScreen()
        let window = try XCTUnwrap(window)
        var jogs = 0, waves = 0, overviews = 0
        var seen: Set<ObjectIdentifier> = []
        var y: CGFloat = 0
        while y < Self.size.height {
            var x: CGFloat = 0
            while x < Self.size.width {
                if let view = window.hitTest(CGPoint(x: x, y: y), with: nil), seen.insert(ObjectIdentifier(view)).inserted {
                    if view is JogLiveView { jogs += 1 }
                    if view is WaveformLiveView { waves += 1 }
                    if view is OverviewLiveView { overviews += 1 }
                }
                x += 6
            }
            y += 6
        }
        XCTAssertEqual(jogs, 2)
        XCTAssertEqual(waves, 2)
        XCTAssertEqual(overviews, 2)
        window.isHidden = true
    }
}
