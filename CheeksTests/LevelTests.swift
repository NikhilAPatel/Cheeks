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
    func testBeatFXLevels() throws {
        let env = ProcessInfo.processInfo.environment
        guard let a = env["CHEEKS_FIXTURE_A"], let b = env["CHEEKS_FIXTURE_B"] else { throw XCTSkip("Set CHEEKS_FIXTURE_A and B") }
        for (path, from, bpm) in [(a, 53.0, 0.0), (b, 129.0, 0.0)] {
            let dj = DJEngine(library: Library())
            dj.stopRealtimeForTesting()
            let deck = dj.decks[0]
            let pcm = try AudioDecoder.decode(url: URL(filePath: path), sampleRate: sr)
            let analysis = TrackAnalyzer.analyze(pcm)
            deck.renderer.setSources([pcm])
            deck.track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: Double(pcm.frames) / sr, bpm: analysis.bpm + bpm, firstBeat: analysis.firstBeat)
            deck.setAutoGainForTesting(loudness: analysis.loudness)
            func measure(_ name: String, _ effects: [BeatFX], depth: Float = 0.6) -> (top: Float, rms: Float) {
                deck.clearFX()
                deck.fxBeats = 0.5
                deck.fxDepth = depth
                effects.forEach { deck.fxEngage($0) }
                deck.renderer.playhead = from * sr
                deck.renderer.isPlaying = true
                dj.updateVolumes()
                var top: Float = 0, red = 0, blocks = 0, energy: Float = 0, count = 0, limited = 0
                for i in 0..<(Int(sr * 13) / 1024) {
                    let out = dj.renderOffline(frames: 1024)
                    guard i > 40 else { continue }
                    blocks += 1
                    top = max(top, deck.level)
                    if deck.level > 1 { red += 1 }
                    if dj.limiterReduction > 0.5 { limited += 1 }
                    for x in out.left { energy += x * x }
                    count += out.left.count
                }
                let rms = (energy / Float(max(count, 1))).squareRoot()
                print("FXLEVEL: \((path as NSString).lastPathComponent) \(name) depth \(depth): meter top \(String(format: "%+.1f", 20 * log10(max(top, 0.0001)))) dB, red \(red * 100 / max(blocks, 1))%, limiter \(limited * 100 / max(blocks, 1))%, level \(String(format: "%.1f", 20 * log10(max(rms, 0.0001)))) dB")
                return (top, rms)
            }
            _ = measure("dry", [])
            for effect in BeatFX.allCases where effect.dsp != CheeksFXNone {
                _ = measure(effect.rawValue, [effect])
                _ = measure(effect.rawValue, [effect], depth: 1)
            }
            _ = measure("CRUSH+PHASER", [.crush, .phaser])
            _ = measure("CRUSH+PHASER+FLANGER", [.crush, .phaser, .flanger], depth: 1)
        }
    }
}
