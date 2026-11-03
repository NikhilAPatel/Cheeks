import Foundation
import QuartzCore

/// Where launch time goes, for when someone asks. With CHEEKS_LAUNCH_LOG=1 in the environment it prints each step, and
/// how long each pre-rendered part took. Without it, it costs a check of one flag.
enum LaunchLog {
    static let isOn = ProcessInfo.processInfo.environment["CHEEKS_LAUNCH_LOG"] != nil
    private static let start = CACurrentMediaTime()
    nonisolated(unsafe) private static var bakes = 0
    nonisolated(unsafe) private static var bakeTime = 0.0

    static func mark(_ step: String) {
        guard isOn else { return }
        print(String(format: "LAUNCH: %7.3f s  %@", CACurrentMediaTime() - start, step))
    }

    static func baked(_ key: String, took seconds: Double) {
        guard isOn else { return }
        bakes += 1
        bakeTime += seconds
        print(String(format: "LAUNCH: %7.3f s  baked %3d in %6.0f ms, %6.2f s so far: %@", CACurrentMediaTime() - start, bakes, seconds * 1000, bakeTime, key))
    }
}
