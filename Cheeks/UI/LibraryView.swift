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
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    enum Source: Hashable { case all, playlist(UUID) }

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
            sidebar.frame(width: 190)
            Divider().overlay(Theme.stroke)
            VStack(spacing: 0) {
                toolbar
                columnHeader
                if tracks.isEmpty {
                    emptyState
                } else {
                    List(tracks) { track in
                        TrackRow(track: track, referenceDeck: referenceDeck, playlistID: playlistID)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { library.importFile(at: url) }
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

    private var playlistID: UUID? {
        if case .playlist(let id) = source { return id }
        return nil
    }

    private var sidebar: some View {
        List {
            Section("Collection") {
                sidebarRow("All Tracks", icon: "music.note.list", count: library.tracks.count, tag: .all)
            }
            Section {
                ForEach(library.playlists) { playlist in
                    sidebarRow(playlist.name, icon: "list.bullet", count: playlist.trackIDs.count, tag: .playlist(playlist.id))
                        .contextMenu {
                            Button("Delete Playlist", role: .destructive) {
                                if source == .playlist(playlist.id) { source = .all }
                                library.deletePlaylist(playlist)
                            }
                        }
                }
                Button { showNewPlaylist = true } label: {
                    Label("New Playlist", systemImage: "plus").font(.system(size: 13))
                }
            } header: {
                Text("Playlists")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarRow(_ title: String, icon: String, count: Int, tag: Source) -> some View {
        Button { source = tag } label: {
            HStack {
                Label(title, systemImage: icon).lineLimit(1)
                Spacer()
                Text("\(count)").foregroundStyle(Theme.dim)
            }
            .font(.system(size: 13, weight: source == tag ? .bold : .regular))
            .foregroundStyle(source == tag ? Color.white : Color.white.opacity(0.75))
        }
        .listRowBackground(source == tag ? Color.white.opacity(0.1) : Color.clear)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("Search title or artist", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.system(size: 12, weight: .semibold))
            }

            if let analyzing = library.analyzing, let t = library.track(analyzing) {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Analysing \(t.title)").lineLimit(1).font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: 160)
            }

            Button { importing = true } label: {
                Label("Import", systemImage: "square.and.arrow.down").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.deckColors[0])
        }
        .padding(8)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("TITLE / ARTIST").frame(maxWidth: .infinity, alignment: .leading)
            Text("BPM").frame(width: 50, alignment: .trailing)
            Text("KEY").frame(width: 38)
            Text("TIME").frame(width: 42, alignment: .trailing)
            Text("LOAD").frame(width: 76)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(loadedOn.map { Theme.deckColors[$0.index] } ?? .white)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.bpm.map { String(format: "%.1f", $0) } ?? "…")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            Text(track.key ?? "…")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(compatible ? Color.green : Color.white.opacity(0.8))
                .frame(width: 38)
            Text(track.duration > 0 ? track.duration.clockString : "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: 42, alignment: .trailing)
            HStack(spacing: 4) {
                ForEach(dj.decks, id: \.index) { deck in
                    Button { deck.load(track) } label: {
                        Text("\(deck.index + 1)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .frame(width: 34, height: 26)
                            .foregroundStyle(.black)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.deckColors[deck.index].opacity(deck.isPlaying ? 0.25 : 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(deck.isPlaying) // never replace a playing track mid-set
                }
            }
            .frame(width: 76)
        }
        .padding(.vertical, 3)
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
