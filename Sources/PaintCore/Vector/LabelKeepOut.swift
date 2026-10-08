/// Where numbers must not go: the writing a template draws (`Writing.keepOut`), whose words a
/// number on top would make unreadable, and the lines the painter drew inside cells
/// (`LayeredLines.Plan.drawnInterior`), which would cross a number out. Rectangles in canvas units
/// (min x, min y, max x, max y), lines as canvas-unit polylines.
///
/// A region's number moves off them to the spot of its polygon farthest from both its outline
/// and the keep-out (`PolyLabel.find(_:precision:seed:keepOut:)`), sized for the room it has
/// there, when that room still holds a legible number (`LabelSizing.minimumRadius(digits:)`) and
/// the room the vectorizer promised it (`LabelRoom`); otherwise it stays at its pole. Extra
/// labels are only placed off them, and not where a drawn line would squeeze one
/// (`RegionFills.addExtraLabels`).
struct LabelKeepOut: Sendable {
    var rects: [SIMD4<Float>]
    var lines: [Line] = []

    /// A polyline and its bounds, which spare a far line's segments.
    struct Line: Sendable {
        let points: [SIMD2<Float>]
        let bounds: SIMD4<Float>

        init(_ points: [SIMD2<Float>]) {
            self.points = points
            var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
            for p in points { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            bounds = SIMD4(lo.x, lo.y, hi.x, hi.y)
        }
    }

    /// Half a drawn line's ink, in canvas units: the book draws its lines 1.5 points wide fitted
    /// to the screen, about 3 units of a large canvas on an iPad, and thinner zoomed in, where
    /// numbers are read.
    static let lineHalfWidth = 1.5

    var isEmpty: Bool { rects.isEmpty && lines.isEmpty }

    /// Distance from (x, y) to the nearest rectangle or line's ink: negative inside one (minus
    /// the distance to its edge), infinity without any.
    func distance(_ x: Double, _ y: Double) -> Double {
        var best = Double.infinity
        for r in rects {
            let dx = max(Double(r.x) - x, x - Double(r.z)), dy = max(Double(r.y) - y, y - Double(r.w))
            let d = dx > 0 || dy > 0 ? (max(dx, 0) * max(dx, 0) + max(dy, 0) * max(dy, 0)).squareRoot() : max(dx, dy)
            best = min(best, d)
        }
        return min(best, lineDistance(x, y, below: best))
    }

    /// Distance from (x, y) to the nearest line's ink, negative on it, or `below` when no line
    /// is nearer than that (lines farther by their bounds are skipped).
    func lineDistance(_ x: Double, _ y: Double, below limit: Double = .infinity) -> Double {
        var best = limit
        let p = SIMD2(Float(x), Float(y))
        for line in lines {
            let b = line.bounds
            let bx = max(Double(b.x) - x, x - Double(b.z), 0), by = max(Double(b.y) - y, y - Double(b.w), 0)
            guard (bx * bx + by * by).squareRoot() - Self.lineHalfWidth < best, var a = line.points.first else { continue }
            var nearest = simdLengthSquared(p - a)
            for q in line.points.dropFirst() {
                let ab = q - a
                let s = min(max(simdDot(p - a, ab) / max(simdLengthSquared(ab), 1e-12), 0), 1)
                nearest = min(nearest, simdLengthSquared(p - (a + ab * s)))
                a = q
            }
            best = min(best, Double(nearest.squareRoot()) - Self.lineHalfWidth)
        }
        return best
    }

    /// Moves the labels that overlap the keep-out (see the type's comment).
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
