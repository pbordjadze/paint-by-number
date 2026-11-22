#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore
import os

/// The cave's paintings (painting-company row 371), in the order they were made: the wall itself.
/// Kept in `Application Support/Cave/Wall/`: `wall.json` lists the paintings oldest first, and
/// each has a folder of its own, `<uuid>/`, with its drawing (`cave.plan`, PaintCore's
/// `CavePlan`), its progress (`progress.bin`, `CaveProgress`: the areas done and the hand) and
/// its pigment (`pigment.lzfse`, `CavePigmentLayer.rgba()` compressed), its name (`title.txt`)
/// and the gallery's picture of it (`picture.jpg`, `CavePicture`, drawn again once its progress is
/// newer). Not a painting's folder of the app's: its numbers are the plan's dots, and it has no
/// template or palette to keep.
///
/// Never lose a painting: one whose drawing can't be read (damaged, or from a newer app) is left
/// on disk and in `wall.json`, and the wall goes on without it; progress that can't be read is a
/// painting not yet blown; pigment that can't be read is filled again from its progress.
@MainActor
@Observable
final class CaveShelf {
    static let shared = CaveShelf()

    let root: URL
    /// Oldest first, those that could be read.
    private(set) var paintings: [CaveScene.Painting] = []
    private(set) var isLoaded = false
    /// Every painting `wall.json` lists, read or not, so a save never drops one.
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(root: URL = CaveShelf.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        #if DEBUG
        // Demo and test launches keep a cave of their own, empty at each launch.
        if DemoMode.isActive || DemoMode.isTestHost { return demoRoot }
        #endif
        return URL.applicationSupportDirectory.appending(path: "Cave/Wall", directoryHint: .isDirectory)
    }

    #if DEBUG
    private static let demoRoot: URL = {
        let root = FileManager.default.temporaryDirectory.appending(path: "CaveDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        return root
    }()
    #endif

    nonisolated static let wallFile = "wall.json"
    nonisolated static let planFile = "cave.plan"
    nonisolated static let progressFile = "progress.bin"
    nonisolated static let pigmentFile = "pigment.lzfse"
    nonisolated static let titleFile = "title.txt"
    nonisolated static let pictureFile = "picture.jpg"

    nonisolated private struct Wall: Codable {
        var paintings: [UUID]
    }

    func load() async {
        guard !isLoaded else { return }
        let root = root
        let (order, read) = await Background.run { Self.read(root) }
        self.order = order
        paintings = read
        isLoaded = true
    }

    nonisolated private static func read(_ root: URL) -> ([UUID], [CaveScene.Painting]) {
        let ids: [UUID]
        if let data = try? Data(contentsOf: root.appending(path: wallFile)), let wall = try? JSONDecoder().decode(Wall.self, from: data) {
            ids = wall.paintings
        } else {
            // No wall.json, or one that can't be read: the order is made again from the paintings'
            // folders, oldest first, so the next save never writes a wall without them.
            ids = folders(root)
            if !ids.isEmpty { Log.library.error("The cave's wall.json can't be read: ordering its \(ids.count) folders by age") }
        }
        var paintings: [CaveScene.Painting] = []
        for id in ids {
            let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
            let plan: CavePlan
            do {
                plan = try CavePlan(encoded: Data(contentsOf: folder.appending(path: planFile)))
            } catch {
                Log.library.error("Cave painting \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
                continue
            }
            var progress = CaveProgress(done: Array(repeating: false, count: plan.areaCount))
            let progressURL = folder.appending(path: progressFile)
            if FileManager.default.fileExists(atPath: progressURL.path) {
                do {
                    progress = try CaveProgress(encoded: Data(contentsOf: progressURL), areas: plan.areaCount)
                } catch CaveProgress.CodingError.corrupt, CaveProgress.CodingError.otherPainting {
                    // Damaged for good: the painting starts again rather than being lost.
                    Log.library.error("Progress of cave painting \(id.uuidString, privacy: .public) is damaged: starting it again")
                } catch {
                    // A newer app's progress, or one that can't be read just now (data protection, a
                    // passing I/O error): the painting is left off the wall this launch, so no save
                    // writes fresh progress over it. The wall's order keeps it.
                    Log.library.error("Progress of cave painting \(id.uuidString, privacy: .public) can't be read now: \(String(describing: error), privacy: .public)")
                    continue
                }
            }
            var pigment: [UInt8]?
            if let packed = try? Data(contentsOf: folder.appending(path: pigmentFile)),
               let raw = try? (packed as NSData).decompressed(using: .lzfse) as Data,
               raw.count == CavePigmentLayer.width * CavePigmentLayer.height * 4 {
                pigment = [UInt8](raw)
            }
            let title = (try? String(contentsOf: folder.appending(path: titleFile), encoding: .utf8)) ?? ""
            paintings.append(CaveScene.Painting(id: id, plan: plan, progress: progress, pigment: pigment, title: title))
        }
        return (ids, paintings)
    }

    /// The paintings' folders, oldest first.
    nonisolated private static func folders(_ root: URL) -> [UUID] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let dated = urls.compactMap { url -> (UUID, Date)? in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return (id, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        return dated.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Adds a painting just drawn, nothing blown, at the deep end of the wall.
    @discardableResult
    func add(_ plan: CavePlan, title: String) async throws -> UUID {
        let id = UUID()
        let painting = CaveScene.Painting(id: id, plan: plan, progress: CaveProgress(done: Array(repeating: false, count: plan.areaCount)),
                                          pigment: nil, title: title)
        let root = root
        let order = self.order + [id]
        await saving?.value
        try await Background.run {
            let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try plan.encoded().write(to: folder.appending(path: CaveShelf.planFile), options: .atomic)
            try painting.progress.encoded().write(to: folder.appending(path: CaveShelf.progressFile), options: .atomic)
            try Data(title.utf8).write(to: folder.appending(path: CaveShelf.titleFile), options: .atomic)
            try JSONEncoder().encode(Wall(paintings: order)).write(to: root.appending(path: CaveShelf.wallFile), options: .atomic)
        }
        self.order = order
        paintings.append(painting)
        return id
    }

    /// A name for a new painting from a photo: the day it was drawn, numbered when the day has one.
    func title(on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        let taken = Set(paintings.map(\.title))
        let first = String(localized: "cave.title", defaultValue: "Cave Painting, \(day)",
                           comment: "Name of a new cave painting: the words Cave Painting and the day it was drawn, e.g. “Cave Painting, November 22”")
        guard taken.contains(first) else { return first }
        for n in 2... {
            let title = String(localized: "cave.titleNumbered", defaultValue: "Cave Painting \(n), \(day)",
                               comment: "Name of a cave painting drawn on a day that already has one: the words Cave Painting, its number that day and the day, e.g. “Cave Painting 2, November 22”")
            if !taken.contains(title) { return title }
        }
        return first
    }

    /// The painting with `id`, as the shelf has it.
    func painting(_ id: UUID) -> CaveScene.Painting? { paintings.first { $0.id == id } }

    /// The gallery's picture of a painting: kept beside it, drawn again (`CavePicture`) when its
    /// progress is newer than the picture.
    func picture(of id: UUID) async -> CGImage? {
        guard let painting = painting(id) else { return nil }
        await saving?.value
        let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        return await Background.run {
            let pictureURL = folder.appending(path: Self.pictureFile)
            func modified(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            if let kept = modified(pictureURL), let progress = modified(folder.appending(path: Self.progressFile)), kept >= progress,
               let image = ImageCodec.image(at: pictureURL) {
                return image
            }
            guard let image = CavePicture.draw(painting) else { return nil }
            if let data = ImageCodec.jpegData(image, quality: 0.85) { try? data.write(to: pictureURL, options: .atomic) }
            return image
        }
    }

    /// Takes a painting off the wall for good, after the saves before it (the painter confirmed it).
    func delete(_ id: UUID) {
        guard paintings.contains(where: { $0.id == id }) else { return }
        paintings.removeAll { $0.id == id }
        order.removeAll { $0 == id }
        let root = root, order = order
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                try await Background.run {
                    try JSONEncoder().encode(Wall(paintings: order)).write(to: root.appending(path: Self.wallFile), options: .atomic)
                    try FileManager.default.removeItem(at: root.appending(path: id.uuidString, directoryHint: .isDirectory))
                }
            } catch {
                Log.library.error("Couldn't delete cave painting \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Waits for every save queued so far to reach the disk.
    func flush() async { await saving?.value }

    /// Keeps a painting's progress and pigment, after the saves before it.
    func save(_ id: UUID, progress: CaveProgress, pigment: [UInt8]) {
        guard let i = paintings.firstIndex(where: { $0.id == id }) else { return }
        paintings[i].progress = progress
        paintings[i].pigment = pigment
        let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                try await Background.run {
                    try progress.encoded().write(to: folder.appending(path: Self.progressFile), options: .atomic)
                    let packed = try (Data(pigment) as NSData).compressed(using: .lzfse) as Data
                    try packed.write(to: folder.appending(path: Self.pigmentFile), options: .atomic)
                }
            } catch {
                Log.library.error("Couldn't save cave painting \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }
}
#endif
