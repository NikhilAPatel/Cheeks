import SwiftUI
import XCTest
@testable import Cheeks

/// Renders the real views at exact landscape screen sizes and writes PNGs, so layout can be
/// checked without tapping through the simulator. Opt-in; run on the 13-inch iPad (the largest screen):
///
///     TEST_RUNNER_CHEEKS_SNAPSHOT_DIR=/some/folder xcodebuild test … -only-testing:CheeksTests/LayoutSnapshots
@MainActor
final class LayoutSnapshots: XCTestCase {
    struct Screen {
        let name: String
        let size: CGSize
        let insets: UIEdgeInsets
        var scale: CGFloat = 3
    }

    /// Landscape sizes in points. The Duo's insets are guesses until it's seen on the device.
    static let screens = [
        Screen(name: "duo", size: CGSize(width: 951, height: 669), insets: .zero),
        Screen(name: "ipad13", size: CGSize(width: 1376, height: 1032), insets: .zero, scale: 2),
    ]

    func testSnapshots() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["CHEEKS_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_CHEEKS_SNAPSHOT_DIR to write layout snapshots")
        }
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        LiveRenderer.shared.captureMode = true
        // Optional: only write some screens, to keep iterating on one quick.
        let only = env["CHEEKS_SNAPSHOT_ONLY"]?.split(separator: ",").map(String.init)
        let onlyScreen = env["CHEEKS_SNAPSHOT_SCREEN"]

        func snapAll(_ name: String, _ view: @autoclosure () -> some View) async throws {
            if let only, !only.contains(name) { return }
            for screen in Self.screens where onlyScreen == nil || screen.name == onlyScreen {
                try await snap(view().environment(library).environment(dj), screen, to: dir.appending(path: "\(screen.name)-\(name).png"))
            }
        }

        try await snapAll("empty", ContentView(opensBrowserWhenEmpty: false))

        // Real music, if the caller points at some (see CLAUDE.md); otherwise a synthetic arrangement.
        loadFixture(dj.decks[0], audio: env["CHEEKS_FIXTURE_A"], title: "Midnight Drive (Extended Mix)", artist: "Synth Test", bpm: 124, key: "8A", chords: Synth.aMinor, at: 61, art: true)
        loadFixture(dj.decks[1], audio: env["CHEEKS_FIXTURE_B"], title: "Second Wind", artist: "Synth Test feat. Someone", bpm: 128, key: "10B", chords: Synth.dMajor, at: 92, art: false)
        dj.setMaster(dj.decks[0])
        dj.decks[1].sync(to: dj.decks[0])
        for deck in dj.decks {
            // Rendered once with the audio thread stopped, so positions and meters are settled.
            deck.renderer.isPlaying = true
            deck.isPlaying = true
        }
        _ = dj.renderOffline(frames: 2048)
        dj.decks[0].setLoop(beats: 4, resizeExisting: false)
        for mode in PadMode.allCases {
            dj.decks.forEach { $0.padMode = mode }
            if mode == .stems {
                // CHEEKS_REAL_STEMS runs the real model, to see what the colours look like with true stems.
                let separator: StemSeparator = env["CHEEKS_REAL_STEMS"] != nil ? StemSeparation.makeSeparator() : FrequencySplitSeparator()
                let stems = try separator.separate(dj.decks[0].renderer.mixSource ?? PCM16Stereo(frames: 1))
                dj.decks[0].renderer.setSources(stems)
                dj.decks[0].stemWaveform = StemWaveformData(stems: stems)
                dj.decks[0].stemStatus = .ready("AI")
                dj.decks[0].stemsOn = [false, true, true, true]
                dj.decks[1].stemStatus = .separating(0.42)
                _ = dj.renderOffline(frames: 2048)
            }
            if mode == .fx { dj.decks[0].fxEngage(.echo) }
            try await snapAll("decks-\(mode.id.lowercased().replacingOccurrences(of: " ", with: "-"))", ContentView(opensBrowserWhenEmpty: false))
            if mode == .fx { dj.decks[0].fxRelease() }
        }
        try await writeAppIcon(to: dir)
        dj.decks.forEach { $0.padMode = .hotCue }

        // Not saved: nothing here calls `library.update`, which is what writes the library to disk.
        let saved = library.tracks
        library.tracks = Self.libraryFixture
        try await snapAll("browser", ContentView(showLibrary: true))
        library.tracks = saved
        try await snapAll("recordings", RecordingsView())
        try await snapAll("settings", SettingsView())
        // Leaves the realtime engine's state harmless for whatever test runs next.
        dj.decks.forEach { $0.pause() }
        LiveRenderer.shared.captureMode = false
    }

    /// The app icon, drawn by the same shader as the jog wheel. Copied to the asset catalog by hand.
    private func writeAppIcon(to dir: URL) async throws {
        guard ProcessInfo.processInfo.environment["CHEEKS_WRITE_ICON"] != nil else { return }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let side: CGFloat = 1024.0 / 3 * 0.86
        window.frame = CGRect(x: 0, y: 0, width: side, height: side)
        window.windowLevel = .alert + 1
        let deck = Deck(index: 0)
        deck.renderer.setSources([PCM16Stereo(frames: 44_100)])
        deck.track = Track(id: UUID(), title: "Cheeks", artist: "", fileName: "none", duration: 1, bpm: 124)
        deck.cuePoint = 100 // keeps the amber cue light off the ring
        let jog = JogLiveView(deck: deck)
        jog.frame = window.bounds
        window.addSubview(jog)
        window.isHidden = false
        jog.metalLayer.contentsScale = 3
        jog.metalLayer.drawableSize = CGSize(width: side * 3, height: side * 3)
        jog.setNeedsLayout()
        jog.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        LiveRenderer.shared.captureForSnapshot()
        let captured = try XCTUnwrap(jog.layer.sublayers?.last?.contents)
        let jogImage = captured as! CGImage
        window.isHidden = true
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { context in
            let c = context.cgContext
            let colors = [UIColor(white: 0.135, alpha: 1).cgColor, UIColor(white: 0.035, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: CGPoint(x: 150, y: 0), end: CGPoint(x: 870, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            let size = side * 3
            let origin = (1024 - size) / 2
            UIImage(cgImage: jogImage).draw(in: CGRect(x: origin, y: origin, width: size, height: size))
            // The hub carries the mark: a blue spindle dot on the black label.
            let center = CGPoint(x: 512, y: 512)
            UIColor(white: 0.02, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: center.x - size * 0.2, y: center.y - size * 0.2, width: size * 0.4, height: size * 0.4))
            UIColor(red: 0.13, green: 0.52, blue: 1, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
        }
        try XCTUnwrap(image.pngData()).write(to: dir.appending(path: "AppIcon.png"))
    }

    static let libraryFixture: [Track] = [
        ("Midnight Drive (Extended Mix)", "Synth Test", 124.0, "8A", 412.0),
        ("Second Wind", "Synth Test feat. Someone", 128.0, "10B", 375.0),
        ("Low Tide", "Harbour Lights", 122.0, "4A", 398.0),
        ("Glass Houses (Club Mix)", "Mira Vale", 126.0, "9A", 441.0),
        ("Night Bus", "Ostinato", 125.0, "7A", 362.0),
        ("Paper Planes", "Kites & Co", 120.0, "11B", 329.0),
        ("Undertow", "Deep Current", 123.0, "5A", 455.0),
        ("Golden Hour (Dub)", "Sunset Strip", 118.0, "12B", 388.0),
    ].map { title, artist, bpm, key, duration in
        Track(id: UUID(), title: title, artist: artist, fileName: "none", duration: duration, bpm: bpm, key: key)
    }

    private func loadFixture(_ deck: Deck, audio: String?, title: String, artist: String, bpm: Double, key: String, chords: [[Int]], at seconds: Double, art: Bool) {
        var pcm = Self.arrangedTrack(bpm: bpm, firstBeat: 0.1, seconds: 180, chords: chords)
        if let audio, let decoded = try? AudioDecoder.decode(url: URL(fileURLWithPath: audio), sampleRate: AudioConfig.sampleRate) {
            pcm = decoded
        }
        deck.renderer.setSources([pcm])
        let analysis = TrackAnalyzer.analyze(pcm)
        deck.waveform = analysis.waveform
        let realBPM = audio == nil ? bpm : analysis.bpm
        let first = audio == nil ? 0.1 : analysis.firstBeat
        let beat = 60 / realBPM
        deck.track = Track(id: UUID(), title: title, artist: artist, fileName: "none", duration: pcm.duration, bpm: realBPM, firstBeat: first,
                           key: analysis.key ?? key, hotCues: [0: first, 1: first + 16 * beat, 3: first + 64 * beat, 5: first + 128 * beat])
        deck.seek(to: min(seconds, pcm.duration * 0.6))
        deck.cuePoint = first + 16 * beat
        if art { deck.artwork = Self.fixtureArtwork() }
    }

    /// A sleeve with some structure, to judge how artwork sits on the jog.
    static func fixtureArtwork() -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let image = renderer.image { context in
            let colors = [UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1).cgColor, UIColor(red: 0.2, green: 0.1, blue: 0.5, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 512, y: 512), options: [])
            UIColor(white: 1, alpha: 0.85).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 150, y: 90, width: 210, height: 210))
            UIColor(red: 0.1, green: 0.05, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 330, width: 512, height: 182))
        }
        return image.cgImage!
    }

    /// A track with an arrangement, so waveforms show structure the way real music does:
    /// intro (kick, hats), build (+ bass, claps), breakdown (chords only), drop (everything).
    static func arrangedTrack(bpm: Double, firstBeat: Double, seconds: Double, chords: [[Int]]) -> PCM16Stereo {
        let sr = Synth.sampleRate
        let n = Int(seconds * sr)
        var x = [Float](repeating: 0, count: n)
        let beat = 60 / bpm, sixteenth = beat / 4
        var seed: UInt32 = 987_654
        func noise() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
        func add(at time: Double, length: Double, _ sample: (Double) -> Double) {
            let start = Int(time * sr)
            for k in 0..<Int(length * sr) where start + k < n && start + k >= 0 { x[start + k] += Float(sample(Double(k) / sr)) }
        }
        var step = 0
        while firstBeat + Double(step) * sixteenth < seconds {
            let t = firstBeat + Double(step) * sixteenth
            let bar = step / 16, inBar = step % 16
            let section = bar < 4 ? 0 : bar < 8 ? 1 : bar < 12 ? 2 : 3 // intro, build, breakdown, drop
            if section != 2 && inBar % 4 == 0 {
                add(at: t, length: 0.18) { 0.95 * sin(2 * .pi * (48 + 90 * exp(-$0 * 35)) * $0) * exp(-$0 * 16) }
            }
            if section != 2 {
                let accent = inBar % 2 == 0 ? 0.08 : 0.14
                add(at: t, length: 0.03) { accent * Double(noise()) * exp(-$0 * 140) }
                if inBar % 4 == 2 { add(at: t, length: 0.12) { 0.12 * Double(noise()) * exp(-$0 * 30) } }
            }
            if section >= 1 && section != 2 && (inBar == 4 || inBar == 12) {
                add(at: t, length: 0.16) { (0.35 * Double(noise()) + 0.25 * sin(2 * .pi * 190 * $0)) * exp(-$0 * 22) }
            }
            let chord = chords[bar % chords.count]
            if section >= 1 && section != 2 && inBar % 4 == 2 {
                let f = Synth.frequency(midi: chord[0] - 24)
                add(at: t, length: sixteenth * 1.8) { 0.4 * sin(2 * .pi * f * $0) * exp(-$0 * 6) }
            }
            if section >= 2 && (inBar == 0 || inBar == 6 || inBar == 10) {
                let level = section == 2 ? 0.16 : 0.1
                add(at: t, length: section == 2 ? beat * 2 : sixteenth * 2) { u in
                    chord.reduce(0) { $0 + level * sin(2 * .pi * Synth.frequency(midi: $1) * u) } * exp(-u * (section == 2 ? 1.2 : 8))
                }
            }
            step += 1
        }
        let peak = x.map(abs).max() ?? 1
        x = x.map { $0 / peak * 0.9 }
        return PCM16Stereo(left: x, right: x)
    }

    private func snap(_ view: some View, _ screen: Screen, to url: URL) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: screen.size)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.layer.contentsScale = screen.scale
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.isHidden = false
        // A new window can start with the scene's portrait bounds, so lay it out at its real size.
        window.frame = CGRect(origin: .zero, size: screen.size)
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        // Top up whatever insets the window already gets from its spot on the iPad screen.
        let system = window.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: max(0, screen.insets.top - system.top),
                                                     left: max(0, screen.insets.left - system.left),
                                                     bottom: max(0, screen.insets.bottom - system.bottom),
                                                     right: max(0, screen.insets.right - system.right))
        try await Task.sleep(for: .milliseconds(500))
        LiveRenderer.shared.captureForSnapshot()
        let format = UIGraphicsImageRendererFormat()
        format.scale = screen.scale
        let image = UIGraphicsImageRenderer(size: screen.size, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        try XCTUnwrap(image.pngData()).write(to: url)
    }
}
