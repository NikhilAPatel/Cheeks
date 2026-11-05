import AVFoundation
import XCTest
@testable import Cheeks

/// A set is hours of loads, with a stem split on every one. Something kept per load would only show up as iOS killing the app, late on.
@MainActor
final class LongNightTests: XCTestCase {
    private var files: [URL] = []
    private var ids: [UUID] = []

    override func tearDown() async throws {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        ids.forEach { StemCache.shared.remove($0) }
    }

    private func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    private func makeTrack(in library: Library, seconds: Int, pitch: Double) throws -> Track {
        let id = UUID()
        ids.append(id)
        let url = LibraryFiles.musicDirectory.appending(path: "\(id.uuidString).wav")
        files.append(url)
        let sr = AudioConfig.sampleRate
        let frames = Int(sr) * seconds
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames {
            let v = 0.3 * Float(sin(2 * .pi * pitch * Double(i) / sr))
            buffer.floatChannelData![0][i] = v
            buffer.floatChannelData![1][i] = v
        }
        do {
            let audio = try AVAudioFile(forWriting: url, settings: format.settings)
            try audio.write(from: buffer)
        }
        // Already split, so this is about what's kept and not how long the model takes.
        let stems = Stem.allCases.map { _ -> PCM16Stereo in
            let stem = PCM16Stereo(frames: frames)
            for i in 0..<(frames * 2) { stem.data[i] = Int16(i % 64) }
            return stem
        }
        try StemCache.shared.store(id, stems: stems)
        let track = Track(id: id, title: "Track", artist: "", fileName: url.lastPathComponent, duration: Double(seconds), bpm: 124, firstBeat: 0, key: "8A", loudness: -11)
        library.tracks.append(track)
        return track
    }

    func testLoadingTrackAfterTrackDoesntGrow() async throws {
        let prepared = UserDefaults.standard.object(forKey: "prepareStemsOnLoad")
        UserDefaults.standard.set(true, forKey: "prepareStemsOnLoad")
        defer { UserDefaults.standard.set(prepared, forKey: "prepareStemsOnLoad") }

        let library = Library()
        library.tracks = []
        library.playlists = []
        library.missingFiles = []
        let dj = DJEngine(library: library)
        dj.stopRealtimeForTesting()
        let tracks = try (0..<4).map { try makeTrack(in: library, seconds: 60, pitch: 110 * Double($0 + 1)) }

        var settled: Int64 = 0
        let rounds = 40
        for round in 0..<rounds {
            let deck = dj.decks[round % 2]
            deck.pause()
            deck.load(tracks[round % tracks.count])
            for _ in 0..<1500 {
                if !deck.isLoading, case .ready = deck.stemStatus { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(deck.isLoading)
            guard case .ready = deck.stemStatus else { return XCTFail("Round \(round): \(deck.stemStatus)") }
            deck.play()
            for _ in 0..<5 {
                _ = dj.renderOffline(frames: 4410)
                dj.tickForTesting()
            }
            await Task.yield()
            // By now there's been time for what's kept for good, like a pad's picture or the shaders, to get made.
            if round == 12 { settled = footprint() }
        }
        let grew = footprint() - settled
        print(String(format: "MEMORY: %d more loads grew it by %.1f MB, from %.0f MB", rounds - 13, Double(grew) / 1_048_576, Double(settled) / 1_048_576))
        // Each track's stems alone are 42 MB, so keeping one load in five would be well over this.
        XCTAssertLessThan(grew, 60 << 20)
    }
}
