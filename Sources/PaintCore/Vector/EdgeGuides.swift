/// The painter's lines (Refine's pen and shapes, `LineArtInput.edits`) as boundary geometry: an
/// edge whose lattice chain runs along one, every corner within `reach` of it and in its order,
/// takes the line's own path between the corners' projections onto it, joined to the chain's end
/// corners (the junctions other edges share), so the area a painter's shape closes is bounded by
/// the shape as drawn, its corners and points too, rather than by its smoothed pixel outline
/// (`EdgeSmoother.Shape.drawn`; the repair loop steps an edge down as any other where that path
/// would cross a neighbour).
///
/// A line splits the paint along the pixels it crosses (`LineLayering.walls`) and those pixels
/// join the cells beside them, so the cell boundary along it keeps within a pixel's diagonal of
/// the line; its junctions with other boundaries a little farther.
enum EdgeGuides {
    /// How far a chain's corners may lie from the line they follow, and its two end corners.
    static let reach: Double = 1.75
    static let endReach: Double = 2.5
    /// How far a corner's projection may fall back along the line (corners step around it).
    static let slack: Double = 1.5

    /// A painter's line prepared for projection: points without repeats, arc length at each.
    struct Guide {
        var points: [SIMD2<Double>]
        var arc: [Double]
        var closed: Bool
        var low: SIMD2<Double>
        var high: SIMD2<Double>

        init?(_ line: [SIMD2<Float>]) {
            var points: [SIMD2<Double>] = []
            for p in line where p.x.isFinite && p.y.isFinite {
                let q = SIMD2<Double>(p)
                if let last = points.last, simdLength(q - last) < 1e-6 { continue }
                points.append(q)
            }
            guard points.count >= 2 else { return nil }
            var arc = [0.0]
            for (a, b) in zip(points, points.dropFirst()) { arc.append(arc[arc.count - 1] + simdLength(b - a)) }
            self.points = points
            self.arc = arc
            closed = points.count >= 4 && simdLength(points[0] - points[points.count - 1]) < 1e-3
            low = points.reduce(points[0]) { pointwiseMin($0, $1) }
            high = points.reduce(points[0]) { pointwiseMax($0, $1) }
        }

        var length: Double { arc[arc.count - 1] }

        /// The distance from `p` to the line and the arc length of the nearest point.
        func project(_ p: SIMD2<Double>) -> (distance: Double, t: Double) {
            var best = (distance: Double.infinity, t: 0.0)
            for i in 0..<(points.count - 1) {
                let a = points[i], ab = points[i + 1] - a
                let l2 = simdLengthSquared(ab)
                let s = l2 > 0 ? min(max(simdDot(p - a, ab) / l2, 0), 1) : 0
                let d = simdLength(p - (a + ab * s))
                if d < best.distance { best = (d, arc[i] + s * (arc[i + 1] - arc[i])) }
            }
            return best
        }

        /// The point at arc length `t` (taken round a closed line).
        func point(at t: Double) -> SIMD2<Double> {
            var t = t
            if closed, length > 0 { t -= (t / length).rounded(.down) * length }
            t = min(max(t, 0), length)
            var lo = 0, hi = arc.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if arc[mid] <= t { lo = mid } else { hi = mid }
            }
            let span = arc[hi] - arc[lo]
            return span > 0 ? points[lo] + (points[hi] - points[lo]) * ((t - arc[lo]) / span) : points[lo]
        }

        /// The line's vertices strictly between arc lengths `a` and `b`, in order from `a` to `b`
        /// (round a closed line as often as the range does).
        func vertices(from a: Double, to b: Double) -> [SIMD2<Double>] {
            let lo = min(a, b), hi = max(a, b)
            var found: [(t: Double, p: SIMD2<Double>)] = []
            let last = closed ? points.count - 1 : points.count
            let laps: ClosedRange<Int> = closed && length > 0
                ? Int((lo / length).rounded(.down)) - 1...Int((hi / length).rounded(.up)) + 1 : 0...0
            for lap in laps {
                for i in 0..<last {
                    let t = arc[i] + Double(lap) * length
                    if t > lo && t < hi { found.append((t, points[i])) }
                }
            }
            found.sort { $0.t < $1.t }
            let ordered = found.map(\.p)
            return a <= b ? ordered : ordered.reversed()
        }
    }

    /// Per interior edge that follows one of `guides` (template coordinates), the path it takes.
    static func paths(graph: BoundaryGraph, guides lines: [[SIMD2<Float>]]) -> [Int: [SIMD2<Double>]] {
        let guides = lines.compactMap(Guide.init)
        guard !guides.isEmpty else { return [:] }
        var out: [Int: [SIMD2<Double>]] = [:]
        var lattice: [SIMD2<Int32>] = []
        for e in 0..<graph.edgeCount where graph.edgeRight[e] != BoundaryEdge.outside {
            graph.latticePoints(e, into: &lattice)
            guard lattice.count >= 3 else { continue }
            let corners = lattice.map { SIMD2<Double>(Double($0.x), Double($0.y)) }
            let low = corners.reduce(corners[0]) { pointwiseMin($0, $1) } - endReach
            let high = corners.reduce(corners[0]) { pointwiseMax($0, $1) } + endReach
            for guide in guides where all(guide.low .<= high) && all(guide.high .>= low) {
                if let path = follow(corners, guide, closed: graph.edgeClosed[e]) {
                    out[e] = path
                    break
                }
            }
        }
        return out
    }

    /// The path of the chain `corners` along `guide`, if it follows the guide.
    static func follow(_ corners: [SIMD2<Double>], _ guide: Guide, closed: Bool) -> [SIMD2<Double>]? {
        let n = corners.count
        var ts: [Double] = []
        ts.reserveCapacity(n)
        for (i, c) in corners.enumerated() {
            let (d, t) = guide.project(c)
            guard d <= (!closed && (i == 0 || i == n - 1) ? endReach : reach) else { return nil }
            ts.append(t)
        }
        let length = guide.length
        if guide.closed {
            for i in 1..<n {
                while ts[i] - ts[i - 1] > length / 2 { ts[i] -= length }
                while ts[i] - ts[i - 1] < -length / 2 { ts[i] += length }
            }
        }
        let span = ts[n - 1] - ts[0], forward = span >= 0
        var extreme = ts[0]
        for t in ts.dropFirst() {
            guard forward ? t >= extreme - slack : t <= extreme + slack else { return nil }
            extreme = forward ? max(extreme, t) : min(extreme, t)
        }
        if closed {
            // Once round a closed line, starting anywhere on it.
            guard guide.closed, abs(abs(span) - length) <= 2 * reach else { return nil }
            let start = guide.point(at: ts[0]), end = ts[0] + (forward ? length : -length)
            return [start] + guide.vertices(from: ts[0], to: end) + [start]
        }
        // Along the line, not across it: a staircase is at most √2 times the line it follows.
        guard abs(span) >= 0.4 * Double(n - 1) else { return nil }
        return [corners[0], guide.point(at: ts[0])] + guide.vertices(from: ts[0], to: ts[n - 1])
            + [guide.point(at: ts[n - 1]), corners[n - 1]]
    }
}
