import AVFoundation
import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct LibraryTests {
    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    private func draft(title: String = "Stripes", painted: [Int] = [], photo: CGImage? = nil) -> ArtworkDraft {
        var progress = PaintProgress(regionCount: 3)
        for region in painted { progress.paint(region) }
        return ArtworkDraft(
            title: title, template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12),
            photo: photo, sampleName: nil, progress: painted.isEmpty ? nil : progress)
    }

    @Test func createsAndReloads() async throws {
        let library = makeLibrary()
        let photo = try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: 300))
        let artwork = try await library.create(draft(photo: photo))
        #expect(library.artworks.map(\.id) == [artwork.id])
        #expect(artwork.regionCount == 3 && artwork.colorCount == 3)
        #expect(artwork.width == 60 && artwork.height == 40)
        for file in ArtworkStore.File.allCases {
            #expect(FileManager.default.fileExists(atPath: library.store.url(file, of: artwork.id).path), "\(file.rawValue)")
        }

        let reloaded = makeLibrary()
        #expect(reloaded.artworks == [artwork])
        let document = try await reloaded.loadForPainting(artwork.id)
        #expect(document.template == Fixtures.stripes())
        #expect(document.progress.paintedCount == 0)
        #expect(reloaded.store.source(artwork.id)?.width == 300)
    }

    @Test func savesProgressCompletionAndThumbnail() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        var progress = PaintProgress(regionCount: 3)
        progress.paint(1)
        library.saveProgress(progress, for: artwork.id)
        #expect(library.artwork(with: artwork.id)?.paintedCount == 1)
        await library.flush()

        let reloaded = makeLibrary()
        #expect(reloaded.artworks.first?.paintedCount == 1)
        let document = try await reloaded.loadForPainting(artwork.id)
        #expect(document.progress.isPainted(1) && !document.progress.isPainted(0))

        progress.paint(0)
        progress.paint(2)
        reloaded.saveProgress(progress, for: artwork.id)
        #expect(reloaded.finished.map(\.id) == [artwork.id])
        #expect(reloaded.inProgress.isEmpty)
        #expect(reloaded.artwork(with: artwork.id)?.completedAt != nil)

        await reloaded.refreshThumbnail(artwork.id, progress: progress)
        #expect(reloaded.artwork(with: artwork.id)?.thumbnailVersion == 2)
        await reloaded.flush()
        let thumbnail = try #require(reloaded.store.thumbnail(artwork.id))
        let pixels = PixelReader(thumbnail)
        #expect(pixels[pixels.width / 6, pixels.height / 2] == SIMD3(255, 0, 0))
        #expect(makeLibrary().artwork(with: artwork.id)?.thumbnailVersion == 2)
    }

    @Test func exportsShareFiles() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(title: "Stripes: Blue/Red", painted: [2, 0, 1]))
        #expect(artwork.isComplete)

        let png = try await PaintingImageFile(store: library.store, artwork: artwork).export()
        #expect(png.lastPathComponent == "Stripes- Blue-Red.png")
        #expect(ImageCodec.image(at: png)?.width == ArtworkExporter.imagePixelSize)

        let movie = try await TimelapseRequest(title: artwork.title, source: .saved(store: library.store, artwork: artwork))
            .render(longSide: 320)
        #expect(movie.pathExtension == "mp4")
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 2)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.width == 320 && size.height == 212)
    }

    @Test func renamesDuplicatesAndRestarts() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0]))
        #expect(artwork.paintedCount == 1)
        library.rename(artwork.id, to: "  Sunset  ")
        #expect(library.artwork(with: artwork.id)?.title == "Sunset")
        library.rename(artwork.id, to: "   ")
        #expect(library.artwork(with: artwork.id)?.title == "Sunset")

        let copy = try await library.duplicate(artwork.id)
        #expect(copy.id != artwork.id)
        #expect(copy.title == "Sunset Copy")
        #expect(copy.paintedCount == 1)

        await library.restart(artwork.id)
        #expect(library.artwork(with: artwork.id)?.paintedCount == 0)
        await library.flush()

        let reloaded = makeLibrary()
        #expect(Set(reloaded.artworks.map(\.title)) == ["Sunset", "Sunset Copy"])
        #expect(try await reloaded.loadForPainting(artwork.id).progress.paintedCount == 0)
        #expect(try await reloaded.loadForPainting(copy.id).progress.paintedCount == 1)
    }

    @Test func deletionCanBeUndoneOrFinalized() async throws {
        let library = makeLibrary()
        let a = try await library.create(draft(title: "A"))
        let b = try await library.create(draft(title: "B"))

        library.delete(a.id)
        #expect(library.artwork(with: a.id) == nil)
        #expect(library.recentlyDeleted?.id == a.id)
        await library.flush()
        #expect(!library.store.exists(a.id))
        #expect(library.store.isInTrash(a.id))

        library.undoDelete()
        #expect(library.recentlyDeleted == nil)
        #expect(library.artwork(with: a.id) != nil)
        await library.flush()
        #expect(library.store.exists(a.id))

        library.delete(b.id)
        library.finalizeDeletion()
        await library.flush()
        #expect(!library.store.exists(b.id))
        #expect(!library.store.isInTrash(b.id))
        #expect(makeLibrary().artworks.map(\.id) == [a.id])
    }

    @Test func toleratesCorruptFiles() async throws {
        let library = makeLibrary()
        let good = try await library.create(draft(title: "Good"))
        let badTemplate = try await library.create(draft(title: "Bad template"))
        let badProgress = try await library.create(draft(title: "Bad progress", painted: [0, 1]))
        let store = library.store
        let fm = FileManager.default

        let badMeta = UUID()
        try fm.createDirectory(at: store.directory(for: badMeta), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.url(.meta, of: badMeta))
        try fm.createDirectory(at: store.directory(for: UUID()), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: store.root.appending(path: "notes.txt"))
        try fm.createDirectory(at: store.root.appending(path: ".staging/\(UUID().uuidString)"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: store.url(.template, of: badTemplate.id))
        try Data("garbage".utf8).write(to: store.url(.progress, of: badProgress.id))

        let reloaded = makeLibrary()
        #expect(Set(reloaded.artworks.map(\.id)) == [good.id, badTemplate.id, badProgress.id])
        #expect(try fm.contentsOfDirectory(atPath: store.root.appending(path: ".staging").path).isEmpty)
        await #expect(throws: (any Error).self) { try await reloaded.loadForPainting(badTemplate.id) }
        let recovered = try await reloaded.loadForPainting(badProgress.id)
        #expect(recovered.progress.regionCount == 3)
        #expect(recovered.progress.paintedCount == 0)

        // A template that decompresses but is truncated must also be rejected.
        let encoded = Fixtures.stripes().encoded()
        let truncated = try (encoded.prefix(encoded.count / 2) as NSData).compressed(using: .lzfse) as Data
        try truncated.write(to: store.url(.template, of: good.id))
        await #expect(throws: (any Error).self) { try await reloaded.loadForPainting(good.id) }
    }

    @Test func seedsStarterSamplesOnce() async throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = makeLibrary()
        let espresso = try #require(Sample.named("espresso"))

        let task = try #require(library.seedIfNeeded([espresso], defaults: defaults))
        #expect(library.placeholders.map(\.id) == ["espresso"])
        #expect(!library.isEmpty)
        await task.value
        #expect(library.placeholders.isEmpty)
        #expect(library.artworks.map(\.title) == ["Espresso"])
        #expect(library.artworks.first?.sampleName == "espresso")
        #expect(defaults.bool(forKey: Library.seededKey))
        #expect(defaults.object(forKey: Library.seedFailuresKey) == nil)
        #expect(library.seedIfNeeded([espresso], defaults: defaults) == nil)
    }

    @Test func seedingRetriesAfterFailuresAndGivesUpAfterThree() async throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = makeLibrary()
        let missing = Sample(id: "missing", title: "Missing")

        for launch in 1..<Library.maxSeedAttempts {
            let task = try #require(library.seedIfNeeded([missing], defaults: defaults), "launch \(launch)")
            await task.value
            #expect(!defaults.bool(forKey: Library.seededKey))
            #expect(defaults.integer(forKey: Library.seedFailuresKey) == launch)
        }
        let last = try #require(library.seedIfNeeded([missing], defaults: defaults))
        await last.value
        #expect(defaults.bool(forKey: Library.seededKey))
        #expect(defaults.object(forKey: Library.seedFailuresKey) == nil)
        #expect(library.seedIfNeeded([missing], defaults: defaults) == nil)
        #expect(library.artworks.isEmpty)
        #expect(library.placeholders.isEmpty)
    }

    @Test func seedingCountsPartialSuccess() async throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = makeLibrary()
        let espresso = try #require(Sample.named("espresso"))

        let task = try #require(library.seedIfNeeded([Sample(id: "missing", title: "Missing"), espresso], defaults: defaults))
        await task.value
        #expect(library.artworks.map(\.title) == ["Espresso"])
        #expect(defaults.bool(forKey: Library.seededKey))
        #expect(defaults.object(forKey: Library.seedFailuresKey) == nil)
    }

    // MARK: Write failures

    /// Makes writes of `file` fail: a non-empty directory in its place can't be replaced by the
    /// atomic write's rename (EISDIR or ENOTEMPTY, whichever the platform reports).
    private func sabotage(_ file: ArtworkStore.File, of id: UUID, in library: Library) throws {
        let url = library.store.url(file, of: id)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appending(path: "blocker"))
    }

    private func repair(_ file: ArtworkStore.File, of id: UUID, in library: Library) throws {
        try FileManager.default.removeItem(at: library.store.url(file, of: id))
    }

    private func progress(painting regions: [Int]) -> PaintProgress {
        var progress = PaintProgress(regionCount: 3)
        for region in regions { progress.paint(region) }
        return progress
    }

    private func savedProgress(_ id: UUID) async throws -> PaintProgress {
        try await makeLibrary().loadForPainting(id).progress
    }

    @Test func surfacesWriteFailuresUntilASaveSucceeds() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        await library.flush()
        #expect(library.writeFailures.isEmpty)

        try sabotage(.progress, of: artwork.id, in: library)
        library.saveProgress(progress(painting: [0]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)
        #expect(library.latestWriteFailure?.artwork.id == artwork.id)

        try repair(.progress, of: artwork.id, in: library)
        library.retrySaving(artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(library.latestWriteFailure == nil)
        #expect(try await savedProgress(artwork.id).isPainted(0))

        // A later save that succeeds clears the error too, and its progress is what's kept.
        try sabotage(.progress, of: artwork.id, in: library)
        library.saveProgress(progress(painting: [0, 1]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)
        try repair(.progress, of: artwork.id, in: library)
        library.saveProgress(progress(painting: [0, 2]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        let saved = try await savedProgress(artwork.id)
        #expect(saved.isPainted(2) && !saved.isPainted(1))
    }

    @Test func retryNeverWritesAnOlderSnapshot() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        try sabotage(.progress, of: artwork.id, in: library)
        library.saveProgress(progress(painting: [1]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)

        try repair(.progress, of: artwork.id, in: library)
        library.saveProgress(progress(painting: [2]), for: artwork.id)
        library.retrySaving(artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        let saved = try await savedProgress(artwork.id)
        #expect(saved.isPainted(2) && !saved.isPainted(1))
    }

    @Test func metadataWriteFailuresAreRetried() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        try sabotage(.meta, of: artwork.id, in: library)
        library.rename(artwork.id, to: "Sunset")
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)

        try repair(.meta, of: artwork.id, in: library)
        library.retrySaving(artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(makeLibrary().artwork(with: artwork.id)?.title == "Sunset")
    }

    @Test func thumbnailWriteFailuresOnlyLog() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        try sabotage(.thumbnail, of: artwork.id, in: library)
        await library.refreshThumbnail(artwork.id, progress: progress(painting: [0]))
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion)
    }

    @Test func failedWriteOfADeletedArtworkIsHiddenThenDropped() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        try sabotage(.progress, of: artwork.id, in: library)
        library.saveProgress(progress(painting: [0]), for: artwork.id)
        await library.flush()
        #expect(library.latestWriteFailure?.artwork.id == artwork.id)

        library.delete(artwork.id)
        #expect(library.latestWriteFailure == nil)
        library.undoDelete()
        #expect(library.latestWriteFailure?.artwork.id == artwork.id)

        library.delete(artwork.id)
        library.finalizeDeletion()
        await library.flush()
        #expect(library.writeFailures.isEmpty)
    }

    @Test func artworkDecodingToleratesMissingFields() throws {
        let id = UUID().uuidString
        let minimal = #"{"id":"\#(id)","width":10,"height":20,"regionCount":5}"#
        let artwork = try JSONDecoder().decode(Artwork.self, from: Data(minimal.utf8))
        #expect(artwork.title.isEmpty)
        #expect(artwork.paintedCount == 0)
        #expect(artwork.settings == GenerationSettings())
        let invalid = #"{"id":"\#(id)","width":0,"height":20,"regionCount":5}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Artwork.self, from: Data(invalid.utf8)) }
    }
}
