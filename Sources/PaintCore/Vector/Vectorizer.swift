import Foundation

/// Segmentation → vector template: shared smoothed boundaries, per-region rings, a
/// triangulated fill mesh and number placements.
///
/// 1. `BoundaryGraph` traces region boundaries on the pixel-corner lattice into edges
///    between junctions (exact, integer chain codes) and assembles each region's rings.
/// 2. `EdgeSmoother` fits every edge once (`CurveFitter`), so both neighbouring regions use
///    the very same curve and fills tile the canvas without gaps or overlaps; it repairs
///    any fit that would cross or touch another edge.
/// 3. Each region's rings are triangulated (`Earcut`) and labelled at the pole of
///    inaccessibility of the smoothed polygon (`PolyLabel`), with extra labels spread
///    over large regions.
public enum Vectorizer {
    /// Precision of label placement, canvas units.
    static let labelPrecision = 0.25

    public static func vectorize(
        _ segmentation: Segmentation,
        settings: GenerationSettings,
        cancel: CancellationCheck,
        clock: StageClock
    ) throws -> Template {
        let map = segmentation.labels
        let w = map.width, h = map.height
        let regionCount = segmentation.regionCount
        guard w > 0, h > 0, regionCount > 0 else {
            return Template(
                width: w, height: h, colorSpace: segmentation.colorSpace, palette: segmentation.palette,
                regions: [], points: [], edges: [], ringEdges: [], rings: [], labels: [], mesh: FillMesh(), regionMap: map)
        }

        let graph = clock.measure("vectorize.graph") { BoundaryGraph.build(labels: map) }
        try cancel.throwIfCancelled()
        let topology = clock.measure("vectorize.rings") { graph.assembleRings(labels: map, regionCount: regionCount) }
        try cancel.throwIfCancelled()

        var repairs = 0
        let geometry = clock.measure("vectorize.smooth") {
            EdgeSmoother(graph: graph, smoothness: settings.normalized.smoothness).run(repairs: &repairs)
        }
        let edges = geometry.boundaryEdges(graph)
        if ProcessInfo.processInfo.environment["PBN_DEBUG"] != nil {
            FileHandle.standardError.write(Data("repairs \(repairs) of \(graph.edgeCount) edges\n".utf8))
        }
        try cancel.throwIfCancelled()

        let distance = clock.measure("vectorize.edt") { DistanceTransform.interiorDistance(labels: map) }
        let raster = clock.measure("vectorize.raster") { RasterStats(labels: map, distance: distance, regionCount: regionCount) }
        try cancel.throwIfCancelled()

        let shapes = RegionShapes(points: geometry.points, edges: edges, topology: topology)
        var fills = clock.measure("vectorize.fill") {
            RegionFills.build(shapes, raster: raster, width: w, height: h)
        }
        try cancel.throwIfCancelled()
        clock.measure("vectorize.labels") {
            fills.addExtraLabels(shapes, raster: raster, distance: distance, map: map, width: w, height: h)
        }

        var regions: [Region] = []
        regions.reserveCapacity(regionCount)
        var labels: [Label] = []
        labels.reserveCapacity(regionCount)
        var indexCursor: UInt32 = 0
        for r in 0..<regionCount {
            let labelStart = UInt32(labels.count)
            labels.append(Label(position: fills.pole[r], radius: fills.poleRadius[r], region: UInt32(r)))
            for extra in fills.extraLabels[r] { labels.append(extra) }
            regions.append(Region(
                colorIndex: segmentation.regionColor[r], area: fills.area[r], bounds: fills.bounds[r],
                inscribedRadius: fills.poleRadius[r],
                ringStart: topology.regionRingStart[r], ringCount: topology.regionRingCount[r],
                labelStart: labelStart, labelCount: UInt32(labels.count) - labelStart,
                indexStart: indexCursor, indexCount: fills.indexCount[r]))
            indexCursor += fills.indexCount[r]
        }

        return Template(
            width: w, height: h, colorSpace: segmentation.colorSpace, palette: segmentation.palette,
            regions: regions, points: geometry.points, edges: edges,
            ringEdges: topology.ringEdges, rings: topology.rings, labels: labels,
            mesh: FillMesh(vertices: fills.vertices, vertexRegion: fills.vertexRegion, indices: fills.indices),
            regionMap: map)
    }
}

/// Per-region raster statistics: pixel area, pixel bounds and the distance-transform
/// maximum (a seed for the pole of inaccessibility).
struct RasterStats {
    var pixelArea: [Int32]
    var pixelBounds: [PixelBounds]
    var bestDistance: [Float]
    var bestPixel: [Int32]

    init(labels: RegionMap, distance: Grid<Float>, regionCount: Int) {
        let w = labels.width, h = labels.height
        struct Band {
            var area: [Int32], bounds: [PixelBounds], best: [Float], bestPixel: [Int32]
        }
        let bands = labels.storage.withUnsafeBufferPointer { lab in
            distance.storage.withUnsafeBufferPointer { dist in
                let l = UncheckedSendable(lab), d = UncheckedSendable(dist)
                return Parallel.mapBands(h, minimumBandSize: 32) { rows -> Band in
                    var b = Band(
                        area: [Int32](repeating: 0, count: regionCount),
                        bounds: [PixelBounds](repeating: .empty, count: regionCount),
                        best: [Float](repeating: -1, count: regionCount),
                        bestPixel: [Int32](repeating: 0, count: regionCount))
                    for y in rows {
                        for x in 0..<w {
                            let i = y * w + x
                            let r = Int(l.value[i])
                            b.area[r] += 1
                            b.bounds[r].include(x: x, y: y)
                            if d.value[i] > b.best[r] { b.best[r] = d.value[i]; b.bestPixel[r] = Int32(i) }
                        }
                    }
                    return b
                }
            }
        }
        pixelArea = [Int32](repeating: 0, count: regionCount)
        pixelBounds = [PixelBounds](repeating: .empty, count: regionCount)
        bestDistance = [Float](repeating: -1, count: regionCount)
        bestPixel = [Int32](repeating: 0, count: regionCount)
        for b in bands {
            for r in 0..<regionCount where b.area[r] > 0 {
                pixelArea[r] += b.area[r]
                pixelBounds[r].formUnion(b.bounds[r])
                if b.best[r] > bestDistance[r] { bestDistance[r] = b.best[r]; bestPixel[r] = b.bestPixel[r] }
            }
        }
    }
}

/// Read access to region polygons in a template under construction.
struct RegionShapes {
    let points: [SIMD2<Float>]
    let edges: [BoundaryEdge]
    let topology: RingTopology

    /// All rings of region `r` (outer first), each without its closing point.
    func polygon(_ r: Int, into poly: inout FlatPolygon) {
        poly.removeAll()
        let start = Int(topology.regionRingStart[r]), count = Int(topology.regionRingCount[r])
        for k in start..<(start + count) {
            let ring = topology.rings[k]
            for q in Int(ring.edgeStart)..<Int(ring.edgeStart + ring.edgeCount) {
                let ref = topology.ringEdges[q]
                let e = edges[Int(ref.edge)]
                let s = Int(e.pointStart), n = Int(e.pointCount)
                if ref.reversed {
                    for i in stride(from: s + n - 1, to: s, by: -1) { poly.points.append(SIMD2<Double>(points[i])) }
                } else {
                    for i in s..<(s + n - 1) { poly.points.append(SIMD2<Double>(points[i])) }
                }
            }
            poly.closeRing()
        }
    }
}

/// Fill mesh, areas, bounds and labels of all regions.
struct RegionFills {
    var vertices: [SIMD2<Float>] = []
    var vertexRegion: [UInt32] = []
    var indices: [UInt32] = []
    var indexCount: [UInt32] = []
    var area: [Float] = []
    var bounds: [PixelBounds] = []
    var pole: [SIMD2<Float>] = []
    var poleRadius: [Float] = []
    var extraLabels: [[Label]] = []

    static func build(_ shapes: RegionShapes, raster: RasterStats, width: Int, height: Int) -> RegionFills {
        let regionCount = shapes.topology.regionRingStart.count
        // Small chunks balance the load: a single huge region must not stall a whole band.
        let bands = mapChunks(regionCount, chunk: 16) { range -> RegionFills in
            var band = RegionFills()
            var poly = FlatPolygon()
            var earcut = Earcut()
            var tri: [UInt32] = []
            var sub: [SIMD2<Double>] = []
            var holeStarts: [Int] = []
            for r in range {
                shapes.polygon(r, into: &poly)
                let base = UInt32(band.vertices.count)
                for p in poly.points {
                    band.vertices.append(SIMD2<Float>(p))
                    band.vertexRegion.append(UInt32(r))
                }

                // Signed ring areas: outer rings positive, holes negative.
                var area2 = 0.0
                for k in 0..<poly.ringCount { area2 += poly.area2(ring: k) }
                band.area.append(Float(area2 / 2))

                var lo = SIMD2<Double>(repeating: .infinity), hi = SIMD2<Double>(repeating: -.infinity)
                for i in 0..<(poly.ringStarts.count > 1 ? poly.ringStarts[1] : 0) {
                    lo = pointwiseMin(lo, poly.points[i]); hi = pointwiseMax(hi, poly.points[i])
                }
                band.bounds.append(lo.x <= hi.x
                    ? PixelBounds(
                        minX: Int32(max(0, lo.x.rounded(.down))), minY: Int32(max(0, lo.y.rounded(.down))),
                        maxX: Int32(min(Double(width), hi.x.rounded(.up))), maxY: Int32(min(Double(height), hi.y.rounded(.up))))
                    : .empty)

                // Triangulate. A 4-connected region has exactly one outer ring; any further
                // outer rings (malformed input) are triangulated with the holes they contain.
                tri.removeAll(keepingCapacity: true)
                let outers = (0..<poly.ringCount).filter { $0 == 0 || !shapes.topology.rings[Int(shapes.topology.regionRingStart[r]) + $0].isHole }
                if outers.count == 1 {
                    earcut.triangulate(poly.points, holeStarts: Array(poly.ringStarts[1..<poly.ringCount]), into: &tri)
                } else {
                    for o in outers {
                        sub.removeAll(keepingCapacity: true)
                        holeStarts.removeAll(keepingCapacity: true)
                        var map: [UInt32] = []
                        func add(ring k: Int) {
                            for i in poly.ringStarts[k]..<poly.ringStarts[k + 1] {
                                sub.append(poly.points[i]); map.append(UInt32(i))
                            }
                        }
                        add(ring: o)
                        for k in 0..<poly.ringCount where !outers.contains(k) {
                            let p = poly.points[poly.ringStarts[k]]
                            if RegionFills.ringContains(poly, ring: o, p) { holeStarts.append(sub.count); add(ring: k) }
                        }
                        var local: [UInt32] = []
                        earcut.triangulate(sub, holeStarts: holeStarts, into: &local)
                        for i in local { tri.append(map[Int(i)]) }
                    }
                }
                RegionFills.splitTJunctions(poly.points, &tri)
                for i in tri { band.indices.append(i + base) }
                band.indexCount.append(UInt32(tri.count))

                let seedPixel = Int(raster.bestPixel[r])
                let seed = SIMD2(Double(seedPixel % width) + 0.5, Double(seedPixel / width) + 0.5)
                let label = PolyLabel.find(poly, precision: Vectorizer.labelPrecision, seed: seed)
                band.pole.append(SIMD2<Float>(label.position))
                band.poleRadius.append(Float(label.distance))
                band.extraLabels.append([])
            }
            return band
        }
        var out = RegionFills()
        for band in bands {
            let base = UInt32(out.vertices.count)
            out.vertices.append(contentsOf: band.vertices)
            out.vertexRegion.append(contentsOf: band.vertexRegion)
            out.indices.append(contentsOf: band.indices.lazy.map { $0 + base })
            out.indexCount.append(contentsOf: band.indexCount)
            out.area.append(contentsOf: band.area)
            out.bounds.append(contentsOf: band.bounds)
            out.pole.append(contentsOf: band.pole)
            out.poleRadius.append(contentsOf: band.poleRadius)
            out.extraLabels.append(contentsOf: band.extraLabels)
        }
        return out
    }

    /// Earcut drops ring vertices that became collinear with their neighbours while it
    /// filtered degenerate cases. The neighbouring region still uses such a vertex, so it
    /// would be a T-junction — a source of pixel cracks on the GPU. Splits every triangle
    /// whose edge passes through an unused vertex so the mesh stays conforming. Exact:
    /// coordinates lie on the `Template.coordinateQuantum` grid.
    static func splitTJunctions(_ points: [SIMD2<Double>], _ tri: inout [UInt32]) {
        var used = [Bool](repeating: false, count: points.count)
        for i in tri { used[Int(i)] = true }
        guard used.contains(false) else { return }
        let scale = Double(1 / Template.coordinateQuantum)
        @inline(__always) func fixed(_ i: Int) -> SIMD2<Int64> {
            SIMD2(Int64((points[i].x * scale).rounded()), Int64((points[i].y * scale).rounded()))
        }
        var usedCoordinates = Set<SIMD2<Int64>>()
        for i in points.indices where used[i] { usedCoordinates.insert(fixed(i)) }
        for v in points.indices where !used[v] {
            let p = fixed(v)
            guard usedCoordinates.insert(p).inserted else { continue }
            var t = 0
            while t < tri.count {
                var split = false
                for k in 0..<3 {
                    let a = fixed(Int(tri[t + k])), b = fixed(Int(tri[t + (k + 1) % 3]))
                    let ab = b &- a, ap = p &- a, bp = p &- b
                    if ab.x * ap.y - ab.y * ap.x == 0 && (ab &* ap).wrappedSum() > 0 && (ab &* bp).wrappedSum() < 0 {
                        // (a, b, c) → (a, v, c) + (v, b, c): same orientation.
                        let ia = tri[t + k], ib = tri[t + (k + 1) % 3], ic = tri[t + (k + 2) % 3]
                        tri[t] = ia; tri[t + 1] = UInt32(v); tri[t + 2] = ic
                        tri.append(UInt32(v)); tri.append(ib); tri.append(ic)
                        split = true
                        break
                    }
                }
                if !split { t += 3 }
            }
        }
    }

    static func ringContains(_ poly: FlatPolygon, ring k: Int, _ p: SIMD2<Double>) -> Bool {
        var inside = false
        let a = poly.ringStarts[k], b = poly.ringStarts[k + 1]
        var j = b - 1
        for i in a..<b {
            let pa = poly.points[i], pb = poly.points[j]
            if (pa.y > p.y) != (pb.y > p.y) && p.x < (pb.x - pa.x) * (p.y - pa.y) / (pb.y - pa.y) + pa.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Spreads additional labels over large regions so a number stays in view when zoomed
    /// into any part of them: raster distance-transform samples are visited from the most
    /// to the least spacious and accepted when far enough from every label placed so far.
    mutating func addExtraLabels(
        _ shapes: RegionShapes, raster: RasterStats, distance: Grid<Float>, map: RegionMap, width: Int, height: Int
    ) {
        let regionCount = pole.count
        // Typical label radius: median pole radius of regions that can hold a number.
        let radii = poleRadius.filter { $0 >= 1 }.sorted()
        let typical = min(max(radii.isEmpty ? 4 : radii[radii.count / 2], 3), 8)
        let spacing = max(10 * typical, Float(max(width, height)) / 16)
        let minRadius = max(1.5 * typical, 5)
        let minArea = Int32(spacing * spacing * 0.5)
        let big = (0..<regionCount).filter { raster.pixelArea[$0] >= minArea && raster.bestDistance[$0] >= minRadius }
        guard !big.isEmpty else { return }

        let found = mapChunks(big.count, chunk: 1) { range -> [[Label]] in
            var result: [[Label]] = []
            var poly = FlatPolygon()
            var candidates: [(key: Int32, pixel: Int32)] = []
            for k in range {
                let r = big[k]
                let b = raster.pixelBounds[r]
                candidates.removeAll(keepingCapacity: true)
                // Even pixels only: labels need no finer placement and it quarters the work.
                for y in stride(from: Int(b.minY + (b.minY & 1)), to: Int(b.maxY), by: 2) {
                    for x in stride(from: Int(b.minX + (b.minX & 1)), to: Int(b.maxX), by: 2) {
                        let i = y * width + x
                        guard map.storage[i] == UInt32(r) else { continue }
                        let d = distance.storage[i]
                        if d >= minRadius { candidates.append((Int32(-(d * 4).rounded()), Int32(i))) }
                    }
                }
                candidates.sort { $0.key != $1.key ? $0.key < $1.key : $0.pixel < $1.pixel }
                let cap = min(64, Int(Float(raster.pixelArea[r]) / (spacing * spacing * 0.6)))
                var placed: [SIMD2<Float>] = [pole[r]]
                var extras: [Label] = []
                var polyBuilt = false
                for c in candidates {
                    if extras.count >= cap { break }
                    let p = SIMD2(Float(Int(c.pixel) % width) + 0.5, Float(Int(c.pixel) / width) + 0.5)
                    var far = true
                    for q in placed where simd_length_squared(p - q) < spacing * spacing { far = false; break }
                    guard far else { continue }
                    if !polyBuilt { shapes.polygon(r, into: &poly); polyBuilt = true }
                    let free = poly.signedDistance(Double(p.x), Double(p.y))
                    guard free >= Double(minRadius) * 0.8 else { continue }
                    placed.append(p)
                    extras.append(Label(position: p, radius: Float(free), region: UInt32(r)))
                }
                result.append(extras)
            }
            return result
        }
        for (k, labels) in found.joined().enumerated() { extraLabels[big[k]] = labels }
    }
}

@inline(__always)
private func simd_length_squared(_ v: SIMD2<Float>) -> Float { (v * v).sum() }

/// Parallel map over `0..<count` in chunks of `chunk`, scheduled dynamically; results
/// in chunk order.
func mapChunks<T>(_ count: Int, chunk: Int, _ body: (Range<Int>) -> T) -> [T] {
    guard count > 0 else { return [] }
    let n = (count + chunk - 1) / chunk
    var results = [T?](repeating: nil, count: n)
    results.withUnsafeMutableBufferPointer { buf in
        let out = UncheckedSendable(buf.baseAddress!)
        withoutActuallyEscaping(body) { body in
            let work = UncheckedSendable(body)
            DispatchQueue.concurrentPerform(iterations: n) { i in
                out.value[i] = work.value((i * chunk)..<min(count, (i + 1) * chunk))
            }
        }
    }
    return results.map { $0! }
}
