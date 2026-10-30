import Foundation

/// Reads a rekordbox collection export (File → Export Collection in xml format):
/// beat grid (with tempo changes), key, hot cues and hot loops, memory cues, saved loops and playlists per track.
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
        /// Set when the grid has tempo changes in it.
        var tempoMarkers: [TempoMarker]?
        var hotCues: [Int: Double] = [:]
        var hotCueInfo: [Int: HotCueInfo] = [:]
        var memoryCues: [MemoryCue] = []
        var savedLoops: [SavedLoop] = []
        var memoryCue: Double? { memoryCues.map(\.time).min() }

        /// Turns every grid marker read from the file into the track's grid.
        fileprivate mutating func finishGrid(_ markers: [TempoMarker]) {
            guard let first = markers.first else { return }
            let beat = 60 / first.bpm
            let downbeat = first.time + Double((4 - first.beatInBar) % 4) * beat
            firstBeat = downbeat.truncatingRemainder(dividingBy: 4 * beat)
            if bpm == nil { bpm = first.bpm }
            // Plenty of tracks repeat one tempo over several markers; that's a steady grid.
            let slowest = markers.map(\.bpm).min() ?? 0, fastest = markers.map(\.bpm).max() ?? 0
            tempoMarkers = fastest - slowest > 0.005 ? markers : nil
            if tempoMarkers != nil { firstBeat = first.time }
        }
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

    /// Type 0 is a cue, 3 a load point and 4 a loop. Num is the hot cue slot, or -1 for memory.
    fileprivate static func color(_ a: [String: String]) -> CueColor? {
        guard let r = a["Red"].flatMap({ Double($0) }), let g = a["Green"].flatMap({ Double($0) }),
              let b = a["Blue"].flatMap({ Double($0) }) else { return nil }
        return CueColor(red: r / 255, green: g / 255, blue: b / 255)
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var collection = RekordboxCollection()
        var sawRoot = false
        private var current: Entry?
        private var markers: [TempoMarker] = []
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
            case "TEMPO" where current != nil:
                // Battito is the position of this beat in the bar, 1 to 4.
                guard let start = a["Inizio"].flatMap({ Double($0) }),
                      let bpm = a["Bpm"].flatMap({ Double($0) }), bpm > 0 else { break }
                markers.append(TempoMarker(time: start, bpm: bpm, beatInBar: ((Int(a["Battito"] ?? "1") ?? 1) - 1 + 4) % 4))
            case "POSITION_MARK" where current != nil:
                addMark(a)
            case "NODE" where !inCollection:
                playlistStack.append((a["Name"] ?? "Playlist", [], a["Type"] == "1"))
            case "TRACK" where !inCollection && !playlistStack.isEmpty:
                if let key = a["Key"] { playlistStack[playlistStack.count - 1].trackIDs.append(key) }
            default:
                break
            }
        }

        private func addMark(_ a: [String: String]) {
            guard let start = a["Start"].flatMap({ Double($0) }),
                  let num = a["Num"].flatMap({ Int($0) }) else { return }
            let type = a["Type"] ?? "0"
            let end = a["End"].flatMap { Double($0) }
            let name = a["Name"] ?? ""
            let color = RekordboxCollection.color(a)
            switch (type, num) {
            case ("0", 0..<8), ("4", 0..<8):
                current?.hotCues[num] = start
                let loopEnd = type == "4" ? end : nil
                if !name.isEmpty || color != nil || loopEnd != nil {
                    current?.hotCueInfo[num] = HotCueInfo(name: name, color: color, loopEnd: loopEnd)
                }
            case ("0", ..<0), ("3", ..<0):
                current?.memoryCues.append(MemoryCue(time: start, name: name, color: color))
            case ("4", ..<0):
                if let end, end > start { current?.savedLoops.append(SavedLoop(start: start, end: end, name: name)) }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "COLLECTION":
                inCollection = false
            case "TRACK" where inCollection:
                if var finished = current {
                    finished.finishGrid(markers)
                    collection.entries.append(finished)
                }
                current = nil
                markers = []
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
            if let first = entry.firstBeat {
                t.firstBeat = first
                t.tempoMarkers = entry.tempoMarkers
                // Phrases are counted in bars, so a new grid means counting them again.
                t.phrases = nil
            }
            if let key = entry.key { t.key = key }
            for (slot, time) in entry.hotCues {
                t.hotCues[slot] = time
                t.hotCueInfo[slot] = entry.hotCueInfo[slot]
            }
            // Importing again adds what's new, without doubling up what's already there.
            for cue in entry.memoryCues where !t.memoryCues.contains(where: { abs($0.time - cue.time) < 0.01 }) {
                t.memoryCues.append(cue)
            }
            for loop in entry.savedLoops where !t.savedLoops.contains(where: { abs($0.start - loop.start) < 0.01 && abs($0.end - loop.end) < 0.01 }) {
                t.savedLoops.append(loop)
            }
            tracks[index] = t
            if t.phrases == nil && !isMissing(t) { enqueueCatchUp(t.id) }
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
