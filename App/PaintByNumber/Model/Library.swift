import CoreGraphics
import Foundation
import Observation
import PaintCore

/// A template and its saved progress, loaded for painting.
nonisolated struct PaintingDocument: Sendable {
    var template: Template
    var progress: PaintProgress
}

/// The user's artworks. Metadata lives in memory (loaded at launch, it is small); templates
/// are loaded on demand. All file work runs off the main actor, serialized per artwork so
/// writes land in the order they were made.
@Observable
final class Library {
    /// An artwork still being generated in the background (first-launch samples).
    struct Placeholder: Identifiable, Hashable {
        let sample: Sample
        var id: String { sample.id }
    }

    private(set) var artworks: [Artwork] = []
    private(set) var placeholders: [Placeholder] = []
    /// The most recently deleted artwork, restorable until the undo window closes.
    private(set) var recentlyDeleted: Artwork?

    @ObservationIgnored let store: ArtworkStore
    @ObservationIgnored private var writes: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var purge: Task<Void, Never>?

    static let undoWindow: Duration = .seconds(6)
    static let seededKey = "library.seededStarterSamples"

    init(store: ArtworkStore) {
        self.store = store
        store.purgeStaging()
        store.purgeTrash()
        artworks = store.loadAll().sorted(by: Self.newestFirst)
    }

    /// The library used by the running app: the real one, or a throwaway one for demos.
    static func forLaunch() -> Library {
        if DemoMode.isActive {
            let root = FileManager.default.temporaryDirectory.appending(path: "DemoLibrary", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
            let library = Library(store: ArtworkStore(root: root))
            ShellDemo.current?.prepare(library)
            return library
        }
        let library = Library(store: ArtworkStore(root: ArtworkStore.defaultRoot))
        library.seedIfNeeded()
        return library
    }

    // MARK: Queries

    var inProgress: [Artwork] { artworks.filter { !$0.isComplete } }
    var finished: [Artwork] {
        artworks.filter(\.isComplete).sorted { ($0.completedAt ?? $0.modifiedAt) > ($1.completedAt ?? $1.modifiedAt) }
    }
    var isEmpty: Bool { artworks.isEmpty && placeholders.isEmpty }

    func artwork(with id: UUID) -> Artwork? { artworks.first { $0.id == id } }

    // MARK: Creating

    @discardableResult
    func create(_ draft: ArtworkDraft) async throws -> Artwork {
        let artwork = Artwork(
            title: draft.title, createdAt: draft.date, template: draft.template, settings: draft.settings,
            progress: draft.progress, sampleName: draft.sampleName)
        let store = self.store
        try await Background.run {
            let progress = draft.progress ?? PaintProgress(regionCount: draft.template.regions.count)
            let thumbnail = TemplateRasterizer.pngData(
                draft.template, painted: progress.painted, style: .thumbnail,
                maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
            let source = draft.photo.flatMap {
                ImageCodec.jpegData(ImageCodec.downscaled($0, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
            }
            try store.create(artwork, template: draft.template, progress: progress, sourceJPEG: source, thumbnailPNG: thumbnail)
        }
        insert(artwork)
        return artwork
    }

    /// First launch: prepares a couple of ready-to-paint samples in the background (shown
    /// as placeholders meanwhile), so the gallery is never empty on day one.
    func seedIfNeeded(_ samples: [Sample] = Sample.starters, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.seededKey) else { return }
        guard artworks.isEmpty else {
            defaults.set(true, forKey: Self.seededKey)
            return
        }
        seed(samples.map { SeedItem(sample: $0) }) {
            defaults.set(true, forKey: Self.seededKey)
        }
    }

    struct SeedItem {
        var sample: Sample
        /// Fraction already painted (demos).
        var painted: Double?
        /// How long ago it was last painted; orders the gallery.
        var age: TimeInterval = 0
    }

    /// Generates artworks from bundled samples, one after another, showing placeholders
    /// until each is ready.
    func seed(_ items: [SeedItem], completion: (() -> Void)? = nil) {
        let now = Date.now
        placeholders = items.map { Placeholder(sample: $0.sample) }
        Task {
            for (index, item) in items.enumerated() {
                // Earlier items sort first when ages tie.
                let date = now.addingTimeInterval(-item.age - Double(index))
                do {
                    let draft = try await ArtworkFactory.draft(sample: item.sample, paintedFraction: item.painted, date: date)
                    try await create(draft)
                } catch {
                    Log.library.error("Seeding \(item.sample.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
                placeholders.removeAll { $0.id == item.sample.id }
            }
            completion?()
        }
    }

    // MARK: Editing

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var artwork = artwork(with: id), artwork.title != trimmed else { return }
        artwork.title = trimmed
        replace(artwork, resort: false)
        persistMeta(artwork)
    }

    /// Copies an artwork, progress included (restart the copy to paint it again).
    @discardableResult
    func duplicate(_ id: UUID) async throws -> Artwork {
        guard let original = artwork(with: id) else { throw ArtworkStore.StoreError.notFound }
        var copy = original
        copy.id = UUID()
        copy.title = copyTitle(for: original.title)
        copy.createdAt = .now
        copy.modifiedAt = .now
        let store = self.store
        _ = await writes[id]?.value
        try await Background.run { try store.duplicate(id, as: copy) }
        insert(copy)
        return copy
    }

    func restart(_ id: UUID) async {
        guard var artwork = artwork(with: id) else { return }
        let fresh = PaintProgress(regionCount: artwork.regionCount)
        artwork.record(fresh)
        replace(artwork)
        let snapshot = artwork
        enqueue(id) { store in
            try store.writeProgress(fresh, for: id)
            try store.writeMeta(snapshot)
        }
        await refreshThumbnail(id, progress: fresh)
    }

    /// Saves painting progress (called debounced while painting).
    func saveProgress(_ progress: PaintProgress, for id: UUID) {
        guard var artwork = artwork(with: id), artwork.regionCount == progress.regionCount else { return }
        artwork.record(progress)
        replace(artwork)
        let snapshot = artwork
        enqueue(id) { store in
            try store.writeProgress(progress, for: id)
            try store.writeMeta(snapshot)
        }
    }

    /// Re-renders the thumbnail, then publishes its new version to the gallery.
    func refreshThumbnail(_ id: UUID, template: Template? = nil, progress: PaintProgress) async {
        let written = await enqueue(id) { store in
            let t = try template ?? store.readTemplate(id)
            guard let png = TemplateRasterizer.pngData(
                t, painted: progress.painted, style: .thumbnail, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
            else { return }
            try store.writeThumbnail(png, for: id)
        }.value
        guard written, var artwork = artwork(with: id) else { return }
        artwork.thumbnailVersion += 1
        replace(artwork, resort: false)
        persistMeta(artwork)
    }

    // MARK: Deleting (undoable)

    func delete(_ id: UUID) {
        guard let artwork = artwork(with: id) else { return }
        finalizeDeletion()
        artworks.removeAll { $0.id == id }
        recentlyDeleted = artwork
        enqueue(id) { store in try store.moveToTrash(id) }
        purge = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.finalizeDeletion()
        }
    }

    func undoDelete() {
        guard let artwork = recentlyDeleted else { return }
        purge?.cancel()
        recentlyDeleted = nil
        let id = artwork.id
        enqueue(id) { store in try store.restoreFromTrash(id) }
        insert(artwork)
    }

    /// Makes the pending deletion permanent (the undo window closed).
    func finalizeDeletion() {
        guard let artwork = recentlyDeleted else { return }
        purge?.cancel()
        recentlyDeleted = nil
        let id = artwork.id
        enqueue(id) { store in store.purgeTrash(id) }
    }

    // MARK: Loading

    func loadForPainting(_ id: UUID) async throws -> PaintingDocument {
        _ = await writes[id]?.value
        let store = self.store
        return try await Background.run {
            let template = try store.readTemplate(id)
            return PaintingDocument(template: template, progress: store.readProgress(id, regionCount: template.regions.count))
        }
    }

    /// Waits until every queued write has reached the disk.
    func flush() async {
        for task in Array(writes.values) { _ = await task.value }
    }

    // MARK: Internals

    private static func newestFirst(_ a: Artwork, _ b: Artwork) -> Bool { a.modifiedAt > b.modifiedAt }

    private func insert(_ artwork: Artwork) {
        artworks.removeAll { $0.id == artwork.id }
        artworks.append(artwork)
        artworks.sort(by: Self.newestFirst)
    }

    private func replace(_ artwork: Artwork, resort: Bool = true) {
        guard let index = artworks.firstIndex(where: { $0.id == artwork.id }) else { return }
        artworks[index] = artwork
        if resort { artworks.sort(by: Self.newestFirst) }
    }

    private func persistMeta(_ artwork: Artwork) {
        enqueue(artwork.id) { store in try store.writeMeta(artwork) }
    }

    private func copyTitle(for title: String) -> String {
        let titles = Set(artworks.map(\.title))
        var candidate = "\(title) Copy"
        var n = 2
        while titles.contains(candidate) {
            candidate = "\(title) Copy \(n)"
            n += 1
        }
        return candidate
    }

    /// Queues file work for one artwork behind its earlier writes; resolves to success.
    @discardableResult
    private func enqueue(_ id: UUID, _ work: @escaping @Sendable (ArtworkStore) throws -> Void) -> Task<Bool, Never> {
        let previous = writes[id]
        let store = self.store
        let task = Task<Bool, Never> {
            _ = await previous?.value
            do {
                try await Background.run { try work(store) }
                return true
            } catch {
                Log.library.error("Write failed for \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                return false
            }
        }
        writes[id] = task
        return task
    }
}
