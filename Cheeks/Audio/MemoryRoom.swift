import Foundation
import os

/// Whether something that size fits, by iOS's own count of what's left before it kills the app, as being killed is the worst
/// thing that can happen in a set. A 20-minute track's stems are about 850 MB, and two of those won't fit on a smaller iPhone.
enum MemoryRoom {
    /// What the model takes to load, on top of a track's stems.
    static let stemModelBytes = 600 << 20
    /// What's left for everything else: the screen, the other deck carrying on, a track's analysis.
    private static let kept = 200 << 20

    #if DEBUG
    nonisolated(unsafe) static var availableForTesting: Int?
    #endif

    static func fits(_ bytes: Int) -> Bool {
        var available = Int(os_proc_available_memory())
        #if DEBUG
        if let availableForTesting { available = availableForTesting }
        #endif
        // There's nothing to go on in the simulator, where it's 0.
        return available == 0 || bytes + kept <= available
    }
}
