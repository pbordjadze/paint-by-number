import Foundation

extension EditWork {
    /// The shape under `p` made one area of its own, painted `color` (OKLab): the closed shape
    /// the ink round the tapped region encloses, found by flooding across undrawn edges, or the
    /// tapped region alone when that reaches the canvas frame (a shape left open) so a fill
    /// never runs into the background. Its regions become one (any ink between them stays as
    /// strokes), painted the paint nearest `color` within a just-noticeable difference, else a
    /// new paint added last (no other number changes), and it is a detail area, kept whatever
    /// its size, numbered down to the detail floor, as a fill has always made it.
    mutating func fill(at p: LatticePoint, color: SIMD3<Float>) throws {
        guard let tapped = locate(p) else { throw EditFailure.invalid("the tap is off the canvas") }
        var members = [tapped]
        var seen: Set<Int> = [tapped]
        var open = false
        var next = 0
        while next < members.count {
            let r = members[next]
            next += 1
            for ring in ringsOf(r) {
                for ref in ring.refs {
                    let e = Int(ref.edge)
                    guard let other = right(e) else {
                        open = true
                        continue
                    }
                    if !isInked(e) {
                        let across = left(e) == r ? other : left(e)
                        if seen.insert(across).inserted { members.append(across) }
                    }
                }
            }
        }
        if open { members = [tapped] }
        members.sort()

        var paint = -1
        var nearest = Float.infinity
        for (k, c) in t.palette.enumerated() {
            let d = ColorScience.distance(c.oklab, color)
            if d < nearest { paint = k; nearest = d }
        }
        if paint < 0 || nearest > SegmentationParameters.jnd {
            t.palette.append(PaletteColor(oklab: color, space: t.colorSpace))
            paint = t.palette.count - 1
            summary.paintsAdded += 1
        }
        let color = UInt32(paint)
        let keep = members.contains(tapped) ? tapped : members[0]
        if members.count > 1 {
            try merge(members, keep: keep, color: color, detail: true)
        } else {
            guard let plan = labelPlan(
                rings: polygons(of: keep), color: color, detail: true, hints: hints(from: [keep]), region: keep, keepOut: [])
            else { throw EditFailure.invalid("the area has no room for the number of its paint") }
            t.regions[keep].colorIndex = color
            labels[keep] = plan.labels
            regionDetail[keep] = true
            regionTouched[keep] = true
            refreshColorWeights(around: keep)
            summary.touched.insert(keep)
        }
        summary.fills += 1
        summary.detailAreas += 1
    }
}
