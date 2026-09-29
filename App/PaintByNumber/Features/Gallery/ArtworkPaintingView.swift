import os
import PaintCore
import SwiftUI

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
