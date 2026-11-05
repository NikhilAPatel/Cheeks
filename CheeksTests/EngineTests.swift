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

    // MARK: Previews

    /// With no headphones it plays over the mix, for whoever's choosing a track. It was on the recording as well, 3 dB down.
    func testAPreviewOverTheMixIsHeardAndNotRecorded() throws {
        let a = DeckRenderer(sampleRate: sr), b = DeckRenderer(sampleRate: sr)
        var handles: [OpaquePointer?] = [a.handle, b.handle]
        let core = try XCTUnwrap(handles.withUnsafeMutableBufferPointer { cheeks_engine_create(sr, $0.baseAddress, 2) })
        defer { cheeks_engine_destroy(core) }
        cheeks_engine_set_master(core, 1, 0.8, 1, false)
        let pcm = stereo(sine(440, seconds: 2))
        cheeks_engine_set_preview(core, pcm.data, Int64(pcm.frames))
        cheeks_engine_set_preview_routing(core, 1, 0.7)
        cheeks_engine_set_preview_playing(core, true)
        cheeks_engine_set_recording(core, true)

        var left = [Float](repeating: 0, count: 256), right = left, heard: Float = 0
        for _ in 0..<40 {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in cheeks_engine_render(core, l.baseAddress!, r.baseAddress!, 256) }
            }
            heard = max(heard, left.map(abs).max() ?? 0)
        }
        XCTAssertGreaterThan(heard, 0.2, "It's on the output")

        var recordedLeft = [Float](repeating: 0, count: 256 * 40), recordedRight = recordedLeft
        let count = recordedLeft.withUnsafeMutableBufferPointer { l in
            recordedRight.withUnsafeMutableBufferPointer { r in cheeks_engine_read_recording(core, l.baseAddress!, r.baseAddress!, Int32(256 * 40)) }
        }
        XCTAssertGreaterThan(count, 0, "It's recording")
        XCTAssertEqual(recordedLeft.map(abs).max() ?? 1, 0, accuracy: 0.0001, "And there's nothing on it")
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

    /// Stems arriving while a deck plays must be inaudible: the audio carries on sample for sample.
    func testSwappingToStemsIsSeamless() throws {
        // Enough going on across the spectrum to give all four stems something.
        let n = Int(sr * 8)
        let music: [Float] = (0..<n).map { i in
            let t = Double(i) / sr
            return Float(0.3 * sin(2 * .pi * 80 * t) + 0.2 * sin(2 * .pi * 900 * t) + 0.1 * sin(2 * .pi * 8000 * t))
        }
        let mix = stereo(music)
        let stems = try FrequencySplitSeparator().separate(mix)

        func render(swapping: Bool, ratio: Double) -> [Float] {
            let r = DeckRenderer(sampleRate: sr)
            r.setSources([mix])
            r.setTempo(ratio: ratio, keyLock: true, keyShift: 0)
            r.isPlaying = true
            var out = r.renderOffline(frames: 22_050).left
            if swapping { r.setSources(stems) }
            out += r.renderOffline(frames: 22_050).left
            return out
        }

        // At normal speed it's read directly: the difference is only 16-bit rounding.
        let plain = render(swapping: false, ratio: 1), swapped = render(swapping: true, ratio: 1)
        let worst = Array(zip(plain, swapped))[22_050...].map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(worst, 0.002)

        // With the stretcher in the path, it mustn't be restarted, which would jolt its phases.
        let stretched = render(swapping: false, ratio: 1.05), stretchedSwap = render(swapping: true, ratio: 1.05)
        let drift = Array(zip(stretched, stretchedSwap))[23_000...].map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(drift, 0.02)
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

    func testTheChannelLeavesTheSignalUntouchedWithEverythingCentred() {
        // Square-ish, like a heavily limited master, where a turned phase shows up as bigger peaks.
        var source = sine(90, seconds: 2)
        for i in source.indices { source[i] = max(-0.6, min(0.6, source[i] * 4 + 0.3 * sine1k(i))) }
        let direct = DeckRenderer(sampleRate: sr), channel = DeckRenderer(sampleRate: sr)
        for r in [direct, channel] {
            r.setSources([stereo(source)])
            r.isPlaying = true
        }
        let a = direct.renderOffline(frames: Int(sr)).left, b = channel.renderChannelOffline(frames: Int(sr)).left
        let difference = zip(a, b).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(difference, 0.0001, "No phase turned, no peaks raised")
    }

    private func sine1k(_ i: Int) -> Float { Float(sin(2 * .pi * 1000 * Double(i) / sr)) }

    func testMovingAnEQKnobOffCentreDoesntClick() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(100, seconds: 3))])
        r.isPlaying = true
        _ = r.renderChannelOffline(frames: Int(sr / 2))
        r.setEQ(low: 0.9, mid: 1, high: 1)
        let out = r.renderChannelOffline(frames: Int(sr / 4)).left
        var worst: Float = 0
        for i in 1..<out.count { worst = max(worst, abs(out[i] - out[i - 1])) }
        // A 100 Hz sine at 0.5 moves by 0.007 per sample at most.
        XCTAssertLessThan(worst, 0.012)
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

    /// A kick, a bass note and a bright noisy part: a loud track's peaks are in its low end.
    private func musicLike(seconds: Double) -> [Float] {
        var seed: UInt32 = 12345
        return (0..<Int(seconds * sr)).map { i in
            let t = Double(i) / sr
            let beat = t.truncatingRemainder(dividingBy: 0.5)
            let kick = 0.5 * Float(exp(-beat * 18) * sin(2 * .pi * 60 * beat))
            let bass = 0.18 * Float(sin(2 * .pi * 55 * t))
            seed = seed &* 1664525 &+ 1013904223
            let noise = (Float(seed >> 16 & 0x7fff) / 16384 - 1) * 0.12
            let chord = 0.12 * Float(sin(2 * .pi * 440 * t) + sin(2 * .pi * 660 * t))
            return kick + bass + noise + chord
        }
    }

    func testBeatEffectsDontAddLevelAtTheirDefaultDepth() {
        let source = stereo(musicLike(seconds: 16))
        func measure(_ type: CheeksFXType?) -> (level: Float, peak: Float) {
            let r = DeckRenderer(sampleRate: sr)
            r.setSources([source])
            r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
            if let type { r.setFX(type, on: true, beats: 0.5, depth: 0.6, stemMask: 0xF) }
            r.isPlaying = true
            let out = r.renderOffline(frames: Int(sr * 14)).left[Int(sr * 4)...]
            return (rms(out), out.map(abs).max() ?? 0)
        }
        let dry = measure(nil)
        let effects: [(CheeksFXType, String)] = [(CheeksFXEcho, "echo"), (CheeksFXPingPong, "ping pong"), (CheeksFXSpiral, "spiral"), (CheeksFXReverb, "reverb"),
                                                 (CheeksFXFlanger, "flanger"), (CheeksFXPhaser, "phaser"), (CheeksFXFilterLFO, "filter"), (CheeksFXGate, "gate"), (CheeksFXCrush, "crush")]
        for (type, name) in effects {
            let wet = measure(type)
            print("FXGUARD: \(name) level \(String(format: "%+.1f", dB(wet.level) - dB(dry.level))) dB, peak \(String(format: "%+.1f", dB(wet.peak) - dB(dry.peak))) dB")
            // Repeats on this steady signal land on each other in a way real music's don't: on real
            // music all of these are within about 1 dB of dry (see LevelTests).
            let limit: Float = type == CheeksFXSpiral ? 5.5 : type == CheeksFXEcho || type == CheeksFXPingPong ? 4.5 : 1
            XCTAssertLessThan(dB(wet.level) - dB(dry.level), limit, "\(name) adds level")
            XCTAssertLessThan(dB(wet.peak) - dB(dry.peak), 3.2, "\(name) adds peak")
        }
    }

    func testTheFlangerMostlyLeavesTheLowsAlone() {
        // Doubling them is what took a loud track's kick into the red.
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(60, seconds: 8, level: 0.7))])
        r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        r.setFX(CheeksFXFlanger, on: true, beats: 0.5, depth: 0.6, stemMask: 0xF)
        r.isPlaying = true
        let out = r.renderOffline(frames: Int(sr * 6)).left[Int(sr * 2)...]
        let lift = dB(out.map(abs).max() ?? 0) - dB(0.7)
        print("FXGUARD: flanger on a bass note \(String(format: "%+.1f", lift)) dB")
        XCTAssertLessThan(abs(lift), 2, "A bass note stays about where it was")
    }

    func testAnEchoOutsTailIsLouderThanAnEchoReleasedOverTheTrack() {
        // The track stops at 4 s either way, so all that's left to measure is the tail.
        let source = stereo(sine(440, seconds: 4) + [Float](repeating: 0, count: Int(sr * 4)))
        func tail(cut: Bool) -> Float {
            let r = DeckRenderer(sampleRate: sr)
            r.setSources([source])
            r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
            r.setFXLink(0, type: CheeksFXEcho, on: true, beats: 1, depth: 0.7)
            r.isPlaying = true
            r.releaseFX(link: 0, atBeat: 8)
            if cut { r.cutSource(atBeat: 8) }
            return rms(r.renderOffline(frames: Int(sr * 5)).left[Int(sr * 4.05)...])
        }
        let difference = dB(tail(cut: true)) - dB(tail(cut: false))
        print("FXGUARD: echo out tail \(String(format: "%+.1f", difference)) dB")
        XCTAssertGreaterThan(difference, 3, "With nothing else playing there's no level to leave room for")
    }

    func testAnEffectLeavingTheChainDoesntStep() {
        for type in [CheeksFXPhaser, CheeksFXFlanger, CheeksFXFilterLFO] {
            let r = DeckRenderer(sampleRate: sr)
            r.setSources([stereo(sine(220, seconds: 6))])
            r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
            r.setFX(type, on: true, beats: 1, depth: 0.6, stemMask: 0xF)
            r.isPlaying = true
            _ = r.renderOffline(frames: Int(sr))
            r.setFX(type, on: false, beats: 1, depth: 0.6, stemMask: 0xF)
            let out = r.renderOffline(frames: Int(sr))
            XCTAssertLessThan(largestStep(out.left[...]), 0.14, "\(type)")
        }
    }

    func testAReverseLoopWrapDoesNotClick() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(997, seconds: 4))])
        r.setLoop(start: 10_000, end: 20_037, active: true)
        r.playhead = 15_000
        r.isPlaying = true
        r.reverse = true
        let out = r.renderOffline(frames: 80_000)
        XCTAssertEqual(r.playhead, 15_000, accuracy: 10_100)
        XCTAssertGreaterThanOrEqual(r.playhead, 10_000)
        XCTAssertLessThan(largestStep(out.left[1000...]), 0.14)
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

    /// The most a mix can ask of the render thread: stems stretched on both decks, three effects
    /// chained on each with both kinds of tail going, and a Color FX on each channel.
    @MainActor
    func testRealtimeHeadroomWithEverythingOn() {
        let library = Library()
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        for (i, deck) in dj.decks.enumerated() {
            let stems = (0..<4).map { s -> PCM16Stereo in
                PCM16Stereo(left: sine(110 * Double(s + 1 + i), seconds: 30, level: 0.2), right: sine(111 * Double(s + 1 + i), seconds: 30, level: 0.2))
            }
            deck.renderer.setSources(stems)
            deck.renderer.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
            deck.renderer.setTempo(ratio: 1.04, keyLock: true, keyShift: 0)
            deck.renderer.setFXLink(0, type: CheeksFXEcho, on: true, beats: 1, depth: 0.7)
            deck.renderer.setFXLink(1, type: CheeksFXReverb, on: true, beats: 1, depth: 0.7)
            deck.renderer.setFXLink(2, type: CheeksFXFlanger, on: true, beats: 1, depth: 0.7)
            deck.renderer.setColor(i == 0 ? CheeksColorDubEcho : CheeksColorPitch, amount: 0.7)
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
        print(String(format: "DSP: average %.1f%% of realtime, worst callback %.1f%% (everything on: stems stretched, 3 FX and a Color FX per deck)",
                     used / (Double(blocks) * budget) * 100, worst / budget * 100))
        XCTAssertLessThan(used / (Double(blocks) * budget), 0.5)
    }

    /// The audio thread doesn't wait for a release, so it can come in partway through a block. That
    /// used to let the return point follow the deck for the rest of the block, and the jump back then
    /// went nowhere: in the hands-on test, about one roll in 30 lost the time it was held for.
    func testReleasingSlipDuringARenderStillJumpsBack() {
        final class Renders: @unchecked Sendable {
            private let lock = NSLock()
            private var done = 0
            private var stopped = false
            var shouldStop: Bool { lock.withLock { stopped } }
            func stop() { lock.withLock { stopped = true } }
            func finishedOne() { lock.withLock { done += 1 } }
            /// Until a whole render has started and finished since now, so it's seen what was just sent.
            func waitForOneFromHere() {
                let target = lock.withLock { done } + 2
                while lock.withLock({ done }) < target { usleep(20) }
            }
        }
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([PCM16Stereo(frames: Int(sr) * 120)])
        r.isPlaying = true
        let renders = Renders()
        let finished = DispatchSemaphore(value: 0)
        // Rendering flat out, so a release from here nearly always lands in the middle of a block.
        Thread.detachNewThread {
            while !renders.shouldStop {
                _ = r.renderOffline(frames: 512)
                renders.finishedOne()
            }
            finished.signal()
        }

        let held = 50_000.0, trials = 300
        var lost = 0
        for _ in 0..<trials {
            r.playhead = 10_000
            renders.waitForOneFromHere()
            let start = r.playhead
            r.engageSlip()
            r.setLoop(start: start, end: start + 2_000, active: true)
            renders.waitForOneFromHere()
            while r.slipPlayhead < start + held { usleep(20) }
            r.loopActive = false
            r.releaseSlip()
            renders.waitForOneFromHere()
            // Held inside the loop, it can't have got this far by playing on from there.
            if r.playhead < start + held { lost += 1 }
        }
        renders.stop()
        finished.wait()
        XCTAssertEqual(lost, 0, "\(lost) of \(trials) releases didn't jump back")
    }

    func testOnePadLetGoAndAnotherPressedInOneBlockStillGoesBack() {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([PCM16Stereo(frames: Int(sr) * 10)])
        r.isPlaying = true
        _ = r.renderOffline(frames: 2048)
        let start = r.playhead
        r.engageSlip()
        r.setLoop(start: start, end: start + 1_000, active: true)
        _ = r.renderOffline(frames: Int(sr))
        let back = r.slipPlayhead
        XCTAssertEqual(back, start + sr, accuracy: 1)

        r.loopActive = false
        r.releaseSlip()
        r.engageSlip()
        _ = r.renderOffline(frames: 512)
        XCTAssertEqual(r.playhead, back + 512, accuracy: 1, "It came back before the next one started")
        XCTAssertEqual(r.slipPlayhead, back + 512, accuracy: 1)
        XCTAssertTrue(r.slipEngaged)
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

    // MARK: Reading both decks at once

    @MainActor
    func testBothDecksPositionsComeFromTheSameMoment() async {
        let dj = DJEngine(library: Library())
        dj.stopRealtimeForTesting()
        for deck in dj.decks {
            deck.renderer.setSources([PCM16Stereo(frames: Int(sr * 120))])
            deck.renderer.playhead = 1000
            deck.renderer.isPlaying = true
        }
        // Rendering on another thread, as the audio callback does. Identical decks are always level,
        // so any difference between them is the read landing between two updates.
        let core = dj.coreForTesting
        let stop = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        stop.pointee = 0
        defer { stop.deallocate() }
        let rendering = Task.detached(priority: .high) {
            var left = [Float](repeating: 0, count: 256), right = left
            while OSAtomicAdd32(0, stop) == 0 {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        cheeks_engine_render(core, l.baseAddress!, r.baseAddress!, 256)
                    }
                }
            }
        }
        var worstTogether = 0.0, worstApart = 0.0
        for _ in 0..<400_000 {
            let together = dj.positions
            worstTogether = max(worstTogether, abs(together[0] - together[1]))
            worstApart = max(worstApart, abs(dj.decks[0].renderer.playhead - dj.decks[1].renderer.playhead))
        }
        OSAtomicAdd32(1, stop)
        await rendering.value
        print("DSP: reading decks one at a time was \(Int(worstApart)) frames apart at worst, reading together \(Int(worstTogether))")
        XCTAssertEqual(worstTogether, 0, "Positions read together must be from one moment")
        XCTAssertGreaterThan(dj.positions[0], 1000, "It did render")
    }

    // MARK: FX chain

    /// A steady tone on a 120 BPM grid, playing.
    private func playingRenderer(_ seconds: Double = 8) -> DeckRenderer {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(sine(440, seconds: seconds))])
        r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        r.isPlaying = true
        return r
    }

    func testTwoEffectsRunTogetherAsAChain() {
        // A gate on its own leaves gaps; an echo on its own doesn't. Chained, the echo runs after the
        // gate, so it fills the gaps in.
        func gapLevel(gate: Bool, echo: Bool) -> Float {
            let r = playingRenderer()
            if gate { r.setFXLink(0, type: CheeksFXGate, on: true, beats: 1, depth: 1) }
            if echo { r.setFXLink(1, type: CheeksFXEcho, on: true, beats: 0.75, depth: 0.8) }
            let out = r.renderOffline(frames: Int(sr * 4)).left
            // The second half of a beat is where the gate closes.
            let beat = Int(sr / 2)
            return rms(out[(beat * 6 + beat * 3 / 4)..<(beat * 7)])
        }
        let gateOnly = gapLevel(gate: true, echo: false)
        let both = gapLevel(gate: true, echo: true)
        XCTAssertLessThan(gateOnly, 0.02, "The gate closes on its own")
        XCTAssertGreaterThan(both, 0.05, "With the echo after it, the repeats fill the gap: the two are really in series")
    }

    func testAQuantizedReleaseWaitsForItsBeat() {
        let r = playingRenderer()
        r.setFXLink(0, type: CheeksFXGate, on: true, beats: 0.5, depth: 1)
        // The gate's going until beat 4 (2 s), then stops, and from there it's a steady tone.
        r.releaseFX(link: 0, atBeat: 4)
        let out = r.renderOffline(frames: Int(sr * 3)).left
        let eighth = Int(sr / 8)
        var closedBefore = false
        for i in stride(from: Int(sr * 1), to: Int(sr * 1.9), by: eighth / 4) where rms(out[i..<(i + eighth / 4)]) < 0.02 { closedBefore = true }
        XCTAssertTrue(closedBefore, "The gate is still working before the beat")
        for i in stride(from: Int(sr * 2.1), to: Int(sr * 2.9), by: eighth / 4) {
            XCTAssertGreaterThan(rms(out[i..<(i + eighth / 4)]), 0.2, "The gate has let go after it")
        }
    }

    func testAQuantizedReleaseStillHappensInALoopThatNeverReachesItsBeat() {
        let r = playingRenderer(20)
        r.setLoop(start: sr, end: sr + 2000, active: true) // far shorter than a beat
        r.playhead = sr
        r.setFXLink(0, type: CheeksFXGate, on: true, beats: 0.25, depth: 1)
        r.releaseFX(link: 0, atBeat: 400) // a beat this loop will never get to
        _ = r.renderOffline(frames: Int(sr * 3.5))
        let out = r.renderOffline(frames: Int(sr * 1)).left
        // Without the gate, the loop's tone never drops away.
        var quietest: Float = 1
        for i in stride(from: 0, to: out.count - 1024, by: 512) { quietest = min(quietest, rms(out[i..<(i + 1024)])) }
        XCTAssertGreaterThan(quietest, 0.1, "The effect gave up waiting and let go")
    }

    func testEchoOutCutsTheTrackAndLeavesTheTail() {
        let r = playingRenderer(14)
        r.setFXLink(0, type: CheeksFXEcho, on: true, beats: 0.5, depth: 0.8)
        r.releaseFX(link: 0, atBeat: 4)
        r.cutSource(atBeat: 4)
        XCTAssertTrue(r.sourceCut)
        let before = r.renderOffline(frames: Int(sr * 2)).left
        XCTAssertGreaterThan(rms(before[(before.count - 2000)...]), 0.2)
        let after = r.renderOffline(frames: Int(sr * 1)).left
        let tail = rms(after[2000..<12000])
        XCTAssertGreaterThan(tail, 0.02, "The repeats ring on")
        let later = r.renderOffline(frames: Int(sr * 6)).left
        XCTAssertLessThan(rms(later[(later.count - 4000)...]), tail / 4, "They die away, with no track under them")
        r.restoreSource()
        XCTAssertFalse(r.sourceCut)
        let back = r.renderOffline(frames: 8192).left
        XCTAssertGreaterThan(rms(back[4000...]), 0.2, "And the track comes back when asked")
    }

    // MARK: Color FX

    private func channel(_ type: CheeksColorType, amount: Float, source: [Float]? = nil) -> [Float] {
        let r = DeckRenderer(sampleRate: sr)
        r.setSources([stereo(source ?? sine(440, seconds: 4))])
        r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        r.isPlaying = true
        r.setColor(type, amount: amount)
        return r.renderChannelOffline(frames: Int(sr * 2)).left
    }

    func testColorEffectsAtTheCentreLeaveTheSoundAlone() {
        let dry = channel(CheeksColorFilter, amount: 0)
        for type in [CheeksColorDubEcho, CheeksColorSpace, CheeksColorNoise, CheeksColorCrush, CheeksColorPitch] {
            let out = channel(type, amount: 0)
            for i in stride(from: 0, to: out.count, by: 997) { XCTAssertEqual(out[i], dry[i], accuracy: 0.0001, "\(type)") }
        }
    }

    func testEveryColorEffectChangesTheSoundAndStaysBounded() {
        let dry = channel(CheeksColorFilter, amount: 0)
        for type in [CheeksColorDubEcho, CheeksColorSpace, CheeksColorNoise, CheeksColorCrush, CheeksColorPitch] {
            for amount: Float in [-1, -0.5, 0.5, 1] {
                let out = channel(type, amount: amount)
                let peak = out.map(abs).max() ?? 0
                XCTAssertLessThan(peak, 3, "\(type) at \(amount) ran away")
                XCTAssertFalse(out.contains { !$0.isFinite }, "\(type) at \(amount) went bad")
                var difference: Float = 0
                for i in Int(sr)..<out.count { difference += abs(out[i] - dry[i]) }
                XCTAssertGreaterThan(difference / Float(out.count), 0.005, "\(type) at \(amount) did nothing")
            }
        }
    }

    func testDubEchoRingsOutAfterTheKnobComesBack() {
        let r = DeckRenderer(sampleRate: sr)
        var source = sine(440, seconds: 6)
        for i in Int(sr * 2)..<source.count { source[i] = 0 } // the track goes silent
        r.setSources([stereo(source)])
        r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        r.isPlaying = true
        r.setColor(CheeksColorDubEcho, amount: -0.8)
        _ = r.renderChannelOffline(frames: Int(sr * 2))
        r.setColor(CheeksColorDubEcho, amount: 0)
        let tail = r.renderChannelOffline(frames: Int(sr * 1)).left
        XCTAssertGreaterThan(rms(tail[...]), 0.01, "The repeats keep going with the knob back at the centre")
    }

    func testDubEchoTailLastsAFewSecondsAndThenStops() {
        let r = DeckRenderer(sampleRate: sr)
        var source = sine(440, seconds: 20)
        for i in Int(sr * 2)..<source.count { source[i] = 0 }
        r.setSources([stereo(source)])
        r.setGrid(beatFrames: sr / 2, firstBeatFrame: 0)
        r.isPlaying = true
        r.setColor(CheeksColorDubEcho, amount: -0.8)
        _ = r.renderChannelOffline(frames: Int(sr * 2))
        r.setColor(CheeksColorDubEcho, amount: 0)
        var levels: [Float] = []
        for _ in 0..<14 { levels.append(rms(r.renderChannelOffline(frames: Int(sr)).left[...])) }
        print("DSP: dub tail per second after the knob comes back: \(levels.map { String(format: "%.0f", 20 * log10(max($0, 1e-6))) }.joined(separator: " ")) dB")
        XCTAssertGreaterThan(levels[2], 0.003, "Still clearly there 3 s later")
        XCTAssertLessThan(levels[13], 0.0003, "and gone in the end")
    }

    func testPitchEffectReallyMovesThePitch() {
        // An octave up should put most of a 440 Hz tone's energy near 880 Hz.
        func power(_ x: ArraySlice<Float>, _ frequency: Double) -> Float {
            var re: Float = 0, im: Float = 0
            for (k, v) in x.enumerated() {
                let phase = 2 * Double.pi * frequency * Double(k) / sr
                re += v * Float(cos(phase))
                im += v * Float(sin(phase))
            }
            return (re * re + im * im) / Float(x.count * x.count)
        }
        let up = channel(CheeksColorPitch, amount: 1)
        let slice = up[Int(sr)..<Int(sr * 1.5)]
        XCTAssertGreaterThan(power(slice, 880), power(slice, 440) * 3)
        let down = channel(CheeksColorPitch, amount: -1)
        let lower = down[Int(sr)..<Int(sr * 1.5)]
        XCTAssertGreaterThan(power(lower, 220), power(lower, 440) * 3)
    }
}
