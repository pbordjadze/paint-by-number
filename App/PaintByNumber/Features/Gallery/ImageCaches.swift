import CoreGraphics
import Foundation

/// Decoded gallery thumbnails, keyed by artwork and thumbnail version.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [String: CGImage] = [:]
    private var order: [String] = []
    private let limit = 120

    static func key(_ artwork: Artwork) -> String { "\(artwork.id.uuidString)#\(artwork.thumbnailVersion)" }

    func cached(_ artwork: Artwork) -> CGImage? { images[Self.key(artwork)] }

    func load(_ artwork: Artwork, from store: ArtworkStore) async -> CGImage? {
        let key = Self.key(artwork)
        if let hit = images[key] { return hit }
        let id = artwork.id
        guard let image = await Background.run({ store.thumbnail(id) }) else { return nil }
        images[key] = image
        order.append(key)
        if order.count > limit { images[order.removeFirst()] = nil }
        return image
    }
}

/// Downscaled bundled sample photos for tiles and placeholders.
final class SampleImages {
    static let shared = SampleImages()

    private var images: [String: CGImage] = [:]

    func cached(_ sample: Sample, maxPixelSize: Int = 640) -> CGImage? { images["\(sample.id)@\(maxPixelSize)"] }

    func load(_ sample: Sample, maxPixelSize: Int = 640) async -> CGImage? {
        let key = "\(sample.id)@\(maxPixelSize)"
        if let hit = images[key] { return hit }
        guard let url = sample.url else { return nil }
        let image = await Background.run { ImageCodec.image(at: url, maxPixelSize: maxPixelSize) }
        images[key] = image
        return image
    }
}
