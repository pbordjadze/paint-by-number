import Foundation
import SwiftUI
import TipKit

/// Ravenna, the mosaic era behind Paint by Moonlight's secret door: the whole of Ravenna's app (its
/// gallery, create flow, making-of, Refine and tile canvas), shown in place of Paint by Moonlight's
/// shell while the clock is set back (the app's `Era`). `leave` sets the clock forward again.
///
/// The era lives beside Paint by Moonlight in one process, so everything it keeps is its own:
/// resources in `RavennaResources.bundle` (`Bundle.ravenna`), settings in a suite of their own
/// (`UserDefaults.ravenna`, every `@AppStorage` too), mosaics in `Application Support/Ravenna`, tip
/// ids under `ravenna.`, log categories under `ravenna.`. Shared on purpose: the free paintings'
/// count (a mosaic counts like any painting) and TipKit's datastore, configured once by the app.
public struct RavennaEra: View {
    private let leave: () -> Void

    public init(leave: @escaping () -> Void) {
        self.leave = leave
    }

    public var body: some View {
        let world = RavennaWorld.shared
        RootView()
            .environment(world.library)
            .environment(world.paintings)
            .environment(\.leaveRavenna, LeaveRavenna(action: leave))
            .defaultAppStorage(.ravenna)
            .tint(Theme.accent)
            .tipImageStyle(Theme.accent)
            // Ravenna is dark only: its apse, bench and joint are night colors.
            .preferredColorScheme(.dark)
    }

    /// Whether the launch asked for one of Ravenna's demo scenarios (`-demo ravenna-<name>`), which
    /// open the era whatever the clock says (Debug builds only).
    public static var isDemoScenario: Bool {
        #if DEBUG
        DemoMode.isActive
        #else
        false
        #endif
    }
}

/// What the era keeps for the process: made the first time the door opens, kept while the app
/// runs, so stepping out and back in finds the gallery as it was left.
@MainActor
final class RavennaWorld {
    static let shared = RavennaWorld()

    let library: Library
    let paintings: UnlimitedPaintings

    private init() {
        PaintTips.configure()
        library = Library.forLaunch()
        paintings = UnlimitedPaintings.forLaunch()
    }
}

/// Sets the clock forward again: back to Paint by Moonlight (Settings' Year).
struct LeaveRavenna {
    let action: () -> Void
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var leaveRavenna = LeaveRavenna(action: {})
}

extension Bundle {
    /// Ravenna's resources: its asset catalog, string catalog, shaders, ancient works and their
    /// mosaics (the app target's `RavennaResources.bundle`). The models are the app's own.
    nonisolated static let ravenna: Bundle = Bundle.main.url(forResource: "RavennaResources", withExtension: "bundle")
        .flatMap(Bundle.init(url:)) ?? .main
}

extension UserDefaults {
    /// Ravenna's settings, apart from Paint by Moonlight's (both apps had the same keys).
    nonisolated(unsafe) static let ravenna = UserDefaults(suiteName: "com.pbordjadze.paintbynumber.ravenna") ?? .standard
}
