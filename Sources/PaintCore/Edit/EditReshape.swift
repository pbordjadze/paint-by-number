import Foundation

extension TemplateEditor {
    /// What a reshape (`Edit.reshape`) grabbed at `from` would lay with its grabbed point at
    /// `to`, canvas units: the line as it lies (`original`, from one end of its chain to the
    /// other) and the points that would replace it (`moved`), for the app to show while the
    /// finger moves. Nil when no line `target` grabs lies within `reach` of `from`, or it is
    /// held there (a junction grabbed). The points are the edit's own; whether it can be laid (it may cross
    /// a line, leave the canvas, or leave an area no room for its number) only the edit says.
    public static func reshapedChain(
        on template: Template, from: SIMD2<Float>, to: SIMD2<Float>, reach: Float = tapReach, target: ReshapeTarget = .any
    ) -> (original: [SIMD2<Float>], moved: [SIMD2<Float>])? {
        guard from.x.isFinite, from.y.isFinite, to.x.isFinite, to.y.isFinite, var work = try? EditWork(template),
              let plan = try? work.reshapePlan(
                from: Lattice.clampedPoint(from), to: Lattice.clampedPoint(to), reach: latticeReach(reach), target: target,
                checking: false)
        else { return nil }
        return (plan.original.map(Lattice.position), plan.path.map(Lattice.position))
    }

    /// A tap's reach in lattice steps, held between 0 and 1024 canvas units.
    static func latticeReach(_ reach: Float) -> Int64 {
        Int64((min(max(reach.isFinite ? reach : 0, 0), 1024) * Float(Lattice.unit)).rounded())
    }
}

extension EditWork {
    /// What a reshape lays: the chain it grabbed and where its points go.
    struct Reshape {
        /// The chain's edges in order along it, each walked one way; empty for a stroke.
        var halves: [HalfEdge] = []
        /// The stroke grabbed, when the chain is one.
        var stroke: Int?
        /// The chain as it lies, from end to end (a loop's first point again last).
        var original: [LatticePoint] = []
        /// The moved points of each piece (each half edge, or the stroke) in walk order.
        var moved: [[LatticePoint]] = []
        /// The moved chain, from end to end.
        var path: [LatticePoint] = []
        /// Strokes ending on the chain, carried along: each one's new points.
        var carried: [(stroke: Int, points: [LatticePoint])] = []
        /// The point of the chain grabbed, as it lies.
        var grabbed = LatticePoint(0, 0)
        /// Where the moved chain meets the drawing: its ends that stay, and where the strokes it
        /// carries end on it.
        var joints: Set<LatticePoint> = []
    }

    /// How far apart, at most, the points of a step of a chain that a reshape bends are laid,
    /// lattice steps: a long straight step bent by a drag becomes a smooth curve.
    static var reshapeStep: Int64 { 3 * Lattice.unit }

    /// How far along a chain, at least, a reshape bends it either side of the grabbed point,
    /// lattice steps: three times the drag, or this much for a short drag. Past it the chain stays
    /// as it is, so a long outline bends near the finger rather than along its whole length.
    static var reshapeSpread: Int64 { 24 * Lattice.unit }

    /// The weight of a point a fraction `u` (0 to 1) of the way from the grabbed point to a held
    /// end: 1 at the grabbed point, 0 at the end, with no slope at either (a smoothstep, the
    /// raised cosine's cubic twin, in `+ - *` alone, so it is the same on every device).
    static func falloff(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return 1 - c * c * (3 - 2 * c)
    }

    /// Refine's Bend Line and Move Edge (`TemplateEditor.Edit.reshape`): the line nearest `from`
    /// within `reach` of those `target` grabs and the chain it continues into is moved, its point nearest `from` to `to`
    /// (`reshapePlan`). The regions on its sides keep their paints; their outlines follow the
    /// edges, their fills are made again and their numbers stay while they have the room
    /// (`labelPlan`), the pixels between the old outline and the new go to the region whose
    /// outline now holds them. Declined when it would cross a line or itself, leave the canvas,
    /// turn an area inside out, carry an island or a stroke into the region across, or leave an
    /// area too little room for its number.
    mutating func reshape(from: LatticePoint, to: LatticePoint, reach: Int64, target: TemplateEditor.ReshapeTarget) throws {
        let plan = try reshapePlan(from: from, to: to, reach: reach, target: target, checking: true)
        guard to != plan.grabbed else { return }
        var areas = Set<Int>()
        if let i = plan.stroke {
            strokes[i].points = plan.moved[0].map(Lattice.position)
            movedStrokes.insert(i)
            areas.insert(strokes[i].region)
        } else {
            for (k, h) in plan.halves.enumerated() { setPoints(h.edge, h.reversed ? plan.moved[k].reversed() : plan.moved[k]) }
            let e = plan.halves[0].edge
            areas.formUnion([left(e), right(e)!])
        }
        var inked: [Int: [[SIMD2<Float>]]] = [:]
        if let i = plan.stroke { inked[strokes[i].region, default: []].append(strokes[i].points) }
        for c in plan.carried {
            strokes[c.stroke].points = c.points.map(Lattice.position)
            movedStrokes.insert(c.stroke)
            areas.insert(strokes[c.stroke].region)
            inked[strokes[c.stroke].region, default: []].append(strokes[c.stroke].points)
        }
        let sides = areas.sorted()
        if plan.stroke == nil {
            for r in sides {
                let rs = ringsOf(r), polys = rs.map(polygon)
                for (ring, poly) in zip(rs, polys) {
                    let a = Lattice.area2(poly)
                    guard a != 0, (a < 0) == ring.isHole else { throw EditFailure.invalid("an area would be turned inside out") }
                }
                let outers = zip(rs, polys).filter { !$0.0.isHole }.map(\.1)
                for (ring, poly) in zip(rs, polys) where ring.isHole {
                    guard let v = poly.first(where: { Lattice.contains(outers, $0) != .boundary }) else { continue }
                    guard Lattice.contains(outers, v) == .inside else { throw EditFailure.invalid("an island would change areas") }
                }
            }
        }
        for i in strokes.indices where strokes[i].alive && sides.contains(strokes[i].region) {
            let pts = strokes[i].points.map(Lattice.point)
            for (a, b) in zip(pts, pts.dropFirst()) {
                let place = contains(strokes[i].region, a &+ b, scale: 2)
                if place == .boundary { continue }
                guard place == .inside else { throw EditFailure.invalid("a line would leave its area") }
                break
            }
        }
        for r in sides {
            guard let plan = labelPlan(
                rings: polygons(of: r), color: t.regions[r].colorIndex, detail: regionDetail[r], hints: hints(from: [r]), region: r,
                keepOut: inked[r] ?? []),
                  !plan.needsDetail || regionDetail[r]
            else { throw EditFailure.invalid("an area would have no room for its number") }
            labels[r] = plan.labels
            regionTouched[r] = true
            summary.touched.insert(r)
        }
        if plan.stroke == nil {
            for r in sides { remesh.insert(r) }
            var lo = plan.original[0], hi = lo
            for p in plan.original + plan.path { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            reclaim(sides, within: (lo, hi))
        }
        summary.reshaped += 1 + plan.carried.count
    }

    /// The chain a reshape grabs and where it goes. The line nearest `from` within `reach` of those
    /// `target` grabs (any; drawn edges and strokes; or edges alone): an edge (not the canvas's
    /// frame), drawn or undrawn, continued through every vertex where it and one other edge alike
    /// (both drawn, or both undrawn) end, every edge counted and no stroke (the Line Eraser's
    /// `eraseLine` counts drawn edges and strokes alone, so its line runs on past an undrawn edge
    /// and stops at a vertex where a stroke ends); or a drawn stroke. Its point nearest `from` goes to `to` and
    /// the rest follows, each point by the drag times its weight (`falloff`) along the chain's
    /// length: 1 at the grabbed point, 0 a spread away (`reshapeSpread`, or three times the drag)
    /// or at the chain's end if that is nearer, which stays on its junction; beyond, the chain
    /// keeps its points, the first of them made a vertex. A loop through no junction is held at
    /// most at its far point, half its length round. A stroke's end that meets no line is free:
    /// within the spread, the stretch from the grabbed point to it moves whole (a short stroke free
    /// at both ends moves as it is); beyond it, it stays. Strokes ending on the chain are carried,
    /// their end moving with the point of it they meet. Where a step's two ends move at least half
    /// a unit apart, it bends: points are added along it so that, moved, they are `reshapeStep` or
    /// less apart (a stretch moved whole stays as it was). With `checking`, the moved chain must
    /// lie on the canvas, be simple, and meet the drawing only where it met it: at its held ends
    /// and the strokes it carries.
    mutating func reshapePlan(
        from: LatticePoint, to: LatticePoint, reach: Int64, target: TemplateEditor.ReshapeTarget, checking: Bool
    ) throws -> Reshape {
        let r2 = reach * reach
        var grab: (edge: Int?, stroke: Int?, segment: Int, point: LatticePoint, d2: Int64)?
        /// Whether the target grabs edge `e` (not the frame), and a stroke of layer `layer`.
        func grabs(edge e: Int) -> Bool {
            switch target {
            case .any: true
            case .ink: LineLayer.isDrawn(layers[e])
            case .edge: left(e) != right(e)
            }
        }
        func grabs(strokeOf layer: UInt8) -> Bool {
            switch target {
            case .any: true
            case .ink: LineLayer.isDrawn(layer)
            case .edge: false
            }
        }
        for e in t.edges.indices where !edgeDead[e] && !isFrame(e) && grabs(edge: e) {
            let b = box(of: e)
            guard from.x >= b.lo.x - reach, from.x <= b.hi.x + reach, from.y >= b.lo.y - reach, from.y <= b.hi.y + reach else { continue }
            let pts = lattice(of: e)
            for j in 0..<(pts.count - 1) {
                let hit = Lattice.nearest(to: from, on: pts[j], pts[j + 1])
                if hit.distanceSquared <= r2, grab == nil || hit.distanceSquared < grab!.d2 { grab = (e, nil, j, hit.point, hit.distanceSquared) }
            }
        }
        var lines: [(index: Int, points: [LatticePoint])] = []
        for (i, s) in strokes.enumerated() where s.alive && s.layer != LineLayer.color.rawValue {
            let pts = Self.dedupe(s.points.map(Lattice.point))
            guard pts.count >= 2 else { continue }
            lines.append((i, pts))
            guard grabs(strokeOf: s.layer) else { continue }
            for j in 0..<(pts.count - 1) {
                let hit = Lattice.nearest(to: from, on: pts[j], pts[j + 1])
                if hit.distanceSquared <= r2, grab == nil || hit.distanceSquared < grab!.d2 { grab = (nil, i, j, hit.point, hit.distanceSquared) }
            }
        }
        guard let grab else { throw EditFailure.invalid(TemplateEditor.noLineNear) }

        var plan = Reshape()
        plan.grabbed = grab.point
        var pieces: [[LatticePoint]]
        var closed = false, startFree = false, endFree = false
        var grabPiece = 0
        if let e0 = grab.edge {
            var ends: [LatticePoint: [(edge: Int, atStart: Bool)]] = [:]
            for e in t.edges.indices where !edgeDead[e] {
                ends[latticePoint(e, 0), default: []].append((e, true))
                ends[latticePoint(e, Int(t.edges[e].pointCount) - 1), default: []].append((e, false))
            }
            let inked = isInked(e0)
            /// The edge going on from the end of edge `e` (its start, or its last point), when it
            /// is the one other edge ending there and is alike.
            func onward(_ e: Int, atStart: Bool) -> (edge: Int, atStart: Bool)? {
                let v = latticePoint(e, atStart ? 0 : Int(t.edges[e].pointCount) - 1)
                guard let here = ends[v], here.count == 2,
                      let next = here.first(where: { !($0.edge == e && $0.atStart == atStart) }),
                      !isFrame(next.edge), isInked(next.edge) == inked
                else { return nil }
                return next
            }
            var halves = [HalfEdge(edge: e0, reversed: false)]
            var seen: Set<Int> = [e0]
            var h = halves[0]
            while let next = onward(h.edge, atStart: h.reversed) {
                if next.edge == e0 {
                    closed = true
                    break
                }
                guard seen.insert(next.edge).inserted else { break }
                h = HalfEdge(edge: next.edge, reversed: !next.atStart)
                halves.append(h)
            }
            if !closed {
                h = halves[0]
                while let next = onward(h.edge, atStart: !h.reversed), seen.insert(next.edge).inserted {
                    h = HalfEdge(edge: next.edge, reversed: next.atStart)
                    halves.insert(h, at: 0)
                    grabPiece += 1
                }
            }
            plan.halves = halves
            pieces = halves.map(walk)
        } else {
            let i = grab.stroke!
            let pts = lines.first { $0.index == i }!.points
            plan.stroke = i
            pieces = [pts]
            closed = pts.first == pts.last
            if !closed {
                /// Whether `p` lies on a line other than the stroke.
                func held(_ p: LatticePoint) -> Bool {
                    func on(_ q: [LatticePoint]) -> Bool {
                        zip(q, q.dropFirst()).contains { a, b in Lattice.orient(a, b, p) == 0 && Lattice.between(a, b, p) }
                    }
                    for e in t.edges.indices where !edgeDead[e] {
                        let b = box(of: e)
                        guard p.x >= b.lo.x, p.x <= b.hi.x, p.y >= b.lo.y, p.y <= b.hi.y else { continue }
                        if on(lattice(of: e)) { return true }
                    }
                    return lines.contains { $0.index != i && on($0.points) }
                }
                startFree = !held(pts[0])
                endFree = !held(pts[pts.count - 1])
            }
        }
        plan.original = pieces[0] + pieces.dropFirst().flatMap { $0.dropFirst() }
        if !closed {
            if !startFree { plan.joints.insert(plan.original[0]) }
            if !endFree { plan.joints.insert(plan.original[plan.original.count - 1]) }
        }

        // The grabbed point, and where the strokes the chain carries end on it, made vertices.
        var inserts = [[(segment: Int, point: LatticePoint)]](repeating: [], count: pieces.count)
        inserts[grabPiece].append((grab.segment, grab.point))
        var attached: [(stroke: Int, atStart: Bool, point: LatticePoint)] = []
        for (i, pts) in lines where i != plan.stroke && pts.first != pts.last {
            for atStart in [true, false] {
                let p = atStart ? pts[0] : pts[pts.count - 1]
                guard !plan.joints.contains(p) else { continue }
                search: for (k, piece) in pieces.enumerated() {
                    for j in 0..<(piece.count - 1) where Lattice.orient(piece[j], piece[j + 1], p) == 0 && Lattice.between(piece[j], piece[j + 1], p) {
                        inserts[k].append((j, p))
                        attached.append((i, atStart, p))
                        break search
                    }
                }
            }
        }
        for k in pieces.indices where !inserts[k].isEmpty { pieces[k] = Self.inserting(inserts[k], into: pieces[k]) }
        /// The chain's points from end to end, where each piece starts among them, and each
        /// point's length along the chain.
        func flatten() -> (points: [LatticePoint], starts: [Int], along: [Double]) {
            var flat = pieces[0], starts = [0]
            for piece in pieces.dropFirst() {
                starts.append(flat.count - 1)
                flat.append(contentsOf: piece.dropFirst())
            }
            var along = [Double](repeating: 0, count: flat.count)
            for i in 1..<flat.count { along[i] = along[i - 1] + Double(Lattice.distanceSquared(flat[i - 1], flat[i])).squareRoot() }
            return (flat, starts, along)
        }
        let delta = to &- grab.point
        let drag = Double(Lattice.distanceSquared(to, grab.point)).squareRoot()
        let spread = max(3 * drag, Double(Self.reshapeSpread))
        var (flat, pieceStart, s) = flatten()
        var total = s[s.count - 1]
        func grabbedAt() -> Double { s[pieceStart[grabPiece] + pieces[grabPiece].firstIndex(of: grab.point)!] }
        var sg = grabbedAt()
        guard closed || (sg > 0 || startFree) && (sg < total || endFree) else {
            throw EditFailure.invalid("the line is held where it was grabbed")
        }
        // A free end within the bend's spread moves whole with the grabbed point; one beyond it stays.
        let freeBefore = !closed && startFree && sg <= spread, freeAfter = !closed && endFree && total - sg <= spread
        /// How far along the chain the bend runs before the grabbed point and after it: the
        /// spread, at most to the chain's end (a loop's far point).
        func bend(after: Bool) -> Double { closed ? min(spread, total / 2) : min(spread, after ? total - sg : sg) }
        /// Makes the point `at` along the chain a vertex, so that the chain beyond it, which
        /// doesn't move, keeps its points exactly.
        func hold(_ at: Double) {
            let at = closed ? (at < 0 ? at + total : at >= total ? at - total : at) : at
            guard let i = (0..<(flat.count - 1)).first(where: { s[$0] < at && at < s[$0 + 1] }) else { return }
            let f = (at - s[i]) / (s[i + 1] - s[i]), d = flat[i + 1] &- flat[i]
            let p = flat[i] &+ LatticePoint(Int64((Double(d.x) * f).rounded()), Int64((Double(d.y) * f).rounded()))
            let k = pieceStart.lastIndex { $0 <= i }!
            pieces[k] = Self.inserting([(i - pieceStart[k], p)], into: pieces[k])
            (flat, pieceStart, s) = flatten()
            total = s[s.count - 1]
            sg = grabbedAt()
        }
        if !freeAfter { hold(sg + bend(after: true)) }
        if !freeBefore { hold(sg - bend(after: false)) }
        func weight(_ at: Double) -> Double {
            let d: Double
            if closed {
                d = min(abs(at - sg), total - abs(at - sg))
            } else if at <= sg {
                if freeBefore { return 1 }
                d = sg - at
            } else {
                if freeAfter { return 1 }
                d = at - sg
            }
            let r = bend(after: at > sg)
            return r > 0 ? Self.falloff(d / r) : 1
        }
        func moved(_ p: LatticePoint, _ w: Double) -> LatticePoint {
            p &+ LatticePoint(Int64((w * Double(delta.x)).rounded()), Int64((w * Double(delta.y)).rounded()))
        }
        let w = s.map(weight)
        let step = Double(Self.reshapeStep)
        for (k, piece) in pieces.enumerated() {
            var out: [LatticePoint] = []
            for j in piece.indices {
                let i = pieceStart[k] + j
                if j > 0, abs(w[i] - w[i - 1]) * drag >= Double(Lattice.unit) / 2 {
                    // The falloff is at its steepest 1.5 times its mean slope over the side, so a
                    // moved step is at most this many times as long as it was.
                    let length = s[i] - s[i - 1], stretch = 1 + 1.5 * drag / bend(after: s[i - 1] + length / 2 > sg)
                    let n = Int64((length * stretch / step).rounded(.up))
                    let a = flat[i - 1], d = flat[i] &- a
                    for q in stride(from: Int64(1), to: n, by: 1) {
                        let p = LatticePoint(a.x + Lattice.mulDiv(d.x, q, n), a.y + Lattice.mulDiv(d.y, q, n))
                        out.append(moved(p, weight(s[i - 1] + length * Double(q) / Double(n))))
                    }
                }
                out.append(moved(flat[i], w[i]))
            }
            plan.moved.append(Self.dedupe(out))
        }
        plan.path = plan.moved[0] + plan.moved.dropFirst().flatMap { $0.dropFirst() }
        for a in attached {
            let i = flat.firstIndex(of: a.point)!
            let to = moved(a.point, w[i])
            var pts = lines.first { $0.index == a.stroke }!.points
            if let j = plan.carried.firstIndex(where: { $0.stroke == a.stroke }) { pts = plan.carried[j].points }
            pts[a.atStart ? 0 : pts.count - 1] = to
            if let j = plan.carried.firstIndex(where: { $0.stroke == a.stroke }) {
                plan.carried[j].points = pts
            } else {
                plan.carried.append((a.stroke, pts))
            }
            plan.joints.insert(to)
        }
        guard checking else { return plan }

        for piece in plan.moved {
            let loop = piece.first == piece.last
            guard piece.count >= (loop ? 4 : 2), Set(piece).count >= (loop ? 3 : 2) else {
                throw EditFailure.invalid("the line would fold onto itself")
            }
        }
        let width = Int64(t.width) * Lattice.unit, height = Int64(t.height) * Lattice.unit
        guard plan.path.allSatisfy({ $0.x >= 0 && $0.y >= 0 && $0.x <= width && $0.y <= height }) else {
            throw EditFailure.invalid("the line would leave the canvas")
        }
        guard plan.carried.allSatisfy({ Self.dedupe($0.points).count == $0.points.count }) else {
            throw EditFailure.invalid("a line would fold onto itself")
        }
        guard Self.isSimple(plan.path), plan.carried.allSatisfy({ Self.isSimple($0.points) }) else {
            throw EditFailure.invalid("the line would cross itself")
        }
        try checkReshape(plan, strokes: lines)
        return plan
    }

    /// Whether the moved chain of `plan`, and the strokes it carries, meet the rest of the
    /// drawing (`lines`, the drawn strokes as they lie) only where they are meant to: a moved
    /// step touches another line only at one of its own ends that is a joint of its line (the
    /// chain's held ends and where carried strokes meet it; a carried stroke's ends).
    func checkReshape(_ plan: Reshape, strokes lines: [(index: Int, points: [LatticePoint])]) throws {
        struct Moving {
            var points: [LatticePoint]
            /// The steps that moved.
            var steps: Range<Int>
            var joints: Set<LatticePoint>
        }
        var moving = [Moving(points: plan.path, steps: 0..<(plan.path.count - 1), joints: plan.joints)]
        for c in plan.carried {
            let original = lines.first { $0.index == c.stroke }!.points
            let n = c.points.count - 1
            let first = c.points[0] != original[0], last = c.points[n] != original[original.count - 1]
            let steps = first && last ? 0..<n : first ? 0..<1 : (n - 1)..<n
            moving.append(Moving(points: c.points, steps: steps, joints: [c.points[0], c.points[n]]))
        }
        let chainEdges = Set(plan.halves.map(\.edge))
        let still = Set(plan.carried.map(\.stroke) + (plan.stroke.map { [$0] } ?? []))
        var fixed: [[LatticePoint]] = []
        var lo = plan.path[0], hi = lo
        for m in moving { for p in m.points { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) } }
        func near(_ pts: [LatticePoint]) -> Bool {
            var a = pts[0], b = pts[0]
            for p in pts { a = pointwiseMin(a, p); b = pointwiseMax(b, p) }
            return a.x <= hi.x && b.x >= lo.x && a.y <= hi.y && b.y >= lo.y
        }
        for e in t.edges.indices where !edgeDead[e] && !chainEdges.contains(e) {
            let pts = lattice(of: e)
            if near(pts) { fixed.append(pts) }
        }
        for line in lines where !still.contains(line.index) && near(line.points) { fixed.append(line.points) }

        func check(_ m: Moving, against other: [LatticePoint]) throws {
            for k in m.steps {
                let a0 = m.points[k], a1 = m.points[k + 1]
                for l in 0..<(other.count - 1) {
                    switch Lattice.contact(a0, a1, other[l], other[l + 1]) {
                    case .none: continue
                    case .touch(let p) where (p == a0 || p == a1) && m.joints.contains(p): continue
                    default: throw EditFailure.invalid("the line would meet another")
                    }
                }
            }
        }
        for (i, m) in moving.enumerated() {
            for other in fixed { try check(m, against: other) }
            for (j, n) in moving.enumerated() where j != i { try check(m, against: n.points) }
        }
    }
}
