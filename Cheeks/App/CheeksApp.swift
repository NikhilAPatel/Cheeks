import SwiftUI

@main
struct CheeksApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: Library
    @State private var dj: DJEngine
    @State private var isOpening = true

    init() {
        LaunchLog.mark("app starting")
        LaunchLog.startWatching()
        let library = Library()
        LaunchLog.mark("library ready, \(library.tracks.count) tracks")
        _library = State(initialValue: library)
        _dj = State(initialValue: DJEngine(library: library))
        LaunchLog.mark("engine ready")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(library)
                    .environment(dj)
                if isOpening {
                    OpeningCover()
                        .transition(.opacity)
                }
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .all)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                LaunchLog.mark("first screen appeared")
                // The main thread's free again once this runs, so touches work from here.
                DispatchQueue.main.async {
                    LaunchLog.mark("main thread free")
                    // The meters' sweep and the jog's wake-up would otherwise happen behind the logo.
                    LiveRenderer.shared.launchTime = CACurrentMediaTime()
                    withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.25)) { isOpening = false }
                }
                SelfTour.start(dj, library)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.importInbox() // pick up files added through the Files app
                dj.startAudio()
                Haptics.shared.start()
            } else if phase == .background {
                library.saveNow()
                library.writeAutomaticBackup(evenIfRecent: true)
                Haptics.shared.stop()
            }
        }
    }
}
