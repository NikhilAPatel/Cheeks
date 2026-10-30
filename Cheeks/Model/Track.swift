import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    /// File name inside `Library.musicDirectory`.
    var fileName: String
    /// Name of the file when it was imported; used to match rekordbox XML entries.
    var originalFileName: String?
    var duration: Double = 0
    /// The track's tempo, or its typical tempo when `tempoMarkers` says it moves around.
    var bpm: Double?
    /// Time of the first beat of the beat grid, in seconds.
    var firstBeat: Double = 0
    /// Set when the tempo changes through the track. The grid comes from these instead of `bpm` and `firstBeat`.
    var tempoMarkers: [TempoMarker]?
    /// Camelot notation, e.g. "8A".
    var key: String?
    /// Integrated loudness in LUFS, from analysis. Used to bring tracks to a matched level.
    var loudness: Double?
    /// Hot cue slot (0...7) → time in seconds. Stored with the track like rekordbox.
    var hotCues: [Int: Double] = [:]
    /// Optional extras for a hot cue slot: its name, its own colour, and a loop if it's a hot loop.
    var hotCueInfo: [Int: HotCueInfo] = [:]
    /// Points to come back to, like a CDJ's memory. The earliest is where the track loads.
    var memoryCues: [MemoryCue] = []
    var savedLoops: [SavedLoop] = []
    /// The song's structure, from analysis. Nil until it's been worked out.
    var phrases: [Phrase]?
    var rating: Int = 0
    var playCount: Int = 0
    var dateAdded = Date()

    var isAnalyzed: Bool { bpm != nil }
    /// Where the track loads: the earliest memory cue.
    var memoryCue: Double? { memoryCues.map(\.time).min() }
}

extension Track {
    private enum LegacyKeys: String, CodingKey { case memoryCue }

    /// Written out by hand so a library saved by any earlier version still loads: anything it
    /// doesn't have takes its default instead of making the whole file unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(String.self, forKey: .artist)
        fileName = try c.decode(String.self, forKey: .fileName)
        originalFileName = try c.decodeIfPresent(String.self, forKey: .originalFileName)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm)
        firstBeat = try c.decodeIfPresent(Double.self, forKey: .firstBeat) ?? 0
        tempoMarkers = try c.decodeIfPresent([TempoMarker].self, forKey: .tempoMarkers)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        loudness = try c.decodeIfPresent(Double.self, forKey: .loudness)
        hotCues = try c.decodeIfPresent([Int: Double].self, forKey: .hotCues) ?? [:]
        hotCueInfo = try c.decodeIfPresent([Int: HotCueInfo].self, forKey: .hotCueInfo) ?? [:]
        savedLoops = try c.decodeIfPresent([SavedLoop].self, forKey: .savedLoops) ?? []
        phrases = try c.decodeIfPresent([Phrase].self, forKey: .phrases)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        playCount = try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        if let saved = try c.decodeIfPresent([MemoryCue].self, forKey: .memoryCues) {
            memoryCues = saved
        } else if let single = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Double.self, forKey: .memoryCue) {
            memoryCues = [MemoryCue(time: single)]
        }
    }
}

/// A colour stored with a track, from rekordbox or chosen by hand.
struct CueColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
}

struct HotCueInfo: Codable, Hashable {
    var name: String = ""
    var color: CueColor?
    /// Set when this is a hot loop: pressing the pad jumps to the cue and loops up to here.
    var loopEnd: Double?
}

struct MemoryCue: Identifiable, Codable, Hashable {
    var id = UUID()
    var time: Double
    var name: String = ""
    var color: CueColor?
}

struct SavedLoop: Identifiable, Codable, Hashable {
    var id = UUID()
    var start: Double
    var end: Double
    var name: String = ""
    /// Turns on when the track loads, so the deck stays in it once it gets there, as on a CDJ.
    var activeOnLoad = false
}

/// A section of the song, from the phrase analysis.
struct Phrase: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case intro = "INTRO", verse = "VERSE", up = "UP", chorus = "CHORUS", down = "DOWN", outro = "OUTRO"
    }
    var start: Double
    var kind: Kind
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [UUID] = []
}

enum Camelot {
    /// Camelot number for each pitch class (C = 0) in major and minor.
    static let major = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]
    static let minor = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]
    static let pitchNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    static func code(pitchClass: Int, minor isMinor: Bool) -> String {
        "\((isMinor ? minor : major)[pitchClass])\(isMinor ? "A" : "B")"
    }

    static func musicalName(_ code: String) -> String {
        guard let parsed = parse(code) else { return code }
        let (number, isMinor) = parsed
        let table = isMinor ? minor : major
        guard let pc = table.firstIndex(of: number) else { return code }
        return pitchNames[pc] + (isMinor ? "m" : "")
    }

    static func parse(_ code: String) -> (Int, Bool)? {
        guard let letter = code.last, let number = Int(code.dropLast()) else { return nil }
        return (number, letter == "A")
    }

    /// Each semitone up is seven steps round the wheel.
    static func shifted(_ code: String, by semitones: Int) -> String {
        guard let (number, isMinor) = parse(code) else { return code }
        return "\(((number - 1 + 7 * semitones) % 12 + 12) % 12 + 1)\(isMinor ? "A" : "B")"
    }

    /// Sorts round the wheel, with minor and major of the same number together.
    static func sortValue(_ code: String) -> Int? {
        parse(code).map { $0.0 * 2 + ($0.1 ? 0 : 1) }
    }

    /// Harmonic mixing: same key, ±1 on the wheel, or relative major/minor.
    static func isCompatible(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, let pa = parse(a), let pb = parse(b) else { return false }
        let (na, ma) = pa, (nb, mb) = pb
        if ma == mb {
            let diff = (na - nb + 12) % 12
            return diff == 0 || diff == 1 || diff == 11
        }
        return na == nb
    }
}

extension Double {
    /// "3:07" style formatting for track times.
    var clockString: String {
        guard isFinite else { return "--:--" }
        let total = Int(abs(self).rounded(.down))
        return String(format: "%@%d:%02d", self < 0 ? "-" : "", total / 60, total % 60)
    }
}
