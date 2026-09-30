import CoreGraphics
import Foundation
import Observation
import os
import PaintCore

/// A template and its saved progress, loaded for painting.
nonisolated struct PaintingDocument: Sendable {
    var template: Template
    var progress: PaintProgress
    /// Something the painter should be told once the painting is on screen.
    var notice: OpenNotice? = nil
}

/// What happened to a painting on its way to the screen.
nonisolated enum OpenNotice: Equatable, Sendable {
    /// The saved progress couldn't be used (damaged, or for another template); it starts fresh.
    case progressReset
    /// The template was regenerated from the photo; `keptProgress` if painted areas carried over.
    case regenerated(keptProgress: Bool)
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
    /// Artworks being regenerated (`regenerate(artwork:settings:)`) and their 0…1 progress.
    private(set) var regenerating: [UUID: Double] = [:]

    /// Why an artwork can't be opened for painting.
    nonisolated enum OpenError: Error, Equatable {
        /// Written by a newer app (metadata, template or progress); kept untouched.
        case needsNewerApp
        /// The template is unreadable; `canRegenerate` if the photo it came from is available.
        case damaged(canRegenerate: Bool)
    }

    nonisolated enum RegenerationError: Error, Equatable {
        case inProgress
        case saveFailed
    }

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
            return nil
        }
        return seed(samples.map { SeedItem(sample: $0) }) {
            defaults.set(true, forKey: Self.seededKey)
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
    /// until each is ready.
    @discardableResult
    func seed(_ items: [SeedItem], completion: (() -> Void)? = nil) -> Task<Void, Never> {
        let now = Date.now
        placeholders = items.map { Placeholder(sample: $0.sample) }
        return Task {
            for (index, item) in items.enumerated() {
                // Earlier items sort first when ages tie.
                let date = now.addingTimeInterval(-item.age - Double(index))
                do {
                    let draft = try await ArtworkFactory.draft(
                        sample: item.sample, paintedFraction: item.painted, date: date,
                        photoMaxPixelSize: item.photoMaxPixelSize)
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
        guard !trimmed.isEmpty, var artwork = artwork(with: id), !artwork.needsNewerApp, artwork.title != trimmed else { return }
        artwork.title = trimmed
        replace(artwork, resort: false)
        persistMeta(artwork)
    }

    /// Copies an artwork, progress included (restart the copy to paint it again).
    @discardableResult
    func duplicate(_ id: UUID) async throws -> Artwork {
        guard let original = artwork(with: id) else { throw ArtworkStore.StoreError.notFound }
        // A copy would need this app to rewrite the newer app's metadata.
        guard !original.needsNewerApp else { throw OpenError.needsNewerApp }
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
        guard var artwork = artwork(with: id), !artwork.needsNewerApp else { return }
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
        guard var artwork = artwork(with: id), !artwork.needsNewerApp else { return }
        guard artwork.regionCount == progress.regionCount else {
            Log.library.error("Not saving progress of \(id.uuidString, privacy: .public): \(progress.regionCount) regions, artwork has \(artwork.regionCount)")
            return
        }
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
        guard artwork(with: id)?.needsNewerApp != true else { return }
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

    /// Loads an artwork's template and progress. Throws `OpenError` when it can't be painted;
    /// progress that can't be used is replaced by fresh progress (`OpenNotice.progressReset`,
    /// reported once: the fresh progress is saved) and stale metadata is repaired.
    func loadForPainting(_ id: UUID) async throws -> PaintingDocument {
        guard let artwork = artwork(with: id) else { throw OpenError.damaged(canRegenerate: false) }
        guard !artwork.needsNewerApp else { throw OpenError.needsNewerApp }
        _ = await writes[id]?.value
        let store = self.store
        let (template, saved) = try await Background.run { () throws -> (Template, ArtworkStore.SavedProgress) in
            let template: Template
            do {
                template = try store.readTemplate(id)
            } catch let error as Template.CodingError where error.requiresNewerReader {
                throw OpenError.needsNewerApp
            } catch {
                Log.library.error("Template of \(id.uuidString, privacy: .public) is unreadable: \(String(describing: error), privacy: .public)")
                throw OpenError.damaged(canRegenerate: ArtworkFactory.canRegenerate(artwork, store: store))
            }
            do {
                return (template, try store.readProgress(id, regionCount: template.regions.count))
            } catch {
                throw OpenError.needsNewerApp
            }
        }

        let reset: Bool
        switch saved.problem {
        case .damaged?, .mismatched?: reset = true
        // A painting that had progress lost its file; say so rather than silently start over.
        case .missing?: reset = artwork.paintedCount > 0
        case nil: reset = false
        }
        // Keep the metadata true to what is on disk (the gallery and saveProgress rely on it),
        // without moving the painting in the gallery's order.
        if let current = self.artwork(with: id) {
            var updated = current
            updated.adopt(template, settings: current.settings)
            if reset || updated.paintedCount != saved.progress.paintedCount {
                updated.record(saved.progress, at: updated.modifiedAt)
            }
            if updated != current {
                replace(updated, resort: false)
                let snapshot = updated, progress = saved.progress
                enqueue(id) { store in
                    if reset { try store.writeProgress(progress, for: id) }
                    try store.writeMeta(snapshot)
                }
            }
        }
        return PaintingDocument(template: template, progress: saved.progress, notice: reset ? .progressReset : nil)
    }

    /// Generates an artwork's template again from its photo (`source.jpg`, or the bundled
    /// sample) with `settings`, off the main actor, and swaps it in atomically. Progress
    /// carries over by painted area when the old template is still readable; otherwise the
    /// painting starts fresh. Recovers damaged paintings, and is the entry point for
    /// re-tuning an artwork's settings. `regenerating[id]` reports progress meanwhile.
    func regenerate(artwork id: UUID, settings: GenerationSettings) async throws -> PaintingDocument {
        guard let artwork = artwork(with: id) else { throw ArtworkStore.StoreError.notFound }
        guard !artwork.needsNewerApp else { throw OpenError.needsNewerApp }
        guard regenerating[id] == nil else { throw RegenerationError.inProgress }
        regenerating[id] = 0
        defer { regenerating[id] = nil }
        _ = await writes[id]?.value

        // Called on pipeline threads; hops to the main actor. The last 5 % are for saving.
        let report: @Sendable (Float) -> Void = { value in
            Task { @MainActor in
                guard self.regenerating[id] != nil else { return }
                self.regenerating[id] = 0.95 * Double(value)
            }
        }
        let store = self.store
        let (template, progress, thumbnail) = try await Background.run { () throws -> (Template, PaintProgress, Data?) in
            let old: Template?
            do {
                old = try store.readTemplate(id)
            } catch let error as Template.CodingError where error.requiresNewerReader {
                throw OpenError.needsNewerApp
            } catch {
                old = nil
            }
            // Progress from a newer app is never overwritten, even when the template is damaged.
            let saved: ArtworkStore.SavedProgress
            do {
                saved = try store.readProgress(id, regionCount: old?.regions.count ?? 0)
            } catch {
                throw OpenError.needsNewerApp
            }
            let photo = try ArtworkFactory.sourcePhoto(of: artwork, in: store)
            let template = try ArtworkFactory.template(from: photo, settings: settings, progress: report)
            let progress = old.map { saved.progress.remapped(from: $0, to: template) }
                ?? PaintProgress(regionCount: template.regions.count)
            let thumbnail = TemplateRasterizer.pngData(
                template, painted: progress.painted, style: .thumbnail, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
            return (template, progress, thumbnail)
        }
        try Task.checkCancellation()

        var updated = self.artwork(with: id) ?? artwork
        updated.adopt(template, settings: settings)
        updated.record(progress)
        updated.thumbnailVersion += 1
        let snapshot = updated
        let saved = await enqueue(id) { store in
            try store.replaceContents(of: snapshot, template: template, progress: progress, thumbnailPNG: thumbnail)
        }.value
        guard saved else { throw RegenerationError.saveFailed }
        replace(updated)
        return PaintingDocument(template: template, progress: progress, notice: .regenerated(keptProgress: progress.paintedCount > 0))
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
