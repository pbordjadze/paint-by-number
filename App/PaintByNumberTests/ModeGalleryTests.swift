#if UNRELEASED
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The frame's gallery (painting-company row 379): a mode's card menu renames a painting on its
/// shelf, at once and on disk, after the saves before it, and the painting is listed in the
/// section its state puts it in.
@MainActor
struct ModeGalleryTests {
    private static func root(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    @Test func aRenamedPrintKeepsItsName() async throws {
        let root = Self.root("ModeGalleryWoodblock")
        defer { try? FileManager.default.removeItem(at: root) }
        let template = SyntheticTemplate.make()
        let shelf = WoodblockShelf(root: root)
        await shelf.load()
        let photo = RGBAImage(width: template.width, height: template.height, fill: SIMD4(200, 120, 40, 255))
        let artwork = try await shelf.create(template: template, settings: GenerationSettings(), photo: photo,
                                             title: "Print, November 23", sampleName: nil)
        shelf.rename(artwork.id, to: "Fuji at Dawn")
        #expect(shelf.print(artwork.id)?.title == "Fuji at Dawn")
        #expect(shelf.print(artwork.id)?.shelfItem.isComplete == false)
        let store = shelf.store
        try await waitUntil { (try? store.readMeta(artwork.id))?.title == "Fuji at Dawn" }
        let again = WoodblockShelf(root: root)
        await again.load()
        #expect(again.print(artwork.id)?.title == "Fuji at Dawn")
    }

    @Test func aRenamedWatercolorKeepsItsName() async throws {
        let root = Self.root("ModeGalleryWatercolor")
        defer { try? FileManager.default.removeItem(at: root) }
        let template = SyntheticTemplate.make()
        let shelf = WatercolorShelf(root: root)
        await shelf.load()
        let photo = RGBAImage(width: template.width, height: template.height, fill: SIMD4(90, 140, 200, 255))
        let artwork = try await shelf.create(template: template, settings: GenerationSettings(), photo: photo,
                                             title: "Watercolor", sampleName: nil)
        shelf.rename(artwork.id, to: "The Harbour")
        #expect(shelf.painting(artwork.id)?.title == "The Harbour")
        let store = shelf.store
        try await waitUntil { (try? store.readMeta(artwork.id))?.title == "The Harbour" }
        let again = WatercolorShelf(root: root)
        await again.load()
        #expect(again.painting(artwork.id)?.title == "The Harbour")
    }
}
#endif
