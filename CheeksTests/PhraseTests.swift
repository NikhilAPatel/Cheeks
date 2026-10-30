import XCTest
@testable import Cheeks

/// Does the phrase analysis find a song's structure? The arrangement here is known exactly.
final class PhraseTests: XCTestCase {
    private let sr = AudioConfig.sampleRate

    private struct Part {
        var bars: Int
        var kick = false, hats = false, bass = false, chords = false, riser = false
    }

    /// Builds a track bar by bar. Quiet parts really are quiet, and the big ones have everything in.
    private func render(_ parts: [Part], bpm: Double, chords: [[Int]] = Synth.aMinor) -> PCM16Stereo {
        let beat = 60 / bpm
        let bar = beat * 4
        let totalBars = parts.reduce(0) { $0 + $1.bars }
        let n = Int(Double(totalBars) * bar * sr)
        var x = [Float](repeating: 0, count: n)
        var seed: UInt32 = 1
        func noise() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
        var barIndex = 0
        for part in parts {
            for b in 0..<part.bars {
                let barStart = Double(barIndex) * bar
                let start = Int(barStart * sr), end = min(n, Int((barStart + bar) * sr))
                let chord = chords[barIndex % chords.count]
                if part.chords {
                    for k in start..<end {
                        let t = Double(k) / sr
                        var v = 0.0
                        for note in chord { v += 0.09 * sin(2 * .pi * Synth.frequency(midi: note) * t) }
                        x[k] += Float(v)
                    }
                }
                if part.bass {
                    for k in start..<end {
                        let t = Double(k) / sr
                        x[k] += Float(0.3 * sin(2 * .pi * Synth.frequency(midi: chord[0] - 24) * t))
                    }
                }
                if part.riser {
                    let amount = Float(b) / Float(max(1, part.bars))
                    var low: Float = 0
                    for k in start..<end {
                        low += (noise() - low) * (0.05 + 0.5 * amount)
                        x[k] += low * (0.05 + 0.3 * amount)
                    }
                }
                for s in 0..<4 {
                    let beatStart = Int((barStart + Double(s) * beat) * sr)
                    if part.kick {
                        for k in 0..<Int(0.15 * sr) where beatStart + k < n {
                            let t = Double(k) / sr
                            x[beatStart + k] += Float(0.8 * sin(2 * .pi * (50 + 80 * exp(-t * 30)) * t) * exp(-t * 18))
                        }
                    }
                    if part.hats {
                        let hat = Int((barStart + (Double(s) + 0.5) * beat) * sr)
                        for k in 0..<Int(0.04 * sr) where hat + k < n {
                            x[hat + k] += 0.2 * noise() * Float(exp(-Double(k) / sr * 90))
                        }
                    }
                }
                barIndex += 1
            }
        }
        let peak = x.map(abs).max() ?? 1
        return PCM16Stereo(left: x.map { $0 / peak * 0.9 }, right: x.map { $0 / peak * 0.9 })
    }

    /// Checks the sections come out in order with their boundaries in the right bars.
    private func check(_ phrases: [Phrase], expected: [(Phrase.Kind, Int)], bpm: Double, tolerance: Double = 1,
                       file: StaticString = #filePath, line: UInt = #line) {
        let bar = 240 / bpm
        let got = phrases.map { "\($0.kind.rawValue)@\(String(format: "%.1f", $0.start / bar))" }.joined(separator: " ")
        print("PHRASE: \(got)")
        XCTAssertEqual(phrases.map(\.kind), expected.map(\.0), "Got \(got)", file: file, line: line)
        guard phrases.count == expected.count else { return }
        for (phrase, want) in zip(phrases, expected) {
            XCTAssertEqual(phrase.start / bar, Double(want.1), accuracy: tolerance, "\(phrase.kind) in \(got)", file: file, line: line)
        }
    }

    func testAClubArrangement() throws {
        let parts = [
            Part(bars: 32, kick: true, hats: true),
            Part(bars: 16, kick: true, hats: true, riser: true),
            Part(bars: 32, kick: true, hats: true, bass: true, chords: true),
            Part(bars: 24, chords: true),
            Part(bars: 8, chords: true, riser: true),
            Part(bars: 32, kick: true, hats: true, bass: true, chords: true),
            Part(bars: 24, kick: true, hats: true),
        ]
        let result = TrackAnalyzer.analyze(render(parts, bpm: 126), knownGrid: BeatGrid(bpm: 126, firstBeat: 0))
        let phrases = try XCTUnwrap(result.phrases)
        // A riser fades in from nothing, so where the build "starts" is a judgement call: the kinds
        // and the hard edges have to be right, and the build has to start somewhere inside the riser.
        check(phrases, expected: [(.intro, 0), (.up, 40), (.chorus, 48), (.down, 80), (.up, 106), (.chorus, 112), (.outro, 144)], bpm: 126, tolerance: 8)
        let bar = 240.0 / 126
        XCTAssertEqual(phrases[2].start / bar, 48, accuracy: 1)
        XCTAssertEqual(phrases[3].start / bar, 80, accuracy: 1)
        XCTAssertEqual(phrases[5].start / bar, 112, accuracy: 1)
        XCTAssertEqual(phrases[6].start / bar, 144, accuracy: 1)
    }

    func testASongWithVerses() throws {
        let parts = [
            Part(bars: 8, chords: true),
            Part(bars: 16, kick: true, chords: true),
            Part(bars: 16, kick: true, hats: true, bass: true, chords: true),
            Part(bars: 16, kick: true, chords: true),
            Part(bars: 16, kick: true, hats: true, bass: true, chords: true),
            Part(bars: 8, chords: true),
        ]
        let result = TrackAnalyzer.analyze(render(parts, bpm: 100), knownGrid: BeatGrid(bpm: 100, firstBeat: 0))
        let phrases = try XCTUnwrap(result.phrases)
        check(phrases, expected: [(.intro, 0), (.chorus, 24), (.verse, 40), (.chorus, 56), (.outro, 72)], bpm: 100)
    }

    func testATrackThatNeverChangesIsOneSection() throws {
        let parts = [Part(bars: 64, kick: true, hats: true, bass: true, chords: true)]
        let result = TrackAnalyzer.analyze(render(parts, bpm: 128, chords: [[57, 60, 64]]), knownGrid: BeatGrid(bpm: 128, firstBeat: 0))
        let phrases = try XCTUnwrap(result.phrases)
        XCTAssertLessThanOrEqual(phrases.count, 2, "Got \(phrases)")
    }

    func testAVeryShortClipHasNoSections() {
        let result = TrackAnalyzer.analyze(Synth.track(bpm: 120, firstBeat: 0, seconds: 6, chords: Synth.aMinor))
        XCTAssertNil(result.phrases)
    }

    /// Opt-in, for looking at real music: set TEST_RUNNER_CHEEKS_FIXTURE_A and B.
    func testRealMusic() throws {
        let env = ProcessInfo.processInfo.environment
        let paths = [env["CHEEKS_FIXTURE_A"], env["CHEEKS_FIXTURE_B"]].compactMap { $0 }
        try XCTSkipIf(paths.isEmpty, "Set CHEEKS_FIXTURE_A to run this")
        for path in paths {
            let pcm = try AudioDecoder.decode(url: URL(filePath: path), sampleRate: sr)
            let started = Date()
            let result = TrackAnalyzer.analyze(pcm)
            let sections = (result.phrases ?? []).map { "\($0.kind.rawValue)@\($0.start.clockString)" }.joined(separator: " ")
            let onsetHops = pcm.frames / TrackAnalyzer.tempoHop
            var full = [Float](repeating: 0, count: onsetHops), low = [Float](repeating: 0, count: onsetHops)
            let filter = Biquad.lowpass(150, sampleRate: sr)
            var tempoLow = (filter, filter)
            for i in 0..<pcm.frames where i / TrackAnalyzer.tempoHop < onsetHops {
                let m = (pcm.left(i) + pcm.right(i)) * 0.5
                let t = tempoLow.1.process(tempoLow.0.process(m))
                full[i / TrackAnalyzer.tempoHop] += m * m
                low[i / TrackAnalyzer.tempoHop] += t * t
            }
            let onset = TrackAnalyzer.onsetEnvelope(energyFull: full, energyLow: low)
            let steady = TrackAnalyzer.detectTempo(onset: onset, sampleRate: sr)
            let e = TempoMapDetector.evaluate(onset: onset, fps: sr / Double(TrackAnalyzer.tempoHop), bpm: steady.bpm, firstBeat: steady.firstBeat)
            print("TEMPO: \((path as NSString).lastPathComponent) steady \(steady.bpm) wander \(Int(e.wander * 1000)) ms, spread \(String(format: "%.1f", e.spread)) BPM, fit steady \(String(format: "%.2f", e.steadyFit)) map \(String(format: "%.2f", e.mapFit))")
            print("PHRASE: \((path as NSString).lastPathComponent) \(pcm.duration.clockString) analysed in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, \(result.bpm) BPM, \(result.tempoMarkers?.count ?? 0) tempo markers, \(sections)")
        }
    }
}
