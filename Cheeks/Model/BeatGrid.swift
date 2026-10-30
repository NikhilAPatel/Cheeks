import Foundation

/// A tempo change in a track: from `time` onwards the beats run at `bpm`. A beat lands exactly on
/// `time`, and `beatInBar` says which beat of the bar it is (0 is the downbeat).
struct TempoMarker: Codable, Hashable {
    var time: Double
    var bpm: Double
    var beatInBar: Int = 0
}

/// Where the beats are. Most tracks have one tempo; live-played ones drift and have many sections.
/// Beats count from 0, and every whole multiple of 4 is a downbeat.
struct BeatGrid: Hashable {
    struct Section: Hashable {
        var time: Double
        var beat: Double
        var bpm: Double
        var secondsPerBeat: Double { 60 / bpm }
    }

    /// Sorted by time, never empty. Times before the first section carry on at its tempo.
    let sections: [Section]

    init(bpm: Double, firstBeat: Double) {
        sections = [Section(time: firstBeat, beat: 0, bpm: bpm)]
    }

    init?(markers: [TempoMarker]) {
        let sorted = markers.filter { $0.bpm > 0 }.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return nil }
        var built = [Section(time: first.time, beat: Double(((first.beatInBar % 4) + 4) % 4), bpm: first.bpm)]
        for marker in sorted.dropFirst() {
            let last = built[built.count - 1]
            guard marker.time > last.time else { continue }
            // Markers land on beats, so the running count is a whole number. The marker's own idea
            // of the bar wins, so a bar that's been counted slightly wrong can't carry on down the track.
            let counted = (last.beat + (marker.time - last.time) / last.secondsPerBeat).rounded()
            let wanted = ((marker.beatInBar % 4) + 4) % 4
            let have = ((Int(counted) % 4) + 4) % 4
            var shift = wanted - have
            if shift > 2 { shift -= 4 }
            if shift < -1 { shift += 4 }
            built.append(Section(time: marker.time, beat: counted + Double(shift), bpm: marker.bpm))
        }
        sections = built
    }

    var isVariable: Bool { sections.count > 1 }

    /// The section playing at `seconds`.
    func sectionIndex(at seconds: Double) -> Int {
        guard sections.count > 1 else { return 0 }
        var low = 0, high = sections.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if sections[mid].time <= seconds { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func section(at seconds: Double) -> Section { sections[sectionIndex(at: seconds)] }

    func bpm(at seconds: Double) -> Double { section(at: seconds).bpm }

    /// Position on the grid: 4.5 is halfway through the second beat of the second bar.
    func beat(at seconds: Double) -> Double {
        let s = section(at: seconds)
        return s.beat + (seconds - s.time) / s.secondsPerBeat
    }

    func seconds(atBeat beat: Double) -> Double {
        guard sections.count > 1 else {
            let s = sections[0]
            return s.time + (beat - s.beat) * s.secondsPerBeat
        }
        var low = 0, high = sections.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if sections[mid].beat <= beat { low = mid } else { high = mid - 1 }
        }
        let s = sections[low]
        return s.time + (beat - s.beat) * s.secondsPerBeat
    }
}

extension Track {
    /// The beat grid, or nil before the track has been analysed.
    var grid: BeatGrid? {
        if let tempoMarkers, let grid = BeatGrid(markers: tempoMarkers) { return grid }
        guard let bpm, bpm > 0 else { return nil }
        return BeatGrid(bpm: bpm, firstBeat: firstBeat)
    }
}
