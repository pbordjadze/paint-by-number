import SwiftUI

/// A floating glass capsule message with an optional action.
struct Toast<Trailing: View>: View {
    let text: String
    let systemImage: String
    /// The screen edge it slides in from.
    var edge: Edge = .bottom
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Accessibility sizes leave a phone-wide capsule too little beside the icon and the action
        // for a painting's title: the message gets the full width, with the action under it.
        let large = dynamicTypeSize.isAccessibilitySize
        let layout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // The action keeps its label however long the message is: the message gets what is left.
            Text(text)
                .lineLimit(large ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            trailing
                .buttonStyle(ToastActionStyle())
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        // The stacked toast is too tall for a capsule's ends: they would cut into the text.
        .glassEffect(.regular, in: large ? AnyShape(.rect(cornerRadius: 28, style: .continuous)) : AnyShape(.capsule))
        .transition(reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity))
        // A toast's action stays a button of its own: combined into the message, a tap on "Undo"
        // by Voice Control or a test landed on the message's middle and undid nothing (QA,
        // November 6: a deletion's Undo did nothing in 1 of 3 tries).
        .accessibilityElement(children: Trailing.self == EmptyView.self ? .combine : .contain)
    }
}

/// A toast's action as the system draws a plain button (the tint, dimmed while pressed), with a
/// hit area grown to 44 points each way: its label alone was 38 by 18 (QA, November 7). The
/// growth is padding laid out as nothing, so the toast keeps its size.
private struct ToastActionStyle: ButtonStyle {
    private static let reach: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.tint)
            .opacity(configuration.isPressed ? 0.35 : 1)
            .padding(Self.reach)
            .contentShape(.rect)
            .padding(-Self.reach)
    }
}

extension Toast where Trailing == EmptyView {
    init(text: String, systemImage: String, edge: Edge = .bottom) {
        self.init(text: text, systemImage: systemImage, edge: edge) { EmptyView() }
    }
}
