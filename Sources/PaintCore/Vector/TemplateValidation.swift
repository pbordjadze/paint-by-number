import Foundation

extension Template {
    /// Structural and geometric invariants of a template, for tests and debug tooling.
    public struct ValidationReport: Sendable, CustomStringConvertible {
        /// Edges with bad sides, too few points, or crossing/touching other edges.
        public var invalidEdges: [Int] = []
        /// Regions whose rings do not chain, keep the region on the wrong side, or have the
        /// wrong orientation for their role (outer positive, holes negative).
        public var badRingRegions: [Int] = []
        /// Regions whose triangles do not exactly cover their polygon area, or that contain
        /// negatively oriented triangles.
        public var badMeshRegions: [Int] = []
        /// Regions with a label outside their polygon (or inside a hole).
        public var badLabelRegions: [Int] = []
        /// |Σ region areas − canvas area|.
        public var canvasAreaError: Double = 0

        public var isValid: Bool {
            invalidEdges.isEmpty && badRingRegions.isEmpty && badMeshRegions.isEmpty && badLabelRegions.isEmpty
                && canvasAreaError <= 1e-3 * Double(max(1, canvasArea))
        }
        var canvasArea: Int = 0

        public var description: String {
            "edges \(invalidEdges.count) rings \(badRingRegions.count) mesh \(badMeshRegions.count) "
                + "labels \(badLabelRegions.count) canvasAreaError \(canvasAreaError)"
        }
    }

    public func validate() -> ValidationReport {
        var report = ValidationReport()
        report.canvasArea = width * height
        var badEdges = Set<Int>()
        for (i, e) in edges.enumerated() {
            let sidesOK = e.left != e.right && Int(e.left) < regions.count
                && (e.right == BoundaryEdge.outside || Int(e.right) < regions.count)
            if !sidesOK || e.pointCount < 2 || Int(e.pointStart) + Int(e.pointCount) > points.count { badEdges.insert(i) }
        }
        if badEdges.isEmpty { badEdges.formUnion(GeometryValidator.invalidEdges(points: points, edges: edges)) }
        report.invalidEdges = badEdges.sorted()
        guard report.invalidEdges.isEmpty else { return report }

        var totalArea = 0.0
        for r in 0..<regions.count {
            let region = regions[r]
            var ringsOK = region.ringCount >= 1
            var polygons: [[SIMD2<Float>]] = []
            for k in 0..<Int(region.ringCount) {
                let ring = rings[Int(region.ringStart) + k]
                if ring.edgeCount == 0 || (k == 0) == ring.isHole { ringsOK = false; continue }
                for q in 0..<Int(ring.edgeCount) {
                    let ref = ringEdges[Int(ring.edgeStart) + q]
                    let next = ringEdges[Int(ring.edgeStart) + (q + 1) % Int(ring.edgeCount)]
                    let e = edges[Int(ref.edge)], n = edges[Int(next.edge)]
                    if (ref.reversed ? e.right : e.left) != UInt32(r) { ringsOK = false }
                    let end = ref.reversed ? points[Int(e.pointStart)] : points[Int(e.pointStart) + Int(e.pointCount) - 1]
                    let start = next.reversed ? points[Int(n.pointStart) + Int(n.pointCount) - 1] : points[Int(n.pointStart)]
                    if end != start { ringsOK = false }
                }
                let poly = polygon(of: ring)
                let a = Template.signedArea(poly)
                if ring.isHole ? a >= 0 : a <= 0 { ringsOK = false }
                polygons.append(poly)
            }
            if !ringsOK { report.badRingRegions.append(r); continue }

            let area = polygons.reduce(0.0) { $0 + Template.signedArea($1) }
            totalArea += area
            var meshArea = 0.0
            var meshOK = region.indexCount % 3 == 0
            let lo = Int(region.indexStart), hi = Int(region.indexStart) + Int(region.indexCount)
            var used = Set<SIMD2<Float>>()
            for t in stride(from: lo, to: hi, by: 3) where meshOK {
                let a = mesh.vertices[Int(mesh.indices[t])], b = mesh.vertices[Int(mesh.indices[t + 1])]
                let c = mesh.vertices[Int(mesh.indices[t + 2])]
                for v in 0..<3 where mesh.vertexRegion[Int(mesh.indices[t + v])] != UInt32(r) { meshOK = false }
                let ta = Template.signedArea([a, b, c])
                if ta < 0 { meshOK = false }
                meshArea += ta
                used.insert(a); used.insert(b); used.insert(c)
            }
            // Watertight: every boundary vertex is a triangle vertex (no T-junctions against
            // the neighbouring region's triangles).
            if polygons.contains(where: { $0.contains { !used.contains($0) } }) { meshOK = false }
            if !meshOK || abs(meshArea - area) > 1e-4 * max(1, abs(area)) || abs(Double(region.area) - area) > 1e-3 * max(1, abs(area)) {
                report.badMeshRegions.append(r)
            }

            for label in labels(ofRegion: r) {
                var inside = false
                for poly in polygons where Template.contains(poly, label.position) { inside.toggle() }
                if !inside || label.region != UInt32(r) { report.badLabelRegions.append(r); break }
            }
        }
        report.canvasAreaError = abs(totalArea - Double(width * height))
        return report
    }

    static func signedArea(_ poly: [SIMD2<Float>]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var sum = 0.0
        var j = poly.count - 1
        for i in 0..<poly.count {
            sum += Double(poly[j].x) * Double(poly[i].y) - Double(poly[i].x) * Double(poly[j].y)
            j = i
        }
        return sum / 2
    }

    static func contains(_ poly: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
