import Foundation
import Testing
@testable import PaintByNumber

/// The Original (painting-company row 120): the real work behind a library picture, read from
/// `library.json` and from nowhere else, the paintings that have one, and what its page's
/// placard ends on.
struct AboutPaintingTests {
    private static let picture = Sample(
        id: "picture", title: "Picture",
        provenance: Sample.Provenance(kind: .painting, creator: "A Painter", year: "1900", credit: "A Museum, A Fund", license: "CC0"))

    private static func works(_ record: String) -> [String: OriginalWork] {
        OriginalWork.listed(in: Data("[\(record)]".utf8), samples: [picture])
    }

    /// Every picture the library offers has its work, with a page to open; the paintings say
    /// where they are kept.
    @Test func everyLibraryPictureHasItsWork() throws {
        #expect(!Sample.all.isEmpty)
        for sample in Sample.all {
            let work = try #require(OriginalWork.of(sample.id), "\(sample.id) has no work")
            #expect(work.sample == sample)
            #expect(work.provenance == sample.provenance)
            #expect(work.source.scheme == "https")
            if sample.provenance?.kind == .painting {
                #expect(work.place != nil, "\(sample.id): a painting says where it is kept")
            }
            if let wikipedia = work.wikipedia {
                #expect(wikipedia.scheme == "https" && wikipedia.host() == "en.wikipedia.org", "\(sample.id): \(wikipedia)")
                #expect(wikipedia.path().hasPrefix("/wiki/"), "\(sample.id): \(wikipedia)")
            }
        }
        #expect(OriginalWork.all.count == Sample.all.count)
    }

    /// The record's links are read whole: none is dropped or changed for its form.
    @Test func theLibrarysLinksAreAllRead() throws {
        let url = try #require(Bundle.main.url(forResource: "library", withExtension: "json"))
        let records = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for record in records {
            let id = try #require(record["id"] as? String)
            #expect(OriginalWork.of(id)?.wikipedia?.absoluteString == record["wikipedia"] as? String, "\(id)")
            #expect(OriginalWork.of(id)?.source.absoluteString == record["source"] as? String, "\(id)")
        }
    }

    /// A painter's own photo, and a picture the library doesn't offer, have none.
    @Test func aPaintersOwnPhotoHasNone() {
        #expect(OriginalWork.of(nil) == nil)
        #expect(OriginalWork.of("not-in-the-library") == nil)
    }

    @Test func aRecordsFactsAreItsOwn() throws {
        let work = try #require(Self.works("""
            {"id": "picture", "source": "https://museum.example/1", "medium": "oil on fabric",
             "place": "A Museum, A City", "work_title": "The Picture, Whole",
             "wikipedia": "https://en.wikipedia.org/wiki/Picture"}
            """)["picture"])
        #expect(work.source.absoluteString == "https://museum.example/1")
        #expect(work.medium == "Oil on fabric", "A medium starts with a capital")
        #expect(work.place == "A Museum, A City")
        #expect(work.wikipedia?.absoluteString == "https://en.wikipedia.org/wiki/Picture")
    }

    /// What a record lacks is left out, never filled in.
    @Test func aFactTheRecordLacksIsLeftOut() throws {
        let work = try #require(Self.works(#"{"id": "picture", "source": "https://museum.example/1", "medium": " "}"#)["picture"])
        #expect(work.medium == nil && work.place == nil && work.wikipedia == nil)
    }

    /// The placard's last line is where the work hangs; a record without a place has none, and
    /// its credit line stays the faint line under the label.
    @Test func thePlacardEndsOnWhereItHangs() throws {
        let hung = try #require(Self.works(#"{"id": "picture", "source": "https://museum.example/1", "place": "A Museum, A City"}"#)["picture"])
        #expect(hung.place == "A Museum, A City")
        let bare = try #require(Self.works(#"{"id": "picture", "source": "https://museum.example/1"}"#)["picture"])
        #expect(bare.place == nil && !bare.provenance.credit.isEmpty)
    }

    /// The picture has most of the sheet, and still some of a very short one.
    @Test func thePictureIsThePagesHero() {
        #expect(AboutPainting.pictureHeight(page: 1200) > 600)
        // A phone's sheet: the label and the links stay in view under it.
        #expect(AboutPainting.pictureHeight(page: 700) == 700 - AboutPainting.labelAndLinks)
        #expect(AboutPainting.pictureHeight(page: 200) == 180)
    }

    /// Only https pages open, and only the English Wikipedia's as its article.
    @Test func onlyHTTPSPagesOpen() throws {
        #expect(Self.works(#"{"id": "picture", "source": "http://museum.example/1"}"#).isEmpty)
        #expect(Self.works(#"{"id": "picture", "source": "not a link"}"#).isEmpty)
        #expect(Self.works(#"{"id": "picture"}"#).isEmpty)
        #expect(Self.works(#"{"id": "another", "source": "https://museum.example/1"}"#).isEmpty, "A record of no picture offered")
        for link in ["https://wikipedia.example/wiki/Picture", "http://en.wikipedia.org/wiki/Picture", "javascript:alert(1)"] {
            let record = #"{"id": "picture", "source": "https://museum.example/1", "wikipedia": ""# + link + #""}"#
            let work = try #require(Self.works(record)["picture"])
            #expect(work.wikipedia == nil, "\(link)")
        }
        #expect(OriginalWork.listed(in: Data("{".utf8), samples: [Self.picture]).isEmpty)
    }
}
