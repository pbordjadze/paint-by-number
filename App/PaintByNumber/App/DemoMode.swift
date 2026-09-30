import Foundation

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.paintbynumber -demo paint-progress
///
/// Scenario names are owned by the features that render them (see `RootView`).
enum DemoMode {
    /// The requested scenario, e.g. "gallery", "create", "paint", "paint-progress".
    static let scenario: String? = UserDefaults.standard.string(forKey: "demo")

    static var isActive: Bool { scenario != nil }

    /// The app is hosting the unit tests: like a demo, it keeps no state between runs.
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// `-tracePhotoPeek YES`: the Photo control's accessibility identifier lists every value it
    /// has had, since a UI test can't read the value mid-hold (`press(forDuration:)` blocks).
    static let tracesPhotoPeek = UserDefaults.standard.bool(forKey: "tracePhotoPeek")

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay (`ci/screenshots.sh`).
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard let scenario else { return }
        try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
    }
}
