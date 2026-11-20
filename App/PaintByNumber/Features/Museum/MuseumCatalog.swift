#if UNRELEASED
import CoreGraphics
import Foundation
import os

/// The Museum's catalog (SideStore and Debug builds, `#if UNRELEASED`; painting-company row 369):
/// open-access paintings, prints and drawings from museums that publish them as public domain
/// (CC0), each with the movement it belongs to and how colorful it is, browsed in `MuseumView`.
///
/// The catalog is one JSON file that `tools/museum/catalog.py` writes and the `museum` branch of
/// this repository serves (`source`): `{"version": 1, "made": "YYYY-MM-DD", "museums": {code:
/// name}, "movements": [name, …], "works": [Work, …]}`, the movements in the order the browser
/// lists them. It is downloaded on first opening, kept in the caches folder, and fetched again
/// in the background when the kept copy is a day old; a copy that can't be fetched or read is
/// no failure while an older one is kept.
nonisolated struct MuseumCatalog: Decodable, Sendable {
    let version: Int
    /// The day the tool wrote it ("2026-11-20").
    let made: String
    let museums: [String: String]
    let movements: [String]
    let works: [Work]
    /// Each work's title, artist, movement and year as search words, folded as a query's are
    /// (`MuseumQuery.words`), in `works`' order: made once, off the main actor, by `decode`.
    private(set) var searchWords: [[Substring]] = []

    private enum CodingKeys: String, CodingKey { case version, made, museums, movements, works }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        made = try container.decodeIfPresent(String.self, forKey: .made) ?? ""
        museums = try container.decode([String: String].self, forKey: .museums)
        movements = try container.decode([String].self, forKey: .movements)
        // A record this build can't read (a kind it doesn't know) is left out, not the catalog.
        works = try container.decode([Lenient].self, forKey: .works).compactMap(\.work)
    }

    private struct Lenient: Decodable {
        let work: Work?
        init(from decoder: any Decoder) throws { work = try? Work(from: decoder) }
    }

    /// One artwork, as the museum describes it. `title`, `artist`, `year` and `medium` are the
    /// museum's own words, shown verbatim.
    struct Work: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let title: String
        let artist: String
        /// As the museum dates the work: "1891", "c. 1830–32".
        let year: String
        /// The year the work was finished, for sorting; nil when the museum gives none.
        let date: Int?
        let movement: String
        let kind: Kind
        /// Hasler and Süsstrunk's colorfulness of the work's image: about 0 for grey, 30 to 60
        /// for most paintings, over 80 for the loudest.
        let colorfulness: Double
        /// The image's mean color (`rrggbb`), the tile's ground while its picture loads.
        let average: String
        let width: Int
        let height: Int
        /// The key of `MuseumCatalog.museums` that holds it.
        let museum: String
        /// A rendition about 400 to 900 pixels wide, for the browser's tiles.
        let thumb: URL
        /// The largest rendition the app paints from (1,686 to 3,400 pixels across, as the
        /// museum serves it).
        let image: URL
        /// The work's page on the museum's website.
        let page: URL?
        let medium: String

        enum Kind: String, Decodable, Sendable, CaseIterable {
            case painting, print, drawing
        }

        /// The work's title as a painting's name: the museum's, without a series it belongs to
        /// (", from the series …", which runs long on prints), and at most about 60 characters.
        var paintingTitle: String {
            var title = title
            for cut in [", from the series", " from the series", ", from the "] {
                if let range = title.range(of: cut, options: .caseInsensitive) { title = String(title[..<range.lowerBound]) }
            }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard title.count > 60 else { return title.isEmpty ? self.title : title }
            let short = title.prefix(60)
            let end = short.lastIndex(of: " ") ?? short.endIndex
            return String(short[..<end]) + "…"
        }

        /// Width over height, 1 when the museum gives no size.
        var aspectRatio: CGFloat {
            guard width > 0, height > 0 else { return 1 }
            return CGFloat(width) / CGFloat(height)
        }
    }

    /// Where the app reads the catalog: the `museum` branch of the app's own repository.
    static let source = URL(string: "https://raw.githubusercontent.com/pbordjadze/paint-by-number/refs/heads/museum/museum.json")!

    static func decode(_ data: Data) throws -> MuseumCatalog {
        var catalog = try JSONDecoder().decode(MuseumCatalog.self, from: data)
        catalog.searchWords = catalog.works.map {
            MuseumQuery.words(of: "\($0.title) \($0.artist) \($0.movement) \($0.year)")
        }
        return catalog
    }
}

/// What the browser shows of the catalog: a movement (or all), a kind, a search and an order.
/// A pure function of the catalog, so `MuseumQueryTests` can hold it.
nonisolated struct MuseumQuery: Equatable, Sendable {
    enum Order: String, CaseIterable, Sendable {
        case colorful, oldest, newest, shuffled
    }

    enum Kinds: String, CaseIterable, Sendable {
        case everything, paintings, printsAndDrawings

        func admits(_ kind: MuseumCatalog.Work.Kind) -> Bool {
            switch self {
            case .everything: true
            case .paintings: kind == .painting
            case .printsAndDrawings: kind != .painting
            }
        }
    }

    var movement: String?
    var kinds: Kinds = .everything
    var order: Order = .colorful
    var search = ""
    /// The order's seed while `shuffled`: the same seed, the same order.
    var seed: UInt64 = 1

    /// The works the browser shows, in its order. A search needs every word to start a word of
    /// the title, the artist, the movement or the year, ignoring case and diacritics. Most
    /// Colorful over all movements takes each movement's most colorful in turn.
    func works(of catalog: MuseumCatalog) -> [MuseumCatalog.Work] {
        let words = Self.words(of: search)
        var kept: [MuseumCatalog.Work] = []
        for (index, work) in catalog.works.enumerated() {
            if let movement, work.movement != movement { continue }
            guard kinds.admits(work.kind) else { continue }
            if !words.isEmpty {
                let haystack = index < catalog.searchWords.count ? catalog.searchWords[index] : []
                guard words.allSatisfy({ word in haystack.contains { $0.hasPrefix(word) } }) else { continue }
            }
            kept.append(work)
        }
        switch order {
        case .colorful:
            let sorted = kept.sorted { ($0.colorfulness, $1.id) > ($1.colorfulness, $0.id) }
            guard movement == nil else { return sorted }
            // Every movement's most colorful work before any movement's second, and so on: the
            // most colorful of all are one tradition's (India's bright borders), and a wall of it
            // hid the rest of the museum.
            var seen: [String: Int] = [:]
            let ranks = sorted.map { work -> Int in
                seen[work.movement, default: 0] += 1
                return seen[work.movement]!
            }
            return zip(ranks, sorted).enumerated()
                .sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
                .map(\.element.1)
        case .oldest:
            return kept.sorted { ($0.date ?? .max, $0.id) < ($1.date ?? .max, $1.id) }
        case .newest:
            return kept.sorted { ($0.date ?? .min, $1.id) > ($1.date ?? .min, $0.id) }
        case .shuffled:
            // A stable hash of each id with the seed: the same shuffle on every render.
            return kept.sorted { (Self.mix($0.id, seed), $0.id) < (Self.mix($1.id, seed), $1.id) }
        }
    }

    /// How many works each movement holds under this query's kind (its chip's count).
    func counts(of catalog: MuseumCatalog) -> [String: Int] {
        var counts: [String: Int] = [:]
        for work in catalog.works where kinds.admits(work.kind) { counts[work.movement, default: 0] += 1 }
        return counts
    }

    static func words(of text: String) -> [Substring] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
    }

    /// FNV-1a over the id's bytes, then SplitMix64's finalizer with the seed.
    static func mix(_ id: String, _ seed: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        var z = hash &+ seed &* 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

/// The catalog as the app holds it: loaded from the caches folder at once, fetched when there
/// is none or it is a day old.
@Observable
final class MuseumLibrary {
    enum State {
        case loading
        case ready(MuseumCatalog)
        case failed
    }

    static let shared = MuseumLibrary()

    private(set) var state: State = .loading
    private var task: Task<Void, Never>?

    private static var file: URL {
        URL.cachesDirectory.appending(path: "Museum/museum.json")
    }

    /// Loads the kept catalog and fetches a newer one when it is due. Calling it again while it
    /// runs, or once it is ready and fresh, does nothing.
    func open() {
        guard task == nil else { return }
        if case .ready = state { return }
        task = Task { await load() }
    }

    /// After a failure: try the network again.
    func retry() {
        task = nil
        state = .loading
        open()
    }

    private func load() async {
        defer { task = nil }
        let file = Self.file
        let kept: (MuseumCatalog, Date)? = await Background.run {
            guard let data = try? Data(contentsOf: file), let catalog = try? MuseumCatalog.decode(data) else { return nil }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (catalog, modified ?? .distantPast)
        }
        if let kept { state = .ready(kept.0) }
        if let kept, Date.now.timeIntervalSince(kept.1) < 24 * 3600 { return }
        do {
            var request = URLRequest(url: MuseumCatalog.source)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 60
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let catalog = try await Background.run {
                let catalog = try MuseumCatalog.decode(data)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                return catalog
            }
            state = .ready(catalog)
        } catch {
            Log.library.error("The museum's catalog didn't load: \(String(describing: error), privacy: .public)")
            if kept == nil { state = .failed }
        }
    }
}
#endif
