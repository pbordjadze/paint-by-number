import SwiftUI

/// Feedback mode's top bar, in place of the painting's: Cancel (which asks before throwing
/// marks or a note away), what the mode is for, Undo and Redo for the ink, and Next, which
/// opens the review and send sheet. Like the painting's bar it keeps its 44 pt height, its
/// controls reaching larger text sizes through the Large Content Viewer.
struct FeedbackBar: View {
    let draft: FeedbackDraft
    /// The window's width: the bar never grows wider than it.
    let width: CGFloat
    var onDiscard: () -> Void
    var onNext: () -> Void

    @State private var confirmsDiscard = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                GlassIconButton(systemImage: "xmark", label: "Cancel", action: cancel)
                    .accessibilityIdentifier("feedback-cancel")
                    .confirmationDialog("Discard Your Feedback?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive, action: onDiscard)
                    } message: {
                        Text("Your marks and notes will be lost.")
                    }
                ViewThatFits(in: .horizontal) {
                    title(showsHint: true)
                    title(showsHint: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GlassIconButton(systemImage: "arrow.uturn.backward", label: "Undo", action: draft.undo)
                    .disabled(!draft.canUndo)
                GlassIconButton(systemImage: "arrow.uturn.forward", label: "Redo", action: draft.redo)
                    .disabled(!draft.canRedo)
                Button(action: onNext) {
                    Text("Next")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .fixedSize()
                .accessibilityIdentifier("feedback-next")
                .accessibilityShowsLargeContentViewer()
            }
            .frame(maxWidth: max(0, width))
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func title(showsHint: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                // Its own key: Settings' "Feedback" is haptics and sounds.
                Text(String(localized: "feedback.mode.title", defaultValue: "Feedback",
                            comment: "Feedback mode's top bar on the painting screen: its title, while the painter marks the painting and writes notes for the developers"))
                    .font(.subheadline.weight(.semibold))
                if showsHint {
                    Text("Draw on the painting, pinch to zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityShowsLargeContentViewer()
    }

    /// Nothing to lose: straight back to painting.
    private func cancel() {
        if draft.isEmpty {
            onDiscard()
        } else {
            confirmsDiscard = true
        }
    }
}
