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
    /// A capture that couldn't be converted is kept as "<name> (raw).caf" so it can still be shared.
    static let rawSuffix = " (raw).caf"
    /// Conversion writes "<name>.converting.<ext>" and renames it only once complete.
    static let convertingMarker = ".converting."
    static let audioExtensions: Set<String> = ["m4a", "wav", "caf"]
    /// 24-bit stereo at 44.1 kHz.
    static let bytesPerMinute: Double = 44_100 * 2 * 3 * 60

    /// "Mix 2026-10-28 22.30.05", with " 2", " 3"… if that name is already used — so a quick
    /// stop-and-restart can never overwrite the recording that's still being saved.
    static func newBaseName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stem = "Mix \(formatter.string(from: Date()))"
        var name = stem
        var n = 2
        while isTaken(name) {
            name = "\(stem) \(n)"
            n += 1
        }
        return name
    }

    private static func isTaken(_ base: String) -> Bool {
        let endings = [inProgressSuffix, rawSuffix, ".m4a", ".wav", "\(convertingMarker)m4a", "\(convertingMarker)wav"]
        return endings.contains { FileManager.default.fileExists(atPath: directory.appending(path: base + $0).path) }
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
            .filter { url in
                let name = url.lastPathComponent
                return audioExtensions.contains(url.pathExtension.lowercased())
                    && !name.hasSuffix(inProgressSuffix) && !name.contains(convertingMarker)
            }
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
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate = AudioConfig.sampleRate

    func start(url: URL, format: AVAudioFormat) throws {
        let newFile = try AVAudioFile(forWriting: url,
                                      settings: Recordings.pcmSettings(sampleRate: format.sampleRate, channels: format.channelCount),
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.withLock {
            file = newFile
            failed = false
            framesWritten = 0
            sampleRate = format.sampleRate
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file else { return }
            do {
                try file.write(from: buffer)
                framesWritten += AVAudioFramePosition(buffer.frameLength)
            } catch {
                // Usually the disk is full. Close what we have so it can still be saved.
                failed = true
                self.file = nil
            }
        }
    }

    var didFail: Bool { lock.withLock { failed } }

    /// Length of audio actually captured. Tracklist times use this rather than the wall clock,
    /// so they stay right if the engine was interrupted (e.g. by a phone call) mid-recording.
    var recordedSeconds: Double { lock.withLock { Double(framesWritten) / sampleRate } }

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
        var previous = -75
        for (i, e) in entries.enumerated() {
            // CUE frames are 1/75 s; indexes must increase, so tracks that started together are 1 s apart.
            let frames = max(Int(max(0, e.offset) * 75), previous + 75)
            previous = frames
            lines.append(String(format: "  TRACK %02d AUDIO", i + 1))
            lines.append("    TITLE \"\(clean(e.title))\"")
            if !e.artist.isEmpty { lines.append("    PERFORMER \"\(clean(e.artist))\"") }
            lines.append(String(format: "    INDEX 01 %02d:%02d:%02d", frames / 75 / 60, frames / 75 % 60, frames % 75))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum RecordingFinalizer {
    enum FinalizeError: Error {
        /// Nothing was captured; the empty file was removed.
        case empty
        /// Couldn't read or convert; the capture was kept as "<name> (raw).caf".
        case keptRaw
    }

    /// Converts a capture to the chosen format, writes its tracklist files, and only then removes
    /// the capture. `recovered` marks a file left behind by a crash or kill. Runs off the main thread.
    static func finalize(_ caf: URL, format: RecordingFormat, recovered: Bool) throws -> URL {
        // A file left by a crash can carry a stale data size (often 0) and still open, reading as
        // empty or short. Repair first so the whole capture is read.
        if recovered { repairCAF(caf) }
        var opened = try? AVAudioFile(forReading: caf)
        if opened == nil {
            repairCAF(caf)
            opened = try? AVAudioFile(forReading: caf)
        }
        let base = caf.lastPathComponent.replacingOccurrences(of: Recordings.inProgressSuffix, with: "")
        guard let reader = opened, reader.length > 0 else {
            if fileSize(caf) < 64 * 1024 { // header only: stopped before any audio arrived
                try? FileManager.default.removeItem(at: caf)
                try? FileManager.default.removeItem(at: Setlist.sidecarURL(forRecording: caf))
                throw FinalizeError.empty
            }
            keepRaw(caf, base: base)
            throw FinalizeError.keptRaw
        }

        let output = Recordings.directory.appending(path: "\(base).\(format.fileExtension)")
        let temp = Recordings.directory.appending(path: "\(base)\(Recordings.convertingMarker)\(format.fileExtension)")
        let processing = reader.processingFormat
        do {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: 65_536) else { throw FinalizeError.keptRaw }
            do {
                let writer = try AVAudioFile(forWriting: temp,
                                             settings: format.settings(sampleRate: processing.sampleRate, channels: processing.channelCount),
                                             commonFormat: processing.commonFormat, interleaved: processing.isInterleaved)
                while reader.framePosition < reader.length {
                    try reader.read(into: buffer)
                    if buffer.frameLength == 0 { break }
                    try writer.write(from: buffer)
                }
            } // writer is released (and its file finalised) here
            try FileManager.default.moveItem(at: temp, to: output)
        } catch {
            // Usually out of space. Keep the full-quality capture rather than a partial file.
            try? FileManager.default.removeItem(at: temp)
            keepRaw(caf, base: base)
            throw FinalizeError.keptRaw
        }

        writeTracklist(from: caf, next: output, title: base)
        try? FileManager.default.removeItem(at: caf)
        try? FileManager.default.removeItem(at: Setlist.sidecarURL(forRecording: caf))
        return output
    }

    /// Renames the capture to "<name> (raw).caf" (listed in Recordings, shareable) with its tracklist.
    private static func keepRaw(_ caf: URL, base: String) {
        let raw = Recordings.directory.appending(path: base + Recordings.rawSuffix)
        guard (try? FileManager.default.moveItem(at: caf, to: raw)) != nil else { return }
        writeTracklist(from: caf, next: raw, title: base)
        try? FileManager.default.removeItem(at: Setlist.sidecarURL(forRecording: caf))
    }

    private static func writeTracklist(from caf: URL, next audio: URL, title: String) {
        let entries = Setlist.load(forRecording: caf)
        guard !entries.isEmpty else { return }
        let companions = Recordings.companionFiles(for: audio)
        try? Setlist.text(entries, title: title).write(to: companions[0], atomically: true, encoding: .utf8)
        try? Setlist.cueSheet(entries, title: title, audioFileName: audio.lastPathComponent)
            .write(to: companions[1], atomically: true, encoding: .utf8)
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// If the app died before the CAF was closed, its data chunk may carry a stale size.
    /// CAF allows -1 ("runs to end of file") for the final chunk, so mark it that way.
    static func repairCAF(_ url: URL) {
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        guard let fileEnd = try? handle.seekToEnd(), (try? handle.seek(toOffset: 0)) != nil,
              let header = try? handle.read(upToCount: 8), header.prefix(4) == Data("caff".utf8) else { return }
        var offset: UInt64 = 8
        while let chunk = try? handle.read(upToCount: 12), chunk.count == 12 {
            let type = String(decoding: chunk.prefix(4), as: UTF8.self)
            let size = chunk.dropFirst(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } // big-endian Int64
            if type == "data" {
                try? handle.seek(toOffset: offset + 4)
                try? handle.write(contentsOf: Data(repeating: 0xFF, count: 8))
                return
            }
            // A corrupt size must not overflow or run past the file (that would crash every launch).
            let (afterHeader, overflowA) = offset.addingReportingOverflow(12)
            let (next, overflowB) = afterHeader.addingReportingOverflow(size)
            guard !overflowA, !overflowB, next <= fileEnd else { return }
            offset = next
            guard (try? handle.seek(toOffset: offset)) != nil else { return }
        }
    }
}
