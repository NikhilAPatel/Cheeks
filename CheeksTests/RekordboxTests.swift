import XCTest
@testable import Cheeks

final class RekordboxTests: XCTestCase {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <DJ_PLAYLISTS Version="1.0.0">
      <PRODUCT Name="rekordbox" Version="7.0.0" Company="AlphaTheta"/>
      <COLLECTION Entries="2">
        <TRACK TrackID="11" Name="Night Drive" Artist="Somebody" AverageBpm="128.00" Tonality="Am"
               Location="file://localhost/Users/me/Music/Night%20Drive.mp3">
          <TEMPO Inizio="0.400" Bpm="128.00" Metro="4/4" Battito="3"/>
          <TEMPO Inizio="60.400" Bpm="128.00" Metro="4/4" Battito="1"/>
          <POSITION_MARK Name="" Type="0" Start="0.400" Num="-1"/>
          <POSITION_MARK Name="Drop" Type="0" Start="45.400" Num="0" Red="40" Green="226" Blue="20"/>
          <POSITION_MARK Name="" Type="4" Start="50.0" End="52.0" Num="1"/>
          <POSITION_MARK Name="" Type="0" Start="75.025" Num="3"/>
        </TRACK>
        <TRACK TrackID="12" Name="Sunrise" Artist="Other" AverageBpm="122.00" Tonality="8B"
               Location="file://localhost/Users/me/Music/sunrise.flac"/>
      </COLLECTION>
      <PLAYLISTS>
        <NODE Type="0" Name="ROOT" Count="1">
          <NODE Name="Warmup" Type="1" KeyType="0" Entries="2">
            <TRACK Key="12"/>
            <TRACK Key="11"/>
          </NODE>
        </NODE>
      </PLAYLISTS>
    </DJ_PLAYLISTS>
    """

    func testParsesGridKeyCuesAndPlaylists() throws {
        let collection = try XCTUnwrap(RekordboxCollection.parse(Data(xml.utf8)))
        XCTAssertEqual(collection.entries.count, 2)

        let first = collection.entries[0]
        XCTAssertEqual(first.fileName, "Night Drive.mp3")
        XCTAssertEqual(first.bpm, 128)
        XCTAssertEqual(first.key, "8A")
        // Beat 3 of the bar sits at 0.4 s, so the next downbeat is two beats later.
        XCTAssertEqual(first.firstBeat ?? -1, 0.4 + 2 * 60 / 128.0, accuracy: 0.0001)
        XCTAssertEqual(first.memoryCue, 0.4)
        XCTAssertEqual(first.hotCues, [0: 45.4, 3: 75.025]) // the saved loop (Type 4) is skipped

        XCTAssertEqual(collection.entries[1].key, "8B")
        XCTAssertEqual(collection.playlists.count, 1)
        XCTAssertEqual(collection.playlists[0].name, "Warmup")
        XCTAssertEqual(collection.playlists[0].trackIDs, ["12", "11"])
    }

    func testTonalityToCamelot() {
        XCTAssertEqual(RekordboxCollection.camelot(fromTonality: "F#m"), "11A")
        XCTAssertEqual(RekordboxCollection.camelot(fromTonality: "Db"), "3B")
        XCTAssertEqual(RekordboxCollection.camelot(fromTonality: "Ebm"), "2A")
        XCTAssertEqual(RekordboxCollection.camelot(fromTonality: "10A"), "10A")
        XCTAssertNil(RekordboxCollection.camelot(fromTonality: "nonsense"))
    }

    func testRejectsNonRekordboxXML() {
        XCTAssertNil(RekordboxCollection.parse(Data("<plist><dict/></plist>".utf8)))
    }
}
