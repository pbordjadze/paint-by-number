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

        let movie = try await TimelapseVideoFile(store: library.store, artwork: artwork).export(longSide: 320)
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
        // Neither a stored photo nor a sample to regenerate from.
        await #expect(throws: Library.OpenError.damaged(canRegenerate: false)) {
            try await reloaded.loadForPainting(badTemplate.id)
        }

        // Unreadable progress: the painting opens fresh, says so once, and keeps its place.
        let modifiedAt = try #require(reloaded.artwork(with: badProgress.id)).modifiedAt
        let recovered = try await reloaded.loadForPainting(badProgress.id)
        #expect(recovered.notice == .progressReset)
        #expect(recovered.progress == PaintProgress(regionCount: 3))
        #expect(reloaded.artwork(with: badProgress.id)?.paintedCount == 0)
        await reloaded.flush()
        #expect(try store.readMeta(badProgress.id).paintedCount == 0)
        let reopened = try await reloaded.loadForPainting(badProgress.id)
        #expect(reopened.notice == nil)
        #expect(reloaded.artwork(with: badProgress.id)?.modifiedAt == modifiedAt)
        #expect(makeLibrary().artwork(with: badProgress.id)?.modifiedAt == modifiedAt)

        // A template that decompresses but is truncated must also be rejected.
        let encoded = Fixtures.stripes().encoded()
        let truncated = try (encoded.prefix(encoded.count / 2) as NSData).compressed(using: .lzfse) as Data
        try truncated.write(to: store.url(.template, of: good.id))
        await #expect(throws: Library.OpenError.damaged(canRegenerate: false)) {
            try await reloaded.loadForPainting(good.id)
        }
    }

    @Test func newerTemplateNeedsNewerApp() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        var encoded = Fixtures.stripes().encoded()
        encoded.replaceSubrange(4..<8, with: withUnsafeBytes(of: UInt32(99)) { Data($0) })
        let compressed = try (encoded as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: library.store.url(.template, of: artwork.id))
        await #expect(throws: Library.OpenError.needsNewerApp) { try await library.loadForPainting(artwork.id) }
        #expect(try Data(contentsOf: library.store.url(.template, of: artwork.id)) == compressed)
    }

    /// Progress written by a newer app is never replaced, not even by regenerating.
    @Test func newerProgressIsKept() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0], photo: try stripesPhoto()))
        let url = library.store.url(.progress, of: artwork.id)
        var bytes = try Data(contentsOf: url)
        bytes.replaceSubrange(4..<8, with: withUnsafeBytes(of: UInt32(2)) { Data($0) })
        try bytes.write(to: url)

        await #expect(throws: Library.OpenError.needsNewerApp) { try await library.loadForPainting(artwork.id) }
        await #expect(throws: Library.OpenError.needsNewerApp) {
            try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        }
        await library.flush()
        #expect(try Data(contentsOf: url) == bytes)
        #expect(library.regenerating.isEmpty)
    }

    /// Metadata from a newer app: listed (and deletable), but never opened or rewritten.
    @Test func newerMetaFormatIsReadOnly() async throws {
        let artwork = try await makeLibrary().create(draft(painted: [0]))
        let metaURL = ArtworkStore(root: root).url(.meta, of: artwork.id)
        let meta = Data(#"{"id":"\#(artwork.id.uuidString)","format":99,"title":"Future","regionCount":3,"hologram":{"layers":4}}"#.utf8)
        try meta.write(to: metaURL)

        let library = makeLibrary()
        let listed = try #require(library.artwork(with: artwork.id))
        #expect(listed.needsNewerApp)
        #expect(listed.title == "Future")
        await #expect(throws: Library.OpenError.needsNewerApp) { try await library.loadForPainting(artwork.id) }
        await #expect(throws: Library.OpenError.needsNewerApp) {
            try await library.regenerate(artwork: artwork.id, settings: listed.settings)
        }
        await #expect(throws: Library.OpenError.needsNewerApp) { try await library.duplicate(artwork.id) }

        library.rename(artwork.id, to: "Renamed")
        var progress = PaintProgress(regionCount: 3)
        progress.paint(1)
        library.saveProgress(progress, for: artwork.id)
        await library.restart(artwork.id)
        await library.flush()
        #expect(try Data(contentsOf: metaURL) == meta)
        #expect(library.artwork(with: artwork.id) == listed)
        #expect(library.artworks.count == 1)

        library.delete(artwork.id)
        await library.flush()
        #expect(library.store.isInTrash(artwork.id))
    }

    @Test func progressMismatchIsGraceful() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0]))
        var other = PaintProgress(regionCount: 5)
        other.paint(4)
        try library.store.writeProgress(other, for: artwork.id)

        let document = try await library.loadForPainting(artwork.id)
        #expect(document.notice == .progressReset)
        #expect(document.progress == PaintProgress(regionCount: 3))
        let session = try PaintingSession(template: document.template, progress: document.progress)
        #expect(session.progress.paintedCount == 0)
        #expect(library.artwork(with: artwork.id)?.paintedCount == 0)
    }

    /// Metadata that disagrees with the files is corrected on open, so saving works again.
    @Test func staleMetaIsRepairedOnOpen() async throws {
        let artwork = try await makeLibrary().create(draft(painted: [0]))
        var stale = artwork
        stale.regionCount = 7
        stale.paintedCount = 4
        let store = ArtworkStore(root: root)
        try store.writeMeta(stale)

        let library = makeLibrary()
        let modifiedAt = try #require(library.artwork(with: artwork.id)).modifiedAt
        #expect(library.artwork(with: artwork.id)?.regionCount == 7)
        let document = try await library.loadForPainting(artwork.id)
        #expect(document.notice == nil)
        #expect(document.progress.paintedCount == 1)
        let repaired = try #require(library.artwork(with: artwork.id))
        #expect(repaired.regionCount == 3 && repaired.paintedCount == 1)
        #expect(repaired.modifiedAt == modifiedAt)

        var progress = document.progress
        progress.paint(2)
        library.saveProgress(progress, for: artwork.id)
        await library.flush()
        #expect(try store.readMeta(artwork.id).regionCount == 3)
        #expect(try store.readMeta(artwork.id).paintedCount == 2)
        #expect(try store.readProgress(artwork.id, regionCount: 3).progress == progress)
    }

    @Test func regenerateKeepsProgressWhenRegionMapsMatch() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0], photo: try stripesPhoto()))
        let store = library.store
        let extra = store.directory(for: artwork.id).appending(path: "future-data.bin")
        try Data([4, 2]).write(to: extra)
        let source = try Data(contentsOf: store.url(.source, of: artwork.id))
        let settings = GenerationSettings(colorCount: 6, detail: 0)

        let document = try await library.regenerate(artwork: artwork.id, settings: settings)
        #expect(document.notice == .regenerated(keptProgress: true))
        #expect(library.regenerating.isEmpty)
        let template = document.template
        #expect(template.pipelineVersion == TemplateGenerator.pipelineVersion)
        // The photo's stripes: only the left one was painted.
        let stripes = try thirds(of: template)
        #expect(Set(stripes).count == 3)
        #expect(document.progress.isPainted(stripes[0]))
        #expect(!document.progress.isPainted(stripes[1]) && !document.progress.isPainted(stripes[2]))

        let meta = try #require(library.artwork(with: artwork.id))
        #expect(meta.settings == settings)
        #expect(meta.pipelineVersion == Int(TemplateGenerator.pipelineVersion))
        #expect(meta.regionCount == template.regions.count && meta.colorCount == template.palette.count)
        #expect(meta.paintedCount == document.progress.paintedCount)
        #expect(meta.thumbnailVersion == artwork.thumbnailVersion + 1)
        #expect(try Data(contentsOf: store.url(.source, of: artwork.id)) == source)
        #expect(try Data(contentsOf: extra) == Data([4, 2]))
        #expect(try fileNames(in: store.root.appending(path: ".staging")).isEmpty)

        let reloaded = makeLibrary()
        #expect(reloaded.artwork(with: artwork.id) == meta)
        let reopened = try await reloaded.loadForPainting(artwork.id)
        #expect(reopened.template == template)
        #expect(reopened.progress == document.progress)
        #expect(reopened.notice == nil)

        // Regenerating again with the same settings carries the newer strokes, in order.
        var progress = document.progress
        progress.activeSeconds += 30
        progress.paint(stripes[1])
        library.saveProgress(progress, for: artwork.id)
        let again = try await library.regenerate(artwork: artwork.id, settings: settings)
        let regions = try thirds(of: again.template)
        #expect(again.progress.isPainted(regions[0]) && again.progress.isPainted(regions[1]))
        #expect(!again.progress.isPainted(regions[2]))
        let order = again.progress.log.map { Int($0.region) }
        let left = try #require(order.firstIndex(of: regions[0]))
        let middle = try #require(order.firstIndex(of: regions[1]))
        #expect(left < middle)
        #expect(again.progress.activeSeconds == progress.activeSeconds)
    }

    @Test func regenerateRestartsWhenTemplateUnreadable() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0, 1], photo: try stripesPhoto()))
        try Data("damaged".utf8).write(to: library.store.url(.template, of: artwork.id))
        await #expect(throws: Library.OpenError.damaged(canRegenerate: true)) {
            try await library.loadForPainting(artwork.id)
        }

        let document = try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        #expect(document.notice == .regenerated(keptProgress: false))
        #expect(document.progress == PaintProgress(regionCount: document.template.regions.count))
        let meta = try #require(library.artwork(with: artwork.id))
        #expect(meta.regionCount == document.template.regions.count)
        #expect(meta.paintedCount == 0 && meta.activeSeconds == 0)
        #expect(meta.pipelineVersion == Int(TemplateGenerator.pipelineVersion))

        let reopened = try await makeLibrary().loadForPainting(artwork.id)
        #expect(reopened.template == document.template)
        #expect(reopened.notice == nil)
    }

    @Test func regenerateWithoutSourceFails() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        let url = library.store.url(.template, of: artwork.id)
        let before = try Data(contentsOf: url)
        await #expect(throws: ArtworkFactory.FactoryError.sourceUnavailable) {
            try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        }
        #expect(try Data(contentsOf: url) == before)
        #expect(library.regenerating.isEmpty)
        #expect(library.artwork(with: artwork.id) == artwork)
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
        #expect(!artwork.needsNewerApp)
        #expect(artwork.pipelineVersion == 0)

        // A newer app's metadata always yields a (read-only) gallery entry.
        let newer = #"{"id":"\#(id)","format":2}"#
        let future = try JSONDecoder().decode(Artwork.self, from: Data(newer.utf8))
        #expect(future.needsNewerApp)
        #expect(future.width == 1 && future.height == 1 && future.regionCount == 0)
    }

    // MARK: Helpers

    /// The stripes template as a photo (red, green, blue thirds), for regenerating.
    private func stripesPhoto() throws -> CGImage {
        try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: 120))
    }

    /// Regions under the centres of the left, middle and right thirds.
    private func thirds(of t: Template) throws -> [Int] {
        try [1, 3, 5].map { (sixth: Int) throws -> Int in
            let point = SIMD2(Float(t.width) * Float(sixth) / 6, Float(t.height) / 2)
            return try #require(t.region(at: point))
        }
    }

    private func fileNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }
}
