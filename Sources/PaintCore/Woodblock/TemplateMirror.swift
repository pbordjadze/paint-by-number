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
}
