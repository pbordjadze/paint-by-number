#if UNRELEASED
import Foundation
import Observation
import PaintCore
import os

/// The cave's paintings (painting-company row 371), in the order they were made: the wall itself.
/// Kept in `Application Support/Cave/Wall/`: `wall.json` lists the paintings oldest first, and
/// each has a folder of its own, `<uuid>/`, with its drawing (`cave.plan`, PaintCore's
/// `CavePlan`), its progress (`progress.bin`, `CaveProgress`: the areas done and the hand) and
/// its pigment (`pigment.lzfse`, `CavePigmentLayer.rgba()` compressed). Not a painting's folder
/// of the app's: a cave painting has no numbers, template or palette to keep.
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
        guard let data = try? Data(contentsOf: root.appending(path: wallFile)) else { return ([], []) }
        guard let wall = try? JSONDecoder().decode(Wall.self, from: data) else {
            Log.library.error("The cave's wall.json can't be read: starting from what its folders hold")
            return ([], [])
        }
        var paintings: [CaveScene.Painting] = []
        for id in wall.paintings {
            let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
            let plan: CavePlan
            do {
                plan = try CavePlan(encoded: Data(contentsOf: folder.appending(path: planFile)))
            } catch {
                Log.library.error("Cave painting \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
                continue
            }
            var progress = CaveProgress(done: Array(repeating: false, count: plan.areaCount))
            if let data = try? Data(contentsOf: folder.appending(path: progressFile)) {
                do {
                    progress = try CaveProgress(encoded: data, areas: plan.areaCount)
                } catch {
                    Log.library.error("Progress of cave painting \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
                }
            }
            var pigment: [UInt8]?
            if let packed = try? Data(contentsOf: folder.appending(path: pigmentFile)),
               let raw = try? (packed as NSData).decompressed(using: .lzfse) as Data,
               raw.count == CavePigmentLayer.width * CavePigmentLayer.height * 4 {
                pigment = [UInt8](raw)
            }
            paintings.append(CaveScene.Painting(id: id, plan: plan, progress: progress, pigment: pigment))
        }
        return (wall.paintings, paintings)
    }

    /// Adds a painting just drawn, nothing blown, at the deep end of the wall.
    @discardableResult
    func add(_ plan: CavePlan) async throws -> UUID {
        let id = UUID()
        let painting = CaveScene.Painting(id: id, plan: plan, progress: CaveProgress(done: Array(repeating: false, count: plan.areaCount)), pigment: nil)
        let root = root
        let order = self.order + [id]
        await saving?.value
        try await Background.run {
            let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try plan.encoded().write(to: folder.appending(path: CaveShelf.planFile), options: .atomic)
            try painting.progress.encoded().write(to: folder.appending(path: CaveShelf.progressFile), options: .atomic)
            try JSONEncoder().encode(Wall(paintings: order)).write(to: root.appending(path: CaveShelf.wallFile), options: .atomic)
        }
        self.order = order
        paintings.append(painting)
        return id
    }

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
