import Foundation

/// Fits a smooth curve to a lattice chain and flattens it into a `DenseCurve`.
///
/// An independent implementation of the method described in P. Selinger, "Potrace: a
/// polygon-based tracing algorithm" (2003), written from the paper (not derived from
/// potrace's source code) and extended to open chains with pinned ends. Stages:
///
/// 1. Straight runs (§2.2.1): for every start vertex the longest straight subpath. With
///    the start fixed, the paper's triplewise criterion is a cone of directions from it
///    that narrows with every vertex, so a start costs one pass over its run; a run never
///    outlasts the run of the next start by more than a step.
/// 2. Optimal polygon (§2.2.2–2.2.4): a segment may join vertices i and j when the path
///    from i − 1 to j + 1 is straight. The ends of the segments from i never decrease
///    with i, so jumping as far as possible gives the fewest segments, and a vertex can
///    only be the c-th vertex of a polygon with that many segments within an interval
///    found by jumping forward and backward. The least summed penalty (constant time per
///    segment from prefix sums) is then a shortest path through those intervals.
/// 3. Vertex adjustment (§2.3.1): each vertex moves within its unit square to the point
///    with the least squared distance to the least-squares lines of its two segments.
/// 4. Corners and smoothing (§2.3.2–2.3.3): each vertex becomes a Bézier curve between
///    the midpoints of its edges with the paper's α, clamped to 0.55…1, or a corner.
/// 5. Curve optimization (§2.4): runs of curves of one convexity turning less than 179°
///    are replaced by single curves enclosing the same area where every tangency check
///    passes within 0.2; again fewest curves first, then least penalty.
/// 6. Flattening: each cubic is split into enough uniform parameter steps that the
///    polyline stays within `flattenTolerance` of it.
///
/// Beyond the paper:
/// - Open chains keep their end points fixed: they are polygon vertices that are never
///   adjusted, straightness at an end is judged without the missing outer neighbour, and
///   the curve leaves and enters them along straight half-edges, like corners. A chain
///   whose ends coincide (a loop through a junction) uses the closed-path rules with its
///   end as a forced vertex.
/// - A closed path is searched from every start within the shortest segment reach of any
///   vertex s: a segment passing over s could start at s instead, so every polygon has a
///   vertex there, and the best of those searches is the optimal polygon.
/// - A loop at most a pixel thick lies within max-distance 1/2 of its centre line, so
///   nearly all of it counts as straight and its optimal polygon collapses into a lopsided
///   triangle. Such loops (a triangle enclosing under ¾ of the loop) use their lattice
///   corners as the polygon instead, which rounds bars and specks evenly.
/// - A vertex becomes a corner only when α reaches `alphaMax` *and* the polygon turns
///   there by at least `minCornerAngle`, so long sides meeting at a gentle bend stay smooth.
/// - With `cornerRadius` > 0 corners are rounded by a cubic approximating the circular arc
///   of that radius tangent to both edges, its tangent length capped by the half-edges.
/// - A joined curve's area-matching α must keep it convex (α ≤ 1); joining stops extending
///   a run at the first candidate that fails its checks. §2.2.3's penalty is computed with
///   −2bxy, the sign its definition (length times deviation from the segment) gives.
struct CurveFitter {
    private let alphaMax: Double
    private let minCornerTurn: Double
    private let cornerRadius: Double
    private let flattenTolerance: Double

    /// Least α of a smooth vertex (§2.3.3): flatter curves look strange.
    private static let lowestAlpha = 0.55
    /// Tolerance of the curve optimization (§2.4).
    private static let joinTolerance = 0.2
    /// Joined curves turn by less than this (§2.4).
    private static let maxJoinTurn = 179 * Double.pi / 180

    // The path, relative to its first point. Cyclic paths are stored twice over so every
    // wrapped range is contiguous; `moments` holds prefix sums of the stored points.
    private var steps = 0
    private var cyclic = false
    private var origin = SIMD2<Double>.zero
    private var px: [Int] = [], py: [Int] = []
    private var direction: [UInt8] = []
    private var moments: [Moments] = []
    /// Per start vertex: steps of the longest straight subpath, and of the longest segment.
    private var straight: [Int] = [], reach: [Int] = []
    /// Per stored index j: the first vertex with a possible segment ending at j.
    private var segmentStart: [Int] = []

    private var ahead: [Int] = [], behind: [Int] = []
    private var dpPenalty: [Double] = [], dpPrevious: [Int] = []
    /// Polygon vertices as stored path indices, ascending.
    private var candidate: [Int] = [], polygon: [Int] = []

    private var lineNormal: [SIMD2<Double>] = [], lineOffset: [Double] = []
    private var vertex: [SIMD2<Double>] = []
    private var corner: [Bool] = [], alpha: [Double] = [], turn: [Double] = []
    private var convexity: [Int8] = [], support: [Double] = []
    private var joint: [SIMD2<Double>] = []

    /// Emission order: vertices, and the joints around them (`knots[q]` before `order[q]`).
    private var order: [Int] = [], knots: [SIMD2<Double>] = []
    private var joinCount: [Int] = [], joinPenalty: [Double] = [], joinPrevious: [Int] = []
    private var joinCurve: [Cubic] = []
    private var chosen: [Int] = []

    init(alphaMax: Double, minCornerAngle: Double, cornerRadius: Double, flattenTolerance: Double) {
        self.alphaMax = alphaMax
        minCornerTurn = minCornerAngle * Double.pi / 180
        self.cornerRadius = max(0, cornerRadius)
        self.flattenTolerance = max(flattenTolerance, 1e-4)
    }

    // MARK: - Entry points

    /// Fits a chain between two junctions. The output starts and ends exactly at the
    /// chain's ends, both pinned; false when the fit degenerates.
    mutating func fitOpen(_ points: [SIMD2<Int32>], into out: inout DenseCurve) -> Bool {
        out.removeAll()
        let n = points.count - 1
        guard n >= 1 else { return false }
        let loop = points[0] == points[n]
        guard !loop || n >= 4, load(points, cyclic: loop) else { return false }
        findStraightRuns()
        findReach()
        fewestSegments(from: 0, to: n)
        leastPenalty(from: 0, to: n)
        polygon.removeAll(keepingCapacity: true)
        polygon.append(contentsOf: candidate)
        polygon.append(n)
        var m = polygon.count - 1
        if loop && m < 3 { return false }
        let thin = loop && m == 3 && collapsed(polygon[0], polygon[1], polygon[2])
        if thin {
            useLatticeCorners(anchored: true)
            m = polygon.count - 1
        } else {
            fitLines(m)
        }
        vertex.removeAll(keepingCapacity: true)
        vertex.append(.zero)
        for k in stride(from: 1, to: m, by: 1) {
            vertex.append(thin ? latticePoint(polygon[k]) : adjustedVertex(k, before: k - 1, after: k))
        }
        vertex.append(latticePoint(n))
        prepareVertices(m + 1)
        for k in stride(from: 1, to: m, by: 1) { analyze(k, previous: vertex[k - 1], next: vertex[k + 1]) }
        for k in 0..<m { joint[k] = (vertex[k] + vertex[k + 1]) * 0.5 }

        put(vertex[0], pinned: true, into: &out)
        if m > 1 {
            order.removeAll(keepingCapacity: true)
            knots.removeAll(keepingCapacity: true)
            for k in 1..<m { order.append(k) }
            knots.append(contentsOf: joint[0..<m])
            put(knots[0], pinned: false, into: &out)
            emitPieces(into: &out)
        }
        put(vertex[m], pinned: true, into: &out)
        return finish(&out, minimumCount: loop ? 4 : 2)
    }

    /// Fits a closed chain (its last point repeats the first). The output repeats its first
    /// point as its last; false when the fit degenerates.
    mutating func fitClosed(_ points: [SIMD2<Int32>], into out: inout DenseCurve) -> Bool {
        out.removeAll()
        let n = points.count - 1
        guard n >= 4, points[0] == points[n], load(points, cyclic: true) else { return false }
        findStraightRuns()
        findReach()
        var s = 0
        for i in 1..<n where reach[i] < reach[s] { s = i }
        var fewest = Int.max
        for t in s...(s + reach[s]) { fewest = min(fewest, fewestSegments(from: t % n, to: t % n + n)) }
        var bestPenalty = Double.infinity
        for t in s...(s + reach[s]) where fewestSegments(from: t % n, to: t % n + n) == fewest {
            let penalty = leastPenalty(from: t % n, to: t % n + n)
            if penalty < bestPenalty {
                bestPenalty = penalty
                polygon.removeAll(keepingCapacity: true)
                polygon.append(contentsOf: candidate)
            }
        }
        var m = polygon.count
        guard m >= 3 else { return false }
        let thin = m == 3 && collapsed(polygon[0], polygon[1], polygon[2])
        if thin {
            useLatticeCorners(anchored: false)
            m = polygon.count
        }
        polygon.append(polygon[0] + n)

        vertex.removeAll(keepingCapacity: true)
        if thin {
            for k in 0..<m { vertex.append(latticePoint(polygon[k])) }
        } else {
            fitLines(m)
            for k in 0..<m { vertex.append(adjustedVertex(k, before: (k + m - 1) % m, after: k)) }
        }
        prepareVertices(m)
        for k in 0..<m { analyze(k, previous: vertex[(k + m - 1) % m], next: vertex[(k + 1) % m]) }
        for k in 0..<m { joint[k] = (vertex[k] + vertex[(k + 1) % m]) * 0.5 }

        order.removeAll(keepingCapacity: true)
        knots.removeAll(keepingCapacity: true)
        if let c = corner[0..<m].firstIndex(of: true) {
            // Start at a corner so the output's first point is a pinned one.
            for q in 1..<m { order.append((c + q) % m) }
            for q in 0..<m { knots.append(joint[(c + q) % m]) }
            let fillet = self.fillet(c, from: knots[m - 1], to: knots[0])
            put(fillet?.z3 ?? vertex[c], pinned: true, into: &out)
            put(knots[0], pinned: false, into: &out)
            emitPieces(into: &out)
            if let fillet {
                put(fillet.z0, pinned: true, into: &out)
                flatten(fillet, pinned: true, into: &out)
            } else {
                put(vertex[c], pinned: true, into: &out)
            }
        } else {
            // Start where no curve could be joined across, if there is such a place.
            var start = m - 1
            for k in 0..<m where !joinable(k, (k + 1) % m) {
                start = k
                break
            }
            for q in 1...m { order.append((start + q) % m) }
            for q in 0...m { knots.append(joint[(start + q) % m]) }
            put(knots[0], pinned: false, into: &out)
            emitPieces(into: &out)
        }
        return finish(&out, minimumCount: 4)
    }

    // MARK: - Path

    private struct Moments {
        var x: Int64 = 0, y: Int64 = 0, xx: Int64 = 0, xy: Int64 = 0, yy: Int64 = 0

        static func - (a: Moments, b: Moments) -> Moments {
            Moments(x: a.x - b.x, y: a.y - b.y, xx: a.xx - b.xx, xy: a.xy - b.xy, yy: a.yy - b.yy)
        }
    }

    /// Stores the path relative to its first point; false unless every step is a unit step.
    private mutating func load(_ points: [SIMD2<Int32>], cyclic: Bool) -> Bool {
        let n = points.count - 1
        steps = n
        self.cyclic = cyclic
        let o = points[0]
        origin = SIMD2(Double(o.x), Double(o.y))
        let stored = cyclic ? 2 * n : n + 1
        px.removeAll(keepingCapacity: true)
        py.removeAll(keepingCapacity: true)
        direction.removeAll(keepingCapacity: true)
        moments.removeAll(keepingCapacity: true)
        var sum = Moments()
        moments.append(sum)
        for k in 0..<stored {
            let p = points[k <= n ? k : k - n]
            let x = Int(p.x) - Int(o.x), y = Int(p.y) - Int(o.y)
            px.append(x)
            py.append(y)
            let x64 = Int64(x), y64 = Int64(y)
            sum.x += x64
            sum.y += y64
            sum.xx += x64 * x64
            sum.xy += x64 * y64
            sum.yy += y64 * y64
            moments.append(sum)
        }
        for k in 0..<(stored - 1) {
            switch (px[k + 1] - px[k], py[k + 1] - py[k]) {
            case (1, 0): direction.append(0)
            case (0, 1): direction.append(1)
            case (-1, 0): direction.append(2)
            case (0, -1): direction.append(3)
            default: return false
            }
        }
        return true
    }

    private func latticePoint(_ i: Int) -> SIMD2<Double> { SIMD2(Double(px[i]), Double(py[i])) }

    // MARK: - Straight runs (§2.2.1)

    private mutating func findStraightRuns() {
        let n = steps
        reset(&straight, n, 0)
        for i in stride(from: n - 1, through: 0, by: -1) {
            // A straight path's subpaths are straight, so a run is at most one step longer
            // than the run of the next start.
            var cap = cyclic ? n - 1 : n - i
            if i < n - 1 { cap = min(cap, straight[i + 1] + 1) }
            straight[i] = straightRun(from: i, upTo: cap)
        }
        if cyclic {
            // Second lap: carry the bound across the wrap.
            straight[n - 1] = min(straight[n - 1], straight[0] + 1)
            for i in stride(from: n - 2, through: 0, by: -1) { straight[i] = min(straight[i], straight[i + 1] + 1) }
        }
    }

    /// Steps of the longest path from vertex i (at most `cap`) that uses at most three
    /// directions and passes the triplewise test for every triple (i, j, k): the line
    /// through v_i and v_k comes within max-distance 1 of v_j. For fixed i that confines
    /// v_k − v_i to the cone from v_i over the squares of radius 1 around all earlier
    /// v_j, kept as its two bounding directions.
    private func straightRun(from i: Int, upTo cap: Int) -> Int {
        let x0 = px[i], y0 = py[i]
        var loX = 0, loY = 0, hiX = 0, hiY = 0
        var seen: UInt8 = 0
        var length = 0
        while length < cap {
            let k = i + length + 1
            seen |= 1 << direction[k - 1]
            if seen == 15 { break }
            let wx = px[k] - x0, wy = py[k] - y0
            if loX * wy - loY * wx < 0 || hiX * wy - hiY * wx > 0 { break }
            length += 1
            guard abs(wx) > 1 || abs(wy) > 1 else { continue }
            // The square's corners at the clockwise and counter-clockwise extremes.
            let lx = wx + (wy > 0 || (wy == 0 && wx < 0) ? 1 : -1)
            let ly = wy + (wx < 0 || (wx == 0 && wy < 0) ? 1 : -1)
            let ux = wx + (wy < 0 || (wy == 0 && wx < 0) ? 1 : -1)
            let uy = wy + (wx < 0 || (wx == 0 && wy > 0) ? -1 : 1)
            if (loX == 0 && loY == 0) || loX * ly - loY * lx > 0 { loX = lx; loY = ly }
            if (hiX == 0 && hiY == 0) || hiX * uy - hiY * ux < 0 { hiX = ux; hiY = uy }
            if loX * hiY - loY * hiX < 0 { break }
        }
        return length
    }

    // MARK: - Optimal polygon (§2.2.2–2.2.4)

    /// Steps of the longest possible segment from each vertex: the path one vertex beyond
    /// both of its ends must be straight (§2.2.2). Open ends have no vertex beyond them.
    private mutating func findReach() {
        let n = steps
        reset(&reach, n, 0)
        for i in 0..<n {
            if cyclic {
                reach[i] = min(n - 3, straight[i == 0 ? n - 1 : i - 1] - 2)
            } else {
                let s = max(0, i - 1)
                let end = s + straight[s]
                reach[i] = (end >= n ? n : end - 1) - i
            }
        }
        let indices = cyclic ? 2 * n : n + 1
        reset(&segmentStart, indices, 0)
        var i = 0
        for j in 1..<indices {
            while i + reach[i >= n ? i - n : i] < j { i += 1 }
            segmentStart[j] = i
        }
    }

    @inline(__always)
    private func reachEnd(_ i: Int, _ last: Int) -> Int {
        min(last, i + reach[i >= steps ? i - steps : i])
    }

    /// The fewest segments from stored index `first` to `last`; leaves in `ahead[c]` the
    /// farthest vertex c segments reach. Every vertex up to `reachEnd(i)` can end a segment
    /// from i, so jumping as far as possible is optimal.
    @discardableResult
    private mutating func fewestSegments(from first: Int, to last: Int) -> Int {
        ahead.removeAll(keepingCapacity: true)
        var i = first
        ahead.append(i)
        while i < last {
            i = reachEnd(i, last)
            ahead.append(i)
        }
        return ahead.count - 1
    }

    /// Least summed penalty of the polygons with the fewest segments from `first` to `last`
    /// (after `fewestSegments` for the same range); leaves the best one's vertices (`first`
    /// included, `last` not) in `candidate`. On such a polygon the c-th vertex is one that
    /// c segments reach and from which the remaining ones reach `last`: an interval per c.
    @discardableResult
    private mutating func leastPenalty(from first: Int, to last: Int) -> Double {
        let count = ahead.count - 1
        behind.removeAll(keepingCapacity: true)
        var b = last
        behind.append(b)
        while b > first {
            b = max(first, segmentStart[b])
            behind.append(b)
        }
        reset(&dpPenalty, last - first + 1, .infinity)
        reset(&dpPrevious, last - first + 1, 0)
        dpPenalty[0] = 0
        var previousLow = first, previousHigh = first
        for c in 1...count {
            let low = max(ahead[c - 1] + 1, behind[count - c])
            let high = c == count ? last : min(ahead[c], behind[count - c - 1] - 1)
            for j in low...high {
                // segmentStart[j] is itself on level c − 1, so the range is never empty.
                var best = Double.infinity, from = previousLow
                for i in max(previousLow, segmentStart[j])...min(previousHigh, j - 1) {
                    let p = dpPenalty[i - first] + penalty(i, j)
                    if p < best {
                        best = p
                        from = i
                    }
                }
                dpPenalty[j - first] = best
                dpPrevious[j - first] = from
            }
            previousLow = low
            previousHigh = high
        }
        candidate.removeAll(keepingCapacity: true)
        var j = last
        while j > first {
            j = dpPrevious[j - first]
            candidate.append(j)
        }
        candidate.reverse()
        return dpPenalty[last - first]
    }

    /// §2.2.3: the segment's length times the standard deviation of the path points'
    /// distances from it, from the prefix sums. Products are exact integers until the end.
    private func penalty(_ i: Int, _ j: Int) -> Double {
        let s = moments[j + 1] - moments[i]
        let c = Int64(j - i + 1)
        let xi = Int64(px[i]), yi = Int64(py[i]), xj = Int64(px[j]), yj = Int64(py[j])
        let u = xi + xj, w = yi + yj
        // 4c times the paper's a, b and c, about the segment's midpoint (u, w) / 2.
        let a4 = 4 * s.xx - 4 * u * s.x + c * u * u
        let b4 = 4 * s.xy - 2 * u * s.y - 2 * w * s.x + c * u * w
        let c4 = 4 * s.yy - 4 * w * s.y + c * w * w
        let dx = Double(xj - xi), dy = Double(yj - yi)
        let v = (Double(c4) * dx * dx - 2 * Double(b4) * dx * dy + Double(a4) * dy * dy) / Double(4 * c)
        return v > 0 ? v.squareRoot() : 0
    }

    /// Whether the triangle on stored indices a, b, c encloses less than ¾ of the loop.
    private func collapsed(_ a: Int, _ b: Int, _ c: Int) -> Bool {
        var loop = 0
        for k in 0..<steps { loop += px[k] * py[k + 1] - py[k] * px[k + 1] }
        let triangle = (px[b] - px[a]) * (py[c] - py[a]) - (py[b] - py[a]) * (px[c] - px[a])
        return 4 * abs(triangle) < 3 * abs(loop)
    }

    /// Makes the loop's lattice corners the polygon (with its end, for a loop through a
    /// junction).
    private mutating func useLatticeCorners(anchored: Bool) {
        polygon.removeAll(keepingCapacity: true)
        if anchored { polygon.append(0) }
        for k in (anchored ? 1 : 0)..<steps where direction[k == 0 ? steps - 1 : k - 1] != direction[k] {
            polygon.append(k)
        }
        if anchored { polygon.append(steps) }
    }

    // MARK: - Vertex adjustment (§2.3.1)

    /// Least-squares line of each polygon segment's path points, as unit normal and offset.
    private mutating func fitLines(_ m: Int) {
        lineNormal.removeAll(keepingCapacity: true)
        lineOffset.removeAll(keepingCapacity: true)
        for k in 0..<m {
            let i = polygon[k], j = polygon[k + 1]
            let s = moments[j + 1] - moments[i]
            let c = Int64(j - i + 1)
            // c² times the covariance matrix; its principal eigenvector is the direction.
            let a = Double(c * s.xx - s.x * s.x), b = Double(c * s.xy - s.x * s.y), d = Double(c * s.yy - s.y * s.y)
            let half = (a - d) / 2
            let lambda = (a + d) / 2 + (half * half + b * b).squareRoot()
            var dir = SIMD2(lambda - d, b)
            let other = SIMD2(b, lambda - a)
            if (other * other).sum() > (dir * dir).sum() { dir = other }
            if (dir * dir).sum() == 0 { dir = latticePoint(j) - latticePoint(i) }
            let normal = SIMD2(-dir.y, dir.x) / (dir * dir).sum().squareRoot()
            let centroid = SIMD2(Double(s.x), Double(s.y)) / Double(c)
            lineNormal.append(normal)
            lineOffset.append((normal * centroid).sum())
        }
    }

    /// The point within max-distance 1/2 of polygon vertex k that minimizes the summed
    /// squared distances to the lines of segments `before` and `after`.
    private func adjustedVertex(_ k: Int, before: Int, after: Int) -> SIMD2<Double> {
        let v = latticePoint(polygon[k])
        let n1 = lineNormal[before], n2 = lineNormal[after]
        let e1 = lineOffset[before] - (n1 * v).sum(), e2 = lineOffset[after] - (n2 * v).sum()
        // The squared distances about v: qᵀMq − 2r·q + const.
        let m00 = n1.x * n1.x + n2.x * n2.x, m01 = n1.x * n1.y + n2.x * n2.y, m11 = n1.y * n1.y + n2.y * n2.y
        let r = n1 * e1 + n2 * e2
        let det = m00 * m11 - m01 * m01
        let q: SIMD2<Double>
        if det > 1e-9 {
            q = SIMD2((m11 * r.x - m01 * r.y) / det, (m00 * r.y - m01 * r.x) / det)
        } else {
            // Parallel lines: the nearest point of the line midway between them.
            let sign: Double = (n1 * n2).sum() < 0 ? -1 : 1
            q = n1 * ((e1 + sign * e2) / 2)
        }
        if abs(q.x) <= 0.5 && abs(q.y) <= 0.5 { return v + q }
        // Otherwise the minimum lies on the square's boundary: the best point of each side.
        var best = SIMD2<Double>.zero, bestCost = Double.infinity
        for side in 0..<4 {
            let fixed = side & 1 == 0 ? -0.5 : 0.5
            let c: SIMD2<Double>
            if side < 2 {
                c = SIMD2(fixed, m11 > 0 ? min(max((r.y - m01 * fixed) / m11, -0.5), 0.5) : 0)
            } else {
                c = SIMD2(m00 > 0 ? min(max((r.x - m01 * fixed) / m00, -0.5), 0.5) : 0, fixed)
            }
            let cost = m00 * c.x * c.x + 2 * m01 * c.x * c.y + m11 * c.y * c.y - 2 * (r * c).sum()
            if cost < bestCost {
                bestCost = cost
                best = c
            }
        }
        return v + best
    }

    // MARK: - Corners and smoothing (§2.3.2–2.3.3)

    private mutating func prepareVertices(_ count: Int) {
        reset(&corner, count, false)
        reset(&alpha, count, 1)
        reset(&turn, count, 0)
        reset(&convexity, count, 0)
        reset(&support, count, 0)
        reset(&joint, count, .zero)
    }

    /// α of a vertex: the line parallel to the chord between its edge midpoints that
    /// touches the unit square around it cuts the edges at γ of the way from the midpoints,
    /// and α = 4γ/3 makes the curve tangent to that line.
    private mutating func analyze(_ k: Int, previous: SIMD2<Double>, next: SIMD2<Double>) {
        let a = vertex[k]
        let u = a - previous, w = next - a
        let turning = Self.cross(u, w)
        turn[k] = atan2(abs(turning), (u * w).sum())
        convexity[k] = turning > 0 ? 1 : turning < 0 ? -1 : 0
        let b0 = (previous + a) * 0.5
        let chord = (next - previous) * 0.5
        let chordLength = (chord * chord).sum().squareRoot()
        guard chordLength > 0 else {
            corner[k] = true
            return
        }
        let height = abs(Self.cross(chord, a - b0)) / chordLength
        support[k] = (abs(chord.x) + abs(chord.y)) / (2 * chordLength)
        let raw = height > 0 ? 4.0 / 3.0 * (1 - support[k] / height) : 0
        corner[k] = raw >= alphaMax && turn[k] >= minCornerTurn
        alpha[k] = min(max(raw, Self.lowestAlpha), 1)
    }

    /// Rounds corner k off with a cubic close to the circular arc of `cornerRadius` that is
    /// tangent to both edges; nil for a sharp corner.
    private func fillet(_ k: Int, from enter: SIMD2<Double>, to exit: SIMD2<Double>) -> Cubic? {
        guard cornerRadius > 0 else { return nil }
        let a = vertex[k], theta = turn[k]
        let toEnter = enter - a, toExit = exit - a
        let lengthIn = (toEnter * toEnter).sum().squareRoot(), lengthOut = (toExit * toExit).sum().squareRoot()
        guard lengthIn > 0, lengthOut > 0, theta > 0 else { return nil }
        let halfTangent = tan(theta / 2)
        let tangentLength = min(cornerRadius * halfTangent, lengthIn, lengthOut)
        guard tangentLength > 1e-9 else { return nil }
        let p = a + toEnter * (tangentLength / lengthIn), q = a + toExit * (tangentLength / lengthOut)
        // A cubic arc of angle θ has control arms 4/3·tan(θ/4) of its radius.
        let arm = 4.0 / 3.0 * tan(theta / 4) / halfTangent
        return Cubic(z0: p, z1: p + (a - p) * arm, z2: q + (a - q) * arm, z3: q)
    }

    /// Whether the curves of vertices k and l may be joined into one (§2.4).
    private func joinable(_ k: Int, _ l: Int) -> Bool {
        !corner[k] && !corner[l] && convexity[k] != 0 && convexity[k] == convexity[l]
    }

    // MARK: - Emission and curve optimization (§2.4)

    /// Emits `order` from `knots[0]` (already emitted) to its last knot.
    private mutating func emitPieces(into out: inout DenseCurve) {
        var q = 0
        while q < order.count {
            let k = order[q]
            if corner[k] {
                if let fillet = fillet(k, from: knots[q], to: knots[q + 1]) {
                    put(fillet.z0, pinned: true, into: &out)
                    flatten(fillet, pinned: true, into: &out)
                } else {
                    put(vertex[k], pinned: true, into: &out)
                }
                put(knots[q + 1], pinned: false, into: &out)
                q += 1
            } else {
                var r = q + 1
                while r < order.count && joinable(order[r - 1], order[r]) { r += 1 }
                emitSmoothRun(q, r, into: &out)
                q = r
            }
        }
    }

    /// Emits the curves of `order[from..<to]`, joined into as few curves as the checks of
    /// §2.4 allow, then by least penalty.
    private mutating func emitSmoothRun(_ from: Int, _ to: Int, into out: inout DenseCurve) {
        let count = to - from
        reset(&joinCount, count + 1, Int.max)
        reset(&joinPenalty, count + 1, .infinity)
        reset(&joinPrevious, count + 1, 0)
        reset(&joinCurve, count + 1, Cubic(z0: .zero, z1: .zero, z2: .zero, z3: .zero))
        joinCount[0] = 0
        joinPenalty[0] = 0
        for i in 0..<count {
            let k = order[from + i]
            let z0 = knots[from + i], z3 = knots[from + i + 1], a = vertex[k]
            let single = Cubic(z0: z0, z1: z0 + (a - z0) * alpha[k], z2: z3 + (a - z3) * alpha[k], z3: z3)
            relax(i + 1, from: i, penalty: 0, single)
            var turned = turn[k]
            var j = i + 2
            while j <= count {
                turned += turn[order[from + j - 1]]
                guard turned < Self.maxJoinTurn, let joined = join(from + i, from + j) else { break }
                relax(j, from: i, penalty: joined.penalty, joined.curve)
                j += 1
            }
        }
        chosen.removeAll(keepingCapacity: true)
        var j = count
        while j > 0 {
            chosen.append(j)
            j = joinPrevious[j]
        }
        for end in chosen.reversed() { flatten(joinCurve[end], pinned: false, into: &out) }
    }

    private mutating func relax(_ j: Int, from i: Int, penalty: Double, _ curve: Cubic) {
        let count = joinCount[i] + 1, total = joinPenalty[i] + penalty
        guard count < joinCount[j] || (count == joinCount[j] && total < joinPenalty[j]) else { return }
        joinCount[j] = count
        joinPenalty[j] = total
        joinPrevious[j] = i
        joinCurve[j] = curve
    }

    /// One curve for the vertices `order[qa..<qb]`, from `knots[qa]` to `knots[qb]`: tangent
    /// to the first and last edges, enclosing the same area against its chord as the curves
    /// it replaces. Accepted when, within the tolerance, it touches every edge in between
    /// (at a point projecting into the edge) and reaches every vertex's tangent line L.
    private func join(_ qa: Int, _ qb: Int) -> (curve: Cubic, penalty: Double)? {
        let z0 = knots[qa], z3 = knots[qb]
        let t0 = vertex[order[qa]] - z0, t3 = z3 - vertex[order[qb - 1]]
        let chord = z3 - z0
        let den = Self.cross(t0, t3)
        guard den != 0 else { return nil }
        let lambda = Self.cross(chord, t3) / den, mu = Self.cross(t0, chord) / den
        guard lambda > 0, mu > 0 else { return nil }
        let o = z0 + t0 * lambda
        let triangle = 0.5 * Self.cross(o - z0, chord)
        // A curve with z1 = z0 + α(o − z0), z2 = z3 + α(o − z3) encloses 3/10·(4α − α²) of
        // the triangle (z0, o, z3) against its chord (§2.3.2).
        var area = 0.0
        for q in qa..<qb {
            let k = order[q], b0 = knots[q], b1 = knots[q + 1], a = alpha[k]
            area += 0.5 * Self.cross(b0 - z0, b1 - z0)
            area += 0.15 * (4 * a - a * a) * Self.cross(vertex[k] - b0, b1 - b0)
        }
        let ratio = 10.0 / 3.0 * area / triangle
        guard ratio > 0, ratio <= 3 else { return nil }
        let shape = 2 - (4 - ratio).squareRoot()
        let curve = Cubic(z0: z0, z1: z0 + (o - z0) * shape, z2: z3 + (o - z3) * shape, z3: z3)
        let tolerance = Self.joinTolerance
        var penalty = 0.0
        for q in qa..<qb {
            let k = order[q], a = vertex[k], b0 = knots[q]
            let e = knots[q + 1] - b0
            guard let t = curve.parameter(along: e) else { return nil }
            var normal = SIMD2(-e.y, e.x) / (e * e).sum().squareRoot()
            if (normal * (a - b0)).sum() < 0 { normal = -normal }
            let reached = (normal * (curve.point(t) - a)).sum() + support[k]
            guard reached >= -tolerance else { return nil }
            penalty += reached * reached
            if q + 1 < qb {
                let u = vertex[order[q + 1]] - a
                let length2 = (u * u).sum()
                guard length2 > 0, let s = curve.parameter(along: u) else { return nil }
                let z = curve.point(s) - a
                let along = (z * u).sum() / length2
                let off = abs(Self.cross(u, z)) / length2.squareRoot()
                guard along >= 0, along <= 1, off <= tolerance else { return nil }
                penalty += off * off
            }
        }
        return (curve, penalty)
    }

    // MARK: - Output

    /// Appends the cubic's points after z0, within `flattenTolerance` of it: a uniform
    /// step h keeps the chords within h²/8 · max|B''| ≤ ¾ h² · max second difference.
    private func flatten(_ curve: Cubic, pinned: Bool, into out: inout DenseCurve) {
        let d1 = curve.z0 - 2 * curve.z1 + curve.z2, d2 = curve.z1 - 2 * curve.z2 + curve.z3
        let bend = max((d1 * d1).sum(), (d2 * d2).sum()).squareRoot()
        let steps = (0.75 * bend / flattenTolerance).squareRoot().rounded(.up)
        let pieces = steps.isFinite ? Int(min(max(steps, 1), 1024)) : 1
        for i in stride(from: 1, to: pieces, by: 1) {
            put(curve.point(Double(i) / Double(pieces)), pinned: pinned, into: &out)
        }
        put(curve.z3, pinned: pinned, into: &out)
    }

    @inline(__always)
    private func put(_ p: SIMD2<Double>, pinned: Bool, into out: inout DenseCurve) {
        out.append(origin + p, pinned: pinned)
    }

    private func finish(_ out: inout DenseCurve, minimumCount: Int) -> Bool {
        guard out.points.count >= minimumCount, out.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            out.removeAll()
            return false
        }
        return true
    }

    @inline(__always)
    fileprivate static func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x * b.y - a.y * b.x }
}

/// A cubic Bézier segment.
private struct Cubic {
    var z0, z1, z2, z3: SIMD2<Double>

    func point(_ t: Double) -> SIMD2<Double> {
        let s = 1 - t
        return z0 * (s * s * s) + z1 * (3 * s * s * t) + z2 * (3 * s * t * t) + z3 * (t * t * t)
    }

    /// The parameter in [0, 1] where the tangent points along `u`, if any.
    func parameter(along u: SIMD2<Double>) -> Double? {
        let d0 = z1 - z0, d1 = z2 - z1, d2 = z3 - z2
        let p = CurveFitter.cross(d0, u), q = CurveFitter.cross(d1, u), r = CurveFitter.cross(d2, u)
        // cross(B'(t), u) / 3 = a t² + b t + c
        let a = p - 2 * q + r, b = 2 * (q - p), c = p
        let scale = max(abs(a), abs(b), abs(c))
        guard scale > 0 else { return nil }
        var first = Double.nan, second = Double.nan
        if abs(a) <= 1e-12 * scale {
            guard b != 0 else { return nil }
            first = -c / b
        } else {
            let disc = b * b - 4 * a * c
            guard disc >= 0 else { return nil }
            let h = -0.5 * (b + (b < 0 ? -disc.squareRoot() : disc.squareRoot()))
            first = h / a
            if h != 0 { second = c / h }
        }
        for root in 0..<2 {
            let t = root == 0 ? first : second
            guard t >= -1e-9 && t <= 1 + 1e-9 else { continue }
            let s = min(max(t, 0), 1)
            let tangent = d0 * ((1 - s) * (1 - s)) + d1 * (2 * s * (1 - s)) + d2 * (s * s)
            if (tangent * u).sum() > 0 { return s }
        }
        return nil
    }
}

@inline(__always)
private func reset<T>(_ array: inout [T], _ count: Int, _ value: T) {
    array.removeAll(keepingCapacity: true)
    array.append(contentsOf: repeatElement(value, count: count))
}
