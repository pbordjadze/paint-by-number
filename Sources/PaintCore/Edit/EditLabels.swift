import Foundation

extension TemplateEditor {
    /// The number Move Number (`Edit.moveLabel`) grabs at `point` (canvas units): the label
    /// nearest it, over every region, whose circle grown by `reach` holds it; of labels as near,
    /// the first in region and label order. Nil when none does. The app draws the held number
    /// from it, so it is the edit's own rule: `point` quantized and `reach` held as the edit's are.
    public static func labelNear(on template: Template, at point: SIMD2<Float>, reach: Float) -> (region: Int, label: Label)? {
        guard point.x.isFinite, point.y.isFinite,
              let hit = nearestLabel(
                in: template.regions.indices, labels: { Array(template.labels(ofRegion: $0)) },
                at: Lattice.position(Lattice.clampedPoint(point)), reach: labelReach(reach))
        else { return nil }
        return (hit.region, Array(template.labels(ofRegion: hit.region))[hit.index])
    }

    /// The label nearest `point` among `regions`' (`labels` gives each one's), within its radius
    /// and `reach`: its region and its index among the region's labels.
    static func nearestLabel(
        in regions: some Sequence<Int>, labels: (Int) -> [Label], at point: SIMD2<Float>, reach: Float
    ) -> (region: Int, index: Int)? {
        var nearest: (region: Int, index: Int, distance: Float)?
        for r in regions {
            for (k, label) in labels(r).enumerated() {
                let d = simdLength(label.position - point)
                if d <= label.radius + reach, nearest == nil || d < nearest!.distance { nearest = (r, k, d) }
            }
        }
        return nearest.map { ($0.region, $0.index) }
    }

    /// Move Number's reach, canvas units: held between 0 and 1024 and to the lattice, as a
    /// reshape's is (`latticeReach`).
    static func labelReach(_ reach: Float) -> Float { Float(latticeReach(reach)) / Float(Lattice.unit) }
}

extension EditWork {
    /// The numbers of a region of a given outline and paint.
    struct LabelPlan {
        var labels: [Label]
        /// The room found is short of the usual floor but holds a detail area's number: the
        /// region must be one (`Template.detailRegions`).
        var needsDetail: Bool
    }

    static func flatPolygon(_ rings: [[LatticePoint]]) -> FlatPolygon {
        var poly = FlatPolygon()
        for ring in rings {
            poly.points.append(contentsOf: ring.map { SIMD2<Double>(Lattice.double($0)) })
            poly.closeRing()
        }
        return poly
    }

    /// Where the numbers of a region with these `rings` go. The first label is the most
    /// spacious spot of the outline (`PolyLabel`, measured as the vectorizer does), kept where it
    /// was (`hints`, the labels of the regions this one replaces, best first) while that spot
    /// still has most of the room, and clear of `keepOut`, the lines this edit left inside the
    /// region, where the room there still holds a legible number (`LabelKeepOut`). Hints that
    /// are far enough from the others and still roomy stay as further labels. Nil when no
    /// spot holds even a detail area's number.
    func labelPlan(
        rings: [[LatticePoint]], color: UInt32, detail: Bool, hints: [Label], region: Int, keepOut lines: [[SIMD2<Float>]]
    ) -> LabelPlan? {
        let poly = Self.flatPolygon(rings)
        guard let outer = poly.ringStarts.count > 1 ? poly.ringStarts[1] : nil, outer >= 3 else { return nil }
        let digits = LabelSizing.digitCount(colorIndex: color)
        let usual = Double(LabelSizing.minimumRadius(digits: digits))
        let floor = Double(LabelSizing.minimumRadius(digits: digits, detail: true))
        let keepOut = LabelKeepOut(rects: [], lines: lines.map(LabelKeepOut.Line.init))

        var seed = SIMD2<Double>(repeating: 0)
        for i in 0..<outer { seed += poly.points[i] }
        seed /= Double(outer)
        if let hint = hints.first { seed = SIMD2(Double(hint.position.x), Double(hint.position.y)) }

        func pole(_ keepOut: LabelKeepOut, seed: SIMD2<Double>) -> (position: SIMD2<Double>, distance: Double) {
            var found = PolyLabel.find(poly, precision: Vectorizer.labelPrecision, seed: seed, keepOut: keepOut)
            if found.distance < Double(Vectorizer.smallRegionRadius) {
                found = PolyLabel.find(poly, precision: Vectorizer.smallRegionLabelPrecision, seed: seed, keepOut: keepOut)
            }
            return found
        }
        var best = pole(LabelKeepOut(rects: []), seed: seed)
        var needsDetail = false
        if !detail && best.distance < usual {
            guard best.distance >= floor else { return nil }
            needsDetail = true
        } else if detail && best.distance < floor {
            return nil
        }
        let required = detail || needsDetail ? floor : usual
        if !keepOut.isEmpty, keepOut.distance(best.position.x, best.position.y) < best.distance {
            let moved = pole(keepOut, seed: best.position)
            if moved.distance >= required { best = moved }
        }

        func room(_ p: SIMD2<Float>) -> Double {
            min(poly.signedDistance(Double(p.x), Double(p.y)), keepOut.distance(Double(p.x), Double(p.y)))
        }
        var labels: [Label] = []
        if let hint = hints.first(where: { room($0.position) >= max(required, 0.85 * best.distance) }) {
            labels.append(Label(position: hint.position, radius: Float(room(hint.position)), region: UInt32(region)))
        } else {
            labels.append(Label(position: SIMD2<Float>(best.position), radius: Float(best.distance), region: UInt32(region)))
        }
        let spacing = Double(labelSpacing)
        var areaPixels = 0.0
        for k in 0..<poly.ringCount { areaPixels += poly.area2(ring: k) / 2 }
        let cap = min(64, Int(areaPixels / (spacing * spacing * 0.6)))
        for hint in hints where labels.count - 1 < cap && !labels.contains(where: { $0.position == hint.position }) {
            let free = room(hint.position)
            guard free >= max(required, 0.85 * Double(hint.radius)) else { continue }
            let far = labels.allSatisfy { simdLength(SIMD2<Double>($0.position) - SIMD2<Double>(hint.position)) >= spacing }
            if far { labels.append(Label(position: hint.position, radius: Float(free), region: UInt32(region))) }
        }
        return LabelPlan(labels: labels, needsDetail: needsDetail)
    }

    /// The largest a number is drawn, its font size as a share of the canvas's shorter side: the
    /// Metal canvas's cap (`LabelSizing.canvasMaximumFraction`), the largest of the renderers'
    /// (print and thumbnails cap lower). Move Number keeps a number's drawn disc off another's by it.
    static let largestNumberFraction = LabelSizing.canvasMaximumFraction

    /// Refine's Move Number (`TemplateEditor.Edit.moveLabel`): the number nearest `from`, within
    /// its radius and `reach` (`TemplateEditor.nearestLabel`), goes to `to` when that lies inside
    /// its own region and a number of its digits fits there (a detail area's by its own floor),
    /// kept off the strokes drawn in the region as numbers are (`LabelKeepOut`) and clear of the
    /// region's other numbers: no two of their circles overlap, each circle its radius but at
    /// most what a number drawn at the largest size (`largestNumberFraction`) fills. Its radius
    /// is the room there, never
    /// more than the region's roomiest spot gives (`PolyLabel`). The region's other numbers, its
    /// outline and fill stay as they were. A later edit that plans the region's numbers again (a
    /// cut, a join, a repaint, a reshape of its outline) keeps it there while it keeps most of the
    /// room, as it keeps any number (`labelPlan`), and may move it otherwise.
    mutating func moveLabel(from: SIMD2<Float>, to: LatticePoint, reach: Float) throws {
        let alive = t.regions.indices.filter { regionAlive[$0] }
        guard let nearest = TemplateEditor.nearestLabel(
            in: alive, labels: { labels[$0] ?? Array(t.labels(ofRegion: $0)) }, at: from, reach: reach)
        else { throw EditFailure.invalid("no number is near enough to move") }
        let r = nearest.region
        var own = labels[r] ?? Array(t.labels(ofRegion: r))
        let position = Lattice.position(to)
        guard own[nearest.index].position != position else { return }
        guard contains(r, to) == .inside else { throw EditFailure.invalid("there is no room for the number there") }
        let poly = Self.flatPolygon(polygons(of: r))
        let inked = strokes.filter { $0.alive && $0.region == r && $0.layer != LineLayer.color.rawValue }
        let keepOut = LabelKeepOut(rects: [], lines: inked.map { LabelKeepOut.Line($0.points) })
        let p = Lattice.double(to)
        var best = PolyLabel.find(poly, precision: Vectorizer.labelPrecision, seed: p, keepOut: keepOut)
        if best.distance < Double(Vectorizer.smallRegionRadius) {
            best = PolyLabel.find(poly, precision: Vectorizer.smallRegionLabelPrecision, seed: p, keepOut: keepOut)
        }
        let room = min(poly.signedDistance(p.x, p.y), keepOut.distance(p.x, p.y), best.distance)
        let digits = LabelSizing.digitCount(colorIndex: t.regions[r].colorIndex)
        guard room >= Double(LabelSizing.minimumRadius(digits: digits, detail: regionDetail[r])) else {
            throw EditFailure.invalid("there is no room for the number there")
        }
        // Each number's circle is the disc its digits are drawn in: its room, but no more than the
        // largest a renderer draws a number fills. A large area's rooms reach past each other while
        // its numbers, drawn far smaller, lie well apart.
        let cap = Self.largestNumberFraction * Float(min(t.width, t.height)) * LabelSizing.runDiagonal(digits: digits)
            / (2 * LabelSizing.fill)
        for (k, other) in own.enumerated() where k != nearest.index {
            let apart = simdLength(SIMD2<Double>(other.position) - p)
            guard apart >= min(room, Double(cap)) + Double(min(other.radius, cap)) else {
                throw EditFailure.invalid("the number would lie on another")
            }
        }
        own[nearest.index] = Label(position: position, radius: Float(room), region: UInt32(r))
        labels[r] = own
        summary.labelsMoved += 1
        summary.touched.insert(r)
    }

    /// Hints for a region taking over from `regions`: their labels, the largest region's first.
    func hints(from regions: [Int]) -> [Label] {
        regions.sorted { area(of: $0) != area(of: $1) ? area(of: $0) > area(of: $1) : $0 < $1 }.flatMap { r -> [Label] in
            labels[r] ?? (r < t.regions.count && t.regions[r].labelCount > 0 ? Array(t.labels(ofRegion: r)) : [])
        }
    }
}
