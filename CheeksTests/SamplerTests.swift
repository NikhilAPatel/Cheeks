import XCTest
@testable import Cheeks

@MainActor
final class SamplerTests: XCTestCase {
    private let sr = AudioConfig.sampleRate

    /// An engine with nothing running, a silent deck, and a clean set of pads.
    private func makeEngine() -> DJEngine {
        let dj = DJEngine(library: Library())
        dj.stopRealtimeForTesting()
        for slot in 0..<8 where dj.sampler.hasOwnSound(slot) { dj.sampler.restoreOriginal(slot) }
        dj.sampler.quantize = false
        dj.sampler.level = 1
        dj.masterVolume = 1
        for slot in 0..<8 { dj.sampler.setMode(.oneShot, slot: slot) }
        return dj
    }

    /// A constant level, so the first non-zero sample is exactly where it started.
    private func dc(_ seconds: Double, level: Float = 0.3) -> PCM16Stereo {
        let n = Int(seconds * sr)
        let x = [Float](repeating: level, count: n)
        return PCM16Stereo(left: x, right: x)
    }

    private func loadSound(_ pcm: PCM16Stereo, on dj: DJEngine, slot: Int = 0, mode: Sampler.Mode = .oneShot) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sampler-\(UUID().uuidString).caf")
        try pcm.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try AudioDecoder.decode(url: url, sampleRate: sr)
        XCTAssertEqual(decoded.frames, pcm.frames)
        let deck = dj.decks[0]
        deck.renderer.setSources([decoded])
        deck.renderer.setLoop(start: 0, end: Double(decoded.frames), active: false)
        XCTAssertNil(dj.sampler.grabLoop(from: deck, slot: slot))
        deck.renderer.setSources([])
        deck.renderer.setLoop(start: 0, end: 0, active: false)
        dj.sampler.setMode(mode, slot: slot)
    }

    private func firstSound(_ x: [Float]) -> Int? { x.firstIndex { abs($0) > 0.0005 } }

    private func rms(_ x: ArraySlice<Float>) -> Float {
        (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot()
    }

    func testOneShotPlaysOnceAndGateStopsWhenLetGo() throws {
        let dj = makeEngine()
        try loadSound(dc(0.2), on: dj)
        dj.sampler.press(0, masterDeck: 0)
        let once = dj.renderOffline(frames: Int(sr * 0.4)).left
        XCTAssertGreaterThan(rms(once[2000..<6000]), 0.1)
        XCTAssertLessThan(rms(once[(once.count - 4000)...]), 0.001, "It finished by itself")
        XCTAssertFalse(dj.sampler.isPlaying(0))

        dj.sampler.setMode(.gate, slot: 0)
        dj.sampler.press(0, masterDeck: 0)
        _ = dj.renderOffline(frames: 1024)
        dj.sampler.release(0)
        let after = dj.renderOffline(frames: 4096).left
        XCTAssertLessThan(rms(after[2048...]), 0.001, "It stopped when the pad came up")
    }

    func testLoopModeGoesRoundUntilPressedAgainWithoutClicking() throws {
        let dj = makeEngine()
        // Ends on a different value from where it starts, so a bare wrap would click.
        let n = Int(sr * 0.1)
        let x = (0..<n).map { 0.4 * Float(sin(2 * .pi * 220 * Double($0) / sr)) + 0.2 * Float($0) / Float(n) }
        try loadSound(PCM16Stereo(left: x, right: x), on: dj, mode: .loop)
        dj.sampler.press(0, masterDeck: 0)
        XCTAssertTrue(dj.sampler.looping.contains(0))
        let out = dj.renderOffline(frames: Int(sr * 0.5)).left
        XCTAssertGreaterThan(rms(out[(out.count - 4000)...]), 0.1, "Still going after several times round")
        var worst: Float = 0
        for i in 2000..<(out.count - 1) { worst = max(worst, abs(out[i + 1] - out[i])) }
        XCTAssertLessThan(worst, 0.08, "A wrap clicked")
        dj.sampler.press(0, masterDeck: 0)
        XCTAssertFalse(dj.sampler.looping.contains(0))
        let after = dj.renderOffline(frames: 4096).left
        XCTAssertLessThan(rms(after[2048...]), 0.001)
    }

    func testQuantizedPadsLandOnTheBeatOfTheMaster() throws {
        let dj = makeEngine()
        try loadSound(dc(0.3), on: dj)
        // How long the limiter holds audio back, measured by firing a pad at a known moment.
        dj.sampler.press(0, masterDeck: 0)
        let reference = try XCTUnwrap(firstSound(dj.renderOffline(frames: 2048).left))
        _ = dj.renderOffline(frames: Int(sr * 0.5))

        let deck = dj.decks[0]
        deck.renderer.setSources([PCM16Stereo(frames: Int(sr * 60))])
        deck.track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: 60, bpm: 120, firstBeat: 0)
        deck.seek(to: 10.05) // 1/4 beat is 0.125 s here, so the next line is at 10.125
        deck.play()
        _ = dj.renderOffline(frames: 256)
        let start = deck.renderer.playhead
        dj.sampler.quantize = true
        dj.sampler.press(0, masterDeck: 0)
        let out = dj.renderOffline(frames: Int(sr * 0.2)).left
        let heard = try XCTUnwrap(firstSound(out))
        let landed = start + Double(heard - reference)
        let line = (landed / (sr * 0.125)).rounded() * sr * 0.125
        XCTAssertEqual(landed, line, accuracy: 2, "It should start exactly on a line of the grid")
        XCTAssertGreaterThan(landed, start, "Not before the press")
    }

    func testAPressJustAfterTheBeatStaysInTime() throws {
        let dj = makeEngine()
        // A ramp, so how far into the sample it starts can be read from the level.
        let n = Int(sr * 0.5)
        let x = (0..<n).map { Float($0) / Float(n) * 0.8 }
        try loadSound(PCM16Stereo(left: x, right: x), on: dj)
        let deck = dj.decks[0]
        deck.renderer.setSources([PCM16Stereo(frames: Int(sr * 60))])
        deck.track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: 60, bpm: 120, firstBeat: 0)
        deck.seek(to: 10.0)
        deck.play()
        _ = dj.renderOffline(frames: Int(sr * 0.01)) // 10 ms past the beat
        dj.sampler.quantize = true
        dj.sampler.press(0, masterDeck: 0)
        let out = dj.renderOffline(frames: 2048).left
        let heard = try XCTUnwrap(firstSound(out))
        XCTAssertLessThan(heard, 1024, "It doesn't wait for the next line")
        // Skips in by about what it was late: at 10 ms into a 500 ms ramp, about 2% of full scale.
        XCTAssertGreaterThan(out[heard + 256], 0.01)
    }

    func testGrabbingALoopRespectsWhatsMuted() throws {
        let dj = makeEngine()
        let deck = dj.decks[0]
        // Stems at their storage level: vocal is a constant 0.2, drums a constant 0.1, once restored.
        let n = Int(sr * 4)
        func stem(_ level: Float) -> PCM16Stereo {
            let x = [Float](repeating: level * PCM16Stereo.stemHeadroom, count: n)
            return PCM16Stereo(left: x, right: x)
        }
        deck.renderer.setSources([stem(0.2), stem(0), stem(0), stem(0.1)])
        deck.stemsOn = [false, true, true, true]
        deck.renderer.setLoop(start: sr, end: sr * 2, active: false)
        XCTAssertNil(dj.sampler.grabLoop(from: deck, slot: 3))
        XCTAssertEqual(dj.sampler.slots[3].mode, .loop, "A grabbed loop goes round")
        XCTAssertTrue(dj.sampler.hasOwnSound(3))
        deck.renderer.setSources([])
        dj.sampler.press(3, masterDeck: 0)
        let out = dj.renderOffline(frames: 8192).left
        XCTAssertEqual(rms(out[4000..<8000]), 0.1, accuracy: 0.01, "Only the drums should be in it")
        dj.sampler.restoreOriginal(3)
    }

    func testGrabbingWithNoLoopSaysSo() {
        let dj = makeEngine()
        XCTAssertNotNil(dj.sampler.grabLoop(from: dj.decks[1], slot: 1))
        XCTAssertFalse(dj.sampler.hasOwnSound(1))
    }

    func testRecordingTheMasterOntoAPad() throws {
        let dj = makeEngine()
        try loadSound(dc(2), on: dj, slot: 0)
        dj.sampler.press(0, masterDeck: 0)
        _ = dj.renderOffline(frames: 2048)
        dj.sampler.startRecording(slot: 5)
        XCTAssertEqual(dj.sampler.recordingSlot, 5)
        _ = dj.renderOffline(frames: Int(sr * 0.5))
        XCTAssertEqual(dj.sampler.recordedSeconds, 0.5, accuracy: 0.01)
        dj.sampler.press(5, masterDeck: 0) // pressing the pad being recorded finishes it
        XCTAssertNil(dj.sampler.recordingSlot)
        XCTAssertTrue(dj.sampler.hasOwnSound(5))
        dj.sampler.stopAll()
        _ = dj.renderOffline(frames: 2048)
        dj.sampler.press(5, masterDeck: 0)
        let out = dj.renderOffline(frames: 8192).left
        XCTAssertGreaterThan(rms(out[4000..<8000]), 0.15, "The recording plays back what the master was playing")
        dj.sampler.restoreOriginal(5)
    }

    func testPadsAreRememberedAndCanBePutBack() throws {
        let dj = makeEngine()
        try loadSound(dc(0.1), on: dj, slot: 2, mode: .gate)
        dj.sampler.rename(2, to: "Vox Stab")
        let file = try XCTUnwrap(dj.sampler.slots[2].fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: Sampler.directory.appending(path: file).path))

        let next = DJEngine(library: Library())
        next.stopRealtimeForTesting()
        XCTAssertEqual(next.sampler.name(2), "Vox Stab")
        XCTAssertEqual(next.sampler.slots[2].mode, .gate)
        XCTAssertEqual(next.sampler.slots[2].fileName, file)

        dj.sampler.restoreOriginal(2)
        XCTAssertEqual(dj.sampler.name(2), SampleBank.names[2])
        XCTAssertEqual(dj.sampler.slots[2].mode, .oneShot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Sampler.directory.appending(path: file).path), "The file's cleared up")
    }

    func testImportingAFileThatsTooLongIsRefused() async throws {
        let dj = makeEngine()
        let url = FileManager.default.temporaryDirectory.appending(path: "long-\(UUID().uuidString).caf")
        try PCM16Stereo(frames: Int(sr * (Sampler.longestSample + 1))).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let message = await dj.sampler.importSample(from: url, slot: 4)
        XCTAssertNotNil(message)
        XCTAssertFalse(dj.sampler.hasOwnSound(4))
    }
}
