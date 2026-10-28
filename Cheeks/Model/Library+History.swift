import Foundation

extension Library {
    static let historyPrefix = "History "

    /// rekordbox-style history: one playlist per day of the tracks that were actually played out.
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
}
