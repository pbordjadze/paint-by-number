import Foundation

extension TemplateEditor {
    /// How far the photo's color of a piece a drawn line cut may be from a paint for the piece to
    /// take that paint: the coloring book's own tolerance for one color, twice the median distance
    /// between its paints (`LayeredLines.mergeSteps` × `paletteStep`: cells whose paints are closer
    /// are merged into one area, `CellMap.mergeCloseColors`), within a just-noticeable difference
    /// and `paintToleranceLimit`. A piece whose photo is farther from every paint than that has a
    /// color the palette lacks, and gets a paint of its own; one nearer takes the paint the
    /// generator would have given it, so drawing lines doesn't fill the palette with twins of its
    /// paints.
    static func paintTolerance(_ palette: [PaletteColor]) -> Float {
        let step = LayeredLines.paletteStep(palette.map(\.oklab))
        return min(max(SegmentationParameters.jnd, LayeredLines.mergeSteps * step), paintToleranceLimit)
    }

    /// The most `paintTolerance` allows, three just-noticeable differences: a few far-apart paints
    /// (a palette of 4 is 0.3 apart) would otherwise take any color in. Of 40 random shapes drawn
    /// on the parrots and lighthouse books (`Tests/Corpus`), 0.06 added 5 paints and 0, 0.04 added
    /// 34 and 1 for about as many pieces given another paint; uncapped, none.
    static let paintToleranceLimit: Float = 3 * SegmentationParameters.jnd
}

extension EditWork {
    /// Gives the pieces the lines of this edit cut (`summary.pieces`) the photo's colors: a paint
    /// whose point lies in such a piece gives it the paint nearest its color within
    /// `TemplateEditor.paintTolerance` (the piece's own paint when that is nearest), else a new
    /// paint of that color, added last so no other number changes. The first paint to land in a
    /// piece decides it. A piece keeps the paint it has where the one it would take is a
    /// neighbour's across an undrawn edge (one area to the eye, with two numbers), or where its
    /// number has no room for the new paint's digits.
    mutating func paint(_ paints: [TemplateEditor.Paint]) throws {
        guard !paints.isEmpty, !summary.pieces.isEmpty else { return }
        let tolerance = TemplateEditor.paintTolerance(t.palette)
        var decided = Set<Int>()
        for paint in paints {
            let c = paint.color
            guard paint.at.x.isFinite, paint.at.y.isFinite, c.x.isFinite, c.y.isFinite, c.z.isFinite,
                  let r = locate(Lattice.clampedPoint(paint.at)), summary.pieces.contains(r), regionAlive[r],
                  decided.insert(r).inserted
            else { continue }
            let color = pointwiseMin(pointwiseMax(c, SIMD3(0, -0.5, -0.5)), SIMD3(1, 0.5, 0.5))
            let current = Int(t.regions[r].colorIndex)
            var nearest = current
            var distance = current < t.palette.count ? ColorScience.distance(t.palette[current].oklab, color) : .infinity
            for (k, p) in t.palette.enumerated() {
                let d = ColorScience.distance(p.oklab, color)
                if d < distance { nearest = k; distance = d }
            }
            let fresh = distance > tolerance
            let target = fresh ? t.palette.count : nearest
            guard target != current, fresh || !hasUndrawnNeighbour(r, painted: UInt32(target)) else { continue }
            guard let plan = labelPlan(
                rings: polygons(of: r), color: UInt32(target), detail: regionDetail[r], hints: hints(from: [r]), region: r,
                keepOut: freshInk[r] ?? []),
                  !plan.needsDetail
            else { continue }
            if fresh {
                t.palette.append(PaletteColor(oklab: color, space: t.colorSpace))
                summary.paintsAdded += 1
            }
            t.regions[r].colorIndex = UInt32(target)
            labels[r] = plan.labels
            regionTouched[r] = true
            refreshColorWeights(around: r)
            summary.touched.insert(r)
            summary.recolored += 1
        }
    }

    /// Whether a region across an undrawn edge of `r` has paint `paint`.
    func hasUndrawnNeighbour(_ r: Int, painted paint: UInt32) -> Bool {
        for ring in ringsOf(r) {
            for ref in ring.refs {
                let e = Int(ref.edge)
                guard !edgeDead[e], !isInked(e), let other = right(e) else { continue }
                let across = left(e) == r ? other : left(e)
                if across != r, t.regions[across].colorIndex == paint { return true }
            }
        }
        return false
    }
}
