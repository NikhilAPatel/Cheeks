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
}
