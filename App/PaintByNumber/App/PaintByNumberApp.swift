import SwiftUI
import TipKit

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()
    @State private var paintings = UnlimitedPaintings.forLaunch()

    init() {
        #if DEBUG
        if DemoMode.isActive {
            DemoStandardError.silence()
            MainThreadWatchdog.start()
            KeyboardWatch.start()
        }
        #endif
        Preferences.removeRetiredSettings()
        PaintTips.configure()
        Theme.styleNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(paintings)
                .tint(Theme.accent)
                // Tip popovers draw their icons in the system blue otherwise, not the tint.
                .tipImageStyle(Theme.accent)
                // Where an iPhone Duo folds, for every screen and sheet (`FoldWatch`).
                .watchesTheFold()
        }
        .commands {
            PaintCommands()
            GalleryCommands()
        }
    }
}
