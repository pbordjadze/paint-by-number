import Foundation
import os

/// A picture bundled with the app (`Resources/Samples/<id>.jpg`).
///
/// `Resources/Samples/library.json` is the library: the pictures the Samples pane offers, in
/// their curated order, and where each one comes from (a record per picture, with its license
/// evidence). Creator, year, credit and license are proper names and facts, read from there
/// and shown verbatim in every language. Titles are translated, so they live here instead
/// (`title(of:)`, keyed `sample.<id>` in the string catalog). `SampleLibraryTests` keeps the
/// file, the titles and the bundled JPEGs in step.
nonisolated struct Sample: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Decodable, Sendable {
        case painting, photograph
    }

    /// Who made a picture and the terms it ships under, as its `library.json` record has them.
    struct Provenance: Hashable, Decodable, Sendable {
        let kind: Kind
        let creator: String
        /// As the source dates the work: "1968", "c. 1830–32".
        let year: String
        /// The collection or agency the file comes from.
        let credit: String
        let license: String
    }

    let id: String
    let title: String
    /// Nil only for the retired samples, whose provenance was never recorded.
    let provenance: Provenance?

    init(id: String, title: String, provenance: Provenance? = nil) {
        self.id = id
        self.title = title
        self.provenance = provenance
    }

    var url: URL? { Bundle.main.url(forResource: id, withExtension: "jpg") }

    /// The pictures the Samples pane offers, in the order of `library.json` (which is
    /// authoritative: curating the library reorders the file, not this code).
    static let all: [Sample] = {
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            Log.library.fault("library.json is missing from the bundle")
            return []
        }
        return Sample.listed(in: data)
    }()

    /// The pictures of one kind, in the library's order: a section of the Samples pane.
    static func all(of kind: Kind) -> [Sample] { all.filter { $0.provenance?.kind == kind } }

    /// Prepared on first launch so the gallery starts with something to paint: a painting and
    /// a photograph, the library's best first impression.
    static let starters: [Sample] = ["great-wave", "delicate-arch"].compactMap { id in Sample.all.first { $0.id == id } }

    /// Any bundled picture, offered or retired: saved paintings name theirs (`Artwork.sampleName`).
    static func named(_ id: String) -> Sample? {
        all.first { $0.id == id } ?? retired.first { $0.id == id }
    }

    /// The pictures a `library.json` lists, in its order, each with its title. A record without
    /// a title, or a file that doesn't decode, lists nothing (and `SampleLibraryTests` fails).
    static func listed(in data: Data) -> [Sample] {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            Log.library.fault("library.json doesn't decode: \(String(describing: error), privacy: .public)")
            return []
        }
        return records.compactMap { record in
            guard let title = title(of: record.id) else {
                Log.library.fault("library.json lists \(record.id, privacy: .public), which has no title")
                return nil
            }
            return Sample(id: record.id, title: title, provenance: record.provenance)
        }
    }

    /// A picture's record in `library.json`. Its other fields (source, license evidence,
    /// checksum, …) are for the people who audit the library.
    private struct Record: Decodable {
        let id: String
        let provenance: Provenance

        private enum CodingKeys: String, CodingKey { case id }

        init(from decoder: any Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
            provenance = try Provenance(from: decoder)
        }
    }

    /// The title of each picture `library.json` lists, translatable. The comment tells
    /// translators which work it is, so a title can follow the work's name in their language.
    private static func title(of id: String) -> String? {
        switch id {
        case "great-wave": String(
            localized: "sample.great-wave", defaultValue: "The Great Wave",
            comment: "Title of a bundled picture: Katsushika Hokusai's woodblock print Under the Wave off Kanagawa, known as The Great Wave. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "delicate-arch": String(
            localized: "sample.delicate-arch", defaultValue: "Delicate Arch",
            comment: "Title of a bundled photograph: the sandstone arch in Arches National Park, Utah, at sunset (photograph by Neal Herbert, National Park Service). Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "wheat-field": String(
            localized: "sample.wheat-field", defaultValue: "Wheat Field with Cypresses",
            comment: "Title of a bundled painting: Vincent van Gogh's 1889 painting of a wheat field with dark cypress trees under a swirling sky. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "hawksbill-turtle": String(
            localized: "sample.hawksbill-turtle", defaultValue: "Hawksbill Sea Turtle",
            comment: "Title of a bundled photograph: a hawksbill sea turtle swimming over a reef (photograph by Caroline S. Rogers). Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "milkmaid": String(
            localized: "sample.milkmaid", defaultValue: "The Milkmaid",
            comment: "Title of a bundled painting: Johannes Vermeer's painting of a kitchen maid pouring milk, known as The Milkmaid. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "earthrise": String(
            localized: "sample.earthrise", defaultValue: "Earthrise",
            comment: "Title of a bundled picture: the Apollo 8 photograph of the Earth rising over the Moon's horizon, known as Earthrise. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "red-fuji": String(
            localized: "sample.red-fuji", defaultValue: "Red Fuji",
            comment: "Title of a bundled picture: Katsushika Hokusai's woodblock print South Wind, Clear Sky, known as Red Fuji. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "red-fox": String(
            localized: "sample.red-fox", defaultValue: "Red Fox in Snow",
            comment: "Title of a bundled photograph: a red fox hunting in the snow in Yellowstone National Park (photograph by Neal Herbert, National Park Service). Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "irises": String(
            localized: "sample.irises", defaultValue: "Irises",
            comment: "Title of a bundled painting: Vincent van Gogh's 1890 still life of blue irises in a vase. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "blue-marble": String(
            localized: "sample.blue-marble", defaultValue: "The Blue Marble",
            comment: "Title of a bundled photograph: the Apollo 17 photograph of the whole Earth, known as The Blue Marble. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "plum-park": String(
            localized: "sample.plum-park", defaultValue: "Plum Garden at Kameido",
            comment: "Title of a bundled picture: Utagawa Hiroshige's woodblock print of plum trees in blossom at Kameido Shrine, Tokyo. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "grand-prismatic": String(
            localized: "sample.grand-prismatic", defaultValue: "Grand Prismatic Spring",
            comment: "Title of a bundled photograph: an aerial view of Grand Prismatic Spring, a multicolored hot spring in Yellowstone National Park. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "cranes": String(
            localized: "sample.cranes", defaultValue: "Cranes",
            comment: "Title of a bundled picture: Kamisaka Sekka's woodblock print of two cranes among pine branches. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "atlantic-puffins": String(
            localized: "sample.atlantic-puffins", defaultValue: "Atlantic Puffins",
            comment: "Title of a bundled photograph: Atlantic puffins on a rocky ledge (U.S. Fish and Wildlife Service). Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "sudden-shower": String(
            localized: "sample.sudden-shower", defaultValue: "Sudden Shower over Shin-Ōhashi",
            comment: "Title of a bundled picture: Utagawa Hiroshige's woodblock print of people crossing the Shin-Ōhashi bridge in a sudden rain shower. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "oxbow-bend": String(
            localized: "sample.oxbow-bend", defaultValue: "Oxbow Bend in Autumn",
            comment: "Title of a bundled photograph: autumn view of aspens reflected in the Snake River at Oxbow Bend, Grand Teton National Park. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "oleanders": String(
            localized: "sample.oleanders", defaultValue: "Oleanders",
            comment: "Title of a bundled painting: Vincent van Gogh's 1888 still life of pink oleanders in a jug beside two books. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "south-manitou-lighthouse": String(
            localized: "sample.south-manitou-lighthouse", defaultValue: "South Manitou Island Lighthouse",
            comment: "Title of a bundled photograph: the lighthouse on South Manitou Island, Lake Michigan. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "paris-street": String(
            localized: "sample.paris-street", defaultValue: "Paris Street; Rainy Day",
            comment: "Title of a bundled painting: Gustave Caillebotte's 1877 painting of people with umbrellas on a rainy Paris street. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "monarch-coneflower": String(
            localized: "sample.monarch-coneflower", defaultValue: "Monarch on Coneflower",
            comment: "Title of a bundled photograph: a monarch butterfly on a purple coneflower. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "cezanne-apples": String(
            localized: "sample.cezanne-apples", defaultValue: "Still Life with Apples and Pears",
            comment: "Title of a bundled painting: Paul Cézanne's still life of apples and pears on a table. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "bison-in-snow": String(
            localized: "sample.bison-in-snow", defaultValue: "Bison in Snow",
            comment: "Title of a bundled photograph: an American bison pushing through deep snow. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "wisteria": String(
            localized: "sample.wisteria", defaultValue: "Wisteria",
            comment: "Title of a bundled picture: Kamisaka Sekka's woodblock print of hanging wisteria blossoms and leaves. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "lassen-lupine": String(
            localized: "sample.lassen-lupine", defaultValue: "Lupine at Lassen Peak",
            comment: "Title of a bundled photograph: purple lupine flowers below Lassen Peak, California. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "sainte-victoire": String(
            localized: "sample.sainte-victoire", defaultValue: "Mont Sainte-Victoire",
            comment: "Title of a bundled painting: Paul Cézanne's painting of the mountain Sainte-Victoire in Provence. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "bald-eagle": String(
            localized: "sample.bald-eagle", defaultValue: "Bald Eagle",
            comment: "Title of a bundled photograph: a close-up of a bald eagle's head. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "fukagawa-eagle": String(
            localized: "sample.fukagawa-eagle", defaultValue: "Jūmantsubo Plain at Fukagawa Susaki",
            comment: "Title of a bundled picture: Utagawa Hiroshige's woodblock print of an eagle soaring over the snowy Jūmantsubo plain at Fukagawa Susaki, Edo. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "reef-fish": String(
            localized: "sample.reef-fish", defaultValue: "Reef Fish",
            comment: "Title of a bundled photograph: a school of fish over a coral reef in Biscayne National Park. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "snap-the-whip": String(
            localized: "sample.snap-the-whip", defaultValue: "Snap the Whip",
            comment: "Title of a bundled painting: Winslow Homer's 1872 painting of boys playing the game snap-the-whip outside a schoolhouse. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "horseshoe-bend": String(
            localized: "sample.horseshoe-bend", defaultValue: "Horseshoe Bend",
            comment: "Title of a bundled photograph: the Colorado River's horseshoe-shaped bend near Page, Arizona. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "morning-glories": String(
            localized: "sample.morning-glories", defaultValue: "Morning Glories",
            comment: "Title of a bundled picture: Suzuki Kiitsu's folding screen of blue morning glories on gold leaf. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "hummingbird": String(
            localized: "sample.hummingbird", defaultValue: "Hummingbird and Beeplant",
            comment: "Title of a bundled photograph: a hummingbird drinking from a pink beeplant flower. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "pourville": String(
            localized: "sample.pourville", defaultValue: "Low Tide at Pourville",
            comment: "Title of a bundled painting: Claude Monet's 1882 painting of a chalk cliff over a calm sea at Pourville, France. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "santa-fe-freight": String(
            localized: "sample.santa-fe-freight", defaultValue: "Freight Train, New Mexico",
            comment: "Title of a bundled photograph: Jack Delano's 1943 color photograph of a steam freight train in New Mexico. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "haeckel-medusae": String(
            localized: "sample.haeckel-medusae", defaultValue: "Jellyfish",
            comment: "Title of a bundled picture: Ernst Haeckel's 1904 scientific illustration of jellyfish from Kunstformen der Natur. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "wood-duck": String(
            localized: "sample.wood-duck", defaultValue: "Wood Duck",
            comment: "Title of a bundled photograph: a male wood duck swimming. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "outskirts-paris": String(
            localized: "sample.outskirts-paris", defaultValue: "Outskirts of Paris",
            comment: "Title of a bundled painting: Henri Rousseau's painting of houses and a canal on the outskirts of Paris. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "catskill-barn": String(
            localized: "sample.catskill-barn", defaultValue: "Barn in the Catskills",
            comment: "Title of a bundled photograph: John Collier's 1943 color photograph of a weathered barn in the Catskill Mountains. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "redoute-rose": String(
            localized: "sample.redoute-rose", defaultValue: "Frankfort Rose",
            comment: "Title of a bundled picture: Pierre-Joseph Redouté's botanical engraving of the Frankfort rose (Rosa turbinata). Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "nassau-surf": String(
            localized: "sample.nassau-surf", defaultValue: "Shore and Surf, Nassau",
            comment: "Title of a bundled picture: Winslow Homer's 1899 watercolor of breaking surf on the shore at Nassau, Bahamas. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "bermuda-garden": String(
            localized: "sample.bermuda-garden", defaultValue: "Flower Garden and Bungalow, Bermuda",
            comment: "Title of a bundled picture: Winslow Homer's 1899 watercolor of a flower garden and a white-roofed bungalow in Bermuda. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "willow-bough": String(
            localized: "sample.willow-bough", defaultValue: "Willow Bough",
            comment: "Title of a bundled picture: William Morris's 1887 wallpaper pattern of willow leaves. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "oriental-poppies": String(
            localized: "sample.oriental-poppies", defaultValue: "Oriental Poppies",
            comment: "Title of a bundled picture: Alphonse Mucha's Art Nouveau design of oriental poppies. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "dancing-fox": String(
            localized: "sample.dancing-fox", defaultValue: "Dancing Fox",
            comment: "Title of a bundled picture: Ohara Koson's woodblock print of a fox dancing with a lotus leaf on its head. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        default: nil
        }
    }

    /// The six photos the app shipped with before the curated library. Saved paintings name
    /// them and regenerate from them when they have no stored photo, so they stay in the
    /// bundle; their provenance was never recorded, so they are neither offered nor credited.
    /// The quality regression and the benchmark run on them (`tools/regression.py`).
    static let retired: [Sample] = [
        Sample(id: "parrots", title: String(
            localized: "sample.parrots", defaultValue: "Parrots",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "hibiscus", title: String(
            localized: "sample.hibiscus", defaultValue: "Hibiscus",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "lighthouse", title: String(
            localized: "sample.lighthouse", defaultValue: "Lighthouse",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "barn", title: String(
            localized: "sample.barn", defaultValue: "Red Barn",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "espresso", title: String(
            localized: "sample.espresso", defaultValue: "Espresso",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "regatta", title: String(
            localized: "sample.regatta", defaultValue: "Regatta",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
    ]
}
