import AVFoundation
import Observation

/// The music collection: tracks copied into the app, their analysis, and playlists.
@MainActor
@Observable
final class Library {
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    private(set) var analyzing: UUID?
    private var analysisQueue: [UUID] = []
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "alac"]

    private static let databaseURL = URL.applicationSupportDirectory.appending(path: "library.json")

    init() {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        load()
        importInbox()
        for track in tracks where !track.isAnalyzed { enqueueAnalysis(track.id) }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var tracks: [Track]
        var playlists: [Playlist]
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.databaseURL) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            tracks = snapshot.tracks
            playlists = snapshot.playlists
        } catch {
            // Never silently overwrite a library we couldn't read: keep a copy to recover from.
            let backup = URL.applicationSupportDirectory.appending(path: "library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: Self.databaseURL, to: backup)
        }
    }

    /// Saves shortly after the last change, so bursts (importing a folder, editing cues) write once.
    func save() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes immediately — call when the app goes to the background.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let data = try? JSONEncoder().encode(Snapshot(tracks: tracks, playlists: playlists)) else { return }
        try? data.write(to: Self.databaseURL, options: .atomic)
    }

    // MARK: Tracks

    func url(for track: Track) -> URL { LibraryFiles.musicDirectory.appending(path: track.fileName) }

    func track(_ id: UUID) -> Track? { tracks.first { $0.id == id } }

    func update(_ id: UUID, _ change: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        change(&tracks[index])
        save()
    }

    /// Moves in audio files that were dropped into the app's Documents folder (Files app / Finder).
    func importInbox() {
        let items = (try? FileManager.default.contentsOfDirectory(at: .documentsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in items where Self.audioExtensions.contains(url.pathExtension.lowercased()) {
            importFile(at: url, move: true)
        }
    }

    /// Copies a file picked in the Files app into the library and queues it for analysis.
    func importFile(at source: URL, move: Bool = false) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        if isAlreadyImported(source) {
            if move { try? FileManager.default.removeItem(at: source) } // don't re-process it every launch
            return
        }

        let id = UUID()
        let fileName = "\(id.uuidString).\(source.pathExtension.lowercased())"
        let destination = LibraryFiles.musicDirectory.appending(path: fileName)
        do {
            if move {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            return
        }
        let title = source.deletingPathExtension().lastPathComponent
        tracks.append(Track(id: id, title: title, artist: "", fileName: fileName, originalFileName: source.lastPathComponent))
        save()
        Task { await loadMetadata(id) }
        enqueueAnalysis(id)
    }

    /// Same original name and byte size as a track we already have.
    private func isAlreadyImported(_ source: URL) -> Bool {
        let name = source.lastPathComponent
        guard let size = Self.fileSize(source) else { return false }
        return tracks.contains { $0.originalFileName == name && Self.fileSize(url(for: $0)) == size }
    }

    private static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private func loadMetadata(_ id: UUID) async {
        guard let track = self.track(id) else { return }
        let asset = AVURLAsset(url: url(for: track))
        var title: String?
        var artist: String?
        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                if item.commonKey == .commonKeyTitle { title = try? await item.load(.stringValue) }
                if item.commonKey == .commonKeyArtist { artist = try? await item.load(.stringValue) }
            }
        }
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        update(id) { t in
            if let title, !title.isEmpty { t.title = title }
            if let artist { t.artist = artist }
            if duration.isFinite { t.duration = duration }
        }
    }

    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: url(for: track))
        try? FileManager.default.removeItem(at: LibraryFiles.waveformURL(track.id))
        tracks.removeAll { $0.id == track.id }
        for i in playlists.indices { playlists[i].trackIDs.removeAll { $0 == track.id } }
        save()
    }

    // MARK: Analysis

    func enqueueAnalysis(_ id: UUID) {
        guard !analysisQueue.contains(id), analyzing != id else { return }
        analysisQueue.append(id)
        analyzeNext()
    }

    func reanalyze(_ track: Track) {
        update(track.id) { $0.bpm = nil; $0.key = nil }
        enqueueAnalysis(track.id)
    }

    /// Analyses one track at a time in the background so the deck stays responsive.
    private func analyzeNext() {
        guard analyzing == nil, !analysisQueue.isEmpty else { return }
        let id = analysisQueue.removeFirst()
        guard let track = self.track(id) else { analyzeNext(); return }
        analyzing = id
        let url = self.url(for: track)
        Task.detached(priority: .utility) {
            let result = (try? AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)).map(TrackAnalyzer.analyze)
            if let result {
                try? result.waveform.encoded().write(to: LibraryFiles.waveformURL(id), options: .atomic)
            }
            await MainActor.run {
                if let result {
                    // Don't overwrite a grid/key that arrived from rekordbox while this was running.
                    self.update(id) { t in
                        guard t.bpm == nil else { return }
                        t.bpm = result.bpm
                        t.firstBeat = result.firstBeat
                        if t.key == nil { t.key = result.key }
                    }
                }
                self.analyzing = nil
                self.analyzeNext()
            }
        }
    }

    // MARK: Playlists

    func createPlaylist(named name: String) {
        playlists.append(Playlist(id: UUID(), name: name))
        save()
    }

    func add(_ trackID: UUID, to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[i].trackIDs.contains(trackID) else { return }
        playlists[i].trackIDs.append(trackID)
        save()
    }

    func remove(_ trackID: UUID, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        save()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }
}

/// On-disk locations. Kept outside the main-actor `Library` so background tasks can use them.
enum LibraryFiles {
    static let musicDirectory: URL = {
        let dir = URL.documentsDirectory.appending(path: "Music", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let waveformDirectory: URL = {
        let dir = URL.cachesDirectory.appending(path: "Waveforms", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func waveformURL(_ id: UUID) -> URL { waveformDirectory.appending(path: "\(id.uuidString).wave") }

    static func cachedWaveform(_ id: UUID) -> WaveformData? {
        (try? Data(contentsOf: waveformURL(id))).flatMap(WaveformData.init(data:))
    }
}
