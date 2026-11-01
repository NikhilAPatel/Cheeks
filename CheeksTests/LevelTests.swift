import XCTest
@testable import Cheeks

/// How hard the master limiter works at default levels with real music. Opt-in, and it only reports:
/// set TEST_RUNNER_CHEEKS_FIXTURE_A and B.
@MainActor
final class LevelTests: XCTestCase {
    private let sr = AudioConfig.sampleRate

    func testLimiterAtDefaultLevels() throws {
        let env = ProcessInfo.processInfo.environment
        guard let a = env["CHEEKS_FIXTURE_A"], let b = env["CHEEKS_FIXTURE_B"] else { throw XCTSkip("Set CHEEKS_FIXTURE_A and B") }
        let dj = DJEngine(library: Library())
        dj.stopRealtimeForTesting()
        for (deck, path) in zip(dj.decks, [a, b]) {
            let pcm = try AudioDecoder.decode(url: URL(filePath: path), sampleRate: sr)
            let analysis = TrackAnalyzer.analyze(pcm)
            deck.renderer.setSources([pcm])
            deck.setAutoGainForTesting(loudness: analysis.loudness)
            deck.renderer.playhead = 40 * sr
            print("LEVEL: \((path as NSString).lastPathComponent) \(String(format: "%.1f", analysis.loudness ?? 0)) LUFS, gain \(String(format: "%+.1f", deck.autoGainDB)) dB")
        }
        func measure(_ name: String, decks: [Int]) {
            dj.decks.enumerated().forEach { $1.renderer.isPlaying = decks.contains($0) }
            dj.updateVolumes()
            var worst: Float = 0, working = 0, blocks = 0, peak: Float = 0, channelRed = [0, 0], channelTop: [Float] = [0, 0]
            for _ in 0..<(Int(sr * 30) / 1024) {
                let out = dj.renderOffline(frames: 1024)
                peak = max(peak, out.left.map(abs).max() ?? 0)
                let reduction = dj.limiterReduction
                worst = max(worst, reduction)
                if reduction > 0.5 { working += 1 }
                blocks += 1
                for (i, deck) in dj.decks.enumerated() {
                    if deck.level > 1 { channelRed[i] += 1 }
                    channelTop[i] = max(channelTop[i], deck.level)
                }
            }
            print("LEVEL: \(name): limiter over 0.5 dB for \(working * 100 / max(blocks, 1))% of the time, worst \(String(format: "%.1f", worst)) dB, output peak \(String(format: "%.2f", peak))")
            for i in decks {
                print("LEVEL: \(name): deck \(i + 1)'s meter in the red \(channelRed[i] * 100 / max(blocks, 1))% of the time, top \(String(format: "%+.1f", 20 * log10(max(channelTop[i], 0.0001)))) dB")
            }
        }
        measure("one deck", decks: [0])
        measure("other deck", decks: [1])
        measure("both decks", decks: [0, 1])
    }

    /// What each beat effect does to the deck's meter and the level, against the same stretch dry.
    /// It reads the meter 60 times a second, and works out what the screen would show from
    /// `MeterLiveView`'s ballistics: a single peak over 0 dB holds a red LED up for over a second.
    func testBeatFXLevels() throws {
        let env = ProcessInfo.processInfo.environment
        guard let a = env["CHEEKS_FIXTURE_A"], let b = env["CHEEKS_FIXTURE_B"] else { throw XCTSkip("Set CHEEKS_FIXTURE_A and B") }
        for (path, from) in [(a, 53.0), (b, 129.0)] {
            let dj = DJEngine(library: Library())
            dj.stopRealtimeForTesting()
            let deck = dj.decks[0]
            let pcm = try AudioDecoder.decode(url: URL(filePath: path), sampleRate: sr)
            let analysis = TrackAnalyzer.analyze(pcm)
            deck.renderer.setSources([pcm])
            var track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: Double(pcm.frames) / sr, bpm: analysis.bpm, firstBeat: analysis.firstBeat)
            track.tempoMarkers = analysis.tempoMarkers
            deck.track = track
            deck.setAutoGainForTesting(loudness: analysis.loudness)

            func position(_ level: Float) -> Float { level > 0.0001 ? max(0, min(1, (20 * log10(level) + 42) / 45)) : 0 }

            /// From `from + offset`, for 13 s: the meter's top, the share of frames the screen would show red, and the level.
            func measure(_ effects: [BeatFX], depth: Float, offset: Double) -> (top: Float, red: Float, level: Float) {
                deck.clearFX()
                _ = dj.renderOffline(frames: Int(sr)) // Tails die down.
                deck.fxBeats = 0.5
                deck.fxDepth = depth
                effects.forEach { deck.fxEngage($0) }
                deck.renderer.playhead = (from + offset) * sr
                deck.renderer.isPlaying = true
                dj.updateVolumes()
                var top: Float = 0, energy: Float = 0, count = 0, frames = 0, redFrames = 0
                var eased: Float = 0, peak: Float = 0, held = 0.0
                let dt = 1.0 / 60
                for i in 0..<(13 * 60) {
                    let out = dj.renderOffline(frames: Int(sr / 60))
                    let target = position(deck.level)
                    eased += (target - eased) * (target > eased ? 1 : Float(min(1, dt * 7)))
                    let now = Double(i) * dt
                    if eased >= peak {
                        peak = eased
                        held = now
                    } else if now - held > 1.1 {
                        peak = max(eased, peak - Float(dt) * 0.5)
                    }
                    guard i > 40 else { continue }
                    frames += 1
                    top = max(top, deck.level)
                    // The red LEDs start at 0 dB on the scale of 30 segments.
                    if peak >= 42.0 / 45 || eased >= 28.5 / 30 { redFrames += 1 }
                    for x in out.left { energy += x * x }
                    count += out.left.count
                }
                deck.renderer.isPlaying = false
                return (20 * log10(max(top, 0.0001)), Float(redFrames) * 100 / Float(max(frames, 1)), 10 * log10(max(energy / Float(max(count, 1)), 1e-9)))
            }

            let name = (path as NSString).lastPathComponent
            let dry = measure([], depth: 0.6, offset: 0)
            print("FXLEVEL: \(name) dry: top \(String(format: "%+.1f", dry.top)) dB, red \(String(format: "%.1f", dry.red))%, level \(String(format: "%.1f", dry.level)) dB")
            let rows: [(String, [BeatFX], Float)] = BeatFX.allCases.filter { $0.dsp != CheeksFXNone }.flatMap { [($0.rawValue, [$0], Float(0.6)), ($0.rawValue, [$0], Float(1))] }
                + [("CRUSH+PHASER", [.crush, .phaser], 0.6), ("ECHO+FLANGER+REVERB", [.echo, .flanger, .reverb], 0.6)]
            for (label, effects, depth) in rows {
                // The effects keep time with the beat, so which peaks they catch depends on where they start.
                let runs = stride(from: 0.0, to: 4.0, by: 0.8).map { measure(effects, depth: depth, offset: $0) }
                let top = runs.map(\.top).max() ?? 0, red = runs.map(\.red).max() ?? 0, level = runs[0].level - dry.level
                print("FXLEVEL: \(name) \(label) depth \(depth): top \(String(format: "%+.1f", top)) dB, red on screen up to \(String(format: "%.1f", red))%, level \(String(format: "%+.1f", level)) dB")
            }
        }
    }
}
