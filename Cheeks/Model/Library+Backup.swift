import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Everything in the library that took work to make: grids, cues, loops, keys and playlists. The
/// music files aren't in it. They're already in the Files app, and they'd make a backup enormous.
struct LibraryBackup: Codable {
    var version = 1
    var exported = Date()
    var tracks: [Track]
    var playlists: [Playlist]
}

/// A backup as a file, for saving through the system's file picker.
struct LibraryBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Library {
    struct RestoreResult {
        var matched = 0
        var added = 0
        var playlists = 0
    }

    enum BackupError: Error { case unreadable }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Kept in Documents, so they show up in the Files app. They're deleted along with the app, so
    /// they protect against a bad library file, not a lost phone.
    static let backupDirectory: URL = {
        let dir = URL.documentsDirectory.appending(path: "Backups", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let automaticBackupsKept = 14

    func backupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(LibraryBackup(tracks: tracks, playlists: playlists))
    }

    var suggestedBackupName: String {
        "Cheeks Library \(Self.dayFormatter.string(from: Date()))"
    }

    /// Writes today's automatic copy if there isn't one yet, and clears out old ones.
    func writeAutomaticBackup(now: Date = Date()) {
        guard !tracks.isEmpty else { return }
        let url = Self.backupDirectory.appending(path: "Cheeks Library \(Self.dayFormatter.string(from: now)).json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? backupData() else { return }
        try? data.write(to: url, options: .atomic)
        pruneAutomaticBackups()
    }

    private func pruneAutomaticBackups() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.backupDirectory, includingPropertiesForKeys: nil)) ?? []
        let dated = files.filter { $0.lastPathComponent.hasPrefix("Cheeks Library ") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in dated.dropFirst(Self.automaticBackupsKept) { try? FileManager.default.removeItem(at: old) }
    }

    /// When the newest automatic copy was made, for the settings screen.
    var lastAutomaticBackup: Date? {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.backupDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    /// Merges a backup into the library. Tracks are matched by ID, then by their original file name,
    /// which covers restoring onto a fresh install where the music's been imported again. What's in
    /// the backup wins for those tracks. Tracks with no match come back as missing, and pick up
    /// their cues when their file is imported. A copy of the library as it was is kept first.
    @discardableResult
    func restore(from data: Data) throws -> RestoreResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(LibraryBackup.self, from: data) else { throw BackupError.unreadable }
        if !tracks.isEmpty, let safety = try? backupData() {
            let name = "Before restore \(Int(Date().timeIntervalSince1970)).json"
            try? safety.write(to: Self.backupDirectory.appending(path: name), options: .atomic)
        }

        var result = RestoreResult()
        var localIndexByName: [String: Int] = [:]
        for (i, track) in tracks.enumerated() {
            if let original = track.originalFileName { localIndexByName[original.lowercased()] = i }
        }
        var localIDForBackupID: [UUID: UUID] = [:]
        for saved in backup.tracks {
            let index = tracks.firstIndex { $0.id == saved.id } ?? saved.originalFileName.flatMap { localIndexByName[$0.lowercased()] }
            if let index {
                let local = tracks[index]
                let merged = Track(id: local.id, title: saved.title, artist: saved.artist, fileName: local.fileName,
                               originalFileName: local.originalFileName ?? saved.originalFileName,
                               duration: local.duration > 0 ? local.duration : saved.duration,
                               bpm: saved.bpm, firstBeat: saved.firstBeat, tempoMarkers: saved.tempoMarkers,
                               key: saved.key, loudness: saved.loudness, hotCues: saved.hotCues, hotCueInfo: saved.hotCueInfo,
                               memoryCues: saved.memoryCues, savedLoops: saved.savedLoops, phrases: saved.phrases,
                               rating: saved.rating, playCount: saved.playCount, dateAdded: saved.dateAdded)
                tracks[index] = merged
                localIDForBackupID[saved.id] = local.id
                result.matched += 1
            } else {
                tracks.append(saved)
                localIDForBackupID[saved.id] = saved.id
                result.added += 1
            }
        }
        for list in backup.playlists {
            let ids = list.trackIDs.compactMap { localIDForBackupID[$0] }
            if let existing = playlists.firstIndex(where: { $0.id == list.id || $0.name == list.name }) {
                playlists[existing].trackIDs = ids
            } else {
                playlists.append(Playlist(id: list.id, name: list.name, trackIDs: ids))
            }
            result.playlists += 1
        }
        refreshMissingFiles()
        save()
        return result
    }

    // MARK: Missing files

    /// Checks every track still has its audio file. Quick enough to do at launch for a big library.
    func refreshMissingFiles() {
        let manager = FileManager.default
        missingFiles = Set(tracks.filter { !manager.fileExists(atPath: url(for: $0).path) }.map(\.id))
    }

    func isMissing(_ track: Track) -> Bool { missingFiles.contains(track.id) }

    /// The track waiting for this file, if there is one: same original name, with no audio of its
    /// own. Importing the file brings the track back with its cues and grid.
    func trackAwaitingFile(named name: String) -> Track? {
        let lowered = name.lowercased()
        return tracks.first { $0.originalFileName?.lowercased() == lowered && missingFiles.contains($0.id) }
    }
}
