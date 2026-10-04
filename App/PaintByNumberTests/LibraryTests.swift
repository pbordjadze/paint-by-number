import AVFoundation
import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct LibraryTests {
    let root = Fixtures.temporaryDirectory()
    let faults = WriteFaults()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root, writeFaults: faults)) }

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

    /// Progress that exists but can't be read this time is not "missing": opening fails and
    /// nothing is written over it, so the painted areas survive to the next attempt.
    @Test func unreadableProgressIsKept() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0, 2]))
        let url = library.store.url(.progress, of: artwork.id)
        let saved = try Data(contentsOf: url)
        // A directory in the file's place reads with an error other than "no such file".
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        await #expect(throws: Library.OpenError.unreadable) { try await library.loadForPainting(artwork.id) }
        await library.flush()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(library.artwork(with: artwork.id)?.paintedCount == 2)

        try FileManager.default.removeItem(at: url)
        try saved.write(to: url)
        let document = try await library.loadForPainting(artwork.id)
        #expect(document.notice == nil)
        #expect(document.progress.paintedCount == 2)
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

    /// Artworks from builds before format 2 open and paint as before; regenerating writes a
    /// current-format template, and the metadata says so.
    @Test func olderMetaFormatStaysOpenable() async throws {
        let artwork = try await makeLibrary().create(draft(painted: [0], photo: try stripesPhoto()))
        #expect(artwork.format == Artwork.currentFormat)
        var older = artwork
        older.format = 1
        let store = ArtworkStore(root: root)
        try store.writeMeta(older)

        let library = makeLibrary()
        #expect(library.artwork(with: artwork.id)?.needsNewerApp == false)
        let document = try await library.loadForPainting(artwork.id)
        var progress = document.progress
        progress.paint(1)
        library.saveProgress(progress, for: artwork.id)
        await library.flush()
        #expect(try store.readMeta(artwork.id).format == 1)
        #expect(try store.readMeta(artwork.id).paintedCount == 2)

        _ = try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        await library.flush()
        #expect(library.artwork(with: artwork.id)?.format == Artwork.currentFormat)
        #expect(try store.readMeta(artwork.id).format == Artwork.currentFormat)
    }

    @Test func progressMismatchIsGraceful() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft(painted: [0]))
        var other = PaintProgress(regionCount: 5)
        other.paint(4)
        try library.store.writeProgress(other, for: artwork.id)
        // More regions than the template is refused before decoding the flags; fewer after.
        #expect(try library.store.readProgress(artwork.id, regionCount: 3).problem == .mismatched)
        #expect(try library.store.readProgress(artwork.id, regionCount: 6).problem == .mismatched)
        #expect(try library.store.readProgress(artwork.id, regionCount: 5).progress == other)

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

    /// Restarting sizes the fresh progress from the template, so stale metadata cannot make
    /// the next open discard it with a notice.
    @Test func restartWithStaleMetaFitsTheTemplate() async throws {
        let artwork = try await makeLibrary().create(draft(painted: [0, 2]))
        var stale = artwork
        stale.regionCount = 7
        let store = ArtworkStore(root: root)
        try store.writeMeta(stale)

        let library = makeLibrary()
        await library.restart(artwork.id)
        let restarted = try #require(library.artwork(with: artwork.id))
        #expect(restarted.regionCount == 3 && restarted.paintedCount == 0)
        await library.flush()
        #expect(try store.readMeta(artwork.id).regionCount == 3)
        let saved = try store.readProgress(artwork.id, regionCount: 3)
        #expect(saved.problem == nil)
        #expect(saved.progress == PaintProgress(regionCount: 3))
        let document = try await library.loadForPainting(artwork.id)
        #expect(document.notice == nil)
        #expect(document.progress.paintedCount == 0)
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

        faults.fail(.progress)
        library.saveProgress(progress(painting: [0]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)
        #expect(library.latestWriteFailure?.artwork.id == artwork.id)

        faults.heal(.progress)
        library.retrySaving(artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(library.latestWriteFailure == nil)
        #expect(try await savedProgress(artwork.id).isPainted(0))

        // A later save that succeeds clears the error too, and its progress is what's kept.
        faults.fail(.progress)
        library.saveProgress(progress(painting: [0, 1]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)
        faults.heal(.progress)
        library.saveProgress(progress(painting: [0, 2]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        let saved = try await savedProgress(artwork.id)
        #expect(saved.isPainted(2) && !saved.isPainted(1))
    }

    @Test func retryNeverWritesAnOlderSnapshot() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        faults.fail(.progress)
        library.saveProgress(progress(painting: [1]), for: artwork.id)
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)

        faults.heal(.progress)
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
        faults.fail(.meta)
        library.rename(artwork.id, to: "Sunset")
        await library.flush()
        #expect(library.writeFailures[artwork.id] != nil)

        faults.heal(.meta)
        library.retrySaving(artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(makeLibrary().artwork(with: artwork.id)?.title == "Sunset")
    }

    @Test func thumbnailWriteFailuresOnlyLog() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        faults.fail(.thumbnail)
        await library.refreshThumbnail(artwork.id, progress: progress(painting: [0]))
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion)
    }

    @Test func failedWriteOfADeletedArtworkIsHiddenThenDropped() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        faults.fail(.progress)
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
        // Saved before line art existed: classic lines, whatever the default style is now.
        #expect(artwork.settings == Artwork.settingsBeforeLineArt && artwork.settings.lineArt.style == .classic)
        let invalid = #"{"id":"\#(id)","width":0,"height":20,"regionCount":5}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Artwork.self, from: Data(invalid.utf8)) }
        #expect(!artwork.needsNewerApp)
        #expect(artwork.pipelineVersion == 0)
        #expect(!artwork.isFavorite)

        // A newer app's metadata always yields a (read-only) gallery entry.
        let newer = #"{"id":"\#(id)","format":3}"#
        let future = try JSONDecoder().decode(Artwork.self, from: Data(newer.utf8))
        #expect(future.needsNewerApp)
        #expect(future.width == 1 && future.height == 1 && future.regionCount == 0)
    }

    /// `meta.json` written before favorites existed has no `isFavorite` key.
    @Test func metaWithoutFavoriteFieldIsNotFavorite() async throws {
        var artwork = try await makeLibrary().create(draft())
        artwork.isFavorite = true
        let encoded = try JSONEncoder().encode(artwork)
        #expect(try JSONDecoder().decode(Artwork.self, from: encoded).isFavorite)

        var fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields.removeValue(forKey: "isFavorite") != nil)
        let old = try JSONDecoder().decode(Artwork.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(!old.isFavorite)
        #expect(old.format == Artwork.currentFormat)
    }

    /// Where the settings came from and the painting length are recorded in `meta.json`; files
    /// from before Suggested settings have neither, and a value this app doesn't know is kept.
    @Test func settingsOriginAndPaintingLengthRoundTripThroughMeta() async throws {
        let library = makeLibrary()
        var item = draft()
        item.settingsOrigin = .custom
        item.paintingLength = .quick
        let artwork = try await library.create(item)
        #expect(artwork.settingsOrigin == "custom")
        #expect(artwork.paintingLength == "quick")
        await library.flush()
        let reloaded = try #require(makeLibrary().artwork(with: artwork.id))
        #expect(reloaded.settingsOrigin == "custom" && reloaded.paintingLength == "quick")
        #expect(reloaded.format == Artwork.currentFormat)

        let encoded = try JSONEncoder().encode(artwork)
        var fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields.removeValue(forKey: "settingsOrigin") != nil)
        #expect(fields.removeValue(forKey: "paintingLength") != nil)
        let old = try JSONDecoder().decode(Artwork.self, from: JSONSerialization.data(withJSONObject: fields))
        #expect(old.settingsOrigin == nil && old.paintingLength == nil)
        #expect(old.settings == artwork.settings && old.format == Artwork.currentFormat)

        fields["settingsOrigin"] = "tuned"
        fields["paintingLength"] = "marathon"
        let newer = try JSONDecoder().decode(Artwork.self, from: JSONSerialization.data(withJSONObject: fields))
        let rewritten = try JSONDecoder().decode(Artwork.self, from: JSONEncoder().encode(newer))
        #expect(rewritten.settingsOrigin == "tuned" && rewritten.paintingLength == "marathon")

        // Paintings made outside the create flow (first-launch samples) record neither.
        let plain = try await library.create(draft(title: "Plain"))
        #expect(plain.settingsOrigin == nil && plain.paintingLength == nil)
    }

    @Test func favoritesPersistAcrossAReload() async throws {
        let library = makeLibrary()
        let a = try await library.create(draft(title: "A"))
        let b = try await library.create(draft(title: "B"))
        #expect(!a.isFavorite && !b.isFavorite)

        library.setFavorite(a.id, true)
        #expect(library.artwork(with: a.id)?.isFavorite == true)
        await library.flush()
        #expect(makeLibrary().artwork(with: a.id)?.isFavorite == true)
        #expect(makeLibrary().artwork(with: b.id)?.isFavorite == false)

        // Painting rewrites the metadata; the mark stays.
        library.saveProgress(progress(painting: [0]), for: a.id)
        await library.flush()
        #expect(makeLibrary().artwork(with: a.id)?.isFavorite == true)
        #expect(makeLibrary().artwork(with: a.id)?.paintedCount == 1)

        library.setFavorite(a.id, false)
        await library.flush()
        #expect(makeLibrary().artwork(with: a.id)?.isFavorite == false)

        // A deletion that is undone brings the mark back with the painting.
        library.setFavorite(b.id, true)
        library.delete(b.id)
        library.undoDelete()
        await library.flush()
        #expect(makeLibrary().artwork(with: b.id)?.isFavorite == true)
    }

    @Test func favoritesComeFirstWithinEachSection() async throws {
        let library = makeLibrary()
        func add(_ title: String, minutesAgo: Double, painted: [Int] = []) async throws -> Artwork {
            var item = draft(title: title, painted: painted)
            item.date = Date(timeIntervalSinceNow: -60 * minutesAgo)
            return try await library.create(item)
        }
        let newest = try await add("Newest", minutesAgo: 1)
        let middle = try await add("Middle", minutesAgo: 2)
        let oldest = try await add("Oldest", minutesAgo: 3)
        let recentlyDone = try await add("Done Recently", minutesAgo: 4, painted: [0, 1, 2])
        let longAgoDone = try await add("Done Long Ago", minutesAgo: 5, painted: [0, 1, 2])
        #expect(library.inProgress.map(\.id) == [newest.id, middle.id, oldest.id])
        #expect(library.finished.map(\.id) == [recentlyDone.id, longAgoDone.id])

        library.setFavorite(oldest.id, true)
        library.setFavorite(longAgoDone.id, true)
        #expect(library.inProgress.map(\.id) == [oldest.id, newest.id, middle.id])
        #expect(library.finished.map(\.id) == [longAgoDone.id, recentlyDone.id])

        // Two favorites keep the section's own order between them.
        library.setFavorite(middle.id, true)
        #expect(library.inProgress.map(\.id) == [middle.id, oldest.id, newest.id])

        library.setFavorite(oldest.id, false)
        library.setFavorite(middle.id, false)
        #expect(library.inProgress.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func galleryListsRespectTheQuery() async throws {
        let library = makeLibrary()
        let barn = try await library.create(draft(title: "Red Barn"))
        let regatta = try await library.create(draft(title: "Regatta", painted: [0, 1, 2]))
        let parrots = try await library.create(draft(title: "Parrots"))
        library.setFavorite(regatta.id, true)
        library.setFavorite(parrots.id, true)

        #expect(Set(library.inProgress(matching: GalleryQuery()).map(\.id)) == [barn.id, parrots.id])
        let favorites = GalleryQuery(filter: .favorites)
        #expect(library.inProgress(matching: favorites).map(\.id) == [parrots.id])
        #expect(library.finished(matching: favorites).map(\.id) == [regatta.id])
        let search = GalleryQuery(filter: .all, search: "re")
        #expect(library.inProgress(matching: search).map(\.id) == [barn.id])
        #expect(library.finished(matching: search).map(\.id) == [regatta.id])
        // The search narrows the filter's list.
        let both = GalleryQuery(filter: .favorites, search: "re")
        #expect(library.inProgress(matching: both).isEmpty)
        #expect(library.finished(matching: both).map(\.id) == [regatta.id])
    }

    @Test func favoriteWriteFailuresAreRetried() async throws {
        let library = makeLibrary()
        let artwork = try await library.create(draft())
        faults.fail(.meta)
        library.setFavorite(artwork.id, true)
        await library.flush()
        #expect(library.artwork(with: artwork.id)?.isFavorite == true)
        #expect(library.writeFailures[artwork.id] != nil)

        faults.heal(.meta)
        library.retrySaving(artwork.id)
        await library.flush()
        #expect(library.writeFailures.isEmpty)
        #expect(makeLibrary().artwork(with: artwork.id)?.isFavorite == true)
    }

    @Test func newerArtworksCannotBeFavorited() async throws {
        let artwork = try await makeLibrary().create(draft())
        let metaURL = ArtworkStore(root: root).url(.meta, of: artwork.id)
        let meta = Data(#"{"id":"\#(artwork.id.uuidString)","format":99,"title":"Future","regionCount":3}"#.utf8)
        try meta.write(to: metaURL)

        let library = makeLibrary()
        library.setFavorite(artwork.id, true)
        await library.flush()
        #expect(library.artwork(with: artwork.id)?.isFavorite == false)
        #expect(try Data(contentsOf: metaURL) == meta)
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
