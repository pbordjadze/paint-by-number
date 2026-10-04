import PaintCore

/// `stats.json`'s `lineArt`.
struct LineArtReport: Codable {
    var settings: LineArtSettings
    /// Size of the edge map read.
    var edgeMap: [Int]
    var stats: LineArtStats
    /// Template edges per layer: outline, detail, texture, color.
    var edgesPerLayer: [Int]
    /// Their length (canvas units) per layer.
    var edgeLengthPerLayer: [Float]
    var interiorStrokes: Int
    var interiorPoints: Int
    /// Cells against the segmentation's regions (a classic template at the same settings).
    var cellsVsClassic: Float
    /// The drawing's length: every drawn layer, along cell boundaries and inside cells (canvas units).
    var drawnLength: Float
    /// Drawn line per 1000 canvas pixels: how dense the drawing is.
    var inkDensity: Float
    /// The share of the drawing that runs inside cells (fur, creases) rather than along a boundary.
    var interiorFraction: Float
    var meanInteriorStrokeLength: Float
    /// Open ends of interior strokes per 1000 units of drawing: how fragmented it is (a closed
    /// drawing has none; every dangling stroke adds two).
    var openEndsPer1000: Float
    /// Areas the drawn lines enclose: cells joined across the edges with no line (`color`). What
    /// the coloring book's painter reads as a shape.
    var enclosedAreas: Int
    var cellsPerEnclosedArea: Float
    /// Enclosed areas holding a single cell, as a fraction of all.
    var singleCellAreaFraction: Float
    /// The largest enclosed area as a fraction of the canvas: a gap in a silhouette lets the
    /// background's area reach inside, and the whole canvas is one area when nothing closes.
    var largestAreaFraction: Float
    /// Areas the outlines alone enclose (cells joined across detail, texture and color edges).
    var outlineAreas: Int
    /// The palette number `selected.svg` hatches: the paint with the most cells.
    var selectedColor: Int
    /// The share of the canvas the drawn lines wall off from the frame, as pixels, with the
    /// lines as drawn and then widened by 1, 2, 3 and 4 pixels on each side: a silhouette that
    /// is open by a few pixels encloses nothing until a widening closes the gap (the jump says
    /// how wide the gap is; `openings` where the widening closed it).
    var enclosedByWidening: [Float]
    /// Where the first widening that walled off the most area closed a gap: [x, y] (canvas
    /// units) of the pixel the frame reached last before, up to five.
    var openings: [[Int]]

    init?(_ out: TemplateGenerator.Output, settings: LineArtSettings, input: LineArtInput?) {
        guard let stats = out.lineArtStats, let lines = out.template.lineArt, let input else { return nil }
        let t = out.template
        self.settings = settings
        edgeMap = [input.edges.width, input.edges.height]
        self.stats = stats
        var count = [0, 0, 0, 0]
        var length: [Float] = [0, 0, 0, 0]
        for (k, e) in t.edges.enumerated() {
            let l = Int(min(lines.edgeLayers[k], 3))
            count[l] += 1
            let p = t.points(of: e)
            for i in p.indices.dropFirst() {
                let d = p[i] - p[i - 1]
                length[l] += (d * d).sum().squareRoot()
            }
        }
        edgesPerLayer = count
        edgeLengthPerLayer = length.map { ($0 * 10).rounded() / 10 }
        interiorStrokes = lines.strokes.count
        interiorPoints = lines.strokePoints.count
        cellsVsClassic = Float(t.regions.count) / Float(max(stats.segmentationRegions, 1))

        var interior: Float = 0
        var openEnds = 0
        for stroke in lines.strokes {
            let start = Int(stroke.pointStart), end = start + Int(stroke.pointCount)
            guard stroke.pointCount >= 2, end <= lines.strokePoints.count else { continue }
            for i in (start + 1)..<end {
                let d = lines.strokePoints[i] - lines.strokePoints[i - 1]
                interior += (d * d).sum().squareRoot()
            }
            if lines.strokePoints[start] != lines.strokePoints[end - 1] { openEnds += 2 }
        }
        let drawn = length[0] + length[1] + length[2] + interior
        func round(_ v: Float, _ places: Float) -> Float { (v * places).rounded() / places }
        drawnLength = round(drawn, 10)
        inkDensity = round(drawn / Float(max(t.width * t.height, 1)) * 1000, 100)
        interiorFraction = round(drawn > 0 ? interior / drawn : 0, 1000)
        meanInteriorStrokeLength = round(lines.strokes.isEmpty ? 0 : interior / Float(lines.strokes.count), 10)
        openEndsPer1000 = round(drawn > 0 ? Float(openEnds) / drawn * 1000 : 0, 100)

        let enclosed = Self.areas(t, labels: Self.enclosedAreaLabels(t))
        enclosedAreas = enclosed.count
        cellsPerEnclosedArea = round(Float(t.regions.count) / Float(max(enclosed.count, 1)), 100)
        singleCellAreaFraction = round(enclosed.isEmpty ? 0 : Float(enclosed.filter { $0.cells == 1 }.count) / Float(enclosed.count), 1000)
        largestAreaFraction = round((enclosed.map(\.area).max() ?? 0) / Float(max(t.width * t.height, 1)), 1000)
        outlineAreas = Self.areas(t, labels: Self.areaLabels(t, joining: { $0 != LineLayer.outline.rawValue })).count

        var cellsPerColor = [Int](repeating: 0, count: t.palette.count)
        for region in t.regions { cellsPerColor[Int(region.colorIndex)] += 1 }
        selectedColor = (cellsPerColor.indices.max { cellsPerColor[$0] < cellsPerColor[$1] } ?? 0) + 1
        let gaps = Self.gaps(t)
        enclosedByWidening = gaps.enclosed.map { round($0, 1000) }
        openings = gaps.openings
    }

    /// The drawn lines (every drawn edge and interior stroke) as a pixel mask.
    static func drawnMask(_ t: Template) -> [Bool] {
        let w = t.width, h = t.height
        var mask = [Bool](repeating: false, count: w * h)
        guard let lines = t.lineArt, lines.edgeLayers.count == t.edges.count else { return mask }
        func segment(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
            let d = b - a
            let n = max(1, Int((d * d).sum().squareRoot().rounded(.up)))
            for s in 0...n {
                let p = a + d * (Float(s) / Float(n))
                let x = Int(p.x.rounded()), y = Int(p.y.rounded())
                if x >= 0, y >= 0, x < w, y < h { mask[y * w + x] = true }
            }
        }
        for (k, e) in t.edges.enumerated() where lines.edgeLayers[k] != LineLayer.color.rawValue {
            let pts = t.points(of: e)
            for j in pts.indices.dropFirst() { segment(pts[j - 1], pts[j]) }
        }
        for stroke in lines.strokes {
            let start = Int(stroke.pointStart), end = start + Int(stroke.pointCount)
            guard stroke.pointCount >= 2, end <= lines.strokePoints.count else { continue }
            for j in (start + 1)..<end { segment(lines.strokePoints[j - 1], lines.strokePoints[j]) }
        }
        return mask
    }

    /// Flood from the frame through the pixels not in `wall` (4-connected): per pixel the
    /// steps from the frame, or -1 when walled off.
    static func flood(_ wall: [Bool], width w: Int, height h: Int) -> [Int32] {
        var steps = [Int32](repeating: -1, count: w * h)
        var queue: [Int32] = []
        for y in 0..<h {
            for x in 0..<w where x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                let i = y * w + x
                if !wall[i] { steps[i] = 0; queue.append(Int32(i)) }
            }
        }
        var head = 0
        while head < queue.count {
            let i = Int(queue[head]); head += 1
            let y = i / w, x = i - y * w, next = steps[i] + 1
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
                let j = yy * w + xx
                if !wall[j] && steps[j] < 0 { steps[j] = next; queue.append(Int32(j)) }
            }
        }
        return steps
    }

    /// `enclosedByWidening` and `openings`: the lines widened by 0...4 pixels, the share of
    /// the canvas the frame cannot reach through them, and where the widening that gained the
    /// most closed a gap (the pixels enclosed by it the frame reached last before it).
    static func gaps(_ t: Template) -> (enclosed: [Float], openings: [[Int]]) {
        let w = t.width, h = t.height
        var wall = drawnMask(t)
        var enclosed: [Float] = []
        var floods: [[Int32]] = []
        for r in 0...4 {
            if r > 0 {
                // One pixel of widening on every side (a 3×3 dilation).
                var wider = wall
                for y in 0..<h {
                    for x in 0..<w where wall[y * w + x] {
                        for yy in max(0, y - 1)...min(h - 1, y + 1) {
                            for xx in max(0, x - 1)...min(w - 1, x + 1) { wider[yy * w + xx] = true }
                        }
                    }
                }
                wall = wider
            }
            let steps = flood(wall, width: w, height: h)
            floods.append(steps)
            enclosed.append(Float(steps.filter { $0 < 0 }.count - wall.filter { $0 }.count) / Float(w * h))
        }
        var openings: [[Int]] = []
        if let best = (1...4).max(by: { enclosed[$0] - enclosed[$0 - 1] < enclosed[$1] - enclosed[$1 - 1] }),
           enclosed[best] - enclosed[best - 1] > 0.01 {
            // Pixels the widening walled off, ordered by how soon the frame reached them before:
            // the first few are at the gap (one per 30-pixel neighbourhood).
            let before = floods[best - 1], after = floods[best]
            var candidates: [(steps: Int32, x: Int, y: Int)] = []
            for i in 0..<(w * h) where after[i] < 0 && before[i] >= 0 {
                candidates.append((before[i], i % w, i / w))
            }
            candidates.sort { $0.steps != $1.steps ? $0.steps < $1.steps : ($0.y, $0.x) < ($1.y, $1.x) }
            for c in candidates where openings.count < 5 && !openings.contains(where: { abs($0[0] - c.x) < 30 && abs($0[1] - c.y) < 30 }) {
                openings.append([c.x, c.y])
            }
        }
        return (enclosed, openings)
    }

    /// Per region, the area the drawn lines enclose it in (0-based, dense), or nil for a
    /// template without line art.
    static func enclosedAreaLabels(_ t: Template) -> [Int] {
        areaLabels(t, joining: { $0 == LineLayer.color.rawValue })
    }

    /// Per region, the area it lies in (0-based, dense) when neighbouring cells join across
    /// every edge whose layer `joining` accepts; every region its own area without line art.
    static func areaLabels(_ t: Template, joining: (UInt8) -> Bool) -> [Int] {
        var parent = Array(t.regions.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        if let layers = t.lineArt?.edgeLayers, layers.count == t.edges.count {
            for (k, e) in t.edges.enumerated() where e.right != BoundaryEdge.outside && joining(layers[k]) {
                let a = find(Int(e.left)), b = find(Int(e.right))
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }
        var dense: [Int: Int] = [:]
        return t.regions.indices.map { i in
            let root = find(i)
            if let label = dense[root] { return label }
            dense[root] = dense.count
            return dense.count - 1
        }
    }

    /// Each area's cell count and area (canvas pixels), by label.
    static func areas(_ t: Template, labels: [Int]) -> [(cells: Int, area: Float)] {
        let count = (labels.max() ?? -1) + 1
        var cells = [Int](repeating: 0, count: count), area = [Float](repeating: 0, count: count)
        for (i, label) in labels.enumerated() {
            cells[label] += 1
            area[label] += t.regions[i].area
        }
        return zip(cells, area).map { ($0, $1) }
    }
}
