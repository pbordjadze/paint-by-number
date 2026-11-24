#if UNRELEASED
import Compression
import CoreGraphics
import Foundation
import Observation
import PaintCore
import os

/// Woodblock's prints (painting-company row 375), kept as the app keeps its paintings: an
/// `ArtworkStore` of their own, `Application Support/Woodblock/Prints/<uuid>/`, each a painting's
/// folder (`meta.json`, `template.pbnt`, `progress.bin`, `source.jpg`, `thumbnail.png`) with one
/// file more, `woodblock.bench` (PaintCore's `WoodblockBench`, LZFSE: the block on the bench, how
/// far it is worked and the sheet so far), and for a Portrait photo `depth.bin` (PaintCore's
/// `PhotoDepth`, LZFSE: the camera's depth and sky, which names the sky the bokashi shades). The
/// template is the print's own, as generated; its blocks (`WoodblockPlan`) are made from it and
/// its depth each time it opens. `progress.bin` stays a fresh
/// painting's, and the meta's painted count is the share of the blocks printed, so the folder
/// reads as a painting to anything that lists one.
@MainActor
@Observable
final class WoodblockShelf {
    static let shared = WoodblockShelf()

    let store: ArtworkStore
    /// Newest first.
    private(set) var prints: [Artwork] = []
    private(set) var isLoaded = false
    @ObservationIgnored private var saving: [UUID: Task<Void, Never>] = [:]

    init(root: URL = WoodblockShelf.defaultRoot) {
        store = ArtworkStore(root: root)
    }

    static var defaultRoot: URL {
        #if DEBUG
        // Demo and test launches keep a shelf of their own, empty at each launch.
        if DemoMode.isActive || DemoMode.isTestHost { return demoRoot }
        #endif
        return URL.applicationSupportDirectory.appending(path: "Woodblock/Prints", directoryHint: .isDirectory)
    }

    #if DEBUG
    private static let demoRoot: URL = {
        let root = FileManager.default.temporaryDirectory.appending(path: "WoodblockDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        return root
    }()
    #endif

    nonisolated static let benchFile = "woodblock.bench"
    /// A bench is 8 bytes a cell of at most 1400 × 1400, compressed.
    nonisolated static let maximumBenchBytes = 24 * 1024 * 1024

    nonisolated static let depthFile = "depth.bin"
    /// The longest side a print keeps its depth at (a camera's is about 768): with its three
    /// mattes, at most 4 bytes a pixel of it.
    nonisolated static let depthSide = 1024
    nonisolated static let maximumDepthBytes = 14 + 4 * depthSide * depthSide

    func load() async {
        let store = store
        let found = await Background.run { store.loadAll() }
        let current = prints
        prints = found.map { read in current.first { $0.id == read.id && $0.modifiedAt > read.modifiedAt } ?? read }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        isLoaded = true
    }

    func print(_ id: UUID) -> Artwork? { prints.first { $0.id == id } }

    /// The template a photo is printed from: the app's own (Auto at a quick Painting Length,
    /// beauty paint, a coloring book), with the few paints a printer would cut a block each for.
    nonisolated static func template(of photo: RGBAImage) async throws -> (Template, GenerationSettings) {
        var kept = GenerationSettings()
        kept.paintMix = CreateModel.newPaintMix
        kept.tuning = CreateModel.newTuning
        var settings = try await ArtworkFactory.suggested(for: photo, keeping: kept, length: .quick,
                                                          maxCandidates: CreateModel.maxCandidates)
        settings.colorCount = WoodblockPlan.paints
        settings.detail = min(settings.detail, 0.4)
        settings = settings.normalized
        let template = try await ArtworkFactory.template(from: photo, settings: settings, progress: nil)
        return (template, settings)
    }

    /// Saves a new print, nothing carved, and lists it first.
    func create(template: Template, settings: GenerationSettings, photo: RGBAImage, depth: PhotoDepth? = nil,
                title: String, sampleName: String?) async throws -> Artwork {
        var artwork = Artwork(title: title, template: template, settings: settings, sampleName: sampleName)
        artwork.paintedCount = 0
        let store = store
        let saved = artwork
        try await Background.run {
            let keptDepth = depth.map(Self.kept)
            let plan = WoodblockPlan(template: template, depth: keptDepth)
            let bench = WoodblockBench(plan: plan)
            let source = PhotoLoader.cgImage(from: photo).flatMap {
                ImageCodec.jpegData(ImageCodec.downscaled($0, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
            }
            var style = TemplateRasterizer.Style()
            style.outlineWidth = 0.9
            style.outlineColor = SIMD4(0.12, 0.1, 0.1, 0.85)
            style.paper = WoodblockPlan.paper
            let thumbnail = TemplateRasterizer.image(template, style: style, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
                .flatMap(ImageCodec.pngData)
            try store.create(saved, template: template, progress: PaintProgress(regionCount: template.regions.count),
                             sourceJPEG: source, thumbnailPNG: thumbnail)
            let dir = store.directory(for: saved.id)
            if let keptDepth {
                let data = try (Data(keptDepth.encoded()) as NSData).compressed(using: .lzfse) as Data
                try data.write(to: dir.appending(path: Self.depthFile), options: .atomic)
            }
            try Self.write(bench, to: dir)
        }
        prints.insert(artwork, at: 0)
        return artwork
    }

    /// A print to open: its blocks and its bench as it was left. A bench missing or damaged is
    /// the print begun again (logged), never a lost print: its template is kept. A bench from a
    /// newer app throws, and a file there but unreadable now throws and is kept.
    struct Opened: Sendable {
        var plan: WoodblockPlan
        var bench: WoodblockBench
    }

    func open(_ artwork: Artwork) async throws -> Opened {
        let store = store
        let id = artwork.id
        return try await Background.run {
            let template = try store.readTemplate(id)
            let plan = WoodblockPlan(template: template, depth: try Self.depth(at: store.directory(for: id)))
            let url = store.directory(for: id).appending(path: Self.benchFile)
            var bench = WoodblockBench(plan: plan)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                let data = try Data(contentsOf: url)
                do {
                    guard data.count <= Self.maximumBenchBytes else { throw WoodblockBench.CodingError.corrupt }
                    bench = try WoodblockBench(decoding: Self.decompressed(data, plan: plan), plan: plan)
                } catch WoodblockBench.CodingError.newerVersion {
                    throw WoodblockBench.CodingError.newerVersion
                } catch {
                    // Kept beside the print, so a later app that reads it can bring it back.
                    let aside = url.appendingPathExtension("unread-\(Int(Date.now.timeIntervalSince1970))")
                    try? FileManager.default.moveItem(at: url, to: aside)
                    Log.library.error("Unreadable bench of print \(id.uuidString, privacy: .public): kept aside, starting it again")
                }
            }
            return Opened(plan: plan, bench: bench)
        }
    }

    /// A Portrait photo's depth at the size a print keeps it.
    nonisolated private static func kept(_ depth: PhotoDepth) -> PhotoDepth {
        let w = depth.nearness.width, h = depth.nearness.height
        guard max(w, h) > depthSide else { return depth }
        let scale = Double(depthSide) / Double(max(w, h))
        return depth.laid(width: max(1, Int((Double(w) * scale).rounded())), height: max(1, Int((Double(h) * scale).rounded())))
    }

    /// A print's depth, read as hostile input: none kept is nil, and so is one damaged (logged;
    /// the print's plan is then made without it, and a bench cut by the plan with it is refused
    /// by its signature, never misread). A file there but unreadable now throws.
    nonisolated private static func depth(at dir: URL) throws -> PhotoDepth? {
        let url = dir.appending(path: depthFile)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumDepthBytes else {
            Log.library.error("Depth of a print is too large: printed without it")
            return nil
        }
        var raw = [UInt8](repeating: 0, count: maximumDepthBytes + 1)
        let count = data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let from = source.bindMemory(to: UInt8.self).baseAddress, !source.isEmpty else { return 0 }
            return raw.withUnsafeMutableBufferPointer { into in
                compression_decode_buffer(into.baseAddress!, into.count, from, source.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard count > 0, count <= maximumDepthBytes else {
            Log.library.error("Unreadable depth of a print: printed without it")
            return nil
        }
        do {
            return try PhotoDepth(decoding: Array(raw.prefix(count)))
        } catch {
            Log.library.error("Unreadable depth of a print (\(String(describing: error), privacy: .public)): printed without it")
            return nil
        }
    }

    /// A bench's bytes out of their LZFSE, never more than the plan's bench holds: a crafted file
    /// that expands past it is refused before it can take the memory.
    nonisolated private static func decompressed(_ data: Data, plan: WoodblockPlan) throws -> [UInt8] {
        let expected = WoodblockBench.byteCount(cells: plan.grid.width * plan.grid.height)
        // One byte more than a bench, to tell a file that fills it from one that runs past.
        var raw = [UInt8](repeating: 0, count: expected + 1)
        let count = data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let from = source.bindMemory(to: UInt8.self).baseAddress, !source.isEmpty else { return 0 }
            return raw.withUnsafeMutableBufferPointer { into in
                compression_decode_buffer(into.baseAddress!, into.count, from, source.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard count == expected else { throw WoodblockBench.CodingError.corrupt }
        raw.removeLast()
        return raw
    }

    nonisolated private static func write(_ bench: WoodblockBench, to dir: URL) throws {
        let data = try (Data(bench.encoded()) as NSData).compressed(using: .lzfse) as Data
        try data.write(to: dir.appending(path: benchFile), options: .atomic)
    }

    /// Writes a print's bench, its picture on the shelf and its meta, after its saves before it.
    @discardableResult
    func enqueue(_ bench: WoodblockBench, of id: UUID, plan: WoodblockPlan) -> Task<Void, Never> {
        let previous = saving[id]
        let task = Task {
            await previous?.value
            await write(bench, of: id, plan: plan)
        }
        saving[id] = task
        return task
    }

    private func write(_ bench: WoodblockBench, of id: UUID, plan: WoodblockPlan) async {
        guard var artwork = print(id) else { return }
        let total = max(1, plan.blocks.count)
        let printed = bench.step == .peeled ? bench.block + 1 : bench.block
        artwork.paintedCount = min(artwork.regionCount, artwork.regionCount * min(printed, total) / total)
        artwork.modifiedAt = .now
        if artwork.completedAt == nil && artwork.isComplete { artwork.completedAt = .now }
        if !artwork.isComplete { artwork.completedAt = nil }
        let picture = printed > 0
        if picture { artwork.thumbnailVersion += 1 }
        let saved = artwork
        let store = store
        let space = plan.template.colorSpace
        do {
            try await Background.run {
                let dir = store.directory(for: id)
                try Self.write(bench, to: dir)
                if picture, let png = Self.picture(of: bench, space: space).flatMap(ImageCodec.pngData) {
                    try? store.writeThumbnail(png, for: id)
                }
                try store.writeMeta(saved)
            }
        } catch {
            Log.library.error("Couldn't save print \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        if let i = prints.firstIndex(where: { $0.id == id }) {
            // A name given while this was written stays: the rename queued after it writes it.
            var kept = saved
            kept.title = prints[i].title
            kept.titled = prints[i].titled
            prints[i] = kept
        }
        prints.sort { $0.modifiedAt > $1.modifiedAt }
    }

    /// The print as it stands, the right way round.
    nonisolated static func picture(of bench: WoodblockBench, space: RGBColorSpace) -> CGImage? {
        var image = bench.print()
        image.colorSpace = space
        return PhotoLoader.cgImage(from: image)
    }

    /// Gives a print the painter's name for it (the frame's card menu, `ModeGallery`), its meta
    /// written after the saves before it (which keep the name it holds here when they land).
    func rename(_ id: UUID, to title: String) {
        guard var artwork = print(id), !artwork.needsNewerApp, artwork.title != title else { return }
        artwork.title = title
        if artwork.titled != nil { artwork.titled = true }
        if let i = prints.firstIndex(where: { $0.id == id }) { prints[i] = artwork }
        let previous = saving[id]
        let store = store
        saving[id] = Task {
            await previous?.value
            guard let saved = print(id) else { return }
            do {
                try await Background.run { try store.writeMeta(saved) }
            } catch {
                Log.library.error("Couldn't rename print \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    func delete(_ id: UUID) {
        let store = store
        prints.removeAll { $0.id == id }
        Task {
            do {
                try await Background.run { try store.moveToTrash(id) }
            } catch {
                Log.library.error("Couldn't delete print \(id.uuidString, privacy: .public)")
            }
        }
    }

    /// The print as it stands, as large as the shelf keeps its picture: what the card menu's Share
    /// shares.
    func picture(of id: UUID) async -> CGImage? {
        await saving[id]?.value
        let store = store
        return await Background.run { store.thumbnail(id, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize) }
    }

    func thumbnail(of artwork: Artwork) async -> CGImage? {
        let store = store, id = artwork.id
        return await Background.run { store.thumbnail(id, maxPixelSize: 720) }
    }

    /// A new print's name: "Print, November 21", and "Print 2, November 21" for the day's second.
    func title(on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        let taken = Set(prints.map(\.title))
        let first = String(localized: "woodblock.printTitle", defaultValue: "Print, \(day)",
                           comment: "Name of a new woodblock print: the word Print and the day it was made, e.g. “Print, November 21”")
        guard taken.contains(first) else { return first }
        for n in 2... {
            let title = String(localized: "woodblock.printTitleNumbered", defaultValue: "Print \(n), \(day)",
                               comment: "Name of a woodblock print made on a day that already has one: the word Print, its number that day and the day, e.g. “Print 2, November 21”")
            if !taken.contains(title) { return title }
        }
        return first
    }
}
#endif
