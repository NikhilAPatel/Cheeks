import SwiftUI
import UniformTypeIdentifiers

/// The track browser, like rekordbox's: a collection and playlists on the left, a dense sortable
/// table with artwork and preview waveforms, and hints for what mixes with what's playing.
struct BrowserView: View {
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    @State private var source: Source = .all
    @State private var search = ""
    @State private var sort: SortKey = .dateAdded
    @State private var ascending = false
    @State private var inKeyOnly = false
    @State private var nearBPMOnly = false
    @State private var importing = false
    @State private var importKind: ImportKind = .audio
    @State private var importMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @FocusState private var searchFocused: Bool

    enum Source: Hashable { case all, playlist(UUID) }
    enum ImportKind { case audio, rekordbox }

    enum SortKey: String, CaseIterable, Identifiable {
        case dateAdded = "Date added", title = "Title", artist = "Artist", bpm = "BPM", key = "Key", duration = "Time"
        var id: String { rawValue }
    }

    /// The deck the DJ is most likely mixing out of, for key and BPM hints.
    private var referenceDeck: Deck? {
        dj.decks[dj.masterIndex].isLoaded ? dj.decks[dj.masterIndex] : dj.decks.first { $0.isLoaded }
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
        if inKeyOnly, let key = referenceDeck?.effectiveKey {
            list = list.filter { Camelot.isCompatible($0.key, key) }
        }
        if nearBPMOnly, let bpm = referenceDeck?.effectiveBPM, bpm > 0 {
            list = list.filter { track in
                guard let t = track.bpm else { return false }
                return [t, t * 2, t / 2].contains { abs($0 - bpm) / bpm < 0.06 }
            }
        }
        // A plain sort on a key that's the same for many tracks is unstable; date breaks the ties.
        list.sort { a, b in
            let order: ComparisonResult
            switch sort {
            case .dateAdded: order = a.dateAdded == b.dateAdded ? .orderedSame : (a.dateAdded < b.dateAdded ? .orderedAscending : .orderedDescending)
            case .title: order = a.title.localizedCaseInsensitiveCompare(b.title)
            case .artist: order = a.artist.localizedCaseInsensitiveCompare(b.artist)
            case .bpm: order = compare(a.bpm ?? 0, b.bpm ?? 0)
            case .key: order = compare(a.key.flatMap { Camelot.sortValue($0) } ?? 99, b.key.flatMap { Camelot.sortValue($0) } ?? 99)
            case .duration: order = compare(a.duration, b.duration)
            }
            if order == .orderedSame { return a.dateAdded > b.dateAdded }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return list
    }

    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 148)
            Rectangle().fill(Color.black).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                columnHeader
                table
            }
        }
        .background(Color(white: 0.06))
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
        .alert("rekordbox import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    @ViewBuilder
    private var table: some View {
        let list = tracks
        if list.isEmpty {
            emptyState
        } else {
            List(Array(list.enumerated()), id: \.element.id) { row, track in
                TrackRow(track: track, referenceDeck: referenceDeck, playlistID: playlistID)
                    .listRowBackground(row % 2 == 0 ? Color(white: 0.07) : Color(white: 0.095))
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 36)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .animation(Theme.panel, value: list.map(\.id))
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
                dj.decks.forEach { $0.refreshTrack() }
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
                    sidebarRow(playlist.name, icon: library.isHistory(playlist) ? "clock.arrow.circlepath" : "music.note.list",
                               count: playlist.trackIDs.count, tag: .playlist(playlist.id))
                        .contextMenu {
                            Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                                if source == .playlist(playlist.id) { source = .all }
                                library.deletePlaylist(playlist)
                            }
                        }
                }
                Button { showNewPlaylist = true } label: {
                    Label("New Playlist", systemImage: "plus").font(Theme.text(11.5)).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                sidebarHeader("Playlists")
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 30)
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.045))
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title.uppercased()).silk(8.5, color: Theme.textTertiary)
    }

    private func sidebarRow(_ title: String, icon: String, count: Int, tag: Source) -> some View {
        Button {
            Haptics.shared.toggle(true)
            source = tag
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10)).frame(width: 14)
                    .foregroundStyle(source == tag ? Color.white : Theme.textSecondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(count)").font(Theme.digits(10)).foregroundStyle(Theme.textTertiary)
            }
            .font(Theme.text(11.5, source == tag ? .semibold : .regular))
            .foregroundStyle(source == tag ? Color.white : Theme.textPrimary.opacity(0.85))
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 8))
        .listRowBackground(source == tag ? Theme.accent.opacity(0.42) : Color.clear)
        .listRowSeparator(.hidden)
    }

    private var toolbar: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                TextField("Search title or artist", text: $search)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .font(Theme.text(12))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black))
            .animation(.easeOut(duration: 0.12), value: search.isEmpty)

            filterKey("IN KEY", isOn: $inKeyOnly, enabled: referenceDeck?.effectiveKey != nil)
            filterKey("±6% BPM", isOn: $nearBPMOnly, enabled: (referenceDeck?.effectiveBPM ?? 0) > 0)

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
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 10, weight: .semibold))
                    Text("IMPORT").font(Theme.silk(8.5))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(KeyFace(color: Theme.accent, lit: true))
            }
        }
        .padding(5)
    }

    private func filterKey(_ title: String, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Key(title, lit: isOn.wrappedValue && enabled, size: 8.5, feel: .toggle, isEnabled: enabled, onPress: {
            withAnimation(Theme.panel) { isOn.wrappedValue.toggle() }
        })
        .frame(width: 56, height: 24)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 28)
            Color.clear.frame(width: 90)
            header(.title, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            header(.artist, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            header(.bpm, alignment: .trailing).frame(width: 40, alignment: .trailing)
            header(.key, alignment: .center).frame(width: 30)
            header(.duration, alignment: .trailing).frame(width: 34, alignment: .trailing)
            Color.clear.frame(width: 62)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Color(white: 0.12))
    }

    /// Tap a column to sort by it; tap again to flip it, like Finder.
    private func header(_ key: SortKey, alignment: Alignment) -> some View {
        Button {
            Haptics.shared.tick()
            withAnimation(Theme.panel) {
                if sort == key { ascending.toggle() } else {
                    sort = key
                    ascending = key == .title || key == .artist || key == .key
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(key.rawValue.uppercased()).silk(8, color: sort == key ? Theme.textPrimary : Theme.textTertiary)
                if sort == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        Group {
            if library.tracks.isEmpty {
                ContentUnavailableView {
                    Label("No music yet", systemImage: "music.note.house")
                } description: {
                    Text("Tap Import to add music from Files, or drop audio into the Cheeks folder in the Files app or Finder.")
                }
            } else {
                ContentUnavailableView.search
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One track. Tap a number to load it, drag it onto a deck, or swipe it across.
struct TrackRow: View {
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    let track: Track
    let referenceDeck: Deck?
    let playlistID: UUID?

    var body: some View {
        let compatible = referenceDeck?.track?.id != track.id && Camelot.isCompatible(track.key, referenceDeck?.effectiveKey)
        let loadedOn = dj.decks.first { $0.track?.id == track.id }
        HStack(spacing: 8) {
            TrackArtwork(track: track).frame(width: 28, height: 28)
            TrackPreview(track: track).frame(width: 90, height: 24)
            HStack(spacing: 4) {
                if library.isMissing(track) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.warn)
                        .accessibilityLabel("File missing")
                }
                Text(track.title)
                    .font(Theme.text(12, .medium))
                    .foregroundStyle(library.isMissing(track) ? Theme.textTertiary : loadedOn != nil ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                .font(Theme.text(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.bpm.map { String(format: "%.1f", $0) } ?? "…")
                .font(Theme.digits(11.5))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, alignment: .trailing)
            keyChip(compatible: compatible)
            Text(track.duration > 0 ? track.duration.clockString : "")
                .font(Theme.digits(11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 34, alignment: .trailing)
            HStack(spacing: 3) {
                ForEach(dj.decks, id: \.index) { deck in
                    Key("\(deck.index + 1)", lit: deck.track?.id == track.id, size: 10.5, feel: .none, isEnabled: !deck.isPlaying,
                        onRefused: { dj.refuseLoad(onto: deck) }, onPress: {
                        _ = dj.load(track, onto: deck)
                    })
                    .frame(width: 29, height: 25)
                }
            }
            .frame(width: 62)
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .draggable(track.id.uuidString) {
            HStack(spacing: 8) {
                TrackArtwork(track: track).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(Theme.text(12, .semibold)).lineLimit(1)
                    Text(track.artist).font(Theme.text(10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(6)
            .frame(width: 210, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Deck 1") { _ = dj.load(track, onto: dj.decks[0]) }.tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Deck 2") { _ = dj.load(track, onto: dj.decks[1]) }.tint(Theme.accent)
        }
        .contextMenu {
            Button("Load on Deck 1", systemImage: "1.circle") { _ = dj.load(track, onto: dj.decks[0]) }
            Button("Load on Deck 2", systemImage: "2.circle") { _ = dj.load(track, onto: dj.decks[1]) }
            Divider()
            if !library.playlists.isEmpty {
                Menu("Add to Playlist", systemImage: "text.badge.plus") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) { library.add(track.id, to: playlist.id) }
                    }
                }
            }
            if let playlistID {
                Button("Remove from Playlist", systemImage: "minus.circle") { library.remove(track.id, from: playlistID) }
            }
            Button("Re-analyse", systemImage: "waveform.badge.magnifyingglass") { library.reanalyze(track) }
            Button("Delete from Library", systemImage: "trash", role: .destructive) { library.delete(track) }
        }
    }

    private func keyChip(compatible: Bool) -> some View {
        Text(track.key ?? "…")
            .font(Theme.digits(10.5))
            .foregroundStyle(compatible ? Color.black : Theme.keyColor(track.key))
            .frame(width: 30, height: 16)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(compatible ? Theme.keyColor(track.key) : Color.clear))
    }
}

/// A row's artwork, loaded on demand and cached.
struct TrackArtwork: View {
    let track: Track
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                GeneratedArt(title: track.title)
            }
        }
        .clipShape(shape)
        .task(id: track.id) {
            image = await ArtworkStore.thumbnail(track.id)
        }
    }
}

/// A row's whole-track waveform, drawn once, off the main thread, and cached.
struct TrackPreview: View {
    @Environment(DJEngine.self) private var dj
    let track: Track
    @State private var image: CGImage?

    var body: some View {
        let previewing = dj.previewingTrack == track.id
        ZStack {
            if let image {
                Image(decorative: image, scale: 3).resizable()
            } else {
                Rectangle().fill(Color.black.opacity(0.4))
            }
            if previewing {
                Color.black.opacity(0.35)
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    GeometryReader { geo in
                        Rectangle().fill(Color.white).frame(width: 1)
                            .offset(x: geo.size.width * dj.previewFraction)
                    }
                }
                Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        // Tap the waveform to audition the track: in the cue ear with a split cable, or quietly on the main output without one.
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.shared.toggle(!previewing)
            dj.togglePreview(track)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewing ? "Stop preview" : "Preview")
        .accessibilityAddTraits(.isButton)
        .task(id: track.bpm) {
            image = await WaveformThumbnails.image(track.id, width: 90 * 3, height: 24 * 3)
        }
    }
}
