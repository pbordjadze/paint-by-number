#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore
import os

/// Watercolor's paintings (painting-company row 373), kept as the app keeps its own: an
/// `ArtworkStore` of their own, `Application Support/Watercolor/Paintings/<uuid>/`, each a
/// painting's folder (`meta.json`, `template.pbnt`, `progress.bin`, `source.jpg`, `thumbnail.png`)
/// with two files more: `watercolor.json` (PaintCore's `WatercolorLog`, every tap: the painting's
/// record) and `watercolor.sheet` (the sheet as it stood when last saved, LZFSE: `WatercolorSim`'s
/// snapshot, so a painting opens at once). `progress.bin` stays a fresh painting's, and the meta's
/// painted count is the areas painted, so the folder reads as a painting to anything that lists one.
@MainActor
@Observable
final class WatercolorShelf {
    static let shared = WatercolorShelf()

    let store: ArtworkStore
    /// Newest first.
    private(set) var paintings: [Artwork] = []
    private(set) var isLoaded = false
    @ObservationIgnored private var saving: [UUID: Task<Void, Never>] = [:]

    init(root: URL = WatercolorShelf.defaultRoot) {
        store = ArtworkStore(root: root)
    }

    static var defaultRoot: URL {
        #if DEBUG
        // Demo and test launches keep a shelf of their own, empty at each launch.
        if DemoMode.isActive || DemoMode.isTestHost { return demoRoot }
        #endif
        return URL.applicationSupportDirectory.appending(path: "Watercolor/Paintings", directoryHint: .isDirectory)
    }

    #if DEBUG
    private static let demoRoot: URL = {
        let root = FileManager.default.temporaryDirectory.appending(path: "WatercolorDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        return root
    }()
    #endif

    nonisolated static let logFile = "watercolor.json"
    nonisolated static let sheetFile = "watercolor.sheet"
    /// A snapshot is 16 bytes a cell of an 800-cell sheet, and a little for its areas.
    nonisolated static let maximumSheetBytes = 32 * 1024 * 1024

    func load() async {
        let store = store
        let found = await Background.run { store.loadAll() }
        let current = paintings
        paintings = found.map { read in current.first { $0.id == read.id && $0.modifiedAt > read.modifiedAt } ?? read }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        isLoaded = true
    }

    func painting(_ id: UUID) -> Artwork? { paintings.first { $0.id == id } }

    /// The template a photo is painted from: the app's own (Auto at the painter's Painting
    /// Length, beauty paint, a coloring book), as a new painting's.
    nonisolated static func template(of photo: RGBAImage, length: PaintingLength) async throws -> (Template, GenerationSettings) {
        var kept = GenerationSettings()
        kept.paintMix = CreateModel.newPaintMix
        kept.tuning = CreateModel.newTuning
        let settings = try await ArtworkFactory.suggested(for: photo, keeping: kept, length: length, maxCandidates: CreateModel.maxCandidates)
        let template = try await ArtworkFactory.template(from: photo, settings: settings, progress: nil)
        return (template, settings)
    }

    /// Saves a new painting, nothing painted, and lists it first.
    func create(template: Template, settings: GenerationSettings, photo: RGBAImage, title: String, sampleName: String?) async throws -> Artwork {
        var artwork = Artwork(title: title, template: template, settings: settings, sampleName: sampleName)
        artwork.paintedCount = 0
        let store = store
        let log = WatercolorLog(seed: WatercolorPainting.seed(of: artwork.id))
        let saved = artwork
        try await Background.run {
            let source = PhotoLoader.cgImage(from: photo).flatMap {
                ImageCodec.jpegData(ImageCodec.downscaled($0, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
            }
            var style = TemplateRasterizer.Style()
            style.outlineWidth = 0.9
            style.outlineColor = SIMD4(0.45, 0.46, 0.49, 0.35)
            style.paper = SIMD3(0.96, 0.94, 0.9)
            let thumbnail = TemplateRasterizer.image(template, style: style, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
                .flatMap(ImageCodec.pngData)
            try store.create(saved, template: template, progress: PaintProgress(regionCount: template.regions.count),
                             sourceJPEG: source, thumbnailPNG: thumbnail)
            try log.encoded().write(to: store.directory(for: saved.id).appending(path: Self.logFile), options: .atomic)
        }
        paintings.insert(artwork, at: 0)
        return artwork
    }

    /// A painting to open: its template, the sheet made for it, the assets it is drawn with and
    /// the simulation as it was left (its snapshot; a snapshot missing or damaged is the log
    /// replayed, which takes longer, and a log damaged a painting begun again, logged, never a
    /// lost painting). A log from a newer app throws.
    struct Opened: Sendable {
        var template: Template
        var log: WatercolorLog
        var sim: UncheckedSendable<WatercolorSim>
        var assets: WatercolorAssets
    }

    func open(_ artwork: Artwork) async throws -> Opened {
        let store = store
        let id = artwork.id
        return try await Background.run {
            let template = try store.readTemplate(id)
            let dir = store.directory(for: id)
            var log = WatercolorLog(seed: WatercolorPainting.seed(of: id))
            if let data = try? Data(contentsOf: dir.appending(path: Self.logFile)) {
                do {
                    log = try WatercolorLog(encoded: data, regions: template.regions.count, width: template.width, height: template.height)
                } catch WatercolorLog.CodingError.newerVersion(let version) {
                    throw WatercolorLog.CodingError.newerVersion(version)
                } catch {
                    Log.library.error("Unreadable watercolor log of \(id.uuidString, privacy: .public): starting it again")
                }
            }
            let sheet = WatercolorSheet(template: template, seed: log.seed)
            let sim = WatercolorSim(sheet: sheet)
            var restored = false
            if let compressed = try? Data(contentsOf: dir.appending(path: Self.sheetFile)) {
                do {
                    try sim.restore(from: ArtworkStore.lzfseDecoded(compressed, maximumBytes: Self.maximumSheetBytes))
                    restored = true
                } catch {
                    Log.library.error("Unreadable watercolor sheet of \(id.uuidString, privacy: .public): replaying its log")
                }
            }
            if !restored && !log.taps.isEmpty { sim.replay(log) }
            let assets = WatercolorAssets.make(template: template, sheet: sheet)
            return Opened(template: template, log: log, sim: UncheckedSendable(sim), assets: assets)
        }
    }

    /// Writes a painting's log and sheet, its picture on the shelf and its meta, after its saves
    /// before it, so an older sheet never lands over a newer one.
    @discardableResult
    func enqueue(id: UUID, log: WatercolorLog, snapshot: Data, painted: Int, picture: CGImage?) -> Task<Void, Never> {
        let previous = saving[id]
        let task = Task {
            await previous?.value
            await write(id: id, log: log, snapshot: snapshot, painted: painted, picture: picture)
        }
        saving[id] = task
        return task
    }

    private func write(id: UUID, log: WatercolorLog, snapshot: Data, painted: Int, picture: CGImage?) async {
        guard var artwork = painting(id) else { return }
        artwork.paintedCount = painted
        artwork.modifiedAt = .now
        if artwork.completedAt == nil && artwork.isComplete { artwork.completedAt = .now }
        if picture != nil { artwork.thumbnailVersion += 1 }
        let saved = artwork
        let store = store
        do {
            try await Background.run {
                let dir = store.directory(for: id)
                try log.encoded().write(to: dir.appending(path: Self.logFile), options: .atomic)
                let compressed = try (snapshot as NSData).compressed(using: .lzfse) as Data
                try compressed.write(to: dir.appending(path: Self.sheetFile), options: .atomic)
                if let png = picture.flatMap(ImageCodec.pngData) { try? store.writeThumbnail(png, for: id) }
                try store.writeMeta(saved)
            }
        } catch {
            Log.library.error("Couldn't save watercolor \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        if let i = paintings.firstIndex(where: { $0.id == id }) { paintings[i] = saved }
        paintings.sort { $0.modifiedAt > $1.modifiedAt }
    }

    func delete(_ id: UUID) {
        let store = store
        paintings.removeAll { $0.id == id }
        Task {
            do {
                try await Background.run { try store.moveToTrash(id) }
            } catch {
                Log.library.error("Couldn't delete watercolor \(id.uuidString, privacy: .public)")
            }
        }
    }

    func thumbnail(of artwork: Artwork) async -> CGImage? {
        let store = store, id = artwork.id
        return await Background.run { store.thumbnail(id, maxPixelSize: 720) }
    }

    /// A new painting's name, when the picture brings none: "Watercolor, November 21", and
    /// "Watercolor 2, November 21" for the day's second.
    func title(on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        let taken = Set(paintings.map(\.title))
        let first = String(localized: "watercolor.title", defaultValue: "Watercolor, \(day)",
                           comment: "Name of a new watercolor painting: the word Watercolor and the day it was made, e.g. “Watercolor, November 21”")
        guard taken.contains(first) else { return first }
        for n in 2... {
            let title = String(localized: "watercolor.titleNumbered", defaultValue: "Watercolor \(n), \(day)",
                               comment: "Name of a watercolor painting made on a day that already has one: the word Watercolor, its number that day and the day, e.g. “Watercolor 2, November 21”")
            if !taken.contains(title) { return title }
        }
        return first
    }
}
#endif
