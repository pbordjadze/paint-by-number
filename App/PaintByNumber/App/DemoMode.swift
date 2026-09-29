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
}
