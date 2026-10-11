/// Exact checks that boundary polylines form a valid planar subdivision: no two segments
/// may cross, overlap or touch, except consecutive segments of one edge at their shared
/// vertex and edges meeting at their end points (junctions).
///
/// Predicates are evaluated exactly in integer arithmetic on the template's coordinate
/// grid (multiples of `Template.coordinateQuantum`); segments are bucketed into a uniform
/// grid. `check` bounds expansion and candidate pairs for decoded templates; the dense grid
/// is linear in the decoded canvas. The smoother's trusted geometry uses `invalidEdges`
/// without those budgets so validation limits cannot change pipeline output.
enum GeometryValidator {
    /// Side of a bucket of the uniform grid, canvas units.
    private static let cellSize: Float = 6

    struct Report {
        var invalidEdges: [Int] = []
        var workLimitReason: String?
    }

    /// Indices of all edges involved in an improper contact (or containing a zero-length
    /// segment), ascending. Empty when the geometry is valid. With `onlyInvolving`, only
    /// pairs where at least one edge is flagged are tested. For the smoother's trusted
    /// geometry; decoded templates must use the bounded `check` instead.
    static func invalidEdges(points: [SIMD2<Float>], edges: [BoundaryEdge], onlyInvolving dirty: [Bool]? = nil) -> [Int] {
        let report = check(points: points, edges: edges, onlyInvolving: dirty, boundWork: false)
        return report.workLimitReason == nil ? report.invalidEdges : Array(edges.indices)
    }

    static func check(points: [SIMD2<Float>], edges: [BoundaryEdge], onlyInvolving dirty: [Bool]? = nil,
                      boundWork: Bool = true) -> Report {
        guard !edges.isEmpty else { return Report() }
        var work = ValidationWorkBudget(counts: [points.count, edges.count])
        func exceeded(_ stage: String) -> Report {
            Report(workLimitReason: "geometry \(stage) (limit \(work.limit))")
        }
        let scale = Double(1 / Template.coordinateQuantum)
        var fixed = [SIMD2<Int64>](repeating: .zero, count: points.count)
        if !points.isEmpty { points.withUnsafeBufferPointer { pb in
            fixed.withUnsafeMutableBufferPointer { fb in
                let p = UncheckedSendable(pb.baseAddress!), f = UncheckedSendable(fb.baseAddress!)
                Parallel.forEachBand(pb.count, minimumBandSize: 8192) { range in
                    for i in range {
                        let q = p.value[i]
                        f.value[i] = SIMD2(Int64((Double(q.x) * scale).rounded()), Int64((Double(q.y) * scale).rounded()))
                    }
                }
            }
        } }

        // Segment s runs from fixed[s] to fixed[s + 1]; segEdge[s] < 0 marks the last point
        // of an edge (no segment starts there).
        var segEdge = [Int](repeating: -1, count: points.count)
        var bad = Set<Int>()
        var lo = SIMD2<Int64>(repeating: .max), hi = SIMD2<Int64>(repeating: .min)
        for (e, edge) in edges.enumerated() {
            let a = Int(edge.pointStart), n = Int(edge.pointCount)
            guard n >= 2, a + n <= points.count else { bad.insert(e); continue }
            guard !boundWork || work.consume(n) else { return exceeded("segment spans") }
            for s in a..<(a + n - 1) {
                segEdge[s] = e
                if fixed[s] == fixed[s + 1] { bad.insert(e) }
            }
            for s in a..<(a + n) {
                lo = pointwiseMin(lo, fixed[s]); hi = pointwiseMax(hi, fixed[s])
            }
        }
        guard lo.x <= hi.x else { return Report(invalidEdges: edges.indices.filter { bad.contains($0) }) }

        let cell = max(Int64(1), Int64((Double(Self.cellSize) * Double(scale)).rounded()))
        let gw = Int((hi.x - lo.x) / cell) + 1, gh = Int((hi.y - lo.y) / cell) + 1
        let (cells, overflow) = gw.multipliedReportingOverflow(by: gh)
        // A decoded canvas has at most maxCanvasArea pixels, and cells are six units wide.
        guard !overflow, cells > 0, cells <= Template.maxCanvasArea else { return exceeded("grid cells") }
        @inline(__always) func cellX(_ v: Int64) -> Int { Int((v - lo.x) / cell) }
        @inline(__always) func cellY(_ v: Int64) -> Int { Int((v - lo.y) / cell) }

        // Bucket segments by the cells their bounding boxes overlap (CSR).
        var cellStart = [Int](repeating: 0, count: cells + 1)
        for s in 0..<points.count where segEdge[s] >= 0 {
            let a = fixed[s], b = fixed[s + 1]
            let cols = cellX(max(a.x, b.x)) - cellX(min(a.x, b.x)) + 1
            let rows = cellY(max(a.y, b.y)) - cellY(min(a.y, b.y)) + 1
            guard !boundWork || work.consume(cols, times: rows) else { return exceeded("bucket entries") }
            for cy in cellY(min(a.y, b.y))...cellY(max(a.y, b.y)) {
                for cx in cellX(min(a.x, b.x))...cellX(max(a.x, b.x)) { cellStart[cy * gw + cx + 1] += 1 }
            }
        }
        // Charge every pair the nested loop will visit, including duplicates in other cells
        // and clean pairs skipped by incremental validation. Divide before multiplying.
        for c in 0..<cells {
            let n = cellStart[c + 1]
            let a = n.isMultiple(of: 2) ? n / 2 : n
            let b = n.isMultiple(of: 2) ? max(0, n - 1) : (n - 1) / 2
            guard !boundWork || work.consume(a, times: b) else { return exceeded("candidate pairs") }
            cellStart[c + 1] += cellStart[c]
        }
        var cursor = cellStart
        var cellSegs = [Int](repeating: 0, count: cellStart[cells])
        for s in 0..<points.count where segEdge[s] >= 0 {
            let a = fixed[s], b = fixed[s + 1]
            for cy in cellY(min(a.y, b.y))...cellY(max(a.y, b.y)) {
                for cx in cellX(min(a.x, b.x))...cellX(max(a.x, b.x)) {
                    cellSegs[cursor[cy * gw + cx]] = s
                    cursor[cy * gw + cx] += 1
                }
            }
        }

        let found = Parallel.mapBands(gh, minimumBandSize: 4) { rows -> [Int] in
            var out: [Int] = []
            for cy in rows {
                for cx in 0..<gw {
                    let c = cy * gw + cx
                    let s0 = cellStart[c], s1 = cellStart[c + 1]
                    guard s1 - s0 >= 2 else { continue }
                    for i in s0..<(s1 - 1) {
                        let a = cellSegs[i]
                        let a0 = fixed[a], a1 = fixed[a + 1]
                        let aMin = pointwiseMin(a0, a1), aMax = pointwiseMax(a0, a1)
                        let aDirty = dirty?[segEdge[a]] ?? true
                        for j in (i + 1)..<s1 {
                            let b = cellSegs[j]
                            if !aDirty && !(dirty?[segEdge[b]] ?? true) { continue }
                            let b0 = fixed[b], b1 = fixed[b + 1]
                            let bMin = pointwiseMin(b0, b1), bMax = pointwiseMax(b0, b1)
                            if aMax.x < bMin.x || bMax.x < aMin.x || aMax.y < bMin.y || bMax.y < aMin.y { continue }
                            // Test each pair once: in the cell holding the overlap's min corner.
                            let ox = max(aMin.x, bMin.x), oy = max(aMin.y, bMin.y)
                            if cellX(ox) != cx || cellY(oy) != cy { continue }
                            if conflict(a, b, fixed: fixed, segEdge: segEdge, edges: edges) {
                                out.append(segEdge[a]); out.append(segEdge[b])
                            }
                        }
                    }
                }
            }
            return out
        }
        for list in found { bad.formUnion(list) }
        return Report(invalidEdges: edges.indices.filter { bad.contains($0) })
    }

    @inline(__always)
    private static func orient(_ a: SIMD2<Int64>, _ b: SIMD2<Int64>, _ c: SIMD2<Int64>) -> Int64 {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    @inline(__always)
    private static func onSegment(_ p: SIMD2<Int64>, _ q: SIMD2<Int64>, _ r: SIMD2<Int64>) -> Bool {
        q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) && q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)
    }

    /// Whether closed segments p1q1 and p2q2 share at least one point.
    @inline(__always)
    private static func segmentsIntersect(_ p1: SIMD2<Int64>, _ q1: SIMD2<Int64>, _ p2: SIMD2<Int64>, _ q2: SIMD2<Int64>) -> Bool {
        let o1 = orient(p1, q1, p2).signum(), o2 = orient(p1, q1, q2).signum()
        let o3 = orient(p2, q2, p1).signum(), o4 = orient(p2, q2, q1).signum()
        if o1 * o2 < 0 && o3 * o4 < 0 { return true }
        if o1 == 0 && onSegment(p1, p2, q1) { return true }
        if o2 == 0 && onSegment(p1, q2, q1) { return true }
        if o3 == 0 && onSegment(p2, p1, q2) { return true }
        if o4 == 0 && onSegment(p2, q1, q2) { return true }
        return false
    }

    /// Whether segments a and b (identified by their start point index) touch improperly.
    private static func conflict(
        _ a: Int, _ b: Int, fixed: [SIMD2<Int64>], segEdge: [Int], edges: [BoundaryEdge]
    ) -> Bool {
        let p1 = fixed[a], q1 = fixed[a + 1], p2 = fixed[b], q2 = fixed[b + 1]
        let shared = (p1 == p2 ? 1 : 0) + (p1 == q2 ? 1 : 0) + (q1 == p2 ? 1 : 0) + (q1 == q2 ? 1 : 0)
        if shared == 0 { return segmentsIntersect(p1, q1, p2, q2) }
        if shared >= 2 { return true }
        // Exactly one shared end point S; the segments touch nowhere else unless they are
        // collinear and leave S in the same direction.
        let aAtStart = p1 == p2 || p1 == q2
        let bAtStart = p2 == p1 || p2 == q1
        let s = aAtStart ? p1 : q1
        let oa = aAtStart ? q1 : p1, ob = bAtStart ? q2 : p2
        if orient(s, oa, ob) == 0 {
            // Collinear nonzero rays agree iff a nonzero component has the same sign.
            // A dot product can overflow on a long, thin canvas accepted by the decoder.
            if oa.x != s.x {
                if (oa.x - s.x).signum() == (ob.x - s.x).signum() { return true }
            } else if (oa.y - s.y).signum() == (ob.y - s.y).signum() { return true }
        }
        let ea = segEdge[a], eb = segEdge[b]
        // Consecutive segments of one edge.
        if ea == eb && ((b == a + 1 && !aAtStart && bAtStart) || (a == b + 1 && aAtStart && !bAtStart)) { return false }
        // Both segments end at an end point (junction) of their edges.
        let edgeA = edges[ea], edgeB = edges[eb]
        let aAtEdgeEnd = aAtStart ? a == Int(edgeA.pointStart) : a + 2 == Int(edgeA.pointStart) + Int(edgeA.pointCount)
        let bAtEdgeEnd = bAtStart ? b == Int(edgeB.pointStart) : b + 2 == Int(edgeB.pointStart) + Int(edgeB.pointCount)
        return !(aAtEdgeEnd && bAtEdgeEnd)
    }
}
