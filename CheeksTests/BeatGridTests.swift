import XCTest
@testable import Cheeks

/// The grid under everything that works in beats, and whether tempo changes get detected.
@MainActor
final class BeatGridTests: XCTestCase {
    private let sr = AudioConfig.sampleRate

    /// 120 BPM for 8 beats from 1 s, then 90 BPM, then 150 BPM.
    private var markers: [TempoMarker] {
        [TempoMarker(time: 1, bpm: 120), TempoMarker(time: 5, bpm: 90), TempoMarker(time: 9, bpm: 150, beatInBar: 2)]
    }

    func testASteadyGridIsTheSameSumAsBefore() {
        let grid = BeatGrid(bpm: 128, firstBeat: 0.37)
        XCTAssertFalse(grid.isVariable)
        XCTAssertEqual(grid.beat(at: 0.37 + 60), 128, accuracy: 1e-9)
        XCTAssertEqual(grid.seconds(atBeat: 128), 0.37 + 60, accuracy: 1e-9)
        XCTAssertEqual(grid.beat(at: 0), -0.37 * 128 / 60, accuracy: 1e-9)
    }

    func testVariableGridCountsThroughItsSections() throws {
        let grid = try XCTUnwrap(BeatGrid(markers: markers))
        XCTAssertEqual(grid.beat(at: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(grid.beat(at: 5), 8, accuracy: 1e-9)
        XCTAssertEqual(grid.beat(at: 5 + 60 / 90.0), 9, accuracy: 1e-9)
        XCTAssertEqual(grid.bpm(at: 4.999), 120)
        XCTAssertEqual(grid.bpm(at: 5), 90)
        // 4 s at 90 BPM is exactly 6 beats, so beat 14 is the third of the bar, as the marker says.
        XCTAssertEqual(grid.beat(at: 9), 14, accuracy: 1e-9)
        for beat in stride(from: -3.0, through: 40, by: 0.37) {
            XCTAssertEqual(grid.beat(at: grid.seconds(atBeat: beat)), beat, accuracy: 1e-9)
        }
    }

    func testTheMarkerDecidesWhereTheBarFalls() throws {
        // The count says this is beat 4, the first of a bar; the marker says it's the third.
        let grid = try XCTUnwrap(BeatGrid(markers: [TempoMarker(time: 0, bpm: 120), TempoMarker(time: 2, bpm: 120, beatInBar: 2)]))
        let beat = grid.beat(at: 2)
        XCTAssertEqual(beat.truncatingRemainder(dividingBy: 4), 2, accuracy: 1e-9)
    }

    func testOldLibrariesStillLoad() throws {
        let json = """
        {"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","title":"Old","artist":"A","fileName":"a.mp3",
         "duration":100,"bpm":128,"firstBeat":0.5,"hotCues":{"2":30.5},"memoryCue":12.5,
         "rating":3,"playCount":4,"dateAdded":700000000}
        """
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        XCTAssertEqual(track.memoryCues.map(\.time), [12.5])
        XCTAssertEqual(track.memoryCue, 12.5)
        XCTAssertEqual(track.hotCues[2], 30.5)
        XCTAssertEqual(track.rating, 3)
        XCTAssertNil(track.tempoMarkers)
        XCTAssertNil(track.phrases)
        XCTAssertTrue(track.savedLoops.isEmpty)
    }

    func testANewLibraryRoundTrips() throws {
        var track = Track(id: UUID(), title: "New", artist: "", fileName: "a.mp3", bpm: 120, firstBeat: 0.1)
        track.tempoMarkers = markers
        track.memoryCues = [MemoryCue(time: 3, name: "Intro")]
        track.savedLoops = [SavedLoop(start: 4, end: 8, name: "Hook", activeOnLoad: true)]
        track.hotCueInfo = [1: HotCueInfo(name: "Drop", color: CueColor(red: 1, green: 0, blue: 0), loopEnd: 9)]
        track.phrases = [Phrase(start: 0, kind: .intro)]
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(back, track)
    }

    // MARK: On a deck

    private func deck(markers: [TempoMarker]) -> Deck {
        let deck = Deck(index: 0)
        deck.renderer.setSources([PCM16Stereo(frames: Int(sr * 60))])
        deck.track = Track(id: UUID(), title: "T", artist: "", fileName: "none", duration: 60, bpm: 120, firstBeat: 1, tempoMarkers: markers)
        return deck
    }

    func testLoopsJumpsAndSlicesFollowTheTempoWhereTheyAre() {
        let deck = deck(markers: markers)
        deck.seek(to: 3) // beat 4, in the 120 BPM section
        _ = deck.renderer.renderOffline(frames: 256)
        // Eight beats from beat 4 crosses into 90 BPM: 2 s at 120, then 4 beats at 90.
        deck.setLoop(beats: 8, resizeExisting: false)
        XCTAssertEqual(deck.renderer.loopStart / sr, 3, accuracy: 0.001)
        XCTAssertEqual(deck.renderer.loopEnd / sr, 5 + 4 * 60 / 90.0, accuracy: 0.001)
        deck.exitLoop()

        deck.beatJump(8)
        _ = deck.renderer.renderOffline(frames: 256)
        XCTAssertEqual(deck.position, 5 + 4 * 60 / 90.0, accuracy: 0.01)
        deck.tick()
        XCTAssertEqual(deck.bpm, 90, "The deck reads the tempo where the playhead is")
    }

    func testTheCoreGetsTheLocalTempoForBeatFX() {
        let deck = deck(markers: markers)
        deck.seek(to: 6)
        _ = deck.renderer.renderOffline(frames: 256)
        deck.tick()
        XCTAssertEqual(deck.bpm, 90)
        XCTAssertEqual(deck.beatFrames, sr * 60 / 90, accuracy: 0.001)
        // Counting back from this section, the beats must land where the map says.
        let beats = (6 * sr - deck.firstBeatFrame) / deck.beatFrames
        XCTAssertEqual(beats, deck.beatPosition(6 * sr), accuracy: 1e-6)
    }

    func testTwoDecksStayLockedThroughATempoChange() {
        // The leader changes tempo twice. The follower has a steady grid and has to keep up.
        let lead = deck(markers: markers)
        let follow = Deck(index: 1)
        follow.renderer.setSources([PCM16Stereo(frames: Int(sr * 60))])
        follow.track = Track(id: UUID(), title: "F", artist: "", fileName: "none", duration: 60, bpm: 124, firstBeat: 0.2)
        lead.seek(to: 2)
        follow.seek(to: 5)
        lead.play(); follow.play()
        _ = lead.renderer.renderOffline(frames: 256)
        _ = follow.renderer.renderOffline(frames: 256)
        follow.sync(to: lead)
        var worst = 0.0
        // Render by hand at 30 ticks a second, the same way the engine's timer drives sync.
        for step in 0..<(30 * 14) {
            lead.tick(); follow.tick()
            let wanted = (follow.matchedBPM(for: lead.effectiveBPM) / follow.bpm - 1) * 100
            if abs(wanted - follow.tempoRatioPercent) > 0.0005 { follow.setTempo(wanted) }
            if follow.renderer.pendingNudge == 0 {
                let drift = follow.phaseOffset(to: lead)
                if abs(drift) > 0.0002 { follow.alignPhase(to: lead, smoothly: true) }
            }
            _ = lead.renderer.renderOffline(frames: 1470)
            _ = follow.renderer.renderOffline(frames: 1470)
            // A moment to settle after each change of tempo; after that they have to be together.
            let sinceChange = [5.0, 9.0].map { abs(lead.position - $0) }.min() ?? 1
            if step > 30 && sinceChange > 0.5 { worst = max(worst, abs(follow.phaseOffset(to: lead))) }
        }
        XCTAssertGreaterThan(lead.position, 12, "The leader has been through both changes")
        XCTAssertLessThan(worst, 0.03, "Decks drifted apart by \(worst) of a beat")
    }

    // MARK: Detecting tempo changes

    /// Kicks and hats on the beats given, plus a held note so it isn't only clicks.
    private func track(beats: [Double], seconds: Double) -> PCM16Stereo {
        let n = Int(seconds * sr)
        var x = [Float](repeating: 0, count: n)
        var seed: UInt32 = 99
        for beat in beats {
            let start = Int(beat * sr)
            for k in 0..<Int(0.14 * sr) where start + k < n && start + k >= 0 {
                let t = Double(k) / sr
                let f = 50 + 80 * exp(-t * 30)
                x[start + k] += Float(0.8 * sin(2 * .pi * f * t) * exp(-t * 18))
                if k < Int(0.03 * sr) {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    x[start + k] += 0.25 * Float(Int32(bitPattern: seed)) / Float(Int32.max) * Float(exp(-t * 120))
                }
            }
        }
        for i in 0..<n { x[i] += 0.05 * Float(sin(2 * .pi * 220 * Double(i) / sr)) }
        return PCM16Stereo(left: x, right: x)
    }

    /// Beat times where the tempo moves with `bpm(seconds)`.
    private func beats(until seconds: Double, bpm: (Double) -> Double) -> [Double] {
        var out: [Double] = []
        var t = 0.3
        while t < seconds {
            out.append(t)
            t += 60 / bpm(t)
        }
        return out
    }

    func testASteadyTrackGetsNoTempoMap() {
        let steady = beats(until: 90) { _ in 124 }
        let result = TrackAnalyzer.analyze(track(beats: steady, seconds: 90))
        XCTAssertNil(result.tempoMarkers)
        XCTAssertEqual(result.bpm, 124, accuracy: 0.05)
    }

    func testABreakdownDoesNotLookLikeATempoChange() {
        // 40 seconds of silence in the kicks is where a tracker's guesses creep.
        let steady = beats(until: 100) { _ in 128 }.filter { $0 < 30 || $0 > 70 }
        XCTAssertNil(TrackAnalyzer.analyze(track(beats: steady, seconds: 100)).tempoMarkers)
    }

    func testADrummersSmallTimingErrorsGetNoTempoMap() {
        var seed: UInt32 = 7
        let played = beats(until: 90) { _ in 110 }.map { beat -> Double in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return beat + 0.012 * Double(Int32(bitPattern: seed)) / Double(Int32.max)
        }
        XCTAssertNil(TrackAnalyzer.analyze(track(beats: played, seconds: 90)).tempoMarkers)
    }

    func testAStepChangeInTempoIsFollowed() throws {
        // A song that changes tempo once, partway through: half a minute at 100, then at 112.
        let played = beats(until: 100) { $0 < 50 ? 100 : 112 }
        let result = TrackAnalyzer.analyze(track(beats: played, seconds: 100))
        let markers = try XCTUnwrap(result.tempoMarkers, "A 12 BPM jump should be detected")
        let grid = try XCTUnwrap(BeatGrid(markers: markers))
        XCTAssertEqual(grid.bpm(at: 20), 100, accuracy: 1.5)
        XCTAssertEqual(grid.bpm(at: 80), 112, accuracy: 1.5)
    }

    func testATrackThatSpeedsUpGetsATempoMapThatFollowsIt() throws {
        // A band speeding up from 112 to 124 over two minutes, about what a live take does.
        let speed: (Double) -> Double = { 112 + 12 * $0 / 120 }
        let played = beats(until: 120, bpm: speed)
        let result = TrackAnalyzer.analyze(track(beats: played, seconds: 120))
        let markers = try XCTUnwrap(result.tempoMarkers, "A 12 BPM drift should be detected")
        let grid = try XCTUnwrap(BeatGrid(markers: markers))
        XCTAssertEqual(grid.bpm(at: 20), speed(20), accuracy: 1.5)
        XCTAssertEqual(grid.bpm(at: 100), speed(100), accuracy: 1.5)
        XCTAssertEqual(result.firstBeat, markers[0].time, accuracy: 0.001)
        // The real test: the beats it thinks exist are where the kicks really are.
        var worst = 0.0
        for beat in played where beat > 10 && beat < 110 {
            let b = grid.beat(at: beat)
            worst = max(worst, abs(b - b.rounded()) * 60 / speed(beat))
        }
        print("TEMPO: speeding-up track, worst beat is \(Int(worst * 1000)) ms off the grid, \(markers.count) markers")
        XCTAssertGreaterThan(markers.count, 8)
        XCTAssertLessThan(worst, 0.04)
    }
}
