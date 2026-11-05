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

    /// The same music read 170 BPM, and 162.7 with 3 minutes of silence after it.
    func testSilenceAfterTheMusicLeavesItsTempoAlone() {
        for bpm in [170.0, 128.0, 96.0] {
            let music = Synth.track(bpm: bpm, firstBeat: 0.2, seconds: 60, chords: Synth.aMinor)
            let longer = PCM16Stereo(frames: music.frames + Int(Synth.sampleRate) * 180)
            memcpy(longer.data, music.data, music.frames * 4)
            let alone = TrackAnalyzer.analyze(music), withSilence = TrackAnalyzer.analyze(longer)
            XCTAssertEqual(withSilence.bpm, alone.bpm, accuracy: 0.05, "\(bpm)")
            XCTAssertEqual(withSilence.firstBeat, alone.firstBeat, accuracy: 0.01, "\(bpm)")
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

    func testTrackMapFindsTheKicksAndTheBars() throws {
        let bpm = 124.0, firstBar = 1.32
        let map = try XCTUnwrap(TrackMapper.map(stems: Synth.clubStems(bpm: bpm, firstBar: firstBar, bars: 64)))
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
        let map = try XCTUnwrap(TrackMapper.map(stems: Synth.clubStems(bpm: 124, firstBar: 0.5, bars: 40, jitter: 0.04)))
        XCTAssertFalse(map.isSteady, "Kicks up to 40 ms off a straight grid drift \(map.drift) ms")
    }

    @MainActor
    private func deckWithMap(source: GridSource, markers: [TempoMarker]? = nil) throws -> (Deck, TrackMap) {
        let stems = Synth.clubStems(bpm: 124, firstBar: 1.32, bars: 40)
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
    func testABigCorrectionSaysSoAndASmallOneDoesnt() throws {
        var said: [String] = []
        let (small, map) = try deckWithMap(source: .analysis)
        small.onMessage = { message, _ in said.append(message) }
        small.applyTrackMap(map)
        XCTAssertEqual(said, [], "123.5 to about 124 isn't worth mentioning")

        let (big, bigMap) = try deckWithMap(source: .analysis)
        big.track?.bpm = 178
        big.onMessage = { message, _ in said.append(message) }
        big.applyTrackMap(bigMap)
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said.first?.contains("BPM") == true, "\(said)")
    }

    /// Kicks on every beat and a hit every beat and a half, which is what read as two-thirds of the tempo.
    func testADottedRhythmDoesntPassForATempo() {
        let fps = 44100.0 / Double(TrackAnalyzer.tempoHop)
        let bpm = 154.0
        var onset = [Float](repeating: 0, count: Int(fps * 240))
        var beat = 0.0
        while Int(beat) < onset.count {
            onset[Int(beat)] = 1
            beat += fps * 60 / bpm
        }
        var dotted = 0.0
        while Int(dotted) < onset.count {
            onset[Int(dotted)] += 0.5
            dotted += fps * 60 / bpm * 1.5
        }
        XCTAssertEqual(TrackAnalyzer.detectTempo(onset: onset, sampleRate: 44100).bpm, bpm, accuracy: 0.1)
    }

    /// A track whose level hardly moves has its tempo only in the highs, and the phase still comes from the kicks.
    func testTheHighsCanSayTheTempoAndTheKicksStillSayTheBeat() {
        let fps = 44100.0 / Double(TrackAnalyzer.tempoHop)
        let bpm = 148.0
        let period = fps * 60 / bpm
        var kicks = [Float](repeating: 0, count: Int(fps * 240))
        var highs = kicks
        var index = 0
        while Int(Double(index) * period) + Int(period / 2) < kicks.count {
            // Weak kicks on the beat, and strong hats on the offbeat.
            kicks[Int(Double(index) * period)] = 0.3
            highs[Int(Double(index) * period + period / 2)] = 1
            index += 1
        }
        let found = TrackAnalyzer.detectTempo(onset: kicks, highs: highs, sampleRate: 44100)
        XCTAssertEqual(found.bpm, bpm, accuracy: 0.1)
        let beat = 60 / bpm
        let off = abs(found.firstBeat.truncatingRemainder(dividingBy: beat))
        XCTAssertLessThan(min(off, beat - off), 0.03, "On the kicks, not the hats")
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
