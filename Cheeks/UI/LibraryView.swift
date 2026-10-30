import SwiftUI
import UniformTypeIdentifiers

/// Track browser: playlists, search, sort, harmonic-key hints and load-to-deck buttons.
struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    @State private var source: Source = .all
    @State private var search = ""
    @State private var sort: SortKey = .dateAdded
    @State private var importing = false
    @State private var importKind: ImportKind = .audio
    @State private var importMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    enum Source: Hashable { case all, playlist(UUID) }
    enum ImportKind { case audio, rekordbox }

    enum SortKey: String, CaseIterable, Identifiable {
        case dateAdded = "Date added", title = "Title", artist = "Artist", bpm = "BPM", key = "Key"
        var id: String { rawValue }
    }

    /// The deck the DJ is most likely mixing out of — used for key/BPM hints.
    private var referenceDeck: Deck? {
        dj.decks.first { $0.isPlaying } ?? dj.decks.first { $0.isLoaded }
    }

    private var tracks: [Track] {
        var list: [Track]
        switch source {
        case .all:
            list = library.tracks
        case .playlist(let id):
            let ids = library.playlists.first { $0.id == id }?.trackIDs ?? []
            list = ids.compactMap { library.track($0) }
        }
        if !search.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.artist.localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case .dateAdded: list.sort { $0.dateAdded > $1.dateAdded }
        case .title: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: list.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .bpm: list.sort { ($0.bpm ?? 0) < ($1.bpm ?? 0) }
        case .key: list.sort { ($0.key.flatMap { Camelot.parse($0)?.0 } ?? 99) < ($1.key.flatMap { Camelot.parse($0)?.0 } ?? 99) }
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 180)
            Rectangle().fill(Color.black).frame(width: 2)
            VStack(spacing: 0) {
                toolbar
                columnHeader
                if tracks.isEmpty {
                    emptyState
                } else {
                    // rekordbox's track table: alternating row shading, thin separators
                    List(Array(tracks.enumerated()), id: \.element.id) { row, track in
                        TrackRow(track: track, referenceDeck: referenceDeck, playlistID: playlistID)
                            .listRowBackground(row % 2 == 0 ? Theme.panel : Color(white: 0.11))
                            .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 8))
                            .listRowSeparatorTint(Color.black.opacity(0.6))
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 34)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(Theme.panel)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: importKind == .audio ? [.audio] : [.xml],
                      allowsMultipleSelection: importKind == .audio) { result in
            guard case .success(let urls) = result else { return }
            switch importKind {
            case .audio:
                for url in urls { library.importFile(at: url) }
            case .rekordbox:
                if let url = urls.first { importRekordbox(url) }
            }
        }
        .alert("New playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { library.createPlaylist(named: name) }
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    private func importRekordbox(_ url: URL) {
        // Big collections take a moment to parse, so keep it off the main thread.
        Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let collection = (try? Data(contentsOf: url)).flatMap(RekordboxCollection.parse)
            await MainActor.run {
                guard let collection else {
                    importMessage = "That file isn't a rekordbox collection XML."
                    return
                }
                let result = library.applyRekordbox(collection)
                importMessage = "Matched \(result.matched) of \(result.total) rekordbox tracks and imported \(result.playlists) playlists. "
                    + "Tracks are matched by file name, so import the audio files first."
            }
        }
    }

    private var playlistID: UUID? {
        if case .playlist(let id) = source { return id }
        return nil
    }

    private var sidebar: some View {
        List {
            Section {
                sidebarRow("All Tracks", icon: "music.note.list", count: library.tracks.count, tag: .all)
            } header: {
                sidebarHeader("Collection")
            }
            Section {
                ForEach(library.playlists) { playlist in
                    sidebarRow(playlist.name, icon: library.isHistory(playlist) ? "clock.arrow.circlepath" : "list.bullet",
                               count: playlist.trackIDs.count, tag: .playlist(playlist.id))
                        .contextMenu {
                            Button("Delete Playlist", role: .destructive) {
                                if source == .playlist(playlist.id) { source = .all }
                                library.deletePlaylist(playlist)
                            }
                        }
                }
                Button { showNewPlaylist = true } label: {
                    Label("New Playlist", systemImage: "plus").font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                sidebarHeader("Playlists")
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 32)
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.06))
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title.uppercased()).font(Theme.legend(10, .semibold)).foregroundStyle(Theme.dim)
    }

    private func sidebarRow(_ title: String, icon: String, count: Int, tag: Source) -> some View {
        Button { source = tag } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer()
                Text("\(count)").font(Theme.readout(11)).foregroundStyle(Theme.dim)
            }
            .font(.system(size: 12, weight: source == tag ? .semibold : .regular))
            .foregroundStyle(source == tag ? Color.white : Color.white.opacity(0.8))
        }
        .listRowBackground(source == tag ? Theme.accent.opacity(0.35) : Color.clear)
        .listRowSeparator(.hidden)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Search title or artist", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.raised))

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(Theme.legend(12))
                    .foregroundStyle(Theme.dim)
            }

            if let analyzing = library.analyzing, let t = library.track(analyzing) {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Analysing \(t.title)").lineLimit(1).font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: 160)
            }

            Menu {
                Button("Music files…", systemImage: "music.note") {
                    importKind = .audio
                    importing = true
                }
                Button("rekordbox library (XML)…", systemImage: "doc.text") {
                    importKind = .rekordbox
                    importing = true
                }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(Theme.legend(12, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.accent))
            }
        }
        .padding(6)
        .alert("rekordbox import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            Text("Artist").frame(maxWidth: .infinity, alignment: .leading)
            Text("BPM").frame(width: 50, alignment: .trailing)
            Text("Key").frame(width: 38)
            Text("Time").frame(width: 42, alignment: .trailing)
            Text("Load").frame(width: 76)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color(white: 0.14))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.house").font(.system(size: 36)).foregroundStyle(Theme.dim)
            Text(search.isEmpty ? "No tracks yet" : "No matches").font(.headline)
            Text("Tap Import to add music from Files, or drop audio files into the Cheeks folder in the Files app / Finder.")
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TrackRow: View {
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    let track: Track
    let referenceDeck: Deck?
    let playlistID: UUID?

    var body: some View {
        let compatible = referenceDeck?.track?.id != track.id && Camelot.isCompatible(track.key, referenceDeck?.track?.key)
        let loadedOn = dj.decks.first { $0.track?.id == track.id }
        HStack(spacing: 8) {
            Text(track.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(loadedOn != nil ? Theme.play : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                .font(.system(size: 12))
                .foregroundStyle(loadedOn != nil ? Theme.play : Theme.dim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.bpm.map { String(format: "%.2f", $0) } ?? "…")
                .font(Theme.readout(12))
                .frame(width: 50, alignment: .trailing)
            Text(track.key ?? "…")
                .font(Theme.readout(12, .semibold))
                .foregroundStyle(compatible ? Color.green : Color.white.opacity(0.8))
                .frame(width: 38)
            Text(track.duration > 0 ? track.duration.clockString : "")
                .font(Theme.readout(12))
                .foregroundStyle(Theme.dim)
                .frame(width: 42, alignment: .trailing)
            HStack(spacing: 4) {
                ForEach(dj.decks, id: \.index) { deck in
                    Button { deck.load(track) } label: {
                        Text("\(deck.index + 1)")
                            .font(Theme.legend(12, .semibold))
                            .frame(width: 34, height: 24)
                            .foregroundStyle(deck.isPlaying ? Theme.faint : .white)
                            .background(RoundedRectangle(cornerRadius: 3).fill(deck.isPlaying ? Theme.raised : Theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(deck.isPlaying) // never replace a playing track mid-set
                }
            }
            .frame(width: 76)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !library.playlists.isEmpty {
                Menu("Add to Playlist") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) { library.add(track.id, to: playlist.id) }
                    }
                }
            }
            if let playlistID {
                Button("Remove from Playlist") { library.remove(track.id, from: playlistID) }
            }
            Button("Re-analyse") { library.reanalyze(track) }
            Button("Delete from Library", role: .destructive) { library.delete(track) }
        }
    }
}
