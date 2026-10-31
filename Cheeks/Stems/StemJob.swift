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

    /// One piece of work that any number of jobs can be waiting for. It stops only when they've all gone.
    private final class Shared: @unchecked Sendable {
        let condition = NSCondition()
        var jobs: [StemJob]
        var listeners: [(Double) -> Void]
        var result: Result<Any, Error>?

        init(job: StemJob, progress: @escaping (Double) -> Void) {
            jobs = [job]
            listeners = [progress]
        }

        var isAbandoned: Bool { jobs.allSatisfy(\.isCancelled) }
    }

    private static let inFlight = OSAllocatedUnfairLock(initialState: [String: Shared]())

    /// Runs `work` once for everyone asking for the same key at the same time: the first caller does it
    /// here, and the others wait for its result. Blocks, so call it off the main thread.
    static func shared<Value>(key: String, job: StemJob, progress: @escaping (Double) -> Void,
                              work: (_ report: @escaping (Double) -> Void, _ isCancelled: @escaping () -> Bool) throws -> Value) throws -> Value {
        let (split, joined): (Shared, Bool) = inFlight.withLock { splits in
            if let running = splits[key] {
                running.condition.lock()
                defer { running.condition.unlock() }
                // One that everyone's left is on its way out, so it can't be relied on for a result.
                if !running.isAbandoned {
                    running.jobs.append(job)
                    running.listeners.append(progress)
                    return (running, true)
                }
            }
            let new = Shared(job: job, progress: progress)
            splits[key] = new
            return (new, false)
        }

        if joined {
            split.condition.lock()
            defer { split.condition.unlock() }
            while split.result == nil {
                if job.isCancelled { throw CancellationError() }
                split.condition.wait(until: Date().addingTimeInterval(0.1))
            }
            return try split.result!.get() as! Value
        }

        let result = Result {
            try work({ fraction in
                split.condition.lock()
                let listeners = split.listeners
                split.condition.unlock()
                listeners.forEach { $0(fraction) }
            }, {
                split.condition.lock()
                defer { split.condition.unlock() }
                return split.isAbandoned
            })
        }
        inFlight.withLock { splits in
            if splits[key] === split { splits[key] = nil }
        }
        split.condition.lock()
        split.result = result.map { $0 as Any }
        split.condition.broadcast()
        split.condition.unlock()
        return try result.get()
    }

    /// The stems for a track: from the cache if it's been split before, otherwise by running the
    /// separator and caching the result. Blocks, so call it off the main thread.
    static func stems(for id: UUID, mix: PCM16Stereo, job: StemJob, progress: @escaping (Double) -> Void) throws -> (stems: [PCM16Stereo], label: String) {
        // The same track on both decks shares one split, and its memory, whichever asked first.
        try shared(key: "\(id)-\(mix.frames)", job: job, progress: progress) { report, isCancelled in
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
                    report(fraction)
                }
            }, isCancelled: isCancelled)
            guard separator.isMachineLearning else { return (stems, "≈EQ") }
            // Losing the cache only costs a re-split later, so a full disk isn't an error here.
            try? StemCache.shared.store(id, stems: stems)
            return (stems, "AI")
        }
    }
}
