#if DEBUG
#if UNRELEASED
import Foundation
import os

/// `-demoModeGalleries YES` (Debug builds; painting-company's `tools/clip`): a demo launch fills
/// Stained Glass's and Watercolor's galleries as it starts, so a door opened from Settings lands
/// on paintings, not on an empty gallery. Their shelves are the demo's own folders, emptied at
/// every launch; the galleries read them as they open.
enum ModeGalleries {
    /// Asked for, and not by a scenario of Stained Glass or Watercolor, which seed their own.
    static var isAsked: Bool {
        guard DemoMode.isActive, UserDefaults.standard.bool(forKey: "demoModeGalleries") else { return false }
        let own = DemoMode.scenario.map { $0.hasPrefix("glass-") || $0.hasPrefix("watercolor-") } ?? false
        return !own
    }

    static func seed() async {
        guard isAsked else { return }
        do {
            try await GlassDemo.seedGallery(on: .shared)
            try await WatercolorDemo.seedGallery(on: .shared)
            // The clip tool opens a door only after this line, so the gallery is whole.
            Log.demo.notice("mode galleries seeded")
        } catch {
            Log.demo.error("Mode galleries: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
#endif
