import Foundation

/// A track's sections, named from what its stems are doing. The first analysis only has the mix to go on, and on real music
/// it took a loud intro for a chorus, or a quiet chorus for an intro. With stems it's plain: a chorus has the kick and the
/// bassline in, at about the track's full level, and the rest follows from where a section sits against the choruses.
extension TrackMap {
    /// Section starts land on `grid`'s bar lines, as a grid someone set needn't be the one these bars were counted on.
    func phrases(on grid: BeatGrid) -> [Phrase] {
        guard barCount > 0, energy.count >= barCount, hasKick.count >= barCount, on[Stem.bass.rawValue].count >= barCount else { return [] }
        let sections = sectionRanges()
        var big = sections.map(isBig)
        if !big.contains(true) {
            // Nothing has what a chorus has, as in a track with no drums: then it's just what's loudest.
            let loudest = sections.map(medianLevel).max() ?? 0
            big = sections.map { medianLevel($0) >= loudest - 1 }
        }
        // A few bars with everything in, on their own, aren't a chorus.
        let alone = sections.indices.map { i in
            big[i] && sections[i].count < Self.shortestChorus && !(i > 0 && big[i - 1]) && !(i + 1 < big.count && big[i + 1])
        }
        if zip(big, alone).contains(where: { $0 && !$1 }) {
            big = zip(big, alone).map { $0 && !$1 }
        }
        big = withSmallerPartsOfLongRuns(big, sections: sections)
        if !big.contains(true) { big = big.map { _ in true } }
        let firstBig = big.firstIndex(of: true) ?? 0, lastBig = big.lastIndex(of: true) ?? sections.count - 1

        var phrases: [Phrase] = []
        for (i, section) in sections.enumerated() {
            let kind = kind(of: section, at: i, big: big, firstBig: firstBig, lastBig: lastBig)
            guard phrases.last?.kind != kind else { continue }
            let start = section.lowerBound == 0 ? 0 : grid.seconds(atBeat: (grid.beat(at: seconds(atBar: section.lowerBound)) / 4).rounded() * 4)
            phrases.append(Phrase(start: start, kind: kind))
        }
        return phrases
    }

    /// A long stretch that's all the same to the kick and the bass, as rock is, and a master that loud barely moves in level.
    /// Its smaller parts are the ones with nobody singing in a stretch that's mostly sung, or clearly quieter than the rest of it.
    private func withSmallerPartsOfLongRuns(_ big: [Bool], sections: [Range<Int>]) -> [Bool] {
        guard vocal.count >= barCount else { return big }
        var out = big
        var i = 0
        while i < sections.count {
            guard big[i] else {
                i += 1
                continue
            }
            var j = i
            while j + 1 < sections.count, big[j + 1] { j += 1 }
            let run = sections[i].lowerBound..<sections[j].upperBound
            if j > i, run.count > Self.longRun {
                let ordered = energy[run].sorted()
                let loud = ordered[Int(Double(ordered.count) * 0.9)]
                let sung = averageVocal(run) >= 0.5
                for k in i...j where sections[k].count >= Self.shortestChorus {
                    if medianLevel(sections[k]) < loud - Self.withinARun || (sung && averageVocal(sections[k]) < 0.4) { out[k] = false }
                }
            }
            i = j + 1
        }
        return out
    }

    private func averageVocal(_ section: Range<Int>) -> Float {
        vocal[section].reduce(0, +) / Float(max(1, section.count))
    }

    /// How far below a track's loud parts a chorus can be. Further than this, and with its kick and bass still in, it's a verse.
    private static let chorusWithin: Float = 4
    private static let shortestChorus = 8
    private static let longRun = 32
    private static let withinARun: Float = 1.5
    /// A build-up longer than this is really a breakdown that happens to end in a chorus.
    private static let longestUp = 16

    private var kicks: Bool { share(hasKick, 0..<barCount) >= 0.2 }
    private var basslines: Bool { share(on[Stem.bass.rawValue], 0..<barCount) >= 0.2 }

    /// Where the arrangement changes, with any scrap at either end joined to what it's next to.
    private func sectionRanges() -> [Range<Int>] {
        var edges = Set(boundaries.filter { $0 > 0 && $0 < barCount }).union([0, barCount]).sorted()
        if edges.count > 2, edges[1] < 4 { edges.remove(at: 1) }
        if edges.count > 2, barCount - edges[edges.count - 2] < 4 { edges.remove(at: edges.count - 2) }
        return zip(edges, edges.dropFirst()).map { $0..<$1 }
    }

    private func isBig(_ section: Range<Int>) -> Bool {
        if kicks, share(hasKick, section) < 0.5 { return false }
        if basslines, share(on[Stem.bass.rawValue], section) < 0.5 { return false }
        return medianLevel(section) >= loudParts - Self.chorusWithin
    }

    private func kind(of section: Range<Int>, at i: Int, big: [Bool], firstBig: Int, lastBig: Int) -> Phrase.Kind {
        let kickIsIn = !kicks || share(hasKick, section) >= 0.5
        let leadsIn = i + 1 < big.count && big[i + 1] && section.count <= Self.longestUp
        if big[i] { return .chorus }
        if i == 0 { return .intro }
        // The last few bars before a chorus are its lead-in, whatever's in them.
        if leadsIn, !kickIsIn || section.count <= 4 || rises(section) { return .up }
        if i < firstBig { return .intro }
        if i > lastBig { return .outro }
        return kickIsIn ? .verse : .down
    }

    /// How loud this track's loud parts are. Not its peak, as one bar can stand out.
    private var loudParts: Float {
        let ordered = energy[0..<barCount].sorted()
        return ordered[Int(Double(ordered.count) * 0.9)]
    }

    private func medianLevel(_ section: Range<Int>) -> Float {
        let ordered = energy[section].sorted()
        return ordered[ordered.count / 2]
    }

    private func rises(_ section: Range<Int>) -> Bool {
        guard section.count >= 4 else { return false }
        let middle = (section.lowerBound + section.upperBound) / 2
        func average(_ part: Range<Int>) -> Float { energy[part].reduce(0, +) / Float(part.count) }
        return average(middle..<section.upperBound) > average(section.lowerBound..<middle) + 1.5
    }

    private func share(_ flags: [Bool], _ section: Range<Int>) -> Float {
        Float(flags[section].lazy.filter { $0 }.count) / Float(max(1, section.count))
    }
}
