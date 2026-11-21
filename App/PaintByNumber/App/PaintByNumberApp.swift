import SwiftUI
import TipKit

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()
    @State private var paintings = UnlimitedPaintings.forLaunch()

    init() {
        #if DEBUG
        TourLog.start()
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
                // The line-art models loaded once the launch has settled, so the first photo
                // picked waits no longer than the next (painting-company row 361).
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    await EdgeDetector.warmUp()
                }
        }
        .commands {
            PaintCommands()
            GalleryCommands()
        }
    }
}
