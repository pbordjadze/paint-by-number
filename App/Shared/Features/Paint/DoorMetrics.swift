import CoreGraphics
import SwiftUI

/// How big the doors are and how they are laid: in one row where each door is still a door's size
/// (an iPad, a phone on its side), else in two rows (two by two; five as three over two), never
/// taller than the room they are given. An iPad's panel widens for a fifth door
/// (`CompletionBar.widestPanel(doors:)`), so its row of five is as large as a row of four. Both
/// eras' Finished panels lay their doors by it (Paint by Mosaic's from painting-company row 330).
nonisolated struct DoorMetrics: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let door: CGSize

    static let gap: CGFloat = 14
    static let rowGap: CGFloat = 12
    static let labelGap: CGFloat = 6
    /// A door's height over its width.
    static let aspect: CGFloat = 1.08
    static let largest: CGFloat = 168
    /// Narrower than this a card is no door: none show.
    static let smallest: CGFloat = 56
    /// One row is taken when its doors are at least this wide.
    static let roomyRow: CGFloat = 110
    /// And a row of five or more when at least this wide, on a screen between a phone's and an
    /// iPad's, where the panel can't widen all the way: their captions may take a second line
    /// there, which the row's height has no room for under `labelHeight` alone.
    static let snugRow: CGFloat = 88

    /// The doors' layout in `width` × `height` points, or nil where they don't fit.
    static func fitting(count: Int, width: CGFloat, height: CGFloat, dynamicTypeSize: DynamicTypeSize) -> DoorMetrics? {
        guard count > 0, width.isFinite, height.isFinite else { return nil }
        let label = labelHeight(dynamicTypeSize)
        func laid(columns: Int) -> DoorMetrics {
            let rows = (count + columns - 1) / columns
            let byWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let byHeight = ((height - rowGap * CGFloat(rows - 1)) / CGFloat(rows) - label - labelGap) / aspect
            let w = max(0, min(byWidth, byHeight, largest)).rounded(.down)
            return DoorMetrics(columns: columns, rows: rows, door: CGSize(width: w, height: (w * aspect).rounded(.down)))
        }
        let row = laid(columns: count)
        let grid = laid(columns: max(min(2, count), (count + 1) / 2))
        // Five doors keep to one row a little sooner: on an iPad's panel two rows of large doors
        // would take the painting's room.
        let roomy = count > 4 ? snugRow : roomyRow
        let best = row.door.width >= roomy || row.door.width >= grid.door.width ? row : grid
        return best.door.width >= smallest ? best : nil
    }

    /// The room a door's words are given under it (`FinishedDoors`, `CompletionBar.panelHeight`):
    /// its name and the line under it, and a second line for that one on doors narrower than a
    /// roomy row's, where it wraps ("To someone you love", most translations).
    func labelRoom(_ size: DynamicTypeSize) -> CGFloat {
        let size = min(size, .xxLarge)
        let label = Self.labelHeight(size)
        guard door.width < Self.roomyRow else { return label }
        return label + (Self.captionLine * Self.textScale(size)).rounded(.up)
    }

    /// A line of `.caption` at the Large text size.
    static let captionLine: CGFloat = 16

    private static func textScale(_ size: DynamicTypeSize) -> CGFloat {
        let steps: [(DynamicTypeSize, CGFloat)] = [(.large, 1), (.xLarge, 1.1), (.xxLarge, 1.2)]
        return steps.last(where: { $0.0 <= size })?.1 ?? 0.9
    }

    /// A door's name and the line under it, one line each, at the text size (capped as the
    /// Finished panel caps it).
    static func labelHeight(_ size: DynamicTypeSize) -> CGFloat {
        (38 * textScale(size)).rounded(.up)
    }
}
