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
    /// A split's pieces (`splitting`) are painted so, and where that leaves one paint on both
    /// sides of the split (the photo is about the same color across it), the smaller side takes a
    /// shade of that paint toward its photo color (`shade(of:toward:)`), an existing paint within
    /// a just-noticeable difference of it or else a new one: the painter asked for the area to be
    /// told apart.
    mutating func paint(_ paints: [TemplateEditor.Paint]) throws {
        if splitting { for r in summary.pieces where regionAlive[r] { refreshColorWeights(around: r) } }
        guard !paints.isEmpty, !summary.pieces.isEmpty else { return }
        let tolerance = TemplateEditor.paintTolerance(t.palette)
        var colors: [Int: SIMD3<Float>] = [:]
        for paint in paints {
            let c = paint.color
            guard paint.at.x.isFinite, paint.at.y.isFinite, c.x.isFinite, c.y.isFinite, c.z.isFinite,
                  let r = locate(Lattice.clampedPoint(paint.at)), summary.pieces.contains(r), regionAlive[r],
                  colors[r] == nil
            else { continue }
            let color = pointwiseMin(pointwiseMax(c, SIMD3(0, -0.5, -0.5)), SIMD3(1, 0.5, 0.5))
            colors[r] = color
            let current = Int(t.regions[r].colorIndex)
            var nearest = current
            var distance = current < t.palette.count ? ColorScience.distance(t.palette[current].oklab, color) : .infinity
            for (k, p) in t.palette.enumerated() {
                let d = ColorScience.distance(p.oklab, color)
                if d < distance { nearest = k; distance = d }
            }
            let fresh = distance > tolerance
            guard fresh || nearest != current, fresh || !hasUndrawnNeighbour(r, painted: UInt32(nearest)) else { continue }
            recolor(r, to: fresh ? t.palette.count : nearest, adding: fresh ? color : nil)
        }
        guard splitting else { return }
        for e in splitEdges where !edgeDead[e] {
            guard let b = right(e) else { continue }
            let a = left(e)
            guard a != b, t.regions[a].colorIndex == t.regions[b].colorIndex else { continue }
            let (areaA, areaB) = (area(of: a), area(of: b))
            let smaller = areaA != areaB ? (areaA < areaB ? a : b) : max(a, b)
            // The larger side takes the shade where the smaller has no room for its number.
            for r in [smaller, smaller == a ? b : a] {
                if let color = colors[r], shadeSplit(r, toward: color) { break }
            }
        }
    }

    /// Paints `r`, one side of a split whose other side has its paint, a shade of that paint
    /// toward `color` (`shade(of:toward:step:)`): an existing paint within a just-noticeable
    /// difference of the shade or else a new one, a step farther out each time a shade lands on a
    /// paint a neighbour across an undrawn edge has, or has no room for its number. False when no
    /// shade fits.
    mutating func shadeSplit(_ r: Int, toward color: SIMD3<Float>) -> Bool {
        let shared = t.regions[r].colorIndex, paint = t.palette[Int(shared)].oklab
        // The first try is the photo's color where that is a step away; each next one a step past it.
        let first = max(ColorScience.distance(paint, color), Self.splitShadeStep)
        for steps in [0, 1, 2] {
            let shade = Self.shade(of: paint, toward: color, step: first + Float(steps) * Self.splitShadeStep)
            var nearest = -1, distance = Float.infinity
            for (k, p) in t.palette.enumerated() where k != Int(shared) {
                let d = ColorScience.distance(p.oklab, shade)
                if d < distance { nearest = k; distance = d }
            }
            if nearest < 0 || distance > SegmentationParameters.jnd {
                if recolor(r, to: t.palette.count, adding: shade) { return true }
            } else if !hasUndrawnNeighbour(r, painted: UInt32(nearest)) {
                if recolor(r, to: nearest, adding: nil) { return true }
            }
        }
        return false
    }

    /// How far a split's shade (`shade(of:toward:)`) is from the paint it parts from: half again a
    /// just-noticeable difference, the least that reads as another paint on the canvas.
    static let splitShadeStep: Float = 1.5 * SegmentationParameters.jnd

    /// A shade of `paint` toward `photo` (OKLab) at least `step` from it: the photo's
    /// own color where it is farther, else `paint` moved that far toward it (away from it where
    /// that would pass white or black); where the photo is `paint`'s own color, lighter (darker
    /// for a paint already near white).
    static func shade(of paint: SIMD3<Float>, toward photo: SIMD3<Float>, step: Float = splitShadeStep) -> SIMD3<Float> {
        let away = photo - paint
        let length = (away * away).sum().squareRoot()
        if length >= step { return photo }
        if length > 1e-4 {
            let toward = paint + away * (step / length)
            return (0...1).contains(toward.x) ? toward : paint - away * (step / length)
        }
        return paint + SIMD3(paint.x > 0.85 ? -step : step, 0, 0)
    }

    /// Paints region `r` with paint `target` (a new one of color `adding`, added last, when
    /// `target` is the palette's end), when its number has room for the paint's digits.
    @discardableResult
    mutating func recolor(_ r: Int, to target: Int, adding color: SIMD3<Float>?) -> Bool {
        guard let plan = labelPlan(
            rings: polygons(of: r), color: UInt32(target), detail: regionDetail[r], hints: hints(from: [r]), region: r,
            keepOut: freshInk[r] ?? []),
              !plan.needsDetail
        else { return false }
        if let color {
            t.palette.append(PaletteColor(oklab: color, space: t.colorSpace))
            summary.paintsAdded += 1
        }
        t.regions[r].colorIndex = UInt32(target)
        labels[r] = plan.labels
        regionTouched[r] = true
        refreshColorWeights(around: r)
        summary.touched.insert(r)
        summary.recolored += 1
        return true
    }

    /// A split whose new boundary has the same paint on both sides divides nothing the painter
    /// could see: two numbers on one color.
    func checkSplitPaints() throws {
        for e in splitEdges where !edgeDead[e] {
            guard let other = right(e) else { continue }
            if t.regions[left(e)].colorIndex == t.regions[other].colorIndex {
                throw EditFailure.invalid("both sides of the split have the same paint")
            }
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
