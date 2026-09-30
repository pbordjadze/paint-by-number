import SwiftUI

/// New painting: pick a photo (library, camera or a sample) → tune the template → paint.
struct CreateFlowView: View {
    var demo: ShellDemo?
    /// A photo dropped on the gallery: the flow opens on its preview.
    var droppedPhoto: Data?
    var onStart: (Artwork) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @State private var model = CreateModel()
    @State private var path: [Step] = []

    enum Step: Hashable { case preview }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Step.self) { _ in
                    TemplatePreviewView(model: model, onStart: start)
                }
        }
        .task {
            // A dropped photo or demo opens straight on the preview (pushing while the cover
            // is still being presented would stall the presentation).
            guard model.source == nil else { return }
            if let droppedPhoto {
                model.load(imageData: droppedPhoto)
            } else if let sample = demo?.previewSample {
                model.load(sample: sample)
            }
        }
        .task {
            // The library picker loads out of process and reports nothing; give it a moment
            // before the screenshot (a cancelled wait must not signal readiness).
            guard demo == .create || demo == .createSamples else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            DemoMode.markReady()
        }
        .onChange(of: model.isFinal) { _, isFinal in
            if isFinal, demo?.previewSample != nil { DemoMode.markReady() }
        }
        .onDisappear { model.cancelAll() }
    }

    @ViewBuilder
    private var root: some View {
        if droppedPhoto != nil || demo?.previewSample != nil {
            TemplatePreviewView(model: model, onStart: start)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        } else {
            PhotoSourceView(
                model: model, initialPane: demo == .createSamples ? .samples : .photos, onClose: { dismiss() }
            ) {
                path = [.preview]
            }
        }
    }

    /// Saves the full-resolution template to the library and opens it for painting.
    private func start() async throws {
        let draft = try await model.makeDraft()
        let artwork = try await library.create(draft)
        onStart(artwork)
    }
}
