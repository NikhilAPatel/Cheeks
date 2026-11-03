import SwiftUI
import UniformTypeIdentifiers

/// The track browser: a collection and playlists on the left, a dense sortable
/// table with artwork and preview waveforms, and hints for what mixes with what's playing.
struct BrowserView: View {
    @Environment(\.screenLayout) private var layout
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    // How the list is showing is worth keeping: the browser closes every time someone goes back to the decks.
    @AppStorage("browserPlaylist") private var chosenPlaylist = ""
    @State private var search = ""
    @AppStorage("browserSort") private var sort: SortKey = .dateAdded
    @AppStorage("browserAscending") private var ascending = false
    @AppStorage("browserInKey") private var inKeyOnly = false
    @AppStorage("browserNearBPM") private var nearBPMOnly = false
    @AppStorage("browserNext") private var bestNext = false
    @State private var importing = false
    @State private var importKind: ImportKind = .audio
    @State private var importMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @FocusState private var searchFocused: Bool

    enum Source: Hashable { case all, playlist(UUID) }
    enum ImportKind { case audio, djLibrary }

    enum SortKey: String, CaseIterable, Identifiable {
        case dateAdded = "Date added", title = "Title", artist = "Artist", bpm = "BPM", key = "Key", duration = "Time"
        var id: String { rawValue }
    }

    /// The playlist showing, or everything if it's been deleted since.
    private var source: Source {
        get {
            guard let id = UUID(uuidString: chosenPlaylist), library.playlists.contains(where: { $0.id == id }) else { return .all }
            return .playlist(id)
        }
        nonmutating set {
            if case .playlist(let id) = newValue { chosenPlaylist = id.uuidString } else { chosenPlaylist = "" }
        }
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
        // A playlist stays in the order it was built, which is the order MIX plays it in, until someone asks for a column.
        let keepsItsOrder = playlistID != nil && sort == .dateAdded
        // A plain sort on a key that's the same for many tracks is unstable; date breaks the ties.
        if !keepsItsOrder { list.sort { a, b in
            let order: ComparisonResult
            switch sort {
            case .dateAdded: order = a.dateAdded == b.dateAdded ? .orderedSame : (a.dateAdded < b.dateAdded ? .orderedAscending : .orderedDescending)
            case .title: order = a.title.localizedCaseInsensitiveCompare(b.title)
            case .artist: order = a.artist.localizedCaseInsensitiveCompare(b.artist)
            case .bpm: order = compare(a.bpm ?? 0, b.bpm ?? 0)
            case .key: order = compare(a.key.flatMap { Camelot.sortValue($0) } ?? 99, b.key.flatMap { Camelot.sortValue($0) } ?? 99)
            case .duration: order = compare(a.duration, b.duration)
            }
            if order == .orderedSame { return a.dateAdded == b.dateAdded ? a.id.uuidString < b.id.uuidString : a.dateAdded > b.dateAdded }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        } }
        guard bestNext else { return list }
        // The best way on from what's playing, which isn't on the list: it can't come next after itself.
        let deck = referenceDeck
        let place = deck.map { SetOrder.Place(bpm: $0.effectiveBPM > 0 ? $0.effectiveBPM : nil, key: $0.effectiveKey) }
        return SetOrder.order(list.filter { $0.id != deck?.track?.id }, from: place, bpm: \.bpm, key: \.key)
    }

    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Held upright, a phone's only got room for the list. Its sources are in a menu instead.
            if layout != .portrait {
                sidebar.frame(width: layout.isCompact ? 118 : 148)
                Rectangle().fill(Color.black).frame(width: 1)
            }
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
            case .djLibrary:
                if let url = urls.first { importDJLibrary(url) }
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
        .alert("Library import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
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

    private func importDJLibrary(_ url: URL) {
        // Big collections take a moment to parse, so keep it off the main thread.
        Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let collection = (try? Data(contentsOf: url)).flatMap(DJLibraryCollection.parse)
            await MainActor.run {
                guard let collection else {
                    importMessage = "That file isn't a DJ library export in XML."
                    return
                }
                let result = library.applyDJLibrary(collection)
                dj.decks.forEach { $0.refreshTrack() }
                importMessage = "Matched \(result.matched) of \(Format.count(result.total, "library track")) and imported \(Format.count(result.playlists, "playlist")). "
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

            filterKey(layout == .portrait ? "KEY" : "IN KEY", isOn: $inKeyOnly, enabled: referenceDeck?.effectiveKey != nil)
            filterKey(layout == .portrait ? "±6%" : "±6% BPM", isOn: $nearBPMOnly, enabled: (referenceDeck?.effectiveBPM ?? 0) > 0)
            filterKey("NEXT", isOn: $bestNext, enabled: true, accessibilityName: "Best next first")
            mixKey

            if layout == .portrait { sourceMenu }

            Menu {
                Button("Music files…", systemImage: "music.note") {
                    importKind = .audio
                    importing = true
                }
                Button("DJ library (XML)…", systemImage: "doc.text") {
                    importKind = .djLibrary
                    importing = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 10, weight: .semibold))
                    if layout != .portrait { Text("IMPORT").font(Theme.silk(8.5)) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(KeyFace(color: Theme.accent, lit: true))
            }
        }
        .padding(5)
    }

    private func filterKey(_ title: String, isOn: Binding<Bool>, enabled: Bool, accessibilityName: String? = nil) -> some View {
        Key(title, lit: isOn.wrappedValue && enabled, size: 8.5, feel: .toggle, isEnabled: enabled, accessibilityName: accessibilityName ?? title, onPress: {
            withAnimation(Theme.panel) { isOn.wrappedValue.toggle() }
        })
        .frame(width: layout == .portrait ? 36 : 56, height: 24)
    }

    /// Auto DJ through the list on screen, in the order it's showing. Pressing it again stops the mix.
    private var mixKey: some View {
        let auto = dj.autoDJ!
        let on = auto.mixSet != nil
        return Key("MIX", lit: on, size: 8.5, feel: .toggle, accessibilityName: on ? "Stop the mix" : "Mix through this list", onPress: {
            if on {
                auto.press()
            } else {
                auto.startSet(named: sourceName, tracks: tracks.map(\.id))
            }
        })
        .frame(width: 36, height: 24)
    }

    private var sourceName: String {
        guard case .playlist(let id) = source, let playlist = library.playlists.first(where: { $0.id == id }) else { return "all your tracks" }
        return playlist.name
    }

    /// Where the sidebar's sources go on a phone held upright.
    private var sourceMenu: some View {
        Menu {
            Button("All tracks", systemImage: "music.note.list") { source = .all }
            ForEach(library.playlists) { playlist in
                Button(playlist.name, systemImage: "music.note") { source = .playlist(playlist.id) }
            }
            Button("New playlist…", systemImage: "plus") { showNewPlaylist = true }
        } label: {
            Image(systemName: "sidebar.left").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 24)
                .background(KeyFace(color: Theme.accent, lit: source != .all))
        }
        .accessibilityLabel("Playlists")
    }

    /// The title gets what's left: it's the column you read.
    static let artistWidth: CGFloat = 110

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 28)
            if !layout.isCompact { Color.clear.frame(width: 90) }
            header(.title, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            if !layout.isCompact { header(.artist, alignment: .leading).frame(width: Self.artistWidth, alignment: .leading) }
            header(.bpm, alignment: .trailing).frame(width: 40, alignment: .trailing)
            header(.key, alignment: .center).frame(width: 30)
            if layout != .portrait { header(.duration, alignment: .trailing).frame(width: 34, alignment: .trailing) }
            Color.clear.frame(width: 62)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Color(white: 0.12))
    }

    /// Tap a column to sort by it, tap again to flip it, and a third time to go back to the list's own order.
    private func header(_ key: SortKey, alignment: Alignment) -> some View {
        Button {
            Haptics.shared.tick()
            withAnimation(Theme.panel) {
                let firstWay = key == .title || key == .artist || key == .key
                if sort != key {
                    sort = key
                    ascending = firstWay
                } else if !bestNext {
                    if ascending == firstWay {
                        ascending.toggle()
                    } else {
                        sort = .dateAdded
                        ascending = false
                    }
                }
                // Asking for a column says what order's wanted, so it takes over from NEXT.
                bestNext = false
            }
        } label: {
            let current = sort == key && !bestNext
            HStack(spacing: 2) {
                Text(key.rawValue.uppercased()).silk(8, color: current ? Theme.textPrimary : Theme.textTertiary)
                if current {
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
            } else if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if inKeyOnly || nearBPMOnly {
                ContentUnavailableView("Nothing fits right now", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Nothing here is in key or close in tempo with what's on the deck. Turn off IN KEY or ±6% BPM to see the rest."))
            } else {
                ContentUnavailableView("Nothing in this playlist yet", systemImage: "music.note.list",
                                       description: Text("Go to All Tracks, press and hold a track, and add it from there."))
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
    @Environment(\.screenLayout) private var layout

    var body: some View {
        let compatible = referenceDeck?.track?.id != track.id && Camelot.isCompatible(track.key, referenceDeck?.effectiveKey)
        let loadedOn = dj.decks.first { $0.track?.id == track.id }
        HStack(spacing: 8) {
            TrackArtwork(track: track).frame(width: 28, height: 28)
            if !layout.isCompact { TrackPreview(track: track).frame(width: 90, height: 24) }
            VStack(alignment: .leading, spacing: 0) {
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
            // On a phone the artist goes under the title, which gives the title the width.
            if layout.isCompact {
                Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                    .font(Theme.text(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !layout.isCompact {
                Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: BrowserView.artistWidth, alignment: .leading)
            }
            Text(track.bpm.map { String(format: "%.1f", $0) } ?? "…")
                .font(Theme.digits(11.5))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, alignment: .trailing)
            keyChip(compatible: compatible)
            if layout != .portrait {
                Text(track.duration > 0 ? track.duration.clockString : "")
                    .font(Theme.digits(11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 34, alignment: .trailing)
            }
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
