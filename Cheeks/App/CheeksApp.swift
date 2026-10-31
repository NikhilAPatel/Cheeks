import SwiftUI

@main
struct CheeksApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: Library
    @State private var dj: DJEngine

    init() {
        let library = Library()
        _library = State(initialValue: library)
        _dj = State(initialValue: DJEngine(library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(dj)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
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
