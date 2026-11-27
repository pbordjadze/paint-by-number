import PaintCore
import SwiftUI

/// ✎ Change (painting-company row 239, "Paint Now"): the drawing tools (`RefineView`) on a
/// painting, from its own bar, any time, half painted too. The painting's photo, settings and
/// refinements are loaded into a `CreateModel` of the change's own (`load(artwork:…)`): an
/// unedited painting's template is the base as it stands, so it opens with nothing made again;
/// one with edits makes its base again first (Preparing…, tens of seconds on a phone). Done
/// hands the model back (`ArtworkPaintingView`), which saves the new template into the painting
/// with its painted areas carried over (`Library.adopt`); Cancel changes nothing. Undo here is
/// the drawing session's; the painting's own Undo stays the painting's. Edits not yet kept are
/// handed on as they change (`onEdit`) and kept on disk until Done or Cancel, so iOS ending the
/// app loses none: the next ✎ Change opens on them (`Library.keepChange`).
///
/// In SideStore and Debug builds only while the drawing tools are (`docs/refine-release-gates.md`).
struct PaintingChangeView: View {
    let model: CreateModel
    /// The tools have opened, on these refinements.
    var onOpen: (TemplateRefinements) -> Void
    /// The refinements changed while the tools are open.
    var onEdit: (TemplateRefinements) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The drawing tools have opened: they stay while their edits are laid, when the template
    /// isn't final for a moment.
    @State private var isOpen = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if isOpen {
                RefineView(model: model)
            } else if case .failed(let message) = model.phase {
                ContentUnavailableView {
                    Label("Couldn’t Open the Drawing Tools", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Preparing…")
                        .foregroundStyle(.secondary)
                    Button("Cancel", role: .cancel) { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                }
                .accessibilityElement(children: .contain)
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: model.canRefine, initial: true) { _, can in
            if can && !isOpen {
                isOpen = true
                onOpen(model.refinements)
            }
        }
        .onChange(of: model.refinements) { _, refinements in
            if isOpen { onEdit(refinements) }
        }
        .onDisappear {
            // A load never opened stops with the screen.
            if !isOpen { model.cancelAll() }
        }
    }
}
