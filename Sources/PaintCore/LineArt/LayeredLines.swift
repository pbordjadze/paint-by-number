/// Line art: an edge map (with eyes, subjects and contours) turned into the cells of a coloring
/// book, bounded by its drawing, each line in a `LineLayer` by its strength. `LineArtSettings`
/// holds every knob.
///
/// Stages (timed as `lineArt.*`):
/// 1. `detect`: the edge map resampled to the working size, its ridges, hysteresis and
///    thinning (`LineDetection`). Nothing below the detail threshold is extracted: a coloring
///    book has no faint lines, so the texture layer stays empty.
/// 2. `trace`: the centerlines as a graph, cleaned (bubbles, spurs, specks, components under
///    `minimumStrokeLength`), gaps up to `gapBridging` bridged, ends led into the frame, and
///    joined into strokes smoothed by `lineSmoothing` (`StrokeGraph`).
/// 3. `layer`: per point, hysteresis along the stroke against the outline and detail
///    thresholds, the outline threshold rising where lines crowd (`LineLayering`); stretches
///    below detail are cut out. Eyes (`outlineEyes`) replace the lines inside them with their
///    contours and irises as outlines and promote the lines around them; the subjects'
///    silhouettes (`outlineObjects`) fill the gaps in the drawing as outlines
///    (`LineLayering.addObjects`). Lines on the writing (`Writing`, traced from the photo
///    before segmenting) are its smudged copy and go. The painter's edits (`LineEdits`) join:
///    drawn lines as outlines, erased places taken out. Free ends reach for the nearest line,
///    paint boundary or frame (`gapBridging` × 1.6 / 1.2 by layer), so open strokes close
///    cells, but never into a place erased after their line was drawn.
/// 4. `cells`: the segmentation split along the rasterized lines (`CellMap`): every cell keeps
///    its paint and holds its number; `keepColorEdges` off merges line-free neighbours whose
///    paints are within two palette steps.
/// 5. `join`: same-paint neighbours join per `samePaint` (by default across everything but
///    outlines), and the lines that end up inside a cell become interior strokes (stretches
///    shorter than `LineLayering.minimumRun` are a boundary stretch's end point or a merged
///    tiny cell's sliver, not drawing, and go): a stretch that bounds no cell is still drawn,
///    the book being a drawing. Paints no cell uses are dropped, cells renumbered. The writing
///    is drawn inside the cells it crosses: it bounds none, so letters never become cells to
///    number.
/// After vectorizing, `annotate` gives each boundary edge the layer of the line along it
/// (`color` where only the paint changes) and a weight, and stamps the template's line art as
/// a coloring book. Near the painter's edits an edge only partly along a line is drawn only
/// there, as interior strokes over an undrawn edge.
///
/// Lengths are canvas units (working pixels). `LineLayering.longOutline`, `objectNear`,
/// `objectMinimumStretch` and `LineDetection.clutterWindow` are given for a 1500-px canvas and
/// scale with its long side; the tracing reaches (`popBubbles` perimeter, `pruneSpurs`,
/// `pruneFragments`, `extendToFrame`) and the ridge Hessian scale with `unit`, the working
/// pixels per edge-map pixel (at least 1; `LineDetection.ridges` clamps it);
/// `minimumStrokeLength`, `gapBridging`, `minimumRun`, `trimNear`, `trimMinimum`,
/// `contourReach`, `annotateNear` and the `lineSmoothing` sigma do not scale.
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
    /// How far (working pixels) a stroke may run from a contour's ridge and still read its
    /// strength for the outline threshold (`LineArtInput.contours`).
    static let contourReach = 2

    struct Plan {
        var segmentation: Segmentation
        /// Line stretches that bound cells (for the edges' layers).
        var boundaryLines: [DrawnLine]
        /// Lines drawn inside a cell, with that cell.
        var interiorLines: [(line: DrawnLine, region: Int)]
        var stats: LineArtStats
        /// Where the painter's edits were (`LineEdits.footprint`); nil without any.
        var edited: [Bool]? = nil
        /// The stretches of the painter's lines drawn inside a cell, in canvas units: numbers
        /// keep off them (`LabelKeepOut`), as the cell's own pole may lie right on one.
        var drawnInterior: [[SIMD2<Float>]] = []
    }

    static func apply(
        _ segmentation: Segmentation, input: LineArtInput, importance: [Float]?, settings: GenerationSettings,
        writing: Writing? = nil, cancel: CancellationCheck, clock: StageClock
    ) throws -> Plan {
        let s = settings.normalized.lineArt
        // A coloring book has no faint lines: nothing is drawn below the detail threshold, so the
        // texture layer is empty.
        let thresholds = [s.outlineThreshold, s.detailThreshold, s.detailThreshold]
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
                threshold: thresholds[2], cancel: cancel)
            let clutter = try LineDetection.clutter(mask, width: w, height: h, cancel: cancel)
            return (mask, ridges.smooth, clutter)
        }
        try cancel.throwIfCancelled()
        // The contour map's strength, smoothed like the lines' and widened by two pixels, so a
        // stroke the drawing traced a little off the contour's ridge still reads the contour.
        let contourStrength: [Float]? = try input.contours.map { contours in
            let field = LineDetection.strength(contours, width: w, height: h)
            try cancel.throwIfCancelled()
            let smooth = Gaussian.filter(field, width: w, height: h, sigma: LineDetection.responseSigma, orderX: 0, orderY: 0)
            let levels = smooth.map { UInt8(min(max($0, 0), 1) * 255 + 0.5) }
            return Self.maxFilter(levels, width: w, height: h, radius: contourReach).map { Float($0) / 255 }
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

        var edits: LineEdits.Applied?
        let lines = clock.measure("lineArt.layer") { () -> [DrawnLine] in
            var lines = LineLayering.layered(
                strokes, thresholds: thresholds, clutter: mask.clutter, width: w, contours: contourStrength)
            if s.outlineEyes {
                let eyes = LineLayering.pixelPolygons(input.eyes, width: w, height: h)
                stats.eyes = eyes.count
                lines = LineLayering.addEyes(lines, eyes: eyes, width: w, height: h)
            }
            if s.outlineObjects {
                let objects = LineLayering.pixelPolygons(input.objects, width: w, height: h)
                stats.objects = objects.count
                let added = LineLayering.addObjects(lines, objects: objects, width: w, height: h)
                stats.objectStretches = added.count
                lines += added
            }
            if let near = writing?.nearInk, !near.isEmpty {
                lines = lines.flatMap { line in
                    line.pieces(keeping: line.points.map { !near[LineLayering.pixelIndex(of: $0, width: w, height: h)] }, freeCuts: false)
                }
            }
            if !input.edits.isEmpty {
                let applied = LineEdits.apply(input.edits, to: lines, width: w, height: h, reach: closeReach[0] * s.gapBridging)
                lines = applied.lines
                stats.drawnLines = applied.drawn
                stats.erasures = applied.erasures.count
                edits = applied
            }
            let colorEdge = Self.boundaryPixels(segmentation.labels.storage, width: w, height: h)
            let first = LineLayering.walls(lines, width: w, height: h)
            // No end reaches into a place erased after its line was drawn.
            var blocked: ((Int, Int) -> Bool)?
            if let origin = edits?.origin, let blockedBy = edits?.blockedBy { blocked = { blockedBy[$1] > origin[$0] } }
            stats.endsClosed = LineLayering.closeFreeEnds(
                &lines, walls: first, colorEdge: colorEdge, reach: closeReach.map { $0 * s.gapBridging }, blocked: blocked)
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

        let finalCells = try clock.measure("lineArt.join") { () throws -> CellMap in
            stats.cellsBeforeJoin = cells.count
            if s.samePaint != .split {
                let drawn = LineLayering.walls(lines, width: w, height: h)
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
        var boundary: [DrawnLine] = [], interior: [(DrawnLine, Int)] = [], drawnInterior: [[SIMD2<Float>]] = []
        let distance = Self.boundaryDistance(final.label, width: w, height: h)
        try cancel.throwIfCancelled()
        for (k, line) in lines.enumerated() {
            let flags = Self.near(line, distance: distance, width: w)
            boundary += line.pieces(keeping: flags, freeCuts: true)
            let drawn = (edits?.origin[k] ?? -1) >= 0
            // A piece shorter than the layering's minimum run is a boundary stretch's end
            // point (every piece takes one point beyond its run) or the sliver a merged tiny
            // cell left, not a line drawn inside the cell.
            for piece in line.pieces(keeping: flags.map { !$0 }, freeCuts: true) where piece.length >= LineLayering.minimumRun {
                interior += Self.byRegion(piece, labels: final.label, width: w, height: h)
                if drawn { drawnInterior.append(piece.points.map { $0 + SIMD2(0.5, 0.5) }) }
            }
        }
        if let writing {
            stats.writingAreas = writing.areas
            stats.writingMarks = writing.marks
            stats.writing = writing.report
            let written = edits.map { LineEdits.cut(writing.lines, by: $0, width: w, height: h) } ?? writing.lines
            for line in written {
                stats.writingLength += line.length
                interior += Self.byRegion(line, labels: final.label, width: w, height: h)
            }
        }
        for line in boundary { stats.add(line, interior: false) }
        for (line, _) in interior { stats.add(line, interior: true) }
        let edited = edits.map { LineEdits.footprint($0, lines: lines, near: annotateNear + 1, width: w, height: h) }
        return Plan(
            segmentation: split, boundaryLines: boundary, interiorLines: interior, stats: stats, edited: edited,
            drawnInterior: drawnInterior)
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
        // Near the painter's edits: each sample of an edge, and the drawn stretches of edges a
        // line runs along only in part.
        var samples: [EdgeSample] = []
        var partial: [EdgeRun] = []
        for (k, e) in t.edges.enumerated() {
            var covered = SIMD4<Float>(repeating: 0)
            var strengthSum: Float = 0, strengthLength: Float = 0
            let pts = t.points(of: e)
            let sampling = plan.edited != nil && e.right != BoundaryEdge.outside
            var edited = false
            samples.removeAll(keepingCapacity: true)
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
                    if sampling {
                        samples.append(EdgeSample(position: q, layer: layer, length: piece, strength: Float(strength[i])))
                        edited = edited || plan.edited![i]
                    }
                }
                previous = p
            }
            // The drawn layer along most of the edge (the stronger on ties), unless more of the
            // edge has no line at all.
            var drawnBest = -1
            for l in 0..<3 where covered[l] > 0 && (drawnBest < 0 || covered[l] > covered[drawnBest]) { drawnBest = l }
            var best = drawnBest >= 0 && covered[drawnBest] >= covered[3] ? drawnBest : 3
            if edited {
                // Drawn where a line runs along it: whole, not at all, or in stretches over an
                // undrawn edge.
                let runs = Self.drawnRuns(samples)
                if runs.isEmpty {
                    best = 3
                } else if runs.count == 1 && runs[0] == 0...(samples.count - 1) {
                    best = drawnBest
                } else {
                    best = 3
                    for run in runs {
                        partial.append(Self.edgeRun(samples[run], from: run.lowerBound == 0 ? pts.first : nil,
                                                    to: run.upperBound == samples.count - 1 ? pts.last : nil, region: e.left))
                    }
                }
            }
            layers[k] = UInt8(best)
            if best < 3 {
                weights[k] = UInt8(min(max(strengthSum / max(strengthLength, 1e-6), 0), 255).rounded())
            } else if e.right != BoundaryEdge.outside {
                let a = t.palette[Int(t.regions[Int(e.left)].colorIndex)].oklab
                let b = t.palette[Int(t.regions[Int(e.right)].colorIndex)].oklab
                weights[k] = UInt8((min(ColorScience.distance(a, b) / colorWeightReference, 1) * 255).rounded())
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
        for run in partial {
            let keep = Self.simplify(run.points, epsilon: 0.3)
            guard keep.count >= 2 else { continue }
            let start = UInt32(points.count)
            for i in keep {
                let p = run.points[i]
                let x = min(max(p.x, 0), Float(w)), y = min(max(p.y, 0), Float(h))
                points.append(SIMD2((x / q).rounded() * q, (y / q).rounded() * q))
            }
            strokes.append(InteriorStroke(
                pointStart: start, pointCount: UInt32(keep.count), layer: run.layer, weight: run.weight, region: run.region))
        }
        return TemplateLineArt(edgeLayers: layers, edgeWeights: weights, strokePoints: points, strokes: strokes, style: .coloringBook)
    }

    /// A step along a template edge (`annotate`): where, the layer of the line within reach
    /// (3: none), the step's length and the line's strength there.
    struct EdgeSample {
        var position: SIMD2<Float>
        var layer: Int
        var length: Float
        var strength: Float
    }

    /// A drawn stretch of an edge, drawn as an interior stroke of the edge's left region.
    struct EdgeRun {
        var points: [SIMD2<Float>]
        var layer: UInt8
        var weight: UInt8
        var region: UInt32
    }

    /// The sample ranges of an edge a line runs along: gaps in a line shorter than
    /// `LineLayering.minimumRun` (where it meets a junction, or runs a little off the edge)
    /// are drawn, and stretches that short beside undrawn ones are not.
    static func drawnRuns(_ samples: [EdgeSample]) -> [ClosedRange<Int>] {
        var drawn = samples.map { $0.layer < 3 }
        guard drawn.contains(true) else { return [] }
        func runs() -> [(range: ClosedRange<Int>, drawn: Bool, length: Float)] {
            var out: [(range: ClosedRange<Int>, drawn: Bool, length: Float)] = []
            var i = 0
            while i < drawn.count {
                var j = i, length = samples[i].length
                while j + 1 < drawn.count && drawn[j + 1] == drawn[i] {
                    j += 1
                    length += samples[j].length
                }
                out.append((i...j, drawn[i], length))
                i = j + 1
            }
            return out
        }
        for run in runs() where !run.drawn && run.length < LineLayering.minimumRun {
            for i in run.range { drawn[i] = true }
        }
        let cleaned = runs()
        if cleaned.count > 1 {
            for run in cleaned where run.drawn && run.length < LineLayering.minimumRun {
                for i in run.range { drawn[i] = false }
            }
        }
        return runs().filter(\.drawn).map(\.range)
    }

    /// The stroke along `samples`, from the edge's end points where it reaches them: the
    /// layer drawn along most of it (the stronger on ties) and its mean strength.
    static func edgeRun(
        _ samples: ArraySlice<EdgeSample>, from start: SIMD2<Float>?, to end: SIMD2<Float>?, region: UInt32
    ) -> EdgeRun {
        var points = samples.map(\.position)
        if let start { points.insert(start, at: 0) }
        if let end { points.append(end) }
        var covered = SIMD3<Float>(repeating: 0)
        var strengthSum: Float = 0, strengthLength: Float = 0
        for sample in samples where sample.layer < 3 {
            covered[sample.layer] += sample.length
            strengthSum += sample.strength * sample.length
            strengthLength += sample.length
        }
        var layer = 0
        for l in 1..<3 where covered[l] > covered[layer] { layer = l }
        let weight = UInt8(min(max(strengthSum / max(strengthLength, 1e-6), 0), 255).rounded())
        return EdgeRun(points: points, layer: UInt8(layer), weight: weight, region: region)
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
        var keep = line.points.map { distance[LineLayering.pixelIndex(of: $0, width: w, height: h)] <= trimNear * trimNear }
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
        let region = line.points.map { labels[LineLayering.pixelIndex(of: $0, width: w, height: h)] }
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
            palette.indices.filter { $0 != i }.map { ColorScience.distance(palette[i], palette[$0]) }.min()!
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
