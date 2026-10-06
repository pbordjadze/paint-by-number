/// Where numbers must not go: the writing a template draws (`Writing.keepOut`), whose words a
/// number on top would make unreadable. Rectangles in canvas units (min x, min y, max x, max y).
///
/// A region's number moves off them to the spot of its polygon farthest from both its outline
/// and the rectangles (`PolyLabel.find(_:precision:seed:keepOut:)`), sized for the room it has
/// there, when that room still holds a legible number (`LabelSizing.minimumRadius(digits:)`) and
/// the room the vectorizer promised it (`LabelRoom`); otherwise it stays at its pole. Extra
/// labels are only placed off them.
struct LabelKeepOut: Sendable {
    var rects: [SIMD4<Float>]

    var isEmpty: Bool { rects.isEmpty }

    /// Distance from (x, y) to the nearest rectangle: negative inside one (minus the distance to
    /// its edge), infinity without rectangles.
    func distance(_ x: Double, _ y: Double) -> Double {
        var best = Double.infinity
        for r in rects {
            let dx = max(Double(r.x) - x, x - Double(r.z)), dy = max(Double(r.y) - y, y - Double(r.w))
            let d = dx > 0 || dy > 0 ? (max(dx, 0) * max(dx, 0) + max(dy, 0) * max(dy, 0)).squareRoot() : max(dx, dy)
            best = min(best, d)
        }
        return best
    }

    /// Moves the labels that overlap the rectangles (see the type's comment).
    func move(_ poles: inout LabelPoles, shapes: RegionShapes, room: LabelRoom, regionColor: [UInt32]) {
        guard !isEmpty else { return }
        var poly = FlatPolygon()
        for r in poles.position.indices {
            let p = poles.position[r]
            guard distance(Double(p.x), Double(p.y)) < Double(poles.radius[r]) else { continue }
            shapes.polygon(r, into: &poly)
            let digits = LabelSizing.digitCount(colorIndex: regionColor[r])
            let need = Double(max(room.minRadius[r], LabelSizing.minimumRadius(digits: digits)))
            let found = PolyLabel.find(poly, precision: Vectorizer.labelPrecision, seed: SIMD2(Double(p.x), Double(p.y)), keepOut: self)
            guard found.distance >= need else { continue }
            poles.position[r] = SIMD2<Float>(found.position)
            poles.radius[r] = Float(found.distance)
        }
    }
}
