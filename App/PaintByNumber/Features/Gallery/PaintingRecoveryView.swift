import SwiftUI

/// Shown instead of the canvas when a painting can't be opened: says why, and offers what
/// can still be done (regenerate it from its photo, delete it, or go back).
struct PaintingRecoveryView: View {
    let artwork: Artwork?
    let failure: Library.OpenError
    /// 0…1 while the painting is being regenerated.
    var progress: Double?
    /// The last attempt to regenerate failed.
    var didFail = false
    var onRegenerate: () -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let progress {
                VStack(spacing: 10) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 260)
                    Text("Regenerating…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Regenerating")
                .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            } else {
                VStack(spacing: 12) {
                    if canRegenerate {
                        Button("Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                            .buttonStyle(.glassProminent)
                    }
                    if artwork != nil {
                        Button("Delete Painting", systemImage: "trash", role: .destructive, action: onDelete)
                            .buttonStyle(.glass)
                    }
                    Button("Back to Gallery", action: onClose)
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var canRegenerate: Bool { artwork != nil && failure == .damaged(canRegenerate: true) }

    private var title: String {
        failure == .needsNewerApp ? "Needs a Newer Version" : "Can’t Open Painting"
    }

    private var systemImage: String {
        failure == .needsNewerApp ? "arrow.up.circle" : "exclamationmark.triangle"
    }

    private var message: String {
        var text: String
        switch failure {
        case .needsNewerApp:
            let name = artwork.map { $0.title.isEmpty ? "This painting" : "“\($0.title)”" } ?? "This painting"
            text = "\(name) was made with a newer version of Paint by Numbers. Update the app to keep painting it."
        case .damaged(canRegenerate: true) where artwork != nil:
            text = "Its file is damaged. Regenerate it from the original photo with the same settings."
            if artwork?.isStarted == true { text += " Painted areas can’t be recovered, so it will start fresh." }
        case .damaged:
            text = "Its file is damaged, and the original photo isn’t available to regenerate it."
        }
        if didFail { text += "\n\nRegenerating didn’t work. Try again." }
        return text
    }
}
