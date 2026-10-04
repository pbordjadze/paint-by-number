import Foundation

/// The outlines of the shapes in a mask (a subject mask from the app's Vision request, a PGM
/// handed to `pbn --objects`), as the closed polygons `LineArtInput.objects` takes.
public enum MaskContours {
    /// Shapes smaller than this share of the mask are specks, not subjects.
    public static let minimumArea: Float = 0.015
    /// Corners within this many mask pixels of the line between their neighbours are dropped
    /// (Douglas–Peucker), so a pixel staircase becomes a straight or gently curved edge.
    public static let tolerance: Float = 1
    public static let quantum: Float = 4096

    /// The outer boundary of every 4-connected shape of `mask` (true = inside) covering at
    /// least `minimumArea` of it, largest first, as closed polygons normalized to the mask
    /// (0...1, origin top-left, pixel corners at x / width; the last point joins the first),
    /// simplified to `tolerance` and quantized to 1 / `quantum`. Holes are not traced: a
    /// subject's silhouette is what closes it off.
    public static func outlines(
        of mask: [Bool], width w: Int, height h: Int, minimumArea: Float = minimumArea
    ) -> [[SIMD2<Float>]] {
        precondition(mask.count == w * h, "MaskContours: mask size")
        guard w > 0, h > 0 else { return [] }
        let components = ConnectedComponents.label(
            Grid(width: w, height: h, storage: mask.map { $0 ? UInt32(1) : 0 }))
        let labels = components.labels.storage
        let least = Int((minimumArea * Float(w * h)).rounded(.up))
        var shapes: [(label: Int, area: Int, first: Int)] = []
        for label in components.area.indices where components.classOf[label] == 1 && components.area[label] >= max(least, 1) {
            shapes.append((label, components.area[label], labels.firstIndex(of: UInt32(label)) ?? 0))
        }
        // Largest first; the earlier shape on ties, so the order never depends on hashing.
        shapes.sort { $0.area != $1.area ? $0.area > $1.area : $0.first < $1.first }
        return shapes.map { shape in
            let corners = trace(labels, label: UInt32(shape.label), start: shape.first, width: w, height: h)
            let kept = LayeredLines.simplify(corners, epsilon: tolerance).map { corners[$0] }
            let polygon = kept.count >= 3 ? kept : corners
            return polygon.map { p in
                SIMD2(
                    (min(max(p.x / Float(w), 0), 1) * quantum).rounded() / quantum,
                    (min(max(p.y / Float(h), 0), 1) * quantum).rounded() / quantum)
            }
        }
    }

    /// Walks the outer boundary of the shape `label` along the cracks between its pixels,
    /// the shape on the right hand, from the top-left corner of its first pixel (in raster
    /// order, so the topmost row's leftmost pixel) heading right, until it is back there: the
    /// corners where the walk turns, in pixel-corner coordinates.
    static func trace(_ labels: [UInt32], label: UInt32, start: Int, width w: Int, height h: Int) -> [SIMD2<Float>] {
        func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && labels[y * w + x] == label }
        // The pixel ahead on the right (or left) of the vertex (x, y) when heading (dx, dy):
        // its corner at the vertex, so its index is the vertex moved back by negative steps.
        func ahead(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int, right: Bool) -> Bool {
            let rx = right ? -dy : dy, ry = right ? dx : -dx
            return inside(x + min(dx, 0) + min(rx, 0), y + min(dy, 0) + min(ry, 0))
        }
        let x0 = start % w, y0 = start / w
        var x = x0, y = y0, dx = 1, dy = 0
        var corners: [SIMD2<Float>] = [SIMD2(Float(x0), Float(y0))]
        // A boundary of n pixels has at most 4n cracks; the bound only guards a corrupt mask.
        for _ in 0..<(8 * w * h + 8) {
            if ahead(x, y, dx, dy, right: false) {
                // The shape bulges ahead on the left: turn left.
                (dx, dy) = (dy, -dx)
                corners.append(SIMD2(Float(x), Float(y)))
            } else if ahead(x, y, dx, dy, right: true) {
                x += dx
                y += dy
            } else {
                // The shape ends ahead: turn right.
                (dx, dy) = (-dy, dx)
                corners.append(SIMD2(Float(x), Float(y)))
            }
            if x == x0 && y == y0 && dx == 1 && dy == 0 { break }
        }
        // Consecutive turns at one vertex repeat it; a polygon lists each corner once.
        var out: [SIMD2<Float>] = []
        for c in corners where out.last != c { out.append(c) }
        if out.count > 1, out.first == out.last { out.removeLast() }
        return out
    }
}
