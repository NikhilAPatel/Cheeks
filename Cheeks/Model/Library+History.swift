import Foundation

extension Library {
    static let historyPrefix = "History "

    /// History: one playlist per day of the tracks that were actually played out.
    func logPlay(_ trackID: UUID) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = Self.historyPrefix + formatter.string(from: Date())
        if let index = playlists.firstIndex(where: { $0.name == name }) {
            guard playlists[index].trackIDs.last != trackID else { return }
            playlists[index].trackIDs.append(trackID)
        } else {
            playlists.append(Playlist(id: UUID(), name: name, trackIDs: [trackID]))
        }
        save()
    }

    func isHistory(_ playlist: Playlist) -> Bool { playlist.name.hasPrefix(Self.historyPrefix) }

    /// What to call a playlist on screen. "History 2026-11-04" was cut off in the sidebar as "History 202…", which leaves out the day.
    func shownName(of playlist: Playlist) -> String {
        guard isHistory(playlist) else { return playlist.name }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(playlist.name.dropFirst(Self.historyPrefix.count))) else { return playlist.name }
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let style: Date.FormatStyle = thisYear ? .dateTime.month(.abbreviated).day() : .dateTime.year().month(.abbreviated).day()
        return Self.historyPrefix + date.formatted(style)
    }
}
