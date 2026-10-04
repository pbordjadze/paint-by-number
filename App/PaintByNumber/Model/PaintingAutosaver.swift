import Foundation
import PaintCore

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
