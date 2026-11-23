#if UNRELEASED
import Foundation
import ImageIO
import UIKit

/// The Museum's pictures, fetched from the museums' servers: tiles at their own pixel size, a
/// work's large picture, and the full image a painting is made from. Fetches go through a URL
/// cache of their own on disk (`Caches/Museum/Images`), so a tile scrolled past and back, or a
/// work opened again, comes from the device; decoded tiles are kept in memory by `ImageCache`.
final class MuseumImages {
    static let shared = MuseumImages()

    private let session: URLSession
    private let tiles = ImageCache<String>(costLimit: 96 * 1024 * 1024)

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(path: "Museum/Images"))
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 45
        session = URLSession(configuration: configuration)
    }

    /// A picture from `url` decoded at most `maxPixelSize` on its long side; nil when it can't be
    /// fetched or decoded, or the task was cancelled (a tile scrolled away).
    func picture(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = "\(url.absoluteString)@\(maxPixelSize)"
        if let cached = tiles.image(for: key) { return cached }
        guard let data = try? await data(url) else { return nil }
        guard !Task.isCancelled, let image = await Background.run({ ImageCodec.image(data: data, maxPixelSize: maxPixelSize) }) else {
            return nil
        }
        tiles.insert(image, for: key)
        return image
    }

    /// The bytes at `url`, as the server sent them (the full image, for a painting).
    func data(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
#endif
