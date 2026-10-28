import Foundation

/// Reads a rekordbox collection export (File → Export Collection in xml format):
/// beat grid, key, hot cues, memory cue and playlists per track.
struct RekordboxCollection {
    struct Entry {
        var trackID: String
        var fileName: String
        var title: String
        var artist: String
        var bpm: Double?
        /// First downbeat in seconds.
        var firstBeat: Double?
        /// Camelot code.
        var key: String?
        var hotCues: [Int: Double] = [:]
        var memoryCue: Double?
    }

    var entries: [Entry] = []
    /// Playlist name → track IDs.
    var playlists: [(name: String, trackIDs: [String])] = []

    static func parse(_ data: Data) -> RekordboxCollection? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawRoot else { return nil }
        return delegate.collection
    }

    /// rekordbox writes keys as "Am", "F#m", "Db" (or Camelot if the user chose that display).
    static func camelot(fromTonality tonality: String) -> String? {
        let t = tonality.trimmingCharacters(in: .whitespaces)
        if Camelot.parse(t) != nil, t.first?.isNumber == true { return t }
        let isMinor = t.hasSuffix("m")
        let root = isMinor ? String(t.dropLast()) : t
        let names: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
        ]
        guard let pc = names[root.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")] else { return nil }
        return Camelot.code(pitchClass: pc, minor: isMinor)
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var collection = RekordboxCollection()
        var sawRoot = false
        private var current: Entry?
        private var inCollection = false
        private var playlistStack: [(name: String, trackIDs: [String], isPlaylist: Bool)] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch name {
            case "DJ_PLAYLISTS":
                sawRoot = true
            case "COLLECTION":
                inCollection = true
            case "TRACK" where inCollection:
                let location = a["Location"] ?? ""
                let path = URL(string: location)?.path ?? location.removingPercentEncoding ?? location
                current = Entry(trackID: a["TrackID"] ?? "",
                                fileName: (path as NSString).lastPathComponent,
                                title: a["Name"] ?? "",
                                artist: a["Artist"] ?? "",
                                bpm: a["AverageBpm"].flatMap { Double($0) }.flatMap { $0 > 0 ? $0 : nil },
                                key: a["Tonality"].flatMap(RekordboxCollection.camelot(fromTonality:)))
            case "TEMPO" where current != nil && current?.firstBeat == nil:
                // Only the first grid marker is used; Battito is that beat's position in the bar (1–4).
                guard let start = a["Inizio"].flatMap({ Double($0) }),
                      let bpm = a["Bpm"].flatMap({ Double($0) }), bpm > 0 else { break }
                let beat = 60 / bpm
                let beatInBar = Int(a["Battito"] ?? "1") ?? 1
                var downbeat = start + Double((5 - beatInBar) % 4) * beat
                downbeat = downbeat.truncatingRemainder(dividingBy: 4 * beat)
                current?.firstBeat = downbeat
                if current?.bpm == nil { current?.bpm = bpm }
            case "POSITION_MARK" where current != nil:
                guard a["Type"] == "0" || a["Type"] == nil,
                      let start = a["Start"].flatMap({ Double($0) }),
                      let num = a["Num"].flatMap({ Int($0) }) else { break }
                if num < 0 {
                    if current?.memoryCue == nil { current?.memoryCue = start }
                } else if num < 8 {
                    current?.hotCues[num] = start
                }
            case "NODE" where !inCollection:
                playlistStack.append((a["Name"] ?? "Playlist", [], a["Type"] == "1"))
            case "TRACK" where !inCollection && !playlistStack.isEmpty:
                if let key = a["Key"] { playlistStack[playlistStack.count - 1].trackIDs.append(key) }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "COLLECTION":
                inCollection = false
            case "TRACK" where inCollection:
                if let current { collection.entries.append(current) }
                current = nil
            case "NODE" where !inCollection:
                if let node = playlistStack.popLast(), node.isPlaylist {
                    collection.playlists.append((node.name, node.trackIDs))
                }
            default:
                break
            }
        }
    }
}

extension Library {
    struct RekordboxImportResult {
        var matched = 0
        var total = 0
        var playlists = 0
    }

    /// Applies grids, keys, cues and playlists to tracks already in the library, matched by file name.
    func applyRekordbox(_ collection: RekordboxCollection) -> RekordboxImportResult {
        var result = RekordboxImportResult(total: collection.entries.count)
        var indexByName: [String: Int] = [:]
        for (index, track) in tracks.enumerated() {
            if let original = track.originalFileName { indexByName[original.lowercased()] = index }
        }
        var idForRekordboxID: [String: UUID] = [:]
        for entry in collection.entries {
            guard let index = indexByName[entry.fileName.lowercased()] else { continue }
            idForRekordboxID[entry.trackID] = tracks[index].id
            result.matched += 1
            // Edit in place and save once at the end; large collections have thousands of tracks.
            var t = tracks[index]
            if !entry.title.isEmpty { t.title = entry.title }
            if !entry.artist.isEmpty { t.artist = entry.artist }
            if let bpm = entry.bpm { t.bpm = bpm }
            if let first = entry.firstBeat { t.firstBeat = first }
            if let key = entry.key { t.key = key }
            for (slot, time) in entry.hotCues { t.hotCues[slot] = time }
            if let memory = entry.memoryCue { t.memoryCue = memory }
            tracks[index] = t
        }
        for list in collection.playlists {
            let ids = list.trackIDs.compactMap { idForRekordboxID[$0] }
            guard !ids.isEmpty else { continue }
            // Re-importing refreshes playlists instead of duplicating them.
            if let existing = playlists.firstIndex(where: { $0.name == list.name }) {
                playlists[existing].trackIDs = ids
            } else {
                playlists.append(Playlist(id: UUID(), name: list.name, trackIDs: ids))
            }
            result.playlists += 1
        }
        save()
        return result
    }
}
