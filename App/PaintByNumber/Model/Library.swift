import CoreGraphics
import Foundation
import Observation
import os
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
    /// Artworks whose progress or details didn't reach the disk; cleared by the next
    /// successful save of them.
    private(set) var writeFailures: [UUID: WriteFailure] = [:]

    struct WriteFailure: Equatable {
        var message: String
        var date: Date
    }

    @ObservationIgnored let store: ArtworkStore
    @ObservationIgnored private var writes: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var purge: Task<Void, Never>?
    /// The newest progress submitted per artwork, kept until a write of exactly that
    /// submission succeeds. Retrying saves it, so a retry never puts an older snapshot over
    /// a newer queued one.
    @ObservationIgnored private var unsavedProgress: [UUID: (progress: PaintProgress, token: Int)] = [:]
    /// Artworks whose metadata write failed and hasn't been superseded by a successful one.
    @ObservationIgnored private var unsavedMeta: Set<UUID> = []
    @ObservationIgnored private var nextToken = 0

    /// What a queued write saves, for failure bookkeeping.
    private enum Saves {
        /// Thumbnails, trash: cosmetic or redone later, so failures are only logged.
        case other
        case meta
        case progress(token: Int)
    }

    static let undoWindow: Duration = .seconds(6)
    static let seededKey = "library.seededStarterSamples"
    /// Launches whose seeding produced nothing; seeding is retried until `maxSeedAttempts`.
    static let seedFailuresKey = "library.starterSampleFailures"
    static let maxSeedAttempts = 3

    init(store: ArtworkStore) {
        self.store = store
        store.purgeStaging()
        store.purgeTrash()
        artworks = store.loadAll().sorted(by: Self.newestFirst)
    }

    /// The library used by the running app: the real one, or a throwaway one for demos.
    static func forLaunch() -> Library {
        // Shared files left over from earlier runs. The cutoff spares exports started right
        // after launch; the sweep runs off the main actor so it never delays launch.
        let launch = Date.now
        Task { await Background.run { ArtworkExporter.purgeExports(createdBefore: launch) } }
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if DemoMode.isActive || isTestHost {
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

    /// The newest failed save of an artwork still in the library (a pending deletion hides it).
    var latestWriteFailure: (artwork: Artwork, failure: WriteFailure)? {
        writeFailures
            .compactMap { entry in artwork(with: entry.key).map { (artwork: $0, failure: entry.value) } }
            .max { $0.failure.date < $1.failure.date }
    }

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
    @discardableResult
    func seedIfNeeded(_ samples: [Sample] = Sample.starters, defaults: UserDefaults = .standard) -> Task<Void, Never>? {
        guard !defaults.bool(forKey: Self.seededKey) else { return nil }
        guard artworks.isEmpty else {
            defaults.set(true, forKey: Self.seededKey)
            defaults.removeObject(forKey: Self.seedFailuresKey)
            return nil
        }
        return seed(samples.map { SeedItem(sample: $0) }) { created in
            // Nothing made (say, the device was out of space): try again on later launches,
            // but not forever.
            let failures = created > 0 ? 0 : defaults.integer(forKey: Self.seedFailuresKey) + 1
            if failures == 0 || failures >= Self.maxSeedAttempts {
                defaults.set(true, forKey: Self.seededKey)
                defaults.removeObject(forKey: Self.seedFailuresKey)
            } else {
                defaults.set(failures, forKey: Self.seedFailuresKey)
            }
        }
    }

    struct SeedItem {
        var sample: Sample
        /// Fraction already painted (demos).
        var painted: Double?
        /// How long ago it was last painted; orders the gallery.
        var age: TimeInterval = 0
        /// Demos use smaller photos so they are ready quickly even in Debug builds.
        var photoMaxPixelSize = ArtworkStore.sourceMaxPixelSize
    }

    /// Generates artworks from bundled samples, one after another, showing placeholders
    /// until each is ready. `completion` gets the number of artworks created.
    @discardableResult
    func seed(_ items: [SeedItem], completion: ((_ created: Int) -> Void)? = nil) -> Task<Void, Never> {
        let now = Date.now
        placeholders = items.map { Placeholder(sample: $0.sample) }
        return Task {
            var created = 0
            for (index, item) in items.enumerated() {
                // Earlier items sort first when ages tie.
                let date = now.addingTimeInterval(-item.age - Double(index))
                do {
                    let draft = try await ArtworkFactory.draft(
                        sample: item.sample, paintedFraction: item.painted, date: date,
                        photoMaxPixelSize: item.photoMaxPixelSize)
                    try await create(draft)
                    created += 1
                } catch {
                    Log.library.error("Seeding \(item.sample.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
                placeholders.removeAll { $0.id == item.sample.id }
            }
            completion?(created)
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
        let store = self.store, snapshot = copy
        _ = await writes[id]?.value
        try await Background.run { try store.duplicate(id, as: snapshot) }
        insert(snapshot)
        return snapshot
    }

    func restart(_ id: UUID) async {
        guard var artwork = artwork(with: id) else { return }
        let fresh = PaintProgress(regionCount: artwork.regionCount)
        artwork.record(fresh)
        replace(artwork)
        persistProgress(fresh, of: artwork)
        await refreshThumbnail(id, progress: fresh)
    }

    /// Saves painting progress (called debounced while painting).
    func saveProgress(_ progress: PaintProgress, for id: UUID) {
        guard var artwork = artwork(with: id), artwork.regionCount == progress.regionCount else { return }
        artwork.record(progress)
        replace(artwork)
        persistProgress(progress, of: artwork)
    }

    /// Saves again what a failed write left unsaved: the newest progress submitted, or else
    /// the details. A new failure shows up again in `writeFailures`.
    func retrySaving(_ id: UUID) {
        clearWriteFailure(id)
        guard let artwork = artwork(with: id) else { return }
        if let unsaved = unsavedProgress[id] {
            persistProgress(unsaved.progress, of: artwork)
        } else if unsavedMeta.contains(id) {
            persistMeta(artwork)
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
        clearWriteFailure(id)
        unsavedProgress[id] = nil
        unsavedMeta.remove(id)
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

    /// The photo an artwork was made from ("compare with photo"), decoded off the main actor.
    func sourcePhoto(for id: UUID, maxPixelSize: Int? = nil) async -> CGImage? {
        let store = self.store
        return await Background.run { store.source(id, maxPixelSize: maxPixelSize) }
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
        enqueue(artwork.id, saves: .meta) { store in try store.writeMeta(artwork) }
    }

    /// Writes progress and the details recording it, remembering the progress until it is
    /// on disk.
    private func persistProgress(_ progress: PaintProgress, of artwork: Artwork) {
        let id = artwork.id
        nextToken += 1
        let token = nextToken
        unsavedProgress[id] = (progress, token)
        enqueue(id, saves: .progress(token: token)) { store in
            try store.writeProgress(progress, for: id)
            try store.writeMeta(artwork)
        }
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
    private func enqueue(
        _ id: UUID, saves: Saves = .other, _ work: @escaping @Sendable (ArtworkStore) throws -> Void
    ) -> Task<Bool, Never> {
        let previous = writes[id]
        let store = self.store
        let task = Task<Bool, Never> {
            _ = await previous?.value
            do {
                try await Background.run { try work(store) }
                recordWrite(id, saves, error: nil)
                return true
            } catch {
                Log.library.error("Write failed for \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                recordWrite(id, saves, error: error)
                return false
            }
        }
        writes[id] = task
        return task
    }

    private func recordWrite(_ id: UUID, _ saves: Saves, error: (any Error)?) {
        if let error {
            // Nothing to retry for an artwork deleted meanwhile.
            guard artwork(with: id) != nil || recentlyDeleted?.id == id else { return }
            switch saves {
            case .other: return
            case .meta, .progress: unsavedMeta.insert(id)
            }
            writeFailures[id] = WriteFailure(message: error.localizedDescription, date: .now)
            return
        }
        switch saves {
        case .other: return
        case .meta:
            unsavedMeta.remove(id)
        case .progress(let token):
            if unsavedProgress[id]?.token == token { unsavedProgress[id] = nil }
            // Writes of one artwork land in order, so these details include every earlier change.
            unsavedMeta.remove(id)
        }
        if unsavedProgress[id] == nil, !unsavedMeta.contains(id) { clearWriteFailure(id) }
    }

    /// Only when there is one: every save lands here, and views observe the failures.
    private func clearWriteFailure(_ id: UUID) {
        if writeFailures[id] != nil { writeFailures[id] = nil }
    }
}
