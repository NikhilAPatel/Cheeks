import XCTest
@testable import Cheeks

final class AnalysisTests: XCTestCase {
    func testTempoAndBeatGrid() {
        for (bpm, firstBeat) in [(128.0, 0.37), (174.0, 0.10), (92.0, 0.52), (140.0, 0.0)] {
            let result = TrackAnalyzer.analyze(Synth.track(bpm: bpm, firstBeat: firstBeat, seconds: 40, chords: Synth.aMinor))
            XCTAssertEqual(result.bpm, bpm, accuracy: 0.05, "BPM for \(bpm)")

            let beat = 60 / bpm
            var error = (result.firstBeat - firstBeat).truncatingRemainder(dividingBy: beat)
            if error > beat / 2 { error -= beat }
            if error < -beat / 2 { error += beat }
            XCTAssertLessThan(abs(error), 0.012, "grid phase for \(bpm) BPM is off by \(error * 1000) ms")
        }
    }

    /// A track whose bars have a real "1": a loud hit every four beats on top of the kicks.
    func testGridStartsOnTheDownbeat() {
        let bpm = 126.0, offset = 0.2
        let sr = Synth.sampleRate
        var x = [Float](repeating: 0, count: Int(sr * 40))
        let beat = 60 / bpm
        var i = 0
        while offset + Double(i) * beat < 39.5 {
            let start = Int((offset + Double(i) * beat) * sr)
            let accent: Float = i % 4 == 3 ? 1 : 0.3 // the 4th beat from the start is the bar's "1"
            for k in 0..<Int(0.1 * sr) {
                x[start + k] += accent * Float(sin(2 * .pi * 70 * Double(k) / sr) * exp(-Double(k) / sr * 30))
            }
            i += 1
        }
        let result = TrackAnalyzer.analyze(PCM16Stereo(left: x, right: x))
        XCTAssertEqual(result.bpm, bpm, accuracy: 0.05)
        let bar = 4 * beat
        var error = (result.firstBeat - (offset + 3 * beat)).truncatingRemainder(dividingBy: bar)
        if error > bar / 2 { error -= bar }
        if error < -bar / 2 { error += bar }
        XCTAssertLessThan(abs(error), 0.015, "bar 1 is off by \(error * 1000) ms")
    }

    func testKeyDetection() {
        let cases: [([[Int]], String)] = [(Synth.aMinor, "8A"), (Synth.dMajor, "10B"), (Synth.fMinor, "4A")]
        for (chords, expected) in cases {
            let result = TrackAnalyzer.analyze(Synth.track(bpm: 124, firstBeat: 0, seconds: 30, chords: chords))
            XCTAssertEqual(result.key, expected)
        }
    }

    func testWaveformRoundTrip() {
        let wave = TrackAnalyzer.analyze(Synth.track(bpm: 120, firstBeat: 0, seconds: 5, chords: Synth.aMinor)).waveform
        XCTAssertEqual(wave.count, Int(5 * WaveformData.binsPerSecond))
        let decoded = WaveformData(data: wave.encoded())
        XCTAssertEqual(decoded?.low, wave.low)
        XCTAssertEqual(decoded?.mid, wave.mid)
        XCTAssertEqual(decoded?.high, wave.high)
    }

    func testCamelot() {
        XCTAssertEqual(Camelot.code(pitchClass: 9, minor: true), "8A")   // A minor
        XCTAssertEqual(Camelot.code(pitchClass: 0, minor: false), "8B")  // C major
        XCTAssertEqual(Camelot.musicalName("8A"), "Am")
        XCTAssertTrue(Camelot.isCompatible("8A", "9A"))
        XCTAssertTrue(Camelot.isCompatible("12A", "1A"))
        XCTAssertTrue(Camelot.isCompatible("8A", "8B"))
        XCTAssertFalse(Camelot.isCompatible("8A", "10A"))
        XCTAssertFalse(Camelot.isCompatible("8A", "9B"))
    }

    func testFrequencySplitStemsSumToOriginal() throws {
        let audio = Synth.track(bpm: 126, firstBeat: 0.2, seconds: 10, chords: Synth.aMinor)
        let stems = try FrequencySplitSeparator().separate(audio)
        XCTAssertEqual(stems.count, 4)
        for i in stride(from: 0, to: audio.frames, by: 101) {
            let sum = stems.reduce(Float(0)) { $0 + Float($1.data[i * 2]) } / 32767 / PCM16Stereo.stemHeadroom
            XCTAssertEqual(sum, audio.left(i), accuracy: 0.0005)
        }
    }

    // MARK: Track map

    /// Four stems of a little club track: a kick on every beat and a clap on 2 and 4, a bass and chords that change on
    /// the 1, and a melody that comes in at bar 16 and a singer at bar 32.
    private func clubStems(bpm: Double, firstBar: Double, bars: Int, jitter: Double = 0) -> [PCM16Stereo] {
        let sr = Synth.sampleRate, beat = 60 / bpm
        let count = Int((firstBar + Double(bars) * 4 * beat + 1) * sr)
        var vocals = [Float](repeating: 0, count: count), melody = vocals, bass = vocals, drums = vocals
        var random = SystemRandomNumberGenerator()
        for bar in 0..<bars {
            let root = [45, 41, 48, 43][(bar / 2) % 4]
            for b in 0..<4 {
                let nudge = jitter > 0 ? Double.random(in: -jitter...jitter, using: &random) : 0
                let start = Int((firstBar + Double(bar * 4 + b) * beat + nudge) * sr)
                for k in 0..<Int(0.14 * sr) where start + k >= 0 && start + k < count {
                    let t = Double(k) / sr
                    drums[start + k] += Float(0.9 * sin(2 * .pi * (55 + 90 * exp(-t * 40)) * t) * exp(-t * 18))
                    if b % 2 == 1, k < Int(0.09 * sr) { drums[start + k] += Float.random(in: -0.35...0.35, using: &random) * Float(exp(-t * 30)) }
                }
            }
            let barStart = Int((firstBar + Double(bar * 4) * beat) * sr), barLength = Int(4 * beat * sr)
            for k in 0..<barLength where barStart + k < count {
                let t = Double(k) / sr
                bass[barStart + k] = Float(0.35 * sin(2 * .pi * Synth.frequency(midi: root - 12) * t))
                if bar >= 16 {
                    melody[barStart + k] = Float(0.12 * (sin(2 * .pi * Synth.frequency(midi: root + 12) * t) + sin(2 * .pi * Synth.frequency(midi: root + 15) * t)
                        + sin(2 * .pi * Synth.frequency(midi: root + 19) * t)))
                }
                if bar >= 32, bar < 48 { vocals[barStart + k] = Float(0.3 * sin(2 * .pi * Synth.frequency(midi: root + 24) * t)) }
            }
        }
        let g = PCM16Stereo.stemHeadroom
        return [vocals, melody, bass, drums].map { stem in
            let scaled = stem.map { $0 * g }
            return PCM16Stereo(left: scaled, right: scaled)
        }
    }

    func testTrackMapFindsTheKicksAndTheBars() throws {
        let bpm = 124.0, firstBar = 1.32
        let map = try XCTUnwrap(TrackMapper.map(stems: clubStems(bpm: bpm, firstBar: firstBar, bars: 64)))
        XCTAssertEqual(map.bpm, bpm, accuracy: 0.02)
        XCTAssertTrue(map.isSteady, "drift \(map.drift) ms")
        let beat = 60 / bpm
        var kick = (map.firstBeat - firstBar).truncatingRemainder(dividingBy: beat)
        if kick > beat / 2 { kick -= beat }
        if kick < -beat / 2 { kick += beat }
        XCTAssertLessThan(abs(kick), 0.008, "The grid should be on the kick's attack, and it's \(kick * 1000) ms off")
        var barError = (map.firstBar - firstBar).truncatingRemainder(dividingBy: 4 * beat)
        if barError > 2 * beat { barError -= 4 * beat }
        if barError < -2 * beat { barError += 4 * beat }
        XCTAssertLessThan(abs(barError), 0.02, "Bar lines should be on the 1, and they're \(barError / beat) beats off")

        func mapBar(_ n: Int) -> Int { Int(((firstBar + Double(n) * 4 * beat - map.firstBar) / (4 * beat)).rounded()) }
        XCTAssertFalse(map.on[Stem.melody.rawValue][mapBar(8)], "No melody yet")
        XCTAssertTrue(map.on[Stem.melody.rawValue][mapBar(20)], "Melody's in")
        XCTAssertLessThan(map.vocal[mapBar(20)], 0.25, "Nobody's singing yet")
        XCTAssertGreaterThan(map.vocal[mapBar(40)], 0.75, "Someone's singing")
        XCTAssertTrue(map.hasKick[mapBar(8)])
        XCTAssertTrue(map.boundaries.contains { abs($0 - mapBar(32)) <= 1 }, "The vocal coming in is a change: \(map.boundaries)")
    }

    func testTrackMapWontCallLooseDrumsSteady() throws {
        let map = try XCTUnwrap(TrackMapper.map(stems: clubStems(bpm: 124, firstBar: 0.5, bars: 40, jitter: 0.04)))
        XCTAssertFalse(map.isSteady, "Kicks up to 40 ms off a straight grid drift \(map.drift) ms")
    }

    @MainActor
    private func deckWithMap(source: GridSource, markers: [TempoMarker]? = nil) throws -> (Deck, TrackMap) {
        let stems = clubStems(bpm: 124, firstBar: 1.32, bars: 40)
        let map = try XCTUnwrap(TrackMapper.map(stems: stems))
        let deck = Deck(index: 0)
        var track = Track(id: UUID(), title: "T", artist: "", fileName: "t.mp3")
        track.bpm = 123.5
        track.firstBeat = 0.1
        track.tempoMarkers = markers
        track.gridSource = source
        deck.track = track
        return (deck, map)
    }

    @MainActor
    func testStemsCorrectAnAnalysedGridOnce() throws {
        let (deck, map) = try deckWithMap(source: .analysis, markers: [TempoMarker(time: 0.1, bpm: 123), TempoMarker(time: 9, bpm: 124)])
        deck.applyTrackMap(map)
        XCTAssertEqual(deck.track?.bpm, map.bpm)
        XCTAssertEqual(deck.track?.firstBeat, map.firstBar)
        XCTAssertNil(deck.track?.tempoMarkers, "A steady track doesn't keep a tempo map")
        XCTAssertEqual(deck.track?.gridSource, .drums)
        XCTAssertNotNil(deck.trackMap)
    }

    @MainActor
    func testStemsLeaveAGridSomeoneSet() throws {
        let (deck, map) = try deckWithMap(source: .person)
        deck.applyTrackMap(map)
        XCTAssertEqual(deck.track?.bpm, 123.5)
        XCTAssertEqual(deck.track?.firstBeat, 0.1)
        XCTAssertNotNil(deck.trackMap, "The map's still there for planning")
    }

    @MainActor
    func testEditingAGridMarksItAsSomeonesOwn() throws {
        let (deck, _) = try deckWithMap(source: .analysis)
        deck.shiftGrid(milliseconds: 10)
        XCTAssertEqual(deck.track?.gridSource, .person)
    }
}
