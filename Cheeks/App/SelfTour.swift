import Foundation

/// A walk round the app from inside it, for measuring. A UI test freezes the app itself whenever it looks at the screen,
/// and this doesn't, so what `LaunchLog` catches here is the app's own doing. It also runs on a phone with nobody touching
/// it. With CHEEKS_SELF_TOUR in the environment it starts by itself after launch. It needs two tracks with real audio.
@MainActor
enum SelfTour {
    static let isOn = ProcessInfo.processInfo.environment["CHEEKS_SELF_TOUR"] != nil
    /// CHEEKS_SELF_TOUR=browser goes straight to opening and closing the browser, over and over, for a profiler to watch.
    private static let browserOnly = ProcessInfo.processInfo.environment["CHEEKS_SELF_TOUR"] == "browser"
    static let openBrowser = Notification.Name("CheeksSelfTourOpenBrowser")
    static let closeBrowser = Notification.Name("CheeksSelfTourCloseBrowser")

    static func start(_ dj: DJEngine, _ library: Library) {
        guard isOn else { return }
        Task { await walk(dj, library) }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func walk(_ dj: DJEngine, _ library: Library) async {
        LaunchLog.step("resting, nothing loaded")
        await wait(5)

        let real = library.tracks.filter { !library.isMissing($0) }
        guard real.count >= 2 else {
            LaunchLog.step("stopped: it needs two tracks with audio")
            return
        }
        for (deck, track) in zip(dj.decks, real) {
            LaunchLog.step("load \(track.title) on deck \(deck.index + 1)")
            _ = dj.load(track, onto: deck)
            while deck.isLoading { await wait(0.05) }
            await wait(1)
        }

        LaunchLog.step("resting, loaded")
        await wait(4)
        LaunchLog.step("both decks start")
        dj.decks.forEach { $0.play() }
        await wait(5)

        if !browserOnly {
            for _ in 0..<2 {
                for mode in PadMode.allCases {
                    LaunchLog.step("deck 1 pads to \(mode.rawValue)")
                    dj.decks[0].padMode = mode
                    await wait(0.7)
                }
            }
            dj.decks[0].padMode = .hotCue
            await wait(1)
        }

        for round in 1...(browserOnly ? 25 : 3) {
            LaunchLog.step("open the browser, \(round)")
            NotificationCenter.default.post(name: openBrowser, object: nil)
            await wait(1.5)
            LaunchLog.step("close the browser, \(round)")
            NotificationCenter.default.post(name: closeBrowser, object: nil)
            await wait(1.5)
        }

        LaunchLog.step("EQ and filter moving for 3 s")
        for i in 0..<90 {
            let value = Float(sin(Double(i) / 8))
            dj.decks[0].eqLow = value * 0.8
            dj.decks[1].filter = value * 0.5
            await wait(1.0 / 30)
        }
        dj.decks[0].eqLow = 0
        dj.decks[1].filter = 0

        LaunchLog.step("resting, playing")
        await wait(10)
        dj.decks.forEach { $0.pause() }
        LaunchLog.step("done")
    }
}
