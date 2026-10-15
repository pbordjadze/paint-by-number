import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// The guardians' sheets that ship in the app (`Resources/pet-<id>.webp`): each loads through the
/// app's own loader with the v2 contract, and together they stay inside the budget in
/// `docs/marginarium-pets.md`. The Moon's drawing is withheld, so no sheet is named for it.
@MainActor
struct BundledPetsTests {
    private static let guardians = [
        "baba-yaga", "balanchine", "bible-school-teacher", "bulat-okudzhava", "child-at-bedtime",
        "dinotopia", "emily-dickinson", "enchanted-workshop", "glassblower", "hedge-witch", "medea", "nutcracker",
        "open-source-enthusiast", "originality", "painter", "pirosmani", "robber-girl", "scholar",
        "snow-queen", "storybook",
    ]

    private var sheets: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "webp", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("pet-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func opaquePixels(in image: CGImage) -> Int {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 0 }.count
    }

    @Test func everyGuardianHasASheetAndNothingElseShips() {
        let ids = sheets.map { String($0.deletingPathExtension().lastPathComponent.dropFirst("pet-".count)) }
        #expect(ids == Self.guardians)
        for id in Self.guardians {
            #expect(MarginariumPet.named(id) != nil, "\(id) must resolve")
        }
    }

    @Test func everySheetLoadsThroughTheAppsLoaderWithTheV2Contract() async throws {
        for url in sheets {
            let name = url.lastPathComponent
            let atlas = try #require(await Background.run { SpriteAtlas.load(at: url) }, "\(name) must be a 1536 × 2288 sheet")
            #expect(atlas.sheet.width == 1536 && atlas.sheet.height == 2288)
            let idle = try #require(atlas.image(at: .init(row: 0, column: 0)))
            let waving = try #require(atlas.image(at: .init(row: 3, column: 1)))
            #expect(opaquePixels(in: idle) > 2_000, "\(name)'s idle pose is empty")
            #expect(opaquePixels(in: waving) > 2_000, "\(name)'s waving pose is empty")
            // Unused cells stay transparent, so a lossy copy must not have smeared into them.
            let unused = try #require(atlas.sheet.cropping(to: CGRect(x: 7 * 192, y: 0, width: 192, height: 208)))
            #expect(opaquePixels(in: unused) == 0, "\(name)'s unused cell isn't transparent")
        }
    }

    /// What the contents page keeps of all twenty drawings on a 3x iPhone (72 pt asks for 234 px):
    /// each drawing's ten frames at the cell's own size, 1.5 MiB, in place of its 13.4 MiB sheet.
    @Test func theContentsPageKeepsEachDrawingsFramesAndNotItsSheet() async throws {
        let cache = SpriteAtlasCache()
        let sheetBytes = SpriteAtlas.width * SpriteAtlas.height * 4
        var kept = 0
        for url in sheets {
            let name = url.lastPathComponent
            let frames = try #require(await cache.frames(at: url, maxPixelSize: 234), "\(name) must give frames")
            #expect(frames.count == SpriteAtlas.playedCells.count)
            for image in frames.values {
                #expect(image.width <= 192 && image.height == 208, "\(name) is drawn at its cell's size")
            }
            let bytes = frames.values.reduce(0) { $0 + ImageCache<URL>.cost(of: $1) }
            #expect(bytes <= 2 << 20, "\(name)'s frames are over 2 MiB")
            kept += bytes
        }
        #expect(kept * 8 < sheets.count * sheetBytes, "A drawing's frames are under an eighth of its sheet")
        #expect(cache.decodedBytes <= SpriteAtlasCache.costLimit)
        #expect(!cache.isLoading)
    }

    @Test func theSheetsStayInsideTheSizeBudget() throws {
        var total = 0
        for url in sheets {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = try #require(attributes[.size] as? Int)
            #expect(size <= 1 << 20, "\(url.lastPathComponent) is over 1 MiB")
            total += size
        }
        #expect(total <= 20 << 20)
    }
}
