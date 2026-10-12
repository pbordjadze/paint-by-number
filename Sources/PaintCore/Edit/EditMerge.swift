import Foundation

extension EditWork {
    /// Makes `members` one region, `keep` (one of them), of paint `color`. The edges between
    /// members go: an inked one stays as strokes in the merged region (`surviving` names the
    /// stretches of an edge that remain, whole when it is not there), an undrawn one is nothing
    /// more than the join of two cells. The edges round the members are the merged region's,
    /// which gets its rings traced again (the neighbours' rings and fills do not change: they
    /// refer to the same edges); its numbers stay where they were while their room does.
    mutating func merge(
        _ members: [Int], keep: Int, color: UInt32, detail: Bool, surviving: [Int: [[LatticePoint]]] = [:]
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

        let wasDetail = members.contains { regionDetail[$0] }
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
