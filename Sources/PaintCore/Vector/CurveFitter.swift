import Foundation

/// Fits smooth curves to stair-stepped lattice chains, after Peter Selinger's potrace
/// ("Potrace: a polygon-based tracing algorithm", 2003):
///
/// 1. find the longest *straight* sub-paths (a line exists that passes within half a
///    pixel of every lattice point),
/// 2. choose the polygon with the fewest segments (then least squared deviation) whose
///    segments all follow straight sub-paths,
/// 3. move each polygon vertex to the point within its lattice square that best fits
///    the two adjacent segments' least-squares lines,
/// 4. turn each vertex into either a sharp corner (when it sticks out far relative to its
///    neighbours, `alphaMax`) or a cubic Bézier through the adjacent edge midpoints.
///
/// Digitized straight lines of any slope come out perfectly straight, circles come out
/// round and genuine corners stay crisp. Unlike potrace, open chains are supported: their
/// end points (junctions shared with other edges) stay exactly where they are, so every
/// edge can be fitted independently and still meet its neighbours.
///
/// Holds scratch buffers; create one per worker and reuse it across chains.
struct CurveFitter {
    /// Vertices whose `alpha` reaches this become corners (potrace default: 1).
    var alphaMax: Double
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

    init(alphaMax: Double, flattenTolerance: Double) {
        self.alphaMax = alphaMax
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
    /// starts and ends exactly at the chain's end points. Returns false when the fit
    /// degenerates (the caller then uses a simpler fallback).
    mutating func fitOpen(_ points: [SIMD2<Int32>], into out: inout [SIMD2<Double>]) -> Bool {
        let n = points.count - 1
        load(points, count: n + 1)
        let first = SIMD2(Double(points[0].x), Double(points[0].y))
        let last = SIMD2(Double(points[n].x), Double(points[n].y))
        calcLonOpen(n)
        let m = bestPolygonOpen(n)
        if m == 1 {
            if first == last { return false }
            out.append(first); out.append(last)
            return true
        }
        if first == last && m < 3 { return false }
        adjustVerticesOpen(n, m)
        // Curve: straight from the start to the first edge midpoint, one piece per interior
        // vertex, straight from the last edge midpoint to the end.
        out.append(first)
        out.append(mid(0, 1))
        for j in 1..<m { emitVertex(i: j - 1, j: j, k: j + 1, into: &out) }
        out.append(last)
        return true
    }

    /// Fits a closed chain (`points` ends with a repeat of its first point, at least four
    /// unit steps). The output repeats its first point at the end.
    mutating func fitClosed(_ points: [SIMD2<Int32>], into out: inout [SIMD2<Double>]) -> Bool {
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
        let start = out.count
        out.append(mid(m - 1, 0))
        for j in 0..<m { emitVertex(i: (j + m - 1) % m, j: j, k: (j + 1) % m, into: &out) }
        out[out.count - 1] = out[start]
        return true
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

    /// The point within the unit square centred on (sxc, syc) minimizing Q.
    private func minimize(_ qIn: Quad, _ sxc: Double, _ syc: Double) -> (Double, Double) {
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
        if abs(wx - sxc) <= 0.5 && abs(wy - syc) <= 0.5 { return (wx, wy) }
        // Minimum outside the square: search its boundary.
        var best = q.eval(sxc, syc)
        var bx = sxc, by = syc
        if q.xx != 0 {
            for z in 0..<2 {
                let y = syc - 0.5 + Double(z)
                let x = -(q.xy * y + q.x1) / q.xx
                let cand = q.eval(x, y)
                if abs(x - sxc) <= 0.5 && cand < best { best = cand; bx = x; by = y }
            }
        }
        if q.yy != 0 {
            for z in 0..<2 {
                let x = sxc - 0.5 + Double(z)
                let y = -(q.xy * x + q.y1) / q.yy
                let cand = q.eval(x, y)
                if abs(y - syc) <= 0.5 && cand < best { best = cand; bx = x; by = y }
            }
        }
        for l in 0..<2 {
            for k in 0..<2 {
                let x = sxc - 0.5 + Double(l), y = syc - 0.5 + Double(k)
                let cand = q.eval(x, y)
                if cand < best { best = cand; bx = x; by = y }
            }
        }
        return (bx, by)
    }

    private mutating func adjustVerticesOpen(_ n: Int, _ m: Int) {
        let x0 = Double(px[0]), y0 = Double(py[0])
        quads.removeAll(keepingCapacity: true)
        for s in 0..<m {
            let ps = pointSlope(po[s], po[s + 1], count: n + 1)
            quads.append(lineQuad(ps.cx, ps.cy, ps.dx, ps.dy))
        }
        vx.removeAll(keepingCapacity: true); vy.removeAll(keepingCapacity: true)
        vx.append(x0); vy.append(y0)
        for i in 1..<m {
            let q = quads[i - 1] + quads[i]
            let (wx, wy) = minimize(q, Double(px[po[i]]) - x0, Double(py[po[i]]) - y0)
            vx.append(wx + x0); vy.append(wy + y0)
        }
        vx.append(Double(px[n])); vy.append(Double(py[n]))
    }

    private mutating func adjustVerticesCyclic(_ n: Int, _ m: Int) {
        let x0 = Double(px[0]), y0 = Double(py[0])
        quads.removeAll(keepingCapacity: true)
        for i in 0..<m {
            var j = po[(i + 1) % m]
            j = CurveFitter.mod(j - po[i], n) + po[i]
            let ps = pointSlope(po[i], j, count: n)
            quads.append(lineQuad(ps.cx, ps.cy, ps.dx, ps.dy))
        }
        vx.removeAll(keepingCapacity: true); vy.removeAll(keepingCapacity: true)
        for i in 0..<m {
            let j = (i + m - 1) % m
            let q = quads[j] + quads[i]
            let (wx, wy) = minimize(q, Double(px[po[i]]) - x0, Double(py[po[i]]) - y0)
            vx.append(wx + x0); vy.append(wy + y0)
        }
    }

    // MARK: - Stage 4: corners and Béziers

    @inline(__always) private func vertex(_ i: Int) -> SIMD2<Double> { SIMD2(vx[i], vy[i]) }
    @inline(__always) private func mid(_ a: Int, _ b: Int) -> SIMD2<Double> { (vertex(a) + vertex(b)) * 0.5 }

    /// Emits the curve piece around vertex j, from mid(i, j) (already emitted) to mid(j, k).
    private func emitVertex(i: Int, j: Int, k: Int, into out: inout [SIMD2<Double>]) {
        let vi = vertex(i), vj = vertex(j), vk = vertex(k)
        let end = (vj + vk) * 0.5
        let dxk = vk.x - vi.x, dyk = vk.y - vi.y
        let denom = abs(dxk) + abs(dyk)
        var alpha: Double
        if denom != 0 {
            let dd = abs((vj.x - vi.x) * dyk - dxk * (vj.y - vi.y)) / denom
            alpha = dd > 1 ? (1 - 1 / dd) / 0.75 : 0
        } else {
            alpha = 4.0 / 3.0
        }
        if alpha >= alphaMax {
            out.append(vj)
            out.append(end)
            return
        }
        alpha = min(max(alpha, 0.55), 1)
        let start = (vi + vj) * 0.5
        let c1 = vi + (0.5 + 0.5 * alpha) * (vj - vi)
        let c2 = vk + (0.5 + 0.5 * alpha) * (vj - vk)
        let d1 = start - 2 * c1 + c2, d2 = c1 - 2 * c2 + end
        let dd = max((d1 * d1).sum(), (d2 * d2).sum()).squareRoot()
        let steps = min(64, max(1, Int((0.75 * dd / flattenTolerance).squareRoot().rounded(.up))))
        for s in 1...steps {
            let t = Double(s) / Double(steps), u = 1 - t
            let p = (u * u * u) * start + (3 * u * u * t) * c1 + (3 * u * t * t) * c2 + (t * t * t) * end
            out.append(p)
        }
    }
}
