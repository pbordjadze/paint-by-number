import SwiftUI

/// Routes to the app shell, or to a demo scenario when launched with `-demo <name>`.
struct RootView: View {
    var body: some View {
        switch DemoMode.scenario {
        case "pipeline":
            PipelineCheckView()
        case let scenario? where scenario.hasPrefix("paint"):
            PaintDemoView(scenario: scenario)
        default:
            AppShellView()
        }
    }
}
