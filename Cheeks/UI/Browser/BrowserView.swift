import SwiftUI
import UniformTypeIdentifiers

/// The track browser: a collection and playlists on the left, a dense sortable
/// table with artwork and preview waveforms, and hints for what mixes with what's playing.
struct BrowserView: View {
    @Environment(\.screenLayout) private var layout
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    /// It stays built while the decks are showing, and has no reason to follow them or sort anything until it's back.
    var isOpen = true
    /// Only the list makes way for a keyboard, and only for its own search's. The file picker's search counts as a
    /// keyboard too, and it used to push the whole browser out of shape behind the picker.
    var keyboardHeight: CGFloat = 0
    @State private var lastList = LastList()
    // How the list is showing is worth keeping: the browser closes every time someone goes back to the decks.
    @AppStorage("browserPlaylist") private var chosenPlaylist = ""
    @State private var search = ""
    @AppStorage("browserSort") private var sort: SortKey = .dateAdded
    @AppStorage("browserAscending") private var ascending = false
    /// All Tracks' sort, while a playlist's showing in its own order.
    @AppStorage("browserAllSort") private var allSort: SortKey = .dateAdded
    @AppStorage("browserAllAscending") private var allAscending = false
    @AppStorage("browserInKey") private var inKeyOnly = false
    @AppStorage("browserNearBPM") private var nearBPMOnly = false
    @AppStorage("browserNext") private var bestNext = false
    /// What NEXT's order is going by, which catches up a moment after anything changes it.
    @State private var nextFrom: NextFrom?
    @State private var importing = false
    @State private var importKind: ImportKind = .audio
    @State private var importMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var renamingPlaylist: Playlist?
    @State private var renamedPlaylistName = ""
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
        guard isOpen else { return nil }
        return dj.decks[dj.masterIndex].isLoaded ? dj.decks[dj.masterIndex] : dj.decks.first { $0.isLoaded }
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
        let from = nextFrom ?? nextFromNow
        return SetOrder.order(list.filter { $0.id != from.track }, from: from.place, heard: { from.onADeck.contains($0.id) || from.heard.contains($0.id) }, bpm: \.bpm, key: \.key)
    }

    /// What decides NEXT's order. A load changes it, and straight away that moved the list under the next press, which landed on
    /// another row. So the list keeps its order until this has settled for a couple of seconds.
    private struct NextFrom: Equatable {
        var place: SetOrder.Place?
        var track: UUID?
        var onADeck: Set<UUID>
        var heard: Set<UUID>
    }

    private var nextFromNow: NextFrom {
        let deck = referenceDeck
        // To a tenth, as a synced deck's tempo can wander in its last few places.
        let place = deck.map { SetOrder.Place(bpm: $0.effectiveBPM > 0 ? ($0.effectiveBPM * 10).rounded() / 10 : nil, key: $0.effectiveKey) }
        return NextFrom(place: place, track: deck?.track?.id, onADeck: Set(dj.decks.compactMap { $0.track?.id }), heard: dj.heardThisSession)
    }

    private func catchUpWithNext() async {
        guard isOpen, bestNext else {
            nextFrom = nil
            return
        }
        let now = nextFromNow
        guard let held = nextFrom else {
            nextFrom = now
            return
        }
        guard held != now else { return }
        try? await Task.sleep(for: .seconds(2))
        if !Task.isCancelled { nextFrom = now }
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
                // Over the list and not above it, so nothing moves under a finger when a mix starts or ends.
                table.safeAreaInset(edge: .bottom, spacing: 0) { mixLine }
            }
        }
        .background(Color(white: 0.06))
        .padding(.bottom, searchFocused ? keyboardHeight : 0)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: importKind == .audio ? [.audio] : [.xml],
                      allowsMultipleSelection: importKind == .audio) { result in
            guard case .success(let urls) = result else { return }
            switch importKind {
            case .audio:
                sayWhatCameOf(urls.map { library.importFile(at: $0) })
            case .djLibrary:
                if let url = urls.first { importDJLibrary(url) }
            }
        }
        .alert("New playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                // Straight into it, or nothing on the screen says anything happened.
                if !name.isEmpty { source = .playlist(library.createPlaylist(named: name)) }
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
        .alert("Library import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .alert("Rename playlist", isPresented: Binding(get: { renamingPlaylist != nil }, set: { if !$0 { renamingPlaylist = nil } }),
               presenting: renamingPlaylist) { playlist in
            TextField("Name", text: $renamedPlaylistName)
            Button("Rename") { library.rename(playlist, to: renamedPlaylistName.trimmingCharacters(in: .whitespaces)) }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: isOpen && bestNext ? nextFromNow : nil) { await catchUpWithNext() }
        // A playlist opens in the order it was built, which is the order MIX plays, whatever All Tracks was sorted by. A
        // first-time user's built order had gone from view, with nothing to say why. All Tracks gets its own sort back.
        .onChange(of: chosenPlaylist) { old, new in
            if old.isEmpty {
                allSort = sort
                allAscending = ascending
            }
            if new.isEmpty {
                sort = allSort
                ascending = allAscending
            } else {
                sort = .dateAdded
                ascending = false
            }
        }
        // It used to go away and come back empty. A search left behind would hide tracks the next time.
        .onChange(of: isOpen) { _, open in
            guard !open else { return }
            search = ""
            searchFocused = false
        }
    }

    /// Importing while looking at a playlist puts them in it. It used to go on saying the playlist was empty, and looked as if it had failed.
    private func sayWhatCameOf(_ outcomes: [Library.ImportOutcome]) {
        let added = outcomes.compactMap { if case .added(let id) = $0 { id } else { nil } }
        let thereAlready = outcomes.compactMap { if case .alreadyThere(let id) = $0 { id } else { nil } }
        // A track you've already got still goes in the playlist you're importing into: that's what was asked for.
        if let playlistID, !library.playlists.contains(where: { $0.id == playlistID && library.isHistory($0) }) {
            (added + thereAlready).forEach { library.add($0, to: playlistID) }
            if added.isEmpty, !thereAlready.isEmpty {
                dj.say("Added \(Format.count(thereAlready.count, "track")) you already had to this playlist.", .done)
                return
            }
        }
        if !added.isEmpty {
            let also = !thereAlready.isEmpty ? " \(Format.count(thereAlready.count, "track")) already in your library." : ""
            dj.say("Added \(Format.count(added.count, "track")).\(also)", .done)
        } else if !thereAlready.isEmpty {
            dj.say(thereAlready.count == 1 ? "That track's already in your library." : "Those tracks are already in your library.", .info)
        } else {
            dj.say("That file couldn't be imported.", .problem)
        }
    }

    /// What the list last showed. A plain box, so that keeping it doesn't ask for another update.
    private final class LastList {
        var tracks: [Track]?
    }

    @ViewBuilder
    private var table: some View {
        let list = isOpen ? tracks : (lastList.tracks ?? tracks)
        // Animating a change to a long list freezes the screen for half a second, with a dim row of the old list showing.
        let isLong = max(list.count, lastList.tracks?.count ?? 0) > 200
        let _ = lastList.tracks = list
        if list.isEmpty {
            emptyState
        } else {
            let rows = Row.rows(of: list, canRepeat: playlistID != nil)
            ScrollViewReader { proxy in
                List(rows) { row in
                    TrackRow(track: row.track, referenceDeck: referenceDeck, playlistID: playlistID)
                        .listRowBackground(row.number % 2 == 0 ? Color(white: 0.07) : Color(white: 0.095))
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 36)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .background(StaysWhereItIs())
                .animation(isLong ? nil : Theme.panel, value: isLong ? [] : list.map(\.id))
                .transaction { if isLong { $0.animation = nil } }
                // A different list starts from its top. Now the list keeps its place, a search from far down opened part-way through its results.
                .onChange(of: whatsListed) { _, _ in
                    if let first = rows.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
        }
    }

    /// A row of the list. History can have a track in it twice, so a track isn't enough to tell rows apart: SwiftUI said so in
    /// the log, and its lists can misbehave with that.
    struct Row: Identifiable {
        struct ID: Hashable {
            let track: UUID
            let time: Int
        }

        let id: ID
        let number: Int
        let track: Track

        static func rows(of list: [Track], canRepeat: Bool) -> [Row] {
            // Only a playlist can repeat, and All Tracks can be thousands long.
            guard canRepeat else { return list.enumerated().map { Row(id: ID(track: $1.id, time: 0), number: $0, track: $1) } }
            var seen: [UUID: Int] = [:]
            return list.enumerated().map { number, track in
                let time = seen[track.id, default: 0]
                seen[track.id] = time + 1
                return Row(id: ID(track: track.id, time: time), number: number, track: track)
            }
        }
    }

    /// What decides which tracks are on the list, and in what order.
    private var whatsListed: [String] {
        [chosenPlaylist, search, sort.rawValue, "\(ascending)", "\(inKeyOnly)", "\(nearBPMOnly)", "\(bestNext)"]
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
                    sidebarRow(library.shownName(of: playlist), icon: library.isHistory(playlist) ? "clock.arrow.circlepath" : "music.note.list",
                               count: playlist.trackIDs.count, tag: .playlist(playlist.id))
                        .contextMenu { playlistActions(playlist) }
                }
                Button { showNewPlaylist = true } label: {
                    Label("New Playlist", systemImage: "plus").font(Theme.text(11.5)).foregroundStyle(Theme.textSecondary)
                }
                .disabled(WhatsThis.shared.isOn)
                .whatsThis("Playlists")
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

    @ViewBuilder
    private func playlistActions(_ playlist: Playlist) -> some View {
        if !library.isHistory(playlist) {
            Button("Rename Playlist", systemImage: "pencil") {
                renamedPlaylistName = playlist.name
                renamingPlaylist = playlist
            }
        }
        Button(library.isHistory(playlist) ? "Delete History" : "Delete Playlist", systemImage: "trash", role: .destructive) {
            if source == .playlist(playlist.id) { source = .all }
            library.deletePlaylist(playlist)
        }
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title.uppercased()).silk(8.5, color: Theme.textTertiary)
            .whatsThis("Playlists")
    }

    private func sidebarRow(_ title: String, icon: String, count: Int, tag: Source) -> some View {
        Button {
            Haptics.shared.toggle(true)
            source = tag
            WhatsThis.shared.note("Playlists")
        } label: {
            HStack(spacing: 6) {
                // On a phone's narrow sidebar, the name matters more: it read "All Tr…".
                if !layout.isCompact {
                    Image(systemName: icon).font(.system(size: 10)).frame(width: 14)
                        .foregroundStyle(source == tag ? Color.white : Theme.textSecondary)
                }
                // Bold when it's chosen, and "History Nov 4" fitted until then.
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
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

            filterKey(layout == .portrait ? "KEY" : "IN KEY", isOn: $inKeyOnly, enabled: referenceDeck?.effectiveKey != nil, help: "In key filter")
            filterKey(layout == .portrait ? "±6%" : "±6% BPM", isOn: $nearBPMOnly, enabled: (referenceDeck?.effectiveBPM ?? 0) > 0, help: "BPM filter")
            filterKey("NEXT", isOn: $bestNext, enabled: true, accessibilityName: "Best next first", help: "Best next first")
            mixKey

            if layout == .portrait { sourceMenu }

            Menu {
                Button("Music files…", systemImage: "music.note") {
                    searchFocused = false
                    importKind = .audio
                    importing = true
                    // The picker can take several seconds to come up the first time, with nothing on screen to say it's coming.
                    dj.say("Opening Files…", .info)
                }
                Button("DJ library (XML)…", systemImage: "doc.text") {
                    searchFocused = false
                    importKind = .djLibrary
                    importing = true
                    dj.say("Choose the XML your DJ software exported.", .info)
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
            .disabled(WhatsThis.shared.isOn)
            .whatsThis("IMPORT")
        }
        .padding(5)
    }

    private func filterKey(_ title: String, isOn: Binding<Bool>, enabled: Bool, accessibilityName: String? = nil, help: String) -> some View {
        Key(title, lit: isOn.wrappedValue && enabled, size: 8.5, feel: .toggle, isEnabled: enabled, accessibilityName: accessibilityName ?? title, help: help, onPress: {
            withAnimation(Theme.panel) { isOn.wrappedValue.toggle() }
        })
        .frame(width: layout == .portrait ? 36 : 56, height: 24)
    }

    /// Auto DJ through the list on screen, in the order it's showing. Pressing it again stops the mix.
    private var mixKey: some View {
        let auto = dj.autoDJ!
        let on = auto.mixSet != nil
        let roomy = layout != .portrait
        return Key(lit: on, feel: .toggle, accessibilityName: on ? "Stop the mix" : "Mix through this list", onPress: {
            if on {
                auto.press()
            } else {
                let air = dj.decks.first(where: \.isPlaying)?.track?.id
                auto.startSet(named: sourceName, tracks: listToMix, airIsElsewhere: air.map { !isInSource($0) } ?? false)
            }
        }) {
            // It does something, where the keys beside it only change what's listed. It read as one more filter, in both rounds
            // where it had no mark: a first-time user upright started a mix by accident, thinking that.
            HStack(spacing: 2) {
                Image(systemName: on ? "stop.fill" : "play.fill").font(.system(size: 6.5, weight: .bold))
                KeyLegend(title: "MIX", size: 8.5)
            }
        }
        .frame(width: roomy ? 46 : 36, height: 24)
        .padding(.leading, roomy ? 5 : 0)
    }

    /// What MIX goes through: the rows, and what NEXT has hidden from them. With a track on the deck and one row showing, it said a
    /// mix needs at least two tracks while the sidebar said there were two.
    private var listToMix: [UUID] {
        let rows = tracks.map(\.id)
        guard bestNext, let hidden = (nextFrom ?? nextFromNow).track, isInSource(hidden) else { return rows }
        return [hidden] + rows
    }

    private func isInSource(_ track: UUID) -> Bool {
        switch source {
        case .all: library.track(track) != nil
        case .playlist(let id): library.playlists.first { $0.id == id }?.trackIDs.contains(track) == true
        }
    }

    /// Which list a mix is going through, and what's left of it, for as long as it's on. Nothing showed this after the first
    /// message, and a first-time user changing list with MIX lit took it to apply to the new one.
    @ViewBuilder
    private var mixLine: some View {
        if let set = dj.autoDJ.mixSet {
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(set.line).font(Theme.text(10.5, .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            // The screen runs under the home indicator, and that went through this.
            .padding(.bottom, homeIndicatorRoom)
            .background(Color(white: 0.12))
            .whatsThis("Mix line")
        }
    }

    private var homeIndicatorRoom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return min(14, scene?.keyWindow?.safeAreaInsets.bottom ?? 0)
    }

    private var sourceName: String {
        // With some of it filtered out it isn't all of anything, and "all your tracks, 3 to go" was said of 4 out of 7.
        if inKeyOnly || nearBPMOnly || !search.isEmpty { return "this list" }
        guard case .playlist(let id) = source, let playlist = library.playlists.first(where: { $0.id == id }) else { return "all your tracks" }
        return library.shownName(of: playlist)
    }

    /// Where the sidebar's sources go on a phone held upright.
    private var sourceMenu: some View {
        Menu {
            Button("All Tracks", systemImage: source == .all ? "checkmark" : "music.note.list") { source = .all }
            ForEach(library.playlists) { playlist in
                Button(library.shownName(of: playlist), systemImage: source == .playlist(playlist.id) ? "checkmark" : "music.note") { source = .playlist(playlist.id) }
            }
            Button("New playlist…", systemImage: "plus") { showNewPlaylist = true }
            // There's no holding a row in a menu, which is how the sidebar does this, and the note said to.
            if let playlistID, let playlist = library.playlists.first(where: { $0.id == playlistID }) {
                Divider()
                playlistActions(playlist)
            }
        } label: {
            Image(systemName: "sidebar.left").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 24)
                .background(KeyFace(color: Theme.accent, lit: source != .all))
        }
        .disabled(WhatsThis.shared.isOn)
        .whatsThis("Playlists")
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

    /// True of what's on: it said nothing was in key or close in tempo, on a screen with one of each.
    private var nothingFits: String {
        let key = layout == .portrait ? "KEY" : "IN KEY", tempo = layout == .portrait ? "±6%" : "±6% BPM"
        if inKeyOnly, nearBPMOnly { return "Nothing here is both in key and close in tempo with what's on the deck. Turn off \(key) or \(tempo) to see more." }
        if inKeyOnly { return "Nothing here is in key with what's on the deck. Turn off \(key) to see the rest." }
        return "Nothing here is close in tempo with what's on the deck. Turn off \(tempo) to see the rest."
    }

    private var emptyState: some View {
        Group {
            if library.tracks.isEmpty {
                ContentUnavailableView {
                    Label("No music yet", systemImage: "music.note.house")
                } description: {
                    let how = " to add music from Files, or drop audio into the Segue DJ folder in the Files app or Finder. If Files opens on an empty folder, go back from there to find your music."
                    // "The blue button" could have been either of two.
                    Text(layout == .portrait ? "Tap \(Image(systemName: "square.and.arrow.down")) above\(how)" : "Tap Import\(how)")
                }
            } else if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if inKeyOnly || nearBPMOnly {
                ContentUnavailableView("Nothing fits right now", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text(nothingFits))
            } else {
                ContentUnavailableView("Nothing in this playlist yet", systemImage: "music.note.list",
                                       description: Text("Go to All Tracks, press and hold a track, and add it from there."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A phone has no room for a row's waveform, so its picture is what previews, and nothing else there did. A first-time user went
/// looking and never found a way to hear a track off the decks.
struct ArtworkPreview: View {
    @Environment(DJEngine.self) private var dj
    let track: Track

    var body: some View {
        let previewing = dj.previewingTrack == track.id
        ZStack {
            if previewing {
                Color.black.opacity(0.5)
                Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.white)
                // A phone's list has no meters or waveform to show it's going, and this is all there is to see.
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Circle().trim(from: 0, to: dj.previewFraction)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !WhatsThis.shared.isOn else { return }
            Haptics.shared.toggle(!previewing)
            dj.togglePreview(track)
        }
        .whatsThis("Preview")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewing ? "Stop preview" : "Preview")
        .accessibilityAddTraits(.isButton)
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
    @State private var askingToDelete = false

    var body: some View {
        let compatible = referenceDeck?.track?.id != track.id && Camelot.isCompatible(track.key, referenceDeck?.effectiveKey)
        let loadedOn = dj.decks.first { $0.track?.id == track.id }
        HStack(spacing: 8) {
            TrackArtwork(track: track).frame(width: 28, height: 28)
                .overlay { if layout.isCompact { ArtworkPreview(track: track) } }
            if !layout.isCompact { TrackPreview(track: track).frame(width: 90, height: 24) }
            VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if library.isMissing(track) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.warn)
                        .accessibilityLabel("File missing")
                }
                // MIX and NEXT go by what's been played, and nothing in the list showed which those were.
                if dj.heardThisSession.contains(track.id) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityLabel("Played")
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
            .contentShape(Rectangle())
            // The first thing a first-time user tries on a row, and it did nothing at all.
            .onTapGesture {
                guard !WhatsThis.shared.isOn else { return }
                Haptics.shared.tick()
                dj.say("Press 1 or 2 to load this, or hold the row for more.", .info)
            }
            .whatsThis("Track row")
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
                    Key("\(deck.index + 1)", lit: deck.track?.id == track.id, size: 10.5, feel: .none, isEnabled: !deck.isPlaying, help: "Load on deck",
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
            let previewing = dj.previewingTrack == track.id
            Button(previewing ? "Stop Preview" : "Preview", systemImage: previewing ? "stop.circle" : "play.circle") { dj.togglePreview(track) }
            Divider()
            let addable = library.playlists.filter { !library.isHistory($0) }
            if !addable.isEmpty {
                Menu("Add to Playlist", systemImage: "text.badge.plus") {
                    ForEach(addable) { playlist in
                        Button(playlist.name) {
                            library.add(track.id, to: playlist.id)
                            dj.say("Added to \(playlist.name).", .done)
                        }
                    }
                }
            }
            if let playlistID {
                let isHistory = library.playlists.first { $0.id == playlistID }.map(library.isHistory) == true
                Button(isHistory ? "Remove from History" : "Remove from Playlist", systemImage: "minus.circle") { library.remove(track.id, from: playlistID) }
            }
            Button("Re-analyse", systemImage: "waveform.badge.magnifyingglass") {
                library.reanalyze(track)
                dj.say("Analysing \(track.title) again.", .info)
            }
            Button("Delete from Library", systemImage: "trash", role: .destructive) {
                // It went at once, file and all, with the deck still playing it and no way back.
                if let deck = dj.decks.first(where: { $0.isPlaying && $0.track?.id == track.id }) {
                    dj.say("Deck \(deck.index + 1) is playing this. Stop it first.", .refused)
                } else {
                    askingToDelete = true
                }
            }
        }
        .alert("Delete \(track.title)?", isPresented: $askingToDelete) {
            Button("Delete", role: .destructive) { library.delete(track) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes its file from Segue DJ, along with its cues, loops and stems.")
        }
    }

    private func keyChip(compatible: Bool) -> some View {
        Text(track.key ?? "…")
            .font(Theme.digits(10.5))
            .foregroundStyle(compatible ? Color.black : Theme.keyColor(track.key))
            .frame(width: 30, height: 16)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(compatible ? Theme.keyColor(track.key) : Color.clear))
            .whatsThis("Track key")
    }
}

/// Touching the top of the screen is iOS's way of sending a list back to its top, and that's where `BROWSE`, `REC` and the
/// rest are. So a press up there lost your place in the list: 6 of 6 in hands-on round 10, on the Duo and on a small phone
/// held upright. A UI test's press doesn't do it, so they couldn't see it. SwiftUI has no way to turn it off, so this finds
/// the list from a view beside it.
private struct StaysWhereItIs: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ view: Marker, context: Context) {}

    final class Marker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Next time round, as the list goes in alongside this.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                Self.leaveAlone(in: window)
            }
        }

        private static func leaveAlone(in view: UIView) {
            if let list = view as? UICollectionView {
                list.scrollsToTop = false
            } else {
                view.subviews.forEach(leaveAlone)
            }
        }
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
                // Twice a second's plenty: across 90 points, a 5-minute track moves about a third of a point each second.
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
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
            guard !WhatsThis.shared.isOn else { return }
            Haptics.shared.toggle(!previewing)
            dj.togglePreview(track)
        }
        .whatsThis("Preview")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewing ? "Stop preview" : "Preview")
        .accessibilityAddTraits(.isButton)
        .task(id: track.bpm) {
            image = await WaveformThumbnails.image(track.id, width: 90 * 3, height: 24 * 3)
        }
    }
}
