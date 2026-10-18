import CoreGraphics
import Foundation
import ImageIO
import PaintCore
import os

/// A new painting the painter refined and didn't start: what the create flow needs to pick up
/// where it was left (`Drafts` keeps one on disk, `CreateModel.load(draft:photo:)` resumes it).
/// The template is not kept: it is generated again from the photo, the settings and the
/// refinements' generator inputs, and the painter's edits (`TemplateRefinements.edits`) are laid
/// on it again, in order, as Refine laid them.
nonisolated struct CreateDraft: Equatable, Codable, Sendable {
    /// Names the photo, so a draft replaces its own earlier saves and the stored photo is
    /// encoded once (`DraftStore.write`).
    var photoID: UUID
    /// As typed; empty means `defaultTitle`.
    var title: String
    /// The sample's name, or the date the photo was chosen.
    var defaultTitle: String
    /// The sliders' settings, as an artwork's `meta.json` records them.
    var settings: GenerationSettings
    /// The Lines slider, which `settings.lineArt` doesn't say how to put back.
    var lines: Double
    var sampleName: String?
    /// Kept beside the draft the way an artwork keeps its own (`refinements.json`).
    var refinements = TemplateRefinements()

    var resolvedTitle: String { Self.resolvedTitle(typed: title, default: defaultTitle) }

    /// The trimmed `typed` title, or `fallback` when it is empty.
    static func resolvedTitle(typed: String, default fallback: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case photoID, title, defaultTitle, settings, lines, sampleName
    }
}

/// File layout and IO of the create flow's draft. Synchronous and file-only like `ArtworkStore`,
/// so callers choose where it runs (`Drafts` keeps it off the main actor).
///
///     <root>/Current/draft.json        `CreateDraft` without its refinements
///                    refinements.json  `TemplateRefinements`
///                    source.jpg        the photo (≤ 2048 px), as the create flow holds it
///     <root>/.staging/  a draft is assembled here and swapped into place atomically
///
/// There is one draft: writing another replaces it. Nothing here creates a folder until
/// something is written.
nonisolated struct DraftStore: Sendable {
    nonisolated enum File: String, CaseIterable {
        case draft = "draft.json"
        case refinements = "refinements.json"
        case source = "source.jpg"
    }

    enum StoreError: Error, Equatable {
        /// The photo is not in the folder to keep, or not at all.
        case missingPhoto
        /// The photo is there but doesn't decode.
        case undecodablePhoto
        case encodingFailed
    }

    let root: URL

    private var fm: FileManager { .default }
    private var folder: URL { root.appending(path: "Current", directoryHint: .isDirectory) }
    private var staging: URL { root.appending(path: ".staging", directoryHint: .isDirectory) }

    func url(_ file: File) -> URL { folder.appending(path: file.rawValue) }

    /// The draft on disk, nil when there is none. Throws for one that is damaged: its files
    /// missing or unreadable.
    func read() throws -> CreateDraft? {
        guard fm.fileExists(atPath: folder.path) else { return nil }
        let decoder = JSONDecoder()
        var draft = try decoder.decode(CreateDraft.self, from: Data(contentsOf: url(.draft)))
        draft.refinements = try decoder.decode(TemplateRefinements.self, from: Data(contentsOf: url(.refinements)))
        guard fm.fileExists(atPath: url(.source).path) else { throw StoreError.missingPhoto }
        return draft
    }

    /// The photo's bytes, checked to decode. A photo that can't be read just now (an I/O or data
    /// protection error) throws that error: it says nothing about the draft.
    func photoData() throws -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url(.source))
        } catch let error as CocoaError where !Library.isDamage(error) {
            throw error
        } catch {
            throw StoreError.missingPhoto
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              ImageCodec.image(from: source, maxPixelSize: 32) != nil
        else { throw StoreError.undecodablePhoto }
        return data
    }

    /// Replaces the draft with `draft` and `photo` (encoded as an artwork's `source.jpg` is); a
    /// nil `photo` keeps the one already stored.
    func write(_ draft: CreateDraft, photo: CGImage?) throws {
        let assembly = staging.appending(path: "Current", directoryHint: .isDirectory)
        try? fm.removeItem(at: assembly)
        try fm.createDirectory(at: assembly, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            try encoder.encode(draft).write(to: assembly.appending(path: File.draft.rawValue), options: .atomic)
            try encoder.encode(draft.refinements).write(to: assembly.appending(path: File.refinements.rawValue), options: .atomic)
            let stored = assembly.appending(path: File.source.rawValue)
            if let photo {
                guard let jpeg = ImageCodec.jpegData(
                    ImageCodec.downscaled(photo, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
                else { throw StoreError.encodingFailed }
                try jpeg.write(to: stored, options: .atomic)
            } else {
                guard fm.fileExists(atPath: url(.source).path) else { throw StoreError.missingPhoto }
                try fm.copyItem(at: url(.source), to: stored)
            }
            if fm.fileExists(atPath: folder.path) {
                _ = try fm.replaceItemAt(folder, withItemAt: assembly)
            } else {
                try fm.moveItem(at: assembly, to: folder)
            }
        } catch {
            try? fm.removeItem(at: assembly)
            throw error
        }
    }

    func remove() {
        guard fm.fileExists(atPath: folder.path) else { return }
        do {
            try fm.removeItem(at: folder)
        } catch {
            Log.create.error("Removing the draft failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Removes the leftovers of a write interrupted by a crash.
    func purgeStaging() {
        try? fm.removeItem(at: staging)
    }
}
