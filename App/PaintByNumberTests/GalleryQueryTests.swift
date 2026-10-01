import Foundation
import Testing
@testable import PaintByNumber

struct TitleSearchTests {
    private func finds(_ query: String, in title: String) -> Bool {
        TitleSearch.matches(title, query: query)
    }

    @Test func matchesWordPrefixes() {
        #expect(finds("ba", in: "Red Barn"))
        #expect(finds("red", in: "Red Barn"))
        #expect(finds("Red Barn", in: "Red Barn"))
        #expect(!finds("arn", in: "Red Barn"))
        #expect(!finds("barnyard", in: "Red Barn"))
        #expect(!finds("x", in: "Red Barn"))
    }

    @Test func everyWordOfTheQueryMustMatchSomeWord() {
        #expect(finds("red ba", in: "Red Barn"))
        #expect(finds("ba red", in: "Red Barn"))
        #expect(!finds("red lig", in: "Red Barn"))
    }

    @Test func ignoresCaseDiacriticsAndWidth() {
        #expect(finds("BA", in: "red barn"))
        #expect(finds("cafe", in: "Café Crème"))
        #expect(finds("CAFÉ", in: "cafe creme"))
        #expect(finds("creme", in: "Café Crème"))
        // A decomposed "é" (e + combining acute) in the title or the query.
        #expect(finds("cafe", in: "Cafe\u{301}"))
        #expect(finds("caf\u{e9}", in: "Cafe"))
        // Full-width letters.
        #expect(finds("ｂａ", in: "Barn"))
    }

    @Test func wordsEndAtPunctuation() {
        #expect(finds("sky", in: "Blue-sky (2)"))
        #expect(finds("2", in: "Blue-sky (2)"))
        #expect(finds("sky", in: "Sunset, sky and sea"))
        #expect(!finds("ky", in: "Blue-sky (2)"))
    }

    @Test func aBlankQueryMatchesEverything() {
        #expect(finds("", in: "Red Barn"))
        #expect(finds("   ", in: "Red Barn"))
        #expect(finds("…", in: "Red Barn"))
        #expect(finds("", in: ""))
        #expect(!finds("a", in: ""))
    }

    @Test func wordsAreFoldedAndSplit() {
        #expect(TitleSearch.words(in: "  Crème-Brûlée, 2nd ") == ["creme", "brulee", "2nd"])
        #expect(TitleSearch.words(in: " .,; ").isEmpty)
    }
}

struct GalleryQueryTests {
    private func artwork(_ title: String, favorite: Bool) throws -> Artwork {
        var artwork = try JSONDecoder().decode(
            Artwork.self, from: Data(#"{"id":"\#(UUID().uuidString)","title":"\#(title)","width":10,"height":10,"regionCount":3}"#.utf8))
        artwork.isFavorite = favorite
        return artwork
    }

    @Test func filterAndSearchCombine() throws {
        let barn = try artwork("Red Barn", favorite: true)
        let regatta = try artwork("Regatta", favorite: false)
        let parrots = try artwork("Parrots", favorite: true)

        let everything = GalleryQuery()
        #expect([barn, regatta, parrots].allSatisfy(everything.includes))
        #expect(!everything.isActive)

        let favorites = GalleryQuery(filter: .favorites)
        #expect(favorites.includes(barn) && favorites.includes(parrots) && !favorites.includes(regatta))
        #expect(favorites.isActive && !favorites.isSearching)

        let search = GalleryQuery(search: "re")
        #expect(search.includes(barn) && search.includes(regatta) && !search.includes(parrots))
        #expect(search.isActive && search.isSearching)

        let both = GalleryQuery(filter: .favorites, search: "re")
        #expect(both.includes(barn) && !both.includes(regatta) && !both.includes(parrots))
    }

    @Test func aBlankSearchIsNotActive() {
        #expect(!GalleryQuery(search: "  ").isActive)
        #expect(!GalleryQuery(search: "—").isSearching)
        #expect(GalleryQuery(filter: .favorites, search: " ").isActive)
    }

    @Test func filterRoundTripsThroughSceneStorage() {
        for filter in GalleryFilter.allCases {
            #expect(GalleryFilter(rawValue: filter.rawValue) == filter)
        }
    }
}
