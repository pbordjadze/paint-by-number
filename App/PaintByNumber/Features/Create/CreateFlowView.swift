import SwiftUI

/// New painting: pick a photo (library, camera or a sample) → tune the template → paint.
struct CreateFlowView: View {
    var demo: ShellDemo?
    var onStart: (Artwork) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @State private var model = CreateModel()
    @State private var path: [Step] = []
    @State private var didStartDemo = false

    enum Step: Hashable { case preview }

    var body: some View {
        NavigationStack(path: $path) {
            PhotoSourceView(model: model, onClose: { dismiss() }) {
                path = [.preview]
            }
            .navigationDestination(for: Step.self) { _ in
                TemplatePreviewView(model: model, onStart: start)
            }
        }
        .onAppear {
            guard !didStartDemo, let sample = demo?.previewSample else { return }
            didStartDemo = true
            model.load(sample: sample)
            path = [.preview]
        }
        .onDisappear { model.cancelAll() }
    }

    /// Saves the full-resolution template to the library and opens it for painting.
    private func start() async throws {
        let draft = try await model.makeDraft()
        let artwork = try await library.create(draft)
        onStart(artwork)
    }
}
