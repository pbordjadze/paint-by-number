import Ravenna
import SwiftUI

/// Routes to the app shell. Debug builds route to a demo scenario when launched with
/// `-demo <name>` (see `DemoMode`); Release builds always show the shell. SideStore and Debug
/// builds show Ravenna instead while the secret door's clock is set back (`EraDoor`), and its own
/// scenarios, `-demo ravenna-<name>`; `era-passage` sets the clock back at launch and holds the
/// passage half laid.
struct RootView: View {
    @State private var door = EraDoor.shared

    var body: some View {
        Group {
            if door.shown == .byzantium || RavennaEra.isDemoScenario {
                RavennaEra(leave: { door.go(to: .moonlight) })
            } else {
                moonlight
            }
        }
        .overlay { EraPassage(door: door) }
        #if DEBUG
        // `era-passage`: the gallery as the clock is set back, the passage held half laid.
        .task { if DemoMode.scenario == "era-passage" { door.go(to: .byzantium) } }
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
