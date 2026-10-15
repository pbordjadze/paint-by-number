import SwiftUI
import TipKit

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
                // Tip popovers draw their icons in the system blue otherwise, not the tint.
                .tipImageStyle(Theme.accent)
        }
        .commands { PaintCommands() }
    }
}
