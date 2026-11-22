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
/// `print-preview…` Print's preview (`PrintPreviewDemo`). In SideStore and Debug builds Stained Glass
/// (`GlassEra`) shows while the clock is at 1248, and for its scenarios, `-demo glass-<name>`
/// (`GlassDemo`); `era-passage-glass` holds the way to it at the rose window's light. Woodblock
/// (`WoodblockEra`) shows at 1765 and for `-demo woodblock-<name>` (`WoodblockDemo`). Watercolor
/// (`WatercolorEra`) shows at 1502 and for `-demo watercolor-<name>` (`WatercolorDemo`);
/// `era-passage-watercolor` holds the way to it as its wash floods in. The Frame (`FrameEra`), the
/// frame every mode shares with nothing of a mode's own in it, shows at 1000 and for
/// `-demo frame-<name>`.
struct RootView: View {
    @State private var door = EraDoor.shared

    var body: some View {
        Group {
            if door.shown == .byzantium || RavennaEra.isDemoScenario {
                RavennaEra(leave: { year in door.go(to: Era.opened(by: year) ?? .moonlight) })
            } else if showsGlass {
                glass
            } else if showsWoodblock {
                woodblock
            } else if showsWatercolor {
                watercolor
            } else if showsFrame {
                frame
            } else {
                moonlight
            }
        }
        .overlay { EraPassage(door: door) }
        #if DEBUG
        // `era-passage`: the gallery as the clock is set back, the passage held half laid.
        .task {
            if DemoMode.scenario == "era-passage" { door.go(to: .byzantium) }
            #if UNRELEASED
            // `era-passage-glass`: the way to Stained Glass, held at the rose window's light.
            if DemoMode.scenario == "era-passage-glass" { door.go(to: .glass) }
            // `era-passage-watercolor`: the way to Watercolor, held as its wash floods in.
            if DemoMode.scenario == "era-passage-watercolor" { door.go(to: .watercolor) }
            #endif
            // `era-passage-back`, `era-passage-night`: the way back, held at a moment each.
            if DemoMode.scenario == "era-passage-back" || DemoMode.scenario == "era-passage-night" {
                door.playDemoWayBack()
            }
        }
        #endif
    }

    /// Whether Stained Glass is on screen: its era, or one of its demo scenarios (`glass-…`).
    private var showsGlass: Bool {
        #if UNRELEASED
        return door.shown == .glass || GlassEra.isDemoScenario
        #else
        return false
        #endif
    }

    /// Stained Glass (SideStore and Debug builds; `GlassEra`).
    @ViewBuilder private var glass: some View {
        #if UNRELEASED
        GlassEra(leave: { year in door.go(to: Era.opened(by: year) ?? .moonlight) })
        #endif
    }

    /// Whether Woodblock is on screen: its era, or one of its demo scenarios (`woodblock-…`).
    private var showsWoodblock: Bool {
        #if UNRELEASED
        return door.shown == .woodblock || WoodblockEra.isDemoScenario
        #else
        return false
        #endif
    }

    /// Whether Watercolor is on screen: its era, or one of its demo scenarios (`watercolor-…`).
    private var showsWatercolor: Bool {
        #if UNRELEASED
        return door.shown == .watercolor || WatercolorEra.isDemoScenario
        #else
        return false
        #endif
    }

    /// Woodblock (SideStore and Debug builds; `WoodblockEra`).
    @ViewBuilder private var woodblock: some View {
        #if UNRELEASED
        WoodblockEra(leave: { year in door.go(to: Era.opened(by: year) ?? .moonlight) })
        #endif
    }

    /// Watercolor (SideStore and Debug builds; `WatercolorEra`).
    @ViewBuilder private var watercolor: some View {
        #if UNRELEASED
        WatercolorEra(leave: { year in door.go(to: Era.opened(by: year) ?? .moonlight) })
        #endif
    }

    /// Whether The Frame is on screen: its era, or one of its demo scenarios (`frame-…`).
    private var showsFrame: Bool {
        #if UNRELEASED
        return door.shown == .frame || FrameEra.isDemoScenario
        #else
        return false
        #endif
    }

    /// The Frame (SideStore and Debug builds; `FrameEra`).
    @ViewBuilder private var frame: some View {
        #if UNRELEASED
        FrameEra(leave: { year in door.go(to: Era.opened(by: year) ?? .moonlight) })
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
