import Ravenna
import SwiftUI

/// Routes to the app shell. Debug builds route to a demo scenario when launched with
/// `-demo <name>` (see `DemoMode`); Release builds always show the shell. Every
/// build shows Ravenna instead while the secret door's clock is set back (`EraDoor`), Debug builds
/// its own scenarios too, `-demo ravenna-<name>`; `era-passage` sets the clock back at launch and holds the
/// passage half laid; `era-passage-back` and `era-passage-night` (SideStore and Debug builds) play
/// the way back over the gallery and hold it with the tiles half fallen, the night showing
/// through, and at its still night, the crescent and stars out; `about-painting` and
/// `about-photograph` are the page about a library picture's real work (`AboutPaintingDemo`),
/// `print-preview…` Print's preview (`PrintPreviewDemo`).
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
        .task {
            if DemoMode.scenario == "era-passage" { door.go(to: .byzantium) }
            // `era-passage-back`, `era-passage-night`: the way back, held at a moment each.
            if DemoMode.scenario == "era-passage-back" || DemoMode.scenario == "era-passage-night" {
                door.playDemoWayBack()
            }
        }
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
        case let scenario? where scenario.hasPrefix("about-"):
            AboutPaintingDemo(scenario: scenario)
        case let scenario? where scenario.hasPrefix("print-preview"):
            PrintPreviewDemo(scenario: scenario)
        default:
            AppShellView()
        }
        #else
        AppShellView()
        #endif
    }
}
