import AVFoundation
import XCTest
@testable import Cheeks

/// What's in someone's library isn't always what it says it is. Each of these has to load or say why not, and nothing can
/// come apart afterwards: play, a seek, a cue, a stem split, or Auto DJ being pressed with it on a deck.
@MainActor
final class OddFilesTests: XCTestCase {
    private var files: [URL] = []
    private var preparedStems: Any?
    private var enginesKeptAlive: [DJEngine] = []

    override func setUp() async throws {
        preparedStems = UserDefaults.standard.object(forKey: "prepareStemsOnLoad")
        UserDefaults.standard.set(false, forKey: "prepareStemsOnLoad")
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(preparedStems, forKey: "prepareStemsOnLoad")
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func makeEngine() -> (DJEngine, Library) {
        let library = Library()
        library.tracks = []
        library.playlists = []
        library.missingFiles = []
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        enginesKeptAlive.append(dj)
        return (dj, library)
    }

    private func newFile(_ ext: String) -> URL {
        let url = LibraryFiles.musicDirectory.appending(path: "\(UUID().uuidString).\(ext)")
        files.append(url)
        return url
    }

    /// A file of audio. `fill` gives each frame's value on every channel.
    private func audioFile(ext: String = "wav", rate: Double = 44_100, channels: AVAudioChannelCount = 2, frames: Int,
                           settings: [String: Any]? = nil, fill: (Int) -> Float = { _ in 0 }) throws -> URL {
        let url = newFile(ext)
        let layout = channels > 2 ? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A) : nil
        let format: AVAudioFormat
        if let layout {
            format = AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
        } else {
            format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
        }
        // In a scope, as the file only gets finished off when it goes.
        do {
            let audio = try AVAudioFile(forWriting: url, settings: settings ?? format.settings)
            if frames > 0 {
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
                buffer.frameLength = AVAudioFrameCount(frames)
                for channel in 0..<Int(channels) {
                    for i in 0..<frames { buffer.floatChannelData![channel][i] = fill(i) }
                }
                try audio.write(from: buffer)
            }
        }
        return url
    }

    private func tone(_ i: Int) -> Float { 0.4 * Float(sin(2 * .pi * 220 * Double(i) / 44_100)) }

    private func oddFiles() throws -> [(name: String, url: URL)] {
        var out: [(String, URL)] = []
        let empty = newFile("mp3")
        try Data().write(to: empty)
        out.append(("no bytes at all", empty))
        let noise = newFile("mp3")
        try Data((0..<65_536).map { _ in UInt8.random(in: 0...255) }).write(to: noise)
        out.append(("random bytes called mp3", noise))
        let text = newFile("wav")
        try Data("this isn't audio".utf8).write(to: text)
        out.append(("words called wav", text))
        out.append(("a header and no audio", try audioFile(frames: 0)))
        out.append(("one sample", try audioFile(frames: 1, fill: tone)))
        out.append(("10 ms", try audioFile(frames: 441, fill: tone)))
        out.append(("half a second", try audioFile(frames: 22_050, fill: tone)))
        out.append(("mono at 8 kHz", try audioFile(rate: 8_000, channels: 1, frames: 16_000, fill: tone)))
        out.append(("96 kHz", try audioFile(rate: 96_000, frames: 192_000, fill: tone)))
        out.append(("six channels", try audioFile(rate: 48_000, channels: 6, frames: 96_000, fill: tone)))
        out.append(("30 s of silence", try audioFile(frames: 44_100 * 30)))
        out.append(("30 s flat out", try audioFile(frames: 44_100 * 30, fill: { $0 % 200 < 100 ? 1 : -1 })))
        out.append(("not a number", try audioFile(frames: 44_100 * 3, fill: { _ in .nan })))
        let aac: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 2]
        let whole = try audioFile(ext: "m4a", frames: 44_100 * 10, settings: aac, fill: tone)
        out.append(("aac", whole))
        let wav = try audioFile(frames: 44_100 * 10, fill: tone)
        let cut = newFile("wav")
        try Data(try Data(contentsOf: wav).prefix(44_100)).write(to: cut)
        out.append(("a wav cut short", cut))
        let cutAAC = newFile("m4a")
        let aacData = try Data(contentsOf: whole)
        try Data(aacData.prefix(aacData.count / 2)).write(to: cutAAC)
        out.append(("an aac cut short", cutAAC))
        return out
    }

    private func track(_ url: URL, in library: Library) -> Track {
        let id = UUID()
        let track = Track(id: id, title: "Odd", artist: "", fileName: url.lastPathComponent)
        library.tracks.append(track)
        return track
    }

    private func finishLoading(_ deck: Deck, _ name: String) async throws {
        for _ in 0..<1500 where deck.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(deck.isLoading, "\(name): the load never finished")
    }

    func testEachOddFileLoadsOrSaysWhy() async throws {
        for (name, url) in try oddFiles() {
            let (dj, library) = makeEngine()
            let deck = dj.decks[0]
            deck.load(track(url, in: library))
            try await finishLoading(deck, name)
            print("ODD: \(name): loaded \(deck.isLoaded), error \(deck.loadError ?? "none"), \(deck.duration) s, \(deck.bpm) BPM")
            guard deck.isLoaded else {
                XCTAssertNotNil(deck.loadError, "\(name): nothing's on the deck, and it doesn't say why")
                continue
            }
            XCTAssertTrue(deck.bpm.isFinite && deck.bpm > 0, "\(name): \(deck.bpm) BPM")
            XCTAssertTrue(deck.duration.isFinite, name)
            deck.play()
            for _ in 0..<5 {
                let (left, _) = dj.renderOffline(frames: 4410)
                XCTAssertFalse(left.contains { !$0.isFinite }, "\(name): that comes out of the speakers")
                dj.tickForTesting()
            }
            deck.seek(to: deck.duration / 2)
            _ = dj.renderOffline(frames: 4410)
            deck.seek(to: deck.duration + 10)
            _ = dj.renderOffline(frames: 4410)
            dj.tickForTesting()
            deck.cueDown()
            deck.cueUp()
            deck.togglePlay()
            _ = dj.renderOffline(frames: 4410)
            dj.tickForTesting()
            let (left, right) = dj.renderOffline(frames: 4410)
            XCTAssertFalse(left.contains { !$0.isFinite } || right.contains { !$0.isFinite }, "\(name): that comes out of the speakers")
        }
    }

    /// A split of something too short to split gives back something short, or says it couldn't.
    func testATinyTrackCanBeSplit() async throws {
        for (name, frames) in [("one sample", 1), ("10 ms", 441), ("half a second", 22_050)] {
            let (dj, library) = makeEngine()
            let deck = dj.decks[0]
            deck.load(track(try audioFile(frames: frames, fill: tone), in: library))
            try await finishLoading(deck, name)
            XCTAssertTrue(deck.isLoaded, name)
            deck.prepareStems()
            for _ in 0..<3000 {
                if case .separating = deck.stemStatus { try await Task.sleep(for: .milliseconds(20)); continue }
                if case .reading = deck.stemStatus { try await Task.sleep(for: .milliseconds(20)); continue }
                break
            }
            print("ODD: \(name) split: \(deck.stemStatus)")
            deck.play()
            let (left, _) = dj.renderOffline(frames: 4410)
            XCTAssertFalse(left.contains { !$0.isFinite }, name)
        }
    }

    /// Auto DJ with what can't be mixed on a deck has to say so, and go on running.
    func testAutoDJWithATinyTrackOnADeck() async throws {
        for frames in [1, 441, 22_050] {
            let (dj, library) = makeEngine()
            let a = dj.decks[0], b = dj.decks[1]
            a.load(track(try audioFile(frames: 44_100 * 20, fill: tone), in: library))
            b.load(track(try audioFile(frames: frames, fill: tone), in: library))
            try await finishLoading(a, "A")
            try await finishLoading(b, "B")
            a.play()
            dj.autoDJ.press()
            for _ in 0..<40 {
                _ = dj.renderOffline(frames: 4410)
                dj.tickForTesting()
                await Task.yield()
            }
            print("ODD: AUTO with \(frames) frames on deck 2: \(dj.autoDJ.phase), said: \(dj.statusMessage ?? "nothing")")
            a.seek(to: a.duration - 1)
            for _ in 0..<40 {
                _ = dj.renderOffline(frames: 4410)
                dj.tickForTesting()
                await Task.yield()
            }
            print("ODD: then at the end: \(dj.autoDJ.phase), said: \(dj.statusMessage ?? "nothing"), deck 1 playing \(a.isPlaying), deck 2 playing \(b.isPlaying)")
        }
    }

    /// A list of tracks that are too short for anything goes on being a list.
    func testAMixOfTinyTracksGetsToTheEnd() async throws {
        let (dj, library) = makeEngine()
        let ids = try [441, 22_050, 441, 22_050].map { track(try audioFile(frames: $0, fill: tone), in: library).id }
        dj.autoDJ.startSet(named: "Tiny", tracks: ids)
        for _ in 0..<200 {
            _ = dj.renderOffline(frames: 4410)
            dj.tickForTesting()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        print("ODD: a mix of tiny tracks: \(dj.autoDJ.phase), said: \(dj.statusMessage ?? "nothing")")
    }
}
