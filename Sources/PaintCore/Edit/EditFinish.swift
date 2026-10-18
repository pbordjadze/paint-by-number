import Foundation

extension EditWork {
    /// What the compaction learned about the regions.
    struct Mapping {
        /// New index of the region each old region continues as (a merged region: the merged
        /// one; a split region: the piece that kept its index).
        var continued: [Int]
        var touched: [Int]
        /// New indices of the pieces drawn lines cut.
        var pieces: [Int]
    }

    /// The numbers of the regions that gained an outline vertex, checked against it: a radius
    /// is never more than the room there is, and a number short of its floor moves.
    mutating func verifyNumbers() throws {
        for r in verifyLabels.sorted() where regionAlive[r] && labels[r] == nil {
            let current = r < t.regions.count && t.regions[r].labelCount > 0 ? Array(t.labels(ofRegion: r)) : []
            guard !current.isEmpty else { continue }
            let poly = Self.flatPolygon(polygons(of: r))
            let digits = LabelSizing.digitCount(colorIndex: t.regions[r].colorIndex)
            let required = Double(LabelSizing.minimumRadius(digits: digits, detail: regionDetail[r]))
            var kept: [Label] = []
            var changed = false
            for (k, label) in current.enumerated() {
                let free = poly.signedDistance(Double(label.position.x), Double(label.position.y))
                if k == 0 || free >= required {
                    var l = label
                    if Double(l.radius) > free {
                        l.radius = Float(max(free, 0))
                        changed = true
                    }
                    kept.append(l)
                } else {
                    changed = true
                }
            }
            if let primary = kept.first, Double(primary.radius) < required - 5e-4 {
                guard let plan = labelPlan(
                    rings: polygons(of: r), color: t.regions[r].colorIndex, detail: regionDetail[r], hints: current, region: r,
                    keepOut: [])
                else { throw EditFailure.invalid("an area beside the line has no room for its number") }
                labels[r] = plan.labels
                if plan.needsDetail { regionDetail[r] = true }
            } else if changed {
                labels[r] = kept
            }
        }
    }

    /// Lays the survivors out again as a template, checking that nothing refers to what the
    /// edit removed.
    mutating func finish() throws -> (template: Template, mapping: Mapping) {
        try verifyNumbers()
        claimPixelsUnderStrokes()
        let aliveRegions = regionAlive.indices.filter { regionAlive[$0] }
        var newIndex = [Int](repeating: -1, count: regionAlive.count)
        for (n, r) in aliveRegions.enumerated() { newIndex[r] = n }

        // Triangles of the regions that need them again.
        let meshed = remesh.filter { regionAlive[$0] }.sorted()
        var topology = RingTopology()
        for r in meshed {
            topology.regionRingStart.append(UInt32(topology.rings.count))
            let rs = ringsOf(r)
            topology.regionRingCount.append(UInt32(rs.count))
            for ring in rs {
                topology.rings.append(Ring(edgeStart: UInt32(topology.ringEdges.count), edgeCount: UInt32(ring.refs.count), isHole: ring.isHole))
                topology.ringEdges.append(contentsOf: ring.refs)
            }
        }
        var fills = RegionFills()
        var vertexStart: [Int] = []
        if !meshed.isEmpty {
            let shapes = RegionShapes(points: t.points, edges: t.edges, topology: topology)
            var position: [SIMD2<Float>] = [], radius: [Float] = []
            for r in meshed {
                guard let label = labels[r]?.first ?? (t.regions[r].labelCount > 0 ? t.labels(ofRegion: r).first : nil) else {
                    throw EditFailure.invalid("a region has no number")
                }
                position.append(label.position)
                radius.append(label.radius)
            }
            do {
                fills = try RegionFills.build(shapes, poles: LabelPoles(position: position, radius: radius), width: t.width, height: t.height)
            } catch { throw EditFailure.invalid("triangulation failed") }
            var counts = [Int](repeating: 0, count: meshed.count)
            for local in fills.vertexRegion { counts[Int(local)] += 1 }
            var total = 0
            for c in counts {
                vertexStart.append(total)
                total += c
            }
        }
        var meshedIndex: [Int: Int] = [:]
        for (i, r) in meshed.enumerated() { meshedIndex[r] = i }
        var fillIndexStart: [Int] = []
        var cursor = 0
        for c in fills.indexCount {
            fillIndexStart.append(cursor)
            cursor += Int(c)
        }

        // Edges.
        let aliveEdges = t.edges.indices.filter { !edgeDead[$0] }
        var edgeNew = [Int](repeating: -1, count: t.edges.count)
        for (n, e) in aliveEdges.enumerated() { edgeNew[e] = n }
        var flip = [Bool](repeating: false, count: t.edges.count)
        var edges: [BoundaryEdge] = []
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(t.points.count)
        for e in aliveEdges {
            let l = left(e), r = right(e)
            guard regionAlive[l], r.map({ regionAlive[$0] }) ?? true, r != l else {
                throw EditFailure.collision("an edge lies between a region and itself")
            }
            var a = UInt32(newIndex[l]), b = r.map { UInt32(newIndex[$0]) } ?? BoundaryEdge.outside
            let edge = t.edges[e]
            var pts = Array(t.points[Int(edge.pointStart)..<Int(edge.pointStart) + Int(edge.pointCount)])
            if edgeDirty[e], b != BoundaryEdge.outside, a > b {
                flip[e] = true
                swap(&a, &b)
                pts.reverse()
            }
            edges.append(BoundaryEdge(left: a, right: b, pointStart: UInt32(points.count), pointCount: edge.pointCount))
            points.append(contentsOf: pts)
        }

        // Regions, in order.
        var regions: [Region] = []
        var ringEdges: [EdgeRef] = []
        var rings: [Ring] = []
        var outLabels: [Label] = []
        var mesh = FillMesh()
        var scratch: [Int32] = []
        for r in aliveRegions {
            var region = t.regions[r]
            region.ringStart = UInt32(rings.count)
            let rs = ringsOf(r)
            region.ringCount = UInt32(rs.count)
            for ring in rs {
                rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: UInt32(ring.refs.count), isHole: ring.isHole))
                for ref in ring.refs {
                    let e = Int(ref.edge)
                    guard edgeNew[e] >= 0 else { throw EditFailure.invalid("an outline uses an edge that was removed") }
                    ringEdges.append(EdgeRef(edge: UInt32(edgeNew[e]), reversed: ref.reversed != flip[e]))
                }
            }
            let own: [Label] = labels[r] ?? (r < t.regions.count && t.regions[r].labelCount > 0 ? Array(t.labels(ofRegion: r)) : [])
            guard !own.isEmpty else { throw EditFailure.invalid("a region has no number") }
            region.labelStart = UInt32(outLabels.count)
            region.labelCount = UInt32(own.count)
            for l in own { outLabels.append(Label(position: l.position, radius: l.radius, region: UInt32(newIndex[r]))) }
            if labels[r] != nil { region.inscribedRadius = own[0].radius }

            region.indexStart = UInt32(mesh.indices.count)
            if let i = meshedIndex[r] {
                let base = UInt32(mesh.vertices.count)
                let from = vertexStart[i]
                let count = (i + 1 < vertexStart.count ? vertexStart[i + 1] : fills.vertices.count) - from
                mesh.vertices.append(contentsOf: fills.vertices[from..<(from + count)])
                mesh.vertexRegion.append(contentsOf: repeatElement(UInt32(newIndex[r]), count: count))
                let lo = fillIndexStart[i], n = Int(fills.indexCount[i])
                for k in lo..<(lo + n) { mesh.indices.append(fills.indices[k] - UInt32(from) + base) }
                region.area = fills.area[i]
                region.bounds = fills.bounds[i]
                region.indexCount = UInt32(n)
            } else {
                // Copied as it was: the vertices its triangles use, in their order.
                let lo = Int(t.regions[r].indexStart), n = Int(t.regions[r].indexCount)
                var used = Set<Int32>()
                for k in lo..<(lo + n) { used.insert(Int32(t.mesh.indices[k])) }
                let sorted = used.sorted()
                if scratch.count < t.mesh.vertices.count { scratch = [Int32](repeating: 0, count: t.mesh.vertices.count) }
                let base = UInt32(mesh.vertices.count)
                for (k, v) in sorted.enumerated() {
                    scratch[Int(v)] = Int32(k)
                    mesh.vertices.append(t.mesh.vertices[Int(v)])
                    mesh.vertexRegion.append(UInt32(newIndex[r]))
                }
                for k in lo..<(lo + n) { mesh.indices.append(UInt32(scratch[Int(t.mesh.indices[k])]) + base) }
                region.indexCount = UInt32(n)
            }
            regions.append(region)
        }

        // The pixel map and the lines.
        var map = t.regionMap.storage
        for i in map.indices {
            let n = newIndex[Int(map[i])]
            guard n >= 0 else { throw EditFailure.invalid("a pixel belongs to a region that was removed") }
            map[i] = UInt32(n)
        }
        var strokePoints: [SIMD2<Float>] = []
        var outStrokes: [InteriorStroke] = []
        var writingStrokes: [UInt32] = []
        for s in strokes where s.alive {
            guard newIndex[s.region] >= 0 else { throw EditFailure.invalid("a stroke lies in a region that was removed") }
            outStrokes.append(InteriorStroke(
                pointStart: UInt32(strokePoints.count), pointCount: UInt32(s.points.count), layer: s.layer, weight: s.weight,
                region: UInt32(newIndex[s.region])))
            if s.writing { writingStrokes.append(UInt32(outStrokes.count - 1)) }
            strokePoints.append(contentsOf: s.points)
        }
        let art = t.lineArt!
        var result = Template(
            width: t.width, height: t.height, colorSpace: t.colorSpace, palette: t.palette, regions: regions, points: points,
            edges: edges, ringEdges: ringEdges, rings: rings, labels: outLabels, mesh: mesh,
            regionMap: RegionMap(width: t.width, height: t.height, storage: map), pipelineVersion: t.pipelineVersion,
            lineArt: TemplateLineArt(
                edgeLayers: aliveEdges.map { layers[$0] }, edgeWeights: aliveEdges.map { weights[$0] },
                strokePoints: strokePoints, strokes: outStrokes, style: art.style, writingStrokes: writingStrokes))
        result.detailRegions = aliveRegions.indices.filter { regionDetail[aliveRegions[$0]] }.map { UInt32($0) }

        var continued = [Int](repeating: -1, count: t.regions.count)
        for r in 0..<t.regions.count {
            var s = r
            while !regionAlive[s], let next = successor[s] { s = next }
            continued[r] = newIndex[s]
        }
        func renumbered(_ regions: Set<Int>) -> [Int] { regions.compactMap { newIndex[$0] >= 0 ? newIndex[$0] : nil }.sorted() }
        return (result, Mapping(continued: continued, touched: renumbered(summary.touched), pieces: renumbered(summary.pieces)))
    }
}
