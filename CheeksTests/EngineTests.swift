import AVFoundation
import XCTest
@testable import Cheeks

/// The realtime core rendered offline: things you'd otherwise only find out by ear.
final class EngineTests: XCTestCase {
    private let sr = AudioConfig.sampleRate

    private func stereo(_ x: [Float]) -> PCM16Stereo { PCM16Stereo(left: x, right: x) }

    private func sine(_ frequency: Double, seconds: Double, level: Float = 0.5) -> [Float] {
        (0..<Int(seconds * sr)).map { level * Float(sin(2 * .pi * frequency * Double($0) / sr)) }
    }

    private func rms(_ x: ArraySlice<Float>) -> Float {
        (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot()
    }

    private func dB(_ x: Float) -> Float { 20 * log10(max(x, 1e-7)) }

    /// A signal with no jumps of its own: any big sample-to-sample step in the output is a click.
    private func largestStep(_ x: ArraySlice<Float>) -> Float {
        var worst: Float = 0
        var previous = x.first ?? 0
        for v in x {
            worst = max(worst, abs(v - previous))
            previous = v
        }
        return worst
    }

    // MARK: De-clicking

    func testLoopWrapDoesNotClick() {
        let r = DeckRenderer(sampleRate: sr)
        // 997 Hz has a sample-to-sample step of about 0.07 at this level; a loop at an arbitrary
        // point would otherwise step by up to 2× the amplitude.
        r.setSources([stereo(sine(997, seconds: 4))])
        r.setLoop(start: 10_000, end: 20_037, active: true)
        r.playhead = 15_000
        r.isPlaying = true
        let out = r.renderOffline(frames: 80_000)
        XCTAssertLessThan(largestStep(out.left[1000...]), 0.14)
    }

    func testJumpAndPauseDoNotClick() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(997, seconds: 4))])
        r.isPlaying = true
        var all = r.renderOffline(frames: 3000).left
        r.playhead = 80_123
        all += r.renderOffline(frames: 3000).left
        r.isPlaying = false
        all += r.renderOffline(frames: 3000).left
        r.isPlaying = true
        all += r.renderOffline(frames: 3000).left
        XCTAssertLessThan(largestStep(all[256...]), 0.14)
    }

    // MARK: Stretcher: position means "what's being heard"

    /// A click track at known frames, stretched with key lock on: each click must come out when
    /// `playhead` reaches it, proving the feed-ahead cancels the stretcher's latency.
    func testStretchedOutputLinesUpWithPlayhead() {
        let r = DeckRenderer(sampleRate: sr)
        var x = [Float](repeating: 0, count: Int(sr * 20))
        let clickEvery = Int(sr / 2)
        for c in stride(from: clickEvery, to: x.count - 512, by: clickEvery) {
            for k in 0..<256 { x[c + k] = 0.8 * Float(sin(2 * .pi * 2000 * Double(k) / sr)) * Float(1 - Double(k) / 256) }
        }
        r.setSources([stereo(x)])
        r.setTempo(ratio: 1.06, keyLock: true, keyShift: 0)
        r.isPlaying = true
        let block = 256
        var heardAtPeak: [(frame: Double, level: Float)] = []
        for _ in 0..<(Int(sr * 8) / block) {
            let before = r.playhead
            let out = r.renderOffline(frames: block)
            XCTAssertTrue(r.isStretching)
            let level = out.left.map(abs).max() ?? 0
            heardAtPeak.append((before + 0.5 * Double(block) * 1.06, level))
        }
        var errors: [Double] = []
        for c in stride(from: clickEvery * 2, to: Int(sr * 7), by: clickEvery) {
            let near = heardAtPeak.filter { abs($0.frame - Double(c)) < sr * 0.1 }
            guard let loudest = near.max(by: { $0.level < $1.level }) else { continue }
            errors.append(abs(loudest.frame - Double(c)))
        }
        XCTAssertFalse(errors.isEmpty)
        // Within a few blocks, i.e. the 125 ms latency really is gone.
        XCTAssertLessThan(errors.max() ?? 1e9, 1100)
    }

    func testKeyLockHoldsPitch() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(440, seconds: 10))])
        r.setTempo(ratio: 1.08, keyLock: true, keyShift: 0)
        r.isPlaying = true
        _ = r.renderOffline(frames: 22_050)
        let out = r.renderOffline(frames: 44_100).left
        XCTAssertEqual(dominantFrequency(out), 440, accuracy: 4)
    }

    func testKeyShiftMovesPitchBySemitones() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(440, seconds: 10))])
        r.setTempo(ratio: 1, keyLock: true, keyShift: 3)
        r.isPlaying = true
        _ = r.renderOffline(frames: 22_050)
        let out = r.renderOffline(frames: 44_100).left
        XCTAssertEqual(dominantFrequency(out), 440 * pow(2, 3.0 / 12), accuracy: 5)
    }

    func testVarispeedMovesPitchWithTempo() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(440, seconds: 10))])
        r.setTempo(ratio: 1.1, keyLock: false, keyShift: 0)
        r.isPlaying = true
        _ = r.renderOffline(frames: 2205)
        XCTAssertFalse(r.isStretching)
        let out = r.renderOffline(frames: 44_100).left
        XCTAssertEqual(dominantFrequency(out), 484, accuracy: 3)
    }

    func testHotCueIsHeardImmediatelyWithKeyLock() {
        let r = DeckRenderer(sampleRate: sr)
        // Silence, then a loud tone from 5 s on: after jumping there it must be audible at once.
        var x = [Float](repeating: 0, count: Int(sr * 10))
        for i in Int(sr * 5)..<Int(sr * 9) { x[i] = 0.7 * Float(sin(2 * .pi * 440 * Double(i) / sr)) }
        r.setSources([stereo(x)])
        r.setTempo(ratio: 1.05, keyLock: true, keyShift: 0)
        r.isPlaying = true
        _ = r.renderOffline(frames: 22_050)
        r.playhead = sr * 5
        let out = r.renderOffline(frames: 1024).left
        XCTAssertGreaterThan(rms(out[512..<1024]), 0.3, "A jump must be heard within a few milliseconds, not after the stretcher's latency")
    }

    func testPlayheadAdvancesAtTempo() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(100, seconds: 30))])
        r.setTempo(ratio: 1.03, keyLock: true, keyShift: 0)
        r.isPlaying = true
        _ = r.renderOffline(frames: 44_100)
        let start = r.playhead
        _ = r.renderOffline(frames: 44_100)
        XCTAssertEqual(r.playhead - start, 44_100 * 1.03, accuracy: 2)
    }

    // MARK: Isolator EQ and filter

    private func channelLevel(frequency: Double, low: Float = 1, mid: Float = 1, high: Float = 1, filter: Float = 0) -> Float {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(frequency, seconds: 2))])
        r.setEQ(low: low, mid: mid, high: high)
        r.setFilter(filter)
        r.isPlaying = true
        _ = r.renderChannelOffline(frames: 22_050)
        return rms(r.renderChannelOffline(frames: 22_050).left[...])
    }

    func testIsolatorIsFlatWhenAllBandsAreUp() {
        let reference = 0.5 / Float(2).squareRoot()
        for f in [40.0, 220, 800, 2600, 9000] {
            XCTAssertEqual(dB(channelLevel(frequency: f) / reference), 0, accuracy: 0.1, "\(f) Hz")
        }
    }

    func testIsolatorKillsEachBand() {
        let reference = 0.5 / Float(2).squareRoot()
        XCTAssertLessThan(dB(channelLevel(frequency: 50, low: 0) / reference), -40)
        XCTAssertLessThan(dB(channelLevel(frequency: 800, mid: 0) / reference), -22)
        XCTAssertLessThan(dB(channelLevel(frequency: 11_000, high: 0) / reference), -40)
    }

    func testFilterSweepsBothWays() {
        let reference = 0.5 / Float(2).squareRoot()
        XCTAssertLessThan(dB(channelLevel(frequency: 5000, filter: -0.8) / reference), -30)
        XCTAssertLessThan(dB(channelLevel(frequency: 60, filter: 0.8) / reference), -30)
        XCTAssertEqual(dB(channelLevel(frequency: 800, filter: 0) / reference), 0, accuracy: 0.1)
    }

    // MARK: Stems and FX

    func testEchoOnOneStemLeavesTheOthersDry() {
        let r = DeckRenderer(sampleRate: sr)
        // Stem 0 is a burst, the rest silent; stem 1 is a quiet steady tone.
        let n = Int(sr * 6)
        let burst = PCM16Stereo(frames: n), tone = PCM16Stereo(frames: n), silent = PCM16Stereo(frames: n), silent2 = PCM16Stereo(frames: n)
        for i in 0..<Int(sr * 0.05) {
            let v = Int16(8000 * sin(2 * .pi * 1000 * Double(i) / sr))
            burst.data[i * 2] = v
            burst.data[i * 2 + 1] = v
        }
        r.setSources([burst, tone, silent, silent2])
        r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        r.setFX(CheeksFXEcho, on: true, beats: 1, depth: 0.7, stemMask: 1)
        r.isPlaying = true
        let out = r.renderOffline(frames: Int(sr)).left
        // The first echo arrives one beat (0.5 s) later.
        XCTAssertGreaterThan(rms(out[Int(sr * 0.5)..<Int(sr * 0.55)]), 0.02)

        // Same again with the FX bus on a different stem: no echo.
        let dry = DeckRenderer(sampleRate: sr)
        dry.setSources([burst, tone, silent, silent2])
        dry.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        dry.setFX(CheeksFXEcho, on: true, beats: 1, depth: 0.7, stemMask: 2)
        dry.isPlaying = true
        let dryOut = dry.renderOffline(frames: Int(sr)).left
        XCTAssertLessThan(rms(dryOut[Int(sr * 0.5)..<Int(sr * 0.55)]), 0.001)
    }

    func testEchoTailRingsOutAfterRelease() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(1000, seconds: 8))])
        r.setGrid(beatFrames: sr / 4, firstBeatFrame: 0)
        r.setFX(CheeksFXEcho, on: true, beats: 1, depth: 0.8, stemMask: 0xF)
        r.isPlaying = true
        _ = r.renderOffline(frames: Int(sr))
        r.setFX(CheeksFXEcho, on: false, beats: 1, depth: 0.8, stemMask: 0xF)
        r.isPlaying = false
        _ = r.renderOffline(frames: 2048)
        let tail = r.renderOffline(frames: 4096).left
        XCTAssertGreaterThan(rms(tail[...]), 0.01)
    }

    func testEveryEffectStaysFiniteAndBounded() {
        let types: [CheeksFXType] = [CheeksFXEcho, CheeksFXPingPong, CheeksFXReverb, CheeksFXFlanger, CheeksFXPhaser,
                                     CheeksFXFilterLFO, CheeksFXGate, CheeksFXCrush, CheeksFXSpiral]
        for type in types {
            let r = DeckRenderer(sampleRate: sr)
            r.setSources([stereo(sine(220, seconds: 12, level: 0.9))])
            r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
            r.setFX(type, on: true, beats: 1, depth: 1, stemMask: 0xF)
            r.isPlaying = true
            let out = r.renderOffline(frames: Int(sr * 10)).left
            XCTAssertTrue(out.allSatisfy(\.isFinite), "\(type)")
            XCTAssertLessThan(out.map(abs).max() ?? 0, 40, "\(type) ran away")
        }
    }

    // MARK: Whole mix

    @MainActor
    func testLimiterHoldsTheMasterBelowClipping() {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        for deck in dj.decks {
            deck.renderer.setSources([stereo(sine(100, seconds: 4, level: 0.95))])
            deck.trim = 1 // +12 dB
            deck.fader = 1
            deck.renderer.isPlaying = true
        }
        dj.masterVolume = 1
        let out = dj.renderOffline(frames: 88_200).left
        XCTAssertLessThanOrEqual(out.map(abs).max() ?? 9, 1.0)
        XCTAssertGreaterThan(dj.limiterReduction, 0)
    }

    @MainActor
    func testSyncedDecksStayLockedForMinutes() {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        let a = dj.decks[0], b = dj.decks[1]
        let silent = PCM16Stereo(frames: Int(sr * 300))
        a.renderer.setSources([silent])
        b.renderer.setSources([silent])
        a.track = Track(id: UUID(), title: "A", artist: "", fileName: "none", bpm: 128, firstBeat: 0.1)
        b.track = Track(id: UUID(), title: "B", artist: "", fileName: "none", bpm: 123.45, firstBeat: 0.37)
        a.seek(to: 5)
        b.seek(to: 11)
        a.play()
        b.play()
        dj.setMaster(a)
        dj.toggleSync(b)
        var worst = 0.0
        // 3 minutes of audio, in 256-frame callbacks. The main thread's sync check runs at 30 Hz,
        // so give the follower a moment after sync engages, then call it as often as the app does.
        for block in 0..<(Int(sr * 180) / 256) {
            _ = dj.renderOffline(frames: 256)
            if block % 6 == 0 { dj.tickForTesting() }
            if block > Int(sr * 2) / 256 && block % 40 == 0 {
                worst = max(worst, abs(b.phaseOffset(to: a)))
            }
        }
        // 1/1000 of a beat at 128 BPM is under half a millisecond: far too small to hear.
        XCTAssertLessThan(worst, 1.0 / 1000)
    }

    /// Recording must capture exactly what's on the program bus, end to end: ring, drain, file, conversion.
    @MainActor
    func testRecordingCapturesTheMix() async throws {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        let before = Set(Recordings.list())
        dj.recordingFormat = .wav
        dj.decks[0].renderer.setSources([stereo(sine(440, seconds: 6, level: 0.4))])
        dj.decks[0].fader = 1
        dj.decks[0].renderer.isPlaying = true
        _ = dj.renderOffline(frames: 2048)
        dj.toggleRecording()
        XCTAssertTrue(dj.isRecording)
        let seconds = 3
        for _ in 0..<(seconds * 44_100 / 256) {
            _ = dj.renderOffline(frames: 256)
            // The drain runs on its own queue; rendering this fast would outrun it without a breather.
            try await Task.sleep(for: .microseconds(200))
        }
        dj.toggleRecording()
        var saved: URL?
        for _ in 0..<100 where saved == nil {
            try await Task.sleep(for: .milliseconds(100))
            saved = Set(Recordings.list()).subtracting(before).first
        }
        let url = try XCTUnwrap(saved, "The recording never appeared")
        defer {
            try? FileManager.default.removeItem(at: url)
            for companion in Recordings.companionFiles(for: url) { try? FileManager.default.removeItem(at: companion) }
        }
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, Double(seconds), accuracy: 0.05)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        XCTAssertEqual(dominantFrequency(samples), 440, accuracy: 1)
        // Fader at full: the tone comes through the limiter at its own level.
        XCTAssertEqual(rms(samples[1000...]), 0.4 / Float(2).squareRoot(), accuracy: 0.03)
    }

    // MARK: Performance

    /// The heaviest realistic load: both decks on four stems, stretched, with an echo and a reverb
    /// running. Prints how much of the available time one audio callback takes on this machine.
    @MainActor
    func testRealtimeHeadroom() {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        let n = Int(sr * 30)
        for (i, deck) in dj.decks.enumerated() {
            let stems = (0..<4).map { s -> PCM16Stereo in
                PCM16Stereo(left: sine(110 * Double(s + 1 + i), seconds: 30, level: 0.2), right: sine(111 * Double(s + 1 + i), seconds: 30, level: 0.2))
            }
            XCTAssertEqual(stems[0].frames, n)
            deck.renderer.setSources(stems)
            deck.renderer.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
            deck.renderer.setTempo(ratio: 1.04, keyLock: true, keyShift: 0)
            deck.renderer.setFX(i == 0 ? CheeksFXEcho : CheeksFXReverb, on: true, beats: 1, depth: 0.7, stemMask: 0xF)
            deck.renderer.isPlaying = true
        }
        dj.decks.forEach { $0.fader = 1 }
        let block = 256, blocks = Int(sr * 10) / block
        let start = CFAbsoluteTimeGetCurrent()
        var worst = 0.0
        for _ in 0..<blocks {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = dj.renderOffline(frames: block)
            worst = max(worst, CFAbsoluteTimeGetCurrent() - t0)
        }
        let used = CFAbsoluteTimeGetCurrent() - start
        let budget = Double(block) / sr
        print(String(format: "DSP: average %.1f%% of realtime, worst callback %.1f%% (2 decks, 4 stems each, stretched, FX on)",
                     used / (Double(blocks) * budget) * 100, worst / budget * 100))
        XCTAssertLessThan(used / (Double(blocks) * budget), 0.5)
    }

    // MARK: Helpers

    /// Estimates pitch from upward zero crossings, which is plenty for a single steady tone.
    private func dominantFrequency(_ x: [Float]) -> Double {
        var crossings: [Double] = []
        for i in 1..<x.count where x[i - 1] < 0 && x[i] >= 0 {
            crossings.append(Double(i - 1) + Double(-x[i - 1] / (x[i] - x[i - 1])))
        }
        guard crossings.count > 2 else { return 0 }
        return Double(crossings.count - 1) * sr / (crossings.last! - crossings.first!)
    }
}
