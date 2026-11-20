import Foundation

/// Plane geometry for the stone book (`StoneBook`): polygons as corner lists, in canvas units.
enum BookGeometry {
    typealias Point = SIMD2<Double>

    /// The shoelace area, positive when the corners run counter-clockwise in a y-up plane.
    static func signedArea(_ p: [Point]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        var j = p.count - 1
        for i in p.indices {
            s += p[j].x * p[i].y - p[i].x * p[j].y
            j = i
        }
        return s / 2
    }

    static func area(_ p: [Point]) -> Double { abs(signedArea(p)) }

    /// The mean of the corners.
    static func centre(_ p: [Point]) -> Point {
        p.reduce(Point(0, 0), +) / Double(max(p.count, 1))
    }

    static func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    /// The convex hull (Andrew's monotone chain), counter-clockwise by `cross`, no repeated corner.
    static func hull(_ points: [Point]) -> [Point] {
        let pts = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard pts.count >= 3 else { return pts }
        var lower: [Point] = [], upper: [Point] = []
        for p in pts {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in pts.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// A convex polygon with its least-needed corners cut away (each removal loses the least area
    /// of any), to at most `corners` or until the next would lose more than `loss` of the area
    /// all told: the straight cuts of nippers rather than a traced outline. Stays inside the
    /// polygon, and convex.
    static func simplified(_ convex: [Point], corners: Int = 7, loss: Double = 0.05) -> [Point] {
        var p = convex
        let budget = area(convex) * loss
        var lost = 0.0
        while p.count > 4 {
            var best = -1, bestLoss = Double.infinity
            for i in p.indices {
                let a = abs(cross(p[(i + p.count - 1) % p.count], p[i], p[(i + 1) % p.count])) / 2
                if a < bestLoss { bestLoss = a; best = i }
            }
            guard p.count > corners || lost + bestLoss <= budget * 0.4 else { break }
            guard lost + bestLoss <= budget else { break }
            lost += bestLoss
            p.remove(at: best)
        }
        return p
    }

    /// The narrowest a convex polygon is across, over every direction (rotating calipers: the
    /// least, over its edges, of the farthest corner from the edge's line).
    static func minimumWidth(_ convex: [Point]) -> Double {
        guard convex.count >= 3 else { return 0 }
        var best = Double.infinity
        var j = convex.count - 1
        for i in convex.indices {
            let a = convex[j], b = convex[i]
            let len = ((b - a) * (b - a)).sum().squareRoot()
            if len > 1e-12 {
                var far = 0.0
                for p in convex { far = max(far, abs(cross(a, b, p)) / len) }
                best = min(best, far)
            }
            j = i
        }
        return best
    }

    /// A convex piece turned to lie flat, as it sits in a parts box: the edge it is narrowest across
    /// laid level, its bounding box's corner at the origin.
    static func flat(_ convex: [Point]) -> [Point] {
        guard convex.count >= 3 else { return convex }
        var best = Double.infinity, angle = 0.0
        var j = convex.count - 1
        for i in convex.indices {
            let a = convex[j], b = convex[i]
            let len = ((b - a) * (b - a)).sum().squareRoot()
            if len > 1e-12 {
                var far = 0.0
                for p in convex { far = max(far, abs(cross(a, b, p)) / len) }
                if far < best - 1e-9 { best = far; angle = atan2(b.y - a.y, b.x - a.x) }
            }
            j = i
        }
        let c = cos(-angle), s = sin(-angle)
        let turned = convex.map { Point($0.x * c - $0.y * s, $0.x * s + $0.y * c) }
        var lo = Point(.infinity, .infinity)
        for p in turned { lo = pointwiseMin(lo, p) }
        return turned.map { $0 - lo }
    }

    /// A convex polygon with each edge moved `d` inward (a mitred inset), or nil when it vanishes:
    /// the polygon clipped by each edge's inner half-plane in turn.
    static func inset(_ convex: [Point], by d: Double) -> [Point]? {
        guard convex.count >= 3 else { return nil }
        let ccw = signedArea(convex) > 0
        var poly = convex
        let n = convex.count
        for i in 0..<n {
            let a = convex[i], b = convex[(i + 1) % n]
            let e = b - a
            let len = ((e * e).sum()).squareRoot()
            guard len > 1e-12 else { continue }
            // the inward normal: left of the edge when the polygon runs counter-clockwise
            var normal = Point(-e.y, e.x) / len
            if !ccw { normal = -normal }
            let origin = a + normal * d
            func side(_ p: Point) -> Double { ((p - origin) * normal).sum() }
            var out: [Point] = []
            for k in poly.indices {
                let p = poly[k], q = poly[(k + 1) % poly.count]
                let sp = side(p), sq = side(q)
                if sp >= 0 { out.append(p) }
                if (sp >= 0) != (sq >= 0) {
                    out.append(p + (q - p) * (sp / (sp - sq)))
                }
            }
            poly = out
            if poly.count < 3 { return nil }
        }
        var clean: [Point] = []
        for p in poly where clean.last.map({ ((p - $0) * (p - $0)).sum() > 1e-12 }) ?? true { clean.append(p) }
        if let f = clean.first, let l = clean.last, clean.count > 1, ((f - l) * (f - l)).sum() <= 1e-12 { clean.removeLast() }
        return clean.count >= 3 && area(clean) > 1e-12 ? clean : nil
    }

    /// Even-odd point in polygon.
    static func contains(_ poly: [Point], _ p: Point) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// The polygon as triangles of its own corners (earcut), each a list of three corner indices.
    static func triangles(_ poly: [Point]) -> [[Int]] {
        var earcut = Earcut()
        var out: [UInt32] = []
        earcut.triangulate(poly, holeStarts: [], into: &out)
        return stride(from: 0, to: out.count - 2, by: 3).map { [Int(out[$0]), Int(out[$0 + 1]), Int(out[$0 + 2])] }
    }

    /// Two pieces of one polygon (corner-index lists, both in the polygon's winding) joined along an
    /// edge they share, or nil when they share none.
    static func join(_ a: [Int], _ b: [Int]) -> [Int]? {
        for i in a.indices {
            let u = a[i], v = a[(i + 1) % a.count]
            // b runs the shared edge the other way: v then u
            guard let j = b.firstIndex(of: v), b[(j + 1) % b.count] == u else { continue }
            // a from v round to u, then b's corners strictly between u and v
            var out: [Int] = []
            var k = (i + 1) % a.count
            for _ in 0..<a.count { out.append(a[k]); k = (k + 1) % a.count }   // v ... u
            var m = (j + 2) % b.count
            while b[m] != v { out.append(b[m]); m = (m + 1) % b.count }
            return out
        }
        return nil
    }
}
