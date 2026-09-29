/// Evens out the curvature of fitted curves.
///
/// potrace-style fits pass through the midpoints of a polygon's edges with the edges as
/// tangents, so mid-sized round shapes come out as rounded polygons with subtly flat
/// sides. Fairing resamples the curve uniformly along its arc length and replaces every
/// point by a tricube-weighted local *quadratic* regression over a window of neighbours.
/// Quadratic (rather than plain averaging) reproduces circles and straight lines exactly,
/// so nothing shrinks and straight runs stay straight, while the curvature ripples
/// between polygon vertices are smoothed away. Pinned points (junctions, corners) never
/// move and split the curve into independently faired runs; no point moves further than
/// `maxShift`. The result is simplified back to a compact polyline.
struct CurveFairing {
    /// Half-width of the regression window along the curve, canvas units; 0 disables fairing.
    var halfWindow: Double
    /// Upper bound on how far fairing may move a point.
    var maxShift: Double
    /// Douglas–Peucker tolerance for the output polyline.
    var tolerance: Double
    /// Resampling step along the curve.
    var spacing = 0.5

    private var sequence: [SIMD2<Double>] = [], sequencePins: [Bool] = []
    private var samples: [SIMD2<Double>] = [], faired: [SIMD2<Double>] = []
    private var arc: [Double] = []
    private var kernel: [Double] = []
    private var kernelHalf = -1
    private var keep: [Bool] = []
    private var stack: [(Int, Int)] = []

    init(halfWindow: Double, maxShift: Double, tolerance: Double) {
        self.halfWindow = halfWindow
        self.maxShift = maxShift
        self.tolerance = tolerance
    }

    /// Fairs `curve` (closed curves repeat their first point at the end) into `out`.
    /// Pinned points and the ends of open curves are kept exactly.
    mutating func fair(_ curve: DenseCurve, closed: Bool, into out: inout [SIMD2<Double>]) {
        out.removeAll(keepingCapacity: true)
        let pts = curve.points
        let n = pts.count
        guard halfWindow > 0, n >= 3 else {
            out.append(contentsOf: pts)
            return
        }
        sequence.removeAll(keepingCapacity: true)
        sequencePins.removeAll(keepingCapacity: true)
        if closed {
            if let p = curve.pinned[0..<(n - 1)].firstIndex(of: true) {
                // Start and end at a pin so every run is bounded by pins.
                for i in p..<(n - 1) { sequence.append(pts[i]); sequencePins.append(curve.pinned[i]) }
                for i in 0...p { sequence.append(pts[i]); sequencePins.append(curve.pinned[i]) }
            } else {
                fairLoop(Array(pts[0..<(n - 1)]), into: &out)
                return
            }
        } else {
            sequence = pts
            sequencePins = curve.pinned
            sequencePins[0] = true
            sequencePins[n - 1] = true
        }
        out.append(sequence[0])
        var a = 0
        for b in 1..<sequence.count where sequencePins[b] {
            fairRun(a, b, into: &out)
            a = b
        }
    }

    // MARK: - Runs

    /// Fairs sequence[a...b] with both ends fixed; appends everything after sequence[a].
    private mutating func fairRun(_ a: Int, _ b: Int, into out: inout [SIMD2<Double>]) {
        resample(sequence, a...b, closed: false)
        let count = samples.count
        guard count >= 5 else {
            for i in (a + 1)...b { out.append(sequence[i]) }
            return
        }
        faired.removeAll(keepingCapacity: true)
        faired.append(samples[0])
        let k = max(1, Int(halfWindow / spacing))
        for i in 1..<(count - 1) {
            faired.append(regress(at: i, halfWidth: k, count: count, cyclic: false))
        }
        faired.append(samples[count - 1])
        simplify(closed: false)
        for i in 1..<count where keep[i] { out.append(faired[i]) }
    }

    /// Fairs a closed curve without pins.
    private mutating func fairLoop(_ pts: [SIMD2<Double>], into out: inout [SIMD2<Double>]) {
        var ring = pts
        ring.append(pts[0])
        resample(ring, 0...(ring.count - 1), closed: true)
        let count = samples.count
        guard count >= 8 else {
            out.append(contentsOf: ring)
            return
        }
        let k = max(1, min(Int(halfWindow / spacing), (count - 1) / 2))
        faired.removeAll(keepingCapacity: true)
        for i in 0..<count { faired.append(regress(at: i, halfWidth: k, count: count, cyclic: true)) }
        faired.append(faired[0])
        simplify(closed: true)
        for i in 0..<faired.count where keep[i] { out.append(faired[i]) }
    }

    /// Uniform resampling of a polyline along its arc length (closed: the last point
    /// repeats the first and is not emitted).
    private mutating func resample(_ pts: [SIMD2<Double>], _ range: ClosedRange<Int>, closed: Bool) {
        let base = range.lowerBound, n = range.count
        arc.removeAll(keepingCapacity: true)
        arc.append(0)
        for i in 1..<n {
            let d = pts[base + i] - pts[base + i - 1]
            arc.append(arc[i - 1] + (d * d).sum().squareRoot())
        }
        let length = arc[n - 1]
        samples.removeAll(keepingCapacity: true)
        let segments = max(1, Int((length / spacing).rounded()))
        let step = length / Double(segments)
        var j = 0
        for s in 0...segments {
            if closed && s == segments { break }
            let t = Double(s) * step
            while j < n - 2 && arc[j + 1] < t { j += 1 }
            let span = arc[j + 1] - arc[j]
            let f = span > 0 ? min(max((t - arc[j]) / span, 0), 1) : 0
            samples.append(pts[base + j] + f * (pts[base + j + 1] - pts[base + j]))
        }
        if !closed { samples[samples.count - 1] = pts[range.upperBound] }
    }

    // MARK: - Local quadratic regression

    @inline(__always)
    private static func tricube(_ u: Int, _ k: Int) -> Double {
        let r = Double(abs(u)) / Double(k + 1)
        let c = 1 - r * r * r
        return c * c * c
    }

    /// Equivalent kernel of a full symmetric window: the regression's value at the centre
    /// is Σ kernel[u + k] · y(u).
    private mutating func prepareKernel(_ k: Int) {
        guard kernelHalf != k else { return }
        kernelHalf = k
        var s0 = 0.0, s2 = 0.0, s4 = 0.0
        for u in -k...k {
            let w = CurveFairing.tricube(u, k), uu = Double(u * u)
            s0 += w; s2 += w * uu; s4 += w * uu * uu
        }
        let det = s0 * s4 - s2 * s2
        kernel = (-k...k).map { u in
            CurveFairing.tricube(u, k) * (s4 - s2 * Double(u * u)) / det
        }
    }

    private mutating func regress(at i: Int, halfWidth k: Int, count: Int, cyclic: Bool) -> SIMD2<Double> {
        let origin = samples[i]
        var result: SIMD2<Double>
        if cyclic || (i - k >= 0 && i + k < count) {
            prepareKernel(k)
            result = .zero
            for u in -k...k {
                var j = i + u
                if j < 0 { j += count } else if j >= count { j -= count }
                result += kernel[u + k] * (samples[j] - origin)
            }
            result += origin
        } else {
            // Truncated window near a pinned end: solve the weighted normal equations.
            var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0
            var t0 = SIMD2<Double>.zero, t1 = SIMD2<Double>.zero, t2 = SIMD2<Double>.zero
            for j in max(0, i - k)...min(count - 1, i + k) {
                let u = Double(j - i), w = CurveFairing.tricube(j - i, k)
                let y = samples[j] - origin
                s0 += w; s1 += w * u; s2 += w * u * u; s3 += w * u * u * u; s4 += w * u * u * u * u
                t0 += w * y; t1 += (w * u) * y; t2 += (w * u * u) * y
            }
            let c0 = s2 * s4 - s3 * s3, c1 = s1 * s4 - s3 * s2, c2 = s1 * s3 - s2 * s2
            let det = s0 * c0 - s1 * c1 + s2 * c2
            guard abs(det) > 1e-9 else { return origin }
            // Cramer's rule for the constant term.
            result = origin + (c0 * t0 - c1 * t1 + c2 * t2) / det
        }
        let shift = result - origin
        let len = (shift * shift).sum().squareRoot()
        return len > maxShift ? origin + shift * (maxShift / len) : result
    }

    // MARK: - Simplification

    /// Douglas–Peucker over `faired`, marking kept points in `keep` (ends always kept).
    private mutating func simplify(closed: Bool) {
        let n = faired.count
        keep.removeAll(keepingCapacity: true)
        keep.append(contentsOf: repeatElement(false, count: n))
        keep[0] = true
        keep[n - 1] = true
        stack.removeAll(keepingCapacity: true)
        if closed && n > 4 {
            // Split the loop at its farthest point from the start so both halves are open.
            var far = 1, best = -1.0
            for i in 1..<(n - 1) {
                let d = faired[i] - faired[0]
                let dd = (d * d).sum()
                if dd > best { best = dd; far = i }
            }
            keep[far] = true
            stack.append((0, far)); stack.append((far, n - 1))
        } else {
            stack.append((0, n - 1))
        }
        let tol2 = tolerance * tolerance
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let p = faired[a], q = faired[b]
            var worst = a, worstD = tol2
            for i in (a + 1)..<b {
                let d = FlatPolygon.segmentDistanceSquared(faired[i].x, faired[i].y, p, q)
                if d > worstD { worstD = d; worst = i }
            }
            if worst != a {
                keep[worst] = true
                stack.append((a, worst)); stack.append((worst, b))
            }
        }
    }
}
