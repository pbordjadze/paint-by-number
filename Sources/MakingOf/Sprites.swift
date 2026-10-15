import Foundation

/// Where a guardian stands in its sprite sheet's cells, measured once from the sheet: the rows of
/// idle frames, drawn on top of each other, give the highest and lowest pixel it ever covers
/// (alpha above 24) and the mean column of those pixels. All three are in the cell's own pixels
/// (a cell is `SpriteMetrics.cell`, origin top-left, as the app's `SpriteAtlas` cuts them), and
/// `SpriteDraw` draws a cell so that (`cx`, `foot`) lands on the guardian's feet and its height
/// from `top` to `foot` is the crew's height. `Sprites` in `making_of_pets.py` measures them
/// (`pet-metrics.json` is its output for the bundled sheets).
public struct SpriteMetrics: Sendable, Equatable {
    public var top: Double
    public var foot: Double
    public var cx: Double

    /// A cell of the create-pet v2 sheet: 192 by 208 pixels.
    public static let cell = (width: 192.0, height: 208.0)

    public init(top: Double, foot: Double, cx: Double) {
        self.top = top
        self.foot = foot
        self.cx = cx
    }

    /// The metrics of `pet-metrics.json` by guardian id. Strict like the spec: version 1, and
    /// every sheet's numbers inside its cell with a body of some height.
    public static func table(json: Data) throws -> [String: SpriteMetrics] {
        struct File: Decodable {
            var version: Int
            var cell: [Double]
            var pets: [String: Sheet]
        }
        struct Sheet: Decodable {
            var top: Double
            var foot: Double
            var cx: Double
        }
        let file = try JSONDecoder().decode(File.self, from: json)
        guard file.version == 1, file.cell == [cell.width, cell.height] else {
            throw ShowError(description: "pet-metrics.json is for version \(file.version), cells \(file.cell), not version 1, \(cell)")
        }
        return try file.pets.mapValues { sheet in
            guard 0 <= sheet.top, sheet.top < sheet.foot, sheet.foot < cell.height, 0 <= sheet.cx, sheet.cx < cell.width else {
                throw ShowError(description: "pet-metrics.json: top \(sheet.top), foot \(sheet.foot), cx \(sheet.cx) don't fit a cell")
            }
            return SpriteMetrics(top: sheet.top, foot: sheet.foot, cx: sheet.cx)
        }
    }
}

extension Row {
    /// The sheet's row of this animation (the create-pet v2 contract, `SpriteAtlas`).
    public var atlasRow: Int {
        switch self {
        case .idle: 0
        case .right: 1
        case .left: 2
        case .wave: 3
        case .busy: 7
        case .review: 8
        }
    }

    /// How many frames the row plays.
    public var frameCount: Int {
        switch self {
        case .idle: 6
        case .right, .left: 8
        case .wave: 4
        case .busy, .review: 6
        }
    }
}

/// The soft shadow under a guardian, on the ground at (`x`, `y`): an ellipse `halfWidth` either
/// side and `height` tall, in ink at `alpha`. It shrinks and pales while the guardian is in the air.
public struct SpriteShadow: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var halfWidth: Double
    public var height: Double
    public var alpha: Double
}

/// A guardian to draw: one cell of its sheet, scaled, leaned and placed. The cell's point
/// (`SpriteMetrics.cx`, `SpriteMetrics.foot`) goes at (`x`, `y`), pixels of the working image like
/// every place in the show, which may be below the picture (the walk out through the card band)
/// and so is the view's to clip; the cell is scaled by `scaleX` and `scaleY` about that point, then
/// turned `rotation` degrees clockwise about it, and drawn at `alpha`. The shadow goes first.
///
/// The frame is already wrapped to the row, so `(atlasRow, frame)` is the cell to cut:
/// column `frame` of row `atlasRow`. (`draw_sprite` in `making_of_pets.py` turns the cell before it
/// scales it, which differs from this order by a squash of 5 % on a lean of 2.5 degrees: nothing
/// anyone can see.)
public struct SpriteDraw: Sendable, Equatable {
    public var id: String
    public var row: Row
    public var frame: Int
    public var x: Double
    public var y: Double
    public var scaleX: Double
    public var scaleY: Double
    /// Degrees, positive turning clockwise (SwiftUI's `rotationEffect`, `PetState.tilt` negated).
    public var rotation: Double
    public var alpha: Double
    public var shadow: SpriteShadow

    public var atlasRow: Int { row.atlasRow }

    /// Draws `state`, `fade` being the whole crew's fade at the end of the show (0...1), or nothing
    /// if the guardian is not there to see. `since` is the time since it appeared and `height` its
    /// height in pixels, `pictureHeight` the working image's, which scales it by how far down it
    /// stands. `sprite_draw` in `making_of_pets.py` is the same, number for number.
    static func make(
        id: String, state: PetState, since: Double, fade: Double, height: Double, pictureHeight: Double,
        metrics: SpriteMetrics, crew: ShowSpec.Crew
    ) -> SpriteDraw? {
        var (sx, sy) = (state.scaleX, state.scaleY)
        if 0 <= since && since < crew.pop {
            let u = since / crew.pop
            let pop = 1 + Look.swell * sin(.pi * u) * (1 - u)
            sx *= pop
            sy *= pop
        }
        let alpha = min(state.alpha, ease(since / Look.appear)) * fade
        guard alpha > Look.invisible else { return nil }
        // guardians higher in the picture are a little smaller; below it, as near as they get
        let depth = Look.depthFar + Look.depthSpan * min(max(state.y / pictureHeight, 0), 1)
        let scale = height * depth / (metrics.foot - metrics.top)
        let air = min(state.lift / max(height * crew.hop, 1), 1)
        let halfWidth = height * depth * Look.shadowWidth * (1 - Look.shadowShrink * air)
        let count = state.row.frameCount
        return SpriteDraw(
            id: id, row: state.row, frame: ((state.frame % count) + count) % count,
            x: state.x, y: state.y - state.lift, scaleX: scale * sx, scaleY: scale * sy, rotation: -state.tilt,
            alpha: alpha,
            shadow: SpriteShadow(
                x: state.x, y: state.y, halfWidth: halfWidth, height: halfWidth * Look.shadowFlat,
                alpha: Look.shadowAlpha * alpha * (1 - Look.shadowPale * air)))
    }

    /// How a guardian is drawn, beyond the spec: `Look` in `making_of_pets.py`.
    enum Look {
        /// Below this alpha a guardian is not drawn.
        static let invisible = 0.01
        /// A guardian fades in over this long as it appears, and swells by this share of its size
        /// over the spec's `crew.pop` on the way.
        static let appear = 0.18
        static let swell = 0.18
        /// A guardian at the picture's top is this share of its height, one at the bottom this
        /// much more.
        static let depthFar = 0.9
        static let depthSpan = 0.16
        /// The shadow: half its width in guardian heights, its height in widths, how much it
        /// shrinks and pales in the air, and its alpha on the ground (44 of 255).
        static let shadowWidth = 0.40
        static let shadowFlat = 0.42
        static let shadowShrink = 0.4
        static let shadowPale = 0.6
        static let shadowAlpha = 44.0 / 255
    }
}
