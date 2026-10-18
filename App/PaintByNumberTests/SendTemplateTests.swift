import Foundation
import PaintCore
import Testing
import UniformTypeIdentifiers
@testable import PaintByNumber

/// Send Template… and its other end: a painting written as a `.moonlight` file (`SharedPaintingFile`,
/// `SharedPaintingCodec`) and a file someone sent added to the library (`Library.receive`).
@MainActor
struct SendTemplateTests {
    let root = Fixtures.temporaryDirectory()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root)) }

    /// A refined, half-painted painting with a photo: what is sent is its template, and only that.
    private func sender(_ library: Library) async throws -> Artwork {
        var progress = PaintProgress(regionCount: 3)
        progress.paint(1)
        var draft = ArtworkDraft(
            title: "Stripes for Ada", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12),
            photo: TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: 120), progress: progress)
        draft.refinements.edits = [.draw(points: [SIMD2(5, 20), SIMD2(55, 20)])]
        return try await library.create(draft)
    }

    @Test func sentFileIsTheTemplateAndItsTitle() async throws {
        let library = makeLibrary()
        let artwork = try await sender(library)
        let url = try await SharedPaintingFile(store: library.store, artwork: artwork).export()
        defer { ArtworkExporter.removeExport(at: url) }
        #expect(url.lastPathComponent == "Stripes for Ada Template.moonlight")
        #expect(UTType(filenameExtension: url.pathExtension) == .moonlightPainting)

        let data = try Data(contentsOf: url)
        #expect(SharedPaintingCodec.isSharedPainting(data))
        let shared = try SharedPaintingCodec.decode(data)
        #expect(shared.title == "Stripes for Ada")
        #expect(shared.settings == GenerationSettings(colorCount: 12))
        #expect(shared.template == Fixtures.stripes())
        // Compressed: smaller than the template it carries.
        #expect(data.count < shared.template.encoded().count)
    }

    @Test func receivedPaintingIsANewBlankPaintingWithoutAPhoto() async throws {
        let library = makeLibrary()
        let artwork = try await sender(library)
        let data = try ArtworkExporter.sharedPainting(store: library.store, artwork: artwork)

        let received = try await library.receive(data, fallbackTitle: "File Name")
        #expect(received.id != artwork.id)
        #expect(received.title == "Stripes for Ada")
        #expect(received.paintedCount == 0 && received.sampleName == nil)
        #expect(library.artworks.count == 2)
        #expect(!library.store.hasSource(received.id))
        #expect(!ArtworkFactory.canRegenerate(received, store: library.store))
        #expect(library.store.readRefinements(received.id).isEmpty)
        #expect(library.store.thumbnail(received.id) != nil)
        let document = try await library.loadForPainting(received.id)
        #expect(document.template == Fixtures.stripes())
        #expect(document.progress.paintedCount == 0 && document.notice == nil)
        // It stays after a relaunch.
        #expect(makeLibrary().artwork(with: received.id) == received)
    }

    @Test func untitledPaintingIsNamedAfterItsFile() async throws {
        let library = makeLibrary()
        let data = try SharedPaintingCodec.encode(SharedPainting(title: "  ", settings: nil, template: Fixtures.stripes()))
        #expect(try await library.receive(data, fallbackTitle: "From Mum").title == "From Mum")
        #expect(try await library.receive(data, fallbackTitle: nil).title == String(localized: "Painting"))
    }

    @Test func unreadableFilesAddNothing() async throws {
        let library = makeLibrary()
        let good = try SharedPaintingCodec.encode(SharedPainting(title: "A", settings: nil, template: Fixtures.stripes()))
        func failure(_ data: Data) async -> Library.ReceiveError? {
            do { _ = try await library.receive(data, fallbackTitle: nil); return nil } catch { return error as? Library.ReceiveError }
        }
        #expect(await failure(good.prefix(good.count - 1)) == .damaged)
        #expect(await failure(Data("PBMS".utf8)) == .damaged)
        var miscounted = good
        miscounted[8] = 3
        #expect(await failure(miscounted) == .damaged)
        // A newer format, and a template stream claiming more than the library would ever store.
        var newer = good
        newer[4] = 2
        #expect(await failure(newer) == .needsNewerApp)
        var w = Data("PBMS".utf8) + le(1) + le(2)
        let meta = Data(#"{"title":"A"}"#.utf8)
        w += Data("META".utf8) + le(1) + le(UInt32(meta.count)) + meta
        let body = le(1) + le(UInt32.max) + Data([1, 2, 3, 4])
        w += Data("TMPL".utf8) + le(1) + le(UInt32(body.count)) + body
        #expect(await failure(w) == .damaged)
        #expect(library.artworks.isEmpty)
    }

    private func le(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    /// A photo opened in the app is never taken for a painting.
    @Test func photosAreNotPaintings() throws {
        let photo = try #require(TemplateRasterizer.pngData(Fixtures.stripes(), style: .painting, maxPixelSize: 60))
        #expect(!SharedPaintingCodec.isSharedPainting(photo))
        #expect(!SharedPaintingCodec.isSharedPainting(Data()))
        #expect(!SharedPaintingCodec.isSharedPainting(Data("PBM".utf8)))
    }
}
