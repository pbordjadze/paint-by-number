#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore

/// Stained Glass's windows (painting-company row 366), kept as the app keeps its paintings: an
/// `ArtworkStore` of their own, `Application Support/StainedGlass/Windows/<uuid>/`, each a
/// painting's folder (`meta.json`, `template.pbnt`, `progress.bin`, `source.jpg`, `thumbnail.png`)
/// with one file more, `glazing.bin` (PaintCore's `Glazing`: the glass in each piece, since the
/// painter may put any glass in any piece). The template is the window's lead, its paints the
/// glasses the photo suggested; `progress.bin` stays a fresh painting's, and the meta's painted
/// count is the pieces glazed, so the folder reads as a painting to anything that lists one.
@MainActor
@Observable
final class GlassShelf {
    static let shared = GlassShelf()

    let store: ArtworkStore
    /// Newest first.
    private(set) var windows: [Artwork] = []
    private(set) var isLoaded = false

    init(root: URL = GlassShelf.defaultRoot) {
        store = ArtworkStore(root: root)
    }

    static var defaultRoot: URL {
        #if DEBUG
        // Demo and test launches keep a window shelf of their own, empty at each launch.
        if DemoMode.isActive || DemoMode.isTestHost { return demoRoot }
        #endif
        return URL.applicationSupportDirectory.appending(path: "StainedGlass/Windows", directoryHint: .isDirectory)
    }

    #if DEBUG
    private static let demoRoot: URL = {
        let root = FileManager.default.temporaryDirectory.appending(path: "StainedGlassDemo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        return root
    }()
    #endif

    nonisolated static let glazingFile = "glazing.bin"

    func load() async {
        let store = store
        let found = await Background.run { store.loadAll() }
        windows = found.sorted { $0.modifiedAt > $1.modifiedAt }
        isLoaded = true
    }

    func window(_ id: UUID) -> Artwork? { windows.first { $0.id == id } }

    /// Saves a window just leaded, nothing glazed, and lists it first.
    func create(_ leaded: GlassWindow.Leaded, photo: RGBAImage, title: String) async throws -> Artwork {
        let template = leaded.template
        let artwork = Artwork(title: title, template: template, settings: GenerationSettings())
        let store = store
        let glazing = Glazing(pieces: template.regions.count)
        let offered = GlassPalette.offered(for: template)
        try await Background.run {
            let source = PhotoLoader.cgImage(from: photo).flatMap {
                ImageCodec.jpegData(ImageCodec.downscaled($0, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
            }
            let thumbnail = GlassPicture.image(of: template, glazing: glazing, offered: offered, longSide: ArtworkStore.thumbnailMaxPixelSize)
                .flatMap(ImageCodec.pngData)
            try store.create(
                artwork, template: template, progress: PaintProgress(regionCount: template.regions.count),
                sourceJPEG: source, thumbnailPNG: thumbnail)
            try glazing.encoded().write(to: store.directory(for: artwork.id).appending(path: Self.glazingFile), options: .atomic)
        }
        windows.insert(artwork, at: 0)
        return artwork
    }

    /// A window to glaze: its lead and glasses, and the glass in each piece so far. A glazing
    /// file missing or damaged is a window not yet glazed (logged), never a lost window; one from
    /// a newer app throws.
    struct Opened: Sendable {
        var template: Template
        var glazing: Glazing
        var offered: [PaletteColor]
    }

    func open(_ artwork: Artwork) async throws -> Opened {
        let store = store
        return try await Background.run {
            let template = try store.readTemplate(artwork.id)
            let offered = GlassPalette.offered(for: template)
            let url = store.directory(for: artwork.id).appending(path: Self.glazingFile)
            var glazing = Glazing(pieces: template.regions.count)
            if let data = try? Data(contentsOf: url) {
                do {
                    glazing = try Glazing(encoded: data, pieces: template.regions.count, offered: offered.count)
                } catch Glazing.CodingError.newerVersion(let version) {
                    throw Glazing.CodingError.newerVersion(version)
                } catch {
                    Log.library.error("Unreadable glazing of window \(artwork.id.uuidString, privacy: .public): starting it unglazed")
                }
            }
            return Opened(template: template, glazing: glazing, offered: offered)
        }
    }

    /// Writes a window's glazing, its picture on the shelf and its meta (the pieces glazed).
    func save(_ glazing: Glazing, of id: UUID, template: Template, offered: [PaletteColor]) async {
        guard var artwork = window(id) else { return }
        artwork.paintedCount = glazing.glazedCount
        artwork.modifiedAt = .now
        if artwork.completedAt == nil && artwork.isComplete { artwork.completedAt = .now }
        if !artwork.isComplete { artwork.completedAt = nil }
        artwork.thumbnailVersion += 1
        let saved = artwork
        let store = store
        do {
            try await Background.run {
                try glazing.encoded().write(to: store.directory(for: id).appending(path: Self.glazingFile), options: .atomic)
                if let png = GlassPicture.image(of: template, glazing: glazing, offered: offered, longSide: ArtworkStore.thumbnailMaxPixelSize)
                    .flatMap(ImageCodec.pngData) {
                    try? store.writeThumbnail(png, for: id)
                }
                try store.writeMeta(saved)
            }
        } catch {
            Log.library.error("Couldn't save window \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        if let i = windows.firstIndex(where: { $0.id == id }) { windows[i] = saved }
        windows.sort { $0.modifiedAt > $1.modifiedAt }
    }

    func delete(_ id: UUID) {
        let store = store
        windows.removeAll { $0.id == id }
        Task {
            do {
                try await Background.run { try store.moveToTrash(id) }
            } catch {
                Log.library.error("Couldn't delete window \(id.uuidString, privacy: .public)")
            }
        }
    }

    func thumbnail(of artwork: Artwork) async -> CGImage? {
        let store = store, id = artwork.id
        return await Background.run { store.thumbnail(id, maxPixelSize: 720) }
    }

    /// A window's name: "Window, November 20".
    static func title(on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        return String(localized: "glass.windowTitle", defaultValue: "Window, \(day)",
                      comment: "Name of a new stained glass window: the word Window and the day it was made, e.g. “Window, November 20”")
    }
}
#endif
