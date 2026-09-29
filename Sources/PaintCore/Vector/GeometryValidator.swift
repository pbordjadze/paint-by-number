/// Exact checks that boundary polylines form a valid planar subdivision: no two segments
/// may cross, overlap or touch, except consecutive segments of one edge at their shared
/// vertex and edges meeting at their end points (junctions).
///
/// Predicates are evaluated exactly in integer arithmetic on the template's coordinate
/// grid (multiples of `Template.coordinateQuantum`); segments are bucketed into a uniform
/// grid so the check runs in near-linear time.
public enum GeometryValidator {

    /// Indices of all edges involved in an improper contact (or containing a zero-length
    /// segment), ascending. Empty when the geometry is valid.
    public static func invalidEdges(points: [SIMD2<Float>], edges: [BoundaryEdge], cellSize: Float = 6) -> [Int] {
        invalidEdges(points: points, edges: edges, cellSize: cellSize, onlyInvolving: nil)
    }

    /// As above, but only tests pairs where at least one edge is flagged in `onlyInvolving`.
    static func invalidEdges(points: [SIMD2<Float>], edges: [BoundaryEdge], cellSize: Float = 6, onlyInvolving dirty: [Bool]?) -> [Int] {
        guard !edges.isEmpty else { return [] }
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
        var segEdge = [Int32](repeating: -1, count: points.count)
        var bad = Set<Int>()
        var lo = SIMD2<Int64>(repeating: .max), hi = SIMD2<Int64>(repeating: .min)
        for (e, edge) in edges.enumerated() {
            let a = Int(edge.pointStart), n = Int(edge.pointCount)
            guard n >= 2, a + n <= points.count else { bad.insert(e); continue }
            for s in a..<(a + n - 1) {
                segEdge[s] = Int32(e)
                if fixed[s] == fixed[s + 1] { bad.insert(e) }
            }
            for s in a..<(a + n) {
                lo = pointwiseMin(lo, fixed[s]); hi = pointwiseMax(hi, fixed[s])
            }
        }
        guard lo.x <= hi.x else { return bad.sorted() }

        let cell = max(Int64(1), Int64((Double(cellSize) * Double(scale)).rounded()))
        let gw = Int((hi.x - lo.x) / cell) + 1, gh = Int((hi.y - lo.y) / cell) + 1
        @inline(__always) func cellX(_ v: Int64) -> Int { Int((v - lo.x) / cell) }
        @inline(__always) func cellY(_ v: Int64) -> Int { Int((v - lo.y) / cell) }

        // Bucket segments by the cells their bounding boxes overlap (CSR).
        var cellStart = [Int32](repeating: 0, count: gw * gh + 1)
        for s in 0..<points.count where segEdge[s] >= 0 {
            let a = fixed[s], b = fixed[s + 1]
            for cy in cellY(min(a.y, b.y))...cellY(max(a.y, b.y)) {
                for cx in cellX(min(a.x, b.x))...cellX(max(a.x, b.x)) { cellStart[cy * gw + cx + 1] += 1 }
            }
        }
        for c in 0..<(gw * gh) { cellStart[c + 1] += cellStart[c] }
        var cursor = cellStart
        var cellSegs = [Int32](repeating: 0, count: Int(cellStart[gw * gh]))
        for s in 0..<points.count where segEdge[s] >= 0 {
            let a = fixed[s], b = fixed[s + 1]
            for cy in cellY(min(a.y, b.y))...cellY(max(a.y, b.y)) {
                for cx in cellX(min(a.x, b.x))...cellX(max(a.x, b.x)) {
                    cellSegs[Int(cursor[cy * gw + cx])] = Int32(s)
                    cursor[cy * gw + cx] += 1
                }
            }
        }

        let found = Parallel.mapBands(gh, minimumBandSize: 4) { rows -> [Int] in
            var out: [Int] = []
            for cy in rows {
                for cx in 0..<gw {
                    let c = cy * gw + cx
                    let s0 = Int(cellStart[c]), s1 = Int(cellStart[c + 1])
                    guard s1 - s0 >= 2 else { continue }
                    for i in s0..<(s1 - 1) {
                        let a = Int(cellSegs[i])
                        let a0 = fixed[a], a1 = fixed[a + 1]
                        let aMin = pointwiseMin(a0, a1), aMax = pointwiseMax(a0, a1)
                        let aDirty = dirty?[Int(segEdge[a])] ?? true
                        for j in (i + 1)..<s1 {
                            let b = Int(cellSegs[j])
                            if !aDirty && !(dirty?[Int(segEdge[b])] ?? true) { continue }
                            let b0 = fixed[b], b1 = fixed[b + 1]
                            let bMin = pointwiseMin(b0, b1), bMax = pointwiseMax(b0, b1)
                            if aMax.x < bMin.x || bMax.x < aMin.x || aMax.y < bMin.y || bMax.y < aMin.y { continue }
                            // Test each pair once: in the cell holding the overlap's min corner.
                            let ox = max(aMin.x, bMin.x), oy = max(aMin.y, bMin.y)
                            if cellX(ox) != cx || cellY(oy) != cy { continue }
                            if conflict(a, b, fixed: fixed, segEdge: segEdge, edges: edges) {
                                out.append(Int(segEdge[a])); out.append(Int(segEdge[b]))
                            }
                        }
                    }
                }
            }
            return out
        }
        for list in found { bad.formUnion(list) }
        return bad.sorted()
    }

    @inline(__always)
    static func orient(_ a: SIMD2<Int64>, _ b: SIMD2<Int64>, _ c: SIMD2<Int64>) -> Int64 {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    @inline(__always)
    private static func onSegment(_ p: SIMD2<Int64>, _ q: SIMD2<Int64>, _ r: SIMD2<Int64>) -> Bool {
        q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) && q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)
    }

    /// Whether closed segments p1q1 and p2q2 share at least one point.
    @inline(__always)
    static func segmentsIntersect(_ p1: SIMD2<Int64>, _ q1: SIMD2<Int64>, _ p2: SIMD2<Int64>, _ q2: SIMD2<Int64>) -> Bool {
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
        _ a: Int, _ b: Int, fixed: [SIMD2<Int64>], segEdge: [Int32], edges: [BoundaryEdge]
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
            let dot = (oa.x - s.x) * (ob.x - s.x) + (oa.y - s.y) * (ob.y - s.y)
            if dot > 0 { return true }
        }
        let ea = Int(segEdge[a]), eb = Int(segEdge[b])
        // Consecutive segments of one edge.
        if ea == eb && ((b == a + 1 && !aAtStart && bAtStart) || (a == b + 1 && aAtStart && !bAtStart)) { return false }
        // Both segments end at an end point (junction) of their edges.
        let edgeA = edges[ea], edgeB = edges[eb]
        let aAtEdgeEnd = aAtStart ? a == Int(edgeA.pointStart) : a + 2 == Int(edgeA.pointStart + edgeA.pointCount)
        let bAtEdgeEnd = bAtStart ? b == Int(edgeB.pointStart) : b + 2 == Int(edgeB.pointStart + edgeB.pointCount)
        return !(aAtEdgeEnd && bAtEdgeEnd)
    }
}
