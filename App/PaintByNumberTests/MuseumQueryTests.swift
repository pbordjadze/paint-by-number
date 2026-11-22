#if UNRELEASED
import Foundation
import SwiftUI
import Testing
@testable import PaintByNumber

/// The Museum's catalog decodes as `tools/museum/catalog.py` writes it, and the browser's query
/// filters and orders it (`MuseumQuery`).
struct MuseumQueryTests {
    private static let json = """
    {"version":1,"made":"2026-11-20","museums":{"aic":"The Art Institute of Chicago","cma":"The Cleveland Museum of Art"},
     "movements":["Impressionism","Art Nouveau","Ukiyo-e"],
     "works":[
      {"id":"aic-1","title":"Water Lilies","artist":"Claude Monet","year":"1906","date":1906,"movement":"Impressionism",
       "kind":"painting","colorfulness":48.5,"average":"6a8a7c","width":3000,"height":2900,"museum":"aic",
       "thumb":"https://example.org/1-t.jpg","image":"https://example.org/1.jpg","page":"https://example.org/1","medium":"Oil on canvas"},
      {"id":"cma-2","title":"Zodiac","artist":"Alphonse Mucha","year":"1896","date":1896,"movement":"Art Nouveau",
       "kind":"print","colorfulness":71.0,"average":"c09a6b","width":2000,"height":2700,"museum":"cma",
       "thumb":"https://example.org/2-t.jpg","image":"https://example.org/2.jpg","page":null,"medium":"Color lithograph"},
      {"id":"aic-3","title":"Fine Wind, Clear Morning","artist":"Katsushika Hokusai","year":"c. 1830–32","date":null,
       "movement":"Ukiyo-e","kind":"print","colorfulness":39.2,"average":"8a6a5c","width":0,"height":0,"museum":"aic",
       "thumb":"https://example.org/3-t.jpg","image":"https://example.org/3.jpg","page":"https://example.org/3","medium":""},
      {"id":"cma-4","title":"Café Terrace","artist":"Unknown","year":"1888","date":1888,"movement":"Impressionism",
       "kind":"painting","colorfulness":12.0,"average":"zz","width":1500,"height":1000,"museum":"cma",
       "thumb":"https://example.org/4-t.jpg","image":"https://example.org/4.jpg","medium":"Oil"}
     ]}
    """

    private let catalog: MuseumCatalog

    init() throws {
        catalog = try MuseumCatalog.decode(Data(Self.json.utf8))
    }

    private func ids(_ query: MuseumQuery) -> [String] {
        query.works(of: catalog).map(\.id)
    }

    @Test func decodesWhatTheToolWrites() throws {
        #expect(catalog.works.count == 4)
        #expect(catalog.movements == ["Impressionism", "Art Nouveau", "Ukiyo-e"])
        let hokusai = try #require(catalog.works.first { $0.id == "aic-3" })
        #expect(hokusai.date == nil)
        #expect(hokusai.aspectRatio == 1)
        #expect(catalog.works.first { $0.id == "cma-2" }?.page == nil)
        #expect(catalog.works.first { $0.id == "cma-4" }?.page == nil)
    }

    @Test func mostColorfulComesFirst() {
        #expect(ids(MuseumQuery()) == ["cma-2", "aic-1", "aic-3", "cma-4"])
    }

    @Test func oldestAndNewestLeaveUndatedWorksLast() {
        #expect(ids(MuseumQuery(order: .oldest)) == ["cma-4", "cma-2", "aic-1", "aic-3"])
        #expect(ids(MuseumQuery(order: .newest)) == ["aic-1", "cma-2", "cma-4", "aic-3"])
    }

    @Test func aMovementAndAKindNarrowTheWorks() {
        #expect(ids(MuseumQuery(movement: "Impressionism")) == ["aic-1", "cma-4"])
        #expect(ids(MuseumQuery(kinds: .printsAndDrawings)) == ["cma-2", "aic-3"])
        #expect(ids(MuseumQuery(movement: "Ukiyo-e", kinds: .paintings)).isEmpty)
        #expect(MuseumQuery(kinds: .paintings).counts(of: catalog) == ["Impressionism": 2])
    }

    @Test func searchFindsWordPrefixesOfTitleArtistMovementAndYear() {
        #expect(ids(MuseumQuery(search: "mon")) == ["aic-1"])
        #expect(ids(MuseumQuery(search: "cafe")) == ["cma-4"])
        #expect(ids(MuseumQuery(search: "art nouv")) == ["cma-2"])
        #expect(ids(MuseumQuery(search: "1830")) == ["aic-3"])
        #expect(ids(MuseumQuery(search: "hokusai wind")) == ["aic-3"])
        #expect(ids(MuseumQuery(search: "lilies mucha")).isEmpty)
    }

    @Test func aShuffleIsStableForItsSeedAndKeepsEveryWork() {
        let first = ids(MuseumQuery(order: .shuffled, seed: 7))
        #expect(first == ids(MuseumQuery(order: .shuffled, seed: 7)))
        #expect(Set(first) == Set(catalog.works.map(\.id)))
    }

    @Test func aWorkOfAKindThisBuildDoesntKnowIsLeftOutAlone() throws {
        let json = Self.json
            .replacingOccurrences(of: #""id":"aic-3","title""#, with: #""id":"aic-3","kind":"sculpture","title""#)
            .replacingOccurrences(of: #""movement":"Ukiyo-e","kind":"print""#, with: #""movement":"Ukiyo-e""#)
        let lenient = try MuseumCatalog.decode(Data(json.utf8))
        #expect(lenient.works.map(\.id) == ["aic-1", "cma-2", "cma-4"])
    }

    @Test func aPaintingIsNamedWithoutTheSeries() {
        func named(_ title: String) -> String {
            let json = Self.json.replacingOccurrences(of: "Water Lilies", with: title)
            let catalog = try? MuseumCatalog.decode(Data(json.utf8))
            return catalog?.works.first { $0.id == "aic-1" }?.paintingTitle ?? ""
        }
        #expect(named("Water Lilies") == "Water Lilies")
        #expect(named("Evening Snow, from the series Eight Views of Ōmi") == "Evening Snow")
        let long = named(String(repeating: "Garden of the Evening ", count: 6))
        #expect(long.count <= 61 && long.hasSuffix("…"))
    }

    @Test func aPaintingNamedAfterAWorkMatchesIt() throws {
        let lilies = try #require(catalog.works.first { $0.id == "aic-1" })
        #expect(MuseumPainted.key("Café Terrace ") == MuseumPainted.key("cafe terrace"))
        #expect(MuseumPainted.matches(lilies, names: [MuseumPainted.key("water lilies")], recorded: [],
                                      shared: catalog.sharedNames))
        #expect(!MuseumPainted.matches(lilies, names: [], recorded: ["aic-1"], shared: catalog.sharedNames))
    }

    @Test func aNameTwoWorksShareMatchesOnlyTheOnePainted() throws {
        let json = Self.json.replacingOccurrences(of: "Café Terrace", with: "Water Lilies")
        let shared = try MuseumCatalog.decode(Data(json.utf8))
        let name = MuseumPainted.key("Water Lilies")
        #expect(shared.sharedNames == [name])
        let first = try #require(shared.works.first { $0.id == "aic-1" })
        let second = try #require(shared.works.first { $0.id == "cma-4" })
        #expect(!MuseumPainted.matches(first, names: [name], recorded: [], shared: shared.sharedNames))
        #expect(MuseumPainted.matches(second, names: [name], recorded: ["cma-4"], shared: shared.sharedNames))
        #expect(!MuseumPainted.matches(first, names: [name], recorded: ["cma-4"], shared: shared.sharedNames))
    }

    @Test func paintThisRecordsEachWorkOnce() throws {
        let suite = "MuseumPaintedTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        MuseumPainted.record("aic-1", in: defaults)
        MuseumPainted.record("aic-1", in: defaults)
        MuseumPainted.record("cma-2", in: defaults)
        #expect(MuseumPainted.recorded(in: defaults) == ["aic-1", "cma-2"])
        #expect(defaults.stringArray(forKey: MuseumPainted.defaultsKey) == ["aic-1", "cma-2"])
    }

    @MainActor @Test func aBadAverageColorStillMakesAColor() {
        _ = Color(museumHex: "zz")
        _ = Color(museumHex: "6a8a7c")
    }
}
#endif
