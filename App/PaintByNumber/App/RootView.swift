import SwiftUI

/// Routes to the app shell. Debug builds route to a demo scenario when launched with
/// `-demo <name>` (see `DemoMode`); Release builds always show the shell.
struct RootView: View {
    var body: some View {
        #if DEBUG
        switch DemoMode.scenario {
        case "pipeline":
            PipelineCheckView()
        case let scenario? where scenario.hasPrefix("paint"):
            PaintDemoView(scenario: scenario)
        default:
            AppShellView()
        }
        #else
        AppShellView()
        #endif
    }
}
