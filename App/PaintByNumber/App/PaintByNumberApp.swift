import SwiftUI

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()

    init() {
        #if DEBUG
        if DemoMode.isActive { MainThreadWatchdog.start() }
        #endif
        Preferences.removeRetiredSettings()
        PaintTips.configure()
        Theme.styleNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(Theme.accent)
        }
        .commands { PaintCommands() }
    }
}
