import CoreGraphics
import Foundation
import PaintCore
import Testing
import UIKit
@testable import PaintByNumber

@MainActor
struct ImageCacheTests {
    private func image(_ side: Int) throws -> CGImage {
        let ctx = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try #require(ctx.makeImage())
    }

    @Test func evictsLeastRecentlyUsedByCost() throws {
        let unit = try image(100)
        let cache = ImageCache<Int>(costLimit: 3 * ImageCache<Int>.cost(of: unit))
        for key in 1...3 { cache.insert(try image(100), for: key) }
        #expect(cache.image(for: 1) != nil)
        cache.insert(try image(100), for: 4)
        #expect(cache.image(for: 2) == nil)
        for key in [1, 3, 4] { #expect(cache.image(for: key) != nil, "\(key)") }
        #expect(cache.totalCost == cache.costLimit)

        // Replacing a key doesn't count it twice.
        cache.insert(try image(100), for: 4)
        #expect(cache.totalCost == cache.costLimit)
        #expect(cache.image(for: 1) != nil && cache.image(for: 3) != nil)

        // Larger than the whole budget: not kept, and nothing else is evicted for it.
        cache.insert(try image(200), for: 5)
        #expect(cache.image(for: 5) == nil)
        #expect(cache.totalCost == cache.costLimit)
    }

    @Test func memoryWarningEmptiesTheCache() async throws {
        let cache = ImageCache<Int>(costLimit: 1 << 20)
        cache.insert(try image(50), for: 1)
        #expect(cache.totalCost > 0)
        // Posted from another thread, as the system may: the cache still empties on the main actor.
        let warning = UIApplication.didReceiveMemoryWarningNotification
        await Task.detached { NotificationCenter.default.post(name: warning, object: nil) }.value
        let deadline = ContinuousClock.now + .seconds(1)
        while cache.totalCost > 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(cache.totalCost == 0)
        #expect(cache.image(for: 1) == nil)
    }

    @Test func thumbnailPixelSizeBuckets() {
        let tile = CGSize(width: 300, height: 300)
        // Filling a square with a 3:2 image shows its long side at 450 pt: 900 px, one bucket up.
        #expect(ThumbnailCache.pixelSize(frame: tile, displayScale: 2, aspectRatio: 1.5, fills: true) == 1024)
        // Fitting shows it at 300 pt: 600 px.
        #expect(ThumbnailCache.pixelSize(frame: tile, displayScale: 2, aspectRatio: 1.5, fills: false) == 640)
        #expect(ThumbnailCache.pixelSize(frame: CGSize(width: 20, height: 20), displayScale: 3, aspectRatio: 1, fills: true) == 128)
        #expect(ThumbnailCache.pixelSize(frame: CGSize(width: 4000, height: 4000), displayScale: 2, aspectRatio: 1, fills: true)
            == ArtworkStore.thumbnailMaxPixelSize)
        #expect(ThumbnailCache.pixelSize(frame: .zero, displayScale: 2, aspectRatio: 1, fills: true) == 0)
        // Small layout changes don't decode again.
        #expect(ThumbnailCache.pixelSize(frame: CGSize(width: 303, height: 303), displayScale: 2, aspectRatio: 1.5, fills: false) == 640)
    }

    @Test func thumbnailsDecodeAtTheTileSize() async throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(store: ArtworkStore(root: root))
        let template = try Fixtures.sample()
        let artwork = try await library.create(ArtworkDraft(
            title: "Parrots", template: template, settings: GenerationSettings(colorCount: 12),
            photo: nil, sampleName: nil, progress: nil))
        await library.flush()

        let cache = ThumbnailCache()
        let tile = try #require(await cache.load(artwork, maxPixelSize: 256, from: library.store))
        #expect(max(tile.width, tile.height) <= 256)
        #expect(cache.cached(artwork, maxPixelSize: 256) === tile)
        #expect(cache.bestCached(artwork) === tile)
        #expect(cache.cached(artwork, maxPixelSize: 512) == nil)
    }
}
