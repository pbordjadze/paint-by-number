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
        #expect(library.seedIfNeeded([espresso], defaults: defaults) == nil)
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
