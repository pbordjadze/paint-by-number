import Foundation

extension EditWork {
    /// Makes `members` one region, `keep` (one of them), of paint `color`. The edges between
    /// members go: an inked one stays as strokes in the merged region (`surviving` names the
    /// stretches of an edge that remain, whole when it is not there), an undrawn one is nothing
    /// more than the join of two cells. The edges round the members are the merged region's,
    /// which gets its rings traced again (the neighbours' rings and fills do not change: they
    /// refer to the same edges); its numbers stay where they were while their room does. It is a
    /// detail area when `detail` says so, or, `inheritingDetail`, when any member was one.
    mutating func merge(
        _ members: [Int], keep: Int, color: UInt32, detail: Bool, inheritingDetail: Bool = true,
        surviving: [Int: [[LatticePoint]]] = [:]
    ) throws {
        let inside = Set(members)
        var edgeSet = Set<Int>()
        for m in members { for ring in ringsOf(m) { for ref in ring.refs { edgeSet.insert(Int(ref.edge)) } } }
        var around: [HalfEdge] = []
        for e in edgeSet.sorted() where !edgeDead[e] {
            let l = left(e), r = right(e)
            switch (inside.contains(l), r.map { inside.contains($0) } ?? false) {
            case (true, true):
                if isInked(e) {
                    for piece in surviving[e] ?? [lattice(of: e)] {
                        addStroke(piece, layer: layers[e], weight: weights[e], region: keep)
                    }
                }
                kill(e)
            case (true, false):
                if l != keep { t.edges[e].left = UInt32(keep); edgeDirty[e] = true }
                around.append(HalfEdge(edge: e, reversed: false))
            case (false, true):
                if r != keep { t.edges[e].right = UInt32(keep); edgeDirty[e] = true }
                around.append(HalfEdge(edge: e, reversed: true))
            case (false, false):
                break
            }
        }
        let cycles = try trace(around)
        var outers: [[HalfEdge]] = [], holes: [[HalfEdge]] = []
        for cycle in cycles {
            let area2 = Lattice.area2(polygon(cycle))
            guard area2 != 0 else { throw EditFailure.collision("the joined area has an empty outline") }
            if area2 > 0 { outers.append(cycle) } else { holes.append(cycle) }
        }
        guard outers.count == 1 else { throw EditFailure.collision("the joined area is not one piece") }
        let ordered = outers + holes
        let newRings = ordered.enumerated().map { i, cycle in
            WorkRing(refs: cycle.map { EdgeRef(edge: UInt32($0.edge), reversed: $0.reversed) }, isHole: i > 0)
        }

        let wasDetail = inheritingDetail && members.contains { regionDetail[$0] }
        guard let plan = labelPlan(
            rings: ordered.map(polygon), color: color, detail: detail || wasDetail, hints: hints(from: members), region: keep,
            keepOut: freshInk[keep] ?? [])
        else { throw EditFailure.invalid("the joined area has no room for its number") }

        t.regions[keep].colorIndex = color
        setRings(keep, newRings)
        labels[keep] = plan.labels
        regionDetail[keep] = detail || wasDetail || plan.needsDetail
        for m in members where m != keep {
            regionAlive[m] = false
            successor[m] = keep
            rings[m] = nil
            labels[m] = nil
            remesh.remove(m)
            verifyLabels.remove(m)
        }
        for i in strokes.indices where strokes[i].alive && inside.contains(strokes[i].region) && strokes[i].region != keep {
            strokes[i].region = keep
            movedStrokes.insert(i)
        }
        if var lines = freshInk[keep] {
            for m in members where m != keep { lines += freshInk[m] ?? [] }
            freshInk[keep] = lines
        }
        relabelPixels(of: inside.subtracting([keep]), to: keep)
        remesh.insert(keep)
        verifyLabels.remove(keep)
        regionTouched[keep] = true
        refreshColorWeights(around: keep)
        summary.regionsMerged += members.count - 1
        summary.touched.insert(keep)
    }

    /// Refine's Merge: the regions under `path` (lattice points, canvas units on the quantum
    /// grid), in the order the path first enters them, walked in steps of half a unit, a point
    /// off the canvas or in no region left out. The first region is joined by each next one that
    /// shares an edge with those joined so far; one that doesn't is passed over. The edges
    /// between them go, ink and all, with no stroke left of an inked one (unlike the eraser's
    /// join); the strokes inside them stay. The joined area keeps the first region's index,
    /// paint and number, and is a detail area only if the first was (a detail area is what a
    /// fill or a cramped cut made: the painter dragged from it, so the area is it, grown). A
    /// paint left with no area leaves the palette, the numbers after it closing up, as Only
    /// This Area's does.
    mutating func merge(along path: [LatticePoint]) throws {
        let width = Int64(t.width) * Lattice.unit, height = Int64(t.height) * Lattice.unit
        var order: [Int] = []
        var seen = Set<Int>()
        var current: (region: Int, rings: [[LatticePoint]])?
        func visit(_ p: LatticePoint) {
            guard p.x >= 0, p.y >= 0, p.x <= width, p.y <= height else { return }
            if let c = current, Lattice.contains(c.rings, p) == .inside { return }
            guard let r = locate(p) else { return }
            current = (r, polygons(of: r))
            if seen.insert(r).inserted { order.append(r) }
        }
        let step = Lattice.unit / 2
        let lo = LatticePoint(0, 0), hi = LatticePoint(width, height)
        for (k, p) in path.enumerated() {
            visit(p)
            guard k + 1 < path.count else { break }
            // Stepped only where it crosses the canvas: off it nothing is visited anyway.
            guard let (a, b) = Self.clip(p, path[k + 1], lo, hi) else { continue }
            visit(a)
            let d = b &- a
            let n = max(abs(d.x), abs(d.y)) / step + 1
            for i in 1..<n { visit(LatticePoint(a.x + Lattice.mulDiv(d.x, i, n), a.y + Lattice.mulDiv(d.y, i, n))) }
            visit(b)
        }
        guard let first = order.first else { throw EditFailure.invalid("the merge joins no areas") }
        var members = [first]
        var joined: Set<Int> = [first]
        for r in order.dropFirst() {
            let borders = ringsOf(r).contains { ring in
                ring.refs.contains { ref in
                    let e = Int(ref.edge)
                    guard !edgeDead[e], let other = right(e) else { return false }
                    return joined.contains(left(e) == r ? other : left(e))
                }
            }
            if borders {
                members.append(r)
                joined.insert(r)
            }
        }
        guard members.count >= 2 else { throw EditFailure.invalid("the merge joins no areas") }
        var between: [Int: [[LatticePoint]]] = [:]
        for m in members {
            for ring in ringsOf(m) {
                for ref in ring.refs {
                    let e = Int(ref.edge)
                    if let other = right(e), joined.contains(left(e)), joined.contains(other) { between[e] = [] }
                }
            }
        }
        let used = Set(t.regions.indices.filter { regionAlive[$0] }.map { t.regions[$0].colorIndex })
        try merge(
            members, keep: first, color: t.regions[first].colorIndex, detail: regionDetail[first], inheritingDetail: false,
            surviving: between)
        try dropPaints(emptiedFrom: used)
    }

    /// Paints of `used` that no area has now leave the palette, the numbers after them closing
    /// up (`renumberPaints`: a number only loses digits).
    mutating func dropPaints(emptiedFrom used: Set<UInt32>) throws {
        let now = Set(t.regions.indices.filter { regionAlive[$0] }.map { t.regions[$0].colorIndex })
        let emptied = used.subtracting(now)
        guard !emptied.isEmpty, let survivor = now.min() else { return }
        var target = Array(t.palette.indices)
        for k in emptied { target[Int(k)] = Int(survivor) }
        try renumberPaints(into: target, colors: t.palette.map(\.oklab))
        summary.paintsMerged += emptied.count
    }

    /// The weight of an undrawn edge between regions of these paints: their difference
    /// (`LayeredLines.annotate`).
    func colorWeight(_ a: UInt32, _ b: UInt32) -> UInt8 {
        let d = ColorScience.distance(t.palette[Int(a)].oklab, t.palette[Int(b)].oklab)
        return UInt8((min(d / LayeredLines.colorWeightReference, 1) * 255).rounded())
    }

    /// Weights of the undrawn edges round `r`, after its paint changed.
    mutating func refreshColorWeights(around r: Int) {
        for ring in ringsOf(r) {
            for ref in ring.refs {
                let e = Int(ref.edge)
                guard !edgeDead[e], layers[e] == LineLayer.color.rawValue, let other = right(e) else { continue }
                let w = colorWeight(t.regions[left(e)].colorIndex, t.regions[other].colorIndex)
                if w != weights[e] { weights[e] = w }
            }
        }
    }
}
