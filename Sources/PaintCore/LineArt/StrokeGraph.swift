import Foundation

/// One-pixel line mask → clean strokes (the vector half of line extraction).
///
/// The mask is traced into a graph: nodes are line ends and junction clusters, edges the
/// pixel chains between them (loops without a node are closed edges). Then bubbles of the
/// thinning are popped (two short edges between the same nodes), spurs pruned (a short end
/// hanging off a junction), specks dropped, gaps bridged (a free end continues along its
/// tangent to another end facing back, or onto a line), components shorter than the minimum
/// stroke length dropped, and free ends heading into the frame continued to it (a contour
/// leaving the picture seals against the canvas edge). Finally edges are joined through
/// junctions into strokes (the best-aligned branches continue each other) and smoothed
/// along their length with the ends pinned, so strokes keep meeting at junctions.
///
/// Coordinates are pixel coordinates (pixel centres at integers). Every point carries the
/// edge strength under it; bridged points interpolate their ends'.
struct StrokeGraph {
    struct Edge {
        var points: [SIMD2<Float>]
        var strength: [Float]
        /// End nodes; both -1 for a closed edge.
        var a: Int
        var b: Int
        var alive = true
        var closed: Bool { a < 0 }
    }

    var nodes: [SIMD2<Float>] = []
    var incidence: [[(edge: Int, end: Int)]] = []
    var nodeAlive: [Bool] = []
    var edges: [Edge] = []
    /// Nodes on the canvas frame (ends there are attached, not free).
    var frameNodes = Set<Int>()

    static let offsets: [(dy: Int, dx: Int)] = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    @discardableResult
    mutating func addNode(_ p: SIMD2<Float>) -> Int {
        nodes.append(p)
        incidence.append([])
        nodeAlive.append(true)
        return nodes.count - 1
    }

    @discardableResult
    mutating func addEdge(_ points: [SIMD2<Float>], _ strength: [Float], _ a: Int, _ b: Int) -> Int {
        let id = edges.count
        edges.append(Edge(points: points, strength: strength, a: a, b: b))
        if a >= 0 {
            incidence[a].append((id, 0))
            incidence[b].append((id, 1))
        }
        return id
    }

    @discardableResult
    mutating func removeEdge(_ id: Int) -> Edge {
        let e = edges[id]
        edges[id].alive = false
        if e.a >= 0 {
            incidence[e.a].removeAll { $0.edge == id }
            incidence[e.b].removeAll { $0.edge == id }
        }
        return e
    }

    mutating func removeNodeIfIsolated(_ n: Int) {
        if n >= 0 && nodeAlive[n] && incidence[n].isEmpty { nodeAlive[n] = false }
    }

    func degree(_ n: Int) -> Int { incidence[n].count }

    /// Points of edge `id` starting at its end `end` (0: `points[0]`, 1: the last point).
    func oriented(_ id: Int, from end: Int) -> [SIMD2<Float>] {
        end == 0 ? edges[id].points : edges[id].points.reversed()
    }

    func orientedStrength(_ id: Int, from end: Int) -> [Float] {
        end == 0 ? edges[id].strength : edges[id].strength.reversed()
    }

    // MARK: - Tracing

    /// Traces a one-pixel mask (border pixels unset) into a graph.
    static func trace(_ mask: [Bool], strength: [Float], width w: Int, height h: Int) -> StrokeGraph {
        var g = StrokeGraph()
        let n = w * h
        var degree = [UInt8](repeating: 0, count: n)
        var isNode = [Bool](repeating: false, count: n)
        var on = mask
        for i in 0..<n where on[i] {
            let y = i / w, x = i - y * w
            guard x > 0 && y > 0 && x < w - 1 && y < h - 1 else { on[i] = false; continue }
            var d: UInt8 = 0
            for o in offsets where mask[i + o.dy * w + o.dx] { d += 1 }
            degree[i] = d
        }
        for i in 0..<n where on[i] {
            if degree[i] == 0 { on[i] = false } else if degree[i] != 2 { isNode[i] = true }
        }
        // Junction clusters: 8-connected node pixels form one node at their centroid.
        var cluster = [Int32](repeating: -1, count: n)
        var stack: [Int] = []
        for i in 0..<n where isNode[i] && cluster[i] < 0 {
            let id = Int32(g.nodes.count)
            var sum = SIMD2<Float>(0, 0)
            var count: Float = 0
            cluster[i] = id
            stack.append(i)
            while let p = stack.popLast() {
                let py = p / w, px = p - py * w
                sum += SIMD2(Float(px), Float(py))
                count += 1
                for o in offsets {
                    let q = p + o.dy * w + o.dx
                    if isNode[q] && cluster[q] < 0 { cluster[q] = id; stack.append(q) }
                }
            }
            g.addNode(sum / count)
        }
        @inline(__always) func xy(_ i: Int) -> SIMD2<Float> { SIMD2(Float(i % w), Float(i / w)) }
        var visited = [Bool](repeating: false, count: n)
        for p in 0..<n where isNode[p] {
            for o in offsets {
                let q = p + o.dy * w + o.dx
                guard on[q] && !isNode[q] && !visited[q] else { continue }
                var path = [p, q]
                var prev = p, cur = q
                while !isNode[cur] {
                    visited[cur] = true
                    var next = -1
                    for o2 in offsets {
                        let r = cur + o2.dy * w + o2.dx
                        if on[r] && r != prev && !(visited[r] && !isNode[r]) { next = r; break }
                    }
                    if next < 0 { break }
                    prev = cur
                    cur = next
                    path.append(cur)
                }
                guard isNode[cur] else { continue }
                let a = Int(cluster[p]), b = Int(cluster[cur])
                var points = path.map(xy)
                points[0] = g.nodes[a]
                points[points.count - 1] = g.nodes[b]
                g.addEdge(points, path.map { strength[$0] }, a, b)
            }
        }
        // Loops without any node.
        for s in 0..<n where on[s] && !isNode[s] && !visited[s] {
            var path = [s]
            visited[s] = true
            var prev = -1, cur = s
            while true {
                var next = -1
                for o in offsets {
                    let r = cur + o.dy * w + o.dx
                    if on[r] && r != prev && !visited[r] { next = r; break }
                }
                if next < 0 { break }
                visited[next] = true
                path.append(next)
                prev = cur
                cur = next
            }
            if path.count >= 3 { g.addEdge(path.map(xy), path.map { strength[$0] }, -1, -1) }
        }
        return g
    }

    // MARK: - Cleanup

    mutating func mergeDegree2() {
        var changed = true
        while changed {
            changed = false
            for n in 0..<nodes.count where nodeAlive[n] && degree(n) == 2 {
                let (e1, end1) = incidence[n][0], (e2, end2) = incidence[n][1]
                if e1 == e2 {
                    // A loop hanging on n alone becomes a closed edge.
                    let e = removeEdge(e1)
                    addEdge(Array(e.points.dropLast()), Array(e.strength.dropLast()), -1, -1)
                    removeNodeIfIsolated(n)
                    changed = true
                    continue
                }
                let p1 = oriented(e1, from: 1 - end1), s1 = orientedStrength(e1, from: 1 - end1)  // ends at n
                let p2 = oriented(e2, from: end2), s2 = orientedStrength(e2, from: end2)  // starts at n
                let o1 = end1 == 1 ? edges[e1].a : edges[e1].b
                let o2 = end2 == 0 ? edges[e2].b : edges[e2].a
                removeEdge(e1)
                removeEdge(e2)
                removeNodeIfIsolated(n)
                addEdge(p1 + p2.dropFirst(), s1 + s2.dropFirst(), o1, o2)
                changed = true
            }
        }
    }

    static func length(_ p: [SIMD2<Float>], closed: Bool = false) -> Float {
        guard p.count > 1 else { return 0 }
        var total: Float = 0
        for i in 1..<p.count { total += simdLength(p[i] - p[i - 1]) }
        if closed { total += simdLength(p[0] - p[p.count - 1]) }
        return total
    }

    func length(_ id: Int) -> Float { Self.length(edges[id].points, closed: edges[id].closed) }

    /// Two short edges between the same two nodes enclose a knot of the thinning, not a shape:
    /// the longer one goes.
    mutating func popBubbles(perimeter: Float) {
        var changed = true
        while changed {
            changed = false
            var byPair: [SIMD2<Int32>: [Int]] = [:]
            var pairs: [SIMD2<Int32>] = []
            for (i, e) in edges.enumerated() where e.alive && e.a >= 0 && e.a != e.b {
                let key = SIMD2(Int32(min(e.a, e.b)), Int32(max(e.a, e.b)))
                if byPair[key] == nil { pairs.append(key) }
                byPair[key, default: []].append(i)
            }
            pairs.sort { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
            for key in pairs {
                guard let ids = byPair[key], ids.count >= 2 else { continue }
                let lens = ids.map { (length($0), $0) }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
                if lens[0].0 + lens[1].0 < perimeter {
                    removeEdge(lens[1].1)
                    changed = true
                }
            }
            if changed { mergeDegree2() }
        }
    }

    /// Short ends hanging off a junction (and small loops hanging on one) go.
    mutating func pruneSpurs(_ spur: Float, rounds: Int = 2) {
        for _ in 0..<rounds {
            var removed = false
            for i in 0..<edges.count where edges[i].alive {
                let e = edges[i]
                guard e.a >= 0 else { continue }
                if e.a == e.b {
                    if length(i) < 2 * spur {
                        removeEdge(i)
                        removeNodeIfIsolated(e.a)
                        removed = true
                    }
                    continue
                }
                let da = degree(e.a), db = degree(e.b)
                if ((da == 1 && db >= 3) || (db == 1 && da >= 3)) && length(i) < spur {
                    removeEdge(i)
                    removeNodeIfIsolated(e.a)
                    removeNodeIfIsolated(e.b)
                    removed = true
                }
            }
            mergeDegree2()
            if !removed { break }
        }
    }

    /// Connected components as lists of edge ids (a closed edge is its own component).
    func components() -> [[Int]] {
        var sets = DisjointSet(count: nodes.count)
        for e in edges where e.alive && e.a >= 0 {
            let ra = sets.find(e.a), rb = sets.find(e.b)
            if ra != rb { sets.parent[max(ra, rb)] = min(ra, rb) }
        }
        var keyOrder: [Int] = []
        var byKey: [Int: [Int]] = [:]
        for (i, e) in edges.enumerated() where e.alive {
            // Closed edges get keys past every node.
            let key = e.a >= 0 ? sets.find(e.a) : nodes.count + i
            if byKey[key] == nil { keyOrder.append(key) }
            byKey[key, default: []].append(i)
        }
        return keyOrder.map { byKey[$0]! }
    }

    /// Drops components shorter than `minimum` (canvas units of line).
    mutating func pruneFragments(_ minimum: Float) {
        for comp in components() {
            let total = comp.reduce(Float(0)) { $0 + length($1) }
            guard total < minimum else { continue }
            for i in comp {
                let e = removeEdge(i)
                removeNodeIfIsolated(e.a)
                removeNodeIfIsolated(e.b)
            }
        }
    }

    /// Unit direction pointing out of a polyline at `points[0]`, from the stretch within `reach`.
    static func endTangent(_ points: [SIMD2<Float>], reach: Float = 8) -> SIMD2<Float> {
        var acc: Float = 0
        var k = 1
        while k < points.count - 1 && acc < reach {
            acc += simdLength(points[k] - points[k - 1])
            k += 1
        }
        let v = points[0] - points[min(k, points.count - 1)]
        let n = simdLength(v)
        return n > 1e-9 ? v / n : .zero
    }

    /// Bridges gaps: from each free end along its tangent (cone ±35°, up to `gap`) to
    /// another free end facing back (within 60°, preferred) or onto a line (a T-junction),
    /// best bridges first.
    mutating func bridgeGaps(_ gap: Float) {
        guard gap > 0 else { return }
        let cosCone = Float(cos(35 * Double.pi / 180)), cosBack = Float(cos(60 * Double.pi / 180))
        var ends: [(node: Int, edge: Int, end: Int)] = []
        for n in 0..<nodes.count where nodeAlive[n] && degree(n) == 1 {
            ends.append((n, incidence[n][0].edge, incidence[n][0].end))
        }
        guard !ends.isEmpty else { return }
        var index = PointIndex(cell: max(gap, 4))
        for (i, e) in edges.enumerated() where e.alive {
            for (k, p) in e.points.enumerated() { index.insert(p, edge: i, index: k) }
        }
        var endOf: [Int: (edge: Int, end: Int)] = [:]
        for e in ends { endOf[e.node] = (e.edge, e.end) }
        struct Proposal { var score: Float; var node: Int; var edge: Int; var index: Int; var target: Int }
        var proposals: [Proposal] = []
        for (n, e, end) in ends {
            let t = Self.endTangent(oriented(e, from: end))
            guard t != .zero else { continue }
            let p0 = nodes[n]
            let count = edges[e].points.count
            var best: Proposal?
            index.forEach(near: p0, radius: gap) { te, ti in
                if te == e {
                    let along = end == 0 ? ti : count - 1 - ti
                    if Float(along) < 3 * gap { return }
                }
                let v = edges[te].points[ti] - p0
                let dist = simdLength(v)
                guard dist >= 1.5, dist <= gap else { return }
                let c = simdDot(v, t) / dist
                guard c >= cosCone else { return }
                let tl = edges[te].points.count
                let targetNode = ti == 0 ? edges[te].a : (ti == tl - 1 ? edges[te].b : -1)
                var score = dist * (1 + 2 * (1 - c))
                if targetNode >= 0, targetNode != n, let other = endOf[targetNode] {
                    let ot = Self.endTangent(oriented(other.edge, from: other.end))
                    if simdDot(ot, -v) / dist < cosBack { return }
                    score *= 0.6
                }
                if best == nil || score < best!.score {
                    best = Proposal(score: score, node: n, edge: te, index: ti, target: targetNode)
                }
            }
            if let best { proposals.append(best) }
        }
        proposals.sort { $0.score != $1.score ? $0.score < $1.score : $0.node < $1.node }
        var used = Set<Int>()
        var splits: [Int: [Int]] = [:]
        let original = edges.map(\.points)
        for p in proposals {
            guard !used.contains(p.node), nodeAlive[p.node], degree(p.node) == 1 else { continue }
            var target: Int
            if p.target >= 0, endOf[p.target] != nil {
                guard !used.contains(p.target), nodeAlive[p.target], degree(p.target) == 1 else { continue }
                target = p.target
                used.insert(p.target)
            } else if p.target >= 0 {
                guard nodeAlive[p.target] else { continue }
                target = p.target
            } else {
                guard let split = split(originalEdge: p.edge, index: p.index, original: original, splits: &splits) else { continue }
                target = split
            }
            let a = nodes[p.node], b = nodes[target]
            let steps = max(2, Int((simdLength(b - a)).rounded(.up)) + 1)
            let sa = strength(atNode: p.node), sb = strength(atNode: target)
            var points: [SIMD2<Float>] = [], strength: [Float] = []
            for k in 0..<steps {
                let t = Float(k) / Float(steps - 1)
                points.append(a + (b - a) * t)
                strength.append(sa + (sb - sa) * t)
            }
            addEdge(points, strength, p.node, target)
            used.insert(p.node)
        }
        mergeDegree2()
    }

    /// Edge strength where some edge meets node `n`.
    func strength(atNode n: Int) -> Float {
        guard let first = incidence[n].first else { return 0 }
        let e = edges[first.edge]
        return first.end == 0 ? e.strength[0] : e.strength[e.strength.count - 1]
    }

    /// Splits the current edge holding the original point (`originalEdge`, `index`); the node there.
    private mutating func split(
        originalEdge: Int, index: Int, original: [[SIMD2<Float>]], splits: inout [Int: [Int]]
    ) -> Int? {
        let target = original[originalEdge][index]
        for ce in [originalEdge] + (splits[originalEdge] ?? []) where edges[ce].alive {
            let p = edges[ce].points
            guard let k = p.firstIndex(of: target) else { continue }
            let e = edges[ce]
            if e.closed {
                // Reopen the closed edge at k with a node there.
                let node = addNode(p[k])
                let ring = Array(p[k...]) + Array(p[...k])
                let ringStrength = Array(e.strength[k...]) + Array(e.strength[...k])
                removeEdge(ce)
                splits[originalEdge, default: []].append(addEdge(ring, ringStrength, node, node))
                return node
            }
            if k == 0 { return e.a }
            if k == p.count - 1 { return e.b }
            let node = addNode(p[k])
            removeEdge(ce)
            let l = addEdge(Array(p[...k]), Array(e.strength[...k]), e.a, node)
            let r = addEdge(Array(p[k...]), Array(e.strength[k...]), node, e.b)
            splits[originalEdge, default: []].append(contentsOf: [l, r])
            return node
        }
        return nil
    }

    /// Free ends that run into the frame are continued straight to it (cone ±50°, up to `reach`).
    mutating func extendToFrame(width w: Int, height h: Int, reach: Float) {
        let cosCone = Float(cos(50 * Double.pi / 180))
        for n in 0..<nodes.count where nodeAlive[n] && degree(n) == 1 && !frameNodes.contains(n) {
            let (e, end) = incidence[n][0]
            let t = Self.endTangent(oriented(e, from: end))
            let p = nodes[n]
            var best: (travel: Float, axis: Int, value: Float)?
            let sides: [(SIMD2<Float>, Float, Int, Float)] = [
                (SIMD2(-1, 0), p.x, 0, 0), (SIMD2(1, 0), Float(w - 1) - p.x, 0, Float(w - 1)),
                (SIMD2(0, -1), p.y, 1, 0), (SIMD2(0, 1), Float(h - 1) - p.y, 1, Float(h - 1)),
            ]
            for (normal, dist, axis, value) in sides {
                let c = simdDot(t, normal)
                guard dist <= reach, c >= cosCone else { continue }
                let travel = dist / c
                if best == nil || travel < best!.travel { best = (travel, axis, value) }
            }
            guard let best else { continue }
            var q = p + t * best.travel
            if best.axis == 0 { q.x = best.value } else { q.y = best.value }
            q = SIMD2(min(max(q.x, 0), Float(w - 1)), min(max(q.y, 0), Float(h - 1)))
            if simdLength(q - p) < 0.5 {
                frameNodes.insert(n)
                continue
            }
            let m = addNode(q)
            frameNodes.insert(m)
            let steps = max(2, Int(simdLength(q - p).rounded(.up)) + 1)
            let s = strength(atNode: n)
            addEdge((0..<steps).map { p + (q - p) * (Float($0) / Float(steps - 1)) }, [Float](repeating: s, count: steps), n, m)
        }
        mergeDegree2()
    }

    // MARK: - Strokes

    struct Stroke {
        var points: [SIMD2<Float>]
        var strength: [Float]
        var closed: Bool
        /// Open ends attached to nothing.
        var free: (Bool, Bool)
        /// Seals for walls: point index → junction node position the stroke passed through
        /// (smoothing pulls strokes off their junction pixels).
        var links: [(index: Int, to: SIMD2<Float>)]
    }

    /// Joins edges through junctions into strokes (at each junction the best-aligned pairs of
    /// branches, within `joinDegrees` of straight, continue each other), smoothed along their
    /// length (Gaussian, `sigma` points, ends pinned).
    func strokes(joinDegrees: Float = 45, sigma: Float) -> [Stroke] {
        let cosJoin = Float(cos(Double(joinDegrees) * Double.pi / 180))
        struct Key: Hashable { var edge: Int; var end: Int }
        var link: [Key: Key] = [:]
        for n in 0..<nodes.count where nodeAlive[n] && incidence[n].count >= 3 {
            let inc = incidence[n]
            let tangents = inc.map { Self.endTangent(oriented($0.edge, from: $0.end)) }
            var pairs: [(Float, Int, Int)] = []
            for i in 0..<inc.count {
                for j in (i + 1)..<inc.count where inc[i].edge != inc[j].edge {
                    let c = -simdDot(tangents[i], tangents[j])
                    if c >= cosJoin { pairs.append((-c, i, j)) }
                }
            }
            pairs.sort { $0.0 != $1.0 ? $0.0 < $1.0 : ($0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2) }
            var paired = Set<Int>()
            for (_, i, j) in pairs where !paired.contains(i) && !paired.contains(j) {
                paired.insert(i)
                paired.insert(j)
                link[Key(edge: inc[i].edge, end: inc[i].end)] = Key(edge: inc[j].edge, end: inc[j].end)
                link[Key(edge: inc[j].edge, end: inc[j].end)] = Key(edge: inc[i].edge, end: inc[i].end)
            }
        }
        var seen = [Bool](repeating: false, count: edges.count)
        func nodeAt(_ e: Int, _ end: Int) -> Int { end == 0 ? edges[e].a : edges[e].b }

        func walk(_ e: Int, _ end: Int) -> (points: [SIMD2<Float>], strength: [Float], closed: Bool, junctions: [(Int, Int)], last: Int) {
            var points: [SIMD2<Float>] = [], strength: [Float] = []
            var junctions: [(Int, Int)] = []
            var cur = Key(edge: e, end: end)
            var closed = false
            while true {
                seen[cur.edge] = true
                let p = oriented(cur.edge, from: cur.end), s = orientedStrength(cur.edge, from: cur.end)
                if points.isEmpty {
                    points = p
                    strength = s
                } else {
                    junctions.append((points.count - 1, nodeAt(cur.edge, cur.end)))
                    points += p.dropFirst()
                    strength += s.dropFirst()
                }
                guard let next = link[Key(edge: cur.edge, end: 1 - cur.end)] else { break }
                if seen[next.edge] {
                    if next.edge == e && next.end == end { closed = true }
                    break
                }
                cur = next
            }
            return (points, strength, closed, junctions, nodeAt(cur.edge, 1 - cur.end))
        }

        var raw: [(points: [SIMD2<Float>], strength: [Float], closed: Bool, free: (Bool, Bool), junctions: [(Int, Int)], ends: (Int, Int))] = []
        for (i, e) in edges.enumerated() where e.alive && e.closed {
            seen[i] = true
            raw.append((e.points, e.strength, true, (false, false), [], (-1, -1)))
        }
        // Open strokes start at unlinked ends.
        for (i, e) in edges.enumerated() where e.alive && !seen[i] {
            for end in 0..<2 where link[Key(edge: i, end: end)] == nil {
                let w = walk(i, end)
                let first = nodeAt(i, end)
                func isFree(_ n: Int) -> Bool { degree(n) == 1 && !frameNodes.contains(n) }
                raw.append((w.points, w.strength, false, (isFree(first), isFree(w.last)), w.junctions, (first, w.last)))
                break
            }
        }
        // What is left are cycles through junctions.
        for (i, e) in edges.enumerated() where e.alive && !seen[i] {
            var w = walk(i, 0)
            let first = nodeAt(i, 0)
            if w.closed {
                w.points.removeLast()
                w.strength.removeLast()
                w.junctions.append((0, first))
            }
            raw.append((w.points, w.strength, w.closed, (false, false), w.junctions, (first, w.last)))
        }

        return raw.compactMap { s in
            guard s.points.count >= 2 else { return nil }
            let dense = Self.smooth(s.points, sigma: sigma, closed: s.closed)
            var links: [(Int, SIMD2<Float>)] = s.junctions.map { (min(max($0.0, 0), dense.count - 1), nodes[$0.1]) }
            if !s.closed {
                if s.ends.0 >= 0 { links.append((0, nodes[s.ends.0])) }
                if s.ends.1 >= 0 { links.append((dense.count - 1, nodes[s.ends.1])) }
            }
            return Stroke(points: dense, strength: s.strength, closed: s.closed, free: s.free, links: links)
        }
    }

    /// Gaussian smoothing along a polyline; open lines reflect at their ends, which stay put.
    static func smooth(_ pts: [SIMD2<Float>], sigma: Float, closed: Bool) -> [SIMD2<Float>] {
        let n = pts.count
        guard n >= 3, sigma > 0 else { return pts }
        let r = Int((3 * sigma).rounded(.up))
        func kernel(_ radius: Int) -> [Float] {
            let k = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
            let sum = k.reduce(0, +)
            return k.map { $0 / sum }
        }
        if closed {
            guard n > r else { return pts }
            let k = kernel(r)
            return (0..<n).map { i in
                var acc = SIMD2<Float>(0, 0)
                for j in -r...r { acc += pts[((i + j) % n + n) % n] * k[j + r] }
                return acc
            }
        }
        let m = min(r, n - 1)
        let k = kernel(m)
        var out = (0..<n).map { i -> SIMD2<Float> in
            var acc = SIMD2<Float>(0, 0)
            for j in -m...m {
                let q = i + j
                let p: SIMD2<Float>
                if q < 0 { p = 2 * pts[0] - pts[-q] } else if q >= n { p = 2 * pts[n - 1] - pts[2 * (n - 1) - q] } else { p = pts[q] }
                acc += p * k[j + m]
            }
            return acc
        }
        out[0] = pts[0]
        out[n - 1] = pts[n - 1]
        return out
    }
}

/// Uniform grid of points for radius queries, visited in a fixed order (deterministic).
struct PointIndex {
    let cell: Float
    private var buckets: [SIMD2<Int32>: [(edge: Int32, index: Int32, point: SIMD2<Float>)]] = [:]

    init(cell: Float) { self.cell = cell }

    private func key(_ p: SIMD2<Float>) -> SIMD2<Int32> {
        SIMD2(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)))
    }

    mutating func insert(_ p: SIMD2<Float>, edge: Int, index: Int) {
        buckets[key(p), default: []].append((Int32(edge), Int32(index), p))
    }

    func forEach(near p: SIMD2<Float>, radius: Float, _ body: (Int, Int) -> Void) {
        let lo = key(p - radius), hi = key(p + radius)
        let r2 = radius * radius
        for y in lo.y...hi.y {
            for x in lo.x...hi.x {
                guard let bucket = buckets[SIMD2(x, y)] else { continue }
                for item in bucket where simdLengthSquared(item.point - p) <= r2 { body(Int(item.edge), Int(item.index)) }
            }
        }
    }
}

@inline(__always) func simdDot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.x + a.y * b.y }
@inline(__always) func simdLengthSquared(_ a: SIMD2<Float>) -> Float { a.x * a.x + a.y * a.y }
@inline(__always) func simdLength(_ a: SIMD2<Float>) -> Float { simdLengthSquared(a).squareRoot() }
