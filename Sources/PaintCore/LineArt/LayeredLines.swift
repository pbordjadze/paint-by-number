import Foundation

/// Layered line art: an edge map (and eyes) turned into cells bounded by lines, each line in
/// a `LineLayer` by its strength. `LineArtSettings` holds every user-facing knob.
///
/// Stages (timed as `lineArt.*`):
/// 1. `detect`: the edge map resampled to the working size, its ridges, hysteresis and
///    thinning (`LineDetection`).
/// 2. `trace`: the centerlines as a graph, cleaned (bubbles, spurs, specks, components under
///    `minimumStrokeLength`), gaps up to `gapBridging` bridged, ends led into the frame, and
///    joined into strokes smoothed by `lineSmoothing` (`StrokeGraph`).
/// 3. `layer`: per point, hysteresis along the stroke against the outline, detail and
///    texture thresholds, the outline threshold rising where lines crowd (`LineLayering`);
///    stretches below texture are cut out. Eyes (`outlineEyes`) replace the lines inside them
///    with their contours and irises as outlines and promote the lines around them. Free ends
///    reach for the nearest line, paint boundary or frame (`gapBridging` × 1.6 / 1.2 / 1 by
///    layer), so open strokes close cells.
/// 4. `cells`: the segmentation split along the rasterized lines (`CellMap`): every cell keeps
///    its paint and holds its number; `keepColorEdges` off merges line-free neighbours whose
///    paints are within two palette steps.
/// 5. `trim`: lines keep only the stretches that run along a cell boundary (a line dangling
///    inside a cell is not drawn); eyes are kept whole.
/// 6. `join`: same-paint neighbours join per `samePaint` (by default across texture lines),
///    and the lines that end up inside a cell become interior strokes. Paints no cell uses
///    are dropped, cells renumbered.
/// After vectorizing, `annotate` gives each boundary edge the layer of the line along it
/// (`color` where only the paint changes) and a weight.
///
/// Deterministic: everything is sequential, per pixel, or integer counts summed across
/// bands, with fixed tie-breaks, so the same edge map and settings give the same template on
/// any number of cores.
enum LayeredLines {
    /// Stretches of line further than this (canvas units) from every cell boundary do not
    /// bound a cell; runs shorter than `trimMinimum` follow their neighbours.
    static let trimNear: Float = 2.2
    static let trimMinimum: Float = 4
    /// Template edges within this distance of a drawn line take its layer.
    static let annotateNear: Float = 3
    /// Free-end reach per layer (outline, detail, texture), as a factor on `gapBridging`.
    static let closeReach: [Float] = [1.6, 1.2, 1]
    /// `keepColorEdges` off: paints within this many palette steps merge.
    static let mergeSteps: Float = 2
    /// Paint difference at which a color line's weight saturates.
    static let colorWeightReference: Float = 0.15

    struct Plan {
        var segmentation: Segmentation
        /// Line stretches that bound cells (for the edges' layers).
        var boundaryLines: [DrawnLine]
        /// Lines drawn inside a cell, with that cell.
        var interiorLines: [(line: DrawnLine, region: Int)]
        var stats: LineArtStats
    }

    static func apply(
        _ segmentation: Segmentation, input: LineArtInput, importance: [Float]?, settings: GenerationSettings,
        cancel: CancellationCheck, clock: StageClock
    ) throws -> Plan {
        let s = settings.normalized.lineArt
        let w = segmentation.width, h = segmentation.height
        var stats = LineArtStats()
        stats.segmentationRegions = segmentation.regionCount
        guard w >= 8, h >= 8, segmentation.regionCount > 0 else {
            return Plan(segmentation: segmentation, boundaryLines: [], interiorLines: [], stats: stats)
        }
        let mapScale = Float(max(w, h)) / Float(max(input.edges.width, input.edges.height))
        let unit = max(mapScale, 1)

        let mask = try clock.measure("lineArt.detect") { () throws -> (mask: [Bool], strength: [Float], clutter: [Float]) in
            let strength = LineDetection.strength(input.edges, width: w, height: h)
            try cancel.throwIfCancelled()
            let ridges = try LineDetection.ridges(strength, width: w, height: h, scale: mapScale, cancel: cancel)
            try cancel.throwIfCancelled()
            let mask = try LineDetection.lines(
                ridge: ridges.ridge, smooth: ridges.smooth, importance: importance, width: w, height: h,
                threshold: s.textureThreshold, cancel: cancel)
            let clutter = try LineDetection.clutter(mask, width: w, height: h, cancel: cancel)
            return (mask, ridges.smooth, clutter)
        }
        try cancel.throwIfCancelled()

        let strokes = clock.measure("lineArt.trace") { () -> [StrokeGraph.Stroke] in
            var g = StrokeGraph.trace(mask.mask, strength: mask.strength, width: w, height: h)
            g.mergeDegree2()
            g.popBubbles(perimeter: 30 * unit)
            g.pruneSpurs(8 * unit)
            g.pruneFragments(4 * unit)
            g.bridgeGaps(s.gapBridging)
            g.pruneSpurs(8 * unit, rounds: 1)
            g.pruneFragments(s.minimumStrokeLength)
            g.extendToFrame(width: w, height: h, reach: 14 * unit)
            return g.strokes(sigma: 4 * s.lineSmoothing)
        }
        try cancel.throwIfCancelled()

        let lines = clock.measure("lineArt.layer") { () -> [DrawnLine] in
            let thresholds = [s.outlineThreshold, s.detailThreshold, s.textureThreshold]
            var lines = LineLayering.layered(strokes, thresholds: thresholds, clutter: mask.clutter, width: w)
            if s.outlineEyes {
                let eyes = LineLayering.eyePolygons(input.eyes, width: w, height: h)
                stats.eyes = eyes.count
                lines = LineLayering.addEyes(lines, eyes: eyes, width: w, height: h)
            }
            let colorEdge = Self.boundaryPixels(segmentation.labels.storage, width: w, height: h)
            let first = LineLayering.walls(lines, width: w, height: h)
            stats.endsClosed = LineLayering.closeFreeEnds(
                &lines, walls: first, colorEdge: colorEdge, reach: closeReach.map { $0 * s.gapBridging })
            return lines
        }
        stats.strokes = lines.count
        try cancel.throwIfCancelled()

        let palette = segmentation.palette.map(\.oklab)
        let params = SegmentationParameters(settings: settings, width: w, height: h)
        let need: (UInt32) -> Float = { params.minRadius(digits: LabelSizing.digitCount(colorIndex: $0)) }
        let walls = LineLayering.walls(lines, width: w, height: h)
        var cells = try clock.measure("lineArt.cells") { () throws -> CellMap in
            var cells = try clock.measure("lineArt.cells.split") { () throws -> CellMap in
                let paint = segmentation.labels.storage.map { segmentation.regionColor[Int($0)] }
                return try CellMap.split(paint: paint, walls: walls, cancel: cancel)
            }
            stats.cellsSplit = cells.count
            stats.smallMerged = try clock.measure("lineArt.cells.small") {
                try cells.mergeSmallWithinAreas(need: need, palette: palette, cancel: cancel)
            }
            try cancel.throwIfCancelled()
            clock.measure("lineArt.cells.walls") { cells.assignWalls() }
            let near = CellMap.near(walls.layer, width: w, height: h)
            stats.tinyMerged = try clock.measure("lineArt.cells.tiny") {
                try cells.mergeTiny(need: need, palette: palette, near: near, cancel: cancel)
            }
            if !s.keepColorEdges {
                let tolerance = mergeSteps * Self.paletteStep(palette)
                stats.closeColorsMerged = try clock.measure("lineArt.cells.colors") {
                    try cells.mergeCloseColors(tolerance: tolerance, palette: palette, near: near, cancel: cancel)
                }
            }
            return cells
        }
        try cancel.throwIfCancelled()

        let trimmed = try clock.measure("lineArt.trim") { () throws -> [DrawnLine] in
            let distance = Self.boundaryDistance(cells.label, width: w, height: h)
            try cancel.throwIfCancelled()
            return lines.flatMap { line -> [DrawnLine] in
                guard !line.eye else { return [line] }
                return line.pieces(keeping: Self.near(line, distance: distance, width: w), freeCuts: true)
            }
        }
        try cancel.throwIfCancelled()

        let finalCells = try clock.measure("lineArt.join") { () throws -> CellMap in
            stats.cellsBeforeJoin = cells.count
            if s.samePaint != .split {
                let drawn = LineLayering.walls(trimmed, width: w, height: h)
                let near = CellMap.near(drawn.layer, width: w, height: h)
                try cancel.throwIfCancelled()
                let blocking = s.samePaint == .joinTexture ? [true, true, false] : [true, false, false]
                stats.samePaintJoins = cells.joinSamePaint(near: near, blocking: blocking)
                try cancel.throwIfCancelled()
            }
            // Joins only unite neighbours, so cells stay connected; the loop is a safeguard
            // for wall assignment leaving a stray pixel.
            while !cells.renumber() {
                _ = try cells.mergeTiny(
                    need: need, palette: palette, near: CellMap.near(walls.layer, width: w, height: h), cancel: cancel)
            }
            return cells
        }
        try cancel.throwIfCancelled()
        var final = finalCells
        let kept = final.compactPalette(paletteCount: segmentation.palette.count)
        let split = Segmentation(
            labels: RegionMap(width: w, height: h, storage: final.label.map { UInt32($0) }),
            regionColor: final.color, palette: kept.map { segmentation.palette[$0] }, colorSpace: segmentation.colorSpace)
        stats.cells = final.count
        stats.paintsDropped = segmentation.palette.count - kept.count

        // Which stretches still bound cells after the joins, and which now run inside one.
        var boundary: [DrawnLine] = [], interior: [(DrawnLine, Int)] = []
        let distance = Self.boundaryDistance(final.label, width: w, height: h)
        try cancel.throwIfCancelled()
        for line in trimmed {
            let flags = Self.near(line, distance: distance, width: w)
            boundary += line.pieces(keeping: flags, freeCuts: true)
            for piece in line.pieces(keeping: flags.map { !$0 }, freeCuts: true) {
                interior += Self.byRegion(piece, labels: final.label, width: w, height: h)
            }
        }
        for line in boundary { stats.add(line, interior: false) }
        for (line, _) in interior { stats.add(line, interior: true) }
        return Plan(segmentation: split, boundaryLines: boundary, interiorLines: interior, stats: stats)
    }

    // MARK: - Annotation

    /// Each edge's layer (the line along most of it; `color` where none is) and weight (the
    /// line's strength, or for color edges the paint difference), and the interior strokes.
    static func annotate(_ t: Template, plan: Plan, cancel: CancellationCheck) throws -> TemplateLineArt {
        let w = t.width, h = t.height
        let walls = LineLayering.walls(plan.boundaryLines, width: w, height: h)
        let r2 = annotateNear * annotateNear
        var distances: [[Float]] = []
        for l in 0..<3 {
            try cancel.throwIfCancelled()
            distances.append(DistanceTransform.squaredEDT(width: w, height: h) { walls.layer[$0] == UInt8(l) }.storage)
        }
        try cancel.throwIfCancelled()
        let strength = Self.maxFilter(walls.strength, width: w, height: h, radius: Int(annotateNear.rounded(.up)))
        try cancel.throwIfCancelled()
        var layers = [UInt8](repeating: LineLayer.color.rawValue, count: t.edges.count)
        var weights = [UInt8](repeating: 0, count: t.edges.count)
        for (k, e) in t.edges.enumerated() {
            var covered = SIMD4<Float>(repeating: 0)
            var strengthSum: Float = 0, strengthLength: Float = 0
            let pts = t.points(of: e)
            var previous = pts.first!
            for p in pts.dropFirst() {
                let length = simdLength(p - previous)
                let steps = max(1, Int(length.rounded(.up)))
                for step in 0..<steps {
                    let q = previous + (p - previous) * ((Float(step) + 0.5) / Float(steps))
                    let x = min(max(Int((q.x - 0.5).rounded()), 0), w - 1), y = min(max(Int((q.y - 0.5).rounded()), 0), h - 1)
                    let i = y * w + x
                    var layer = 3
                    for l in 0..<3 where distances[l][i] <= r2 { layer = l; break }
                    let piece = length / Float(steps)
                    covered[layer] += piece
                    if layer < 3 {
                        strengthSum += Float(strength[i]) * piece
                        strengthLength += piece
                    }
                }
                previous = p
            }
            // The drawn layer along most of the edge (the stronger on ties), unless more of the
            // edge has no line at all.
            var drawnBest = -1
            for l in 0..<3 where covered[l] > 0 && (drawnBest < 0 || covered[l] > covered[drawnBest]) { drawnBest = l }
            let best = drawnBest >= 0 && covered[drawnBest] >= covered[3] ? drawnBest : 3
            layers[k] = UInt8(best)
            if best < 3 {
                weights[k] = UInt8(min(max(strengthSum / max(strengthLength, 1e-6), 0), 255).rounded())
            } else if e.right != BoundaryEdge.outside {
                let a = t.palette[Int(t.regions[Int(e.left)].colorIndex)].oklab
                let b = t.palette[Int(t.regions[Int(e.right)].colorIndex)].oklab
                weights[k] = UInt8((min(simdDistance(a, b) / colorWeightReference, 1) * 255).rounded())
            }
        }

        var points: [SIMD2<Float>] = []
        var strokes: [InteriorStroke] = []
        let q = Template.coordinateQuantum
        for (line, region) in plan.interiorLines {
            // A closed line (an eye inside one cell) ends where it starts.
            var keep = Self.simplify(line.points, epsilon: 0.3)
            if line.closed, let first = keep.first { keep.append(first) }
            guard keep.count >= 2 else { continue }
            let start = UInt32(points.count)
            for i in keep {
                let p = line.points[i] + SIMD2(0.5, 0.5)
                let x = min(max(p.x, 0), Float(w)), y = min(max(p.y, 0), Float(h))
                points.append(SIMD2((x / q).rounded() * q, (y / q).rounded() * q))
            }
            let mean = line.strength.reduce(0, +) / Float(line.strength.count)
            let counts = (0..<3).map { l in line.layer.filter { $0 == UInt8(l) }.count }
            let layer = counts.indices.max { counts[$0] != counts[$1] ? counts[$0] < counts[$1] : $0 > $1 }!
            strokes.append(InteriorStroke(
                pointStart: start, pointCount: UInt32(keep.count), layer: UInt8(layer),
                weight: UInt8((min(max(mean, 0), 1) * 255).rounded()), region: UInt32(region)))
        }
        return TemplateLineArt(edgeLayers: layers, edgeWeights: weights, strokePoints: points, strokes: strokes)
    }

    // MARK: - Helpers

    /// Pixels with a 4-neighbour of another label.
    static func boundaryPixels<T: Equatable>(_ labels: [T], width w: Int, height h: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if x + 1 < w && labels[i] != labels[i + 1] { out[i] = true; out[i + 1] = true }
                if y + 1 < h && labels[i] != labels[i + w] { out[i] = true; out[i + w] = true }
            }
        }
        return out
    }

    /// Squared distance from every pixel to the nearest cell-boundary pixel.
    static func boundaryDistance(_ labels: [Int32], width w: Int, height h: Int) -> [Float] {
        let boundary = boundaryPixels(labels, width: w, height: h)
        return DistanceTransform.squaredEDT(width: w, height: h) { boundary[$0] }.storage
    }

    /// Per point of a line, whether a cell boundary runs within `trimNear` (short runs follow
    /// their neighbours: short gaps inside the line close, short pieces go).
    static func near(_ line: DrawnLine, distance: [Float], width w: Int) -> [Bool] {
        let h = distance.count / w
        var keep = line.points.map { p -> Bool in
            let x = min(max(Int(p.x.rounded()), 0), w - 1), y = min(max(Int(p.y.rounded()), 0), h - 1)
            return distance[y * w + x] <= trimNear * trimNear
        }
        let arc = line.arcLength
        let n = keep.count
        for flag in [false, true] {
            var i = 0
            while i < n {
                guard keep[i] == flag else { i += 1; continue }
                var j = i
                while j + 1 < n && keep[j + 1] == flag { j += 1 }
                let interiorRun = line.closed || (i > 0 && j < n - 1)
                if arc[j] - arc[i] < trimMinimum && (interiorRun || flag) {
                    for m in i...j { keep[m] = !flag }
                }
                i = j + 1
            }
        }
        return keep
    }

    /// Splits a line running inside cells where the cell under it changes.
    static func byRegion(_ line: DrawnLine, labels: [Int32], width w: Int, height h: Int) -> [(DrawnLine, Int)] {
        let region = line.points.map { p -> Int32 in
            labels[min(max(Int(p.y.rounded()), 0), h - 1) * w + min(max(Int(p.x.rounded()), 0), w - 1)]
        }
        var out: [(DrawnLine, Int)] = []
        var i = 0
        while i < region.count {
            var j = i
            while j + 1 < region.count && region[j + 1] == region[i] { j += 1 }
            if j > i {
                var piece = line
                piece.points = Array(line.points[i...j])
                piece.strength = Array(line.strength[i...j])
                piece.layer = Array(line.layer[i...j])
                piece.closed = line.closed && i == 0 && j == region.count - 1
                piece.links = []
                if piece.length >= 2 { out.append((piece, Int(region[i]))) }
            }
            i = j + 1
        }
        return out
    }

    /// Median distance from a paint to its nearest other paint.
    static func paletteStep(_ palette: [SIMD3<Float>]) -> Float {
        guard palette.count > 1 else { return 0 }
        var nearest = palette.indices.map { i in
            palette.indices.filter { $0 != i }.map { simdDistance(palette[i], palette[$0]) }.min()!
        }
        nearest.sort()
        let n = nearest.count
        return n % 2 == 1 ? nearest[n / 2] : (nearest[n / 2 - 1] + nearest[n / 2]) / 2
    }

    /// Square max filter of `radius` (separable).
    static func maxFilter(_ values: [UInt8], width w: Int, height h: Int, radius r: Int) -> [UInt8] {
        func pass(_ src: [UInt8], horizontal: Bool) -> [UInt8] {
            var dst = [UInt8](repeating: 0, count: w * h)
            src.withUnsafeBufferPointer { sb in
                dst.withUnsafeMutableBufferPointer { db in
                    let s = UncheckedSendable(sb.baseAddress!), d = UncheckedSendable(db.baseAddress!)
                    Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                        for y in rows {
                            for x in 0..<w {
                                var m: UInt8 = 0
                                if horizontal {
                                    for xx in max(0, x - r)...min(w - 1, x + r) { m = max(m, s.value[y * w + xx]) }
                                } else {
                                    for yy in max(0, y - r)...min(h - 1, y + r) { m = max(m, s.value[yy * w + x]) }
                                }
                                d.value[y * w + x] = m
                            }
                        }
                    }
                }
            }
            return dst
        }
        return pass(pass(values, horizontal: true), horizontal: false)
    }

    /// Douglas–Peucker: indices of the points kept (the ends always; closed lines keep their
    /// first point and the point farthest from it).
    static func simplify(_ pts: [SIMD2<Float>], epsilon: Float) -> [Int] {
        let n = pts.count
        guard n >= 3 else { return Array(0..<n) }
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true
        var stack = [(0, n - 1)]
        while let (i, j) = stack.popLast() {
            guard j > i + 1 else { continue }
            let a = pts[i], ab = pts[j] - a
            let length = simdLength(ab)
            var best = -1
            var bestDistance: Float = 0
            for k in (i + 1)..<j {
                let v = pts[k] - a
                let d = length < 1e-9 ? simdLength(v) : abs(v.x * ab.y - v.y * ab.x) / length
                if d > bestDistance { bestDistance = d; best = k }
            }
            if bestDistance > epsilon {
                keep[best] = true
                stack.append((i, best))
                stack.append((best, j))
            }
        }
        return (0..<n).filter { keep[$0] }
    }
}

/// What layered line art did (`pbn`'s `stats.json` `lineArt` section). Lengths in canvas units.
public struct LineArtStats: Sendable, Codable, Equatable {
    /// Regions of the color segmentation the lines split (a classic template's regions).
    public var segmentationRegions = 0
    /// Lines after tracing, layering, eyes and closing.
    public var strokes = 0
    /// Eyes outlined.
    public var eyes = 0
    /// Free ends extended to a line, paint boundary or the frame.
    public var endsClosed = 0
    /// Cells right after splitting the segmentation along the lines.
    public var cellsSplit = 0
    /// Cells too small for their number merged inside their enclosed area.
    public var smallMerged = 0
    /// Cells too small for their number merged across a line.
    public var tinyMerged = 0
    /// Line-free neighbours merged for close paints (`keepColorEdges` off).
    public var closeColorsMerged = 0
    public var cellsBeforeJoin = 0
    /// Same-paint neighbours joined (`samePaint`).
    public var samePaintJoins = 0
    /// Cells of the template.
    public var cells = 0
    /// Paints no cell used any more.
    public var paintsDropped = 0
    /// Drawn line along cell boundaries per layer (outline, detail, texture).
    public var boundaryLength: [Float] = [0, 0, 0]
    /// Drawn line inside cells per layer.
    public var interiorLength: [Float] = [0, 0, 0]
    public var interiorStrokes = 0

    public init() {}

    mutating func add(_ line: DrawnLine, interior: Bool) {
        guard line.points.count > 1 else { return }
        for k in 1..<line.points.count {
            let l = Int(min(line.layer[k - 1], 2))
            let d = simdLength(line.points[k] - line.points[k - 1])
            if interior { interiorLength[l] += d } else { boundaryLength[l] += d }
        }
        if interior { interiorStrokes += 1 }
    }
}
