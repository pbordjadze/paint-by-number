import Foundation

/// What stays of one block, on the print's grid (`WoodblockGrid`): the wood that must stand to
/// print, as a signed distance (`shape`, in cells: negative inside what stays, clamped to ±`band`)
/// drawn smooth at any zoom, and every cell's room from it (`clearance`), which sizes the tool.
///
/// The key block keeps the template's drawing: its drawn lines (`TemplateLineArt`), each cut at
/// one weight that swells a little with its strength, and the drawing's strokes inside areas
/// that are long or closed (a carver cuts no crumbs); a template without line art keeps the
/// edges where its paint changes. A colour block keeps its paint's areas, cut along the
/// template's own smoothed boundaries, so each meets the key line at its middle, as the kyōgō
/// proofs marked them.
public struct WoodblockField: Sendable {
    public let grid: WoodblockGrid
    /// Signed distance to the edge of what stays, in cells, clamped to ±`band`.
    public let shape: [Float]
    /// Distance from each cell's centre to the nearest cell that stays, in cells (0 on it).
    public let clearance: [Float]
    /// Cells that stay.
    public let standing: Int

    /// How far either side of an edge `shape` is exact.
    public static let band: Float = 6

    public init(plan: WoodblockPlan, block b: Int) {
        let grid = plan.grid
        let t = plan.template
        var shape: [Float]
        switch plan.blocks[b].kind {
        case .key:
            shape = [Float](repeating: Self.band, count: grid.count)
            let long = Float(max(t.width, t.height))
            for line in Self.keyLines(of: t) {
                let widths = Self.carvedWidths(of: line, long: long).map { $0 / grid.cellSize }
                Self.stamp(line.points, halfWidth: line.halfWidth / grid.cellSize, widths: widths, grid: grid, into: &shape, signed: nil)
            }
        case .color, .bokashi:
            let paint = plan.blocks[b].paint ?? -1
            var inside = [Bool](repeating: false, count: t.regions.count + 1)
            for (r, region) in t.regions.enumerated() where Int(region.colorIndex) == paint { inside[r] = true }
            func member(_ r: UInt32) -> Bool { Int(r) < t.regions.count && inside[Int(r)] }
            var mask = [Bool](repeating: false, count: grid.count)
            for j in 0..<grid.height {
                let y = min(t.regionMap.height - 1, Int((Float(j) + 0.5) * grid.cellSize))
                for i in 0..<grid.width {
                    let x = min(t.regionMap.width - 1, Int((Float(i) + 0.5) * grid.cellSize))
                    guard x >= 0, y >= 0 else { continue }
                    mask[j * grid.width + i] = member(t.regionMap[x, y])
                }
            }
            shape = mask.map { $0 ? -Self.band : Self.band }
            for e in t.edges where member(e.left) != member(e.right) {
                Self.stamp(Array(t.points(of: e)), halfWidth: 0, grid: grid, into: &shape, signed: mask)
            }
        }
        self.grid = grid
        self.shape = shape
        let squared = DistanceTransform.squaredEDT(width: grid.width, height: grid.height) { shape[$0] < 0 }
        clearance = squared.storage.map { $0.isFinite ? $0.squareRoot() : 1e6 }
        standing = shape.reduce(0) { $0 + ($1 < 0 ? 1 : 0) }
    }

    /// Whether cell `i` stands to print.
    public func stays(_ i: Int) -> Bool { shape[i] < 0 }

    /// A line of the key block: its points in canvas units and half its width; an open stroke
    /// (`tapers`) is cut to a point at its ends.
    public struct Line: Sendable {
        public var points: [SIMD2<Float>]
        public var halfWidth: Float
        public var tapers = false
    }

    /// Half a line's width at each of its points, as a knife cuts it: swelling and thinning
    /// along its way (by where it lies, so lines meeting at a junction meet at one width), and
    /// an open stroke drawn to a point at its ends.
    static func carvedWidths(of line: Line, long: Float) -> [Float] {
        let pts = line.points
        let scale = long * 0.018
        var along = [Float](repeating: 0, count: pts.count)
        for k in pts.indices.dropFirst() {
            let d = pts[k] - pts[k - 1]
            along[k] = along[k - 1] + (d.x * d.x + d.y * d.y).squareRoot()
        }
        let total = along.last ?? 0
        let taper = long * 0.012
        return pts.indices.map { k in
            let p = pts[k] / scale
            let swell = 0.45 + 1.1 * WoodblockBench.noise(p.x, p.y, 7)
            var w = line.halfWidth * swell
            if line.tapers && taper > 0 {
                let end = min(along[k], total - along[k]) / taper
                w *= 0.35 + 0.65 * min(1, max(0, end))
            }
            return w
        }
    }

    /// The key block's lines: the drawing as a carver would cut it.
    public static func keyLines(of t: Template) -> [Line] {
        let long = Float(max(t.width, t.height))
        let half = 0.5 * max(1.6, long * 0.0026)
        let shortest = long * 0.03
        var lines: [Line] = []
        if let art = t.lineArt, art.edgeLayers.count == t.edges.count {
            for (i, e) in t.edges.enumerated() where LineLayer.isDrawn(art.edgeLayers[i]) {
                let weight = i < art.edgeWeights.count ? Float(art.edgeWeights[i]) / 255 : 0.5
                lines.append(Line(points: Array(t.points(of: e)), halfWidth: half * (0.8 + 0.4 * weight)))
            }
            for s in art.strokes {
                let lo = Int(s.pointStart), hi = lo + Int(s.pointCount)
                guard s.pointCount >= 2, hi <= art.strokePoints.count, LineLayer.isDrawn(s.layer) else { continue }
                let pts = Array(art.strokePoints[lo..<hi])
                let closed = pts.first == pts.last
                if !closed && length(of: pts) < shortest { continue }
                lines.append(Line(points: pts, halfWidth: half * (0.8 + 0.4 * Float(s.weight) / 255), tapers: !closed))
            }
        } else {
            for e in t.edges where e.right != BoundaryEdge.outside && Int(e.left) < t.regions.count && Int(e.right) < t.regions.count
                && t.regions[Int(e.left)].colorIndex != t.regions[Int(e.right)].colorIndex {
                lines.append(Line(points: Array(t.points(of: e)), halfWidth: half))
            }
        }
        return lines
    }

    static func length(of pts: [SIMD2<Float>]) -> Float {
        zip(pts, pts.dropFirst()).reduce(0) { s, p in
            let d = p.1 - p.0
            return s + (d.x * d.x + d.y * d.y).squareRoot()
        }
    }

    /// Lowers `shape` near a polyline (canvas units) to its distance in cells, less `halfWidth`
    /// (cells): unsigned for a line (`signed` nil), signed by `signed`'s cells for an edge.
    static func stamp(_ pts: [SIMD2<Float>], halfWidth h: Float, widths: [Float]? = nil, grid: WoodblockGrid,
                      into shape: inout [Float], signed: [Bool]?) {
        guard pts.count >= 2 else { return }
        let widths = widths.flatMap { $0.count == pts.count ? $0 : nil }
        let reach = (widths?.max() ?? h) + band
        for k in 0..<(pts.count - 1) {
            let a = grid.cells(pts[k]), b = grid.cells(pts[k + 1])
            let x0 = max(0, Int((min(a.x, b.x) - reach).rounded(.down))), x1 = min(grid.width - 1, Int((max(a.x, b.x) + reach).rounded(.up)))
            let y0 = max(0, Int((min(a.y, b.y) - reach).rounded(.down))), y1 = min(grid.height - 1, Int((max(a.y, b.y) + reach).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            let ab = b - a
            let len2 = max(ab.x * ab.x + ab.y * ab.y, 1e-9)
            for y in y0...y1 {
                for x in x0...x1 {
                    let c = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                    let ac = c - a
                    let t = min(max((ac.x * ab.x + ac.y * ab.y) / len2, 0), 1)
                    let d = c - (a + ab * t)
                    let half = widths.map { $0[k] + ($0[k + 1] - $0[k]) * t } ?? h
                    let dist = (d.x * d.x + d.y * d.y).squareRoot() - half
                    let i = y * grid.width + x
                    if let signed {
                        if signed[i] { shape[i] = max(shape[i], -dist) } else { shape[i] = min(shape[i], dist) }
                    } else {
                        shape[i] = min(shape[i], dist)
                    }
                }
            }
        }
    }
}
