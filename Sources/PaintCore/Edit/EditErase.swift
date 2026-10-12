import Foundation

/// The eraser's reach: everything within `radius` of a path (a stadium on each of its steps, a
/// disc for a dab), in canvas units.
struct Rub {
    let points: [SIMD2<Double>]
    let radius: Double
    private let low: SIMD2<Double>
    private let high: SIMD2<Double>

    init(path: [LatticePoint], radius: Double) {
        points = path.map(Lattice.double)
        self.radius = radius
        low = points.reduce(points[0]) { pointwiseMin($0, $1) } - radius
        high = points.reduce(points[0]) { pointwiseMax($0, $1) } + radius
    }

    func mayReach(low l: LatticePoint, high h: LatticePoint) -> Bool {
        let a = Lattice.double(l), b = Lattice.double(h)
        return b.x >= low.x && a.x <= high.x && b.y >= low.y && a.y <= high.y
    }

    /// The parameters `t` of the segment a→b (canvas units) within reach, as ranges in [0, 1]
    /// in order and apart. A stadium is convex, so the segment crosses each in one range.
    func covered(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> [ClosedRange<Double>] {
        guard max(a.x, b.x) >= low.x, min(a.x, b.x) <= high.x, max(a.y, b.y) >= low.y, min(a.y, b.y) <= high.y else { return [] }
        let d = b - a
        var ranges: [ClosedRange<Double>] = []
        func add(_ lo: Double, _ hi: Double) {
            let lo = max(lo, 0), hi = min(hi, 1)
            if lo < hi { ranges.append(lo...hi) }
        }
        func disc(_ c: SIMD2<Double>) -> (Double, Double)? {
            let l2 = simdDot(d, d)
            guard l2 > 0 else { return nil }
            let m = a - c
            let bq = simdDot(d, m), cq = simdDot(m, m) - radius * radius
            let det = bq * bq - l2 * cq
            guard det >= 0 else { return nil }
            let s = det.squareRoot()
            return ((-bq - s) / l2, (-bq + s) / l2)
        }
        /// t with lo ≤ c0 + c1·t ≤ hi.
        func linear(_ c0: Double, _ c1: Double, _ lo: Double, _ hi: Double) -> (Double, Double)? {
            if c1 == 0 { return c0 >= lo && c0 <= hi ? (-.infinity, .infinity) : nil }
            let x = (lo - c0) / c1, y = (hi - c0) / c1
            return (min(x, y), max(x, y))
        }
        for k in 0..<points.count {
            var found: [(Double, Double)] = []
            if let r = disc(points[k]) { found.append(r) }
            if k + 1 < points.count {
                if let r = disc(points[k + 1]) { found.append(r) }
                let q0 = points[k], e = points[k + 1] - q0
                let l2 = simdDot(e, e)
                if l2 > 0 {
                    let length = l2.squareRoot()
                    let m = a - q0
                    let along = linear(simdDot(m, e) / l2, simdDot(d, e) / l2, 0, 1)
                    let across = linear((e.x * m.y - e.y * m.x) / length, (e.x * d.y - e.y * d.x) / length, -radius, radius)
                    if let along, let across {
                        let lo = max(along.0, across.0), hi = min(along.1, across.1)
                        if lo <= hi { found.append((lo, hi)) }
                    }
                }
            }
            if let lo = found.map(\.0).min(), let hi = found.map(\.1).max() { add(lo, hi) }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for r in ranges {
            if let last = merged.last, r.lowerBound <= last.upperBound + 1e-12 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    /// `points` minus what the rub reaches: the stretches left, cut at the rub's edge (rounded
    /// to the lattice), and whether any stretch was taken out.
    func uncovered(_ points: [LatticePoint]) -> (pieces: [[LatticePoint]], broken: Bool) {
        let d = points.map(Lattice.double)
        typealias Position = (segment: Int, t: Double)
        var stretches: [(from: Position, to: Position)] = []
        for i in 0..<(points.count - 1) {
            for range in covered(d[i], d[i + 1]) {
                if let last = stretches.last, last.to.segment == i - 1, last.to.t >= 1 - 1e-12, range.lowerBound <= 1e-12 {
                    stretches[stretches.count - 1].to = (i, range.upperBound)
                } else {
                    stretches.append(((i, range.lowerBound), (i, range.upperBound)))
                }
            }
        }
        func at(_ p: Position) -> LatticePoint {
            if p.t <= 0 { return points[p.segment] }
            if p.t >= 1 { return points[p.segment + 1] }
            let a = points[p.segment], b = points[p.segment + 1]
            return LatticePoint(
                a.x + Int64((Double(b.x - a.x) * p.t).rounded()), a.y + Int64((Double(b.y - a.y) * p.t).rounded()))
        }
        var broken = false
        for s in stretches where s.from.segment != s.to.segment || at(s.from) != at(s.to) { broken = true }
        guard broken else { return ([points], false) }
        var pieces: [[LatticePoint]] = []
        func add(_ piece: [LatticePoint]) {
            var clean: [LatticePoint] = []
            for p in piece where p != clean.last { clean.append(p) }
            if clean.count >= 2 { pieces.append(clean) }
        }
        var start: [LatticePoint] = [points[0]]
        var nextVertex = 1
        for s in stretches {
            var piece = start
            if nextVertex <= s.from.segment { piece.append(contentsOf: points[nextVertex...s.from.segment]) }
            piece.append(at(s.from))
            add(piece)
            start = [at(s.to)]
            nextVertex = s.to.segment + 1
        }
        var tail = start
        if nextVertex < points.count { tail.append(contentsOf: points[nextVertex...]) }
        add(tail)
        // A loop whose start is uncovered has the stretch round it in two pieces: they are one.
        if points.first == points.last, pieces.count >= 2, let first = stretches.first, let last = stretches.last,
           !(first.from.segment == 0 && first.from.t <= 1e-12),
           !(last.to.segment == points.count - 2 && last.to.t >= 1 - 1e-12) {
            let joined = pieces[pieces.count - 1] + pieces[0].dropFirst()
            pieces.removeFirst()
            pieces[pieces.count - 1] = joined
        }
        return (pieces, true)
    }
}

extension EditWork {
    /// Regions that must become one, grouped.
    struct Groups {
        private var parent: [Int: Int] = [:]

        mutating func find(_ a: Int) -> Int {
            guard let p = parent[a] else {
                parent[a] = a
                return a
            }
            if p == a { return a }
            let root = find(p)
            parent[a] = root
            return root
        }

        mutating func join(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        mutating func groups() -> [[Int]] {
            var byRoot: [Int: [Int]] = [:]
            for key in parent.keys.sorted() { byRoot[find(key), default: []].append(key) }
            return byRoot.keys.sorted().map { byRoot[$0]! }
        }
    }

    /// Merges each group: the largest region of a group keeps its index and its paint.
    mutating func mergeGroups(_ groups: [[Int]], surviving: [Int: [[LatticePoint]]]) throws {
        for group in groups where group.count > 1 {
            let keep = group.max { a, b in
                let x = area(of: a), y = area(of: b)
                return x != y ? x < y : a > b
            }!
            try merge(group, keep: keep, color: t.regions[keep].colorIndex, detail: false, surviving: surviving)
        }
    }

    /// The eraser dragged along `path`: the ink it reaches is taken out, cut exactly at the edge
    /// of its reach. Ink between two regions that it breaks lets the paint through: the regions
    /// become one (the larger keeps its paint) and the ink of that boundary it left stays as
    /// strokes. Undrawn edges are never touched.
    mutating func erase(path: [LatticePoint], radius: Double) throws {
        guard !path.isEmpty else { return }
        let rub = Rub(path: path, radius: radius)
        var groups = Groups()
        var surviving: [Int: [[LatticePoint]]] = [:]
        for e in t.edges.indices where !edgeDead[e] && isInked(e) && !isFrame(e) {
            let b = box(of: e)
            guard rub.mayReach(low: b.lo, high: b.hi) else { continue }
            let cut = rub.uncovered(lattice(of: e))
            guard cut.broken else { continue }
            surviving[e] = cut.pieces
            groups.join(left(e), right(e)!)
        }
        var reached = 0
        for i in strokes.indices where strokes[i].alive && strokes[i].layer != LineLayer.color.rawValue {
            let cut = rub.uncovered(strokes[i].points.map(Lattice.point))
            guard cut.broken else { continue }
            let stroke = strokes[i]
            strokes[i].alive = false
            summary.touched.insert(stroke.region)
            reached += 1
            for piece in cut.pieces {
                strokes.append(WorkStroke(
                    points: piece.map(Lattice.position), layer: stroke.layer, weight: stroke.weight, region: stroke.region))
            }
        }
        try mergeGroups(groups.groups(), surviving: surviving)
        summary.erased += surviving.count + reached
    }

    /// The line under `p`, from junction to junction (`LineChains`): the drawn line nearest
    /// within `reach`, continued through every vertex where exactly one other drawn line ends.
    /// It is taken out whole, and the regions it kept apart become one as for `erase`.
    mutating func eraseLine(near p: LatticePoint, reach: Int64) throws {
        enum Line: Hashable { case edge(Int), stroke(Int) }
        var lines: [Line] = []
        var geometry: [[LatticePoint]] = []
        for e in t.edges.indices where !edgeDead[e] && isInked(e) && !isFrame(e) {
            lines.append(.edge(e))
            geometry.append(lattice(of: e))
        }
        for (i, s) in strokes.enumerated() where s.alive && s.layer != LineLayer.color.rawValue {
            let pts = Self.dedupe(s.points.map(Lattice.point))
            guard pts.count >= 2 else { continue }
            lines.append(.stroke(i))
            geometry.append(pts)
        }
        var nearest: (index: Int, d2: Int64)?
        for (k, pts) in geometry.enumerated() {
            for j in 0..<(pts.count - 1) {
                let d2 = Lattice.nearest(to: p, on: pts[j], pts[j + 1]).distanceSquared
                if d2 <= reach * reach, nearest == nil || d2 < nearest!.d2 { nearest = (k, d2) }
            }
        }
        guard let start = nearest?.index else { return }
        var ends: [LatticePoint: [(line: Int, atStart: Bool)]] = [:]
        for (k, pts) in geometry.enumerated() {
            ends[pts[0], default: []].append((k, true))
            ends[pts[pts.count - 1], default: []].append((k, false))
        }
        var chain: Set<Int> = [start]
        var closed = false
        for forward in [true, false] where !closed {
            var current = start
            var atEnd = forward
            while true {
                let pts = geometry[current]
                guard let here = ends[atEnd ? pts[pts.count - 1] : pts[0]], here.count == 2,
                      let next = here.first(where: { !($0.line == current && $0.atStart == !atEnd) })
                else { break }
                if next.line == start {
                    closed = true
                    break
                }
                guard chain.insert(next.line).inserted else { break }
                current = next.line
                atEnd = next.atStart
            }
        }
        var groups = Groups()
        var surviving: [Int: [[LatticePoint]]] = [:]
        for k in chain.sorted() {
            switch lines[k] {
            case .edge(let e):
                surviving[e] = []
                groups.join(left(e), right(e)!)
            case .stroke(let i):
                strokes[i].alive = false
                summary.touched.insert(strokes[i].region)
            }
        }
        try mergeGroups(groups.groups(), surviving: surviving)
        summary.erased += chain.count
    }
}
