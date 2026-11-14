/// The pixels a line runs through, by the distance from each pixel's centre to the line, with
/// nothing from a rasterizer: `line_mask` in `making_of_exact.py`, the same pixels. It stands in for
/// the rasterized drawing where the show must decide something from where lines run (where the
/// fuses burn, `FieldPlan.burn`), since anti-aliasing differs between rasterizers.
struct LineMask: Sendable, Equatable {
    /// 1 where a line runs, else 0.
    var plane: Plane<UInt8>

    /// The pixels whose centre is within `halfWidth` of a stroke (`line_mask(..., half_width)`).
    init(width: Int, height: Int, strokes: [Polyline], halfWidth half: Double) {
        var plane = Plane<UInt8>(width: width, height: height, repeating: 0)
        let near = half * half
        for stroke in strokes {
            for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
                let x0 = max(truncated((min(a.x, b.x) - half).rounded(.down)) - 1, 0)
                let x1 = min(truncated((max(a.x, b.x) + half).rounded(.down)) + 2, width)
                let y0 = max(truncated((min(a.y, b.y) - half).rounded(.down)) - 1, 0)
                let y1 = min(truncated((max(a.y, b.y) + half).rounded(.down)) + 2, height)
                guard x0 < x1, y0 < y1 else { continue }
                let vx = b.x - a.x, vy = b.y - a.y
                let length2 = vx * vx + vy * vy
                for y in y0..<y1 {
                    let py = Double(y) + 0.5
                    for x in x0..<x1 {
                        let px = Double(x) + 0.5
                        var t = 0.0
                        if length2 > 0 { t = min(max(((px - a.x) * vx + (py - a.y) * vy) / length2, 0), 1) }
                        let dx = px - (a.x + t * vx), dy = py - (a.y + t * vy)
                        if dx * dx + dy * dy <= near { plane.data[y * width + x] = 1 }
                    }
                }
            }
        }
        self.plane = plane
    }
}
