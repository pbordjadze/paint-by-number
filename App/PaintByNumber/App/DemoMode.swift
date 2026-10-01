#if DEBUG
import Foundation

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.paintbynumber -demo paint-progress
///
/// Scenario names are owned by the features that render them (see `RootView`). Scenarios named
/// `*-long-text` are launched with `-NSDoubleLocalizedStrings YES` as well (`ci/screenshots.sh`):
/// every localized string comes out twice as long, standing in for long translations.
///
/// Debug builds only (CI screenshots and UI tests): the demo types are compiled out of Release
/// builds, so a shipped app has no launch argument that swaps its content or library.
enum DemoMode {
    /// The requested scenario, e.g. "gallery", "create", "paint", "paint-progress".
    static let scenario: String? = UserDefaults.standard.string(forKey: "demo")

    static var isActive: Bool { scenario != nil }

    /// The app is hosting the unit tests: like a demo, it keeps no state between runs.
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// `-openFile <path>`: the file the app opens on launch, through the same handler as a file
    /// opened from the share sheet. The `create-from-file` scenario, given none, opens a bundled
    /// sample it writes to the temporary directory under a name of its own, so the title the
    /// create flow derives from the file name is visible.
    static let openFileURL: URL? = {
        if let path = UserDefaults.standard.string(forKey: "openFile") { return URL(fileURLWithPath: path) }
        guard scenario == "create-from-file", let sample = Sample.named("parrots")?.url else { return nil }
        let copy = FileManager.default.temporaryDirectory.appending(path: "Morning Parrots.jpg")
        try? FileManager.default.removeItem(at: copy)
        do { try FileManager.default.copyItem(at: sample, to: copy) } catch { return nil }
        return copy
    }()

    /// `-tracePhotoPeek YES`: the Photo control's accessibility identifier lists every value it
    /// has had, since a UI test can't read the value mid-hold (`press(forDuration:)` blocks).
    static let tracesPhotoPeek = UserDefaults.standard.bool(forKey: "tracePhotoPeek")

    /// `-tracePaper YES`: the canvas's accessibility identifier names the paper it resolved
    /// (`canvas-paper-light` or `canvas-paper-dark`), so a UI test can see the preference reach it.
    static let tracesPaper = UserDefaults.standard.bool(forKey: "tracePaper")

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay (`ci/screenshots.sh`).
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard let scenario else { return }
        try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
    }
}
#endif
