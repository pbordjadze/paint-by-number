import CoreGraphics
import Foundation

/// The create-pet v2 contract: 192 × 208 cells, eight columns, eleven rows, top-left origin.
/// Rows 0–8 animate; rows 9–10 hold sixteen clockwise looks. Unused cells are never played.
/// Decode and crop through Background.run; a damaged or non-v2 sheet yields no animation.
nonisolated struct SpriteAtlas: Sendable {
    static let width = 1536
    static let height = 2288
    static let frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]

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
    private let cells: [Cell: CGImage]

    init?(sheet: CGImage) {
        guard sheet.width == Self.width, sheet.height == Self.height else { return nil }
        var cells: [Cell: CGImage] = [:]
        for (row, count) in Self.frameCounts.enumerated() {
            for column in 0..<count {
                let cell = Cell(row: row, column: column)
                guard let rect = cell.rect, let image = sheet.cropping(to: rect) else { return nil }
                cells[cell] = image
            }
        }
        self.sheet = sheet
        self.cells = cells
    }

    func image(at cell: Cell) -> CGImage? { cells[cell] }

    /// The cells `animation` plays, each redrawn so its long side is `maxPixelSize`. A crop shares
    /// its sheet's pixels, so these copies are what lets a small player drop the sheet.
    func thumbnails(maxPixelSize: Int) -> [Cell: CGImage] {
        var result: [Cell: CGImage] = [:]
        let frames = Self.animation.idle + Self.animation.action + [Self.animation.reducedMotionAction]
        for frame in frames {
            guard case .cell(let cell) = frame.source, result[cell] == nil, let image = cells[cell] else { continue }
            result[cell] = ImageCodec.downscaled(image, maxPixelSize: maxPixelSize)
        }
        return result
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

/// Reuses the gallery's byte-bounded, memory-warning-aware image cache. Two decoded v2 sheets
/// fit in 32 MiB; crops retain their sheet while a player is visible. Concurrent readers share
/// one decode. Only cheap cache bookkeeping runs on MainActor; decoding and slicing do not.
final class SpriteAtlasCache {
    static let shared = SpriteAtlasCache()
    private let images = ImageCache<URL>(costLimit: 32 << 20)
    private var pending: [URL: Task<SpriteAtlas?, Never>] = [:]
    private var failed: Set<URL> = []

    func load(at url: URL) async -> SpriteAtlas? {
        if failed.contains(url) { return nil }
        if let task = pending[url] { return await task.value }
        let cached = images.image(for: url)
        let task = Task {
            await Background.run {
                if let cached { return SpriteAtlas(sheet: cached) }
                return SpriteAtlas.load(at: url)
            }
        }
        pending[url] = task
        let atlas = await task.value
        if let atlas { images.insert(atlas.sheet, for: url) }
        else { failed.insert(url) }
        pending[url] = nil
        return atlas
    }
}
