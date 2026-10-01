import Foundation

/// Fits smooth curves to stair-stepped lattice chains. A Swift translation of potrace 1.16
/// (Copyright (C) 2001-2019 Peter Selinger, GPL-2.0-or-later; "Potrace: a polygon-based
/// tracing algorithm", 2003), so it is a derivative work under the same license (see
/// `ACKNOWLEDGEMENTS.md`), extended to open chains. potrace's stages:
///
/// 1. find the longest *straight* sub-paths (a line exists that passes within half a
///    pixel of every lattice point),
/// 2. choose the polygon with the fewest segments (then least squared deviation) whose
///    segments all follow straight sub-paths,
/// 3. move each polygon vertex to the point near its lattice corner that best fits the
///    two adjacent segments' least-squares lines (corrected for the bias of line fits
///    along curves),
/// 4. turn each vertex into either a sharp corner (when it sticks out far relative to its
///    neighbours, `alphaMax`) or a cubic Bézier through the adjacent edge midpoints,
/// 5. join runs of Béziers into fewer, longer ones where that stays within tolerance,
///    which evens out curvature,
///
/// and flatten the result into a polyline.
///
/// Digitized straight lines of any slope come out perfectly straight, circles come out
/// round and genuine corners stay crisp. Unlike potrace, open chains are supported: their
/// end points (junctions shared with other edges) stay exactly where they are, so every
/// edge can be fitted independently and still meet its neighbours.
///
/// Holds scratch buffers; create one per worker and reuse it across chains.
struct CurveFitter {
    /// Vertices whose `alpha` reaches this become corners (potrace default: 1)…
    var alphaMax: Double
    /// …provided the polygon turns there by at least the angle with this cosine.
    var cornerCos: Double
    /// Corners are rounded off with fillets of this size (0: sharp), canvas units.
    var cornerRadius: Double
    /// Maximum distance between a Bézier and its flattened polyline, canvas units.
    var flattenTolerance: Double

    private var px: [Int] = [], py: [Int] = []
    private var sx: [Double] = [], sy: [Double] = [], sxx: [Double] = [], sxy: [Double] = [], syy: [Double] = []
    private var nc: [Int] = [], pivk: [Int] = [], lon: [Int] = []
    private var clip0: [Int] = [], clip1: [Int] = [], seg0: [Int] = [], seg1: [Int] = []
    private var prev: [Int] = [], pen: [Double] = []
    private var po: [Int] = []
    private var vx: [Double] = [], vy: [Double] = []
    private var quads: [Quad] = []
    private var lineCentre: [SIMD2<Double>] = [], lineDir: [SIMD2<Double>] = [], lineLength: [Double] = []
    private var lineShift: [SIMD2<Double>] = []
    // Curve segments: segment j runs from the end of segment j − 1 to `segEnd[j]`, either
    // as a corner (straight to `segVertex[j]`, then to the end) or as a cubic Bézier.
    private var segCorner: [Bool] = [], segVertex: [SIMD2<Double>] = [], segAlpha: [Double] = []
    private var segC0: [SIMD2<Double>] = [], segC1: [SIMD2<Double>] = [], segEnd: [SIMD2<Double>] = []
    private var convexity: [Int] = [], areaPrefix: [Double] = []
    private var optPrev: [Int] = [], optLen: [Int] = [], optPen: [Double] = []
    private var optC0: [SIMD2<Double>] = [], optC1: [SIMD2<Double>] = []
    private var outCorner: [Bool] = [], outC0: [SIMD2<Double>] = [], outC1: [SIMD2<Double>] = []
    private var outVertex: [SIMD2<Double>] = [], outEnd: [SIMD2<Double>] = []

    init(alphaMax: Double, minCornerAngle: Double, cornerRadius: Double, flattenTolerance: Double) {
        self.alphaMax = alphaMax
        self.cornerCos = cos(minCornerAngle * Double.pi / 180)
        self.cornerRadius = cornerRadius
        self.flattenTolerance = flattenTolerance
    }

    /// Symmetric 3×3 quadratic form: squared distance to a line, (x, y, 1) Q (x, y, 1)ᵀ with
    /// Q = [[xx, xy, x1], [xy, yy, y1], [x1, y1, cc]].
    private struct Quad {
        var xx = 0.0, xy = 0.0, x1 = 0.0, yy = 0.0, y1 = 0.0, cc = 0.0

        /// Adds v vᵀ / d for the line v·(x, y, 1) = 0.
        mutating func add(_ v0: Double, _ v1: Double, _ v2: Double, _ d: Double) {
            xx += v0 * v0 / d; xy += v0 * v1 / d; x1 += v0 * v2 / d
            yy += v1 * v1 / d; y1 += v1 * v2 / d; cc += v2 * v2 / d
        }

        static func + (a: Quad, b: Quad) -> Quad {
            Quad(xx: a.xx + b.xx, xy: a.xy + b.xy, x1: a.x1 + b.x1, yy: a.yy + b.yy, y1: a.y1 + b.y1, cc: a.cc + b.cc)
        }

        func eval(_ x: Double, _ y: Double) -> Double {
            xx * x * x + 2 * xy * x * y + 2 * x1 * x + yy * y * y + 2 * y1 * y + cc
        }
    }

    // MARK: - Entry points

    /// Fits an open chain of lattice points (`points.count >= 2`, unit steps). The output
    /// starts and ends exactly at the chain's end points, which are pinned. Returns false
    /// when the fit degenerates (the caller then uses a simpler fallback).
    mutating func fitOpen(_ points: [SIMD2<Int32>], into out: inout DenseCurve) -> Bool {
        out.removeAll()
        let n = points.count - 1
        load(points, count: n + 1)
        let first = SIMD2(Double(points[0].x), Double(points[0].y))
        let last = SIMD2(Double(points[n].x), Double(points[n].y))
        calcLonOpen(n)
        let m = bestPolygonOpen(n)
        if m == 1 {
            if first == last { return false }
            out.append(first, pinned: true); out.append(last, pinned: true)
            return true
        }
        if first == last && m < 3 { return false }
        adjustVerticesOpen(n, m)
        buildSegments(vertexCount: m + 1, open: true)
        optimizeCurve(open: true)
        out.append(first, pinned: true)
        out.append(segEnd[0], pinned: false)
        flattenOutput(from: segEnd[0], into: &out)
        return true
    }

    /// Fits a closed chain (`points` ends with a repeat of its first point, at least four
    /// unit steps). The output repeats its first point at the end; corners are pinned.
    mutating func fitClosed(_ points: [SIMD2<Int32>], into out: inout DenseCurve) -> Bool {
        out.removeAll()
        let n = points.count - 1
        load(points, count: n)
        var m = 0
        if n >= 16 {
            calcLonCyclic(n)
            m = bestPolygonCyclic(n)
        }
        if m >= 3 {
            adjustVerticesCyclic(n, m)
        } else {
            // Tiny loops: use every lattice turn as a vertex; the Béziers round them off.
            m = turnPolygon(n)
            if m < 3 { return false }
        }
        buildSegments(vertexCount: m, open: false)
        optimizeCurve(open: false)
        out.append(segEnd[0], pinned: false)
        flattenOutput(from: segEnd[0], into: &out)
        out.points[out.points.count - 1] = out.points[0]
        return out.points.count >= 4
    }

    // MARK: - Setup

    private mutating func load(_ points: [SIMD2<Int32>], count: Int) {
        px.removeAll(keepingCapacity: true); py.removeAll(keepingCapacity: true)
        for i in 0..<count { px.append(Int(points[i].x)); py.append(Int(points[i].y)) }
        // Prefix sums relative to the first point keep the moments numerically tame.
        let x0 = px[0], y0 = py[0]
        sx.removeAll(keepingCapacity: true); sy.removeAll(keepingCapacity: true)
        sxx.removeAll(keepingCapacity: true); sxy.removeAll(keepingCapacity: true); syy.removeAll(keepingCapacity: true)
        sx.append(0); sy.append(0); sxx.append(0); sxy.append(0); syy.append(0)
        for i in 0..<count {
            let x = Double(px[i] - x0), y = Double(py[i] - y0)
            sx.append(sx[i] + x); sy.append(sy[i] + y)
            sxx.append(sxx[i] + x * x); sxy.append(sxy[i] + x * y); syy.append(syy[i] + y * y)
        }
        resize(&nc, count + 1); resize(&pivk, count + 1); resize(&lon, count + 1)
        resize(&clip0, count + 1); resize(&clip1, count + 2); resize(&seg0, count + 2); resize(&seg1, count + 2)
        resize(&prev, count + 2)
        if pen.count < count + 2 { pen = [Double](repeating: 0, count: count + 2) }
    }

    private func resize(_ a: inout [Int], _ n: Int) {
        if a.count < n { a = [Int](repeating: 0, count: n) }
    }

    // MARK: - Stage 1: straight sub-paths

    @inline(__always) private static func xprod(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> Int { ax * by - ay * bx }
    @inline(__always) private static func sign(_ v: Int) -> Int { v > 0 ? 1 : (v < 0 ? -1 : 0) }
    @inline(__always) private static func floordiv(_ a: Int, _ n: Int) -> Int { a >= 0 ? a / n : -1 - (-1 - a) / n }
    @inline(__always) private static func mod(_ a: Int, _ n: Int) -> Int {
        a >= n ? a % n : (a >= 0 ? a : n - 1 - (-1 - a) % n)
    }
    /// a <= b < c cyclically.
    @inline(__always) private static func cyclic(_ a: Int, _ b: Int, _ c: Int) -> Bool {
        a <= c ? (a <= b && b < c) : (a <= b || b < c)
    }

    /// Walks from `i` along direction-change corners, maintaining potrace's pair of
    /// constraint vectors, and returns the furthest index reachable by a straight line.
    /// `nextIndex(k)` is the next corner after `k` or nil at the end of an open path.
    @inline(__always)
    private func pivot(from i: Int, count n: Int, cyclicPath: Bool) -> Int {
        var ct = SIMD4<Int>(repeating: 0)
        let i1 = cyclicPath ? CurveFitter.mod(i + 1, n) : i + 1
        ct[(3 + 3 * (px[i1] - px[i]) + (py[i1] - py[i])) / 2] += 1
        var c0x = 0, c0y = 0, c1x = 0, c1y = 0
        var k = nc[i], k1 = i
        while true {
            ct[(3 + 3 * CurveFitter.sign(px[k] - px[k1]) + CurveFitter.sign(py[k] - py[k1])) / 2] += 1
            if ct[0] > 0 && ct[1] > 0 && ct[2] > 0 && ct[3] > 0 { return k1 }
            let curx = px[k] - px[i], cury = py[k] - py[i]
            if CurveFitter.xprod(c0x, c0y, curx, cury) < 0 || CurveFitter.xprod(c1x, c1y, curx, cury) > 0 { break }
            if abs(curx) > 1 || abs(cury) > 1 {
                var ox = curx + ((cury >= 0 && (cury > 0 || curx < 0)) ? 1 : -1)
                var oy = cury + ((curx <= 0 && (curx < 0 || cury < 0)) ? 1 : -1)
                if CurveFitter.xprod(c0x, c0y, ox, oy) >= 0 { c0x = ox; c0y = oy }
                ox = curx + ((cury <= 0 && (cury < 0 || curx < 0)) ? 1 : -1)
                oy = cury + ((curx >= 0 && (curx > 0 || cury < 0)) ? 1 : -1)
                if CurveFitter.xprod(c1x, c1y, ox, oy) <= 0 { c1x = ox; c1y = oy }
            }
            k1 = k
            if cyclicPath {
                k = nc[k1]
                if !CurveFitter.cyclic(k, i, k1) { break }
            } else {
                if k1 >= n { return n }
                k = nc[k1]
            }
        }
        // k1 satisfied the constraints and k violates them: find the last lattice point on
        // the axis-aligned run k1 → k that still satisfies them.
        let dkx = CurveFitter.sign(px[k] - px[k1]), dky = CurveFitter.sign(py[k] - py[k1])
        let curx = px[k1] - px[i], cury = py[k1] - py[i]
        let a = CurveFitter.xprod(c0x, c0y, curx, cury), b = CurveFitter.xprod(c0x, c0y, dkx, dky)
        let c = CurveFitter.xprod(c1x, c1y, curx, cury), d = CurveFitter.xprod(c1x, c1y, dkx, dky)
        let run = cyclicPath ? CurveFitter.mod(k - k1, n) : k - k1
        var j = run
        if b < 0 { j = min(j, CurveFitter.floordiv(a, -b)) }
        if d > 0 { j = min(j, CurveFitter.floordiv(-c, d)) }
        j = max(0, j)
        return cyclicPath ? CurveFitter.mod(k1 + j, n) : k1 + j
    }

    private mutating func calcLonOpen(_ n: Int) {
        var k = n
        for i in stride(from: n - 1, through: 0, by: -1) {
            if px[i] != px[k] && py[i] != py[k] { k = i + 1 }
            nc[i] = k
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            pivk[i] = min(n, max(i + 1, pivot(from: i, count: n, cyclicPath: false)))
        }
        lon[n - 1] = pivk[n - 1]
        if n >= 2 {
            for i in stride(from: n - 2, through: 0, by: -1) { lon[i] = min(pivk[i], lon[i + 1]) }
        }
    }

    private mutating func calcLonCyclic(_ n: Int) {
        var k = 0
        for i in stride(from: n - 1, through: 0, by: -1) {
            if px[i] != px[k] && py[i] != py[k] { k = i + 1 }
            nc[i] = k
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            pivk[i] = pivot(from: i, count: n, cyclicPath: true)
        }
        var j = pivk[n - 1]
        lon[n - 1] = j
        for i in stride(from: n - 2, through: 0, by: -1) {
            if CurveFitter.cyclic(i + 1, pivk[i], j) { j = pivk[i] }
            lon[i] = j
        }
        var i = n - 1
        while i >= 0 && CurveFitter.cyclic(CurveFitter.mod(i + 1, n), j, lon[i]) {
            lon[i] = j
            i -= 1
        }
    }

    // MARK: - Stage 2: optimal polygon

    /// Penalty of the polygon segment i → j: root of the summed squared distances of the
    /// lattice points in between from the segment, scaled by its length (potrace `penalty3`).
    @inline(__always)
    private func penalty(_ i: Int, _ jIn: Int, count n: Int) -> Double {
        var j = jIn
        var x: Double, y: Double, x2: Double, xy: Double, y2: Double, k: Double
        if j >= n {
            j -= n
            x = sx[j + 1] - sx[i] + sx[n]; y = sy[j + 1] - sy[i] + sy[n]
            x2 = sxx[j + 1] - sxx[i] + sxx[n]; xy = sxy[j + 1] - sxy[i] + sxy[n]; y2 = syy[j + 1] - syy[i] + syy[n]
            k = Double(j + 1 - i + n)
        } else {
            x = sx[j + 1] - sx[i]; y = sy[j + 1] - sy[i]
            x2 = sxx[j + 1] - sxx[i]; xy = sxy[j + 1] - sxy[i]; y2 = syy[j + 1] - syy[i]
            k = Double(j + 1 - i)
        }
        let pxm = Double(px[i] + px[j]) / 2 - Double(px[0])
        let pym = Double(py[i] + py[j]) / 2 - Double(py[0])
        let ey = Double(px[j] - px[i])
        let ex = -Double(py[j] - py[i])
        let a = (x2 - 2 * x * pxm) / k + pxm * pxm
        let b = (xy - x * pym - y * pxm) / k + pxm * pym
        let c = (y2 - 2 * y * pym) / k + pym * pym
        return max(0, ex * ex * a + 2 * ex * ey * b + ey * ey * c).squareRoot()
    }

    /// Shortest-then-cheapest polygon from `clip0` (the furthest allowed next vertex of
    /// each vertex). Returns the segment count; vertices land in `po[0...m]`.
    private mutating func shortestPolygon(_ n: Int, _ pathLength: Int) -> Int {
        var j = 1
        for i in 0..<n {
            while j <= clip0[i] { clip1[j] = i; j += 1 }
        }
        var i = 0
        j = 0
        while i < n { seg0[j] = i; i = clip0[i]; j += 1 }
        seg0[j] = n
        let m = j
        i = n
        for jj in stride(from: m, to: 0, by: -1) { seg1[jj] = i; i = clip1[i] }
        seg1[0] = 0
        pen[0] = 0
        for jj in 1...m {
            for ii in stride(from: seg1[jj], through: seg0[jj], by: 1) {
                var best = -1.0
                var k = seg0[jj - 1]
                while k >= clip1[ii] {
                    let p = penalty(k, ii, count: pathLength) + pen[k]
                    if best < 0 || p < best { prev[ii] = k; best = p }
                    k -= 1
                }
                pen[ii] = best
            }
        }
        po.removeAll(keepingCapacity: true)
        po.append(contentsOf: repeatElement(0, count: m + 1))
        po[m] = n
        i = n
        var jj = m - 1
        while i > 0 && jj >= 0 {
            i = prev[i]
            po[jj] = i
            jj -= 1
        }
        return m
    }

    private mutating func bestPolygonOpen(_ n: Int) -> Int {
        // Segment i → j is allowed when the lattice path i−1 … j+1 is straight, clipped at
        // the pinned ends.
        for i in 0..<n {
            let a = max(i - 1, 0)
            var c = lon[a] >= n ? n : lon[a] - 1
            if c <= i { c = i + 1 }
            clip0[i] = min(c, n)
        }
        return shortestPolygon(n, n + 1)
    }

    private mutating func bestPolygonCyclic(_ n: Int) -> Int {
        for i in 0..<n {
            var c = CurveFitter.mod(lon[CurveFitter.mod(i - 1, n)] - 1, n)
            if c == i { c = CurveFitter.mod(i + 1, n) }
            clip0[i] = c < i ? n : c
        }
        return shortestPolygon(n, n)
    }

    /// Polygon through every direction change of a closed lattice path.
    private mutating func turnPolygon(_ n: Int) -> Int {
        vx.removeAll(keepingCapacity: true); vy.removeAll(keepingCapacity: true)
        for i in 0..<n {
            let a = CurveFitter.mod(i - 1, n), b = CurveFitter.mod(i + 1, n)
            let dx0 = px[i] - px[a], dy0 = py[i] - py[a], dx1 = px[b] - px[i], dy1 = py[b] - py[i]
            if dx0 != dx1 || dy0 != dy1 {
                vx.append(Double(px[i])); vy.append(Double(py[i]))
            }
        }
        return vx.count
    }

    // MARK: - Stage 3: vertex adjustment

    /// Centroid and principal direction of lattice points i…j (j may wrap for cyclic paths),
    /// relative to the first path point.
    @inline(__always)
    private func pointSlope(_ iIn: Int, _ jIn: Int, count n: Int) -> (cx: Double, cy: Double, dx: Double, dy: Double) {
        var i = iIn, j = jIn, r = 0
        while j >= n { j -= n; r += 1 }
        while i >= n { i -= n; r -= 1 }
        while j < 0 { j += n; r -= 1 }
        while i < 0 { i += n; r += 1 }
        let rd = Double(r)
        let x = sx[j + 1] - sx[i] + rd * sx[n], y = sy[j + 1] - sy[i] + rd * sy[n]
        let x2 = sxx[j + 1] - sxx[i] + rd * sxx[n], xy = sxy[j + 1] - sxy[i] + rd * sxy[n]
        let y2 = syy[j + 1] - syy[i] + rd * syy[n]
        let k = Double(j + 1 - i + r * n)
        var a = (x2 - x * x / k) / k
        let b = (xy - x * y / k) / k
        var c = (y2 - y * y / k) / k
        let lambda2 = (a + c + ((a - c) * (a - c) + 4 * b * b).squareRoot()) / 2
        a -= lambda2
        c -= lambda2
        var dx = 0.0, dy = 0.0
        if abs(a) >= abs(c) {
            let l = (a * a + b * b).squareRoot()
            if l != 0 { dx = -b / l; dy = a / l }
        } else {
            let l = (c * c + b * b).squareRoot()
            if l != 0 { dx = -c / l; dy = b / l }
        }
        return (x / k, y / k, dx, dy)
    }

    private func lineQuad(_ ctrX: Double, _ ctrY: Double, _ dirX: Double, _ dirY: Double) -> Quad {
        var q = Quad()
        let d = dirX * dirX + dirY * dirY
        guard d != 0 else { return q }
        q.add(dirY, -dirX, dirX * ctrY - dirY * ctrX, d)
        return q
    }

    /// The point within the square of half-size `r` centred on (sxc, syc) minimizing Q.
    private func minimize(_ qIn: Quad, _ sxc: Double, _ syc: Double, _ r: Double) -> (Double, Double) {
        var q = qIn
        var wx = 0.0, wy = 0.0
        while true {
            let det = q.xx * q.yy - q.xy * q.xy
            if det != 0 {
                wx = (-q.x1 * q.yy + q.y1 * q.xy) / det
                wy = (q.x1 * q.xy - q.y1 * q.xx) / det
                break
            }
            // Parallel lines: add an orthogonal axis through the square's centre.
            var v0: Double, v1: Double
            if q.xx > q.yy {
                v0 = -q.xy; v1 = q.xx
            } else if q.yy != 0 {
                v0 = -q.yy; v1 = q.xy
            } else {
                v0 = 1; v1 = 0
            }
            q.add(v0, v1, -v1 * syc - v0 * sxc, v0 * v0 + v1 * v1)
        }
        if abs(wx - sxc) <= r && abs(wy - syc) <= r { return (wx, wy) }
        // Minimum outside the square: search its boundary.
        var best = q.eval(sxc, syc)
        var bx = sxc, by = syc
        if q.xx != 0 {
            for z in 0..<2 {
                let y = syc + (z == 0 ? -r : r)
                let x = -(q.xy * y + q.x1) / q.xx
                let cand = q.eval(x, y)
                if abs(x - sxc) <= r && cand < best { best = cand; bx = x; by = y }
            }
        }
        if q.yy != 0 {
            for z in 0..<2 {
                let x = sxc + (z == 0 ? -r : r)
                let y = -(q.xy * x + q.y1) / q.yy
                let cand = q.eval(x, y)
                if abs(y - syc) <= r && cand < best { best = cand; bx = x; by = y }
            }
        }
        for l in 0..<2 {
            for k in 0..<2 {
                let x = sxc + (l == 0 ? -r : r), y = syc + (k == 0 ? -r : r)
                let cand = q.eval(x, y)
                if cand < best { best = cand; bx = x; by = y }
            }
        }
        return (bx, by)
    }

    /// Records the least-squares line of polygon segment `s` (lattice points a…b), with its
    /// direction oriented along the path.
    private mutating func addLine(_ a: Int, _ b: Int, count n: Int, from ia: Int, to ib: Int) {
        let ps = pointSlope(a, b, count: n)
        var d = SIMD2(ps.dx, ps.dy)
        let chord = SIMD2(Double(px[ib] - px[ia]), Double(py[ib] - py[ia]))
        if (d * chord).sum() < 0 { d = -d }
        lineCentre.append(SIMD2(ps.cx, ps.cy)); lineDir.append(d)
        lineLength.append((chord * chord).sum().squareRoot())
    }

    /// A least-squares line through lattice points along a curved stretch lies inside the
    /// curve's tangent by about κL²/24 (the mean sagitta over an arc of length L), and the
    /// curve is later drawn tangent to it — so long polygon edges, such as the flat runs at
    /// the extremes of a digitized circle, would come out flattened. Shift each line back
    /// out where its neighbours show a smooth, consistently turning curve.
    private mutating func correctCurvatureBias(cyclic: Bool) {
        let m = lineDir.count
        guard m >= 3 else { return }
        let maxTurnCos = cos(Double.pi / 4)
        lineShift.removeAll(keepingCapacity: true)
        for s in 0..<m {
            guard cyclic || (s > 0 && s < m - 1) else { lineShift.append(.zero); continue }
            let a = lineDir[(s + m - 1) % m], b = lineDir[s], c = lineDir[(s + 1) % m]
            let t1 = a.x * b.y - a.y * b.x, t2 = b.x * c.y - b.y * c.x
            guard t1 * t2 > 0, (a * b).sum() > maxTurnCos, (b * c).sum() > maxTurnCos else {
                lineShift.append(.zero)
                continue
            }
            let theta = atan2(a.x * c.y - a.y * c.x, (a * c).sum())
            let arc = 0.5 * lineLength[(s + m - 1) % m] + lineLength[s] + 0.5 * lineLength[(s + 1) % m]
            let delta = min(0.5, abs(theta) / arc * lineLength[s] * lineLength[s] / 24)
            let outward = theta > 0 ? SIMD2(b.y, -b.x) : SIMD2(-b.y, b.x)
            lineShift.append(delta * outward)
        }
        for s in 0..<m { lineCentre[s] += lineShift[s] }
    }

    /// How far (per axis) a polygon vertex may move from its lattice corner. potrace uses
    /// half a unit; along gently curving arcs the vertex that makes the curve tangent to the
    /// true outline often lies further out, and clamping it flattens the curve there.
    static let vertexReach = 1.0

    private mutating func adjustVerticesOpen(_ n: Int, _ m: Int) {
        let x0 = Double(px[0]), y0 = Double(py[0])
        lineCentre.removeAll(keepingCapacity: true); lineDir.removeAll(keepingCapacity: true)
        lineLength.removeAll(keepingCapacity: true)
        for s in 0..<m { addLine(po[s], po[s + 1], count: n + 1, from: po[s], to: po[s + 1]) }
        correctCurvatureBias(cyclic: false)
        quads.removeAll(keepingCapacity: true)
        for s in 0..<m { quads.append(lineQuad(lineCentre[s].x, lineCentre[s].y, lineDir[s].x, lineDir[s].y)) }
        vx.removeAll(keepingCapacity: true); vy.removeAll(keepingCapacity: true)
        vx.append(x0); vy.append(y0)
        for i in 1..<m {
            let q = quads[i - 1] + quads[i]
            let (wx, wy) = minimize(q, Double(px[po[i]]) - x0, Double(py[po[i]]) - y0, CurveFitter.vertexReach)
            vx.append(wx + x0); vy.append(wy + y0)
        }
        vx.append(Double(px[n])); vy.append(Double(py[n]))
    }

    private mutating func adjustVerticesCyclic(_ n: Int, _ m: Int) {
        let x0 = Double(px[0]), y0 = Double(py[0])
        lineCentre.removeAll(keepingCapacity: true); lineDir.removeAll(keepingCapacity: true)
        lineLength.removeAll(keepingCapacity: true)
        for i in 0..<m {
            var j = po[(i + 1) % m]
            j = CurveFitter.mod(j - po[i], n) + po[i]
            addLine(po[i], j, count: n, from: po[i], to: po[(i + 1) % m])
        }
        correctCurvatureBias(cyclic: true)
        quads.removeAll(keepingCapacity: true)
        for s in 0..<m { quads.append(lineQuad(lineCentre[s].x, lineCentre[s].y, lineDir[s].x, lineDir[s].y)) }
        vx.removeAll(keepingCapacity: true); vy.removeAll(keepingCapacity: true)
        for i in 0..<m {
            let j = (i + m - 1) % m
            let q = quads[j] + quads[i]
            let (wx, wy) = minimize(q, Double(px[po[i]]) - x0, Double(py[po[i]]) - y0, CurveFitter.vertexReach)
            vx.append(wx + x0); vy.append(wy + y0)
        }
    }

    // MARK: - Stage 4: corners and Béziers

    @inline(__always) private func vertex(_ i: Int) -> SIMD2<Double> { SIMD2(vx[i], vy[i]) }

    /// One curve segment per polygon vertex (potrace `smooth`): a corner when the vertex
    /// sticks out far from the chord of its neighbours, else a Bézier from the midpoint of
    /// the incoming polygon edge to the midpoint of the outgoing one. The end vertices of
    /// open chains are pinned corners.
    private mutating func buildSegments(vertexCount m: Int, open: Bool) {
        segCorner.removeAll(keepingCapacity: true); segVertex.removeAll(keepingCapacity: true)
        segAlpha.removeAll(keepingCapacity: true); segC0.removeAll(keepingCapacity: true)
        segC1.removeAll(keepingCapacity: true); segEnd.removeAll(keepingCapacity: true)
        func append(_ corner: Bool, _ v: SIMD2<Double>, _ alpha: Double, _ c0: SIMD2<Double>, _ c1: SIMD2<Double>, _ end: SIMD2<Double>) {
            segCorner.append(corner); segVertex.append(v); segAlpha.append(alpha)
            segC0.append(c0); segC1.append(c1); segEnd.append(end)
        }
        for j in 0..<m {
            let vj = vertex(j)
            if open && (j == 0 || j == m - 1) {
                append(true, vj, 4.0 / 3.0, vj, vj, j == 0 ? (vj + vertex(1)) * 0.5 : vj)
                continue
            }
            let vi = vertex((j + m - 1) % m), vk = vertex((j + 1) % m)
            let end = (vj + vk) * 0.5
            let dk = vk - vi
            let denom = abs(dk.x) + abs(dk.y)
            var alpha = 4.0 / 3.0
            if denom != 0 {
                let dd = abs((vj.x - vi.x) * dk.y - dk.x * (vj.y - vi.y)) / denom
                alpha = dd > 1 ? (1 - 1 / dd) / 0.75 : 0
            }
            // potrace's alpha alone flags a vertex once it sticks out ~4 px from the chord of
            // its neighbours, which also happens along smooth arcs of any radius (their
            // polygon edges grow with the radius); a corner must also turn sharply.
            let din = vj - vi, dout = vk - vj
            let turnCos = (din * dout).sum() / max(1e-12, ((din * din).sum() * (dout * dout).sum()).squareRoot())
            if alpha >= alphaMax && turnCos <= cornerCos {
                append(true, vj, alpha, vj, vj, end)
            } else {
                alpha = min(max(alpha, 0.55), 1)
                append(false, vj, alpha, vi + (0.5 + 0.5 * alpha) * (vj - vi), vk + (0.5 + 0.5 * alpha) * (vj - vk), end)
            }
        }
    }

    private static let optTolerance = 0.2
    private static let cos179 = cos(179.0 * Double.pi / 180)

    @inline(__always) private static func dpara(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>) -> Double {
        (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y)
    }
    @inline(__always) private static func cprod(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>) -> Double {
        (p1.x - p0.x) * (p3.y - p2.y) - (p3.x - p2.x) * (p1.y - p0.y)
    }
    @inline(__always) private static func iprod(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>) -> Double {
        (p1.x - p0.x) * (p2.x - p0.x) + (p1.y - p0.y) * (p2.y - p0.y)
    }
    @inline(__always) private static func iprod1(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>) -> Double {
        (p1.x - p0.x) * (p3.x - p2.x) + (p1.y - p0.y) * (p3.y - p2.y)
    }
    @inline(__always) private static func dist(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = a - b
        return (d * d).sum().squareRoot()
    }
    @inline(__always) private static func bezier(_ t: Double, _ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>) -> SIMD2<Double> {
        let s = 1 - t
        return (s * s * s) * p0 + (3 * s * s * t) * p1 + (3 * s * t * t) * p2 + (t * t * t) * p3
    }

    /// Parameter in [0, 1] where the convex Bézier is tangent to q0→q1, or −1.
    private static func tangent(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>, _ q0: SIMD2<Double>, _ q1: SIMD2<Double>) -> Double {
        let aa = cprod(p0, p1, q0, q1), bb = cprod(p1, p2, q0, q1), cc = cprod(p2, p3, q0, q1)
        let a = aa - 2 * bb + cc, b = -2 * aa + 2 * bb, c = aa
        let d = b * b - 4 * a * c
        if a == 0 || d < 0 { return -1 }
        let s = d.squareRoot()
        let r1 = (-b + s) / (2 * a), r2 = (-b - s) / (2 * a)
        if r1 >= 0 && r1 <= 1 { return r1 }
        if r2 >= 0 && r2 <= 1 { return r2 }
        return -1
    }

    /// Whether segments i+1 … j (indices modulo the segment count for closed curves) can be
    /// replaced by one Bézier from the end of segment i to the end of segment j — same
    /// convexity, no corner, less than 179° of total turn, within `optTolerance` of the
    /// polygon edges and keeping the enclosed area (potrace `opti_penalty`).
    private func optiPenalty(_ i: Int, _ j: Int, open: Bool) -> (pen: Double, c0: SIMD2<Double>, c1: SIMD2<Double>)? {
        let m = segEnd.count
        if i == j { return nil }
        @inline(__always) func md(_ a: Int) -> Int { open ? a : a % m }
        let v = segVertex
        let i1 = md(i + 1)
        let conv = convexity[i1]
        if conv == 0 { return nil }
        let d = CurveFitter.dist(v[i], v[i1])
        var k = i1
        while k != j {
            let k1 = md(k + 1)
            if convexity[k1] != conv { return nil }
            let k2 = md(k + 2)
            let turn = CurveFitter.cprod(v[i], v[i1], v[k1], v[k2])
            if (turn > 0 ? 1 : (turn < 0 ? -1 : 0)) != conv { return nil }
            if CurveFitter.iprod1(v[i], v[i1], v[k1], v[k2]) < d * CurveFitter.dist(v[k1], v[k2]) * CurveFitter.cos179 { return nil }
            k = k1
        }

        let p0 = segEnd[i], p1 = v[i1], p2 = v[j], p3 = segEnd[j]
        var area = areaPrefix[j] - areaPrefix[i] - CurveFitter.dpara(v[0], segEnd[i], segEnd[j]) / 2
        if i >= j { area += areaPrefix[m] }
        let a1 = CurveFitter.dpara(p0, p1, p2), a2 = CurveFitter.dpara(p0, p1, p3), a3 = CurveFitter.dpara(p0, p2, p3)
        let a4 = a1 + a3 - a2
        if a2 == a1 { return nil }
        let t = a3 / (a3 - a4), s = a2 / (a2 - a1)
        let triangle = a2 * t / 2
        if triangle == 0 { return nil }
        let alpha = 2 - (4 - area / triangle / 0.3).squareRoot()
        guard alpha.isFinite else { return nil }
        let c0 = p0 + (t * alpha) * (p1 - p0), c1 = p3 + (s * alpha) * (p2 - p3)

        var pen = 0.0
        k = i1
        while k != j {
            let k1 = md(k + 1)
            let tt = CurveFitter.tangent(p0, c0, c1, p3, v[k], v[k1])
            if tt < -0.5 { return nil }
            let pt = CurveFitter.bezier(tt, p0, c0, c1, p3)
            let dd = CurveFitter.dist(v[k], v[k1])
            if dd == 0 { return nil }
            let d1 = CurveFitter.dpara(v[k], v[k1], pt) / dd
            if abs(d1) > CurveFitter.optTolerance { return nil }
            if CurveFitter.iprod(v[k], v[k1], pt) < 0 || CurveFitter.iprod(v[k1], v[k], pt) < 0 { return nil }
            pen += d1 * d1
            k = k1
        }
        k = i
        while k != j {
            let k1 = md(k + 1)
            let tt = CurveFitter.tangent(p0, c0, c1, p3, segEnd[k], segEnd[k1])
            if tt < -0.5 { return nil }
            let pt = CurveFitter.bezier(tt, p0, c0, c1, p3)
            let dd = CurveFitter.dist(segEnd[k], segEnd[k1])
            if dd == 0 { return nil }
            var d1 = CurveFitter.dpara(segEnd[k], segEnd[k1], pt) / dd
            var d2 = CurveFitter.dpara(segEnd[k], segEnd[k1], v[k1]) / dd * 0.75 * segAlpha[k1]
            if d2 < 0 { d1 = -d1; d2 = -d2 }
            if d1 < d2 - CurveFitter.optTolerance { return nil }
            if d1 < d2 { pen += (d1 - d2) * (d1 - d2) }
            k = k1
        }
        return (pen, c0, c1)
    }

    /// Joins runs of Bézier segments into fewer, longer ones (potrace `opticurve`): the
    /// fewest segments, then the least penalty. This evens out curvature — circles become
    /// round instead of rounded polygons. Results land in `out*`, covering segments 1…
    /// (segment 0 stays as is: the start stub of open chains, the start point of loops).
    private mutating func optimizeCurve(open: Bool) {
        let m = segEnd.count
        convexity.removeAll(keepingCapacity: true)
        for i in 0..<m {
            if segCorner[i] {
                convexity.append(0)
            } else {
                let turn = CurveFitter.dpara(segVertex[(i + m - 1) % m], segVertex[i], segVertex[(i + 1) % m])
                convexity.append(turn > 0 ? 1 : (turn < 0 ? -1 : 0))
            }
        }
        areaPrefix.removeAll(keepingCapacity: true)
        areaPrefix.append(0)
        var area = 0.0
        let p0 = segVertex[0]
        for i in 0..<(open ? m - 1 : m) {
            let i1 = (i + 1) % m
            if !segCorner[i1] {
                let alpha = segAlpha[i1]
                area += 0.3 * alpha * (4 - alpha) * CurveFitter.dpara(segEnd[i], segVertex[i1], segEnd[i1]) / 2
                area += CurveFitter.dpara(p0, segEnd[i], segEnd[i1]) / 2
            }
            areaPrefix.append(area)
        }

        let last = open ? m - 1 : m
        if optPrev.count < last + 1 {
            optPrev = [Int](repeating: 0, count: last + 1)
            optLen = [Int](repeating: 0, count: last + 1)
            optPen = [Double](repeating: 0, count: last + 1)
            optC0 = [SIMD2<Double>](repeating: .zero, count: last + 1)
            optC1 = [SIMD2<Double>](repeating: .zero, count: last + 1)
        }
        optPrev[0] = -1; optPen[0] = 0; optLen[0] = 0
        if last >= 1 {
            for j in 1...last {
                optPrev[j] = j - 1; optPen[j] = optPen[j - 1]; optLen[j] = optLen[j - 1] + 1
                var i = j - 2
                while i >= 0 {
                    guard let o = optiPenalty(i, open ? j : j % m, open: open) else { break }
                    if optLen[j] > optLen[i] + 1 || (optLen[j] == optLen[i] + 1 && optPen[j] > optPen[i] + o.pen) {
                        optPrev[j] = i; optPen[j] = optPen[i] + o.pen; optLen[j] = optLen[i] + 1
                        optC0[j] = o.c0; optC1[j] = o.c1
                    }
                    i -= 1
                }
            }
        }

        outCorner.removeAll(keepingCapacity: true); outC0.removeAll(keepingCapacity: true)
        outC1.removeAll(keepingCapacity: true); outVertex.removeAll(keepingCapacity: true)
        outEnd.removeAll(keepingCapacity: true)
        var j = last
        while j > 0 {
            let jm = j % m
            if optPrev[j] == j - 1 {
                outCorner.append(segCorner[jm]); outC0.append(segC0[jm]); outC1.append(segC1[jm])
                outVertex.append(segVertex[jm])
            } else {
                outCorner.append(false); outC0.append(optC0[j]); outC1.append(optC1[j]); outVertex.append(segVertex[jm])
            }
            outEnd.append(segEnd[jm])
            j = optPrev[j]
        }
        outCorner.reverse(); outC0.reverse(); outC1.reverse(); outVertex.reverse(); outEnd.reverse()
    }

    /// Appends the optimized curve, starting after `start` (already emitted).
    private func flattenOutput(from start: SIMD2<Double>, into out: inout DenseCurve) {
        var p0 = start
        for s in 0..<outEnd.count {
            let end = outEnd[s]
            if outCorner[s] {
                let v = outVertex[s]
                let inLen = CurveFitter.dist(p0, v), outLen = CurveFitter.dist(v, end)
                let d = min(cornerRadius, 0.9 * inLen, 0.9 * outLen)
                if d > 0.05 {
                    // Soften the corner with a fillet (a quadratic arc with its control
                    // point on the corner), keeping both legs straight up to it.
                    let a = v + (d / inLen) * (p0 - v), b = v + (d / outLen) * (end - v)
                    let c0 = a + (2.0 / 3.0) * (v - a), c1 = b + (2.0 / 3.0) * (v - b)
                    out.append(a, pinned: true)
                    let steps = max(2, Int((0.75 * CurveFitter.dist(a - 2 * c0 + c1, .zero) / flattenTolerance).squareRoot().rounded(.up)))
                    for k in 1..<steps { out.append(CurveFitter.bezier(Double(k) / Double(steps), a, c0, c1, b), pinned: false) }
                    out.append(b, pinned: true)
                } else {
                    out.append(v, pinned: true)
                }
                out.append(end, pinned: false)
            } else {
                let c0 = outC0[s], c1 = outC1[s]
                let d1 = p0 - 2 * c0 + c1, d2 = c0 - 2 * c1 + end
                let dd = max((d1 * d1).sum(), (d2 * d2).sum()).squareRoot()
                let steps = min(64, max(1, Int((0.75 * dd / flattenTolerance).squareRoot().rounded(.up))))
                for k in 1...steps { out.append(CurveFitter.bezier(Double(k) / Double(steps), p0, c0, c1, end), pinned: false) }
            }
            p0 = end
        }
    }
}
