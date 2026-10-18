import Testing
@testable import PaintCore

@Suite("Template validation work limits")
struct TemplateValidationTests {
    @Test func rejectsBucketPrefixOverflow() throws {
        // Each diagonal covers 1001² buckets. 2144 diagonals need 2,148,290,144
        // entries: the old Int32 CSR prefix sum traps before it can check contacts.
        let side = 6000, segments = 2144
        #expect((side / 6 + 1) * (side / 6 + 1) * segments > Int(Int32.max))
        let points = (0...segments).map { i in
            SIMD2<Float>(repeating: i.isMultiple(of: 2) ? 0 : Float(side))
        }
        let template = Template(
            width: side, height: side, colorSpace: .sRGB,
            palette: [PaletteColor(oklab: .zero, rgb: .zero)],
            regions: [Region(colorIndex: 0, area: 0, bounds: .empty, inscribedRadius: 0)],
            points: points,
            edges: [BoundaryEdge(left: 0, right: .max, pointStart: 0, pointCount: UInt32(points.count))],
            ringEdges: [], rings: [], labels: [], mesh: FillMesh(),
            regionMap: RegionMap(width: side, height: side, repeating: 0))
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate()
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("bucket entries") == true)
        #expect(report.description.contains("validation work limit exceeded"))
    }

    @Test func rejectsQuadraticBucketPairsIncludingCleanPairs() throws {
        var template = Self.square()
        template.points = (0..<1000).flatMap { _ in [SIMD2<Float>(0, 0), SIMD2<Float>(1, 1)] }
        template.edges = (0..<1000).map {
            BoundaryEdge(left: 0, right: .max, pointStart: UInt32(2 * $0), pointCount: 2)
        }
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate()
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("candidate pairs") == true)
        // Incremental mode still visits clean pairs before skipping their predicates.
        let clean = GeometryValidator.check(points: decoded.points, edges: decoded.edges,
                                            onlyInvolving: Array(repeating: false, count: decoded.edges.count))
        #expect(clean.workLimitReason?.contains("candidate pairs") == true)
        #expect(GeometryValidator.invalidEdges(points: decoded.points, edges: decoded.edges) == Array(decoded.edges.indices))
    }

    @Test func rejectsRepeatedEdgePointSpans() throws {
        var template = Self.square()
        template.edges = Array(repeating: template.edges[0], count: 4096)
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate()
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("segment spans") == true)
    }

    @Test func rejectsRepeatedRingPointSpans() throws {
        var template = Self.square()
        template.ringEdges = Array(repeating: template.ringEdges[0], count: 4096)
        template.rings[0].edgeCount = UInt32(template.ringEdges.count)
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate()
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("ring point spans") == true)
    }

    @Test func rejectsRepeatedRegionRingSpans() throws {
        var template = Self.square()
        template.regions = Array(repeating: template.regions[0], count: 4096)
        #expect(throws: Template.CodingError.corrupt("overlapping region rings")) {
            try Template(encoded: template.encoded())
        }
        // In-memory templates still need the work limit, independently of decoding.
        let report = template.validate()
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("ring point spans") == true)
    }

    @Test(arguments: [false, true]) func rejectsQuadraticLabelChecks(measureRoom: Bool) throws {
        var template = Self.square()
        template.labels = Array(repeating: template.labels[0], count: 4096)
        template.regions[0].labelCount = UInt32(template.labels.count)
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate(minLabelRadius: measureRoom ? LabelSizing.minimumRadius : nil)
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("label polygon checks") == true)
    }

    @Test func rejectsRepeatedStrokePointSpans() throws {
        var template = Self.square()
        let points = Array(repeating: SIMD2<Float>(128, 128), count: 4096)
        let stroke = InteriorStroke(pointStart: 0, pointCount: UInt32(points.count), layer: 0, weight: 255, region: 0)
        template.lineArt = TemplateLineArt(edgeLayers: [0], edgeWeights: [255], strokePoints: points,
                                          strokes: Array(repeating: stroke, count: 4096))
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate()
        #expect(!report.isValid)
        #expect(report.workLimitReason?.contains("line stroke spans") == true)
    }

    @Test func ordinaryDetailedGeometryStillValidates() throws {
        let decoded = try Template(encoded: Self.square().encoded())
        for report in [decoded.validate(), decoded.validate(minLabelRadius: LabelSizing.minimumRadius)] {
            #expect(report.isValid, "\(report)")
            #expect(report.workLimitReason == nil)
        }
    }

    @Test func budgetRejectsOverflowingProducts() {
        var budget = ValidationWorkBudget(counts: [Int.max])
        let overflow = budget.consume(Int.max, times: Int.max)
        let one = budget.consume(1)
        let excessive = budget.consume(Int.max)
        #expect(!overflow)
        #expect(one)
        #expect(!excessive)
    }

    @Test func sparseBoundaryAtMaximumWorkingSizeStillValidates() throws {
        // A flat generated image can span the whole 2100-unit canvas with only four sides.
        var template = Self.square()
        let side = 2100
        template.width = side; template.height = side
        template.points = [SIMD2(0, 0), SIMD2(Float(side), 0), SIMD2(Float(side), Float(side)),
                           SIMD2(0, Float(side)), SIMD2(0, 0)]
        template.edges[0].pointCount = 5
        template.mesh = FillMesh(vertices: Array(template.points.prefix(4)), vertexRegion: [0, 0, 0, 0],
                                 indices: [0, 1, 2, 0, 2, 3])
        template.regions[0].area = Float(side * side)
        template.regions[0].bounds = PixelBounds(minX: 0, minY: 0, maxX: Int32(side), maxY: Int32(side))
        template.regions[0].inscribedRadius = Float(side) / 2
        template.regions[0].indexCount = 6
        template.labels[0] = Label(position: SIMD2(repeating: Float(side) / 2), radius: Float(side) / 2, region: 0)
        template.regionMap = RegionMap(width: side, height: side, repeating: 0)
        let decoded = try Template(encoded: template.encoded())
        let report = decoded.validate(minLabelRadius: LabelSizing.minimumRadius)
        #expect(report.isValid, "\(report)")
    }

    @Test func collinearRaysOnThinCanvasDoNotOverflow() {
        // These fixed-point ray products exceed Int64.max. Padding supplies enough stored
        // geometry for the long edges to fit the linear work budget and reach the predicate.
        let points = [SIMD2<Float>(0, 0), SIMD2<Float>(12_000_000, 0),
                      SIMD2<Float>(0, 0), SIMD2<Float>(12_000_000, 0)]
            + Array(repeating: SIMD2<Float>(0, 0), count: 100_000)
        let edges = [BoundaryEdge(left: 0, right: .max, pointStart: 0, pointCount: 2),
                     BoundaryEdge(left: 0, right: .max, pointStart: 2, pointCount: 2)]
        // Give the second ray a distinct end so conflict tests the collinear-ray case.
        var rays = points
        rays[3].x = 11_999_999
        let report = GeometryValidator.check(points: rays, edges: edges)
        #expect(report.workLimitReason == nil)
        #expect(report.invalidEdges == [0, 1])
    }

    /// A valid square with unit boundary segments and a conforming triangle fan. Its many
    /// points make repeated spans and label × polygon amplification visible in small tests.
    private static func square() -> Template {
        let side = 256
        var points: [SIMD2<Float>] = []
        for x in 0..<side { points.append(SIMD2(Float(x), 0)) }
        for y in 0..<side { points.append(SIMD2(Float(side), Float(y))) }
        for x in (1...side).reversed() { points.append(SIMD2(Float(x), Float(side))) }
        for y in (1...side).reversed() { points.append(SIMD2(0, Float(y))) }
        let count = points.count
        let centre = SIMD2<Float>(repeating: Float(side) / 2)
        let indices = (0..<count).flatMap { [UInt32($0), UInt32(($0 + 1) % count), UInt32(count)] }
        let mesh = FillMesh(vertices: points + [centre], vertexRegion: Array(repeating: 0, count: count + 1), indices: indices)
        points.append(points[0])
        return Template(
            width: side, height: side, colorSpace: .sRGB,
            palette: [PaletteColor(oklab: .zero, rgb: .zero)],
            regions: [Region(colorIndex: 0, area: Float(side * side),
                             bounds: PixelBounds(minX: 0, minY: 0, maxX: Int32(side), maxY: Int32(side)),
                             inscribedRadius: Float(side) / 2, ringCount: 1, labelCount: 1, indexCount: UInt32(indices.count))],
            points: points,
            edges: [BoundaryEdge(left: 0, right: .max, pointStart: 0, pointCount: UInt32(points.count))],
            ringEdges: [EdgeRef(edge: 0, reversed: false)], rings: [Ring(edgeStart: 0, edgeCount: 1, isHole: false)],
            labels: [Label(position: centre, radius: Float(side) / 2, region: 0)], mesh: mesh,
            regionMap: RegionMap(width: side, height: side, repeating: 0))
    }
}
