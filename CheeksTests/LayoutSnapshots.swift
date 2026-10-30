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
        Screen(name: "duo", size: CGSize(width: 951, height: 669), insets: UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)),
        Screen(name: "ipad13", size: CGSize(width: 1376, height: 1032), insets: UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0), scale: 2),
    ]

    func testSnapshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["CHEEKS_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_CHEEKS_SNAPSHOT_DIR to write layout snapshots")
        }
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let library = Library()
        let dj = DJEngine(library: library)

        func snapAll(_ name: String, _ view: some View) async throws {
            for screen in Self.screens {
                try await snap(view.environment(library).environment(dj), screen, to: dir.appending(path: "\(screen.name)-\(name).png"))
            }
        }

        try await snapAll("empty", ContentView())

        loadFixture(dj.decks[0], title: "Midnight Drive (Extended Mix)", artist: "Synth Test", bpm: 124, key: "8A", chords: Synth.aMinor, at: 31)
        loadFixture(dj.decks[1], title: "Second Wind", artist: "Synth Test feat. Someone", bpm: 128, key: "10B", chords: Synth.dMajor, at: 62)
        dj.decks[1].syncOn = true
        for mode in PadMode.allCases {
            dj.decks.forEach { $0.padMode = mode }
            if mode == .stems {
                dj.decks[0].stemStatus = .separating(0.42)
                dj.decks[1].stemStatus = .ready("APPROX")
            }
            try await snapAll("decks-\(mode.id.lowercased().replacingOccurrences(of: " ", with: "-"))", ContentView())
        }
        dj.decks.forEach { $0.padMode = .hotCue }

        // Not saved: nothing here calls `library.update`, which is what writes the library to disk.
        let saved = library.tracks
        library.tracks = Self.libraryFixture
        try await snapAll("browser", ContentView(showLibrary: true))
        library.tracks = saved
        try await snapAll("recordings", RecordingsView())
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

    private func loadFixture(_ deck: Deck, title: String, artist: String, bpm: Double, key: String, chords: [[Int]], at seconds: Double) {
        let pcm = Self.arrangedTrack(bpm: bpm, firstBeat: 0.1, seconds: 90, chords: chords)
        deck.renderer.setSources([pcm])
        deck.waveform = TrackAnalyzer.analyze(pcm).waveform
        let beat = 60 / bpm
        deck.track = Track(id: UUID(), title: title, artist: artist, fileName: "none", duration: 90, bpm: bpm, firstBeat: 0.1,
                           key: key, hotCues: [0: 0.1, 1: 0.1 + 16 * beat, 3: 0.1 + 64 * beat])
        deck.seek(to: seconds)
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
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.isHidden = false
        // Top up whatever insets the window already gets from its spot on the iPad screen.
        let system = window.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: max(0, screen.insets.top - system.top),
                                                     left: max(0, screen.insets.left - system.left),
                                                     bottom: max(0, screen.insets.bottom - system.bottom),
                                                     right: max(0, screen.insets.right - system.right))
        try await Task.sleep(for: .milliseconds(500))
        let format = UIGraphicsImageRendererFormat()
        format.scale = screen.scale
        let image = UIGraphicsImageRenderer(size: screen.size, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        try XCTUnwrap(image.pngData()).write(to: url)
    }
}
