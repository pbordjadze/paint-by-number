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
        /// Regions with a label outside their polygon (or inside a hole) or, when label room
        /// is checked, a label claiming more free radius than it has.
        public var badLabelRegions: [Int] = []
        /// Regions with a label whose free radius is short of the minimum for its number
        /// (`validate(minLabelRadius:)`; a detail area's, its own).
        public var crampedLabelRegions: [Int] = []
        /// Smallest free radius of any label divided by `LabelSizing.roomFactor` of its number
        /// (the single-digit equivalent), a detail area's scaled from its floor to the usual one
        /// (by `minimumRadius / detailMinimumRadius`), so it compares with the floor either way;
        /// infinite unless label room was checked.
        public var minLabelRoom: Float = .infinity
        /// |Σ region areas − canvas area|.
        public var canvasAreaError: Double = 0
        /// Problems with line data (`Template.lineArt`): layer or weight counts unlike
        /// the edges', unknown layers, interior strokes with a bad span, a point outside the
        /// canvas, or a point away from the stroke's region. Nil for classic templates.
        public var badLines: [String]?
        /// Validation stopped before expanding spans or testing pairs beyond its linear
        /// work budget. This is a failure even when no bad edge was found yet.
        public var workLimitReason: String?

        public var isValid: Bool {
            invalidEdges.isEmpty && badRingRegions.isEmpty && badMeshRegions.isEmpty && badLabelRegions.isEmpty
                && crampedLabelRegions.isEmpty && canvasAreaError <= 1e-3 * Double(max(1, canvasArea))
                && (badLines ?? []).isEmpty && workLimitReason == nil
        }
        var canvasArea: Int = 0

        public var description: String {
            var text = "edges \(invalidEdges.count) rings \(badRingRegions.count) mesh \(badMeshRegions.count) "
                + "labels \(badLabelRegions.count) canvasAreaError \(canvasAreaError) cramped \(crampedLabelRegions.count)"
            if minLabelRoom.isFinite { text += " minLabelRoom " + String(format: "%.3f", Double(minLabelRoom)) }
            if let badLines { text += " lines \(badLines.count)" + (badLines.isEmpty ? "" : " (\(badLines.prefix(3).joined(separator: "; ")))") }
            if let workLimitReason { text += " validation work limit exceeded: \(workLimitReason)" }
            return text
        }
    }

    /// Checks the template's invariants. Excessive bucket expansion, candidate pairs or
    /// repeated spans fail with `ValidationReport.workLimitReason` before superlinear work.
    /// - Parameter minLabelRadius: When set, also requires every label to keep this free
    ///   radius from its region's outline (scaled per number by `LabelSizing.roomFactor`) and
    ///   its stored radius to be honest; a detail area's (`detailRegions`) need keep only that
    ///   scaled as `LabelSizing.detailMinimumRadius` is from `minimumRadius`. Pipeline outputs
    ///   pass `LabelSizing.minimumRadius`; nil suits hand-made or synthetic templates (one-pixel
    ///   regions, raster-derived radii).
    public func validate(minLabelRadius: Float? = nil) -> ValidationReport {
        var report = ValidationReport()
        report.canvasArea = width * height
        var work = ValidationWorkBudget(counts: [
            regions.count, points.count, edges.count, ringEdges.count, rings.count,
            labels.count, mesh.vertices.count, mesh.indices.count,
            lineArt?.strokePoints.count ?? 0, lineArt?.strokes.count ?? 0,
        ])
        func exceeded(_ stage: String) -> ValidationReport {
            var stopped = report
            stopped.workLimitReason = "\(stage) (limit \(work.limit))"
            return stopped
        }
        var badEdges = Set<Int>()
        for (i, e) in edges.enumerated() {
            let sidesOK = e.left != e.right && Int(e.left) < regions.count
                && (e.right == BoundaryEdge.outside || Int(e.right) < regions.count)
            if !sidesOK || e.pointCount < 2 || Int(e.pointStart) + Int(e.pointCount) > points.count { badEdges.insert(i) }
        }
        if badEdges.isEmpty {
            let geometry = GeometryValidator.check(points: points, edges: edges)
            report.workLimitReason = geometry.workLimitReason
            badEdges.formUnion(geometry.invalidEdges)
        }
        report.invalidEdges = edges.indices.filter { badEdges.contains($0) }
        guard report.workLimitReason == nil else { return report }
        guard report.invalidEdges.isEmpty else { return report }

        var totalArea = 0.0
        for r in 0..<regions.count {
            let region = regions[r]
            var ringsOK = region.ringCount >= 1
            var polygons: [[SIMD2<Float>]] = []
            var polygonPoints = 0
            for k in 0..<Int(region.ringCount) {
                guard work.consume(1) else { return exceeded("region ring spans") }
                let ring = rings[Int(region.ringStart) + k]
                if ring.edgeCount == 0 || (k == 0) == ring.isHole { ringsOK = false; continue }
                for q in 0..<Int(ring.edgeCount) {
                    let ref = ringEdges[Int(ring.edgeStart) + q]
                    let next = ringEdges[Int(ring.edgeStart) + (q + 1) % Int(ring.edgeCount)]
                    let e = edges[Int(ref.edge)], n = edges[Int(next.edge)]
                    // Charge before polygon(of:) expands references, including repeated edges.
                    guard work.consume(Int(e.pointCount)) else { return exceeded("ring point spans") }
                    polygonPoints += Int(e.pointCount) - 1
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
            guard work.consume(Int(region.indexCount)) else { return exceeded("region mesh spans") }
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

            var labelOK = true, roomOK = true
            let digits = LabelSizing.digitCount(colorIndex: region.colorIndex)
            let detail = LabelSizing.detailMinimumRadius / LabelSizing.minimumRadius
            let floor = isDetailRegion(r) ? detail : 1
            // Each label scans all polygon points, twice when measuring outline distance.
            guard work.consume(max(1, polygonPoints), times: Int(region.labelCount)),
                  minLabelRadius == nil || work.consume(polygonPoints, times: Int(region.labelCount))
            else { return exceeded("label polygon checks") }
            for label in labels(ofRegion: r) {
                var inside = false
                for poly in polygons where Template.contains(poly, label.position) { inside.toggle() }
                if !inside || label.region != UInt32(r) { labelOK = false }
                guard let minLabelRadius else { continue }
                let free = Template.outlineDistance(polygons, label.position)
                // The stored radius may exceed the measured one only by Float rounding.
                if Double(label.radius) > free + 2e-3 { labelOK = false }
                let factor = LabelSizing.roomFactor(digits: digits)
                report.minLabelRoom = min(report.minLabelRoom, Float(free) / factor / floor)
                if free < Double(minLabelRadius * floor * factor) - 1e-3 { roomOK = false }
            }
            if !labelOK { report.badLabelRegions.append(r) }
            if !roomOK { report.crampedLabelRegions.append(r) }
        }
        report.canvasAreaError = abs(totalArea - Double(width * height))
        if let lineArt {
            // The decoder permits many strokes to reuse the same point span.
            for stroke in lineArt.strokes {
                guard work.consume(Int(stroke.pointCount)) else { return exceeded("line stroke spans") }
            }
            report.badLines = validateLines(lineArt)
        }
        return report
    }

    /// See `ValidationReport.badLines`. An interior stroke's points must lie in its region's
    /// pixels or touch them (its ends meet the boundary lines it runs between).
    func validateLines(_ lines: TemplateLineArt) -> [String] {
        var problems: [String] = []
        let layers = UInt8(LineLayer.allCases.count)
        if lines.edgeLayers.count != edges.count || lines.edgeWeights.count != edges.count {
            problems.append("\(lines.edgeLayers.count) layers and \(lines.edgeWeights.count) weights for \(edges.count) edges")
        }
        if let bad = lines.edgeLayers.firstIndex(where: { $0 >= layers }) { problems.append("edge \(bad) layer") }
        var previousWriting = -1
        for s in lines.writingStrokes {
            guard Int(s) > previousWriting, Int(s) < lines.strokes.count else {
                problems.append("writing strokes")
                break
            }
            previousWriting = Int(s)
        }
        let w = Float(width), h = Float(height)
        for (k, stroke) in lines.strokes.enumerated() {
            let start = Int(stroke.pointStart), count = Int(stroke.pointCount)
            guard count >= 2, start + count <= lines.strokePoints.count, stroke.layer < layers, Int(stroke.region) < regions.count else {
                problems.append("stroke \(k) span, layer or region")
                continue
            }
            for p in lines.strokePoints[start..<(start + count)] {
                guard p.x >= 0 && p.x <= w && p.y >= 0 && p.y <= h else {
                    problems.append("stroke \(k) point outside the canvas")
                    break
                }
                let px = Int(p.x.rounded(.down)), py = Int(p.y.rounded(.down))
                var touches = false
                for y in max(0, py - 1)...min(height - 1, py + 1) where !touches {
                    for x in max(0, px - 1)...min(width - 1, px + 1) where regionMap[x, y] == stroke.region {
                        touches = true
                        break
                    }
                }
                if !touches {
                    problems.append("stroke \(k) leaves region \(stroke.region)")
                    break
                }
            }
        }
        return problems
    }

    /// Distance from `p` to the nearest point of any ring.
    static func outlineDistance(_ polygons: [[SIMD2<Float>]], _ p: SIMD2<Float>) -> Double {
        var best = Double.infinity
        for poly in polygons where !poly.isEmpty {
            var j = poly.count - 1
            for i in 0..<poly.count {
                best = min(best, FlatPolygon.segmentDistanceSquared(
                    Double(p.x), Double(p.y), SIMD2<Double>(poly[j]), SIMD2<Double>(poly[i])))
                j = i
            }
        }
        return best.squareRoot()
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

/// Bounds amplification per stored element, independently of canvas size. A large empty
/// raster must not buy quadratic geometry or label work. 128 leaves room for ordinary
/// shared boundaries, labels and bucket occupancy while bounding each expanded pass.
/// A 4096-operation starting allowance covers the canvas border at the generator's maximum
/// working size even when a flat image stores only a handful of boundary points.
struct ValidationWorkBudget {
    let limit: Int
    private var remaining: Int

    init(counts: [Int]) {
        let cap = Int.max / 128
        var size = 32
        for count in counts { size += min(count, cap - size) }
        limit = size * 128
        remaining = limit
    }

    mutating func consume(_ count: Int, times: Int = 1) -> Bool {
        guard count >= 0, times >= 0 else { return false }
        guard times == 0 || count <= remaining / times else { return false }
        remaining -= count * times
        return true
    }
}
