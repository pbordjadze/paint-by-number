import SwiftUI

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()

    init() {
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
