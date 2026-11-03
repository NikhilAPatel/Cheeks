import Foundation

/// Decides when a track has earned a line in a history or a tracklist. It counts once it's been audible for 10 seconds,
/// like DJ software's history. It counts again if it comes back on air after something else has had a line: going
/// back to a track is what someone reading the list would want to see, and without it the track before seemed to run on
/// for the whole time. Stopping and starting with nothing else in between is still the one play.
struct OnAirLog {
    static let seconds: TimeInterval = 10

    private var since: [Date?] = [nil, nil, nil, nil]
    /// Each deck's track that's got a line, until it's left the air.
    private var logged: [UUID?] = [nil, nil, nil, nil]
    private var last: UUID?

    /// Returns when the track became audible, if it's just earned a line.
    mutating func update(deck: Int, track: UUID?, audible: Bool, now: Date) -> Date? {
        guard let track, audible else {
            since[deck] = nil
            // It's off the air, and so it can earn another line, unless it's still the last thing on the list.
            logged[deck] = nil
            return nil
        }
        let from = since[deck] ?? now
        since[deck] = from
        guard now.timeIntervalSince(from) >= Self.seconds, logged[deck] != track else { return nil }
        logged[deck] = track
        guard last != track else { return nil }
        last = track
        return from
    }
}
