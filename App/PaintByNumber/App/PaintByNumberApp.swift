import SwiftUI

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()

    init() {
        Theme.configureNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
