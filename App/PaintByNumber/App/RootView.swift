import SwiftUI

/// Routes to the app shell, or to a demo scenario when launched with `-demo <name>`.
struct RootView: View {
    var body: some View {
        switch DemoMode.scenario {
        case "pipeline":
            PipelineCheckView()
        case "paint-unavailable":
            // The painting screen's stand-in when the device can't draw the canvas.
            CanvasUnavailableView(onClose: {})
                .background(Theme.paper)
                .task { DemoMode.markReady() }
        case let scenario? where scenario.hasPrefix("paint"):
            PaintDemoView(scenario: scenario)
        default:
            AppShellView()
        }
    }
}
