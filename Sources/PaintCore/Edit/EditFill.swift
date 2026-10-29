import Foundation

extension EditWork {
    /// The shape under `p` made one area of its own, painted `color` (OKLab): the closed shape
    /// the ink round the tapped region encloses, found by flooding across undrawn edges, or the
    /// tapped region alone when that reaches the canvas frame (a shape left open) so a fill
    /// never runs into the background. Its regions become one (any ink between them stays as
    /// strokes), painted the paint nearest `color` within a just-noticeable difference, else a
    /// new paint added last (no other number changes), and it is a detail area, kept whatever
    /// its size, numbered down to the detail floor, as a fill has always made it. A paint it
    /// leaves with no area leaves the palette, the numbers after it closing up, as Merge's
    /// does (editor version 2: before, the paint stayed, and the painting's numbers skipped it).
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

        let used = livePaints
        let color = UInt32(paint(matching: color))
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
        try dropPaints(emptiedFrom: used)
        summary.fills += 1
        summary.detailAreas += 1
    }

    /// The paint a tapped color (OKLab) takes: the nearest within a just-noticeable difference,
    /// else a new paint of that color, added last so no other number changes.
    mutating func paint(matching color: SIMD3<Float>) -> Int {
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
        return paint
    }

    /// The region under `p` alone, flooding nothing (Refine's Only This Area: the generator had
    /// given a husky's eyes the sky's blue), painted `color` (OKLab) with the paint a fill would
    /// take (`paint(matching:)`). It stays a detail area or not as it was, and its numbers are
    /// sized for the new paint's digits: an area without room for them is declined. A paint it
    /// leaves with no area goes, the numbers after it closing up as a repaint's merge closes them
    /// (`renumberPaints`); no other region's paint changes. Where the area then meets one of its
    /// new paint across an undrawn boundary, the two become one area (`joinAreas`). A color whose
    /// paint the region has already changes nothing. `color` is one of the template on screen,
    /// as sent, not a photo's brought through the looks (`TemplateEditor.recolored`).
    mutating func paintArea(at p: LatticePoint, color: SIMD3<Float>) throws {
        guard let r = locate(p) else { throw EditFailure.invalid("the tap is off the canvas") }
        let before = t.regions.map(\.colorIndex)
        let old = Int(before[r])
        var new = paint(matching: color)
        guard new != old else { return }
        if !t.regions.indices.contains(where: { $0 != r && regionAlive[$0] && Int(t.regions[$0].colorIndex) == old }) {
            // The area was its paint's last: that paint becomes the new one, so the area's number
            // is the new paint's once the numbers after the old have closed up.
            var target = Array(t.palette.indices)
            target[old] = new
            try renumberPaints(into: target, colors: t.palette.map(\.oklab))
            new = Int(t.regions[r].colorIndex)
            summary.paintsMerged += 1
        }
        guard recolor(r, to: new, adding: nil) else {
            throw EditFailure.invalid("the area has no room for the number of its new paint")
        }
        try joinAreas(paintedBefore: before)
    }
}
