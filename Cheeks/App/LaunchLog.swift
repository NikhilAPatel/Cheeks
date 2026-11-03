import Darwin
import Foundation
import QuartzCore

/// Where the time goes, for when someone asks. With CHEEKS_LAUNCH_LOG in the environment it prints each step of launch,
/// each shader and pre-rendered part, every time the main thread freezes for 100 ms or more, and CPU and memory every
/// 5 s. If the value's a path, the lines go there too. It works the same on a phone, through
/// `devicectl device process launch --console --environment-variables`. Without it, this costs a check of one flag.
enum LaunchLog {
    private static let setting = ProcessInfo.processInfo.environment["CHEEKS_LAUNCH_LOG"]
    static let isOn = setting != nil
    private static let start = CACurrentMediaTime()
    nonisolated(unsafe) private static var bakes = 0
    nonisolated(unsafe) private static var bakeTime = 0.0
    /// A freeze this long is six frames gone, which anyone would notice. A walk round the app looks closer.
    private static let stallLimit = ProcessInfo.processInfo.environment["CHEEKS_SELF_TOUR"] == nil ? 0.1 : 0.05

    private static var elapsed: Double { CACurrentMediaTime() - start }

    private static func write(_ line: String) {
        print(line)
        guard let setting, setting.hasPrefix("/"), let file = fopen(setting, "a") else { return }
        fputs(line + "\n", file)
        fclose(file)
    }

    static func mark(_ step: String) {
        guard isOn else { return }
        write(String(format: "LAUNCH: %7.3f s  %@", elapsed, step))
    }

    /// Says what's about to happen, so a freeze can be matched to it.
    static func step(_ name: String) {
        guard isOn else { return }
        write("STEP:  " + name)
    }

    static func baked(_ key: String, took seconds: Double) {
        guard isOn else { return }
        bakes += 1
        bakeTime += seconds
        write(String(format: "LAUNCH: %7.3f s  baked %3d in %6.0f ms, %6.2f s so far: %@", elapsed, bakes, seconds * 1000, bakeTime, key))
    }

    /// Starts watching the main thread. It's a thread of its own, because it has to notice when the main one's stuck.
    static func startWatching() {
        guard isOn else { return }
        let thread = Thread {
            var lastReport = CACurrentMediaTime(), lastCPU = cpuSeconds()
            var stalls = 0, worst = 0.0
            while true {
                let sent = CACurrentMediaTime()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let now = CACurrentMediaTime(), waited = now - sent
                if waited >= stallLimit {
                    stalls += 1
                    worst = max(worst, waited)
                    write(String(format: "STALL: %6.0f ms, ending at %7.2f s", waited * 1000, now - start))
                }
                if now - lastReport >= 5 {
                    let cpu = cpuSeconds()
                    write(String(format: "PERF:  %7.1f s  CPU %4.0f%% of a core, memory %5.0f MB, %d freezes, worst %.0f ms",
                                 now - start, (cpu - lastCPU) / (now - lastReport) * 100, memoryMB(), stalls, worst * 1000))
                    lastReport = now
                    lastCPU = cpu
                    stalls = 0
                    worst = 0
                }
                usleep(16_000)
            }
        }
        thread.name = "Main thread watch"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let seconds = { (t: timeval) in Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// What iOS goes by when it decides an app's using too much.
    private static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
