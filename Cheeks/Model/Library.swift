import AVFoundation
import Observation

/// The music collection: tracks copied into the app, their analysis, and playlists.
@MainActor
@Observable
final class Library {
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    private(set) var analyzing: UUID?
    /// Tracks whose audio file has gone. They stay in the list, and come back when the file's imported.
    var missingFiles: Set<UUID> = []
    /// Called when analysis has finished with a track, so a deck holding it can pick up the results.
    @ObservationIgnored var onAnalyzed: (@MainActor (UUID) -> Void)?
    /// A save didn't reach the disk. What was there's still there, as a write goes to a new file first.
    @ObservationIgnored var onSaveFailed: (@MainActor () -> Void)?
    #if DEBUG
    nonisolated(unsafe) static var savesFailForTesting = false
    #endif
    @ObservationIgnored private var whenReanalysed: [UUID: @MainActor (Track?) -> Void] = [:]
    private var analysisQueue: [UUID] = []
    /// Tracks that only need catching up with newer analysis. These wait while the decks are busy,
    /// so a big library can't heat the phone up in the middle of a set.
    private var catchUpQueue: [UUID] = []
    private var catchUpRetry: Task<Void, Never>?
    /// Whether a mix is going on right now.
    @ObservationIgnored var isBusy: (@MainActor () -> Bool)?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// One at a time and in order, so the last save is what's on disk. Off the main thread: writing out 2,000 tracks took 34 ms on a
    /// Mac every time a cue was saved or a track loaded, and a backup takes longer, in the middle of a set.
    @ObservationIgnored private let writes = DispatchQueue(label: "com.nikhilpatel.seguedj.library-writes", qos: .utility)

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "alac"]

    private nonisolated static let databaseURL = URL.applicationSupportDirectory.appending(path: "library.json")

    init() {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        load()
        refreshMissingFiles()
        importInbox()
        // Tracks from before phrase analysis get theirs too, one at a time in the background.
        for track in tracks where !isMissing(track) {
            if !track.isAnalyzed {
                enqueueAnalysis(track.id)
            } else if track.phrases == nil {
                enqueueCatchUp(track.id)
            }
        }
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
            guard !Task.isCancelled, let self else { return }
            self.pendingSave = nil
            self.writes.async(execute: self.writingWhatsHere())
        }
    }

    /// Writes before it returns, after anything still being written: call when the app goes to the background.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        writes.sync(execute: writingWhatsHere())
    }

    /// What's in the library as of now, as a job that doesn't need the main thread.
    private func writingWhatsHere() -> @Sendable () -> Void {
        let snapshot = Snapshot(tracks: tracks, playlists: playlists)
        return { [weak self] in
            do {
                #if DEBUG
                if Self.savesFailForTesting { throw CocoaError(.fileWriteOutOfSpace) }
                #endif
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: Self.databaseURL, options: .atomic)
                Self.writeAutomaticBackup(tracks: snapshot.tracks, playlists: snapshot.playlists)
            } catch {
                Task { @MainActor [weak self] in self?.onSaveFailed?() }
            }
        }
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
    /// What came of an import, for saying so: it can be a while before a track shows up, and nothing happening looks like failing.
    enum ImportOutcome {
        case added(UUID), alreadyThere(UUID), failed
    }

    @discardableResult
    func importFile(at source: URL, move: Bool = false) -> ImportOutcome {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        if let known = trackAlreadyImported(source) {
            if move { try? FileManager.default.removeItem(at: source) } // don't re-process it every launch
            return .alreadyThere(known)
        }
        let id = idForImporting(source)
        guard Self.bringIn(source, to: destination(of: source, id: id), move: move) else { return .failed }
        return broughtIn(source, id: id)
    }

    /// Files chosen in the picker, off the main thread: a copy's as long as the file, and longer if it's still in iCloud.
    /// They used to go one after another on the main thread, with everything stopped, music included if the render needed anything from it.
    func importFiles(_ sources: [URL], progress: (Int, Int) -> Void = { _, _ in }) async -> [ImportOutcome] {
        var outcomes: [ImportOutcome] = []
        for (index, source) in sources.enumerated() {
            if sources.count > 1 { progress(index + 1, sources.count) }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            if let known = trackAlreadyImported(source) {
                outcomes.append(.alreadyThere(known))
                continue
            }
            let id = idForImporting(source)
            let destination = destination(of: source, id: id)
            let arrived = await Task.detached(priority: .userInitiated) { Self.bringIn(source, to: destination, move: false) }.value
            outcomes.append(arrived ? broughtIn(source, id: id) : .failed)
        }
        return outcomes
    }

    /// A track restored from a backup, or whose file went missing, gets its audio back.
    private func idForImporting(_ source: URL) -> UUID {
        trackAwaitingFile(named: source.lastPathComponent)?.id ?? UUID()
    }

    private func destination(of source: URL, id: UUID) -> URL {
        LibraryFiles.musicDirectory.appending(path: "\(id.uuidString).\(source.pathExtension.lowercased())")
    }

    #if DEBUG
    nonisolated(unsafe) static var lastBroughtInOnTheMainThread = false
    #endif

    /// What can't be read is refused now, while whoever chose it can be told, and not when it's on a deck in the middle of a set.
    /// It's the call a load makes, so it's the same answer.
    private nonisolated static func bringIn(_ source: URL, to destination: URL, move: Bool) -> Bool {
        #if DEBUG
        lastBroughtInOnTheMainThread = Thread.isMainThread
        #endif
        guard let audio = try? AVAudioFile(forReading: source), audio.length > 0 else { return false }
        do {
            if move {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            return true
        } catch {
            return false
        }
    }

    private func broughtIn(_ source: URL, id: UUID) -> ImportOutcome {
        let fileName = destination(of: source, id: id).lastPathComponent
        if self.track(id) != nil {
            update(id) { $0.fileName = fileName }
            missingFiles.remove(id)
            return .added(id)
        }
        let title = source.deletingPathExtension().lastPathComponent
        tracks.append(Track(id: id, title: title, artist: "", fileName: fileName, originalFileName: source.lastPathComponent))
        save()
        Task { await loadMetadata(id) }
        enqueueAnalysis(id)
        return .added(id)
    }

    /// Same original name and byte size as a track we already have.
    private func trackAlreadyImported(_ source: URL) -> UUID? {
        let name = source.lastPathComponent
        guard let size = Self.fileSize(source) else { return nil }
        return tracks.first { $0.originalFileName == name && Self.fileSize(url(for: $0)) == size }?.id
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
        await ArtworkStore.extract(from: asset, id: id)
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
        ArtworkStore.delete(track.id)
        StemCache.shared.remove(track.id)
        tracks.removeAll { $0.id == track.id }
        missingFiles.remove(track.id)
        for i in playlists.indices { playlists[i].trackIDs.removeAll { $0 == track.id } }
        save()
    }

    // MARK: Analysis

    func enqueueAnalysis(_ id: UUID) {
        guard !analysisQueue.contains(id), analyzing != id else { return }
        analysisQueue.append(id)
        analyzeNext()
    }

    func enqueueCatchUp(_ id: UUID) {
        if !catchUpQueue.contains(id), !analysisQueue.contains(id), analyzing != id { catchUpQueue.append(id) }
        analyzeNext()
    }

    /// `then` hears how it came out, with nil if it couldn't be read. It said "Analysing … again" and never another word.
    func reanalyze(_ track: Track, then done: (@MainActor (Track?) -> Void)? = nil) {
        whenReanalysed[track.id] = done
        update(track.id) { t in
            t.bpm = nil
            t.key = nil
            t.tempoMarkers = nil
            t.gridSource = .analysis
            t.phrases = nil
        }
        enqueueAnalysis(track.id)
    }

    /// Analyses one track at a time in the background so the deck stays responsive.
    private func analyzeNext() {
        guard analyzing == nil else { return }
        let next: UUID
        if !analysisQueue.isEmpty {
            next = analysisQueue.removeFirst()
        } else if !catchUpQueue.isEmpty {
            guard isBusy?() != true else {
                retryCatchUpLater()
                return
            }
            next = catchUpQueue.removeFirst()
        } else {
            return
        }
        let id = next
        guard let track = self.track(id) else { analyzeNext(); return }
        analyzing = id
        let url = self.url(for: track)
        let knownGrid = track.grid
        Task.detached(priority: .utility) {
            let result = (try? AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)).map { TrackAnalyzer.analyze($0, knownGrid: knownGrid) }
            if let result {
                try? result.waveform.encoded().write(to: LibraryFiles.waveformURL(id), options: .atomic)
            }
            await MainActor.run {
                if let result {
                    // Don't overwrite a grid/key that arrived from an import while this was running.
                    self.update(id) { t in
                        guard t.bpm == nil else { return }
                        t.bpm = result.bpm
                        t.firstBeat = result.firstBeat
                        t.tempoMarkers = result.tempoMarkers
                        if t.key == nil { t.key = result.key }
                    }
                    self.update(id) { t in
                        t.loudness = result.loudness
                        t.phrases = result.phrases ?? t.phrases ?? []
                    }
                    self.onAnalyzed?(id)
                }
                self.whenReanalysed.removeValue(forKey: id)?(result == nil ? nil : self.track(id))
                self.analyzing = nil
                self.analyzeNext()
            }
        }
    }

    private func retryCatchUpLater() {
        guard catchUpRetry == nil else { return }
        catchUpRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.catchUpRetry = nil
            self?.analyzeNext()
        }
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(named name: String) -> UUID {
        let id = UUID()
        playlists.append(Playlist(id: id, name: name))
        save()
        return id
    }

    func add(_ trackID: UUID, to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[i].trackIDs.contains(trackID) else { return }
        playlists[i].trackIDs.append(trackID)
        save()
    }

    /// Several at once, in this order, written out once. Says how many weren't already there.
    @discardableResult
    func add(_ trackIDs: [UUID], to playlistID: UUID) -> [UUID] {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return [] }
        var there = Set(playlists[i].trackIDs)
        let new = trackIDs.filter { there.insert($0).inserted }
        guard !new.isEmpty else { return [] }
        playlists[i].trackIDs += new
        save()
        return new
    }

    /// Takes a track to this place in the playlist, counted as the list is before it moves.
    func move(_ trackID: UUID, in playlistID: UUID, to offset: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }),
              let from = playlists[i].trackIDs.firstIndex(of: trackID) else { return }
        playlists[i].trackIDs.move(fromOffsets: IndexSet(integer: from), toOffset: min(max(offset, 0), playlists[i].trackIDs.count))
        save()
    }

    /// Puts a playlist's tracks back as they were, for `UNDO`.
    func setTracks(_ trackIDs: [UUID], of playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs = trackIDs
        save()
    }

    func remove(_ trackID: UUID, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        save()
    }

    /// Several at once, written out once. One at a time, a whole list took thousands of passes over it on the main thread.
    func remove(_ trackIDs: [UUID], from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let going = Set(trackIDs)
        playlists[i].trackIDs.removeAll(where: going.contains)
        save()
    }

    func rename(_ playlist: Playlist, to name: String) {
        guard !name.isEmpty, let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].name = name
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
