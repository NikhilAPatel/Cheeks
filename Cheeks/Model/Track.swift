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
    var bpm: Double?
    /// Time of the first beat of the beat grid, in seconds.
    var firstBeat: Double = 0
    /// Camelot notation, e.g. "8A".
    var key: String?
    /// Hot cue slot (0...7) → time in seconds. Stored with the track like rekordbox.
    var hotCues: [Int: Double] = [:]
    var memoryCue: Double?
    var rating: Int = 0
    var playCount: Int = 0
    var dateAdded = Date()

    var isAnalyzed: Bool { bpm != nil }
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
