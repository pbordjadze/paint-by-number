/// The outline of each piece's glass inside its lead (painting-company row 366): the app lays a
/// pane of real glass on each glazed piece, and a pane must stay off the lead, which bends and
/// tints under glass. Traced from the same distance field the canvas casts the lead from
/// (`GlassTexture`), so a pane follows the lead exactly, joints and slivers too, where a pane
/// inset from the vector rings by path arithmetic left shards and hairlines across the came.
public enum GlassPaneOutlines {
    /// How far inside the lead's middle a pane's edge sits, as a share of the lead's width: past
    /// the came's widest (the canvas casts it 0.4 to 0.6 of the width each side), so no glass lies
    /// over the lead.
    public static let insetShare: Float = 0.62

    /// Each piece's pane in canvas units: its rings, each a closed polygon (the last point joins
    /// the first); outer rings clockwise on screen (y down), holes the other way, so a path of them
    /// fills right by either rule. None for a piece the lead covers whole, or nearly.
    ///
    /// A pane is every pixel of its piece more than `inset` canvas units from the lead's middle
    /// (the edge between pieces), traced along the pixels' cracks, simplified to a pixel and
    /// its corners cut twice, by up to three pixels, so a staircase becomes a smooth glass edge. A shape under
    /// `minimumArea` square units is a shard and dropped. The lead round an island piece is a
    /// hole in the pane round it.
    public static func outlines(of t: Template, texture: GlassTexture, inset: Float, minimumArea: Float) -> [[[SIMD2<Float>]]] {
        let w = t.width, h = t.height
        var out = [[[SIMD2<Float>]]](repeating: [], count: t.regions.count)
        guard w > 0, h > 0, texture.width == w, texture.height == h else { return out }
        let pieces = t.regions.count
        // 0: the lead and what lies within `inset` of it; r + 1: piece r's glass.
        var classes = Grid<UInt32>(width: w, height: h, repeating: 0)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let r = Int(t.regionMap[x, y])
                // The field is 1 on a piece's edge pixel; the edge itself lies half a pixel out.
                if r < pieces, texture.lead[i] - 0.5 > inset { classes.storage[i] = UInt32(r + 1) }
            }
        }
        let components = ConnectedComponents.label(classes)
        let labels = components.labels.storage
        let count = components.count
        var first = [Int](repeating: -1, count: count)
        var touchesBorder = [Bool](repeating: false, count: count)
        for y in 0..<h {
            for x in 0..<w {
                let k = Int(labels[y * w + x])
                if first[k] < 0 { first[k] = y * w + x }
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { touchesBorder[k] = true }
            }
        }
        for k in 0..<count where first[k] >= 0 {
            let piece = Int(components.classOf[k]) - 1
            if piece >= 0 {
                guard Float(components.area[k]) >= minimumArea else { continue }
                let ring = smoothed(MaskContours.trace(labels, label: UInt32(k), start: first[k], width: w, height: h))
                if ring.count >= 3 { out[piece].append(ring) }
            } else if !touchesBorder[k] {
                // Lead closed on itself: round an island piece, a hole in the pane round it. The
                // pixel above its first is outside it, so it is that pane's.
                let above = first[k] - w
                guard above >= 0 else { continue }
                let owner = Int(components.classOf[Int(labels[above])]) - 1
                guard owner >= 0 else { continue }
                let ring = smoothed(MaskContours.trace(labels, label: UInt32(k), start: first[k], width: w, height: h))
                if ring.count >= 3 { out[owner].append(ring.reversed()) }
            }
        }
        return out
    }

    /// A traced staircase simplified to a pixel, its corners cut twice (Chaikin's, held short).
    static func smoothed(_ corners: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard corners.count >= 3 else { return corners }
        // Simplified as an open run back to its start, so the first corner is kept.
        let open = corners + [corners[0]]
        var ring = LayeredLines.simplify(open, epsilon: 1).map { open[$0] }
        if ring.count > 1, ring.first == ring.last { ring.removeLast() }
        guard ring.count >= 3 else { return ring }
        // Each corner cut a quarter of the way along its sides, but never more than `cut`, so a
        // long straight edge keeps its corner where the lead turns.
        for cut: Float in [3, 1.5] {
            var next: [SIMD2<Float>] = []
            next.reserveCapacity(ring.count * 2)
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let d = b - a, length = (d.x * d.x + d.y * d.y).squareRoot()
                guard length > 0 else { continue }
                let k = min(0.25, cut / length)
                next.append(a + (b - a) * k)
                next.append(b + (a - b) * k)
            }
            ring = next
        }
        return ring
    }
}
