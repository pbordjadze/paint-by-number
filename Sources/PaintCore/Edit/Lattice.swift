import Foundation

/// A point on the template's coordinate grid, in units of `Template.coordinateQuantum`.
typealias LatticePoint = SIMD2<Int64>

/// Exact planar geometry on that grid, for the manual editor (`TemplateEditor`): orientation,
/// segment contact and point containment are decided in integer arithmetic, so an edit gives the
/// same template on every device, and a point it computes (where two lines cross) is the one
/// lattice point nearest the true one, by one rule everywhere.
///
/// Coordinates are bounded (`TemplateEditor` refuses a canvas over `maximumCanvas` and clamps
/// what it is given to `inputLimit`), so differences fit in 27 bits and a cross product in 55:
/// plain `Int64` arithmetic cannot overflow.
enum Lattice {
    /// Lattice steps per canvas unit.
    static let unit = Int64((1 / Template.coordinateQuantum).rounded())
    /// The largest canvas side an edit works on, canvas units: what a `Float` still holds on
    /// the quantum grid (24 bits of 1/256).
    static let maximumCanvas = 1 << 15
    /// Points handed to an edit are clamped to ± this, canvas units, before they are used.
    static let inputLimit: Float = 65536

    static func point(_ p: SIMD2<Float>) -> LatticePoint {
        let u = Double(unit)
        return LatticePoint(Int64((Double(p.x) * u).rounded()), Int64((Double(p.y) * u).rounded()))
    }

    /// The lattice point nearest a point as an edit is handed it, held within `inputLimit`.
    static func clampedPoint(_ p: SIMD2<Float>) -> LatticePoint {
        point(pointwiseMin(pointwiseMax(p, SIMD2(repeating: -inputLimit)), SIMD2(repeating: inputLimit)))
    }

    /// Exact inside the canvas bound: a lattice coordinate there has at most 24 significant
    /// bits and the unit is a power of two.
    static func position(_ p: LatticePoint) -> SIMD2<Float> {
        SIMD2(Float(p.x) / Float(unit), Float(p.y) / Float(unit))
    }

    static func double(_ p: LatticePoint) -> SIMD2<Double> {
        SIMD2(Double(p.x) / Double(unit), Double(p.y) / Double(unit))
    }

    /// Twice the signed area of triangle (a, b, c): positive when c is left of a→b (raw
    /// coordinates, as `BoundaryEdge` defines left).
    @inline(__always)
    static func orient(_ a: LatticePoint, _ b: LatticePoint, _ c: LatticePoint) -> Int64 {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    @inline(__always)
    static func cross(_ a: LatticePoint, _ b: LatticePoint) -> Int64 { a.x * b.y - a.y * b.x }

    @inline(__always)
    static func dot(_ a: LatticePoint, _ b: LatticePoint) -> Int64 { a.x * b.x + a.y * b.y }

    @inline(__always)
    static func distanceSquared(_ a: LatticePoint, _ b: LatticePoint) -> Int64 {
        let d = a &- b
        return d.x * d.x + d.y * d.y
    }

    /// Whether `p`, known to be on the line through `a` and `b`, lies between them.
    @inline(__always)
    static func between(_ a: LatticePoint, _ b: LatticePoint, _ p: LatticePoint) -> Bool {
        p.x >= min(a.x, b.x) && p.x <= max(a.x, b.x) && p.y >= min(a.y, b.y) && p.y <= max(a.y, b.y)
    }

    /// `a·b / c` rounded to the nearest integer (halves away from zero), computed in 128 bits.
    /// The quotient must fit in 64 bits, as it does for a point on a segment.
    static func mulDiv(_ a: Int64, _ b: Int64, _ c: Int64) -> Int64 {
        var a = a, c = c
        if c < 0 { a = -a; c = -c }
        let product = a.multipliedFullWidth(by: b)
        let (q, r) = c.dividingFullWidth(product)
        guard r != 0 else { return q }
        return r.magnitude &* 2 >= c.magnitude ? (r < 0 ? q - 1 : q + 1) : q
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return a % b != 0 && (a < 0) != (b < 0) ? q - 1 : q
    }

    static func lexicographicallyBefore(_ a: LatticePoint, _ b: LatticePoint) -> Bool {
        a.x != b.x ? a.x < b.x : a.y < b.y
    }

    // MARK: - Segment contact

    /// How two closed segments meet.
    enum Contact: Equatable {
        case none
        /// Interiors cross at one point (rounded to the lattice).
        case cross(LatticePoint)
        /// They share exactly one point, which is an end point of at least one: a lattice point.
        case touch(LatticePoint)
        /// They are collinear and share a stretch of positive length.
        case overlap(LatticePoint, LatticePoint)
    }

    static func contact(_ a0: LatticePoint, _ a1: LatticePoint, _ b0: LatticePoint, _ b1: LatticePoint) -> Contact {
        if max(a0.x, a1.x) < min(b0.x, b1.x) || max(b0.x, b1.x) < min(a0.x, a1.x)
            || max(a0.y, a1.y) < min(b0.y, b1.y) || max(b0.y, b1.y) < min(a0.y, a1.y) { return .none }
        let o1 = orient(a0, a1, b0).signum(), o2 = orient(a0, a1, b1).signum()
        let o3 = orient(b0, b1, a0).signum(), o4 = orient(b0, b1, a1).signum()
        if o1 * o2 < 0 && o3 * o4 < 0 { return .cross(crossing(a0, a1, b0, b1)) }
        if o1 == 0 && o2 == 0 {
            // Collinear: compare along the axis the segments run on.
            let alongX = a0.x != a1.x || b0.x != b1.x
            func key(_ p: LatticePoint) -> Int64 { alongX ? p.x : p.y }
            let lo = max(min(key(a0), key(a1)), min(key(b0), key(b1)))
            let hi = min(max(key(a0), key(a1)), max(key(b0), key(b1)))
            if lo > hi { return .none }
            let ends = [a0, a1, b0, b1]
            let first = ends.first { key($0) == lo }!, last = ends.first { key($0) == hi }!
            return lo == hi ? .touch(first) : .overlap(first, last)
        }
        if o1 == 0 && between(a0, a1, b0) { return .touch(b0) }
        if o2 == 0 && between(a0, a1, b1) { return .touch(b1) }
        if o3 == 0 && between(b0, b1, a0) { return .touch(a0) }
        if o4 == 0 && between(b0, b1, a1) { return .touch(a1) }
        return .none
    }

    /// The lattice point nearest the crossing of segments a0a1 and b0b1 (which cross properly).
    /// Both segments are put in a canonical order first, so the point does not depend on which
    /// is asked about, nor on their directions.
    static func crossing(_ a0: LatticePoint, _ a1: LatticePoint, _ b0: LatticePoint, _ b1: LatticePoint) -> LatticePoint {
        func canonical(_ p: LatticePoint, _ q: LatticePoint) -> (LatticePoint, LatticePoint) {
            lexicographicallyBefore(q, p) ? (q, p) : (p, q)
        }
        var (p0, p1) = canonical(a0, a1)
        var (q0, q1) = canonical(b0, b1)
        if lexicographicallyBefore(q0, p0) || (q0 == p0 && lexicographicallyBefore(q1, p1)) {
            swap(&p0, &q0)
            swap(&p1, &q1)
        }
        let d1 = p1 &- p0, d2 = q1 &- q0
        let denominator = cross(d1, d2)
        let numerator = cross(q0 &- p0, d2)
        return LatticePoint(p0.x + mulDiv(d1.x, numerator, denominator), p0.y + mulDiv(d1.y, numerator, denominator))
    }

    // MARK: - Nearest point

    /// The point of segment ab nearest `p`, on the lattice, and its squared distance from `p`.
    static func nearest(to p: LatticePoint, on a: LatticePoint, _ b: LatticePoint) -> (point: LatticePoint, distanceSquared: Int64) {
        let d = b &- a
        let length = dot(d, d)
        guard length > 0 else { return (a, distanceSquared(p, a)) }
        let along = dot(p &- a, d)
        let point: LatticePoint
        if along <= 0 {
            point = a
        } else if along >= length {
            point = b
        } else {
            point = LatticePoint(a.x + mulDiv(d.x, along, length), a.y + mulDiv(d.y, along, length))
        }
        return (point, distanceSquared(p, point))
    }

    // MARK: - Polygons

    enum Containment { case inside, outside, boundary }

    /// Where `p` lies against rings taken together (even-odd: holes count out), each ring a
    /// polygon without its closing point.
    static func contains(_ rings: [[LatticePoint]], _ p: LatticePoint) -> Containment {
        var inside = false
        for ring in rings where ring.count >= 2 {
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[j], b = ring[i]
                j = i
                let o = orient(a, b, p)
                if o == 0 && between(a, b, p) { return .boundary }
                if (a.y > p.y) != (b.y > p.y), b.y > a.y ? o > 0 : o < 0 { inside.toggle() }
            }
        }
        return inside ? .inside : .outside
    }

    /// Twice the signed shoelace area of a ring (positive for an outer ring: counter-clockwise
    /// in raw coordinates, as `BoundaryEdge` defines). Wrapping: the sum is exact whenever its
    /// result fits, whatever the partial sums.
    static func area2(_ ring: [LatticePoint]) -> Int64 {
        guard ring.count >= 3 else { return 0 }
        var sum: Int64 = 0
        var j = ring.count - 1
        for i in 0..<ring.count {
            sum = sum &+ (ring[j].x &* ring[i].y) &- (ring[i].x &* ring[j].y)
            j = i
        }
        return sum
    }

    // MARK: - Angles

    /// Orders directions by their clockwise turn from `back` in (0, 360°], the full turn being
    /// `back` itself: the next boundary edge of a face that lies on the left of the edge arriving
    /// along −`back` is the outgoing edge with the smallest such turn. Returns whether `u`
    /// comes before `v`.
    static func clockwiseBefore(from back: LatticePoint, _ u: LatticePoint, _ v: LatticePoint) -> Bool {
        func half(_ d: LatticePoint) -> Int {
            let c = cross(back, d)
            if c < 0 { return 0 }
            if c == 0 { return dot(back, d) < 0 ? 1 : 3 }
            return 2
        }
        let hu = half(u), hv = half(v)
        if hu != hv { return hu < hv }
        // Same half-turn: u first when v lies clockwise of it.
        return cross(u, v) < 0
    }
}
