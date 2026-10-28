import AVFoundation

enum RecordingFormat: String, CaseIterable, Identifiable {
    case aac = "AAC (small)"
    case wav = "WAV (lossless)"
    var id: String { rawValue }

    var fileExtension: String { self == .aac ? "m4a" : "wav" }

    func settings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        switch self {
        case .aac:
            [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
             AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: 256_000]
        case .wav:
            Recordings.pcmSettings(sampleRate: sampleRate, channels: channels)
        }
    }
}

/// Where recordings live (Documents/Recordings, visible in the Files app) and how they're named.
enum Recordings {
    static let directory: URL = {
        let dir = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A recording in progress is "<name>.recording.caf" with its tracklist in "<name>.recording.json".
    static let inProgressSuffix = ".recording.caf"
    static let audioExtensions: Set<String> = ["m4a", "wav"]
    /// 24-bit stereo at 44.1 kHz.
    static let bytesPerMinute: Double = 44_100 * 2 * 3 * 60

    static func newBaseName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Mix \(formatter.string(from: Date()))"
    }

    static func pcmSettings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
         AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
         AVLinearPCMIsNonInterleaved: false]
    }

    /// Finished recordings, newest first.
    static func list() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return items
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { creationDate($0) > creationDate($1) }
    }

    /// Recordings that never got finalised (the app was killed mid-set).
    static func unfinished() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.hasSuffix(inProgressSuffix) }
    }

    static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    /// Free space in minutes of 24-bit stereo audio.
    static func minutesOfStorageLeft() -> Double? {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Double(bytes) / bytesPerMinute
    }

    /// Text and CUE tracklists that sit next to a finished recording.
    static func companionFiles(for audio: URL) -> [URL] {
        let base = audio.deletingPathExtension()
        return [base.appendingPathExtension("txt"), base.appendingPathExtension("cue")]
    }
}

/// Writes the program bus from the tap thread to a 24-bit CAF. CAF stays recoverable if the
/// app is killed mid-set (see `RecordingFinalizer.repairCAF`); it's converted to the chosen
/// format when recording stops.
final class MixRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var failed = false

    func start(url: URL, format: AVAudioFormat) throws {
        let newFile = try AVAudioFile(forWriting: url,
                                      settings: Recordings.pcmSettings(sampleRate: format.sampleRate, channels: format.channelCount),
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.withLock {
            file = newFile
            failed = false
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file else { return }
            do {
                try file.write(from: buffer)
            } catch {
                // Usually the disk is full. Close what we have so it can still be saved.
                failed = true
                self.file = nil
            }
        }
    }

    var didFail: Bool { lock.withLock { failed } }

    /// Closes the file (AVAudioFile finalises its header when released).
    func stop() {
        lock.withLock { file = nil }
    }
}

struct SetlistEntry: Codable, Hashable {
    /// Seconds from the start of the recording.
    var offset: TimeInterval
    var title: String
    var artist: String
    var bpm: Double?
    var key: String?
}

enum Setlist {
    static func sidecarURL(forRecording caf: URL) -> URL {
        URL(fileURLWithPath: caf.path.replacingOccurrences(of: ".caf", with: ".json"))
    }

    static func save(_ entries: [SetlistEntry], forRecording caf: URL) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: sidecarURL(forRecording: caf), options: .atomic)
    }

    static func load(forRecording caf: URL) -> [SetlistEntry] {
        guard let data = try? Data(contentsOf: sidecarURL(forRecording: caf)) else { return [] }
        return (try? JSONDecoder().decode([SetlistEntry].self, from: data)) ?? []
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "00:00  Artist – Title  (128.0 BPM, 8A)" lines.
    static func text(_ entries: [SetlistEntry], title: String) -> String {
        var lines = [title, ""]
        for e in entries {
            var line = "\(timestamp(e.offset))  " + (e.artist.isEmpty ? e.title : "\(e.artist) – \(e.title)")
            let details = [e.bpm.map { String(format: "%.1f BPM", $0) }, e.key].compactMap { $0 }
            if !details.isEmpty { line += "  (\(details.joined(separator: ", ")))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// CUE sheet: gives chapter markers in players and mix-upload sites.
    static func cueSheet(_ entries: [SetlistEntry], title: String, audioFileName: String) -> String {
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'") }
        var lines = ["TITLE \"\(clean(title))\"", "PERFORMER \"Cheeks\"", "FILE \"\(clean(audioFileName))\" WAVE"]
        for (i, e) in entries.enumerated() {
            let frames = Int(max(0, e.offset) * 75) // CUE frames are 1/75 s
            lines.append(String(format: "  TRACK %02d AUDIO", i + 1))
            lines.append("    TITLE \"\(clean(e.title))\"")
            if !e.artist.isEmpty { lines.append("    PERFORMER \"\(clean(e.artist))\"") }
            lines.append(String(format: "    INDEX 01 %02d:%02d:%02d", frames / 75 / 60, frames / 75 % 60, frames % 75))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum RecordingFinalizer {
    enum FinalizeError: Error { case unreadable }

    /// Converts an in-progress CAF to the chosen format, writes its tracklist files, and removes
    /// the CAF and sidecar once everything is safely written. Runs off the main thread.
    static func finalize(_ caf: URL, format: RecordingFormat) throws -> URL {
        let reader: AVAudioFile
        if let file = try? AVAudioFile(forReading: caf) {
            reader = file
        } else {
            repairCAF(caf)
            guard let file = try? AVAudioFile(forReading: caf) else { throw FinalizeError.unreadable }
            reader = file
        }

        let base = caf.lastPathComponent.replacingOccurrences(of: Recordings.inProgressSuffix, with: "")
        let output = Recordings.directory.appending(path: "\(base).\(format.fileExtension)")
        let processing = reader.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: 65_536) else { throw FinalizeError.unreadable }
        do {
            let writer = try AVAudioFile(forWriting: output,
                                         settings: format.settings(sampleRate: processing.sampleRate, channels: processing.channelCount),
                                         commonFormat: processing.commonFormat, interleaved: processing.isInterleaved)
            while reader.framePosition < reader.length {
                try reader.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try writer.write(from: buffer)
            }
        } // writer is released (and its file finalised) here

        let entries = Setlist.load(forRecording: caf)
        if !entries.isEmpty {
            let companions = Recordings.companionFiles(for: output)
            try? Setlist.text(entries, title: base).write(to: companions[0], atomically: true, encoding: .utf8)
            try? Setlist.cueSheet(entries, title: base, audioFileName: output.lastPathComponent)
                .write(to: companions[1], atomically: true, encoding: .utf8)
        }
        try? FileManager.default.removeItem(at: caf)
        try? FileManager.default.removeItem(at: Setlist.sidecarURL(forRecording: caf))
        return output
    }

    /// If the app died before the CAF was closed, its data chunk may carry a stale size.
    /// CAF allows -1 ("runs to end of file") for the final chunk, so mark it that way.
    static func repairCAF(_ url: URL) {
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.prefix(4) == Data("caff".utf8) else { return }
        var offset: UInt64 = 8
        while let chunk = try? handle.read(upToCount: 12), chunk.count == 12 {
            let type = String(decoding: chunk.prefix(4), as: UTF8.self)
            let size = chunk.dropFirst(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } // big-endian Int64
            if type == "data" {
                try? handle.seek(toOffset: offset + 4)
                try? handle.write(contentsOf: Data(repeating: 0xFF, count: 8))
                return
            }
            offset += 12 + size
            guard (try? handle.seek(toOffset: offset)) != nil else { return }
        }
    }
}
