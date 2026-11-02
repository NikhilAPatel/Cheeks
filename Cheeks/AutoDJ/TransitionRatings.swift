import Foundation

/// What someone thought of a move, kept on this device only.
struct TransitionRating: Codable, Equatable {
    var move: TransitionMove
    /// The two tracks' titles, so the file makes sense to a person reading it.
    var from: String
    var to: String
    var liked: Bool
    var at: Date
}

/// The ratings so far, which lean on what Auto DJ chooses. They never rule a move out: one with bad ratings can still
/// be picked if nothing else passes the audition.
final class TransitionRatings {
    private(set) var all: [TransitionRating]
    private let url: URL

    static var defaultURL: URL { URL.applicationSupportDirectory.appending(path: "auto-dj-ratings.json") }

    init(url: URL = TransitionRatings.defaultURL) {
        self.url = url
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([TransitionRating].self, from: $0) }
        all = saved ?? []
    }

    func add(_ rating: TransitionRating) {
        all.append(rating)
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    var taste: [TransitionMove: Double] { Self.taste(from: all) }

    /// Only the latest count for each move, so a change of mind shows up.
    private static let remembered = 20

    /// What each move gains or loses when choosing. It starts gently, so one press doesn't decide much, and never goes
    /// past 0.6, about what playing the same move twice in a row costs.
    static func taste(from ratings: [TransitionRating]) -> [TransitionMove: Double] {
        var out: [TransitionMove: Double] = [:]
        for move in TransitionMove.allCases {
            let latest = ratings.filter { $0.move == move }.suffix(remembered)
            guard !latest.isEmpty else { continue }
            let liked = latest.filter(\.liked).count
            out[move] = 0.6 * Double(liked - (latest.count - liked)) / Double(latest.count + 2)
        }
        return out
    }
}
