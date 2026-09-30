import CoreGraphics
import os
import PaintCore
import SwiftUI
import UIKit

/// Opens an artwork for painting: loads it off the main actor, hosts `PaintView`, and
/// saves progress while the user paints.
struct ArtworkPaintingView: View {
    let artworkID: UUID
    var onClose: () -> Void

    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = true
    @State private var autosaver: PaintingAutosaver?
    @State private var failed = false

    private var artwork: Artwork? { library.artwork(with: artworkID) }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let autosaver {
                PaintView(session: autosaver.session, title: artwork?.title ?? "", onClose: close)
                    .environment(\.sourcePhotoLoader, SourcePhotoLoader { [library, artworkID] maxPixelSize in
                        await library.sourcePhoto(for: artworkID, maxPixelSize: maxPixelSize)
                    })
                    .background { RevisionObserver(session: autosaver.session, onChange: autosaver.sessionChanged) }
                    .transition(.opacity)
            } else if failed {
                ContentUnavailableView {
                    SwiftUI.Label("Can’t Open Painting", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Its file may be damaged.")
                } actions: {
                    Button("Back to Gallery", action: onClose)
                        .buttonStyle(.glass)
                }
            } else if let artwork {
                // Where the zoom transition lands while the template loads.
                ArtworkThumbnail(artwork: artwork, contentMode: .fit)
                    .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                    .padding(20)
                    .overlay { ProgressView().controlSize(.large) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background { CanvasGesturesOverZoomDismissal().frame(width: 0, height: 0) }
        .task { await open() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autosaver?.saveNow(refreshThumbnail: true) }
        }
        .onChange(of: autoAdvance) { _, value in autosaver?.session.autoAdvance = value }
        .onDisappear { autosaver?.saveNow(refreshThumbnail: true) }
    }

    private func open() async {
        guard autosaver == nil, !failed else { return }
        do {
            let document = try await library.loadForPainting(artworkID)
            let session = PaintingSession(template: document.template, progress: document.progress)
            Preferences().apply(to: session)
            withAnimation(.easeOut(duration: 0.25)) {
                autosaver = PaintingAutosaver(session: session, artworkID: artworkID, library: library)
            }
        } catch {
            Log.library.error("Opening \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            failed = true
        }
    }

    private func close() {
        autosaver?.saveNow(refreshThumbnail: true)
        onClose()
    }
}

/// The zoom transition lets a swipe down or a pinch anywhere dismiss the pushed screen, which
/// steals the canvas's pan and pinch and drops the painter back in the gallery. SwiftUI has no
/// switch for it, so this turns those two recognizers off on the pushed controller's view once
/// it has appeared; the edge swipe back and the Close button keep working. The recognizers are
/// found by their UIKit class names (`PaintingNavigationTests` notices if they change).
private struct CanvasGesturesOverZoomDismissal: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private static let dismissalRecognizers: Set<String> = [
            "_UIContentSwipeDismissGestureRecognizer", "_UISwipeDownGestureRecognizer", "_UITransformGestureRecognizer",
        ]

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The transition may install its recognizers just after the push completes.
            disableDismissalGestures()
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                disableDismissalGestures()
            }
        }

        private func disableDismissalGestures() {
            var pushed: UIViewController? = self
            while let controller = pushed, !(controller.parent is UINavigationController) { pushed = controller.parent }
            guard let recognizers = pushed?.view.gestureRecognizers, !recognizers.isEmpty else { return }
            var names: [String] = []
            for recognizer in recognizers {
                let name = String(describing: type(of: recognizer))
                if recognizer.isEnabled && Self.dismissalRecognizers.contains(name) {
                    recognizer.isEnabled = false
                    names.append("\(name) (disabled)")
                } else {
                    names.append(name)
                }
            }
            Log.library.notice("Painting screen recognizers: \(names.joined(separator: ", "), privacy: .public)")
        }
    }
}

/// Re-evaluates only itself on each paint, keeping `PaintView` out of the invalidation.
private struct RevisionObserver: View {
    let session: PaintingSession
    var onChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.revision) { onChange() }
    }
}

/// Persists a painting session: progress about a second after the last change (right
/// away when the painting is finished), and a fresh thumbnail when leaving.
final class PaintingAutosaver {
    let session: PaintingSession
    let artworkID: UUID
    private let library: Library
    private var pending: Task<Void, Never>?
    private var savedRevision: Int
    private var thumbnailRevision: Int

    static let delay: Duration = .seconds(1)

    init(session: PaintingSession, artworkID: UUID, library: Library) {
        self.session = session
        self.artworkID = artworkID
        self.library = library
        savedRevision = session.revision
        thumbnailRevision = session.revision
    }

    func sessionChanged() {
        pending?.cancel()
        if session.isComplete {
            saveNow(refreshThumbnail: true)
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow(refreshThumbnail: Bool = false) {
        pending?.cancel()
        pending = nil
        if session.revision != savedRevision {
            savedRevision = session.revision
            library.saveProgress(session.progress, for: artworkID)
        }
        if refreshThumbnail && session.revision != thumbnailRevision {
            thumbnailRevision = session.revision
            let library = library, id = artworkID, template = session.template, progress = session.progress
            Task { await library.refreshThumbnail(id, template: template, progress: progress) }
        }
    }
}

/// Loads the photo the open painting was made from, for the painting screen's "compare with
/// photo" (read it with `@Environment(\.sourcePhotoLoader)`).
nonisolated struct SourcePhotoLoader: Sendable {
    let load: @Sendable (_ maxPixelSize: Int?) async -> CGImage?

    func callAsFunction(maxPixelSize: Int? = nil) async -> CGImage? { await load(maxPixelSize) }
}

private nonisolated struct SourcePhotoLoaderKey: EnvironmentKey {
    static let defaultValue: SourcePhotoLoader? = nil
}

extension EnvironmentValues {
    var sourcePhotoLoader: SourcePhotoLoader? {
        get { self[SourcePhotoLoaderKey.self] }
        set { self[SourcePhotoLoaderKey.self] = newValue }
    }
}
