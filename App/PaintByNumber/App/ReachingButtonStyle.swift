import SwiftUI

/// A text button drawn as the system draws a plain one (the tint, dimmed while pressed, grey while
/// disabled), whose hit area reaches `reach` points past its label each way: a toast's Undo was
/// its word alone, 38 by 18 points, and the unlock sheet's Restore Purchases 110 by 16, under
/// Apple's 44-point minimum (QA, November 7). The reach is padding laid out as none, so what
/// holds the button keeps its size and the label its place.
struct ReachingButtonStyle: ButtonStyle {
    var reach: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        Reaching(configuration: configuration, reach: reach)
    }

    private struct Reaching: View {
        let configuration: Configuration
        let reach: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .opacity(configuration.isPressed ? 0.35 : 1)
                .padding(reach)
                .contentShape(.rect)
                .padding(-reach)
        }
    }
}
