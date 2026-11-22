extension Template {
    /// The template seen in a mirror, left for right (painting-company row 375: a woodblock is
    /// carved mirrored, so the print comes out the right way round). Every convention holds: each
    /// edge's points run backwards, so its `left` region stays on its left; each ring takes its
    /// edges in the opposite order, so outer rings still run clockwise on screen; each triangle
    /// swaps two corners. Coordinates stay on `coordinateQuantum`, and `mirrored().mirrored()`
    /// is the template again.
    public func mirrored() -> Template {
        let w = Float(width)
        func flip(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(w - p.x, p.y) }

        var newPoints: [SIMD2<Float>] = []
        newPoints.reserveCapacity(points.count)
        var newEdges = edges
        for (i, e) in edges.enumerated() {
            let start = newPoints.count
            for p in self.points(of: e).reversed() { newPoints.append(flip(p)) }
            newEdges[i].pointStart = UInt32(start)
        }
        var newRingEdges = ringEdges
        for ring in rings {
            let lo = Int(ring.edgeStart), hi = lo + Int(ring.edgeCount)
            guard hi <= ringEdges.count else { continue }
            newRingEdges.replaceSubrange(lo..<hi, with: ringEdges[lo..<hi].reversed())
        }

        var mesh = self.mesh
        mesh.vertices = mesh.vertices.map(flip)
        for t in stride(from: 0, to: mesh.indices.count - 2, by: 3) { mesh.indices.swapAt(t + 1, t + 2) }

        var map = regionMap
        for y in 0..<map.height {
            for x in 0..<map.width / 2 {
                let a = y * map.width + x, b = y * map.width + map.width - 1 - x
                map.storage.swapAt(a, b)
            }
        }

        var out = self
        out.points = newPoints
        out.edges = newEdges
        out.ringEdges = newRingEdges
        out.mesh = mesh
        out.regionMap = map
        out.labels = labels.map { Label(position: flip($0.position), radius: $0.radius, region: $0.region) }
        out.regions = regions.map { r in
            var r = r
            if !r.bounds.isEmpty {
                r.bounds = PixelBounds(minX: Int32(width) - r.bounds.maxX, minY: r.bounds.minY,
                                       maxX: Int32(width) - r.bounds.minX, maxY: r.bounds.maxY)
            }
            return r
        }
        if var lines = lineArt {
            lines.strokePoints = lines.strokePoints.map(flip)
            out.lineArt = lines
        }
        return out
    }

    /// The template with its paints in a new order: paint `order[k]` becomes paint `k`, and every
    /// region follows its paint. `order` must be a permutation of the palette's indices.
    public func reorderingPalette(_ order: [Int]) -> Template {
        precondition(order.count == palette.count && Set(order) == Set(palette.indices), "not a permutation")
        var rank = [UInt32](repeating: 0, count: palette.count)
        for (k, p) in order.enumerated() { rank[p] = UInt32(k) }
        var out = self
        out.palette = order.map { palette[$0] }
        out.regions = regions.map { r in
            var r = r
            if Int(r.colorIndex) < rank.count { r.colorIndex = rank[Int(r.colorIndex)] }
            return r
        }
        return out
    }

    /// The template with each region's primary label alone (its pole): a printer marks an area
    /// of the kyōgō once, where the canvas would spread a big region's number across it.
    public func primaryLabelsOnly() -> Template {
        var out = self
        var kept: [Label] = []
        kept.reserveCapacity(regions.count)
        out.regions = regions.map { r in
            var r = r
            let start = Int(r.labelStart)
            if r.labelCount > 0, start < labels.count {
                r.labelStart = UInt32(kept.count)
                r.labelCount = 1
                kept.append(labels[start])
            } else {
                r.labelStart = UInt32(kept.count)
                r.labelCount = 0
            }
            return r
        }
        out.labels = kept
        return out
    }

    /// The template with each cell of its drawing (the areas its drawn lines close, `TemplateLineArt`)
    /// printed in few paints: a paint holding less than `minorShare` of its cell takes the
    /// cell's main paint, so no speck or island of colour lies where no line drew it, unless
    /// it is lighter or darker than that paint by `keepContrast` (an eye's white, a shadow's
    /// black). A template without line art is as it was.
    public func flattenedToCells(minorShare: Float, keepContrast: Float) -> Template {
        guard let art = lineArt, art.edgeLayers.count == edges.count, !regions.isEmpty else { return self }
        var cells = DisjointSet(count: regions.count)
        for (i, e) in edges.enumerated() where !LineLayer.isDrawn(art.edgeLayers[i]) {
            let a = Int(e.left), b = Int(e.right)
            guard a < regions.count, b < regions.count, a != b else { continue }
            let ra = cells.find(a), rb = cells.find(b)
            if ra != rb { cells.parent[max(ra, rb)] = min(ra, rb) }
        }
        var share: [Int: [UInt32: Float]] = [:]
        var total: [Int: Float] = [:]
        for (r, region) in regions.enumerated() {
            let c = cells.find(r)
            share[c, default: [:]][region.colorIndex, default: 0] += region.area
            total[c, default: 0] += region.area
        }
        var out = self
        for r in regions.indices {
            let c = cells.find(r)
            guard let paints = share[c], let sum = total[c], sum > 0,
                  let main = paints.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key,
                  (paints[regions[r].colorIndex] ?? 0) < minorShare * sum,
                  Int(main) < palette.count, Int(regions[r].colorIndex) < palette.count,
                  abs(palette[Int(main)].oklab.x - palette[Int(regions[r].colorIndex)].oklab.x) < keepContrast
            else { continue }
            out.regions[r].colorIndex = main
        }
        return out
    }
}
