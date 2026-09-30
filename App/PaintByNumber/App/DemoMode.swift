#if DEBUG
import Foundation

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.paintbynumber -demo paint-progress
///
/// Scenario names are owned by the features that render them (see `RootView`).
///
/// Debug builds only (CI screenshots and UI tests): the demo types are compiled out of Release
/// builds, so a shipped app has no launch argument that swaps its content or library.
enum DemoMode {
    /// The requested scenario, e.g. "gallery", "create", "paint", "paint-progress".
    static let scenario: String? = UserDefaults.standard.string(forKey: "demo")

    static var isActive: Bool { scenario != nil }

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
