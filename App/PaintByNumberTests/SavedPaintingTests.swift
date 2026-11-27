import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// A painting exactly as 1.5 left it on disk (`Saved15-*`, frozen: `tools/fixtures/saved_painting.py`
/// says how its files were made and must never be run over them) opens in this build with its
/// painted areas, time, paint in hand, settings and refinements, paints on and saves, and opens
/// in ✎ Change. Every update must keep this passing: a painting is never lost to one.
@MainActor
struct SavedPaintingTests {
    let root = Fixtures.temporaryDirectory()
    static let id = UUID(uuidString: "5A1E0015-0000-4000-8000-0000000000B5")!
    static let painted = [0, 2, 3, 5, 8, 13]

    /// The fixture laid in a library's folder, as the painter's iPad holds it.
    private func library() throws -> Library {
        let folder = root.appending(path: Self.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (file, ext) in [("meta", "json"), ("template", "pbnt"), ("progress", "bin"), ("refinements", "json"), ("source", "jpg"), ("thumbnail", "png")] {
            let fixture = try #require(
                Bundle(for: Marker.self).url(forResource: "Saved15-\(file)", withExtension: ext),
                "Saved15-\(file).\(ext) isn't in the test bundle")
            try FileManager.default.copyItem(at: fixture, to: folder.appending(path: "\(file).\(ext)"))
        }
        return Library(store: ArtworkStore(root: root))
    }

    @Test func aPaintingSavedBy15OpensWithItsProgress() async throws {
        let library = try library()
        let artwork = try #require(library.artwork(with: Self.id))
        #expect(artwork.title == "Saved by 1.5")
        #expect(!artwork.needsNewerApp)
        #expect(artwork.isFavorite)
        #expect(artwork.paintedCount == Self.painted.count)
        #expect(artwork.settings.lineArt.style == .coloringBook)

        let document = try await library.loadForPainting(Self.id)
        #expect(document.notice == nil)
        #expect(document.template.regions.count == artwork.regionCount)
        #expect(document.progress.paintedCount == Self.painted.count)
        for region in Self.painted { #expect(document.progress.isPainted(region)) }
        #expect(document.progress.activeSeconds == 321.5)
        #expect(document.progress.inHand == 2)
        #expect(document.hasPhoto)
    }

    @Test func aPaintingSavedBy15PaintsOnAndSaves() async throws {
        let library = try library()
        var progress = try await library.loadForPainting(Self.id).progress
        let next = try #require((0..<progress.regionCount).first { !progress.isPainted($0) })
        progress.paint(next)
        library.saveProgress(progress, for: Self.id)
        await library.flush()

        let reopened = try await Library(store: ArtworkStore(root: root)).loadForPainting(Self.id)
        #expect(reopened.progress.paintedCount == Self.painted.count + 1)
        #expect(reopened.progress.isPainted(next))
        for region in Self.painted { #expect(reopened.progress.isPainted(region)) }
    }

    @Test func aPaintingSavedBy15OpensInChange() async throws {
        let library = try library()
        let inputs = try await library.changeInputs(for: Self.id)
        #expect(!inputs.photo.isEmpty)
        #expect(inputs.refinements.edits.count == 1)
        #expect(inputs.refinements.editorVersion == 7)
        #expect(inputs.unsaved == nil)
    }
}

private final class Marker {}
