import MediaPlayer
import UIKit

/// Puts the track on the Lock Screen and in Control Center, as any Apple audio app would, with the
/// play button there controlling the deck that's on air. Updates only when something changes.
@MainActor
final class NowPlaying {
    private weak var engine: DJEngine?
    private var lastTrack: UUID?
    private var lastPlaying: Bool?
    private var lastUpdate: TimeInterval = 0

    init(engine: DJEngine) {
        self.engine = engine
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() ?? .commandFailed }
        }
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() ?? .commandFailed }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlay() ?? .commandFailed }
        }
    }

    private func togglePlay() -> MPRemoteCommandHandlerStatus {
        guard let engine else { return .commandFailed }
        let deck = engine.loudestDeck ?? engine.decks.first { $0.isLoaded }
        deck?.togglePlay()
        return deck == nil ? .noActionableNowPlayingItem : .success
    }

    func update() {
        guard let engine else { return }
        let now = CACurrentMediaTime()
        let deck = engine.loudestDeck
        let track = deck?.track
        let playing = deck?.isPlaying ?? false
        // Position only needs refreshing occasionally: the system extrapolates between updates.
        guard track?.id != lastTrack || playing != lastPlaying || now - lastUpdate > 10 else { return }
        lastTrack = track?.id
        lastPlaying = playing
        lastUpdate = now
        guard let deck, let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: deck.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: deck.position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? deck.tempoRatio : 0,
        ]
        if let art = deck.artwork {
            let image = UIImage(cgImage: art)
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
