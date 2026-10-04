import SwiftUI

/// A floating glass capsule message with an optional action.
struct Toast<Trailing: View>: View {
    let text: String
    let systemImage: String
    /// The screen edge it slides in from.
    var edge: Edge = .bottom
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            // The action keeps its label however long the message is: the message gets what is left.
            Text(text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(-1)
            trailing
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: edge).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

extension Toast where Trailing == EmptyView {
    init(text: String, systemImage: String, edge: Edge = .bottom) {
        self.init(text: text, systemImage: systemImage, edge: edge) { EmptyView() }
    }
}
