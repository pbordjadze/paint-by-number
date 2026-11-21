#if UNRELEASED
import CoreGraphics
import Foundation
import Observation
import PaintCore
import os

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
    /// Each window's last save, which its next waits for.
    @ObservationIgnored private var saving: [UUID: Task<Void, Never>] = [:]

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
        // A save that finished while the shelf was read keeps what it wrote.
        let current = windows
        windows = found.map { read in current.first { $0.id == read.id && $0.modifiedAt > read.modifiedAt } ?? read }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        isLoaded = true
    }

    func window(_ id: UUID) -> Artwork? { windows.first { $0.id == id } }

    /// Saves a window just leaded, nothing glazed, and lists it first.
    func create(_ leaded: GlassWindow.Leaded, photo: RGBAImage, title: String) async throws -> Artwork {
        let template = leaded.template
        let artwork = Artwork(title: title, template: template, settings: GenerationSettings())
        let store = store
        let offered = GlassPalette.offered(for: template)
        let glazing = Glazing(pieces: template.regions.count, offered: offered)
        try await Background.run {
            let image = PhotoLoader.cgImage(from: photo)
            let source = image.flatMap {
                ImageCodec.jpegData(ImageCodec.downscaled($0, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
            }
            let thumbnail = Self.picture(of: template, glazing: glazing, offered: offered, texture: GlassTexture(template: template),
                                         photo: image, mode: nil)
                .flatMap(ImageCodec.pngData)
            try store.create(
                artwork, template: template, progress: PaintProgress(regionCount: template.regions.count),
                sourceJPEG: source, thumbnailPNG: thumbnail)
            try glazing.encoded().write(to: store.directory(for: artwork.id).appending(path: Self.glazingFile), options: .atomic)
        }
        windows.insert(artwork, at: 0)
        return artwork
    }

    /// A window to glaze: its lead and glasses, the glass in each piece so far, and its photo at
    /// the template's size, which its lenses look onto (none if it can't be read). A glazing
    /// file missing or damaged is a window not yet glazed (logged), never a lost window; one from
    /// a newer app throws.
    struct Opened: Sendable {
        var template: Template
        var glazing: Glazing
        var offered: [PaletteColor]
        var texture: GlassTexture
        var photo: CGImage?
    }

    func open(_ artwork: Artwork) async throws -> Opened {
        let store = store
        return try await Background.run {
            let template = try store.readTemplate(artwork.id)
            let url = store.directory(for: artwork.id).appending(path: Self.glazingFile)
            var glazing = Glazing(pieces: template.regions.count, offered: GlassPalette.offered(for: template))
            if let data = try? Data(contentsOf: url) {
                do {
                    let read = try Glazing(encoded: data, pieces: template.regions.count)
                    // Fewer glasses than the window's own is a damaged file: every piece's
                    // suggested glass must be one offered.
                    if read.offered.count >= template.palette.count {
                        glazing = read
                    } else {
                        Log.library.error("Glazing of window \(artwork.id.uuidString, privacy: .public) offers too few glasses: starting it unglazed")
                    }
                } catch Glazing.CodingError.newerVersion(let version) {
                    throw Glazing.CodingError.newerVersion(version)
                } catch {
                    Log.library.error("Unreadable glazing of window \(artwork.id.uuidString, privacy: .public): starting it unglazed")
                }
            }
            let photo = store.source(artwork.id, maxPixelSize: max(template.width, template.height))
            return Opened(template: template, glazing: glazing, offered: glazing.offered, texture: GlassTexture(template: template),
                          photo: photo)
        }
    }

    /// Writes a window's glazing, its picture on the shelf and its meta (the pieces glazed), after
    /// the window's saves before it, so an older glazing never lands over a newer one.
    func save(_ glazing: Glazing, of id: UUID, template: Template, offered: [PaletteColor], texture: GlassTexture,
              mode: GlassMode? = nil) async {
        await enqueue(glazing, of: id, template: template, offered: offered, texture: texture, mode: mode).value
    }

    /// `save`, queued now and run in its turn: a caller that can't wait still has its saves
    /// written in the order it made them.
    @discardableResult
    func enqueue(_ glazing: Glazing, of id: UUID, template: Template, offered: [PaletteColor], texture: GlassTexture,
                 mode: GlassMode? = nil) -> Task<Void, Never> {
        let previous = saving[id]
        let task = Task {
            await previous?.value
            await write(glazing, of: id, template: template, offered: offered, texture: texture, mode: mode)
        }
        saving[id] = task
        return task
    }

    private func write(_ glazing: Glazing, of id: UUID, template: Template, offered: [PaletteColor], texture: GlassTexture,
                       mode: GlassMode?) async {
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
                // Without the screen's mode, the window's photo makes one.
                let photo = mode == nil ? store.source(id, maxPixelSize: max(template.width, template.height)) : nil
                if let png = Self.picture(of: template, glazing: glazing, offered: offered, texture: texture, photo: photo, mode: mode)
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

    /// A window's card on the shelf, drawn as the canvas draws it (`mode`, or one made with
    /// `photo`), or by `GlassPicture` where the device has no Metal.
    nonisolated static func picture(of template: Template, glazing: Glazing, offered: [PaletteColor], texture: GlassTexture,
                                    photo: CGImage?, mode: GlassMode?) -> CGImage? {
        let longSide = ArtworkStore.thumbnailMaxPixelSize
        if let mode = mode ?? RenderContext.shared.flatMap({
            GlassMode(template: template, texture: texture, offered: offered, photo: photo, context: $0)
        }), let image = GlassGlazeModel.picture(template: template, glazing: glazing, offered: offered.count, mode: mode,
                                                 longSide: longSide) {
            return image
        }
        return GlassPicture.image(of: template, glazing: glazing, offered: offered, texture: texture, longSide: longSide)
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

    /// A new window's name: "Window, November 20", and "Window 2, November 20" for the day's
    /// second, so no two windows on the shelf share one.
    func title(on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        let taken = Set(windows.map(\.title))
        let first = String(localized: "glass.windowTitle", defaultValue: "Window, \(day)",
                           comment: "Name of a new stained glass window: the word Window and the day it was made, e.g. “Window, November 20”")
        guard taken.contains(first) else { return first }
        for n in 2... {
            let title = String(localized: "glass.windowTitleNumbered", defaultValue: "Window \(n), \(day)",
                               comment: "Name of a stained glass window made on a day that already has one: the word Window, its number that day and the day, e.g. “Window 2, November 20”")
            if !taken.contains(title) { return title }
        }
        return first
    }
}
#endif
