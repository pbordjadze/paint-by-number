import SwiftUI

/// New painting: pick a photo (library, camera or a sample) → tune the template → paint.
struct CreateFlowView: View {
    /// A bundled sample to open straight on its preview (demo scenarios).
    var openingSample: Sample?
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
            } else if let openingSample {
                model.load(sample: openingSample)
            }
        }
        #if DEBUG
        .task {
            // A cancelled wait must not signal readiness.
            guard ShellDemo.current == .create || ShellDemo.current == .createSamples else { return }
            do { try await Task.sleep(for: ShellDemo.pickerLoadAllowance) } catch { return }
            DemoMode.markReady()
        }
        .onChange(of: model.isFinal) { _, isFinal in
            if isFinal, openingSample != nil { DemoMode.markReady() }
        }
        #endif
        .onDisappear { model.cancelAll() }
    }

    @ViewBuilder
    private var root: some View {
        if droppedPhoto != nil || openingSample != nil {
            TemplatePreviewView(model: model, onStart: start)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        } else {
            PhotoSourceView(model: model, initialPane: initialPane, onClose: { dismiss() }) {
                path = [.preview]
            }
        }
    }

    /// The `create-samples` demo opens on the Samples pane; everything else starts on Photos.
    private var initialPane: PhotoSourceView.Pane {
        #if DEBUG
        if ShellDemo.current == .createSamples { return .samples }
        #endif
        return .photos
    }

    /// Saves the full-resolution template to the library and opens it for painting.
    private func start() async throws {
        let draft = try await model.makeDraft()
        let artwork = try await library.create(draft)
        onStart(artwork)
    }
}
