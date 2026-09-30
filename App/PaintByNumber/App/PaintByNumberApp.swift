import SwiftUI

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .tint(Theme.accent)
        }
        .commands { PaintCommands() }
    }
}
