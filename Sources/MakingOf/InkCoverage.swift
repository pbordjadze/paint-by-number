/// How much ink a set of lines puts on each pixel: the reference rasterizer behind
/// `FieldShow.composite`, that a view's Core Graphics strokes are meant to look like. A pixel is covered
/// by a line as far as its center is within half the width of the line, softened over one pixel
/// (full at half a pixel inside the edge, none at half a pixel outside), and by the line's `value`;
/// where lines meet, the darker one wins. Segments join round, and a line ends round, because the
/// distance is taken to the segments themselves.
///
/// Only `+ - *` and `sqrt` on Doubles, in a fixed order: `ink_coverage` in `making_of_show.py`
/// gives the same numbers, bit for bit.
enum InkCoverage {
    static func plane(_ lines: [InkLine], width: Int, height: Int, lineWidth: Double) -> Plane<Float> {
        var coverage = [Double](repeating: 0, count: width * height)
        let half = lineWidth / 2
        let reach = half + 0.5
        for line in lines {
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let x0 = max(truncated((min(a.x, b.x) - reach).rounded(.down)), 0)
                let x1 = min(truncated((max(a.x, b.x) + reach).rounded(.down)) + 1, width)
                let y0 = max(truncated((min(a.y, b.y) - reach).rounded(.down)), 0)
                let y1 = min(truncated((max(a.y, b.y) + reach).rounded(.down)) + 1, height)
                guard x0 < x1, y0 < y1 else { continue }
                let (vx, vy) = (b.x - a.x, b.y - a.y)
                let lengthSquared = vx * vx + vy * vy
                for y in y0..<y1 {
                    let py = Double(y) + 0.5
                    for x in x0..<x1 {
                        let px = Double(x) + 0.5
                        let along = lengthSquared > 0 ? min(max(((px - a.x) * vx + (py - a.y) * vy) / lengthSquared, 0), 1) : 0
                        let (dx, dy) = (px - (a.x + along * vx), py - (a.y + along * vy))
                        let covered = min(max(reach - (dx * dx + dy * dy).squareRoot(), 0), 1) * line.value
                        if covered > coverage[y * width + x] { coverage[y * width + x] = covered }
                    }
                }
            }
        }
        return Plane(width: width, height: height, data: coverage.map { Float($0) })
    }
}
