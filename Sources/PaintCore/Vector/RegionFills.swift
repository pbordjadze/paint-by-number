/// Read access to region polygons in a template under construction.
struct RegionShapes {
    let points: [SIMD2<Float>]
    let edges: [BoundaryEdge]
    let topology: RingTopology

    /// Number of outline points of region `r` (a proxy for the work its fill takes).
    func pointCount(_ r: Int) -> Int {
        var total = 0
        let start = Int(topology.regionRingStart[r]), count = Int(topology.regionRingCount[r])
        for k in start..<(start + count) {
            let ring = topology.rings[k]
            for q in Int(ring.edgeStart)..<Int(ring.edgeStart + ring.edgeCount) {
                total += Int(edges[Int(topology.ringEdges[q].edge)].pointCount)
            }
        }
        return total
    }

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

    static func build(
        _ shapes: RegionShapes, poles: LabelPoles, width: Int, height: Int, cancel: CancellationCheck = .none
    ) throws -> RegionFills {
        let regionCount = shapes.topology.regionRingStart.count
        // Small chunks balance the load: a single huge region must not stall a whole band.
        // Waves of regions keep cancellation responsive.
        var bands: [RegionFills] = []
        var first = 0
        while first < regionCount {
            try cancel.throwIfCancelled()
            let last = min(regionCount, first + 512)
            let offset = first
            bands += Parallel.mapChunks(last - first, chunk: 16, cost: { shapes.pointCount(offset + $0) }) { chunk -> RegionFills in
                let range = (chunk.lowerBound + offset)..<(chunk.upperBound + offset)
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

                    band.pole.append(poles.position[r])
                    band.poleRadius.append(poles.radius[r])
                    band.extraLabels.append([])
                }
                return band
            }
            first = last
        }
        try cancel.throwIfCancelled()
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
    /// to the least spacious and accepted when far enough from every label placed so far, and
    /// with room to spare from the outline and from `keepOut`.
    mutating func addExtraLabels(
        _ shapes: RegionShapes, raster: RasterStats, distance: Grid<Float>, map: RegionMap, regionColor: [UInt32],
        keepOut: LabelKeepOut = LabelKeepOut(rects: []), width: Int, height: Int
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

        let found = Parallel.mapChunks(big.count, chunk: 1) { range -> [[Label]] in
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
                let legible = LabelSizing.minimumRadius(digits: LabelSizing.digitCount(colorIndex: regionColor[r]))
                var placed: [SIMD2<Float>] = [pole[r]]
                var extras: [Label] = []
                var polyBuilt = false
                for c in candidates {
                    if extras.count >= cap { break }
                    let p = SIMD2(Float(Int(c.pixel) % width) + 0.5, Float(Int(c.pixel) / width) + 0.5)
                    var far = true
                    for q in placed {
                        let d = p - q
                        if (d * d).sum() < spacing * spacing { far = false; break }
                    }
                    guard far else { continue }
                    if !polyBuilt { shapes.polygon(r, into: &poly); polyBuilt = true }
                    let free = min(poly.signedDistance(Double(p.x), Double(p.y)), keepOut.distance(Double(p.x), Double(p.y)))
                    guard free >= max(Double(minRadius) * 0.8, Double(legible)) else { continue }
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
