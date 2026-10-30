import Foundation
import os

/// One track being split: can be cancelled when the deck loads something else, and keeps count so
/// the model's memory is given back once nothing's waiting for it.
final class StemJob: Sendable {
    private let flag = OSAllocatedUnfairLock(initialState: false)

    func cancel() { flag.withLock { $0 = true } }
    var isCancelled: Bool { flag.withLock { $0 } }

    @MainActor private static var running = 0

    @MainActor static func started() { running += 1 }

    @MainActor static func finished() {
        running -= 1
        if running == 0 { StemSeparation.releaseModel() }
    }

    /// The stems for a track: from the cache if it's been split before, otherwise by running the
    /// separator and caching the result. Blocks, so call it off the main thread.
    static func stems(for id: UUID, mix: PCM16Stereo, job: StemJob, progress: @escaping (Double) -> Void) throws -> (stems: [PCM16Stereo], label: String) {
        // Only real separations are cached, so a hit is always the model's work. It also has to
        // match the audio on the deck, in case the file was replaced.
        if let cached = StemCache.shared.load(id), cached.first?.frames == mix.frames {
            return (cached, "AI")
        }
        let separator = StemSeparation.makeSeparator()
        var last = -1.0
        let stems = try separator.separate(mix, progress: { fraction in
            // A percent at a time is all the display needs.
            if fraction - last >= 0.01 {
                last = fraction
                progress(fraction)
            }
        }, isCancelled: { job.isCancelled })
        guard separator.isMachineLearning else { return (stems, "≈EQ") }
        // Losing the cache only costs a re-split later, so a full disk isn't an error here.
        try? StemCache.shared.store(id, stems: stems)
        return (stems, "AI")
    }
}
