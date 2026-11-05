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

    private func makeScreen(size: CGSize = TouchWiringTests.size, startsOnJog: Bool = false) async throws -> (DJEngine, Library) {
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
        let host = UIHostingController(rootView: ContentView(opensBrowserWhenEmpty: false).environment(library).environment(dj).environment(\.compactDeckStartsOnJog, startsOnJog))
        window.rootViewController = host
        window.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false
        window.frame = CGRect(origin: .zero, size: size)
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
            // They come in no fixed order, and SYNC refuses on the only deck playing, so each starts with nothing playing.
            dj.decks.forEach { $0.pause() }
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

    func testAPadTappedRightAfterATabBelongsToTheNewPage() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.padMode = .hotCue
        try await settle()
        let hotCuesBefore = deck.track?.hotCues.count ?? 0
        // The lower-left part of the screen, with the tabs just above the pads.
        // Only surfaces centred on the pad grid: the round CUE and PLAY reach into this area too.
        let pads = controls(in: CGRect(x: 72, y: Self.size.height - 100, width: 320, height: 100))
            .filter { $0.point.x > 72 }
            .sorted { ($0.point.x, $0.point.y) < ($1.point.x, $1.point.y) }
        let tabs = controls(in: CGRect(x: 72, y: Self.size.height - 124, width: 320, height: 4))
            .sorted { $0.point.x < $1.point.x }
        let target = try XCTUnwrap(pads.first).point
        XCTAssertEqual(hotCuesBefore, 0, "So an old page's pad would set a cue")
        XCTAssertGreaterThanOrEqual(tabs.count, 3)

        tabs[2].view.onDown?(tabs[2].point) // LOOP
        tabs[2].view.onUp?()
        XCTAssertEqual(deck.padMode, .beatLoop)
        // A quick second tap: less than a tenth of a second later.
        try await Task.sleep(for: .milliseconds(40))
        let hit = window?.hitTest(target, with: nil) as? TouchSurfaceView
        hit?.onDown?(target)
        hit?.onUp?()
        XCTAssertEqual(deck.track?.hotCues.count ?? 0, hotCuesBefore, "The old page's pad must not fire")
        XCTAssertTrue(deck.loopActive, "The new page's pad does")
        deck.exitLoop()
        window?.isHidden = true
    }

    func testFaderCapsAreCentredOnTheirValue() {
        // The space a cap takes up is its own size, not its size less its shadow margin.
        let host = UIHostingController(rootView: FaderCap(vertical: false, width: 26, length: 26))
        let size = host.sizeThatFits(in: CGSize(width: 200, height: 200))
        XCTAssertEqual(size.width, 26, accuracy: 0.5)
        XCTAssertEqual(size.height, 26, accuracy: 0.5)
    }

    func testMetersOnlySweepAtLaunch() async throws {
        let renderer = LiveRenderer.shared
        let launched = renderer.launchTime
        defer { renderer.launchTime = launched }

        // Long after launch, a meter being built with nothing playing stays at rest.
        renderer.launchTime = CACurrentMediaTime() - 60
        let late = MeterLiveView(bars: 4) { [0, 0, 0, 0] }
        _ = late.update(hostTime: mach_absolute_time())
        try await Task.sleep(for: .milliseconds(300))
        _ = late.update(hostTime: mach_absolute_time())
        XCTAssertEqual(late.shownLevels, [0, 0, 0, 0])

        // While the app's just started, it does run up. Skipped under Reduce Motion, where it doesn't.
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        renderer.launchTime = CACurrentMediaTime()
        let early = MeterLiveView(bars: 1) { [0] }
        _ = early.update(hostTime: mach_absolute_time())
        try await Task.sleep(for: .milliseconds(300))
        _ = early.update(hostTime: mach_absolute_time())
        XCTAssertGreaterThan(early.shownLevels[0], 0.1)
    }

    func testAMeterDrawsAgainWhenTheAppComesBack() async throws {
        let renderer = LiveRenderer.shared
        let launch = renderer.launchTime
        defer { renderer.launchTime = launch }
        renderer.launchTime = CACurrentMediaTime() - 60 // Past the run-up at launch.
        let meter = MeterLiveView(bars: 1) { [0] }
        renderer.register(meter)
        defer { renderer.unregister(meter) }
        _ = meter.update(hostTime: mach_absolute_time())
        XCTAssertFalse(meter.update(hostTime: mach_absolute_time()), "Nothing's changed, so there's nothing to draw")

        // Its last frames were sent as the app went away, and never got to the screen.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(meter.update(hostTime: mach_absolute_time()))
        XCTAssertFalse(meter.update(hostTime: mach_absolute_time()))
    }

    func testTheJogLetsGoAsTheAppGoesAway() throws {
        let deck = Deck(index: 0)
        deck.renderer.setSources([PCM16Stereo(frames: 44_100)])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let jog = JogLiveView(deck: deck)
        window.addSubview(jog)
        jog.holdForTesting()
        XCTAssertTrue(cheeks_deck_scratching(deck.renderer.handle))

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(cheeks_deck_scratching(deck.renderer.handle), "It shouldn't wait for the system to cancel the touch")
    }

    func testTheDeckNoticesATrackFinishingLoadingWhileItWasEmpty() {
        let deck = Deck(index: 0)
        // A view reading this while the deck's empty has to get told when loading ends.
        var told = false
        withObservationTracking { _ = deck.isLoaded } onChange: { told = true }
        deck.setLoadingForTesting(true)
        XCTAssertTrue(told)
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

    // MARK: A held pad's view going away

    /// Deck 1's first pad on this page, held down.
    private func holdFirstPad(of deck: Deck, on page: PadMode) async throws {
        deck.padMode = page
        try await settle()
        let pads = controls(in: CGRect(x: 72, y: Self.size.height - 100, width: 320, height: 100))
            .filter { $0.point.x > 72 }
            .sorted { ($0.point.x, $0.point.y) < ($1.point.x, $1.point.y) }
        let pad = try XCTUnwrap(pads.first)
        pad.view.onDown?(pad.view.convert(pad.point, from: window))
    }

    /// The track's place, and the deck's state, after a held roll or slice has gone.
    private func assertRollEnded(_ deck: Deck, dj: DJEngine, heldFrom start: Double, frames: Int, line: UInt = #line) {
        XCTAssertEqual(deck.heldMomentaryPads, 0, line: line)
        XCTAssertFalse(deck.loopActive, line: line)
        XCTAssertFalse(deck.renderer.slipEngaged, line: line)
        _ = dj.renderOffline(frames: 1024)
        XCTAssertEqual(deck.renderer.playhead, start + Double(frames) + 1024, accuracy: 4096, "It lands where the track's got to", line: line)
    }

    func testChangingTabWithARollHeldEndsTheRoll() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.play()
        let start = deck.renderer.playhead
        try await holdFirstPad(of: deck, on: .roll)
        XCTAssertEqual(deck.heldMomentaryPads, 1)
        XCTAssertTrue(deck.loopActive)
        _ = dj.renderOffline(frames: 44_100)
        deck.padMode = .hotCue
        try await settle(1500)
        assertRollEnded(deck, dj: dj, heldFrom: start, frames: 44_100)
        // And the next one isn't left stuck.
        let here = deck.renderer.playhead
        deck.rollBegin(0.25)
        _ = dj.renderOffline(frames: 4096)
        deck.rollEnd()
        assertRollEnded(deck, dj: dj, heldFrom: here, frames: 4096)
    }

    func testChangingTabWithASliceHeldEndsTheSlice() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.play()
        let start = deck.renderer.playhead
        try await holdFirstPad(of: deck, on: .slicer)
        XCTAssertEqual(deck.heldMomentaryPads, 1)
        _ = dj.renderOffline(frames: 44_100)
        deck.padMode = .memory
        try await settle(1500)
        assertRollEnded(deck, dj: dj, heldFrom: start, frames: 44_100)
    }

    /// Two hands-on rounds said the thumbs vanish with no acknowledgement. Whatever answers has to be left up to be read.
    func testAThumbLeavesItsAnswerUp() async throws {
        let (dj, _) = try await makeScreen()
        let window = try XCTUnwrap(self.window)
        let before = Set(controls(in: window.bounds).map { ObjectIdentifier($0.view) })
        dj.say("Loop build done. More like that?", .done)
        dj.rateAction = { [weak dj] _ in dj?.say("Got it. More like that.", .done) }
        try await settle(800)
        let thumbs = controls(in: window.bounds).filter { !before.contains(ObjectIdentifier($0.view)) }
        XCTAssertEqual(thumbs.count, 2, "Each has a touch of its own")
        thumbs[0].view.onDown?(.zero)
        thumbs[0].view.onUp?()
        try await settle(3000)
        XCTAssertEqual(dj.statusMessage, "Got it. More like that.")
        XCTAssertNil(dj.rateAction)
    }

    /// Going for a thumb as the question left, the press landed on the overview under it, and a deck went from 1:08 to 4:01.
    func testAThumbPressedAsTheQuestionLeavesStillCounts() async throws {
        let (dj, _) = try await makeScreen()
        let window = try XCTUnwrap(self.window)
        let before = Set(controls(in: window.bounds).map { ObjectIdentifier($0.view) })
        var rated: Bool?
        dj.say("Loop build done. More loop builds?", .done)
        dj.rateAction = { rated = $0 }
        // Long enough for it to have gone by itself, with its time up.
        try await settle(8600)
        XCTAssertNil(dj.statusMessage, "The question's gone")
        let thumbs = controls(in: window.bounds).filter { !before.contains(ObjectIdentifier($0.view)) }
        XCTAssertEqual(thumbs.count, 2, "Their touches are still there")
        thumbs[0].view.onDown?(.zero)
        thumbs[0].view.onUp?()
        XCTAssertNotNil(rated, "And count")
        try await settle(300)
        XCTAssertEqual(controls(in: window.bounds).filter { !before.contains(ObjectIdentifier($0.view)) }.count, 0, "Once")
    }

    func testTheKeysTouchesDontStayForever() async throws {
        let (dj, _) = try await makeScreen()
        let window = try XCTUnwrap(self.window)
        let before = Set(controls(in: window.bounds).map { ObjectIdentifier($0.view) })
        dj.say("Loop build done. More loop builds?", .done)
        dj.rateAction = { _ in }
        try await settle(8000 + 2800)
        XCTAssertEqual(controls(in: window.bounds).filter { !before.contains(ObjectIdentifier($0.view)) }.count, 0)
    }

    private func overview(of deck: Int) throws -> OverviewLiveView {
        var found: [OverviewLiveView] = []
        func walk(_ view: UIView) {
            if let view = view as? OverviewLiveView { found.append(view) }
            view.subviews.forEach(walk)
        }
        try walk(XCTUnwrap(window))
        return found[deck]
    }

    /// Pressing JOG made the waveforms hop 3 or 4 pt, in the first-time user's report for round 17.
    func testOnAPhoneTheWaveformsDontMoveWithADecksPage() async throws {
        for size in [CGSize(width: 667, height: 375), CGSize(width: 844, height: 390), CGSize(width: 375, height: 667)] {
            var tops: [CGFloat] = []
            for onJog in [false, true] {
                _ = try await makeScreen(size: size, startsOnJog: onJog)
                try await settle(300)
                let strip = try overview(of: 1)
                tops.append(strip.convert(strip.bounds, to: nil).minY)
            }
            XCTAssertEqual(tops[0], tops[1], accuracy: 0.5, "At \(size)")
        }
    }

    /// One stray touch on this strip moved a live track by minutes.
    func testOnAPlayingDeckAStrayTouchOnTheOverviewDoesntJump() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0], strip = try overview(of: 0)
        var said: String?
        deck.onMessage = { message, _ in said = message }
        deck.play()
        XCTAssertTrue(deck.isPlaying)
        strip.touchDown(at: strip.bounds.width * 0.9)
        strip.touchUp()
        XCTAssertEqual(deck.position, 20, accuracy: 0.5, "A tap's not enough")
        XCTAssertEqual(said, "Hold the overview for a moment to jump while the deck's playing.")
        try await settle(Int(OverviewLiveView.holdToJump * 1000) + 200)
        XCTAssertEqual(deck.position, 20, accuracy: 0.5, "Nor does it go off late")

        strip.touchDown(at: strip.bounds.width * 0.9)
        try await settle(Int(OverviewLiveView.holdToJump * 1000) + 200)
        XCTAssertEqual(deck.position, 54, accuracy: 1, "Held, it goes")
        strip.touchUp()

        deck.seek(to: 20)
        strip.touchDown(at: strip.bounds.width * 0.5)
        strip.touchMoved(to: strip.bounds.width * 0.8)
        XCTAssertEqual(deck.position, 20, accuracy: 0.5, "A thumb brushing along it is still a stray touch")
        strip.touchUp()
        XCTAssertEqual(deck.position, 20, accuracy: 0.5)

        strip.touchDown(at: strip.bounds.width * 0.5)
        try await settle(Int(OverviewLiveView.holdToJump * 1000) + 200)
        XCTAssertEqual(deck.position, 30, accuracy: 1)
        strip.touchMoved(to: strip.bounds.width * 0.8)
        XCTAssertEqual(deck.position, 48, accuracy: 1, "Once it's held it goes with the finger")
        strip.touchUp()

        deck.pause()
        strip.touchDown(at: strip.bounds.width * 0.25)
        XCTAssertEqual(deck.position, 15, accuracy: 1, "Stopped, it goes at once")
        strip.touchUp()
    }

    /// Presses the BROWSE key, where it is at the top left, and waits for the decks to slide away.
    private func pressBrowse() async throws {
        let key = try XCTUnwrap(window?.hitTest(CGPoint(x: 112, y: 12), with: nil) as? TouchSurfaceView)
        key.onDown?(.zero)
        key.onUp?()
        try await settle(2000)
    }

    func testOpeningTheBrowserWithARollHeldEndsTheRoll() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.play()
        let start = deck.renderer.playhead
        try await holdFirstPad(of: deck, on: .roll)
        _ = dj.renderOffline(frames: 44_100)
        try await pressBrowse()
        assertRollEnded(deck, dj: dj, heldFrom: start, frames: 44_100)
    }

    /// The browser stays built while the decks are showing and the other way about, so nothing's built twice.
    func testClosingTheBrowserBringsBackTheSameDeck() async throws {
        _ = try await makeScreen()
        let cue = try XCTUnwrap(window?.hitTest(CGPoint(x: 36, y: 544), with: nil))
        try await pressBrowse()
        XCTAssertNil(cue.window, "Out of sight, it's out of the window")
        try await pressBrowse()
        XCTAssertNotNil(cue.window)
        XCTAssertTrue(window?.hitTest(CGPoint(x: 36, y: 544), with: nil) === cue)
    }

    /// Round 12: PLAY pressed just after closing the browser landed on a pad going past, and set a hot cue, 4 times out of 5.
    /// So anything a press can find from the first moment of the slide has to be what'll be there when it stops.
    func testAPressDuringTheSlideLandsOnWhatsArriving() async throws {
        _ = try await makeScreen()
        let window = try XCTUnwrap(self.window)
        let settled = controls(in: window.bounds)
        XCTAssertGreaterThan(settled.count, 40)
        // The decks are in hosts of their own. The mixer isn't, and takes no touches while it's moving.
        func isInADeck(_ view: UIView) -> Bool {
            var hosts = 0
            var next: UIView? = view
            while let current = next {
                if String(describing: type(of: current)).contains("HostingView") { hosts += 1 }
                next = current.superview
            }
            return hosts >= 2
        }
        let deckControls = settled.filter { isInADeck($0.view) }
        XCTAssertGreaterThan(deckControls.count, 20)
        XCTAssertLessThan(deckControls.count, settled.count)
        try await pressBrowse()

        let key = try XCTUnwrap(window.hitTest(CGPoint(x: 112, y: 12), with: nil) as? TouchSurfaceView)
        key.onDown?(.zero)
        key.onUp?()
        // For its first moment the decks are still on their way back into the window, and a press finds nothing, which is fine.
        // What it mustn't find is some other control.
        for (wait, decksThere) in [(20, false), (40, true), (80, true), (80, true), (80, true)] {
            try await Task.sleep(for: .milliseconds(wait))
            var missing = 0, wrong = 0
            for control in settled {
                let hit = window.hitTest(control.point, with: nil)
                if hit === control.view { continue }
                if hit is TouchSurfaceView { wrong += 1 } else if isInADeck(control.view) { missing += 1 }
            }
            print("SLIDEHITS: \(wait) ms further on, of \(settled.count): \(wrong) landed on another control, \(missing) of the decks' on nothing")
            XCTAssertEqual(wrong, 0, "\(wait) ms further on")
            if decksThere { XCTAssertEqual(missing, 0, "\(wait) ms further on") }
        }
        // And once it's all stopped, the mixer's back as well.
        try await Task.sleep(for: .milliseconds(500))
        for control in settled { XCTAssertTrue(window.hitTest(control.point, with: nil) === control.view) }
        window.isHidden = true
    }

    /// The decks slide with UIKit and the mixer with SwiftUI, and they have to look like one thing moving.
    func testTheDecksAndTheMixerSlideTogether() async throws {
        _ = try await makeScreen()
        let window = try XCTUnwrap(self.window)
        func find<T: UIView>(in view: UIView) -> [T] {
            view.subviews.flatMap { [$0 as? T].compactMap { $0 } + find(in: $0) }
        }
        func showing(_ view: UIView) -> CGFloat {
            guard let shown = view.layer.presentation(), let top = window.layer.presentation() else { return 0 }
            return shown.convert(CGPoint.zero, to: top).x
        }
        // Below the top bar and the waveforms, which don't move.
        let surfaces: [TouchSurfaceView] = find(in: window).filter { ($0 as UIView).convert(CGPoint.zero, to: window).y > window.bounds.height * 0.45 }
        func place(_ view: UIView) -> CGFloat { view.convert(CGPoint.zero, to: window).x }
        let width = window.bounds.width
        // The crossfader's the widest thing in the middle, and any control at the far right is deck 2's.
        let crossfader = try XCTUnwrap(surfaces.filter { place($0) > width * 0.3 && place($0) < width * 0.6 }.max { $0.bounds.width < $1.bounds.width })
        let deck2 = try XCTUnwrap(surfaces.max { place($0) < place($1) })
        let apart = place(deck2) - place(crossfader)
        let key = try XCTUnwrap(window.hitTest(CGPoint(x: 112, y: 12), with: nil) as? TouchSurfaceView)
        // The first slide after a launch can wait on the simulator's render server for 100 to 240 ms, whatever the app's doing,
        // and that isn't what this is about. One there and back gets it out of the way.
        for _ in 0..<2 {
            key.onDown?(.zero)
            key.onUp?()
            try await settle(1500)
        }
        // The best of three: a busy Mac can slip a frame, about 30 pt at this speed, and read 46. What's wrong with the slide itself
        // is wrong every time: 62 without the delay, and 110 to 320 with a label changing as it starts.
        var worst: [CGFloat] = []
        for _ in 0..<3 {
            key.onDown?(.zero)
            key.onUp?()
            var mixer: [CGFloat] = [], gaps: [CGFloat] = []
            // Not much longer than this, as the deck leaves the window once it's out of sight.
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(16))
                // A busy Mac can take that long over 30 of these, and what's left has nothing to measure: it read 566.
                guard deck2.window != nil else { break }
                mixer.append(showing(crossfader))
                gaps.append(showing(deck2) - showing(crossfader) - apart)
            }
            print("SLIDETOGETHER: mixer \(mixer.map { Int($0) })")
            print("SLIDETOGETHER: off by \(gaps.map { Int($0) })")
            XCTAssertNotEqual(mixer.first ?? 0, mixer.last ?? 0, accuracy: 20, "It should have moved")
            worst.append(gaps.map(abs).max() ?? 0)
            try await settle(1500)
            key.onDown?(.zero)
            key.onUp?()
            try await settle(1500)
        }
        XCTAssertLessThan(worst.min() ?? 0, 45, "They drift apart by this much on the way")
        window.isHidden = true
    }

    /// Round 13: deck 1 went left as the mixer went right, and the browser hadn't got there yet, so black opened between them:
    /// 381 pt on the iPad, like a pair of doors. The panels' own timing has nothing to do with this one.
    func testNoGapOpensBesideTheMixerWhenTheBrowserOpensOrCloses() async throws {
        _ = try await makeScreen()
        let window = try XCTUnwrap(self.window)
        func find<T: UIView>(in view: UIView) -> [T] {
            view.subviews.flatMap { [$0 as? T].compactMap { $0 } + find(in: $0) }
        }
        func showing(_ view: UIView) -> CGRect? {
            guard let shown = view.layer.presentation(), let top = window.layer.presentation() else { return nil }
            return shown.convert(shown.bounds, to: top)
        }
        // What slides, each in a controller of its own.
        func panels() -> [UIView] {
            find(in: window).filter { view in
                guard let owner = view.superview?.next else { return false }
                return String(describing: type(of: owner)).contains("OffstageController")
            }
        }
        let surfaces: [TouchSurfaceView] = find(in: window).filter { ($0 as UIView).convert(CGPoint.zero, to: window).y > window.bounds.height * 0.45 }
        func place(_ view: UIView) -> CGFloat { view.convert(CGPoint.zero, to: window).x }
        let width = window.bounds.width
        let crossfader = try XCTUnwrap(surfaces.filter { place($0) > width * 0.3 && place($0) < width * 0.6 }.max { $0.bounds.width < $1.bounds.width })
        // How far the crossfader sits in from the mixer's left edge, which starts just past deck 1's right edge.
        let deck1Right = try XCTUnwrap(panels().filter { $0.convert($0.bounds, to: window).minX < 10 }.map { $0.convert($0.bounds, to: window).maxX }.first)
        let inset = place(crossfader) - deck1Right
        // Until the browser's built, which comes a moment after launch, the first press has nothing to slide in.
        try await Task.sleep(for: .seconds(1.8))

        for way in ["opening", "closing"] {
            let key = try XCTUnwrap(window.hitTest(CGPoint(x: 112, y: 12), with: nil) as? TouchSurfaceView)
            key.onDown?(.zero)
            key.onUp?()
            var gaps: [CGFloat] = []
            for _ in 0..<28 {
                try await Task.sleep(for: .milliseconds(16))
                guard let mixer = showing(crossfader) else { continue }
                // Whatever's reaching furthest towards the mixer, from the left of it.
                let edge = panels().compactMap(showing).filter { $0.minX < mixer.minX - inset - 40 }.map(\.maxX).max() ?? 0
                gaps.append(mixer.minX - inset - edge)
            }
            print("NOGAP: \(way) \(gaps.map { Int($0) })")
            // The mixer only moves when the main thread gets a turn, which can leave it behind for a frame, most of all on the
            // first slide after launch. Before, it was every frame in the middle of the slide.
            XCTAssertLessThanOrEqual(gaps.filter { $0 > 60 }.count, 2, "Black between the panels, \(way): \(gaps.map { Int($0) })")
            try await Task.sleep(for: .milliseconds(900))
        }
        window.isHidden = true
    }

    /// Round 12: on the Duo, messages of over about 60 characters lost their ends at any size, and the end's what you act on.
    func testALongMessageTakesASecondLine() async throws {
        let (dj, _) = try await makeScreen()
        func height(of message: String) -> CGFloat {
            dj.say(message, .info)
            let host = UIHostingController(rootView: StatusCapsule().environment(dj))
            return host.sizeThatFits(in: CGSize(width: 300, height: 200)).height
        }
        let short = height(of: "Mix off.")
        let long = height(of: "There's no loop to go back to yet. Press a loop size, or IN and OUT, and it goes round.")
        XCTAssertEqual(short, 24, accuracy: 1, "It's the size of the keys beside it")
        XCTAssertGreaterThan(long, 30, "Two lines, rather than an ellipsis")
        window?.isHidden = true
    }

    /// Leaving the window doesn't move a list. What round 10 saw was `testATouchAlongTheTopLeavesTheListAlone`.
    func testTheBrowsersListKeepsItsPlace() async throws {
        let (_, library) = try await makeScreen()
        library.tracks = (1...155).map { Track(id: UUID(), title: "Track \($0)", artist: "", fileName: "none", duration: 200, bpm: 120, key: "8A", dateAdded: .distantPast) }
        try await pressBrowse()
        func list() throws -> UICollectionView {
            func all(in view: UIView) -> [UICollectionView] {
                view.subviews.flatMap { [$0 as? UICollectionView].compactMap { $0 } + all(in: $0) }
            }
            return try XCTUnwrap(all(in: try XCTUnwrap(window)).max { $0.contentSize.height < $1.contentSize.height })
        }
        try list().setContentOffset(CGPoint(x: 0, y: 2000), animated: false)
        try await settle(500)
        print("LISTPLACE: scrolled \(try list().contentOffset.y) of \(try list().contentSize.height)")
        XCTAssertEqual(try list().contentOffset.y, 2000, accuracy: 1)
        try await pressBrowse()
        try await pressBrowse()
        print("LISTPLACE: reopened \(try list().contentOffset.y) of \(try list().contentSize.height)")
        XCTAssertEqual(try list().contentOffset.y, 2000, accuracy: 1, "The list should be where it was")
    }

    /// Round 10: on a phone held upright, a press along the top of the screen sent the list back to its top, every time.
    func testATouchAlongTheTopLeavesTheListAlone() async throws {
        let (_, library) = try await makeScreen()
        library.tracks = (1...30).map { Track(id: UUID(), title: "Track \($0)", artist: "", fileName: "none", duration: 200, bpm: 120, key: "8A", dateAdded: .distantPast) }
        try await pressBrowse()
        func all(in view: UIView) -> [UICollectionView] {
            view.subviews.flatMap { [$0 as? UICollectionView].compactMap { $0 } + all(in: $0) }
        }
        let lists = all(in: try XCTUnwrap(window))
        XCTAssertFalse(lists.isEmpty)
        for list in lists { XCTAssertFalse(list.scrollsToTop, "That's what takes it to the top") }
    }

    /// Round 11: now the list keeps its place, a search typed from far down it opened part-way through its results.
    func testASearchStartsFromTheTopOfItsResults() async throws {
        let (_, library) = try await makeScreen()
        library.tracks = (1...155).map { Track(id: UUID(), title: "Track \($0)", artist: "", fileName: "none", duration: 200, bpm: 120, key: "8A", dateAdded: .distantPast) }
        try await pressBrowse()
        func find<T: UIView>(in view: UIView) -> [T] {
            view.subviews.flatMap { [$0 as? T].compactMap { $0 } + find(in: $0) }
        }
        func list() throws -> UICollectionView {
            let lists: [UICollectionView] = find(in: try XCTUnwrap(window))
            return try XCTUnwrap(lists.max { $0.contentSize.height < $1.contentSize.height })
        }
        try list().setContentOffset(CGPoint(x: 0, y: 3000), animated: false)
        try await settle(300)
        let fields: [UITextField] = find(in: try XCTUnwrap(window))
        let field = try XCTUnwrap(fields.first)
        field.text = "Track 1"
        field.sendActions(for: .editingChanged)
        try await settle(800)
        print("SEARCHTOP: \(try list().contentOffset.y) of \(try list().contentSize.height)")
        XCTAssertLessThan(try list().contentSize.height, 7000, "The search did narrow it")
        XCTAssertLessThan(try list().contentOffset.y, 5, "From the first match")
    }

    /// Round 10: behind the file picker, the browser's list disappeared and the strip of decks jumped up the screen. A keyboard
    /// that isn't the browser's own search has no business moving it.
    func testAKeyboardThatIsntTheSearchsLeavesTheBrowserAlone() async throws {
        let (_, library) = try await makeScreen()
        library.tracks = (1...20).map { Track(id: UUID(), title: "Track \($0)", artist: "", fileName: "none", duration: 200, bpm: 120, key: "8A", dateAdded: .distantPast) }
        try await pressBrowse()
        func all(in view: UIView) -> [UICollectionView] {
            view.subviews.flatMap { [$0 as? UICollectionView].compactMap { $0 } + all(in: $0) }
        }
        func height() throws -> CGFloat {
            try XCTUnwrap(all(in: try XCTUnwrap(window)).max { $0.contentSize.height < $1.contentSize.height }).bounds.height
        }
        let before = try height()
        XCTAssertGreaterThan(before, 100)
        let size = Self.size
        NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil,
                                        userInfo: [UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 100, width: size.width, height: size.height - 100)])
        try await settle(600)
        XCTAssertEqual(try height(), before, accuracy: 1, "The list shouldn't make way for it")
        NotificationCenter.default.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil,
                                        userInfo: [UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: size.height, width: size.width, height: 0)])
        try await settle(300)
    }

    func testOpeningTheBrowserWithCueHeldEndsThePreview() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        let cue = try XCTUnwrap(window?.hitTest(CGPoint(x: 36, y: 544), with: nil) as? TouchSurfaceView)
        cue.onDown?(.zero)
        XCTAssertTrue(deck.cuePreviewing, "It's the CUE key")
        try await pressBrowse()
        XCTAssertFalse(deck.cuePreviewing, "Nothing's holding it any more")
        XCTAssertFalse(deck.isPlaying)
    }

    func testAnEffectHeldWhenItsPageGoesEndsLikeALift() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.play()
        try await holdFirstPad(of: deck, on: .fx)
        let effect = try XCTUnwrap(deck.activeFX.first?.effect)
        try await Task.sleep(for: .milliseconds(300)) // Long enough to be a hold, not a latch.
        deck.padMode = .hotCue
        try await settle()
        XCTAssertFalse(deck.isFXOn(effect))
    }

    func testAPadLeftOnScreenStillEndsOnItsOwnLift() async throws {
        let (dj, _) = try await makeScreen()
        let deck = dj.decks[0]
        deck.play()
        let start = deck.renderer.playhead
        try await holdFirstPad(of: deck, on: .roll)
        _ = dj.renderOffline(frames: 4096)
        let pads = controls(in: CGRect(x: 72, y: Self.size.height - 100, width: 320, height: 100))
            .filter { $0.point.x > 72 }
            .sorted { ($0.point.x, $0.point.y) < ($1.point.x, $1.point.y) }
        pads.first?.view.onUp?()
        assertRollEnded(deck, dj: dj, heldFrom: start, frames: 4096)
        deck.padMode = .hotCue
        try await settle()
        XCTAssertEqual(deck.heldMomentaryPads, 0, "and going away afterwards does nothing more")
    }

    // MARK: The Undo key

    func testTheUndoKeysTouchStaysStillWhileTheCapsuleArrives() async throws {
        let (dj, _) = try await makeScreen()
        let strip = CGRect(x: 300, y: 0, width: 650, height: 30)
        let before = Set(controls(in: strip).map { ObjectIdentifier($0.view) })
        // Where the key ends up, with the capsule settled.
        dj.decks[0].offerUndo?("Deleted hot cue A", .removed) {}
        try await settle(800)
        let settled = try XCTUnwrap(controls(in: strip).first { !before.contains(ObjectIdentifier($0.view)) })
        var undone = 0
        dj.statusMessage = nil
        dj.undoAction = nil
        try await settle(800)
        XCTAssertTrue(controls(in: strip).allSatisfy { before.contains(ObjectIdentifier($0.view)) }, "It's gone again")

        // From the first frame on, a touch there has to land on the key.
        dj.decks[0].offerUndo?("Deleted hot cue A", .removed) { undone += 1 }
        var frames = 0, missed = 0
        var pressed = false
        for _ in 0..<40 {
            await Task.yield()
            window?.layoutIfNeeded()
            frames += 1
            let hit = window?.hitTest(settled.point, with: nil)
            if let hit = hit as? TouchSurfaceView, !before.contains(ObjectIdentifier(hit)) {
                if frames > 25, !pressed {
                    hit.onDown?(.zero)
                    hit.onUp?()
                    pressed = true
                }
            } else {
                missed += 1
            }
            if pressed { break }
            try await Task.sleep(for: .milliseconds(12))
        }
        XCTAssertEqual(missed, 0, "A touch on it lands on it the whole time, out of \(frames) frames")
        XCTAssertEqual(undone, 1)
    }
}
