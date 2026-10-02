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
    /// Artworks whose progress or details didn't reach the disk; cleared by the next
    /// successful save of them.
    private(set) var writeFailures: [UUID: WriteFailure] = [:]

    struct WriteFailure: Equatable {
        var message: String
        var date: Date
    }

    /// Why an artwork can't be opened for painting.
    nonisolated enum OpenError: Error, Equatable {
        /// Written by a newer app (metadata, template or progress); kept untouched.
        case needsNewerApp
        /// The template is unreadable; `canRegenerate` if the photo it came from is available.
        case damaged(canRegenerate: Bool)
        /// A file couldn't be read this time (an I/O or protection error, not damage); nothing
        /// was changed, so opening it again may work.
        case unreadable
    }

    nonisolated enum RegenerationError: Error, Equatable {
        case inProgress
        case saveFailed
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

    /// The library used by the running app: the real one (Debug builds: or a throwaway one
    /// for demos and the test host, so they never touch real paintings).
    static func forLaunch() -> Library {
        // Shared files left over from earlier runs. The cutoff spares exports started right
        // after launch; the sweep runs off the main actor so it never delays launch.
        let launch = Date.now
        Task { await Background.run { ArtworkExporter.purgeExports(createdBefore: launch) } }
        #if DEBUG
        if DemoMode.isActive || DemoMode.isTestHost {
            let root = FileManager.default.temporaryDirectory.appending(path: "DemoLibrary", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
            let library = Library(store: ArtworkStore(root: root))
            ShellDemo.current?.prepare(library)
            return library
        }
        #endif
        let library = Library(store: ArtworkStore(root: ArtworkStore.defaultRoot))
        library.seedIfNeeded()
        return library
    }

    // MARK: Queries

    /// Favorites first, then newest change first.
    var inProgress: [Artwork] { Self.favoritesFirst(artworks.filter { !$0.isComplete }) }
    /// Favorites first, then most recently finished first.
    var finished: [Artwork] {
        Self.favoritesFirst(
            artworks.filter(\.isComplete).sorted { ($0.completedAt ?? $0.modifiedAt) > ($1.completedAt ?? $1.modifiedAt) })
    }
    func inProgress(matching query: GalleryQuery) -> [Artwork] { inProgress.filter(query.includes) }
    func finished(matching query: GalleryQuery) -> [Artwork] { finished.filter(query.includes) }
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
            settingsOrigin: draft.settingsOrigin, paintingLength: draft.paintingLength,
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
        guard !trimmed.isEmpty, var artwork = artwork(with: id), !artwork.needsNewerApp, artwork.title != trimmed else { return }
        artwork.title = trimmed
        replace(artwork, resort: false)
        persistMeta(artwork)
    }

    func setFavorite(_ id: UUID, _ favorite: Bool) {
        guard var artwork = artwork(with: id), !artwork.needsNewerApp, artwork.isFavorite != favorite else { return }
        artwork.isFavorite = favorite
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
        let snapshot = copy
        // In line with the original's writes, so none lands while its folder is being copied.
        guard await enqueue(id, { try $0.duplicate(id, as: snapshot) }).value else {
            throw CocoaError(.fileWriteUnknown)
        }
        insert(snapshot)
        return snapshot
    }

    func restart(_ id: UUID) async {
        guard artwork(with: id)?.needsNewerApp == false else { return }
        // The fresh progress is sized from the template: metadata can be stale, and progress
        // that doesn't fit would be discarded on the next open with a "couldn't be read" notice.
        _ = await writes[id]?.value
        let store = self.store
        let template: Template?
        do {
            template = try await Background.run { try store.readTemplate(id) }
        } catch let error as Template.CodingError where error.requiresNewerReader {
            return
        } catch {
            template = nil  // damaged: opening offers to regenerate, which sizes progress itself
        }
        guard var artwork = artwork(with: id), !artwork.needsNewerApp else { return }
        if let template { artwork.adopt(template, settings: artwork.settings) }
        let fresh = PaintProgress(regionCount: artwork.regionCount)
        artwork.record(fresh)
        replace(artwork)
        persistProgress(fresh, of: artwork)
        await refreshThumbnail(id, template: template, progress: fresh)
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
        persistProgress(progress, of: artwork)
    }

    /// Saves again what a failed write left unsaved: the newest progress submitted, or else
    /// the details. A new failure shows up again in `writeFailures`.
    func retrySaving(_ id: UUID) {
        clearWriteFailure(id)
        guard let artwork = artwork(with: id) else { return }
        if let unsaved = unsavedProgress[id], unsaved.progress.regionCount == artwork.regionCount {
            persistProgress(unsaved.progress, of: artwork)
        } else if unsavedMeta.contains(id) {
            persistMeta(artwork)
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
        clearWriteFailure(id)
        unsavedProgress[id] = nil
        unsavedMeta.remove(id)
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
            } catch is PaintProgress.CodingError {
                throw OpenError.needsNewerApp
            } catch {
                Log.library.error("Progress of \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
                throw OpenError.unreadable
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
        let (old, savedProgress, photo) = try await Background.run { () throws -> (Template?, ArtworkStore.SavedProgress, RGBAImage) in
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
            } catch is PaintProgress.CodingError {
                throw OpenError.needsNewerApp
            } catch {
                throw OpenError.unreadable
            }
            return (old, saved, try ArtworkFactory.sourcePhoto(of: artwork, in: store))
        }
        let template = try await ArtworkFactory.template(from: photo, settings: settings, progress: report)
        let (progress, thumbnail) = await Background.run { () -> (PaintProgress, Data?) in
            let progress = old.map { savedProgress.progress.remapped(from: $0, to: template) }
                ?? PaintProgress(regionCount: template.regions.count)
            let thumbnail = TemplateRasterizer.pngData(
                template, painted: progress.painted, style: .thumbnail, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
            return (progress, thumbnail)
        }
        try Task.checkCancellation()

        var updated = self.artwork(with: id) ?? artwork
        updated.adopt(template, settings: settings)
        updated.format = Artwork.currentFormat
        updated.record(progress)
        updated.thumbnailVersion += 1
        let snapshot = updated
        let saved = await enqueue(id) { store in
            try store.replaceContents(of: snapshot, template: template, progress: progress, thumbnailPNG: thumbnail)
        }.value
        guard saved else { throw RegenerationError.saveFailed }
        // The new contents include the newest progress and details: nothing older is left to retry.
        unsavedProgress[id] = nil
        unsavedMeta.remove(id)
        clearWriteFailure(id)
        replace(updated)
        return PaintingDocument(template: template, progress: progress, notice: .regenerated(keptProgress: progress.paintedCount > 0))
    }

    /// The photo an artwork was made from (the painting screen's photo peek), decoded off the main actor.
    func sourcePhoto(for id: UUID, maxPixelSize: Int? = nil) async -> CGImage? {
        let store = self.store
        return await Background.run { store.source(id, maxPixelSize: maxPixelSize) }
    }

    /// Waits until every queued write has reached the disk.
    func flush() async {
        for task in Array(writes.values) { _ = await task.value }
    }

    // MARK: Internals

    /// A stable partition: each group keeps the order it came in.
    private static func favoritesFirst(_ list: [Artwork]) -> [Artwork] {
        list.filter(\.isFavorite) + list.filter { !$0.isFavorite }
    }

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
        var candidate = String(localized: "library.copyTitle", defaultValue: "\(title) Copy",
                               comment: "Title of a duplicated painting; the argument is the original's title")
        var n = 2
        while titles.contains(candidate) {
            candidate = String(localized: "library.copyTitle.numbered", defaultValue: "\(title) Copy \(n)",
                               comment: "Title of a second or later duplicate of a painting; the arguments are the original's title and the copy number (2, 3, …)")
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
            guard artwork(with: id) != nil || recentlyDeleted?.id == id else {
                unsavedProgress[id] = nil
                unsavedMeta.remove(id)
                return
            }
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
