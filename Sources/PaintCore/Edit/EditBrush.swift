import Foundation

/// The Paint Brush's footprint: every point within `radius` of the polyline `path` (a disc for a
/// single point), all on the lattice, and its outline.
///
/// The outline is traced on a square grid (`outline`): each grid vertex is in or out of the
/// footprint, decided exactly in integers (`contains`); where a grid edge joins a vertex in to one
/// out, the outline crosses it where the footprint ends along it (the eraser's reach, `Rub`, the
/// same union of stadiums, rounded to the lattice and kept off the edge's ends); each cell joins
/// its crossings as marching squares do, a cell with two diagonal corners in joining them. The
/// crossings lie inside distinct grid edges and each segment inside one cell, so the rings are
/// simple and meet neither each other nor themselves. They are then thinned (Douglas–Peucker
/// within `radius / 40`, in exact distances), and kept thinned only where that leaves them simple
/// and apart. Everything is integer arithmetic on the lattice, or IEEE `+ - * / sqrt` on its
/// values in a fixed order on one thread, so the same stroke gives the same outline on every
/// device and core count.
struct BrushFootprint {
    let path: [LatticePoint]
    let radius: Int64
    let low: LatticePoint
    let high: LatticePoint

    /// The grid's cells at most: a finer grid for a stroke this large widens its cells.
    static let maximumCells = 1 << 20

    init?(path input: [LatticePoint], radius: Int64) {
        let path = EditWork.dedupe(input)
        guard !path.isEmpty, radius > 0 else { return nil }
        self.path = path
        self.radius = radius
        var lo = path[0], hi = path[0]
        for p in path { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
        low = lo &- radius
        high = hi &+ radius
    }

    /// Whether `p` is within the radius of the path, exactly.
    func contains(_ p: LatticePoint) -> Bool {
        guard p.x >= low.x, p.x <= high.x, p.y >= low.y, p.y <= high.y else { return false }
        let r2 = UInt64(radius * radius)
        if path.count == 1 { return Self.within(p, path[0], path[0], r2) }
        for k in 0..<(path.count - 1) where Self.within(p, path[k], path[k + 1], r2) { return true }
        return false
    }

    /// Whether `p` is within √`r2` of segment ab: compared in 128 bits, as the squares of a cross
    /// product of the lattice's differences can need.
    static func within(_ p: LatticePoint, _ a: LatticePoint, _ b: LatticePoint, _ r2: UInt64) -> Bool {
        let d = b &- a, w = p &- a
        let along = Lattice.dot(w, d), length = Lattice.dot(d, d)
        if length == 0 || along <= 0 { return UInt64(Lattice.dot(w, w)) <= r2 }
        if along >= length { return UInt64(Lattice.distanceSquared(p, b)) <= r2 }
        let c = Lattice.cross(d, w).magnitude
        let lhs = c.multipliedFullWidth(by: c), rhs = r2.multipliedFullWidth(by: UInt64(length))
        return lhs.high != rhs.high ? lhs.high < rhs.high : lhs.low <= rhs.low
    }

    /// The outline of the footprint over a canvas `width` × `height` (lattice steps) and a margin
    /// past it: closed rings without a closing point, the footprint on the left of each
    /// (`Lattice.orient`), so outer rings have a positive area and holes a negative one. What
    /// lies beyond the margin is left out, the rings closing past the canvas instead. No vertex
    /// lies on the canvas's frame lines, so a ring meets the frame only where it crosses it.
    func outline(width: Int64, height: Int64) -> [[LatticePoint]] {
        var h = max(radius / 4, 16)
        func span(_ lo: Int64, _ hi: Int64, _ side: Int64) -> (Int64, Int64) { (max(lo, -2 * h), min(hi, side + 2 * h)) }
        var (x0, x1) = span(low.x, high.x, width), (y0, y1) = span(low.y, high.y, height)
        guard x0 < x1, y0 < y1 else { return [] }
        while (x1 - x0) / h + 3 > Int64(Self.maximumCells) / ((y1 - y0) / h + 3) {
            h *= 2
            (x0, x1) = span(low.x, high.x, width)
            (y0, y1) = span(low.y, high.y, height)
        }
        // Grid lines miss the frame: a column at x ≡ c (mod h) never lies on x = 0 or x = width.
        func offset(_ side: Int64) -> Int64 {
            let along = side - Lattice.floorDiv(side, h) * h
            return [h / 2, h / 2 + 1, h / 2 + 2].first { $0 != along }!
        }
        let cx = offset(width), cy = offset(height)
        let gx = (Lattice.floorDiv(x0 - cx, h) - 1) * h + cx, gy = (Lattice.floorDiv(y0 - cy, h) - 1) * h + cy
        let nx = Int((x1 - gx + h - 1) / h) + 1, ny = Int((y1 - gy + h - 1) / h) + 1
        let columns = nx + 1
        func vertex(_ i: Int, _ j: Int) -> LatticePoint { LatticePoint(gx + Int64(i) * h, gy + Int64(j) * h) }

        // In or out, each vertex; the grid's border is out.
        var inside = [Bool](repeating: false, count: columns * (ny + 1))
        let r2 = UInt64(radius * radius)
        let steps = path.count == 1 ? [(path[0], path[0])] : Array(zip(path, path.dropFirst()))
        for (a, b) in steps {
            let lo = pointwiseMin(a, b) &- radius, hi = pointwiseMax(a, b) &+ radius
            let i0 = max(Int(Lattice.floorDiv(lo.x - gx + h - 1, h)), 1), i1 = min(Int(Lattice.floorDiv(hi.x - gx, h)), nx - 1)
            let j0 = max(Int(Lattice.floorDiv(lo.y - gy + h - 1, h)), 1), j1 = min(Int(Lattice.floorDiv(hi.y - gy, h)), ny - 1)
            guard i0 <= i1, j0 <= j1 else { continue }
            // Each row only where the capsule can reach it (a long diagonal's box is mostly
            // empty): the segment's stretch within the radius of the row, widened by the radius
            // and a cell. The test itself stays exact; this bounds only which vertices it sees.
            let ax = Double(a.x), ay = Double(a.y), dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let reach = Double(radius), cell = Double(h)
            for j in j0...j1 {
                let y = Double(gy + Int64(j) * h)
                var low = min(ax, ax + dx), high = max(ax, ax + dx)
                if dy != 0 {
                    let t0 = (y - reach - ay) / dy, t1 = (y + reach - ay) / dy
                    let tl = max(0, min(t0, t1)), th = min(1, max(t0, t1))
                    guard tl <= th else { continue }
                    low = min(ax + dx * tl, ax + dx * th)
                    high = max(ax + dx * tl, ax + dx * th)
                }
                let ri0 = max(i0, Int(((low - reach - Double(gx)) / cell).rounded(.down)) - 1)
                let ri1 = min(i1, Int(((high + reach - Double(gx)) / cell).rounded(.up)) + 1)
                guard ri0 <= ri1 else { continue }
                for i in ri0...ri1 where !inside[j * columns + i] && Self.within(vertex(i, j), a, b, r2) {
                    inside[j * columns + i] = true
                }
            }
        }
        func isIn(_ i: Int, _ j: Int) -> Bool { inside[j * columns + i] }

        // Where the outline crosses the grid edge from vertex `a` (in) to `b` (out).
        let rub = Rub(path: path, radius: Double(radius) / Double(Lattice.unit))
        let margin = max(2, h / 8)
        func crossing(from a: LatticePoint, to b: LatticePoint) -> LatticePoint {
            let ranges = rub.covered(Lattice.double(a), Lattice.double(b))
            let t = ranges.first.map { $0.lowerBound <= 1e-9 ? $0.upperBound : 0 } ?? 0
            let along = min(max(Int64((t * Double(h)).rounded()), margin), h - margin)
            var p = a &+ (b &- a) / h &* along
            // Off the frame lines: a crossing there moves a step out, along its own grid edge.
            if p.x == 0 { p.x = -1 } else if p.x == width { p.x = width + 1 }
            if p.y == 0 { p.y = -1 } else if p.y == height { p.y = height + 1 }
            return p
        }
        var found: [Int: LatticePoint] = [:]
        /// Horizontal edge (i, j)–(i + 1, j) is 2k, vertical (i, j)–(i, j + 1) is 2k + 1.
        func point(horizontal: Bool, _ i: Int, _ j: Int) -> LatticePoint {
            let key = 2 * (j * columns + i) + (horizontal ? 0 : 1)
            if let p = found[key] { return p }
            let a = vertex(i, j), b = horizontal ? vertex(i + 1, j) : vertex(i, j + 1)
            let p = isIn(i, j) ? crossing(from: a, to: b) : crossing(from: b, to: a)
            found[key] = p
            return p
        }

        // Each cell's segments, the footprint on their left.
        var next: [LatticePoint: LatticePoint] = [:]
        var starts: [LatticePoint] = []
        for j in 0..<ny {
            for i in 0..<nx {
                let c = [isIn(i, j), isIn(i + 1, j), isIn(i + 1, j + 1), isIn(i, j + 1)]
                guard c.contains(true), c.contains(false) else { continue }
                let corners = [vertex(i, j), vertex(i + 1, j), vertex(i + 1, j + 1), vertex(i, j + 1)]
                // Sides: top, right, bottom, left; side s joins corners s and s + 1.
                func side(_ s: Int) -> LatticePoint {
                    switch s {
                    case 0: point(horizontal: true, i, j)
                    case 1: point(horizontal: false, i + 1, j)
                    case 2: point(horizontal: true, i, j + 1)
                    default: point(horizontal: false, i, j)
                    }
                }
                let crossed = (0..<4).filter { c[$0] != c[($0 + 1) % 4] }
                let pairs: [(Int, Int)]
                if crossed.count == 4 {
                    // Two diagonal corners in: joined, the segments cutting off the corners out.
                    pairs = c[0] ? [(0, 1), (2, 3)] : [(3, 0), (1, 2)]
                } else {
                    pairs = [(crossed[0], crossed[1])]
                }
                for (s, u) in pairs {
                    // Adjacent sides cut off the corner between them; opposite ones are judged by
                    // the first corner.
                    let corner = (s + 1) % 4 == u ? u : ((u + 1) % 4 == s ? s : 0)
                    var p = side(s), q = side(u)
                    if (Lattice.orient(p, q, corners[corner]) > 0) != c[corner] { swap(&p, &q) }
                    next[p] = q
                    starts.append(p)
                }
            }
        }
        var rings: [[LatticePoint]] = []
        var used = Set<LatticePoint>()
        for s in starts where !used.contains(s) {
            var ring: [LatticePoint] = []
            var p = s
            while used.insert(p).inserted, let q = next[p] {
                ring.append(p)
                p = q
            }
            if ring.count >= 3 { rings.append(ring) }
        }
        let tolerance = max(radius / 40, 1)
        let thinned = rings.map { Self.thinned($0, tolerance: tolerance) }
        return Self.areSimpleAndApart(thinned, like: rings) ? thinned : rings
    }

    /// A closed ring thinned to within `tolerance` lattice steps (Douglas–Peucker from its first
    /// point in lexicographic order and the point farthest from it).
    static func thinned(_ ring: [LatticePoint], tolerance: Int64) -> [LatticePoint] {
        let n = ring.count
        guard n > 4 else { return ring }
        let first = ring.indices.min { Lattice.lexicographicallyBefore(ring[$0], ring[$1]) }!
        var far = first, farthest: Int64 = -1
        for k in ring.indices where Lattice.distanceSquared(ring[k], ring[first]) > farthest {
            far = k
            farthest = Lattice.distanceSquared(ring[k], ring[first])
        }
        var keep = [Bool](repeating: false, count: n)
        keep[first] = true
        keep[far] = true
        var stack = [(first, far), (far, first)]
        let limit = tolerance * tolerance
        while let (a, b) = stack.popLast() {
            var worst = -1, distance = limit
            var k = (a + 1) % n
            while k != b {
                let d = Lattice.nearest(to: ring[k], on: ring[a], ring[b]).distanceSquared
                if d > distance { worst = k; distance = d }
                k = (k + 1) % n
            }
            guard worst >= 0 else { continue }
            keep[worst] = true
            stack.append((a, worst))
            stack.append((worst, b))
        }
        return ring.indices.filter { keep[$0] }.map { ring[$0] }
    }

    /// Whether thinned rings are still simple, each of the sign of area it was, and apart.
    static func areSimpleAndApart(_ rings: [[LatticePoint]], like original: [[LatticePoint]]) -> Bool {
        for (ring, was) in zip(rings, original) {
            let area = Lattice.area2(ring)
            guard ring.count >= 3, area != 0, (area > 0) == (Lattice.area2(was) > 0), EditWork.isSimple(ring + [ring[0]])
            else { return false }
        }
        let boxes = rings.map { ring in
            ring.reduce((lo: ring[0], hi: ring[0])) { (pointwiseMin($0.lo, $1), pointwiseMax($0.hi, $1)) }
        }
        for a in rings.indices {
            for b in (a + 1)..<max(rings.count, a + 1) {
                guard boxes[a].lo.x <= boxes[b].hi.x, boxes[b].lo.x <= boxes[a].hi.x,
                      boxes[a].lo.y <= boxes[b].hi.y, boxes[b].lo.y <= boxes[a].hi.y else { continue }
                let p = rings[a], q = rings[b]
                for k in p.indices {
                    for l in q.indices
                    where Lattice.contact(p[k], p[(k + 1) % p.count], q[l], q[(l + 1) % q.count]) != .none { return false }
                }
            }
        }
        return true
    }
}

extension EditWork {
    /// Refine's Paint Brush: the stroke's footprint (`BrushFootprint`) becomes paint `color` (a
    /// color as on screen, OKLab: the paint within a just-noticeable difference, else a new one
    /// added last). Its outline is laid as a closed cell edge is, undrawn boundaries clipped to
    /// the canvas (`splitting`: no ink; a piece with no room for a number not cut off); each area
    /// inside it then takes the paint, ink between areas untouched, so pieces either side of a
    /// drawn line stay two cells. An area is inside when it lies on the footprint's side of the
    /// boundaries laid (the outline runs with the footprint on its left), or, touching none of
    /// them or both sides, when the footprint covers it whole. Areas of the brush's paint
    /// then meet across undrawn boundaries as one area (`mergeGroups`, the largest keeping its
    /// index), wherever one of them is inside or the boundary is the outline itself, so a stroke
    /// along a cell's edge grows the cell. A paint left with no area leaves the palette
    /// (`dropPaints`). An area with no room for the paint's number, even a detail area's, keeps its
    /// paint (`Outcome.tooSmall`), one again with the rest of the cell it was cut from. A stroke
    /// that paints no area its paint does not already have changes nothing; one with no area
    /// inside it, not even a whole cell, or none with room for the paint's number, is declined.
    mutating func brush(path: [LatticePoint], radius: Int64, color: SIMD3<Float>) throws {
        guard let footprint = BrushFootprint(path: path, radius: radius) else { return }
        let width = Int64(t.width) * Lattice.unit, height = Int64(t.height) * Lattice.unit
        guard footprint.high.x > 0, footprint.high.y > 0, footprint.low.x < width, footprint.low.y < height else { return }
        let saved = self
        let used = Set(t.regions.indices.filter { regionAlive[$0] }.map { t.regions[$0].colorIndex })

        splitting = true
        for ring in footprint.outline(width: width, height: height) {
            // Clipped from a vertex off the canvas, so every run ends on the frame.
            let start = ring.firstIndex { $0.x < 0 || $0.y < 0 || $0.x > width || $0.y > height } ?? 0
            let closed = Array(ring[start...]) + Array(ring[..<start]) + [ring[start]]
            for run in clip(closed) { try drawRun(run, nudging: true) }
        }

        var sides: [Int: (in: Int, out: Int)] = [:]
        for e in lineEdges where !edgeDead[e] {
            guard let r = right(e), r != left(e) else { continue }
            sides[left(e), default: (0, 0)].in += 1
            sides[r, default: (0, 0)].out += 1
        }
        var inside: [Int] = []
        for r in regionAlive.indices where regionAlive[r] {
            let s = sides[r] ?? (0, 0)
            switch (s.in > 0, s.out > 0) {
            case (true, false): inside.append(r)
            case (false, true): continue
            default:
                // Cut by no outline edge it lies wholly in: inside only when the footprint covers
                // it. A stroke too thin to cut a piece off, crossing a cell's number, paints
                // nothing there, not the whole cell.
                if polygons(of: r).allSatisfy({ $0.allSatisfy(footprint.contains) }) { inside.append(r) }
            }
        }
        guard !inside.isEmpty else { throw EditFailure.invalid("the brush's stroke has no room for a number there") }
        var nearest = -1, distance = Float.infinity
        for (k, c) in t.palette.enumerated() where ColorScience.distance(c.oklab, color) < distance {
            nearest = k
            distance = ColorScience.distance(c.oklab, color)
        }
        if distance <= SegmentationParameters.jnd, inside.allSatisfy({ Int(t.regions[$0].colorIndex) == nearest }) {
            self = saved
            return
        }

        let paint = UInt32(self.paint(matching: color))
        let within = Set(inside)
        var repainted: [Int] = []
        var before: [Int: UInt32] = [:]
        for r in inside where t.regions[r].colorIndex != paint {
            before[r] = t.regions[r].colorIndex
            t.regions[r].colorIndex = paint
            regionTouched[r] = true
            summary.touched.insert(r)
            summary.recolored += 1
            repainted.append(r)
        }
        let outline = Set(lineEdges)
        var groups = Groups()
        for e in t.edges.indices where !edgeDead[e] && !isInked(e) {
            guard let r = right(e) else { continue }
            let l = left(e)
            guard l != r, t.regions[l].colorIndex == paint, t.regions[r].colorIndex == paint,
                  within.contains(l) || within.contains(r) || outline.contains(e) else { continue }
            groups.join(l, r)
        }
        let joins = groups.groups().filter { $0.count > 1 }
        try mergeGroups(joins, surviving: [:])
        let grouped = Set(joins.flatMap { $0 })
        var kept = false
        for r in repainted where regionAlive[r] && !grouped.contains(r) {
            if let plan = labelPlan(
                rings: polygons(of: r), color: paint, detail: regionDetail[r], hints: hints(from: [r]), region: r,
                keepOut: freshInk[r] ?? []) {
                labels[r] = plan.labels
                regionDetail[r] = regionDetail[r] || plan.needsDetail
            } else {
                // No room for the new paint's digits, even a detail area's: the area keeps its paint.
                t.regions[r].colorIndex = before[r]!
                summary.recolored -= 1
                summary.declined.append(Self.centre(of: polygons(of: r)[0]))
                kept = true
            }
        }
        guard summary.recolored > 0 else { throw EditFailure.invalid("an area has no room for the number of its new paint") }
        if kept {
            // A piece that kept its paint is one area again with the rest of the cell it was cut from.
            var again = Groups()
            for e in lineEdges where !edgeDead[e] && !isInked(e) {
                guard let r = right(e), r != left(e), t.regions[left(e)].colorIndex == t.regions[r].colorIndex else { continue }
                again.join(left(e), r)
            }
            try mergeGroups(again.groups().filter { $0.count > 1 }, surviving: [:])
        }
        for r in Set(repainted).union(summary.pieces).sorted() where regionAlive[r] { refreshColorWeights(around: r) }
        try dropPaints(emptiedFrom: used)
    }
}
