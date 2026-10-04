import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PaintCore
import Testing
@testable import PaintByNumber

/// The picture library: `Resources/Samples/library.json`, the catalog's titles and the bundled
/// JPEGs agree, and the app ships no picture the library doesn't list.
struct SampleLibraryTests {
    /// The bundled `library.json`, read without `Sample`'s decoder.
    private static func records() throws -> [[String: Any]] {
        let url = try #require(Bundle.main.url(forResource: "library", withExtension: "json"), "library.json isn't bundled")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
    }

    /// Every record is offered, in the file's order, with its title (the catalog's English is
    /// the record's title) and its facts; nothing else is offered.
    @Test func theLibraryOffersEveryRecordWithItsTitle() throws {
        let records = try Self.records()
        #expect(!records.isEmpty)
        #expect(Sample.all.map(\.id) == records.map { $0["id"] as? String ?? "" },
                "The file must decode: every record needs its id, title and facts")
        for (sample, record) in zip(Sample.all, records) {
            let missing = "\u{0}missing"
            #expect(Bundle.main.localizedString(forKey: "sample.\(sample.id)", value: missing, table: nil) == record["title"] as? String,
                    "\(sample.id): the catalog has no sample.\(sample.id), or its English differs from the record's title")
            #expect(sample.title == record["title"] as? String, "\(sample.id): the catalog's title differs from the record's")
            let provenance = try #require(sample.provenance)
            #expect(provenance.kind.rawValue == record["kind"] as? String)
            #expect(provenance.creator == record["creator"] as? String)
            #expect(provenance.year == record["year"] as? String)
            #expect(provenance.credit == record["credit"] as? String)
            #expect(provenance.license == record["license"] as? String)
        }
    }

    /// A record carries everything the license audit relies on, under an id that is a flat
    /// file name; no picture is listed twice.
    @Test func recordsAreComplete() throws {
        let fields = ["id", "kind", "title", "creator", "year", "credit", "license", "source", "image", "evidence",
                      "retrieved", "crop", "sha256"]
        let records = try Self.records()
        for record in records {
            let id = record["id"] as? String ?? "?"
            for field in fields {
                let value = (record[field] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                #expect(!value.isEmpty, "\(id) has no \(field)")
            }
            #expect(id.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil, "\(id) isn't a flat file name")
            #expect(Sample.Kind(rawValue: record["kind"] as? String ?? "") != nil, "\(id): kind is painting or photograph")
            #expect((record["source"] as? String)?.hasPrefix("https://") == true, "\(id): the source is an https URL")
            let retrieved = record["retrieved"] as? String ?? ""
            #expect(retrieved.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, "\(id): retrieved \(retrieved)")
        }
        let ids = records.compactMap { $0["id"] as? String }
        #expect(Set(ids).count == ids.count, "A picture is listed twice")
    }

    /// Each listed picture ships as the file its record describes: the checksum matches, and
    /// the long edge is at most what the app stores of a photo (`ArtworkStore.sourceMaxPixelSize`)
    /// and at least half of it (a thumbnail slipping in would make a coarse template). The size
    /// comes from the JPEG's header: decoding every picture in full would load the parallel test
    /// run enough to push the timing tests over their budgets.
    @Test func everyRecordShipsItsFile() throws {
        for record in try Self.records() {
            let id = try #require(record["id"] as? String)
            let url = try #require(Bundle.main.url(forResource: id, withExtension: "jpg"), "\(id).jpg isn't bundled")
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == record["sha256"] as? String, "\(id).jpg differs from its record's checksum")
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil), "\(id).jpg isn't an image")
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                                          "\(id).jpg has no image properties")
            let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
            let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
            #expect((ArtworkStore.sourceMaxPixelSize / 2...ArtworkStore.sourceMaxPixelSize).contains(max(width, height)),
                    "\(id).jpg is \(width)×\(height)")
        }
    }

    /// Every picture the app bundles is a listed one, so every one is credited (`AboutTests`):
    /// a photo whose provenance nobody recorded doesn't ship.
    @Test func everyBundledPictureIsListed() throws {
        let listed = try Set(Self.records().compactMap { $0["id"] as? String })
        let bundled = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? []
        #expect(!bundled.isEmpty)
        for url in bundled {
            let id = url.deletingPathExtension().lastPathComponent
            #expect(listed.contains(id), "\(id).jpg ships, but library.json doesn't list it")
        }
    }

    /// First launch prepares a painting and a photograph from the library.
    @Test func startersAreAPaintingAndAPhotograph() {
        #expect(Sample.starters.count == 2)
        #expect(Set(Sample.starters.compactMap(\.provenance?.kind)) == [.painting, .photograph])
        #expect(Sample.starters.allSatisfy { Sample.all.contains($0) })
    }

    /// The Samples pane's sections split the library by kind, each in the library's order.
    @Test func sectionsSplitTheLibraryByKind() {
        let paintings = Sample.all(of: .painting)
        let photographs = Sample.all(of: .photograph)
        #expect(!paintings.isEmpty && !photographs.isEmpty)
        #expect(paintings.count + photographs.count == Sample.all.count)
        #expect(paintings.allSatisfy { $0.provenance?.kind == .painting })
        #expect(photographs.allSatisfy { $0.provenance?.kind == .photograph })
        #expect(paintings == Sample.all.filter { paintings.contains($0) })
    }

    /// Saved paintings name their picture by id (`Artwork.sampleName`): every library picture
    /// resolves by its own, and nothing else does.
    @Test func picturesResolveByTheirIds() {
        for sample in Sample.all {
            #expect(Sample.named(sample.id) == sample)
        }
        #expect(Sample.named("missing") == nil)
    }

    /// A title is the catalog's `sample.<id>`, or the record's own where the catalog has none. A
    /// file that doesn't decode (a record without its title or a fact) offers nothing. Fields
    /// the app doesn't read (the audit's) are ignored.
    @Test func titlesComeFromTheCatalogAndUnreadableFilesOfferNothing() {
        let json = """
            [{"id": "great-wave", "kind": "painting", "title": "Under the Wave off Kanagawa", "creator": "Katsushika Hokusai",
              "year": "c. 1830–32", "credit": "A museum", "license": "CC0", "source": "https://example.org/45434"},
             {"id": "uncatalogued", "kind": "photograph", "title": "Uncatalogued", "creator": "Somebody", "year": "1900",
              "credit": "An archive", "license": "Public domain"}]
            """
        let listed = Sample.listed(in: Data(json.utf8))
        #expect(listed.map(\.id) == ["great-wave", "uncatalogued"])
        #expect(listed.map(\.title) == ["The Great Wave", "Uncatalogued"])
        #expect(listed.first?.provenance?.creator == "Katsushika Hokusai")
        #expect(listed.first?.provenance?.year == "c. 1830–32")
        #expect(Sample.listed(in: Data(#"[{"id": "great-wave", "kind": "painting", "creator": "x", "year": "x", "credit": "x", "license": "x"}]"#.utf8)).isEmpty)
        #expect(Sample.listed(in: Data(#"[{"id": "great-wave", "kind": "painting"}]"#.utf8)).isEmpty)
        #expect(Sample.listed(in: Data(#"[{"id": "great-wave", "kind": "sculpture", "title": "x", "creator": "x", "year": "x", "credit": "x", "license": "x"}]"#.utf8)).isEmpty)
        #expect(Sample.listed(in: Data("{".utf8)).isEmpty)
    }
}

/// Paintings made from a library picture regenerate from it when no `source.jpg` was stored;
/// one whose picture the app no longer has can't be regenerated, and says so up front.
@MainActor
struct SampleRegenerationTests {
    let root = Fixtures.temporaryDirectory()

    @Test func paintingsWithoutAStoredPhotoRegenerateFromTheLibraryPicture() async throws {
        // Regeneration finds a painting's photo by its `sampleName`; every library picture
        // resolves (SampleLibraryTests checks the files themselves).
        for sample in Sample.all {
            #expect(Sample.named(sample.id)?.url != nil, "\(sample.id) doesn't resolve to a bundled file")
        }
        // Stored artworks for two of them: storing one per picture (44 and counting) would load
        // the parallel test run enough to push its timing tests over their budgets.
        let library = Library(store: ArtworkStore(root: root))
        var artworks: [Artwork] = []
        for id in ["great-wave", "morning-glories"] {
            let sample = try #require(Sample.named(id))
            artworks.append(try await library.create(ArtworkDraft(
                title: sample.title, template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12),
                photo: nil, sampleName: sample.id, progress: nil)))
        }
        for artwork in artworks {
            #expect(!library.store.hasSource(artwork.id))
            #expect(ArtworkFactory.canRegenerate(artwork, store: library.store), "\(artwork.title) can't regenerate")
            let photo = try ArtworkFactory.sourcePhoto(of: artwork, in: library.store)
            #expect(photo.width > 0 && photo.height > 0)
        }

        // End to end on one of them.
        let glories = try #require(artworks.last)
        let document = try await library.regenerate(artwork: glories.id, settings: GenerationSettings(colorCount: 12, detail: 0))
        #expect(document.template.regions.count > Fixtures.stripes().regions.count)
        #expect(library.artwork(with: glories.id)?.regionCount == document.template.regions.count)
    }

    /// "parrots" is one of the six photos the app shipped before its library, which saved
    /// paintings may name. Without a stored photo such a painting has nothing to regenerate
    /// from: damaged, it opens on the recovery screen without the offer, and regenerating
    /// anyway fails without touching it.
    @Test func paintingsOfAPictureTheAppNoLongerHasCantRegenerate() async throws {
        let library = Library(store: ArtworkStore(root: root))
        let artwork = try await library.create(ArtworkDraft(
            title: "Parrots", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12),
            photo: nil, sampleName: "parrots", progress: nil))
        #expect(Sample.named("parrots") == nil)
        #expect(!ArtworkFactory.canRegenerate(artwork, store: library.store))
        #expect(throws: ArtworkFactory.FactoryError.sourceUnavailable) {
            try ArtworkFactory.sourcePhoto(of: artwork, in: library.store)
        }

        let url = library.store.url(.template, of: artwork.id)
        try Data("damaged".utf8).write(to: url)
        await #expect(throws: Library.OpenError.damaged(canRegenerate: false)) {
            try await library.loadForPainting(artwork.id)
        }
        await #expect(throws: ArtworkFactory.FactoryError.sourceUnavailable) {
            try await library.regenerate(artwork: artwork.id, settings: artwork.settings)
        }
        #expect(try Data(contentsOf: url) == Data("damaged".utf8))
        #expect(library.regenerating.isEmpty)
    }
}
