/// Flat per-edge polylines (canonical edge orientation, closed edges repeat their first point).
struct EdgePolylines: Sendable {
    var points: [SIMD2<Float>] = []
    var start: [Int32] = []
    var count: [Int32] = []

    func boundaryEdges(_ g: BoundaryGraph) -> [BoundaryEdge] {
        (0..<g.edgeCount).map {
            BoundaryEdge(left: g.edgeLeft[$0], right: g.edgeRight[$0], pointStart: UInt32(start[$0]), pointCount: UInt32(count[$0]))
        }
    }

    /// Replaces the polylines of `list` (ascending) with `newPoints`/`newCounts` (same order).
    mutating func replace(_ list: [Int], points newPoints: [SIMD2<Float>], counts newCounts: [Int32]) {
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(points.count + newPoints.count)
        var k = 0, src = 0
        for e in 0..<start.count {
            let s = Int(start[e]), c = Int(count[e])
            start[e] = Int32(out.count)
            if k < list.count && list[k] == e {
                let n = Int(newCounts[k])
                out.append(contentsOf: newPoints[src..<(src + n)])
                count[e] = Int32(n)
                src += n
                k += 1
            } else {
                out.append(contentsOf: points[s..<(s + c)])
            }
        }
        points = out
    }
}

/// Room every region's number must keep once edges are smoothed (see `EdgeSmoother.run`).
struct LabelRoom: Sendable {
    let topology: RingTopology
    /// Per region: centre of its raster interior-distance maximum pixel.
    let seeds: [SIMD2<Double>]
    /// Per region: the free radius its label must keep. At most the pixel outline's
    /// clearance at the seed (`RasterStats.latticeClearance`), so lattice edges always
    /// provide it.
    let minRadius: [Float]
    /// Per region: whether its pole is searched at `Vectorizer.smallRegionLabelPrecision`
    /// from the start (regions near the radius floor, whose radius sizes their number).
    let measureFinely: [Bool]
}

/// Per region: label position (pole of inaccessibility) and its free radius.
struct LabelPoles: Sendable {
    var position: [SIMD2<Float>]
    var radius: [Float]
}

struct SmoothingResult {
    var geometry: EdgePolylines
    /// Edges that needed a fallback shape for valid geometry (zero for clean segmentations).
    var repairs: Int
    /// Edges stepped toward the lattice so a label keeps its room, and the regions whose
    /// labels needed it.
    var labelRoomEdges: Int
    var labelRoomRegions: Int
    /// Labels still short of their room when no edge near them could step down any more.
    /// Zero by construction (see `EdgeSmoother.run`); counted so a broken invariant shows up
    /// in the stats rather than only as an invalid template.
    var labelRoomUnmet: Int
    /// Labels of the final geometry; nil when no label room was requested.
    var poles: LabelPoles?
}

/// Turns lattice chains into smooth shared boundary polylines and guarantees the result
/// is a valid planar subdivision.
///
/// Interior edges are curve-fitted (`CurveFitter`) and faired (`CurveFairing`); border
/// edges stay exactly on the canvas border. Coordinates are snapped to
/// `Template.coordinateQuantum` so every later geometric predicate is exact. Curves of
/// very thin features may cross their neighbours; the repair loop detects any crossing,
/// touching or change of edge order around a junction and steps just the offending edges
/// down to the unfaired fit, then the midpoint polyline (stair corners cut at the lattice
/// segment midpoints), then the raw lattice chain. The last two are provably free of
/// crossings among themselves, so the loop always terminates with valid geometry.
///
/// Smoothing can also shave a thin region's interior (a fitted curve cuts across a narrow
/// waist), leaving its number too little room. With a `LabelRoom`, each region's label is
/// placed on the smoothed polygon and a region whose label falls short of its minimum
/// steps the edges near its raster seed down the same chain until it holds.
struct EdgeSmoother {
    /// Edge shapes in order of preference; the repair loop moves offending edges down.
    enum Shape: UInt8 { case faired = 0, fitted = 1, midpoints = 2, lattice = 3 }

    let graph: BoundaryGraph
    let alphaMax: Double
    let minCornerAngle: Double
    let cornerRadius: Double
    let tolerance: Double
    let fairingWindow: Double
    let fairingShift: Double

    /// `smoothness` 0 keeps boundaries crisp and faithful (more corners, light fairing);
    /// 0.5 uses potrace's default corner threshold; above that corners are kept but rounded
    /// with growing fillets and curves are faired more strongly. (Raising the threshold
    /// instead would bend long straight sides into the curves around their corners.)
    init(graph: BoundaryGraph, smoothness: Float) {
        self.graph = graph
        let s = Double(min(max(smoothness, 0), 1))
        alphaMax = 0.6 + 0.8 * min(s, 0.5)
        minCornerAngle = 35 + 40 * s
        cornerRadius = 6 * max(0, s - 0.5)
        tolerance = 0.05
        fairingWindow = 2 + 8 * s
        fairingShift = 0.3 + 0.4 * s
    }

    /// Smooths all edges, repairs invalid geometry and, with `labelRoom`, places every
    /// region's label and makes sure it keeps its minimum room.
    ///
    /// The label stage terminates with every label at least `labelRoom.minRadius` (less a
    /// rounding slack) from its outline: `PolyLabel` evaluates the seed, so a label's radius
    /// is at least the seed's distance to the outline. If that is short of the minimum, some
    /// edge within the minimum of the seed is not lattice-shaped (border edges always are),
    /// since lattice edges keep at least the seed's clearance, which bounds the minimum. Those
    /// edges step down; shapes only ever step down, so the loop ends.
    func run(labelRoom room: LabelRoom? = nil, cancel: CancellationCheck = .none) throws -> SmoothingResult {
        var repairs = 0
        let edgeCount = graph.edgeCount
        var shapes = [UInt8](repeating: Shape.faired.rawValue, count: edgeCount)
        // Waves of edges keep cancellation responsive.
        var first: (points: [SIMD2<Float>], counts: [Int32]) = ([], [])
        for start in stride(from: 0, to: edgeCount, by: 1024) {
            try cancel.throwIfCancelled()
            let wave = polylines(for: Array(start..<min(edgeCount, start + 1024)), shapes: shapes)
            first.points += wave.points
            first.counts += wave.counts
        }
        var geo = EdgePolylines(points: first.points, start: [], count: first.counts)
        geo.start.reserveCapacity(edgeCount)
        var offset: Int32 = 0
        for c in first.counts { geo.start.append(offset); offset += c }

        let regionCount = room?.seeds.count ?? 0
        var poles = LabelPoles(
            position: [SIMD2<Float>](repeating: .zero, count: regionCount), radius: [Float](repeating: 0, count: regionCount))
        var needPole = [Bool](repeating: true, count: regionCount)
        var roomEdge = [Bool](repeating: false, count: edgeCount)
        var roomRegion = [Bool](repeating: false, count: regionCount)
        var unmet = 0
        func step(_ list: [Int], shapes: inout [UInt8]) -> [Bool] {
            var changed = [Bool](repeating: false, count: edgeCount)
            for e in list {
                shapes[e] += 1
                changed[e] = true
                if room != nil {
                    needPole[Int(graph.edgeLeft[e])] = true
                    if graph.edgeRight[e] != BoundaryEdge.outside { needPole[Int(graph.edgeRight[e])] = true }
                }
            }
            let redo = polylines(for: list, shapes: shapes)
            geo.replace(list, points: redo.points, counts: redo.counts)
            return changed
        }

        // Every round moves each offending edge one shape down, so the loop terminates. After
        // the first round only pairs involving a changed edge can newly conflict.
        var dirty: [Bool]? = nil
        while true {
            try cancel.throwIfCancelled()
            var bad = Set(GeometryValidator.invalidEdges(points: geo.points, edges: geo.boundaryEdges(graph), onlyInvolving: dirty))
            bad.formUnion(junctionOrderViolations(geo))
            let fix = bad.filter { graph.edgeRight[$0] != BoundaryEdge.outside && shapes[$0] < Shape.lattice.rawValue }.sorted()
            if !fix.isEmpty {
                for e in fix where shapes[e] == Shape.faired.rawValue { repairs += 1 }
                dirty = step(fix, shapes: &shapes)
                continue
            }
            guard let room else { break }

            // Valid geometry: place the labels of regions whose outline changed.
            let edges = geo.boundaryEdges(graph)
            try placeLabels(
                &poles, regions: (0..<regionCount).filter { needPole[$0] }, room: room,
                shapes: RegionShapes(points: geo.points, edges: edges, topology: room.topology), cancel: cancel)
            needPole = [Bool](repeating: false, count: regionCount)
            var pick = [Bool](repeating: false, count: edgeCount)
            var short = 0
            for r in 0..<regionCount where poles.radius[r] < room.minRadius[r] - Self.labelRoomSlack {
                short += 1
                roomRegion[r] = true
                let seed = room.seeds[r]
                let reach = Double(room.minRadius[r]) + 1
                let ringStart = Int(room.topology.regionRingStart[r]), ringCount = Int(room.topology.regionRingCount[r])
                for ring in room.topology.rings[ringStart..<(ringStart + ringCount)] {
                    for ref in room.topology.ringEdges[Int(ring.edgeStart)..<Int(ring.edgeStart + ring.edgeCount)] {
                        let e = Int(ref.edge)
                        guard !pick[e], shapes[e] < Shape.lattice.rawValue, graph.edgeRight[e] != BoundaryEdge.outside else { continue }
                        let s = Int(geo.start[e]), c = Int(geo.count[e])
                        for i in s..<(s + c - 1) where FlatPolygon.segmentDistanceSquared(
                            seed.x, seed.y, SIMD2<Double>(geo.points[i]), SIMD2<Double>(geo.points[i + 1])) < reach * reach {
                            pick[e] = true
                            break
                        }
                    }
                }
            }
            let demote = (0..<edgeCount).filter { pick[$0] }
            // Empty once every label has its room; never while one is short (see above), so
            // `unmet` stays zero unless that argument breaks.
            if demote.isEmpty {
                unmet = short
                break
            }
            for e in demote { roomEdge[e] = true }
            dirty = step(demote, shapes: &shapes)
        }
        return SmoothingResult(
            geometry: geo, repairs: repairs, labelRoomEdges: roomEdge.count(where: { $0 }),
            labelRoomRegions: roomRegion.count(where: { $0 }), labelRoomUnmet: unmet, poles: room == nil ? nil : poles)
    }

    /// Tolerance of the label room check: a lattice polygon clears exactly the seed's lattice
    /// clearance, but `PolyLabel` measures it along a different route of float operations.
    static let labelRoomSlack: Float = 1e-4

    /// Places the labels of `regions` at the poles of their current polygons. A label short
    /// of its room is searched again more finely before it counts as failing: the coarse
    /// search only promises a pole within `Vectorizer.labelPrecision` of the best one.
    private func placeLabels(
        _ poles: inout LabelPoles, regions list: [Int], room: LabelRoom, shapes: RegionShapes, cancel: CancellationCheck
    ) throws {
        for first in stride(from: 0, to: list.count, by: 512) {
            try cancel.throwIfCancelled()
            let wave = Array(list[first..<min(list.count, first + 512)])
            let found = mapChunks(wave.count, chunk: 16, cost: { shapes.pointCount(wave[$0]) }) { range -> [(SIMD2<Double>, Double)] in
                var poly = FlatPolygon()
                return range.map { k in
                    let r = wave[k]
                    shapes.polygon(r, into: &poly)
                    let precision = room.measureFinely[r] ? Vectorizer.smallRegionLabelPrecision : Vectorizer.labelPrecision
                    var label = PolyLabel.find(poly, precision: precision, seed: room.seeds[r])
                    if precision > Vectorizer.finePrecision, Float(label.distance) < room.minRadius[r] - Self.labelRoomSlack {
                        let fine = PolyLabel.find(poly, precision: Vectorizer.finePrecision, seed: room.seeds[r])
                        if fine.distance > label.distance { label = fine }
                    }
                    return label
                }
            }
            for (k, label) in found.joined().enumerated() {
                poles.position[wave[k]] = SIMD2<Float>(label.0)
                poles.radius[wave[k]] = Float(label.1)
            }
        }
    }

    // MARK: - Polylines

    func polylines(for list: [Int], shapes: [UInt8]) -> (points: [SIMD2<Float>], counts: [Int32]) {
        // Edge lengths vary wildly (a coastline next to specks), so small chunks are handed
        // out dynamically.
        let bands = mapChunks(list.count, chunk: 48, cost: { Int(graph.edgeStepCount[list[$0]]) }) { range -> ([SIMD2<Float>], [Int32]) in
            var worker = Worker(
                fitter: CurveFitter(alphaMax: alphaMax, minCornerAngle: minCornerAngle, cornerRadius: cornerRadius, flattenTolerance: tolerance),
                fairing: CurveFairing(halfWindow: fairingWindow, maxShift: fairingShift, tolerance: tolerance))
            var pts: [SIMD2<Float>] = []
            var counts: [Int32] = []
            counts.reserveCapacity(range.count)
            for k in range {
                let e = list[k]
                let before = pts.count
                emit(e, shape: Shape(rawValue: shapes[e]) ?? .lattice, worker: &worker, into: &pts)
                counts.append(Int32(pts.count - before))
            }
            return (pts, counts)
        }
        var points: [SIMD2<Float>] = []
        var counts: [Int32] = []
        points.reserveCapacity(bands.reduce(0) { $0 + $1.0.count })
        counts.reserveCapacity(list.count)
        for band in bands {
            points.append(contentsOf: band.0)
            counts.append(contentsOf: band.1)
        }
        return (points, counts)
    }

    /// Per-thread scratch state.
    private struct Worker {
        var fitter: CurveFitter
        var fairing: CurveFairing
        var lattice: [SIMD2<Int32>] = []
        var dense = DenseCurve()
        var scratch: [SIMD2<Double>] = []
    }

    private func emit(_ e: Int, shape requested: Shape, worker w: inout Worker, into out: inout [SIMD2<Float>]) {
        graph.latticePoints(e, into: &w.lattice)
        let lattice = w.lattice
        let closed = graph.edgeClosed[e]
        w.scratch.removeAll(keepingCapacity: true)
        var shape = requested
        if graph.edgeRight[e] == BoundaryEdge.outside { shape = .lattice }
        if shape == .faired || shape == .fitted {
            let ok = closed ? w.fitter.fitClosed(lattice, into: &w.dense) : w.fitter.fitOpen(lattice, into: &w.dense)
            if !ok { shape = .midpoints }
        }
        switch shape {
        case .faired:
            w.fairing.fair(w.dense, closed: closed, into: &w.scratch)
        case .fitted:
            w.scratch.append(contentsOf: w.dense.points)
        case .midpoints:
            let n = lattice.count - 1
            @inline(__always) func mid(_ k: Int) -> SIMD2<Double> {
                SIMD2(Double(lattice[k].x + lattice[k + 1].x) * 0.5, Double(lattice[k].y + lattice[k + 1].y) * 0.5)
            }
            if closed {
                for k in 0..<n { w.scratch.append(mid(k)) }
                w.scratch.append(w.scratch[0])
            } else {
                w.scratch.append(SIMD2(Double(lattice[0].x), Double(lattice[0].y)))
                for k in 0..<n { w.scratch.append(mid(k)) }
                w.scratch.append(SIMD2(Double(lattice[n].x), Double(lattice[n].y)))
            }
        case .lattice:
            for p in lattice { w.scratch.append(SIMD2(Double(p.x), Double(p.y))) }
        }
        EdgeSmoother.appendQuantized(w.scratch, closed: closed, into: &out)
    }

    /// Snaps to the coordinate grid, drops repeated points and exactly collinear interior
    /// points (end points always stay).
    static func appendQuantized(_ pts: [SIMD2<Double>], closed: Bool, into out: inout [SIMD2<Float>]) {
        let q = Double(1 / Template.coordinateQuantum)
        let base = out.count
        for (i, p) in pts.enumerated() {
            var s = SIMD2(Float((p.x * q).rounded() / q), Float((p.y * q).rounded() / q))
            if closed && i == pts.count - 1 { s = out[base] }
            if out.count > base && out[out.count - 1] == s { continue }
            while out.count - base >= 2 {
                let a = SIMD2<Double>(out[out.count - 2]), b = SIMD2<Double>(out[out.count - 1]), c = SIMD2<Double>(s)
                let u = b - a, v = c - b
                if u.x * v.y - u.y * v.x == 0 && u.x * v.x + u.y * v.y > 0 {
                    out.removeLast()
                } else {
                    break
                }
            }
            out.append(s)
        }
    }

    // MARK: - Junction order

    /// Edges at junctions where smoothing changed the cyclic order in which edges leave
    /// the junction (which would flip a region's corner inside out without any crossing).
    func junctionOrderViolations(_ geo: EdgePolylines) -> [Int] {
        let q = Double(1 / Template.coordinateQuantum)
        let found = Parallel.mapBands(graph.junctions.count, minimumBandSize: 256) { range -> [Int] in
            var out: [Int] = []
            var dirs: [SIMD2<Int64>] = []
            var edgesHere: [Int] = []
            for j in range {
                dirs.removeAll(keepingCapacity: true)
                edgesHere.removeAll(keepingCapacity: true)
                for d in 0..<4 {
                    let code = Int(graph.junctionSlots[j * 4 + d])
                    guard code >= 0 else { continue }
                    let e = code >> 1
                    let s = Int(geo.start[e]), c = Int(geo.count[e])
                    let a = code & 1 == 0 ? geo.points[s] : geo.points[s + c - 1]
                    let b = code & 1 == 0 ? geo.points[s + 1] : geo.points[s + c - 2]
                    dirs.append(SIMD2(Int64((Double(b.x - a.x) * q).rounded()), Int64((Double(b.y - a.y) * q).rounded())))
                    edgesHere.append(e)
                }
                // Lattice directions east, south, west, north are in increasing angle, so the
                // smoothed directions must be strictly increasing cyclically: exactly one descent.
                var descents = 0
                for k in 0..<dirs.count where !EdgeSmoother.angleLess(dirs[k], dirs[(k + 1) % dirs.count]) {
                    descents += 1
                }
                if descents != 1 { out.append(contentsOf: edgesHere) }
            }
            return out
        }
        return Array(found.joined())
    }

    /// Strict angular order of direction vectors by atan2(y, x) in [0, 2π).
    @inline(__always)
    static func angleLess(_ u: SIMD2<Int64>, _ v: SIMD2<Int64>) -> Bool {
        let hu = u.y < 0 || (u.y == 0 && u.x < 0) ? 1 : 0
        let hv = v.y < 0 || (v.y == 0 && v.x < 0) ? 1 : 0
        if hu != hv { return hu < hv }
        return u.x * v.y - u.y * v.x > 0
    }
}
