import Foundation

/// What the app lays out for the parts of it that live outside the app: its widgets and its
/// stickers (painting-company rows 348 and 349). Compiled into the app, the widget extension and
/// the sticker extension alike, and Foundation only.
///
/// The paintings themselves never leave the app's own folder. The shelf holds pictures drawn
/// from them and three small lists, in a folder of the app group all three can read:
///
/// - `now.json` (`Now`) and the pictures it names: the painting in progress as it stands, and as
///   it will stand after each of the next few areas is painted, in the order the app would
///   paint them. The widget's Paint One Area shows the next picture and counts the tap in
///   `taps.json` (`Taps`); the app paints those areas for real when it next comes forward
///   (`OutsideDesk.absorb`) and lays the shelf out again. The extension never reads or writes
///   a painting.
/// - `finished.json` (`Finished`): the finished paintings' pictures, for the frame.
/// - `stickers.json` (`Stickers`): the stickers made of them.
///
/// Every list carries `version`; a reader that doesn't know it shows nothing rather than guess.
nonisolated struct OutsideShelf: Sendable {
    /// The app group as the project's entitlements name it.
    static let group = "group.com.pbordjadze.paintbynumber"
    static let version = 1

    let root: URL

    init(root: URL) { self.root = root }

    /// The shelf of this process, nil where the app group can't be reached (a build signed
    /// without it): the app then lays nothing out, and the extensions show their empty states.
    static func shared(bundle: Bundle = .main, fileManager: FileManager = .default) -> OutsideShelf? {
        for group in groups(of: bundle) {
            if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return OutsideShelf(root: container.appending(path: "Outside", directoryHint: .isDirectory))
            }
        }
        return nil
    }

    /// The names the app group may go by, likeliest first. An installer that signs the app
    /// again under another team (SideStore, AltStore) gives the group a name of that team and
    /// writes it into `ALTAppGroups` of the Info.plist; an extension asks its host app's too.
    static func groups(of bundle: Bundle) -> [String] {
        var names: [String] = []
        var bundles = [bundle]
        if bundle.bundleURL.pathExtension == "appex",
           let host = Bundle(url: bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) {
            bundles.append(host)
        }
        for b in bundles {
            names += (b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []).filter { $0.hasPrefix(group) }
        }
        names.append(group)
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    // MARK: The painting in progress

    struct Now: Codable, Sendable, Equatable {
        var version = OutsideShelf.version
        /// New each time the app lays the shelf out: taps counted against another are stale.
        var token: String
        var artwork: UUID
        var title: String
        /// Areas in the painting.
        var total: Int
        /// `steps[0]` is the painting as saved; `steps[k]` after the widget painted `k` areas.
        var steps: [Step]

        struct Step: Codable, Sendable, Equatable {
            /// The picture's file name on the shelf.
            var picture: String
            /// Areas painted in this picture.
            var painted: Int
            /// The area whose painting made this picture; nil for the first.
            var region: Int?
            /// The paint the next area takes: its number, its name where the app has one in the
            /// reader's language, and its color (sRGB, 0...255). Nil when the widget has no next
            /// area to offer from this picture.
            var next: Paint?
        }

        struct Paint: Codable, Sendable, Equatable {
            var number: Int
            var name: String?
            var red: Int
            var green: Int
            var blue: Int
        }

        /// The step the widget shows after `taps` taps.
        func step(after taps: Int) -> Step? {
            steps.isEmpty ? nil : steps[min(max(taps, 0), steps.count - 1)]
        }

        /// Whether a tap more has a picture to show.
        func offersTap(after taps: Int) -> Bool {
            taps >= 0 && taps < steps.count - 1
        }
    }

    struct Taps: Codable, Sendable, Equatable {
        var token: String
        var count: Int
    }

    // MARK: Finished paintings and stickers

    struct Finished: Codable, Sendable, Equatable {
        var version = OutsideShelf.version
        var paintings: [Painting]

        struct Painting: Codable, Sendable, Equatable, Identifiable {
            var id: UUID
            var title: String
            var picture: String
        }

        /// The painting the frame shows on `day` (a count of days): each a day in turn.
        func painting(onDay day: Int) -> Painting? {
            paintings.isEmpty ? nil : paintings[((day % paintings.count) + paintings.count) % paintings.count]
        }
    }

    struct Stickers: Codable, Sendable, Equatable {
        var version = OutsideShelf.version
        var stickers: [Sticker]

        struct Sticker: Codable, Sendable, Equatable {
            var painting: UUID
            /// What VoiceOver says of the sticker: the painting's title.
            var title: String
            var picture: String
        }
    }

    // MARK: Reading and writing

    enum File: String, Sendable {
        case now = "now.json"
        case taps = "taps.json"
        case finished = "finished.json"
        case stickers = "stickers.json"
    }

    func url(_ name: String) -> URL { root.appending(path: name) }

    func now() -> Now? {
        let value: Now? = read(.now)
        return value?.version == Self.version ? value : nil
    }

    func finished() -> Finished? {
        let value: Finished? = read(.finished)
        return value?.version == Self.version ? value : nil
    }

    func stickers() -> Stickers? {
        let value: Stickers? = read(.stickers)
        return value?.version == Self.version ? value : nil
    }

    /// The taps counted against `now`, 0 when there are none or they are another layout's.
    func taps(for now: Now) -> Int {
        guard let taps: Taps = read(.taps), taps.token == now.token else { return 0 }
        return min(max(taps.count, 0), max(now.steps.count - 1, 0))
    }

    /// Counts one more tap of Paint One Area, if the layout has a picture for it. Returns the count.
    @discardableResult
    func addTap() -> Int {
        guard let now = now() else { return 0 }
        let count = taps(for: now)
        guard now.offersTap(after: count) else { return count }
        try? write(Taps(token: now.token, count: count + 1), to: .taps)
        return count + 1
    }

    func clearTaps() { try? FileManager.default.removeItem(at: url(File.taps.rawValue)) }

    func read<T: Decodable>(_ file: File) -> T? {
        guard let data = try? Data(contentsOf: url(file.rawValue)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func write<T: Encodable>(_ value: T, to file: File) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url(file.rawValue), options: .atomic)
    }

    func write(_ data: Data, named name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url(name), options: .atomic)
    }

    /// Removes every picture whose name starts with `prefix` and isn't in `keeping`.
    func sweep(prefix: String, keeping: Set<String>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix(prefix) && !keeping.contains(name) {
            try? FileManager.default.removeItem(at: url(name))
        }
    }

    // MARK: Links

    /// The link a widget opens the app with to show a painting; any other URL is nil.
    static func link(toPainting id: UUID) -> URL { URL(string: "paintbymoonlight://painting/\(id.uuidString)")! }

    static func painting(of link: URL) -> UUID? {
        guard link.scheme == "paintbymoonlight", link.host() == "painting" else { return nil }
        return UUID(uuidString: link.lastPathComponent)
    }
}
