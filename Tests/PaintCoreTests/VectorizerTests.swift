import Foundation
import Testing
@testable import PaintCore

@Suite("Vectorizer")
struct VectorizerTests {

    // MARK: - Helpers

    static func length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }

    /// Label map from rows of palette classes; regions are their 4-connected components.
    static func segmentation(_ rows: [[UInt32]]) -> Segmentation {
        let h = rows.count, w = rows.first?.count ?? 0
        return segmentation(width: w, height: h, classes: rows.flatMap { $0 })
    }

    static func segmentation(width: Int, height: Int, classes: [UInt32]) -> Segmentation {
        let cc = ConnectedComponents.label(Grid(width: width, height: height, storage: classes))
        let colors = Int(classes.max() ?? 0) + 1
        let palette = (0..<colors).map { i in
            PaletteColor(oklab: SIMD3(0.3 + 0.6 * Float(i) / Float(max(1, colors)), 0.05, -0.05), space: .sRGB)
        }
        return Segmentation(labels: cc.labels, regionColor: cc.classOf, palette: palette, colorSpace: .sRGB)
    }

    static func vectorize(_ s: Segmentation, smoothness: Float = 0.5) throws -> Template {
        var settings = GenerationSettings()
        settings.smoothness = smoothness
        return try Vectorizer.vectorize(s, settings: settings, cancel: .none, clock: StageClock())
    }

    /// Random blob map: coarse random cells, nearest upscaled, majority-filtered into
    /// organic shapes, plus salt noise for single-pixel regions.
    static func blobMap(width: Int, height: Int, colors: UInt32, cell: Int, noise: Float, seed: UInt64) -> Segmentation {
        var rng = SplitMix64(seed: seed)
        let cw = (width + cell - 1) / cell + 1, ch = (height + cell - 1) / cell + 1
        let coarse = (0..<(cw * ch)).map { _ in UInt32(rng.next() % UInt64(colors)) }
        var classes = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let jx = Int(rng.next() % 3) - 1, jy = Int(rng.next() % 3) - 1
                let cx = min(cw - 1, max(0, (x + jx * cell / 3) / cell)), cy = min(ch - 1, max(0, (y + jy * cell / 3) / cell))
                classes[y * width + x] = coarse[cy * cw + cx]
            }
        }
        for _ in 0..<2 {
            var next = classes
            for y in 0..<height {
                for x in 0..<width {
                    var counts = [Int](repeating: 0, count: Int(colors))
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let xx = min(width - 1, max(0, x + dx)), yy = min(height - 1, max(0, y + dy))
                            counts[Int(classes[yy * width + xx])] += 1
                        }
                    }
                    next[y * width + x] = UInt32(counts.indices.max { counts[$0] < counts[$1] }!)
                }
            }
            classes = next
        }
        for i in 0..<classes.count where rng.nextFloat() < noise { classes[i] = UInt32(rng.next() % UInt64(colors)) }
        return segmentation(width: width, height: height, classes: classes)
    }

    /// Checks every invariant the rest of the app relies on.
    static func expectValid(_ t: Template, _ s: Segmentation, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let report = t.validate()
        #expect(report.isValid, "\(report)", sourceLocation: sourceLocation)
        #expect(t.regions.count == s.regionCount, sourceLocation: sourceLocation)
        #expect(t.regionMap == s.labels, sourceLocation: sourceLocation)
        #expect(t.regions.map(\.colorIndex) == s.regionColor, sourceLocation: sourceLocation)
        #expect(t.palette == s.palette, sourceLocation: sourceLocation)
        // Every edge separates two distinct regions and is stored with left < right.
        for e in t.edges { #expect(e.left < e.right, sourceLocation: sourceLocation) }
        // Every region has exactly one outer ring, listed first, and at least one label.
        for r in t.regions {
            #expect(r.ringCount >= 1 && !t.rings[Int(r.ringStart)].isHole, sourceLocation: sourceLocation)
            for k in 1..<Int(r.ringCount) { #expect(t.rings[Int(r.ringStart) + k].isHole, sourceLocation: sourceLocation) }
            #expect(r.labelCount >= 1, sourceLocation: sourceLocation)
            #expect(r.indexCount >= 3 && r.indexCount % 3 == 0, sourceLocation: sourceLocation)
        }
        let total = t.regions.reduce(0.0) { $0 + Double($1.area) }
        #expect(abs(total - Double(t.width * t.height)) < 1e-3 * Double(t.width * t.height), sourceLocation: sourceLocation)
        #expect(try Template(encoded: t.encoded()) == t, sourceLocation: sourceLocation)
    }

    /// Point sampling: every sample lies in exactly one region polygon (fills tile the
    /// canvas without gaps or overlaps), and pixels deep inside a region map to it.
    static func expectTiling(_ t: Template, samples: Int, seed: UInt64, sourceLocation: SourceLocation = #_sourceLocation) {
        let polys = (0..<t.regions.count).map { t.polygons(ofRegion: $0) }
        let boxes = polys.map { rings -> (SIMD2<Float>, SIMD2<Float>) in
            var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
            for p in rings[0] { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            return (lo, hi)
        }
        let depth = DistanceTransform.interiorDistance(labels: t.regionMap)
        var rng = SplitMix64(seed: seed)
        var failures = 0
        for _ in 0..<samples {
            let p = SIMD2(rng.nextFloat() * Float(t.width), rng.nextFloat() * Float(t.height))
            var owners: [Int] = []
            for r in 0..<polys.count where p.x >= boxes[r].0.x && p.x <= boxes[r].1.x && p.y >= boxes[r].0.y && p.y <= boxes[r].1.y {
                var inside = false
                for ring in polys[r] where Template.contains(ring, p) { inside.toggle() }
                if inside { owners.append(r) }
            }
            let px = min(t.width - 1, Int(p.x)), py = min(t.height - 1, Int(p.y))
            if owners.count != 1 || (depth[px, py] >= 2.5 && owners[0] != Int(t.regionMap[px, py])) { failures += 1 }
        }
        #expect(failures == 0, "\(failures) of \(samples) samples misassigned", sourceLocation: sourceLocation)
    }

    // MARK: - Synthetic maps

    @Test func singleRegion() throws {
        let s = Self.segmentation(Array(repeating: Array(repeating: 0, count: 5), count: 4))
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        #expect(t.edges.count == 1)
        #expect(t.edges[0].right == BoundaryEdge.outside)
        // Closed border loop: the canvas corners, first point repeated.
        #expect(Array(t.points(of: t.edges[0])) == [SIMD2(0, 0), SIMD2(5, 0), SIMD2(5, 4), SIMD2(0, 4), SIMD2(0, 0)])
        #expect(t.regions[0].area == 20)
        #expect(t.regions[0].bounds == PixelBounds(minX: 0, minY: 0, maxX: 5, maxY: 4))
        let label = t.labels[0]
        #expect(abs(label.position.x - 2.5) < 0.3 && abs(label.position.y - 2) < 0.3)
        #expect(abs(label.radius - 2) < 0.3)
    }

    @Test func orientationConvention() throws {
        // Left half region 0, right half region 1: the shared edge is vertical with
        // region 0 on its `left`, i.e. cross(direction, x − p) > 0 on region 0's side.
        let s = Self.segmentation([[0, 0, 1, 1], [0, 0, 1, 1], [0, 0, 1, 1]])
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        let shared = t.edges.filter { $0.right != BoundaryEdge.outside }
        #expect(shared.count == 1)
        let e = shared[0], pts = t.points(of: e)
        let a = pts[pts.startIndex], b = pts[pts.endIndex - 1]
        let d = b - a
        let leftCentre = SIMD2<Float>(1, 1.5)  // centre of region 0
        let cross = d.x * (leftCentre.y - a.y) - d.y * (leftCentre.x - a.x)
        #expect(e.left == 0 && cross > 0)
        // Outer rings have positive shoelace area.
        for r in 0..<t.regions.count { #expect(Template.signedArea(t.polygons(ofRegion: r)[0]) > 0) }
    }

    @Test func nestedIslands() throws {
        // Region A contains B, which contains C: closed junction-free edges.
        var rows = Array(repeating: Array(repeating: UInt32(0), count: 20), count: 20)
        for y in 3..<17 { for x in 3..<17 { rows[y][x] = 1 } }
        for y in 7..<13 { for x in 7..<13 { rows[y][x] = 2 } }
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        Self.expectTiling(t, samples: 3000, seed: 1)
        #expect(t.regions.map(\.ringCount) == [2, 2, 1])
        for e in t.edges {
            let pts = t.points(of: e)
            #expect(pts.first == pts.last, "all edges are closed loops")
        }
        // The 6×6 island is small enough for its corners to be rounded off.
        #expect(abs(t.regions[2].area - 36) < 6)
        #expect(abs(t.regions[1].area + t.regions[2].area - 196) < 3)
    }

    @Test func regionWithManyHoles() throws {
        var rows = Array(repeating: Array(repeating: UInt32(0), count: 40), count: 30)
        let holes = [(4, 4, 6), (15, 5, 8), (28, 3, 5), (6, 18, 7), (22, 17, 9)]
        for (i, (hx, hy, size)) in holes.enumerated() {
            for y in hy..<(hy + size) { for x in hx..<(hx + size) { rows[y][x] = UInt32(1 + i % 3) } }
        }
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        Self.expectTiling(t, samples: 3000, seed: 2)
        #expect(t.regions[0].ringCount == 6)
        #expect(t.labels(ofRegion: 0).allSatisfy { label in
            // Not inside any hole.
            (1..<t.regions.count).allSatisfy { !Template.contains(t.polygons(ofRegion: $0)[0], label.position) }
        })
    }

    @Test func checkerboard() throws {
        let rows = (0..<8).map { y in (0..<9).map { x in UInt32((x + y) % 2) } }
        let s = Self.segmentation(rows)
        #expect(s.regionCount == 72)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        Self.expectTiling(t, samples: 2000, seed: 3)
        // Every interior lattice corner is a junction, so every edge is a single unit step.
        for e in t.edges where e.right != BoundaryEdge.outside { #expect(e.pointCount == 2) }
    }

    @Test func diagonalTouches() throws {
        // Two holes touching diagonally, and a region meeting itself at a corner.
        let rows: [[UInt32]] = [
            [0, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 2, 2, 0],
            [0, 0, 1, 0, 2, 0, 0],
            [0, 0, 0, 0, 0, 2, 0],
            [0, 3, 3, 0, 0, 0, 0],
            [0, 3, 0, 3, 3, 0, 0],
            [0, 3, 3, 3, 0, 0, 0],
        ]
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        Self.expectTiling(t, samples: 3000, seed: 4)
    }

    @Test func borderTouchingRegions() throws {
        let rows = (0..<12).map { y in (0..<16).map { x in UInt32(x < 5 ? 0 : (y < 6 ? 1 : 2)) } }
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        // Border edges lie exactly on the canvas border.
        for e in t.edges where e.right == BoundaryEdge.outside {
            for p in t.points(of: e) {
                #expect(p.x == 0 || p.y == 0 || p.x == 16 || p.y == 12)
            }
        }
        // Each region's outer ring includes border edges.
        for r in 0..<t.regions.count {
            let ring = t.rings[Int(t.regions[r].ringStart)]
            let refs = t.ringEdges[Int(ring.edgeStart)..<Int(ring.edgeStart + ring.edgeCount)]
            #expect(refs.contains { t.edges[Int($0.edge)].right == BoundaryEdge.outside })
        }
    }

    @Test func tinyImages() throws {
        for rows in [[[UInt32(0)]], [[0, 1, 1, 0, 2, 2, 2]], [[0], [1], [1], [0]], [[0, 1], [1, 0]], [[0, 1, 0], [1, 0, 1]]] {
            let s = Self.segmentation(rows)
            let t = try Self.vectorize(s)
            try Self.expectValid(t, s)
            Self.expectTiling(t, samples: 300, seed: 5)
        }
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func randomBlobMaps(seed: UInt64) throws {
        let noise: Float = seed % 2 == 0 ? 0 : 0.02
        let s = Self.blobMap(width: 70 + Int(seed) * 7, height: 50, colors: 3 + UInt32(seed % 4), cell: 6 + Int(seed % 3) * 4, noise: noise, seed: seed)
        for smoothness in [Float(0), 0.5, 1] {
            let t = try Self.vectorize(s, smoothness: smoothness)
            try Self.expectValid(t, s)
            Self.expectTiling(t, samples: 1500, seed: seed)
        }
    }

    @Test func deterministic() throws {
        let s = Self.blobMap(width: 90, height: 60, colors: 5, cell: 8, noise: 0.01, seed: 42)
        let a = try Self.vectorize(s), b = try Self.vectorize(s)
        #expect(a == b)
        #expect(a.encoded() == b.encoded())
    }

    // MARK: - Geometry quality

    @Test func digitalStraightLinesStayStraight() throws {
        // Half-planes split by digitized lines of various slopes: each boundary is a
        // single straight segment after fitting.
        for (num, den) in [(1, 3), (2, 5), (1, 1), (3, 7), (1, 9)] {
            let w = 60, h = 40
            let rows = (0..<h).map { y in (0..<w).map { x in UInt32(y * den > x * num + 7 * den ? 1 : 0) } }
            let s = Self.segmentation(rows)
            let t = try Self.vectorize(s)
            try Self.expectValid(t, s)
            let interior = t.edges.filter { $0.right != BoundaryEdge.outside }
            #expect(interior.count == 1)
            #expect(interior.allSatisfy { $0.pointCount == 2 }, "slope \(num)/\(den)")
        }
    }

    @Test func circlesAreRound() throws {
        let w = 120, h = 120, r = 40.0
        func inside(_ x: Int, _ y: Int) -> Bool {
            let dx = Double(x) + 0.5 - 60, dy = Double(y) + 0.5 - 60
            return dx * dx + dy * dy < r * r
        }
        let rows = (0..<h).map { y in (0..<w).map { x in UInt32(inside(x, y) ? 1 : 0) } }
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        let disc = t.regions.firstIndex { $0.colorIndex == 1 }!
        let ring = t.polygons(ofRegion: disc)[0]
        let radii = ring.map { Double(Self.length($0 - SIMD2(60, 60))) }
        #expect(radii.allSatisfy { abs($0 - r) < 0.6 })
        #expect(abs(Double(t.regions[disc].area) - Double.pi * r * r) < 0.02 * Double.pi * r * r)
        // Round, not a polygon: the largest turn between consecutive segments is small.
        var maxTurn = 0.0
        for i in 0..<ring.count {
            let a = ring[(i + ring.count - 1) % ring.count], b = ring[i], c = ring[(i + 1) % ring.count]
            let u: SIMD2<Float> = b - a, v: SIMD2<Float> = c - b
            maxTurn = max(maxTurn, Double(abs(atan2(u.x * v.y - u.y * v.x, (u * v).sum()))))
        }
        #expect(maxTurn < 0.35)
        // The pole of a disc is its centre.
        #expect(Self.length(t.labels(ofRegion: disc).first!.position - SIMD2(60, 60)) < 1.5)
    }

    @Test func rectangleCornersStayCrisp() throws {
        let rows = (0..<50).map { y in (0..<70).map { x in UInt32(x >= 10 && x < 60 && y >= 10 && y < 40 ? 1 : 0) } }
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        let rect = t.regions.firstIndex { $0.colorIndex == 1 }!
        let ring = t.polygons(ofRegion: rect)[0]
        #expect(Set(ring) == [SIMD2(10, 10), SIMD2(60, 10), SIMD2(60, 40), SIMD2(10, 40)])
        #expect(t.regions[rect].area == 1500)
    }

    @Test func cleanShapesNeedNoFallbacks() throws {
        // Discs, a rotated rectangle and a 3-px diagonal stripe: every edge keeps its faired
        // curve (no repair fell back to cruder geometry).
        let w = 120, h = 90
        var classes = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let fx = Double(x) + 0.5, fy = Double(y) + 0.5
                var c: UInt32 = 0
                if (fx - 30) * (fx - 30) + (fy - 30) * (fy - 30) < 400 { c = 1 }
                if (fx - 30) * (fx - 30) + (fy - 30) * (fy - 30) < 64 { c = 2 }
                let u = (fx - 85) * 0.9 + (fy - 30) * 0.44, v = -(fx - 85) * 0.44 + (fy - 30) * 0.9
                if abs(u) < 20 && abs(v) < 11 { c = 3 }
                if abs(fy - 0.6 * fx - 40) < 2 { c = 4 }
                classes[y * w + x] = c
            }
        }
        let s = Self.segmentation(width: w, height: h, classes: classes)
        for smoothness in [Float(0), 0.5, 1] {
            try Self.expectValid(try Self.vectorize(s, smoothness: smoothness), s)
            var settings = GenerationSettings()
            settings.smoothness = smoothness
            let stats = try Vectorizer.vectorizeWithStats(s, settings: settings, cancel: .none, clock: StageClock()).stats
            #expect(stats == VectorStats())
        }
    }

    // MARK: - Label room

    /// The room each region's label must keep (`LabelRoom.minRadius`), recomputed from the
    /// raster: the tolerance times its raster minimum, at most the pixel outline's clearance.
    static func requiredRoom(_ s: Segmentation, settings: GenerationSettings) -> (seeds: [SIMD2<Double>], radius: [Float]) {
        let map = s.labels
        let raster = RasterStats(
            labels: map, distance: DistanceTransform.interiorDistance(labels: map), regionCount: s.regionCount)
        let p = SegmentationParameters(settings: settings, width: map.width, height: map.height)
        var seeds: [SIMD2<Double>] = [], radius: [Float] = []
        for r in 0..<s.regionCount {
            let pixel = Int(raster.bestPixel[r])
            let digits = LabelSizing.digitCount(colorIndex: s.regionColor[r])
            let required = SegmentationParameters.vectorRadiusTolerance * p.minRadius(digits: digits)
            seeds.append(SIMD2(Double(pixel % map.width) + 0.5, Double(pixel / map.width) + 0.5))
            radius.append(min(required, RasterStats.latticeClearance(map, pixel: pixel, region: UInt32(r), limit: required)))
        }
        return (seeds, radius)
    }

    @Test func labelRoomHoldsAfterSmoothing() throws {
        // Organic blobs with salt noise: smoothing shaves thin regions and specks, and the
        // edges near their labels fall back until every label has its room again.
        let s = Self.blobMap(width: 120, height: 90, colors: 12, cell: 5, noise: 0.02, seed: 7)
        var demoted = 0
        for smoothness in [Float(0), 0.5, 1] {
            var settings = GenerationSettings()
            settings.smoothness = smoothness
            let (t, stats) = try Vectorizer.vectorizeWithStats(s, settings: settings, cancel: .none, clock: StageClock())
            try Self.expectValid(t, s)
            let room = Self.requiredRoom(s, settings: settings)
            for r in t.regions.indices {
                #expect(t.regions[r].inscribedRadius >= room.radius[r] - 1e-4, "region \(r), smoothness \(smoothness)")
                #expect(t.labels(ofRegion: r).first?.radius == t.regions[r].inscribedRadius)
            }
            #expect(stats.labelRoomRegions > 0 || stats.labelRoomEdges == 0)
            #expect(stats.labelRoomUnmet == 0)
            demoted += stats.labelRoomEdges
        }
        #expect(demoted > 0)
    }

    @Test func labelRoomReachesLatticeWhenNeeded() throws {
        // Asking every label for the full clearance of the pixel outline is always satisfiable:
        // the lattice provides it exactly.
        let s = Self.blobMap(width: 90, height: 70, colors: 5, cell: 6, noise: 0.01, seed: 3)
        let map = s.labels
        let graph = try BoundaryGraph.build(labels: map)
        let topology = graph.assembleRings(labels: map, regionCount: s.regionCount)
        let raster = RasterStats(
            labels: map, distance: DistanceTransform.interiorDistance(labels: map), regionCount: s.regionCount)
        var seeds: [SIMD2<Double>] = [], clearance: [Float] = []
        for r in 0..<s.regionCount {
            let pixel = Int(raster.bestPixel[r])
            seeds.append(SIMD2(Double(pixel % map.width) + 0.5, Double(pixel / map.width) + 0.5))
            clearance.append(RasterStats.latticeClearance(map, pixel: pixel, region: UInt32(r), limit: .infinity))
        }
        let room = LabelRoom(
            topology: topology, seeds: seeds, minRadius: clearance,
            measureFinely: Array(repeating: false, count: seeds.count))
        let result = try EdgeSmoother(graph: graph, smoothness: 1).run(labelRoom: room)
        let poles = result.poles
        for r in 0..<s.regionCount { #expect(poles.radius[r] >= clearance[r] - 1e-4, "region \(r)") }
        #expect(result.labelRoomEdges > 0)
        #expect(result.labelRoomUnmet == 0)
        #expect(GeometryValidator.invalidEdges(points: result.geometry.points, edges: result.geometry.boundaryEdges(graph)).isEmpty)
    }

    @Test func latticeClearanceMeasuresThePixelOutline() {
        // A 7×5 block of region 1 in region 0 on a 12×9 canvas, touching the right edge.
        var rows = Array(repeating: Array(repeating: UInt32(0), count: 12), count: 9)
        for y in 2..<7 { for x in 5..<12 { rows[y][x] = 1 } }
        let map = Self.segmentation(rows).labels
        let block = map[8, 4]
        // From the centre of (8, 4) to the pixel squares of rows 1 and 7: 2.5.
        #expect(RasterStats.latticeClearance(map, pixel: 4 * 12 + 8, region: block, limit: .infinity) == 2.5)
        #expect(RasterStats.latticeClearance(map, pixel: 4 * 12 + 8, region: block, limit: 1) == 1)
        // Next to the canvas edge: the outside counts as another region.
        #expect(RasterStats.latticeClearance(map, pixel: 4 * 12 + 11, region: block, limit: .infinity) == 0.5)
        // Only a diagonal neighbour is foreign: from (4, 1) of the frame to the corner of the
        // block's pixel (5, 2) is √(½² + ½²).
        let frame = map[0, 0]
        let diagonal = RasterStats.latticeClearance(map, pixel: 1 * 12 + 4, region: frame, limit: .infinity)
        #expect(abs(diagonal - 0.5 * Float(2).squareRoot()) < 1e-6)
    }

    @Test func validateReportsCrampedLabels() throws {
        // A 3×3 island in a ring in a frame: the ring and the frame are roomy, the island not.
        var rows = Array(repeating: Array(repeating: UInt32(0), count: 30), count: 30)
        for y in 8..<22 { for x in 8..<22 { rows[y][x] = 1 } }
        for y in 13..<16 { for x in 13..<16 { rows[y][x] = 2 } }
        let s = Self.segmentation(rows)
        var t = try Self.vectorize(s)
        let island = try #require(t.regions.firstIndex { $0.colorIndex == 2 })
        #expect(t.validate().isValid)
        let report = t.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(!report.isValid)
        #expect(report.crampedLabelRegions == [island])
        #expect(report.minLabelRoom < LabelSizing.minimumRadius)
        #expect(t.validate(minLabelRadius: 0.5).isValid)
        // A label claiming more room than it has is caught too.
        let k = Int(t.regions[island].labelStart)
        t.labels[k].radius += 1
        #expect(t.validate().isValid)
        #expect(t.validate(minLabelRadius: 0.5).badLabelRegions == [island])
    }

    @Test func largeRegionsGetExtraLabels() throws {
        let rows = (0..<300).map { y in (0..<400).map { x in UInt32(x < 20 && y < 20 ? 1 : 0) } }
        let s = Self.segmentation(rows)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        let bigRegion = t.regions.firstIndex { $0.colorIndex == 0 }!, smallRegion = 1 - bigRegion
        let big = t.labels(ofRegion: bigRegion)
        #expect(big.count > 3)
        for (i, a) in big.enumerated() {
            for b in big.dropFirst(i + 1) { #expect(Self.length(a.position - b.position) > 10) }
            #expect(a.radius >= 5)
        }
        #expect(t.labels(ofRegion: smallRegion).count == 1)
    }

    @Test func smallRegionsReportTheirInscribedRadiusPrecisely() throws {
        // Spots about 5 px across, the smallest the segmentation keeps: their inscribed radius
        // is held to the paintability floor of 2, so it must not be understated.
        let w = 96, h = 64
        var rng = SplitMix64(seed: 3)
        var classes = [UInt32](repeating: 0, count: w * h)
        for cy in stride(from: 8, to: h, by: 16) {
            for cx in stride(from: 8, to: w, by: 16) {
                let r = 2.6 + 0.6 * Double(rng.nextFloat())
                let ox = Double(cx) + Double(rng.nextFloat()), oy = Double(cy) + Double(rng.nextFloat())
                for y in (cy - 5)...(cy + 5) {
                    for x in (cx - 5)...(cx + 5) {
                        let dx = Double(x) + 0.5 - ox, dy = Double(y) + 0.5 - oy
                        if dx * dx + dy * dy < r * r { classes[y * w + x] = 1 }
                    }
                }
            }
        }
        let s = Self.segmentation(width: w, height: h, classes: classes)
        let t = try Self.vectorize(s)
        try Self.expectValid(t, s)
        let spots = t.regions.indices.filter { t.regions[$0].colorIndex == 1 }
        #expect(spots.count == 24)
        for r in spots {
            var poly = FlatPolygon()
            for ring in t.polygons(ofRegion: r) {
                for p in ring { poly.points.append(SIMD2<Double>(p)) }
                poly.closeRing()
            }
            // Dense search for the largest inscribed disc: a 0.05 grid, then a 0.002 grid
            // around its best point. Distance is 1-Lipschitz, so the true maximum is within
            // 0.036 of the coarse one.
            let b = t.regions[r].bounds
            var best = (d: -Double.infinity, x: 0.0, y: 0.0)
            for y in stride(from: Double(b.minY), through: Double(b.maxY), by: 0.05) {
                for x in stride(from: Double(b.minX), through: Double(b.maxX), by: 0.05) {
                    let d = poly.signedDistance(x, y)
                    if d > best.d { best = (d, x, y) }
                }
            }
            let coarse = best.d
            for y in stride(from: best.y - 0.05, through: best.y + 0.05, by: 0.002) {
                for x in stride(from: best.x - 0.05, through: best.x + 0.05, by: 0.002) {
                    best.d = max(best.d, poly.signedDistance(x, y))
                }
            }
            let reported = Double(t.regions[r].inscribedRadius)
            #expect(reported >= best.d - 0.006, "region \(r): \(reported) vs \(best.d)")
            #expect(reported <= coarse + 0.036, "region \(r): \(reported) vs \(coarse)")
            let label = t.labels(ofRegion: r).first!
            #expect(abs(poly.signedDistance(Double(label.position.x), Double(label.position.y)) - reported) < 1e-4)
        }
    }

    // MARK: - Pipeline

    @Test func photoThroughPipeline() throws {
        // A synthetic "photo": gradients, discs and noise, through the full pipeline.
        let w = 160, h = 120
        var rng = SplitMix64(seed: 9)
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var c = SIMD3<Float>(Float(x) / Float(w), Float(y) / Float(h), 0.5)
                for (cx, cy, r, col) in [(50, 60, 30, SIMD3<Float>(0.9, 0.2, 0.1)), (110, 40, 18, SIMD3<Float>(0.1, 0.3, 0.8))] {
                    let d = Float((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                    if d < Float(r) { c = col }
                }
                c += SIMD3(repeating: (rng.nextFloat() - 0.5) * 0.15)
                let i = (y * w + x) * 4
                for k in 0..<3 { px[i + k] = UInt8(min(max(c[k], 0), 1) * 255) }
            }
        }
        var settings = GenerationSettings(colorCount: 8)
        settings.detail = 0
        let out = try TemplateGenerator(settings: settings).generate(from: RGBAImage(width: w, height: h, pixels: px), cancel: .none)
        try Self.expectValid(out.template, out.segmentation)
        let report = out.template.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        #expect(out.timings.contains { $0.name == "vectorize.smooth" })
    }

    @Test func highColorPipelineIsLegibleAndDeterministic() throws {
        let generator = TemplateGenerator(settings: GenerationSettings(colorCount: 150, detail: 1))
        let image = TestScenes.colorful()
        let out = try generator.generate(from: image, cancel: .none)
        let again = try generator.generate(from: image, cancel: .none)
        #expect(again.template == out.template)
        #expect(again.vectorStats == out.vectorStats)
        #expect(out.vectorStats.labelRoomUnmet == 0)
        try Self.expectValid(out.template, out.segmentation)
        let report = out.template.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
        #expect(out.template.regions.contains { LabelSizing.digitCount(colorIndex: $0.colorIndex) == 3 })
        for label in out.template.labels {
            let digits = LabelSizing.digitCount(colorIndex: out.template.regions[Int(label.region)].colorIndex)
            #expect(LabelSizing.fittedFontSize(radius: label.radius, digits: digits) >= LabelSizing.minimumFontSize - 1e-4)
        }
    }

    // MARK: - Components

    @Test func validatorDetectsBadContacts() {
        func edge(_ start: Int, _ count: Int) -> BoundaryEdge { BoundaryEdge(left: 0, right: 1, pointStart: UInt32(start), pointCount: UInt32(count)) }
        // Three edges meeting at a shared end point (a junction): fine.
        let ok: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 1), SIMD2(1, 1), SIMD2(2, 0), SIMD2(1, 1), SIMD2(1, 3)]
        #expect(GeometryValidator.invalidEdges(points: ok, edges: [edge(0, 2), edge(2, 2), edge(4, 2)]).isEmpty)
        // Crossing.
        let cross: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(2, 2), SIMD2(0, 2), SIMD2(2, 0)]
        #expect(GeometryValidator.invalidEdges(points: cross, edges: [edge(0, 2), edge(2, 2)]) == [0, 1])
        // T-touch: an end point on another edge's interior.
        let touch: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(2, 0), SIMD2(1, 0), SIMD2(1, 2)]
        #expect(GeometryValidator.invalidEdges(points: touch, edges: [edge(0, 2), edge(2, 2)]) == [0, 1])
        // An edge ending on another edge's interior vertex.
        let vertex: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 1), SIMD2(2, 0), SIMD2(1, 1), SIMD2(1, 3)]
        #expect(GeometryValidator.invalidEdges(points: vertex, edges: [edge(0, 3), edge(3, 2)]) == [0, 1])
        let through: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 1), SIMD2(2, 0), SIMD2(1, 3), SIMD2(1, 1), SIMD2(1, -1)]
        #expect(GeometryValidator.invalidEdges(points: through, edges: [edge(0, 3), edge(3, 3)]) == [0, 1])
        // Collinear overlap and a zero-length segment.
        let overlap: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(3, 0), SIMD2(1, 0), SIMD2(2, 0)]
        #expect(GeometryValidator.invalidEdges(points: overlap, edges: [edge(0, 2), edge(2, 2)]) == [0, 1])
        let spike: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(2, 0), SIMD2(1, 0)]
        #expect(GeometryValidator.invalidEdges(points: spike, edges: [edge(0, 3)]) == [0])
        let zero: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0, 0), SIMD2(1, 0)]
        #expect(GeometryValidator.invalidEdges(points: zero, edges: [edge(0, 3)]) == [0])

        // Incremental mode, as the repair loop uses it: only pairs with a flagged edge are
        // tested. Edge 2 shares the crossing's grid cell without touching either edge.
        let crowded = cross + [SIMD2(4, 0), SIMD2(4, 2)]
        let edges = [edge(0, 2), edge(2, 2), edge(4, 2)]
        #expect(GeometryValidator.invalidEdges(points: crowded, edges: edges) == [0, 1])
        #expect(GeometryValidator.invalidEdges(points: crowded, edges: edges, onlyInvolving: [true, true, true]) == [0, 1])
        #expect(GeometryValidator.invalidEdges(points: crowded, edges: edges, onlyInvolving: [false, false, true]).isEmpty)
        #expect(GeometryValidator.invalidEdges(points: crowded, edges: edges, onlyInvolving: [true, false, false]) == [0, 1])
    }

    @Test func earcutCoversPolygonsExactly() {
        func area(_ pts: [SIMD2<Double>], _ tris: [UInt32]) -> Double {
            stride(from: 0, to: tris.count, by: 3).reduce(0.0) { acc, t in
                let a = pts[Int(tris[t])], b = pts[Int(tris[t + 1])], c = pts[Int(tris[t + 2])]
                return acc + ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
            }
        }
        var earcut = Earcut()
        var tris: [UInt32] = []
        // Square with a square hole, collinear and duplicate points on the outline.
        let pts: [SIMD2<Double>] = [
            SIMD2(0, 0), SIMD2(5, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(10, 10), SIMD2(0, 10),
            SIMD2(3, 3), SIMD2(3, 7), SIMD2(7, 7), SIMD2(7, 3),
        ]
        earcut.triangulate(pts, holeStarts: [6], into: &tris)
        #expect(abs(area(pts, tris) - 84) < 1e-9)
        // A large star (z-order hashing path) with a hole touching its outline.
        var star: [SIMD2<Double>] = []
        for k in 0..<200 {
            let a = Double(k) * 2 * .pi / 200, r = k % 2 == 0 ? 50.0 : 35.0
            star.append(SIMD2(r * cos(a), r * sin(a)))
        }
        let outerArea = abs(zip(star, star.dropFirst() + [star[0]]).reduce(0.0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }) / 2
        tris.removeAll()
        star += [SIMD2(35, 0), SIMD2(20, 5), SIMD2(20, -5)]
        earcut.triangulate(star, holeStarts: [200], into: &tris)
        #expect(abs(abs(area(star, tris)) - (outerArea - 75)) < 1e-6)
    }

    @Test func cancellation() {
        let s = Self.blobMap(width: 40, height: 30, colors: 3, cell: 6, noise: 0, seed: 1)
        #expect(throws: CancellationError.self) {
            try Vectorizer.vectorize(s, settings: GenerationSettings(), cancel: CancellationCheck { true }, clock: StageClock())
        }
    }
}
