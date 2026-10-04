import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PaintCore
import Testing
@testable import PaintByNumber

/// The picture library: `Resources/Samples/library.json`, the catalog's titles and the bundled
/// JPEGs agree, and the retired samples stay bundled for the paintings that name them.
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
    /// file name; no picture is listed twice and no retired sample is listed at all.
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
        #expect(Set(ids).isDisjoint(with: Sample.retired.map(\.id)), "A retired sample is listed")
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

    /// The six former samples stay bundled and resolve by name (saved paintings name them), but
    /// nothing records where they come from, so they are not offered.
    @Test func retiredSamplesStayBundledButAreNotOffered() {
        #expect(Sample.retired.map(\.id) == ["parrots", "hibiscus", "lighthouse", "barn", "espresso", "regatta"])
        for sample in Sample.retired {
            #expect(sample.url != nil, "\(sample.id).jpg isn't bundled")
            #expect(sample.provenance == nil)
            #expect(Sample.named(sample.id) == sample)
            #expect(!Sample.all.contains { $0.id == sample.id })
        }
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

/// Paintings made from a bundled picture keep regenerating whatever the library offers: when
/// no `source.jpg` was stored, `sampleName` still finds the photo, retired or not.
@MainActor
struct SampleRegenerationTests {
    let root = Fixtures.temporaryDirectory()

    @Test func paintingsWithoutAStoredPhotoRegenerateFromTheBundledPicture() async throws {
        // Regeneration finds a painting's photo by its `sampleName`; every bundled picture
        // resolves (SampleLibraryTests checks the files themselves).
        for sample in Sample.retired + Sample.all {
            #expect(Sample.named(sample.id)?.url != nil, "\(sample.id) doesn't resolve to a bundled file")
        }
        // Stored artworks for two retired samples and a library picture: storing one per picture
        // (44 and counting) would load the parallel test run enough to push its timing tests
        // over their budgets.
        let library = Library(store: ArtworkStore(root: root))
        let picture = try #require(Sample.all.first)
        let espressoSample = try #require(Sample.named("espresso"))
        var artworks: [Artwork] = []
        for sample in [Sample.retired[0], espressoSample, picture] {
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

        // End to end on the smallest retired photo.
        let espresso = try #require(artworks.first { $0.sampleName == "espresso" })
        let document = try await library.regenerate(artwork: espresso.id, settings: GenerationSettings(colorCount: 12, detail: 0))
        #expect(document.template.regions.count > Fixtures.stripes().regions.count)
        #expect(library.artwork(with: espresso.id)?.regionCount == document.template.regions.count)
    }
}
