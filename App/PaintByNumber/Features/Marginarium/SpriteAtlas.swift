import CoreGraphics
import Foundation

/// The create-pet v2 contract: 192 × 208 cells, eight columns, eleven rows, top-left origin.
/// Rows 0–8 animate; rows 9–10 hold sixteen clockwise looks. Unused cells are never played.
/// A decoded sheet is 14 MiB: decode it through Background.run, take what a player shows
/// (`thumbnails`) and let it go; a damaged or non-v2 sheet yields no animation.
nonisolated struct SpriteAtlas: Sendable {
    static let width = 1536
    static let height = 2288
    static let frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]
    /// A cell's long side in pixels: no player shows more of a cell than it holds.
    static let cellLongSide = 208

    struct Cell: Hashable, Sendable {
        let row: Int
        let column: Int

        var rect: CGRect? {
            guard SpriteAtlas.frameCounts.indices.contains(row),
                  column >= 0, column < SpriteAtlas.frameCounts[row] else { return nil }
            return CGRect(x: column * 192, y: row * 208, width: 192, height: 208)
        }
    }

    let sheet: CGImage

    init?(sheet: CGImage) {
        guard sheet.width == Self.width, sheet.height == Self.height else { return nil }
        self.sheet = sheet
    }

    /// The cell's pixels as a crop, which shares the sheet's: it keeps all of the sheet alive.
    func image(at cell: Cell) -> CGImage? { cell.rect.flatMap { sheet.cropping(to: $0) } }

    /// Every cell `animation` plays, once each, in the order it first does.
    static let playedCells: [Cell] = {
        var seen: Set<Cell> = []
        let animation = SpriteAtlas.animation
        let frames = animation.idle + animation.action + [animation.reducedMotionAction]
        return frames.compactMap { frame in
            guard case .cell(let cell) = frame.source else { return nil }
            return seen.insert(cell).inserted ? cell : nil
        }
    }()

    /// The cells `animation` plays, each redrawn into a bitmap of its own with its long side at
    /// most `maxPixelSize` (a cell is never scaled up). A crop keeps its whole sheet alive, so
    /// only these copies let a player drop the 14 MiB behind them. Nil when any cell can't be
    /// drawn: an animation with a hole in it would stall.
    func thumbnails(maxPixelSize: Int) -> [Cell: CGImage]? {
        var result: [Cell: CGImage] = [:]
        for cell in Self.playedCells {
            guard let crop = image(at: cell), let copy = Self.standalone(crop, longSide: maxPixelSize) else { return nil }
            result[cell] = copy
        }
        return result
    }

    /// Premultiplied BGRA, the layout the render server takes without converting it.
    private static func standalone(_ crop: CGImage, longSide: Int) -> CGImage? {
        let scale = min(1, Double(max(1, longSide)) / Double(max(crop.width, crop.height)))
        let width = max(1, Int((Double(crop.width) * scale).rounded()))
        let height = max(1, Int((Double(crop.height) * scale).rounded()))
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        for space in [crop.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)] {
            guard let space, space.model == .rgb,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
            else { continue }
            context.interpolationQuality = .high
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        return nil
    }

    static func load(at url: URL) -> SpriteAtlas? {
        guard let sheet = ImageCodec.image(at: url) else { return nil }
        return SpriteAtlas(sheet: sheet)
    }

    /// A calm idle and a single greeting. Reduce Motion cuts to one waving pose, then rests.
    static let animation = SpriteAnimation(
        idle: [280, 110, 110, 140, 140, 320].enumerated().map { column, hold in
            SpriteFrame(source: .cell(Cell(row: 0, column: column)), hold: .milliseconds(hold))
        },
        action: [140, 140, 140, 280].enumerated().map { column, hold in
            SpriteFrame(source: .cell(Cell(row: 3, column: column)), hold: .milliseconds(hold))
        },
        reducedMotionAction: SpriteFrame(source: .cell(Cell(row: 3, column: 1)), hold: .milliseconds(600)))
}

/// Lets `limit` callers hold a place at once; the rest wait, first come first served.
private actor DecodeLimiter {
    private var available: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { available = max(1, limit) }

    func acquire() async {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    func release() {
        if waiting.isEmpty { available += 1 } else { waiting.removeFirst().resume() }
    }
}

/// What the pets' players keep of a sheet, shared across pages. A sheet is 14 MiB decoded and
/// the contents page shows twenty of them at once, so no player keeps one: `frames` decodes a
/// sheet off the main actor (two at a time, in the order asked), redraws the cells the animation
/// plays into small bitmaps of their own (about 160 KiB each at their largest) and lets the sheet
/// go. Those bitmaps are what the gallery's byte-bounded, memory-warning-aware `ImageCache`
/// keeps. Askers for the same frames share one decode. Only cache bookkeeping runs on the main actor.
final class SpriteAtlasCache {
    static let shared = SpriteAtlasCache()
    /// Decoded bytes kept: the contents page's twenty drawings' frames (1.5 MiB each at 3x) fit, an
    /// eighth of the sheets they come from.
    static let costLimit = 32 << 20

    private struct Request: Hashable {
        let url: URL
        let pixels: Int
    }

    private struct Key: Hashable {
        let request: Request
        let cell: SpriteAtlas.Cell
    }

    private let images: ImageCache<Key>
    private let limiter: DecodeLimiter
    private let sheet: @Sendable (URL) -> SpriteAtlas?
    private var pending: [Request: Task<[SpriteAtlas.Cell: CGImage]?, Never>] = [:]

    /// `sheet` reads and validates a sheet; tests replace it to count and pace the decodes.
    init(costLimit: Int = SpriteAtlasCache.costLimit, concurrentDecodes: Int = 2,
         sheet: @escaping @Sendable (URL) -> SpriteAtlas? = { SpriteAtlas.load(at: $0) }) {
        images = ImageCache(costLimit: costLimit)
        limiter = DecodeLimiter(limit: concurrentDecodes)
        self.sheet = sheet
    }

    /// Decoded bytes the cache holds.
    var decodedBytes: Int { images.totalCost }

    /// Whether any frames are still being decoded.
    var isLoading: Bool { !pending.isEmpty }

    /// The cells `SpriteAtlas.animation` plays, standalone and no larger than `maxPixelSize` on their
    /// long side (rounded up to a multiple of 16 so near-equal sizes share, and never past the
    /// cell's own 208). Nil for a missing, unreadable or wrong-size sheet.
    func frames(at url: URL, maxPixelSize: Int) async -> [SpriteAtlas.Cell: CGImage]? {
        let pixels = min(SpriteAtlas.cellLongSide, max(16, (maxPixelSize + 15) / 16 * 16))
        let request = Request(url: url, pixels: pixels)
        if let kept = kept(request) { return kept }
        if let task = pending[request] { return await task.value }
        let limiter = limiter
        let sheet = sheet
        let task = Task { () -> [SpriteAtlas.Cell: CGImage]? in
            await limiter.acquire()
            let frames = await Background.run { sheet(request.url)?.thumbnails(maxPixelSize: request.pixels) }
            await limiter.release()
            if let frames { self.keep(frames, for: request) }
            self.pending[request] = nil
            return frames
        }
        pending[request] = task
        return await task.value
    }

    private func kept(_ request: Request) -> [SpriteAtlas.Cell: CGImage]? {
        var found: [SpriteAtlas.Cell: CGImage] = [:]
        for cell in SpriteAtlas.playedCells {
            guard let image = images.image(for: Key(request: request, cell: cell)) else { return nil }
            found[cell] = image
        }
        return found
    }

    private func keep(_ frames: [SpriteAtlas.Cell: CGImage], for request: Request) {
        for (cell, image) in frames { images.insert(image, for: Key(request: request, cell: cell)) }
    }
}
