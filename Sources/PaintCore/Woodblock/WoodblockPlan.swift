/// A print's blocks (painting-company row 375, Woodblock at 1765): your photo, printed by numbers.
///
/// A print is made from the app's own template (a coloring book made with few paints, the
/// pigments a printer would cut): the **key block** carries its drawing, cut to stand as lines;
/// then one **colour block** per paint, numbered as the painting numbers its paints, printed in
/// number order, light to dark, as the printers did; last, where the picture has a calm ground
/// along its top, a **bokashi** block wiped to a band of colour fading down the sky.
///
/// Everything here is in the block's space: the template mirrored (`Template.mirrored`), since a
/// block is carved as the print's mirror. Its paints are reordered light to dark, so paint `k`
/// is block number `k + 1` and the canvas's own numbers name the blocks. The print the painter
/// holds up at the end is this space seen the right way round.
public struct WoodblockPlan: Sendable {
    public enum Kind: UInt8, Sendable { case key, color, bokashi }

    public struct Block: Sendable, Equatable {
        public var kind: Kind
        /// The paint this block prints (`template.palette`); nil for the key block.
        public var paint: Int?
        /// The ink, in the template's color space (gamma-encoded, 0…1).
        public var ink: SIMD3<Float>
        /// How much of the paper the ink hides where it is printed fully (washi takes a color
        /// block's pigment transparently; sumi is black).
        public var opacity: Float
        /// The number the painter sees: the paint's (`paint + 1`); 0 for the key and bokashi blocks.
        public var number: Int { kind == .color ? (paint ?? -1) + 1 : 0 }
    }

    /// The template in the block's space: mirrored, its paints light to dark.
    public let template: Template
    public let blocks: [Block]
    public let grid: WoodblockGrid

    /// How many paints a print's template is made with: the pigments a printer of 1765 would
    /// cut a block each for.
    public static let paints = 7
    /// Sumi, the key block's ink.
    public static let sumi = SIMD3<Float>(0.11, 0.10, 0.10)
    /// The washi's color, unprinted.
    public static let paper = SIMD3<Float>(0.95, 0.93, 0.875)

    /// The plan for a print of `template` (in the print's own space, as generated).
    public init(template printed: Template) {
        let order = printed.palette.indices.sorted {
            let a = printed.palette[$0].oklab.x, b = printed.palette[$1].oklab.x
            return a != b ? a > b : $0 < $1
        }
        let t = printed.reorderingPalette(order).mirrored()
        template = t
        grid = WoodblockGrid(width: t.width, height: t.height)
        var blocks = [Block(kind: .key, paint: nil, ink: Self.sumi, opacity: 1)]
        var used = [Bool](repeating: false, count: t.palette.count)
        for r in t.regions where Int(r.colorIndex) < used.count { used[Int(r.colorIndex)] = true }
        for p in t.palette.indices where used[p] {
            blocks.append(Block(kind: .color, paint: p, ink: t.palette[p].rgb, opacity: 0.92))
        }
        if let ground = Self.ground(of: t) {
            var lab = t.palette[ground].oklab
            lab.x *= 0.62
            lab.y *= 1.25
            lab.z *= 1.25
            let ink = ColorScience.okLabToEncoded(lab, space: t.colorSpace)
            blocks.append(Block(kind: .bokashi, paint: ground, ink: ink.clamped(lowerBound: .zero, upperBound: .one), opacity: 0.85))
        }
        self.blocks = blocks
    }

    /// The paint that holds the top of the picture (the top fifth's most common, if it holds at
    /// least 40% of it), which the bokashi block shades; nil for a picture without one.
    static func ground(of t: Template) -> Int? {
        let map = t.regionMap
        guard map.width > 0, map.height > 0 else { return nil }
        let rows = max(1, map.height / 5)
        var counts = [Int](repeating: 0, count: t.palette.count)
        var total = 0
        for y in 0..<rows {
            for x in stride(from: 0, to: map.width, by: 2) {
                let r = Int(map[x, y])
                guard r < t.regions.count else { continue }
                let p = Int(t.regions[r].colorIndex)
                if p < counts.count { counts[p] += 1 }
                total += 1
            }
        }
        guard total > 0, let best = counts.indices.max(by: { counts[$0] < counts[$1] }),
              Float(counts[best]) >= 0.4 * Float(total) else { return nil }
        return best
    }

    /// Whether region `r` is printed by block `b` (the key block prints lines, not regions).
    public func prints(region r: Int, block b: Int) -> Bool {
        guard blocks.indices.contains(b), let paint = blocks[b].paint, template.regions.indices.contains(r) else { return false }
        return Int(template.regions[r].colorIndex) == paint
    }
}

/// The cells a print is worked in: the template's canvas at most `longSide` cells on its long
/// side. Cell (i, j) covers canvas units `[i s, (i + 1) s) × [j s, (j + 1) s)`, s = `cellSize`.
public struct WoodblockGrid: Sendable, Equatable {
    public static let longSide = 1400

    public let width: Int
    public let height: Int
    /// Canvas units per cell.
    public let cellSize: Float

    public init(width canvasWidth: Int, height canvasHeight: Int, longSide: Int = WoodblockGrid.longSide) {
        let long = max(canvasWidth, canvasHeight, 1)
        cellSize = max(1, Float(long) / Float(longSide))
        width = max(1, Int((Float(canvasWidth) / cellSize).rounded(.up)))
        height = max(1, Int((Float(canvasHeight) / cellSize).rounded(.up)))
    }

    public var count: Int { width * height }

    /// The cell under a point in canvas units, nil off the grid.
    public func cell(at p: SIMD2<Float>) -> Int? {
        let x = Int((p.x / cellSize).rounded(.down)), y = Int((p.y / cellSize).rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return y * width + x
    }

    /// A point in canvas units, in cells (cell centres at half-integers).
    public func cells(_ p: SIMD2<Float>) -> SIMD2<Float> { p / cellSize }
}
