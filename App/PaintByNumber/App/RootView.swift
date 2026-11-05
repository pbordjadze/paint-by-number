#if UNRELEASED
import Ravenna
#endif
import SwiftUI

/// Routes to the app shell. Debug builds route to a demo scenario when launched with
/// `-demo <name>` (see `DemoMode`); Release builds always show the shell. SideStore and Debug
/// builds show Ravenna instead while the secret door's clock is set back (`EraDoor`), and its own
/// scenarios, `-demo ravenna-<name>`.
struct RootView: View {
    #if UNRELEASED
    @State private var door = EraDoor.shared
    #endif

    var body: some View {
        #if UNRELEASED
        Group {
            if door.shown == .byzantium || RavennaEra.isDemoScenario {
                RavennaEra(leave: { door.go(to: .moonlight) })
            } else {
                moonlight
            }
        }
        .overlay { EraPassage(door: door) }
        #else
        moonlight
        #endif
    }

    @ViewBuilder private var moonlight: some View {
        #if DEBUG
        switch DemoMode.scenario {
        case "paint-unavailable":
            // The painting screen's stand-in when the device can't draw the canvas.
            CanvasUnavailableView(onClose: {})
                .background(Theme.paper)
                .task { DemoMode.markReady() }
        case let scenario? where scenario.hasPrefix("paint"):
            PaintDemoView(scenario: scenario)
        case let scenario? where scenario.hasPrefix("making-of"):
            MakingOfDemoView(scenario: scenario)
        default:
            AppShellView()
        }
        #else
        AppShellView()
        #endif
    }
}
