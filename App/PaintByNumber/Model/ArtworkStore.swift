import Compression
import CoreGraphics
import Foundation
import PaintCore
import Synchronization
import os

/// File layout and IO of the artwork library. Every method is synchronous and touches
/// only the file system, so callers choose where it runs (`Library` keeps it off the
/// main actor).
///
///     <root>/<uuid>/meta.json      `Artwork`, written last: a folder without valid meta is ignored
///                   template.pbnt  `Template.encoded()`, LZFSE-compressed
///                   progress.bin   `PaintProgress.encoded()`
///                   source.jpg     the photo (≤ 2048 px) for the photo peek and regeneration
///                   thumbnail.png  the current state of the painting
///                   refinements.json  `TemplateRefinements`, only for a painting refined before
///                                  painting, read again to regenerate it
///                   change.json    ✎ Change's refinements not yet kept by Done, so iOS ending the
///                                  app loses no edit (`Library.keepChange`)
///     <root>/.staging/  new artworks are assembled here and moved into place atomically
///     <root>/.trash/    deleted artworks wait here while the deletion can still be undone
nonisolated struct ArtworkStore: Sendable {
    enum StoreError: Error, Equatable {
        case notFound, unreadable(String)
        /// The artwork was written by a newer app (`Artwork.needsNewerApp`); never rewrite it.
        case newerFormat
    }

    nonisolated enum File: String, CaseIterable {
        case meta = "meta.json"
        case template = "template.pbnt"
        case progress = "progress.bin"
        case source = "source.jpg"
        case thumbnail = "thumbnail.png"
        /// Written only for a refined painting.
        case refinements = "refinements.json"
        /// ✎ Change's unfinished edits, there only while its tools have edits Done hasn't kept.
        case change = "change.json"
    }

    static let sourceMaxPixelSize = 2048
    static let thumbnailMaxPixelSize = 1024
    /// Far above templates made at the app's working resolution; bounds decompression of
    /// damaged files before the template decoder can check their contents.
    static let maximumTemplateBytes = 256 * 1024 * 1024

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
    func hasSource(_ id: UUID) -> Bool { fm.fileExists(atPath: url(.source, of: id).path) }

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
        // Rewriting would drop whatever the newer app stored in fields this one doesn't know.
        guard !artwork.needsNewerApp else { throw StoreError.newerFormat }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artwork).write(to: dir.appending(path: File.meta.rawValue), options: .atomic)
    }

    // MARK: Template

    func readTemplate(_ id: UUID, maximumBytes: Int = Self.maximumTemplateBytes) throws -> Template {
        let compressed = try Data(contentsOf: url(.template, of: id), options: .mappedIfSafe)
        return try Template(encoded: Self.lzfseDecoded(compressed, maximumBytes: maximumBytes))
    }

    /// `compressed` decoded from LZFSE, at most `maximumBytes` of it: the buffer grows only as the
    /// stream fills it, so a damaged or hostile stream reserves no more than it decodes to.
    static func lzfseDecoded(_ compressed: Data, maximumBytes: Int) throws -> Data {
        guard !compressed.isEmpty, maximumBytes > 0, maximumBytes <= Self.maximumTemplateBytes else {
            throw StoreError.unreadable("template decompression")
        }
        // One extra byte distinguishes a file exactly at the limit from an oversized one.
        var capacity = min(64 * 1024, maximumBytes + 1)
        while true {
            var raw = Data(count: capacity)
            let count = raw.withUnsafeMutableBytes { destination in
                compressed.withUnsafeBytes { source in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                        nil, COMPRESSION_LZFSE)
                }
            }
            guard count > 0, count <= maximumBytes else {
                throw StoreError.unreadable("template decompression")
            }
            if count < capacity {
                raw.count = count
                return raw
            }
            capacity = min(capacity * 2, maximumBytes + 1)
        }
    }

    private func writeTemplate(_ template: Template, in dir: URL) throws {
        let compressed = try (template.encoded() as NSData).compressed(using: .lzfse) as Data
        try compressed.write(to: dir.appending(path: File.template.rawValue), options: .atomic)
    }

    // MARK: Progress

    /// Progress as read from disk, or fresh progress and why the saved one couldn't be used.
    struct SavedProgress: Sendable {
        enum Problem: Sendable, Equatable { case missing, damaged, mismatched }

        var progress: PaintProgress
        var problem: Problem?
    }

    /// The saved progress, or a fresh one (with the `problem`) if the file is missing, damaged
    /// or belongs to a different template. Throws for progress written by a newer app
    /// (`PaintProgress.CodingError.newerVersion`) and for a file that exists but can't be read
    /// right now: both must be kept, not replaced with fresh progress.
    func readProgress(_ id: UUID, regionCount: Int) throws -> SavedProgress {
        let fresh = PaintProgress(regionCount: regionCount)
        let data: Data
        do {
            data = try Data(contentsOf: url(.progress, of: id))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return SavedProgress(progress: fresh, problem: .missing)
        }
        func mismatched(_ count: Int) -> SavedProgress {
            Log.library.error("Discarding progress of \(id.uuidString, privacy: .public): \(count) regions, template has \(regionCount)")
            return SavedProgress(progress: fresh, problem: .mismatched)
        }
        let progress: PaintProgress
        do {
            progress = try PaintProgress(encoded: data, maxRegionCount: max(regionCount, 0))
        } catch PaintProgress.CodingError.newerVersion(let version) {
            throw PaintProgress.CodingError.newerVersion(version)
        } catch PaintProgress.CodingError.tooManyRegions(let count) {
            return mismatched(count)
        } catch {
            Log.library.error("Discarding unreadable progress of \(id.uuidString, privacy: .public)")
            return SavedProgress(progress: fresh, problem: .damaged)
        }
        guard progress.regionCount == regionCount else { return mismatched(progress.regionCount) }
        return SavedProgress(progress: progress)
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

    /// Whether the progress on disk was written after the thumbnail (by more than `slack`, as
    /// a folder written whole may write them in either order). Closing a painting writes both;
    /// one the app ended in (a crash) saved its progress and never the thumbnail.
    func thumbnailIsBehindProgress(_ id: UUID, slack: TimeInterval = 2) -> Bool {
        func modified(_ file: File) -> Date? {
            try? url(file, of: id).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let progress = modified(.progress) else { return false }
        guard let thumbnail = modified(.thumbnail) else { return true }
        return progress.timeIntervalSince(thumbnail) > slack
    }

    func thumbnail(_ id: UUID, maxPixelSize: Int? = nil) -> CGImage? {
        ImageCodec.image(at: url(.thumbnail, of: id), maxPixelSize: maxPixelSize)
    }

    func source(_ id: UUID, maxPixelSize: Int? = nil) -> CGImage? {
        ImageCodec.image(at: url(.source, of: id), maxPixelSize: maxPixelSize)
    }

    // MARK: Refinements

    /// The painting's refinements; none when it has no file, or one this app can't read (they
    /// only shape a regeneration, which then makes the painting as first suggested). A file that
    /// can't be read just now (an I/O or data protection error) throws: regenerating without it
    /// would lose the painter's edits.
    func readRefinements(_ id: UUID) throws -> TemplateRefinements {
        let data: Data
        do {
            data = try Data(contentsOf: url(.refinements, of: id))
        } catch let error as CocoaError where !Library.isDamage(error) {
            throw error
        } catch {
            return TemplateRefinements()
        }
        return (try? JSONDecoder().decode(TemplateRefinements.self, from: data)) ?? TemplateRefinements()
    }

    /// ✎ Change's refinements its tools left without Done or Cancel (iOS ended the app), or nil.
    /// A `change.json` that can't be read gives the newest of the vault's saves that can, made
    /// since edits were last let go (the same edits a second or so earlier); none of either, the
    /// painting's own refinements open.
    func readChange(_ id: UUID) -> TemplateRefinements? {
        guard let data = try? Data(contentsOf: url(.change, of: id)) else { return nil }
        if let refinements = try? JSONDecoder().decode(TemplateRefinements.self, from: data) { return refinements }
        // Only this ✎ Change's saves: those older than the last edits let go were made on
        // another template, or were let go themselves.
        let lastLetGo = vaulted(id, kind: Vault.letGo).last.map(Vault.stamp(of:)) ?? ""
        for save in vaulted(id, kind: Vault.save).reversed() where Vault.stamp(of: save) > lastLetGo {
            if let data = try? Data(contentsOf: save),
               let refinements = try? JSONDecoder().decode(TemplateRefinements.self, from: data) {
                Breadcrumbs.trace("change \(id.uuidString) unreadable, from the vault's \(save.lastPathComponent)")
                return refinements
            }
        }
        return nil
    }

    /// Keeps ✎ Change's refinements as they stand, with a copy among the vault's last saves; nil
    /// lets them go into the vault, never deleting them.
    func writeChange(_ refinements: TemplateRefinements?, of id: UUID) throws {
        guard exists(id) else { return }
        guard let refinements else {
            do {
                try setAsideChange(of: id)
            } catch {
                // Kept where it was rather than lost: the next ✎ Change opens on it again.
                Breadcrumbs.trace("change \(id.uuidString) set aside failed: \(error)")
            }
            return
        }
        let data = try JSONEncoder().encode(refinements)
        try data.write(to: url(.change, of: id), options: .atomic)
        let vault = directory(for: id).appending(path: Vault.folder, directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: vault, withIntermediateDirectories: true)
            try data.write(to: vault.appending(path: Vault.name(Vault.save, in: vault)), options: .atomic)
            prune(vault, kind: Vault.save)
        } catch {
            Breadcrumbs.trace("vault save failed \(id.uuidString): \(error)")
        }
    }

    /// The vault (`<id>/vault/`): copies of ✎ Change's edits, so no save, mistaken Cancel, failed
    /// reopen or remade painting loses them for good. `save-…` are its last saves, newest last;
    /// `letgo-…` the edits as they stood when Cancel, Done or a new template let them go. Only
    /// the newest of each are kept; the painting's remakes carry the folder over.
    nonisolated enum Vault {
        static let folder = "vault"
        static let save = "save"
        static let letGo = "letgo"
        static let keeps = [save: 8, letGo: 12]

        /// A name sorting after every file in `vault`, of either kind: the time in milliseconds
        /// since 1970, zero-padded, or a millisecond past the newest there when the clock is
        /// behind it (set back), so the newest is always the last written.
        static func name(_ kind: String, in vault: URL) -> String {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: vault.path)) ?? []
            let newest = names.compactMap { name -> Int64? in
                guard name.hasSuffix(".json"), let dash = name.lastIndex(of: "-") else { return nil }
                return Int64(name[name.index(after: dash)...].dropLast(5))
            }.max() ?? 0
            let ms = max(Int64(Date.now.timeIntervalSince1970 * 1000), newest + 1)
            return kind + "-" + String(format: "%015lld", ms) + ".json"
        }

        /// The time a vault file's name holds, which orders saves and let-go edits together.
        static func stamp(of file: URL) -> String {
            String(file.lastPathComponent.split(separator: "-").last ?? "")
        }
    }

    /// The vault's files of one kind, oldest first (their names sort by time).
    func vaulted(_ id: UUID, kind: String) -> [URL] {
        vaulted(in: directory(for: id).appending(path: Vault.folder, directoryHint: .isDirectory), kind: kind)
    }

    private func vaulted(in vault: URL, kind: String) -> [URL] {
        ((try? fm.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(kind + "-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func prune(_ vault: URL, kind: String) {
        let files = vaulted(in: vault, kind: kind)
        for old in files.dropLast(Vault.keeps[kind] ?? 8) { try? fm.removeItem(at: old) }
    }

    /// Moves the painting's `change.json`, if any, into its vault as edits let go, or copies it
    /// into the vault of `staging`, the painting's folder being remade, which a failed copy
    /// stops: the folder stays as it was rather than lose them.
    private func setAsideChange(of id: UUID, copyingInto staging: URL? = nil) throws {
        let change = url(.change, of: id)
        guard fm.fileExists(atPath: change.path) else { return }
        let vault = (staging ?? directory(for: id)).appending(path: Vault.folder, directoryHint: .isDirectory)
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)
        let name = Vault.name(Vault.letGo, in: vault)
        if staging == nil {
            try fm.moveItem(at: change, to: vault.appending(path: name))
        } else {
            try fm.copyItem(at: change, to: vault.appending(path: name))
        }
        prune(vault, kind: Vault.letGo)
        Breadcrumbs.trace("change \(id.uuidString) set aside in the vault as \(name)")
    }

    // MARK: Lifecycle

    /// Writes a complete artwork into staging, then moves it into place, so a crash never
    /// leaves a half-written artwork in the library.
    func create(
        _ artwork: Artwork, template: Template, progress: PaintProgress, sourceJPEG: Data?, thumbnailPNG: Data?,
        refinements: TemplateRefinements = TemplateRefinements()
    ) throws {
        let staging = stagingRoot.appending(path: artwork.id.uuidString, directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try writeTemplate(template, in: staging)
            try progress.encoded().write(to: staging.appending(path: File.progress.rawValue), options: .atomic)
            try sourceJPEG?.write(to: staging.appending(path: File.source.rawValue), options: .atomic)
            try thumbnailPNG?.write(to: staging.appending(path: File.thumbnail.rawValue), options: .atomic)
            if !refinements.isEmpty {
                try JSONEncoder().encode(refinements).write(to: staging.appending(path: File.refinements.rawValue), options: .atomic)
            }
            try writeMeta(artwork, in: staging)
            try fm.moveItem(at: staging, to: directory(for: artwork.id))
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Swaps in a regenerated template with its progress, thumbnail and metadata as one step:
    /// the new folder is assembled in staging (keeping the photo and any file this version
    /// doesn't know) and replaces the old one atomically, so a crash leaves either version.
    /// A nil `thumbnailPNG` keeps the current thumbnail, and nil `refinements` the current ones
    /// (the painting's ✎ Change gives its new ones: none, written as no file).
    func replaceContents(
        of artwork: Artwork, template: Template, progress: PaintProgress, thumbnailPNG: Data?,
        refinements: TemplateRefinements? = nil
    ) throws {
        let id = artwork.id
        let staging = stagingRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            // ✎ Change's unsaved edits were made on the template being replaced: they go with it…
            var rewritten = Set([File.meta, .template, .progress, .thumbnail, .change].map(\.rawValue))
            if refinements != nil { rewritten.insert(File.refinements.rawValue) }
            for item in try fm.contentsOfDirectory(at: directory(for: id), includingPropertiesForKeys: nil)
            where !rewritten.contains(item.lastPathComponent) {
                try fm.copyItem(at: item, to: staging.appending(path: item.lastPathComponent))
            }
            // …into the vault, which the loop carried over, never lost.
            try setAsideChange(of: id, copyingInto: staging)
            try writeTemplate(template, in: staging)
            try progress.encoded().write(to: staging.appending(path: File.progress.rawValue), options: .atomic)
            let thumbnail = staging.appending(path: File.thumbnail.rawValue)
            if let thumbnailPNG {
                try thumbnailPNG.write(to: thumbnail, options: .atomic)
            } else if fm.fileExists(atPath: url(.thumbnail, of: id).path) {
                try fm.copyItem(at: url(.thumbnail, of: id), to: thumbnail)
            }
            if let refinements, !refinements.isEmpty {
                try JSONEncoder().encode(refinements).write(to: staging.appending(path: File.refinements.rawValue), options: .atomic)
            }
            try writeMeta(artwork, in: staging)
            _ = try fm.replaceItemAt(directory(for: id), withItemAt: staging)
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
