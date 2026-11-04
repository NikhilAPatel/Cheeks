import XCTest
@testable import Cheeks

/// Naming sections from what the stems are doing. The arrangements are the ones real club tracks have, as `tools/autodj`'s
/// maps show them. Bars here are seconds, so an answer reads as a bar number.
final class TrackMapSectionsTests: XCTestCase {
    private struct Part {
        var bars: Int
        var kick = true, bass = true
        var level: Float = 0
        /// Added per bar, for what builds.
        var climb: Float = 0
        /// How much of each bar someone's singing in.
        var sung: Float = 0
    }

    private let grid = BeatGrid(bpm: 240, firstBeat: 0)

    private func map(_ parts: [Part]) -> TrackMap {
        var kick: [Bool] = [], bass: [Bool] = [], energy: [Float] = [], vocal: [Float] = [], boundaries = [0]
        for part in parts {
            for bar in 0..<part.bars {
                kick.append(part.kick)
                bass.append(part.bass)
                energy.append(part.level + part.climb * Float(bar))
                vocal.append(part.sung)
            }
            boundaries.append(kick.count)
        }
        let silent = [Bool](repeating: false, count: kick.count)
        return TrackMap(bpm: 240, firstBeat: 0, drift: 0, isSteady: true, firstBar: 0, barCount: kick.count,
                        levels: [], kickLevels: [], vocal: vocal, on: [silent, silent, bass, kick], hasKick: kick, energy: energy,
                        lattice: 0, boundaries: boundaries, harmony: [], vocalNotes: [], keyRoot: 0, keyIsMinor: false)
    }

    private func check(_ parts: [Part], _ expected: [(Phrase.Kind, Double)], file: StaticString = #filePath, line: UInt = #line) {
        let phrases = map(parts).phrases(on: grid)
        let got = phrases.map { "\($0.kind.rawValue)@\($0.start)" }.joined(separator: " ")
        let want = expected.map { "\($0.0.rawValue)@\($0.1)" }.joined(separator: " ")
        XCTAssertEqual(got, want, file: file, line: line)
    }

    func testAClubTrack() {
        check([Part(bars: 32, bass: false, level: -8), Part(bars: 8, kick: false, bass: false, level: -6),
               Part(bars: 32), Part(bars: 24, kick: false, bass: false, level: -12), Part(bars: 4, kick: false, bass: false, level: -8),
               Part(bars: 32), Part(bars: 24, bass: false, level: -8)],
              [(.intro, 0), (.up, 32), (.chorus, 40), (.down, 72), (.up, 96), (.chorus, 100), (.outro, 132)])
    }

    func testABreakdownTooLongToBeABuildIsABreakdown() {
        check([Part(bars: 32), Part(bars: 44, kick: false, bass: false, level: -10), Part(bars: 32)],
              [(.chorus, 0), (.down, 32), (.chorus, 76)])
    }

    func testAFillBeforeAChorusLeadsIntoIt() {
        // Only the bass stops, for four bars. It's a fill, so it isn't a section of its own kind.
        check([Part(bars: 32), Part(bars: 4, bass: false, level: -2), Part(bars: 32)],
              [(.chorus, 0), (.up, 32), (.chorus, 36)])
    }

    func testSomethingBuildingWithItsKickInIsABuildUp() {
        check([Part(bars: 32), Part(bars: 16, bass: false, level: -12), Part(bars: 12, bass: false, level: -10, climb: 0.8), Part(bars: 32)],
              [(.chorus, 0), (.verse, 32), (.up, 48), (.chorus, 60)])
    }

    /// Rock: the kick and the bass never stop, so what's a chorus comes down to its level.
    func testAKitThatNeverStopsGoesByLevel() {
        check([Part(bars: 16, level: -7), Part(bars: 16), Part(bars: 16, level: -7), Part(bars: 16), Part(bars: 16, level: -7)],
              [(.intro, 0), (.chorus, 16), (.verse, 32), (.chorus, 48), (.outro, 64)])
    }

    /// A loud master hardly moves in level, so the parts of a long stretch with nobody singing are its smaller ones.
    func testAStretchWithNobodySingingIsntTheChorus() {
        check([Part(bars: 32, sung: 0.9), Part(bars: 12, sung: 0.1), Part(bars: 24, sung: 0.9), Part(bars: 16, sung: 0), Part(bars: 32, sung: 0.9)],
              [(.chorus, 0), (.verse, 32), (.chorus, 44), (.verse, 68), (.chorus, 84)])
    }

    func testAQuieterPartOfALongStretchIsntTheChorus() {
        check([Part(bars: 32), Part(bars: 16, level: -3), Part(bars: 32)],
              [(.chorus, 0), (.verse, 32), (.chorus, 48)])
    }

    /// A gap between lines isn't a section, and neither is a track that's one long chorus to begin with.
    func testALongStretchKeepsItsShortGapsAndItsWhole() {
        check([Part(bars: 32, sung: 0.9), Part(bars: 4, sung: 0.1), Part(bars: 32, sung: 0.9)], [(.chorus, 0)])
        check([Part(bars: 64, level: 0, climb: -0.1)], [(.chorus, 0)])
    }

    func testATrackWithNoDrumsGoesByLevel() {
        check([Part(bars: 16, kick: false, bass: false, level: -9), Part(bars: 32, kick: false, bass: false), Part(bars: 16, kick: false, bass: false, level: -9)],
              [(.intro, 0), (.chorus, 16), (.outro, 48)])
    }

    func testATrackThatNeverChangesIsOneSection() {
        check([Part(bars: 64)], [(.chorus, 0)])
    }

    func testAScrapAtEitherEndJoinsWhatItsNextTo() {
        check([Part(bars: 1, kick: false, bass: false, level: -40), Part(bars: 32), Part(bars: 2, kick: false, bass: false, level: -40)],
              [(.chorus, 0)])
    }

    func testAFewBarsWithEverythingInArentAChorusOnTheirOwn() {
        check([Part(bars: 32, bass: false, level: -8), Part(bars: 4), Part(bars: 12, bass: false, level: -8), Part(bars: 32), Part(bars: 16, bass: false, level: -8)],
              [(.intro, 0), (.chorus, 48), (.outro, 80)])
    }

    /// Bars get counted on a grid of the map's own, and someone's grid can sit anywhere against it.
    func testSectionsStartOnTheBarsOfTheGridInUse() {
        let phrases = map([Part(bars: 32, bass: false, level: -8), Part(bars: 32)]).phrases(on: BeatGrid(bpm: 240, firstBeat: 0.3))
        XCTAssertEqual(phrases.map(\.kind), [.intro, .chorus])
        XCTAssertEqual(phrases[0].start, 0, "The first section's from the very start")
        XCTAssertEqual(phrases[1].start, 32.3, accuracy: 0.001)
    }

    // MARK: On a deck

    @MainActor
    private func loadedDeck(gridSource: GridSource) -> Deck {
        let deck = Deck(index: 0)
        var track = Track(id: UUID(), title: "T", artist: "", fileName: "t.mp3")
        track.bpm = 240
        track.firstBeat = 0
        track.gridSource = gridSource
        track.phrases = [Phrase(start: 0, kind: .chorus)]
        deck.track = track
        return deck
    }

    @MainActor
    func testStemsNameADecksSections() {
        let deck = loadedDeck(gridSource: .analysis)
        deck.applyTrackMap(map([Part(bars: 32, bass: false, level: -8), Part(bars: 32)]))
        XCTAssertEqual(deck.track?.phrases?.map(\.kind), [.intro, .chorus])
        XCTAssertEqual(deck.phrase(atFrame: 40 * deck.sampleRate)?.kind, .chorus)
    }

    /// Someone's grid stays, and what's in the track is still what's in the track.
    @MainActor
    func testStemsNameTheSectionsOnAGridSomeoneSet() {
        let deck = loadedDeck(gridSource: .person)
        deck.applyTrackMap(map([Part(bars: 32, bass: false, level: -8), Part(bars: 32)]))
        XCTAssertEqual(deck.track?.gridSource, .person)
        XCTAssertEqual(deck.track?.phrases?.map(\.kind), [.intro, .chorus])
    }

    /// Round 13, on a real track: 4:27 of `CHORUS`. Its kick, bass and level never move, and only the singer comes and goes.
    func testAVeryLongRunNamesItsSungParts() {
        check([Part(bars: 4), Part(bars: 12), Part(bars: 8, sung: 1), Part(bars: 24), Part(bars: 16, sung: 1), Part(bars: 40)],
              [(.intro, 0), (.chorus, 16), (.verse, 24), (.chorus, 48), (.outro, 64)])
    }

    func testAVeryLongRunWithNobodySingingHasNothingToGoOn() {
        check([Part(bars: 40), Part(bars: 40), Part(bars: 40)], [(.chorus, 0)])
    }

    func testARunThatIsntSoLongKeepsItsChorus() {
        check([Part(bars: 32), Part(bars: 8, sung: 1), Part(bars: 16)], [(.chorus, 0)])
    }

    /// A loose track keeps its grid, as its kicks are no use for one, but they still say where they stop.
    @MainActor
    func testStemsNameTheSectionsOfATrackWithALooseGrid() {
        let deck = loadedDeck(gridSource: .analysis)
        var loose = map([Part(bars: 32, bass: false, level: -8), Part(bars: 32)])
        loose.isSteady = false
        deck.applyTrackMap(loose)
        XCTAssertEqual(deck.track?.gridSource, .analysis)
        XCTAssertEqual(deck.track?.phrases?.map(\.kind), [.intro, .chorus])
    }
}
