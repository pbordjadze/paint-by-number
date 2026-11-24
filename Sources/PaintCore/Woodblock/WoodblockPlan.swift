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
    /// The blocks, as a number a saved bench records (FNV-1a over their count and each one's kind
    /// and paint; not the inks, which pass through floating-point math a system update may round
    /// otherwise): the same photo cut by a build that chooses blocks otherwise has another.
    public var signature: UInt32 {
        var h: UInt32 = 2_166_136_261
        func mix(_ v: UInt32) {
            for k in 0..<4 { h = (h ^ ((v >> (8 * k)) & 0xFF)) &* 16_777_619 }
        }
        mix(UInt32(blocks.count))
        for b in blocks {
            mix(UInt32(b.kind.rawValue))
            mix(UInt32(bitPattern: Int32(truncatingIfNeeded: b.paint ?? -1)))
        }
        return h
    }

    public static let paper = SIMD3<Float>(0.95, 0.93, 0.875)

    /// The plan for a print of `template` (in the print's own space, as generated). A Portrait
    /// photo's `depth` with a sky matte (PaintCore's `PhotoDepth`) names the sky the bokashi
    /// shades, whatever its lightness: the paint holding most of the camera's sky, once the sky
    /// covers `leastSky` of the picture. Without it the top of the picture is read as before, and
    /// a plan without depth is the plan it always was (its `signature` too).
    public init(template generated: Template, depth: PhotoDepth? = nil) {
        let printed = generated.flattenedToCells(minorShare: Self.minorShare, keepContrast: 0.3)
        // Paints light to dark; a paint as pale as the washi is the paper itself, left bare
        // (no block cuts it), and goes last, so the blocks are numbered from 1.
        let paper = printed.palette.indices.filter { Self.isPaper(printed.palette[$0].oklab) }
        let order = printed.palette.indices.sorted {
            let pa = paper.contains($0), pb = paper.contains($1)
            if pa != pb { return pb }
            let a = printed.palette[$0].oklab.x, b = printed.palette[$1].oklab.x
            return a != b ? a > b : $0 < $1
        }
        let t = printed.reorderingPalette(order).mirrored().primaryLabelsOnly()
        template = t
        grid = WoodblockGrid(width: t.width, height: t.height)
        var blocks = [Block(kind: .key, paint: nil, ink: Self.sumi, opacity: 1)]
        var used = [Bool](repeating: false, count: t.palette.count)
        for r in t.regions where Int(r.colorIndex) < used.count { used[Int(r.colorIndex)] = true }
        for p in t.palette.indices where used[p] && !Self.isPaper(t.palette[p].oklab) {
            blocks.append(Block(kind: .color, paint: p, ink: Self.pigment(t.palette[p].oklab, space: t.colorSpace), opacity: 0.9))
        }
        if let sky = depth.flatMap({ Self.sky(of: printed, depth: $0) }),
           let ground = order.firstIndex(of: sky), used[ground], !Self.isPaper(t.palette[ground].oklab) {
            blocks.append(Block(kind: .bokashi, paint: ground, ink: Self.ai, opacity: 0.9))
        } else if let ground = Self.ground(of: t), t.palette[ground].oklab.x >= 0.6 {
            blocks.append(Block(kind: .bokashi, paint: ground, ink: Self.ai, opacity: 0.9))
        }
        self.blocks = blocks
    }

    /// A paint holding less of a cell of the drawing than this takes the cell's main paint.
    public static let minorShare: Float = 0.3

    /// Ai, the indigo a printer wiped down the sky.
    public static let ai = SIMD3<Float>(0.13, 0.22, 0.36)

    /// Whether a paint is pale and quiet enough to be the bare washi.
    static func isPaper(_ lab: SIMD3<Float>) -> Bool {
        lab.x >= 0.86 && (lab.y * lab.y + lab.z * lab.z).squareRoot() <= 0.05
    }

    /// A paint as a block's ink: a pigment's, purer and a little lighter than the photo's mean,
    /// since washi takes it transparently over its own cream.
    static func pigment(_ lab: SIMD3<Float>, space: RGBColorSpace) -> SIMD3<Float> {
        var ink = lab
        ink.x = min(0.95, ink.x + 0.03)
        ink.y *= 1.3
        ink.z *= 1.3
        return ColorScience.okLabToEncoded(ink, space: space).clamped(lowerBound: .zero, upperBound: .one)
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

    /// The least share of the picture the camera's sky must cover to have a bokashi of its own.
    public static let leastSky: Float = 0.05

    /// The paint (in `t`'s own palette) that holds most of the camera's sky, by area; nil without
    /// a sky matte or with too little sky.
    static func sky(of t: Template, depth: PhotoDepth) -> Int? {
        let isSky = depth.skyRegions(of: t)
        let map = t.regionMap
        guard isSky.count == t.regions.count, map.count > 0 else { return nil }
        var area = [Int](repeating: 0, count: t.regions.count)
        for i in 0..<map.count {
            let r = Int(map.storage[i])
            if r < area.count { area[r] += 1 }
        }
        var byPaint = [Int](repeating: 0, count: t.palette.count)
        var total = 0
        for r in t.regions.indices where isSky[r] {
            let p = Int(t.regions[r].colorIndex)
            guard p < byPaint.count else { continue }
            byPaint[p] += area[r]
            total += area[r]
        }
        guard Float(total) >= leastSky * Float(map.count),
              let best = byPaint.indices.max(by: { byPaint[$0] < byPaint[$1] || (byPaint[$0] == byPaint[$1] && $0 > $1) })
        else { return nil }
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

    /// A point in canvas units, in cells (cell centres at half-integers).
    public func cells(_ p: SIMD2<Float>) -> SIMD2<Float> { p / cellSize }
}
