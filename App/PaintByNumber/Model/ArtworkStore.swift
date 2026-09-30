import CoreGraphics
import Foundation
import PaintCore
import Synchronization
import os

nonisolated enum Log {
    static let library = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "library")
    static let create = Logger(subsystem: "com.pbordjadze.paintbynumber", category: "create")
}

/// File layout and IO of the artwork library. Every method is synchronous and touches
/// only the file system, so callers choose where it runs (`Library` keeps it off the
/// main actor).
///
///     <root>/<uuid>/meta.json      `Artwork`, written last: a folder without valid meta is ignored
///                   template.pbnt  `Template.encoded()`, LZFSE-compressed
///                   progress.bin   `PaintProgress.encoded()`
///                   source.jpg     the photo (≤ 2048 px) for "compare with photo" and regeneration
///                   thumbnail.png  the current state of the painting
///     <root>/.staging/  new artworks are assembled here and moved into place atomically
///     <root>/.trash/    deleted artworks wait here while the deletion can still be undone
nonisolated struct ArtworkStore: Sendable {
    enum StoreError: Error { case notFound, unreadable(String) }

    nonisolated enum File: String, CaseIterable {
        case meta = "meta.json"
        case template = "template.pbnt"
        case progress = "progress.bin"
        case source = "source.jpg"
        case thumbnail = "thumbnail.png"
    }

    static let sourceMaxPixelSize = 2048
    static let thumbnailMaxPixelSize = 1024

    let root: URL
    /// Failures to inject into in-place writes; only tests set it.
    let writeFaults: WriteFaults?

    init(root: URL, writeFaults: WriteFaults? = nil) {
        self.root = root
        self.writeFaults = writeFaults
        for dir in [root, root.appending(path: ".staging"), root.appending(path: ".trash")] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Artworks", directoryHint: .isDirectory)
    }

    private var fm: FileManager { .default }
    private var stagingRoot: URL { root.appending(path: ".staging", directoryHint: .isDirectory) }
    private var trashRoot: URL { root.appending(path: ".trash", directoryHint: .isDirectory) }

    func directory(for id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }
    func url(_ file: File, of id: UUID) -> URL { directory(for: id).appending(path: file.rawValue) }
    func exists(_ id: UUID) -> Bool { fm.fileExists(atPath: url(.meta, of: id).path) }

    // MARK: Listing

    /// Metadata of every readable artwork. Damaged folders are skipped (and logged), never fatal.
    func loadAll() -> [Artwork] {
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { dir -> Artwork? in
            guard let id = UUID(uuidString: dir.lastPathComponent) else { return nil }
            do {
                var artwork = try readMeta(in: dir)
                artwork.id = id  // the folder name is authoritative
                return artwork
            } catch {
                Log.library.error("Skipping unreadable artwork \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    // MARK: Metadata

    func readMeta(_ id: UUID) throws -> Artwork { try readMeta(in: directory(for: id)) }

    private func readMeta(in dir: URL) throws -> Artwork {
        let data = try Data(contentsOf: dir.appending(path: File.meta.rawValue))
        return try JSONDecoder().decode(Artwork.self, from: data)
    }

    func writeMeta(_ artwork: Artwork) throws {
        try writeFaults?.check(.meta)
        guard fm.fileExists(atPath: directory(for: artwork.id).path) else { throw StoreError.notFound }
        try writeMeta(artwork, in: directory(for: artwork.id))
    }

    private func writeMeta(_ artwork: Artwork, in dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artwork).write(to: dir.appending(path: File.meta.rawValue), options: .atomic)
    }

    // MARK: Template

    func readTemplate(_ id: UUID) throws -> Template {
        let compressed = try Data(contentsOf: url(.template, of: id), options: .mappedIfSafe)
        let raw: Data
        do {
            raw = try (compressed as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw StoreError.unreadable("template decompression")
        }
        return try Template(encoded: raw)
    }

    private func writeTemplate(_ template: Template, in dir: URL) throws {
        let compressed = try (template.encoded() as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: dir.appending(path: File.template.rawValue), options: .atomic)
    }

    // MARK: Progress

    /// The saved progress, or a fresh one if the file is missing, damaged or doesn't match.
    func readProgress(_ id: UUID, regionCount: Int) -> PaintProgress {
        guard let data = try? Data(contentsOf: url(.progress, of: id)) else {
            return PaintProgress(regionCount: regionCount)
        }
        guard let progress = try? PaintProgress(encoded: data), progress.regionCount == regionCount else {
            Log.library.error("Discarding unreadable progress of \(id.uuidString, privacy: .public)")
            return PaintProgress(regionCount: regionCount)
        }
        return progress
    }

    func writeProgress(_ progress: PaintProgress, for id: UUID) throws {
        try writeFaults?.check(.progress)
        try progress.encoded().write(to: url(.progress, of: id), options: .atomic)
    }

    // MARK: Images

    func writeThumbnail(_ png: Data, for id: UUID) throws {
        try writeFaults?.check(.thumbnail)
        try png.write(to: url(.thumbnail, of: id), options: .atomic)
    }

    func thumbnail(_ id: UUID, maxPixelSize: Int? = nil) -> CGImage? {
        ImageCodec.image(at: url(.thumbnail, of: id), maxPixelSize: maxPixelSize)
    }

    func source(_ id: UUID, maxPixelSize: Int? = nil) -> CGImage? {
        ImageCodec.image(at: url(.source, of: id), maxPixelSize: maxPixelSize)
    }

    // MARK: Lifecycle

    /// Writes a complete artwork into staging, then moves it into place, so a crash never
    /// leaves a half-written artwork in the library.
    func create(_ artwork: Artwork, template: Template, progress: PaintProgress, sourceJPEG: Data?, thumbnailPNG: Data?) throws {
        let staging = stagingRoot.appending(path: artwork.id.uuidString, directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try writeTemplate(template, in: staging)
            try progress.encoded().write(to: staging.appending(path: File.progress.rawValue), options: .atomic)
            try sourceJPEG?.write(to: staging.appending(path: File.source.rawValue), options: .atomic)
            try thumbnailPNG?.write(to: staging.appending(path: File.thumbnail.rawValue), options: .atomic)
            try writeMeta(artwork, in: staging)
            try fm.moveItem(at: staging, to: directory(for: artwork.id))
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Copies an artwork's files under a new identity (`copy.id`).
    func duplicate(_ id: UUID, as copy: Artwork) throws {
        let staging = stagingRoot.appending(path: copy.id.uuidString, directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        do {
            try fm.copyItem(at: directory(for: id), to: staging)
            try writeMeta(copy, in: staging)
            try fm.moveItem(at: staging, to: directory(for: copy.id))
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    func moveToTrash(_ id: UUID) throws {
        let destination = trashRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: directory(for: id), to: destination)
    }

    func restoreFromTrash(_ id: UUID) throws {
        try fm.moveItem(at: trashRoot.appending(path: id.uuidString, directoryHint: .isDirectory), to: directory(for: id))
    }

    func isInTrash(_ id: UUID) -> Bool {
        fm.fileExists(atPath: trashRoot.appending(path: id.uuidString).path)
    }

    /// Permanently removes trashed artworks (one, or all).
    func purgeTrash(_ id: UUID? = nil) {
        if let id {
            try? fm.removeItem(at: trashRoot.appending(path: id.uuidString, directoryHint: .isDirectory))
            return
        }
        for url in (try? fm.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
    }

    /// Removes leftovers of creations interrupted by a crash.
    func purgeStaging() {
        for url in (try? fm.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
    }
}

/// Makes an `ArtworkStore`'s in-place writes of chosen files fail as a full disk would, so tests
/// can check how the library copes. Shared by reference: tests flip it while the library's
/// writes run on other threads.
nonisolated final class WriteFaults: Sendable {
    private let failing = Mutex<Set<ArtworkStore.File>>([])

    func fail(_ file: ArtworkStore.File) { failing.withLock { _ = $0.insert(file) } }
    func heal(_ file: ArtworkStore.File) { failing.withLock { _ = $0.remove(file) } }

    func check(_ file: ArtworkStore.File) throws {
        if failing.withLock({ $0.contains(file) }) { throw CocoaError(.fileWriteOutOfSpace) }
    }
}
