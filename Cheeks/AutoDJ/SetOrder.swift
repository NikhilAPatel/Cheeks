import Foundation

/// What should come next, from what the library knows about every track: its tempo and its key. It can't hear whether
/// two tracks suit each other, but a lot of bad pairings are a bad tempo or a clashing key, and those it can rule out.
enum SetOrder {
    /// Where the mix has got to.
    struct Place: Equatable {
        var bpm: Double?
        var key: String?
    }

    /// Past this many it stops looking for the best next one. Each step looks through all that's left, so a huge library
    /// would otherwise hold up the screen, and nobody plays through 300 tracks in one go.
    static let longestChain = 300

    /// A tempo change nobody hears.
    private static let unnoticed = 0.03

    /// How well a track follows this place, 0...1. What isn't known counts for half, so it neither wins nor loses.
    static func fit(from place: Place, bpm: Double?, key: String?) -> Double {
        0.6 * tempoFit(from: place.bpm, to: bpm) + 0.4 * keyFit(from: place.key, to: key)
    }

    private static func tempoFit(from playing: Double?, to bpm: Double?) -> Double {
        guard let playing, let bpm, playing > 0, bpm > 0 else { return 0.5 }
        let gap = abs(playing / bpm - 1)
        if gap <= unnoticed { return 1 }
        return max(0, 1 - (gap - unnoticed) / (TransitionPlanner.maxStretch - unnoticed))
    }

    private static func keyFit(from playing: String?, to key: String?) -> Double {
        guard let playing, let key else { return 0.5 }
        if Camelot.isCompatible(playing, key) { return 1 }
        // A semitone's shift would fix it, which Auto DJ can do but only when it has to.
        if Camelot.isCompatible(playing, Camelot.shifted(key, by: 1)) || Camelot.isCompatible(playing, Camelot.shifted(key, by: -1)) { return 0.6 }
        return 0
    }

    /// A key as a number, so a long list can compare every pair by looking it up: this runs on the main thread, and
    /// taking the key's name apart each time made a 2,000-track library take seconds.
    private static func keyNumber(_ key: String?) -> Int? {
        guard let key, let (number, isMinor) = Camelot.parse(key), (1...12).contains(number) else { return nil }
        return (number - 1) * 2 + (isMinor ? 0 : 1)
    }

    /// `keyFit` for every pair of keys.
    private static let keyTable: [Double] = {
        let names = (0..<24).map { "\($0 / 2 + 1)\($0 % 2 == 0 ? "A" : "B")" }
        return names.flatMap { from in names.map { keyFit(from: from, to: $0) } }
    }()

    /// The best way through a list, one track at a time, from here. With nowhere to start from, the first track stays first.
    static func order<T>(_ items: [T], from start: Place?, bpm: (T) -> Double?, key: (T) -> String?) -> [T] {
        let tempos = items.map(bpm), keys = items.map { keyNumber(key($0)) }
        var left = Array(items.indices)
        var chain: [Int] = []
        var playing = start?.bpm
        var inKey = keyNumber(start?.key)
        var hasPlace = start != nil
        while !left.isEmpty, chain.count < longestChain {
            var best = 0
            if hasPlace {
                var top = -1.0
                for (position, item) in left.enumerated() {
                    var keyScore = 0.5
                    if let inKey, let theirs = keys[item] { keyScore = keyTable[inKey * 24 + theirs] }
                    let score = 0.6 * tempoFit(from: playing, to: tempos[item]) + 0.4 * keyScore
                    // The list's own order settles a tie.
                    if score > top {
                        top = score
                        best = position
                    }
                }
            }
            let chosen = left.remove(at: best)
            chain.append(chosen)
            // A track within stretching distance comes in at the mix's tempo, so that's still the tempo afterwards.
            if let tempo = tempos[chosen] {
                if let now = playing, abs(now / tempo - 1) <= TransitionPlanner.maxStretch {} else { playing = tempo }
            }
            inKey = keys[chosen] ?? inKey
            hasPlace = true
        }
        return (chain + left).map { items[$0] }
    }
}
