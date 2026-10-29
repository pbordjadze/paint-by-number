import Foundation

extension EditWork {
    /// A line the painter drew, as the polyline it is (`TemplateEditor.Edit.draw`). Parts off the
    /// canvas are cut away; the rest is laid on the template as drawn, in `drawRun`, `nudging` it
    /// through the junctions it passes close by (`throughJunctions`).
    mutating func draw(_ input: [SIMD2<Float>], closed: Bool, nudging: Bool = false) throws {
        var points: [LatticePoint] = []
        for p in input.prefix(TemplateEditor.maximumPoints) where p.x.isFinite && p.y.isFinite {
            let q = Lattice.clampedPoint(p)
            if q != points.last { points.append(q) }
        }
        if closed, points.count >= 3, points.first != points.last { points.append(points[0]) }
        guard points.count >= 2 else { return }
        for run in clip(points) { try drawRun(run, nudging: nudging) }
    }

    // MARK: - The canvas

    /// The parts of `points` inside the canvas, each a polyline; ends cut at the frame lie on it.
    func clip(_ points: [LatticePoint]) -> [[LatticePoint]] {
        let lo = LatticePoint(0, 0), hi = LatticePoint(Int64(t.width) * Lattice.unit, Int64(t.height) * Lattice.unit)
        var runs: [[LatticePoint]] = []
        var current: [LatticePoint] = []
        func flush() {
            if current.count >= 2 { runs.append(current) }
            current = []
        }
        for (a, b) in zip(points, points.dropFirst()) {
            guard let (c0, c1) = Self.clip(a, b, lo, hi) else { flush(); continue }
            if current.last != c0 {
                flush()
                current = [c0]
            }
            if c1 != current.last { current.append(c1) }
            if c1 != b { flush() }
        }
        flush()
        return runs
    }

    /// Segment ab cut to the rectangle: where it enters and leaves, on the frame exactly.
    static func clip(_ a: LatticePoint, _ b: LatticePoint, _ lo: LatticePoint, _ hi: LatticePoint) -> (LatticePoint, LatticePoint)? {
        let d = b &- a
        let dx = Double(d.x), dy = Double(d.y)
        var t0 = 0.0, t1 = 1.0
        var enter = -1, leave = -1
        let sides: [(p: Double, q: Double)] = [
            (-dx, Double(a.x - lo.x)), (dx, Double(hi.x - a.x)), (-dy, Double(a.y - lo.y)), (dy, Double(hi.y - a.y)),
        ]
        for (side, c) in sides.enumerated() {
            if c.p == 0 {
                if c.q < 0 { return nil }
                continue
            }
            let r = c.q / c.p
            if c.p < 0 {
                if r > t1 { return nil }
                if r > t0 { t0 = r; enter = side }
            } else {
                if r < t0 { return nil }
                if r < t1 { t1 = r; leave = side }
            }
        }
        guard t0 <= t1 else { return nil }
        func at(_ side: Int) -> LatticePoint {
            var p: LatticePoint
            switch side {
            case 0: p = LatticePoint(lo.x, a.y + Lattice.mulDiv(d.y, lo.x - a.x, d.x))
            case 1: p = LatticePoint(hi.x, a.y + Lattice.mulDiv(d.y, hi.x - a.x, d.x))
            case 2: p = LatticePoint(a.x + Lattice.mulDiv(d.x, lo.y - a.y, d.y), lo.y)
            default: p = LatticePoint(a.x + Lattice.mulDiv(d.x, hi.y - a.y, d.y), hi.y)
            }
            p = pointwiseMin(pointwiseMax(p, lo), hi)
            return p
        }
        return (enter >= 0 && t0 > 0 ? at(enter) : a, leave >= 0 && t1 < 1 ? at(leave) : b)
    }

    // MARK: - Joining ink

    /// Where a line's end goes: the nearest ink within reach, otherwise where it was drawn.
    /// A line meets the ink as it lies, the end moved onto it (the nearest vertex when one is
    /// within `TemplateEditor.vertexSnap`, else the nearest point), the canvas frame always
    /// counting as ink.
    mutating func joinPoint(near p: LatticePoint) -> LatticePoint {
        let reachSquared = TemplateEditor.reach * TemplateEditor.reach
        var best: (point: LatticePoint, d2: Int64, edge: Int?, stroke: Int?, segment: Int)?
        func offer(_ hit: (point: LatticePoint, distanceSquared: Int64), edge: Int?, stroke: Int?, segment: Int) {
            if hit.distanceSquared <= reachSquared, best == nil || hit.distanceSquared < best!.d2 {
                best = (hit.point, hit.distanceSquared, edge, stroke, segment)
            }
        }
        let reach = TemplateEditor.reach
        for e in t.edges.indices where !edgeDead[e] && (isFrame(e) || isInked(e) || splitting) {
            let b = box(of: e)
            guard p.x >= b.lo.x - reach, p.x <= b.hi.x + reach, p.y >= b.lo.y - reach, p.y <= b.hi.y + reach else { continue }
            let pts = lattice(of: e)
            for j in 0..<(pts.count - 1) { offer(Lattice.nearest(to: p, on: pts[j], pts[j + 1]), edge: e, stroke: nil, segment: j) }
        }
        for (i, stroke) in strokes.enumerated() where stroke.joinsLines && !splitting {
            let pts = stroke.points.map(Lattice.point)
            for j in 0..<(pts.count - 1) { offer(Lattice.nearest(to: p, on: pts[j], pts[j + 1]), edge: nil, stroke: i, segment: j) }
        }
        guard let best else { return p }
        let a: LatticePoint, b: LatticePoint
        if let e = best.edge {
            a = latticePoint(e, best.segment)
            b = latticePoint(e, best.segment + 1)
        } else {
            a = Lattice.point(strokes[best.stroke!].points[best.segment])
            b = Lattice.point(strokes[best.stroke!].points[best.segment + 1])
        }
        var target = best.point
        let snap = TemplateEditor.vertexSnap * TemplateEditor.vertexSnap
        let da = Lattice.distanceSquared(a, target), db = Lattice.distanceSquared(b, target)
        if min(da, db) <= snap { target = da <= db ? a : b }
        // The ink passes through the point from now on: a point off it (the lattice has no point
        // on most segments) is made a vertex, nudging the line by under a lattice step.
        if target != a, target != b, Lattice.orient(a, b, target) != 0 {
            if let e = best.edge {
                insertVertex(edge: e, segment: best.segment, target)
            } else {
                strokes[best.stroke!].points.insert(Lattice.position(target), at: best.segment + 1)
            }
        }
        summary.joins += 1
        return target
    }

    // MARK: - Laying a line

    static func dedupe(_ points: [LatticePoint]) -> [LatticePoint] {
        var out: [LatticePoint] = []
        for p in points where p != out.last { out.append(p) }
        return out
    }

    /// A polyline that meets itself only where consecutive segments share an end.
    static func isSimple(_ points: [LatticePoint]) -> Bool {
        let n = points.count - 1
        guard n >= 1 else { return false }
        let closed = points.first == points.last
        for i in 0..<n {
            for j in (i + 1)..<max(n, i + 1) {
                let adjacent = j == i + 1 || (closed && i == 0 && j == n - 1)
                let c = Lattice.contact(points[i], points[i + 1], points[j], points[j + 1])
                switch c {
                case .none: continue
                case .touch: if !adjacent { return false }
                case .cross, .overlap: return false
                }
            }
        }
        return true
    }

    struct Contact {
        var edge: Int
        var segment: Int
        var mine: Int
        var contact: Lattice.Contact
    }

    /// Every contact of `poly` with the alive edges.
    mutating func contacts(of poly: [LatticePoint]) -> [Contact] {
        var lo = LatticePoint(repeating: .max), hi = LatticePoint(repeating: .min)
        for p in poly { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
        var out: [Contact] = []
        for e in t.edges.indices where !edgeDead[e] {
            let b = box(of: e)
            guard b.lo.x <= hi.x, b.hi.x >= lo.x, b.lo.y <= hi.y, b.hi.y >= lo.y else { continue }
            let pts = lattice(of: e)
            for j in 0..<(pts.count - 1) {
                let a0 = pts[j], a1 = pts[j + 1]
                guard max(a0.x, a1.x) >= lo.x, min(a0.x, a1.x) <= hi.x, max(a0.y, a1.y) >= lo.y, min(a0.y, a1.y) <= hi.y else { continue }
                for k in 0..<(poly.count - 1) {
                    let c = Lattice.contact(poly[k], poly[k + 1], a0, a1)
                    if c != .none { out.append(Contact(edge: e, segment: j, mine: k, contact: c)) }
                }
            }
        }
        return out
    }

    /// Lays one polyline, wholly on the canvas, on the template. Its ends meet the ink they are
    /// near; it is cut where it meets the drawing (the edges, itself, and the strokes it touches,
    /// `node`; never writing, `WorkStroke.joinsLines`) into chains; each chain, with the outline of
    /// the region it lies in, either closes off part of the region (`splitRegion`) or is a stroke.
    mutating func drawRun(_ input: [LatticePoint], nudging: Bool = false) throws {
        var run = Self.dedupe(input)
        guard run.count >= 2 else { return }
        if !(run.count >= 4 && run.first == run.last) {
            let reach = TemplateEditor.reach
            var length = 0.0
            for (a, b) in zip(run, run.dropFirst()) { length += Double(Lattice.distanceSquared(a, b)).squareRoot() }
            if run.count >= 4, Lattice.distanceSquared(run[0], run[run.count - 1]) <= reach * reach, length > 4 * Double(reach) {
                // An end that lands on the other closes the line into a loop.
                run[run.count - 1] = run[0]
            } else {
                run[0] = joinPoint(near: run[0])
                run[run.count - 1] = joinPoint(near: run[run.count - 1])
            }
        }
        run = Self.dedupe(run)
        guard run.count >= 2, Set(run).count >= 2 else { return }
        if nudging { run = throughJunctions(run) }

        // The strokes the line might meet: simple ones near it that stay clear of every outline.
        var lo = LatticePoint(repeating: .max), hi = LatticePoint(repeating: .min)
        for p in run { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
        var candidates: [(index: Int, points: [LatticePoint])] = []
        // A split divides paint, not ink: the drawing's strokes are no part of it.
        for (i, stroke) in strokes.enumerated() where stroke.joinsLines && !splitting {
            let pts = Self.dedupe(stroke.points.map(Lattice.point))
            guard pts.count >= 2 else { continue }
            var slo = LatticePoint(repeating: .max), shi = LatticePoint(repeating: .min)
            for p in pts { slo = pointwiseMin(slo, p); shi = pointwiseMax(shi, p) }
            guard slo.x <= hi.x, shi.x >= lo.x, slo.y <= hi.y, shi.y >= lo.y, Self.isSimple(pts) else { continue }
            let crossesOutline = contacts(of: pts).contains { c in
                switch c.contact {
                case .cross, .overlap: return true
                default: return false
                }
            }
            if !crossesOutline { candidates.append((i, pts)) }
        }
        func meet(_ a: [LatticePoint], _ b: [LatticePoint]) -> Bool {
            for k in 0..<(a.count - 1) {
                for l in 0..<(b.count - 1) where Lattice.contact(a[k], a[k + 1], b[l], b[l + 1]) != .none { return true }
            }
            return false
        }
        // Those it touches, and those touching them, are part of the drawing's graph.
        var graph = Set(candidates.indices.filter { meet(run, candidates[$0].points) })
        var frontier = graph.sorted()
        while let a = frontier.popLast() {
            for b in candidates.indices where !graph.contains(b) && meet(candidates[a].points, candidates[b].points) {
                graph.insert(b)
                frontier.append(b)
            }
        }
        let members = graph.sorted()

        var lines = [NodedLine(points: run)] + members.map { NodedLine(points: candidates[$0].points) }
        try node(&lines)

        // The line and the strokes of the graph, cut at the points they meet the drawing.
        struct Chain {
            var points: [LatticePoint]
            var layer: UInt8
            var weight: UInt8
            var region: Int?
            var fresh: Bool
        }
        var all: [Chain] = []
        for points in Self.chains(of: lines[0].points, nodes: lines[0].nodes) {
            all.append(Chain(
                points: points, layer: splitting ? LineLayer.color.rawValue : LineLayer.outline.rawValue, weight: splitting ? 0 : 255,
                region: nil, fresh: true))
        }
        for (k, a) in members.enumerated() {
            let stroke = strokes[candidates[a].index]
            strokes[candidates[a].index].alive = false
            for points in Self.chains(of: lines[k + 1].points, nodes: lines[k + 1].nodes) {
                all.append(Chain(points: points, layer: stroke.layer, weight: stroke.weight, region: stroke.region, fresh: false))
            }
        }

        // Where two chains are the same line (or one is an edge already), it is there once.
        struct Key: Hashable {
            var points: [LatticePoint]
            init(_ p: [LatticePoint]) { points = p.reversed().lexicographicallyPrecedes(p, by: Lattice.lexicographicallyBefore) ? p.reversed() : p }
        }
        var chosen: [Key: Int] = [:]
        var dropped = Set<Int>()
        for (i, c) in all.enumerated() {
            let key = Key(c.points)
            if let j = chosen[key] {
                if all[j].fresh && !c.fresh {
                    dropped.insert(j)
                    chosen[key] = i
                } else {
                    dropped.insert(i)
                }
            } else {
                chosen[key] = i
            }
        }
        let ends = Set(all.flatMap { [$0.points[0], $0.points[$0.points.count - 1]] })
        for e in t.edges.indices where !edgeDead[e] {
            let n = Int(t.edges[e].pointCount)
            guard ends.contains(latticePoint(e, 0)), ends.contains(latticePoint(e, n - 1)),
                  let i = chosen[Key(lattice(of: e))], !dropped.contains(i) else { continue }
            dropped.insert(i)
            if !isInked(e) {
                layers[e] = all[i].layer
                weights[e] = all[i].weight
            }
        }
        all = all.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)

        for c in all.indices where all[c].region == nil {
            let p = all[c].points
            guard let r = locate(p[0] &+ p[1], scale: 2) else { throw EditFailure.degenerate("a line lies outside every region") }
            all[c].region = r
        }
        var byRegion: [Int: [Int]] = [:]
        var fresh = Set<Int>()
        for chain in all {
            let e = addEdge(
                left: chain.region!, right: chain.region!, points: chain.points, layer: chain.layer, weight: chain.weight)
            byRegion[chain.region!, default: []].append(e)
            if chain.fresh {
                fresh.insert(e)
                lineEdges.append(e)
            }
        }
        for r in byRegion.keys.sorted() { try splitRegion(r, chains: byRegion[r]!, fresh: fresh) }
        summary.lines += 1
    }

    /// `run` passing through each junction (an end of an edge) within `TemplateEditor.reach` (the
    /// width of ink) of a point where it crosses that edge: the junction becomes a vertex of the
    /// line in its place. Otherwise the line clips the corner there, and the sliver it closes off
    /// has no room for even a detail area's number (a right angle cut 2 units from its tip leaves
    /// about 0.8 of room, against a floor of about 1): it stays uncut, the shape's line beside it
    /// only a stroke there. The line moves by under the ink's width, as an end joining ink does
    /// (`joinPoint`); the drawing's lines never move. A nudge that would make the line double
    /// back on itself is not made.
    mutating func throughJunctions(_ run: [LatticePoint]) -> [LatticePoint] {
        let reachSquared = TemplateEditor.reach * TemplateEditor.reach
        var inserts: [(segment: Int, point: LatticePoint)] = []
        for c in contacts(of: run) {
            guard case .cross(let p) = c.contact else { continue }
            let n = Int(t.edges[c.edge].pointCount)
            var best: (point: LatticePoint, d2: Int64)?
            for j in [latticePoint(c.edge, 0), latticePoint(c.edge, n - 1)] {
                let d2 = Lattice.distanceSquared(j, p)
                if d2 <= reachSquared, best == nil || d2 < best!.d2 || (d2 == best!.d2 && Lattice.lexicographicallyBefore(j, best!.point)) {
                    best = (j, d2)
                }
            }
            if let best { inserts.append((c.mine, best.point)) }
        }
        guard !inserts.isEmpty else { return run }
        let nudged = Self.dedupe(Self.inserting(inserts, into: run))
        guard nudged.count >= 2 else { return run }
        for i in 0..<(nudged.count - 1) {
            for j in (i + 1)..<(nudged.count - 1) {
                if case .overlap = Lattice.contact(nudged[i], nudged[i + 1], nudged[j], nudged[j + 1]) { return run }
            }
        }
        return nudged
    }

    /// `points` cut into chains at the vertices in `nodes`: a loop is cut at its first node,
    /// or is one chain when it has none.
    static func chains(of points: [LatticePoint], nodes: Set<LatticePoint>) -> [[LatticePoint]] {
        var sequence = points
        if points.first == points.last, points.count >= 3 {
            let body = Array(points.dropLast())
            guard let first = body.firstIndex(where: { nodes.contains($0) }) else { return [points] }
            sequence = Array(body[first...]) + Array(body[..<first]) + [body[first]]
        }
        var out: [[LatticePoint]] = []
        var current: [LatticePoint] = [sequence[0]]
        for p in sequence.dropFirst() {
            current.append(p)
            if nodes.contains(p) {
                out.append(current)
                current = [p]
            }
        }
        if current.count >= 2 { out.append(current) }
        return out
    }
}

/// A polyline being brought to meet the drawing, with the vertices where it meets it.
struct NodedLine {
    var points: [LatticePoint]
    var nodes: Set<LatticePoint> = []
}

extension EditWork {
    /// Cuts `lines` and the edges at every point where they meet, so that afterwards they meet
    /// only at vertices both have: a crossing is a point nearest the true one on the lattice, a
    /// vertex on a line one that line passes through. Inserting such a point moves a line off its
    /// path by under a lattice step, which can make it meet another line elsewhere (two lines
    /// close and nearly parallel): the lines are checked again, until they meet only at vertices.
    /// Lines that lay along one another for a stretch are given vertices at its ends.
    mutating func node(_ lines: inout [NodedLine]) throws {
        for _ in 0..<8 {
            var inserts = [[(segment: Int, point: LatticePoint)]](repeating: [], count: lines.count)
            var edgeInserts: [Int: [(segment: Int, point: LatticePoint)]] = [:]
            var grew = false
            func mark(_ i: Int, _ segment: Int, _ p: LatticePoint) {
                lines[i].nodes.insert(p)
                if p != lines[i].points[segment], p != lines[i].points[segment + 1] {
                    inserts[i].append((segment, p))
                    grew = true
                }
            }
            for a in lines.indices {
                for b in a..<lines.count {
                    let pa = lines[a].points, pb = lines[b].points
                    let closed = pa.first == pa.last
                    for k in 0..<(pa.count - 1) {
                        for l in (a == b ? k + 1 : 0)..<max(pb.count - 1, a == b ? k + 1 : 0) {
                            let c = Lattice.contact(pa[k], pa[k + 1], pb[l], pb[l + 1])
                            if a == b, l == k + 1 || (closed && k == 0 && l == pa.count - 2) {
                                if case .overlap = c { throw EditFailure.degenerate(TemplateEditor.lineDoublesBack) }
                                continue
                            }
                            switch c {
                            case .none: continue
                            case .cross(let p):
                                let q = snapped(p, to: [pa[k], pa[k + 1], pb[l], pb[l + 1]])
                                mark(a, k, q)
                                mark(b, l, q)
                            case .touch(let p):
                                mark(a, k, p)
                                mark(b, l, p)
                            case .overlap(let p, let q):
                                for point in [p, q] {
                                    mark(a, k, point)
                                    mark(b, l, point)
                                }
                            }
                        }
                    }
                }
            }
            for i in lines.indices {
                for c in contacts(of: lines[i].points) {
                    var found: [LatticePoint] = []
                    switch c.contact {
                    case .none: continue
                    case .cross(let p):
                        found = [snapped(p, to: [
                            lines[i].points[c.mine], lines[i].points[c.mine + 1], latticePoint(c.edge, c.segment),
                            latticePoint(c.edge, c.segment + 1),
                        ])]
                    case .touch(let p): found = [p]
                    case .overlap(let p, let q): found = [p, q]
                    }
                    let last = Int(t.edges[c.edge].pointCount) - 1
                    for p in found {
                        mark(i, c.mine, p)
                        if p != latticePoint(c.edge, 0), p != latticePoint(c.edge, last) {
                            edgeInserts[c.edge, default: []].append((c.segment, p))
                            grew = true
                        }
                    }
                }
            }
            guard grew else { return }
            for i in lines.indices where !inserts[i].isEmpty { lines[i].points = Self.inserting(inserts[i], into: lines[i].points) }
            for e in edgeInserts.keys.sorted() { split(edge: e, at: edgeInserts[e]!) }
        }
        throw EditFailure.collision("the lines meet too closely")
    }

    /// A crossing within `snapRadius` lattice steps of an end of either segment is that end: two
    /// lines that meet there would otherwise leave a stub a step long, which two edges meeting at
    /// the end would both pass through, one on the other. A stub is a problem as long as the
    /// edges at its end are closer than a step apart there, so the radius grows (up to a few
    /// hundredths of a unit) when an edit meets lines too close to be told apart.
    func snapped(_ p: LatticePoint, to ends: [LatticePoint]) -> LatticePoint {
        var best = p
        var distance = Int64.max
        for e in ends where abs(e.x - p.x) <= snapRadius && abs(e.y - p.y) <= snapRadius {
            let d = Lattice.distanceSquared(e, p)
            if d < distance || (d == distance && Lattice.lexicographicallyBefore(e, best)) {
                best = e
                distance = d
            }
        }
        return best
    }

    /// `points` with each insert's point made a vertex, on the segment it is given for.
    static func inserting(_ inserts: [(segment: Int, point: LatticePoint)], into points: [LatticePoint]) -> [LatticePoint] {
        let ordered = inserts.sorted { a, b in
            if a.segment != b.segment { return a.segment < b.segment }
            let d = points[a.segment + 1] &- points[a.segment]
            return Lattice.dot(a.point &- points[a.segment], d) < Lattice.dot(b.point &- points[b.segment], d)
        }
        var out: [LatticePoint] = []
        var next = 0
        for i in 0..<(points.count - 1) {
            out.append(points[i])
            while next < ordered.count && ordered[next].segment == i {
                let p = ordered[next].point
                next += 1
                if p != out[out.count - 1], p != points[i + 1] { out.append(p) }
            }
        }
        out.append(points[points.count - 1])
        return out
    }
}
