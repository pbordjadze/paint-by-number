import Foundation
import Testing
@testable import PaintCore

/// The painter's manual edits of a coloring book (`TemplateEditor`), on `LineArtTests`' scene
/// (a 192 × 144 canvas: sky above the horizon, ground below, a disc round (60, 72) of radius 27
/// and a square over x 120..<168, y 45..<93, both straddling the horizon and outlined, and the
/// ground's detail line at y ≈ 120 drawn inside its cell) and on a crowded scene (`richBook`)
/// for the invariants that need junctions, islands and thin cells.
///
/// The horizon is not level: from the frame at (0, 76) it runs up to y ≈ 72 by x = 10 (edge 6 of
/// the scene, whose third vertex `horizon` is where tests land lines exactly) and on to the disc.
@Suite("Template editor")
struct TemplateEditorTests {
    // MARK: - Scenes

    static let scene = try! LineArtTests.generate().template

    /// A vertex of the horizon, between the frame and the disc.
    static let horizon = Array(scene.points(of: scene.edges[6]))[2]

    /// A coloring book of a crowded scene: the plain template's region boundaries are the edge
    /// map (dilated a pixel), so most boundaries between paints are drawn, with their
    /// junctions, islands and thin cells, and the rest are undrawn paint edges.
    static func richBook(width: Int = 240, height: Int = 160, colors: Int = 40, seed: UInt64 = 13) throws -> Template {
        let photo = TestScenes.colorful(width: width, height: height, seed: seed)
        var classic = GenerationSettings(colorCount: colors, detail: 0.5)
        classic.lineArt = LineArtSettings(style: .classic)
        let plain = try TemplateGenerator(settings: classic).generate(from: photo, cancel: .none).template
        let w = plain.width, h = plain.height
        var values = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let r = plain.regionMap[x, y]
                guard (x + 1 < w && plain.regionMap[x + 1, y] != r) || (y + 1 < h && plain.regionMap[x, y + 1] != r) else { continue }
                for dy in -1...1 {
                    for dx in -1...1 where x + dx >= 0 && y + dy >= 0 && x + dx < w && y + dy < h { values[(y + dy) * w + x + dx] = 255 }
                }
            }
        }
        var book = GenerationSettings(colorCount: colors, detail: 0.5)
        book.lineArt = LineArtSettings(
            outlineThreshold: 0.8, detailThreshold: 0.5, minimumStrokeLength: 8, gapBridging: 6, lineSmoothing: 0.5)
        return try TemplateGenerator(settings: book).generate(
            from: photo, lineArt: LineArtInput(edges: EdgeMap(width: w, height: h, values: values)), cancel: .none).template
    }

    static let rich = try! richBook()

    /// An edit that must be made, on a template that validates, giving one that validates.
    static func apply(_ edit: TemplateEditor.Edit, to t: Template) throws -> (Template, TemplateEditor.Outcome) {
        let (out, outcome) = try TemplateEditor.apply(edit, to: t)
        #expect(outcome.declined == nil, "\(outcome.declined?.reason ?? "")")
        expectValid(out)
        return (out, outcome)
    }

    static func region(_ t: Template, _ x: Float, _ y: Float) throws -> Int { try #require(t.region(at: SIMD2(x, y))) }

    /// A point as the template stores it: on the quantum grid.
    static func quantized(_ p: SIMD2<Float>) -> SIMD2<Float> { Lattice.position(Lattice.point(p)) }

    // MARK: - What a template draws

    typealias Ink = (points: [SIMD2<Float>], left: Int, right: Int, layer: UInt8, weight: UInt8)

    /// The drawn polylines of a template: inked edges (not the frame) and strokes, with the
    /// regions on their sides (a stroke has its own on both).
    static func ink(_ t: Template) -> [Ink] {
        let art = t.lineArt!
        var out: [Ink] = []
        for (k, e) in t.edges.enumerated() where e.right != BoundaryEdge.outside && art.edgeLayers[k] != LineLayer.color.rawValue {
            out.append((Array(t.points(of: e)), Int(e.left), Int(e.right), art.edgeLayers[k], art.edgeWeights[k]))
        }
        for s in art.strokes where s.layer != LineLayer.color.rawValue {
            let pts = Array(art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)])
            out.append((pts, Int(s.region), Int(s.region), s.layer, s.weight))
        }
        return out
    }

    /// Whether some ink has exactly these points, in either direction.
    static func inked(_ t: Template, _ points: [SIMD2<Float>]) -> Bool {
        ink(t).contains { $0.points == points || $0.points == points.reversed() }
    }

    /// The farthest the ink of `t` is from the interior vertices of `line` and the steps between
    /// them (not the steps at its ends, which turn to meet the ink an end joins), canvas units.
    static func deviation(_ t: Template, of line: [SIMD2<Float>]) -> Float {
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        for item in ink(t) { for (a, b) in zip(item.points, item.points.dropFirst()) { segments.append((a, b)) } }
        func distance(_ p: SIMD2<Float>) -> Float {
            var best = Float.infinity
            for (u, v) in segments {
                let uv = v - u
                let s = min(max(simdDot(p - u, uv) / max(simdLengthSquared(uv), 1e-12), 0), 1)
                best = min(best, simdLength(p - (u + uv * s)))
            }
            return best
        }
        var worst: Float = 0
        for p in line.dropFirst().dropLast() { worst = max(worst, distance(p)) }
        if line.count >= 4 {
            for k in 1..<(line.count - 2) {
                for s in 0...16 { worst = max(worst, distance(line[k] + (line[k + 1] - line[k]) * (Float(s) / 16))) }
            }
        }
        return worst
    }

    // MARK: - What a region is

    struct Snapshot: Equatable {
        var paint: SIMD3<Float>
        var detail: Bool
        var area: Float
        var bounds: PixelBounds
        var inscribedRadius: Float
        var rings: [[SIMD2<Float>]]
        var labels: [Label]
        var triangles: [[SIMD2<Float>]]
        var strokes: [[SIMD2<Float>]]
        /// Layer and weight of each edge of its rings.
        var edgeInk: [SIMD2<Int>]
    }

    /// Everything a region is, by value, so regions of two templates compare whatever their
    /// indices: outline, fill, numbers, paint, the strokes lying in it, how its edges are drawn.
    static func snapshot(_ t: Template, _ r: Int) -> Snapshot {
        let region = t.regions[r]
        let art = t.lineArt!
        var edgeInk: [SIMD2<Int>] = []
        for ring in t.rings[Int(region.ringStart)..<Int(region.ringStart + region.ringCount)] {
            for ref in t.ringEdges[Int(ring.edgeStart)..<Int(ring.edgeStart + ring.edgeCount)] {
                edgeInk.append(SIMD2(Int(art.edgeLayers[Int(ref.edge)]), Int(art.edgeWeights[Int(ref.edge)])))
            }
        }
        return Snapshot(
            paint: t.palette[Int(region.colorIndex)].oklab, detail: t.isDetailRegion(r), area: region.area, bounds: region.bounds,
            inscribedRadius: region.inscribedRadius, rings: t.polygons(ofRegion: r),
            labels: t.labels(ofRegion: r).map { Label(position: $0.position, radius: $0.radius, region: 0) },
            triangles: stride(from: Int(region.indexStart), to: Int(region.indexStart + region.indexCount), by: 3).map { k in
                (0..<3).map { t.mesh.vertices[Int(t.mesh.indices[k + $0])] }
            },
            strokes: art.strokes.filter { Int($0.region) == r }.map {
                Array(art.strokePoints[Int($0.pointStart)..<Int($0.pointStart + $0.pointCount)])
            },
            edgeInk: edgeInk)
    }

    /// The regions of `old` that are in `of` or share an edge with one.
    static func adjacent(_ old: Template, to of: Set<Int>) -> Set<Int> {
        var out = of
        for e in old.edges where e.right != BoundaryEdge.outside {
            if of.contains(Int(e.left)) { out.insert(Int(e.right)) }
            if of.contains(Int(e.right)) { out.insert(Int(e.left)) }
        }
        return out
    }

    /// Everything the edit left alone is as it was: of the regions of `old`, only those it touched
    /// (those `outcome` names, and those merged into one) and their neighbours, which may have
    /// gained an outline vertex, differ. The paints are as they were, a new one only last.
    static func expectOthersUnchanged(
        _ old: Template, _ new: Template, _ outcome: TemplateEditor.Outcome, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var merged = Set<Int>()
        var seen = Set<Int>()
        for (r, n) in outcome.continued.enumerated() where !seen.insert(n).inserted { merged.insert(r) }
        for r in outcome.continued.indices where outcome.continued.filter({ $0 == outcome.continued[r] }).count > 1 { merged.insert(r) }
        let touched = Set(outcome.continued.indices.filter { outcome.touchedRegions.contains(outcome.continued[$0]) || merged.contains($0) })
        let mayDiffer = adjacent(old, to: touched)
        for r in old.regions.indices {
            let same = snapshot(old, r) == snapshot(new, outcome.continued[r])
            #expect(same || mayDiffer.contains(r), "region \(r) changed but was not touched or beside a touched region", sourceLocation: sourceLocation)
        }
        #expect(Array(new.palette.prefix(old.palette.count)) == old.palette, sourceLocation: sourceLocation)
    }

    // MARK: - The lattice

    @Test func latticeArithmeticIsExact() {
        #expect(Lattice.mulDiv(7, 1, 2) == 4 && Lattice.mulDiv(-7, 1, 2) == -4 && Lattice.mulDiv(7, -1, 2) == -4)
        #expect(Lattice.mulDiv(1, 1, 3) == 0 && Lattice.mulDiv(2, 1, 3) == 1 && Lattice.mulDiv(2, 1, -3) == -1)
        #expect(Lattice.mulDiv(1 << 40, 1 << 20, 1 << 30) == 1 << 30)
        #expect(Lattice.mulDiv(123_456_789_012, 987_654, 1_000_003) == Int64((Double(123_456_789_012) * 987_654 / 1_000_003).rounded()))
        #expect(Lattice.floorDiv(-1, 256) == -1 && Lattice.floorDiv(255, 256) == 0 && Lattice.floorDiv(-256, 256) == -1)
        // The quantum is a power of two, so every lattice point of the canvas is a Float.
        for v: Int64 in [0, 1, 255, 256, 257, 8_388_607] { #expect(Int64(Lattice.position(LatticePoint(v, v)).x * 256) == v) }
    }

    @Test func segmentsMeetExactly() {
        func p(_ x: Int64, _ y: Int64) -> LatticePoint { LatticePoint(x, y) }
        #expect(Lattice.contact(p(0, 0), p(10, 10), p(0, 10), p(10, 0)) == .cross(p(5, 5)))
        #expect(Lattice.contact(p(0, 0), p(10, 0), p(5, 0), p(5, 7)) == .touch(p(5, 0)))
        #expect(Lattice.contact(p(0, 0), p(10, 0), p(10, 0), p(12, 4)) == .touch(p(10, 0)))
        #expect(Lattice.contact(p(0, 0), p(10, 0), p(4, 0), p(20, 0)) == .overlap(p(4, 0), p(10, 0)))
        #expect(Lattice.contact(p(0, 0), p(10, 0), p(10, 0), p(20, 0)) == .touch(p(10, 0)))
        #expect(Lattice.contact(p(0, 0), p(10, 0), p(0, 1), p(10, 1)) == .none)
        // A crossing is the lattice point nearest the true one, whichever way it is asked.
        let a0 = p(0, 0), a1 = p(7, 3), b0 = p(2, 5), b1 = p(5, -4)
        let c = Lattice.crossing(a0, a1, b0, b1)
        #expect(c == Lattice.crossing(a1, a0, b1, b0) && c == Lattice.crossing(b0, b1, a0, a1) && c == Lattice.crossing(b1, b0, a1, a0))
        let den = Double((a1.x - a0.x) * (b1.y - b0.y) - (a1.y - a0.y) * (b1.x - b0.x))
        let t = Double((b0.x - a0.x) * (b1.y - b0.y) - (b0.y - a0.y) * (b1.x - b0.x)) / den
        #expect(c == p(Int64((7 * t).rounded()), Int64((3 * t).rounded())))
        // Left of a→b is positive, as an edge's `left` is.
        #expect(Lattice.orient(p(0, 0), p(10, 0), p(5, 3)) > 0)
        #expect(Lattice.contains([[p(0, 0), p(10, 0), p(10, 10), p(0, 10)]], p(5, 5)) == .inside)
        #expect(Lattice.contains([[p(0, 0), p(10, 0), p(10, 10), p(0, 10)]], p(10, 5)) == .boundary)
        #expect(Lattice.contains([[p(0, 0), p(10, 0), p(10, 10), p(0, 10)], [p(4, 4), p(6, 4), p(6, 6), p(4, 6)]], p(5, 5)) == .outside)
    }

    @Test func facesTurnTowardTheirRegion() {
        // Arriving from the east along an edge (back = east), the face on its left continues along
        // the first edge clockwise from east: of north, south and west, north comes first.
        let back = LatticePoint(1, 0)
        let north = LatticePoint(0, -1), south = LatticePoint(0, 1), west = LatticePoint(-1, 0)
        #expect(Lattice.clockwiseBefore(from: back, north, west) && Lattice.clockwiseBefore(from: back, west, south))
        #expect(Lattice.clockwiseBefore(from: back, north, south) && !Lattice.clockwiseBefore(from: back, south, north))
        #expect(!Lattice.clockwiseBefore(from: back, back, north), "the way back is the full turn, last")
        // The ring of a clockwise square on screen (y down) has positive area, as `BoundaryEdge` has it.
        #expect(Lattice.area2([LatticePoint(0, 0), LatticePoint(10, 0), LatticePoint(10, 10), LatticePoint(0, 10)]) > 0)
    }

    @Test func theEraserReachesExactlyItsRadius() {
        let rub = Rub(path: [LatticePoint(0, 0), LatticePoint(2560, 0)], radius: 3)
        // A horizontal line 2 units above the path: covered where within 3 of it: the path's span
        // and the ends' discs, sqrt(9 - 4) either side.
        let line = [LatticePoint(-5120, -512), LatticePoint(7680, -512)]
        let cut = rub.uncovered(line)
        #expect(cut.broken && cut.pieces.count == 2)
        let reach = Double(5).squareRoot()
        #expect(abs(Lattice.double(cut.pieces[0].last!).x - (-reach)) < 0.005)
        #expect(abs(Lattice.double(cut.pieces[1].first!).x - (10 + reach)) < 0.005)
        #expect(cut.pieces[0].first == line[0] && cut.pieces[1].last == line[1])
        #expect(!rub.uncovered([LatticePoint(0, 5120), LatticePoint(2560, 5120)]).broken)
        // Dabs, and ink wholly inside, leave nothing.
        let dab = Rub(path: [LatticePoint(0, 0)], radius: 2)
        #expect(dab.uncovered([LatticePoint(-256, 0), LatticePoint(256, 0)]) == ([], true))
    }

    // MARK: - Drawing

    /// A line from the frame down to the horizon walls off the sky's left: two areas of the one
    /// paint, each with a number of its own, cut exactly along the line: the new boundary is an edge
    /// whose points are the polyline given, quantized, inked as an outline at full weight.
    @Test func aLineClosingOffAnAreaSplitsItAlongTheLine() throws {
        let t = Self.scene
        let sky = try Self.region(t, 100, 20)
        let h = Self.horizon
        let line: [SIMD2<Float>] = [SIMD2(h.x, 0), SIMD2(12.003, 30.25), SIMD2(9.5, 55.7519), h]
        let exact = line.map(Self.quantized)
        let (u, outcome) = try Self.apply(.draw(points: line), to: t)
        #expect(outcome.changed && outcome.regionsSplit == 1 && outcome.lines == 1 && outcome.tooSmall.isEmpty)
        #expect(u.regions.count == t.regions.count + 1)
        let left = try Self.region(u, 5, 40), right = try Self.region(u, 100, 20)
        #expect(left != right)
        // Both keep the sky's paint, each has its own number.
        #expect(u.regions[left].colorIndex == t.regions[sky].colorIndex && u.regions[right].colorIndex == t.regions[sky].colorIndex)
        #expect(u.labels(ofRegion: left).count >= 1 && u.labels(ofRegion: right).count >= 1)
        #expect(abs(u.regions[left].area + u.regions[right].area - t.regions[sky].area) < 0.05)
        // The line is the edge between them, exactly, drawn as the outline it is.
        let between = Self.ink(u).filter { Set([$0.left, $0.right]) == [left, right] }
        let lineEdges = between.filter { $0.points == exact || $0.points == exact.reversed() }
        #expect(lineEdges.count == 1 && lineEdges[0].layer == LineLayer.outline.rawValue && lineEdges[0].weight == 255)
        #expect(Self.deviation(u, of: exact) <= Template.coordinateQuantum)
        #expect(u.region(at: SIMD2(8.5, 40)) == left && u.region(at: SIMD2(14, 40)) == right)
        Self.expectOthersUnchanged(t, u, outcome)
        #expect(u.palette == t.palette)
    }

    /// The same line, ending a unit and a half short of the frame and of the horizon, joins both:
    /// each end moves onto the ink (to its nearest vertex within half a unit, else the nearest
    /// point) and the cell closes as it looks.
    @Test func aLineEndingNearInkJoinsIt() throws {
        let t = Self.scene
        let h = Self.horizon
        let (u, outcome) = try Self.apply(.draw(points: [SIMD2(h.x, 1.5), SIMD2(10.25, 30), SIMD2(h.x, h.y - 1.4)]), to: t)
        #expect(outcome.joins == 2 && outcome.regionsSplit == 1)
        let left = try Self.region(u, 5, 40), right = try Self.region(u, 100, 20)
        #expect(left != right)
        let edge = try #require(Self.ink(u).first { Set([$0.left, $0.right]) == [left, right] && $0.points.count == 3 })
        let ends = [edge.points.first!, edge.points.last!].sorted { $0.y < $1.y }
        #expect(ends[0] == SIMD2(h.x, 0), "joined to the frame, straight above its end")
        #expect(ends[1] == h, "joined to the horizon's vertex beside it")
        #expect(edge.points.contains(SIMD2(10.25, 30)), "its middle as drawn")
        // The ink it joined has a vertex there: no edge of the template touches another but at its ends.
        #expect(u.validate(minLabelRadius: LabelSizing.minimumRadius).invalidEdges.isEmpty)
        // Ending 5 units short is not near enough: the line is a stroke and the sky is whole.
        let (v, far) = try Self.apply(.draw(points: [SIMD2(h.x, 5), SIMD2(h.x, 40)]), to: t)
        #expect(far.joins == 0 && far.regionsSplit == 0 && far.strokes == 1 && v.regions.count == t.regions.count)
    }

    /// A line that closes nothing is an interior stroke, verbatim, in the cell it lies in; the
    /// cell and everything else stay as they were.
    @Test func aDanglingLineBecomesAnInteriorStroke() throws {
        let t = Self.scene
        let line: [SIMD2<Float>] = [SIMD2(100.3, 10.7), SIMD2(110.5, 30.1), SIMD2(104.25, 41.8)]
        let (u, outcome) = try Self.apply(.draw(points: line), to: t)
        #expect(outcome.regionsSplit == 0 && outcome.strokes == 1 && u.regions.count == t.regions.count && u.edges.count == t.edges.count)
        let stroke = try #require(u.lineArt!.strokes.last)
        let points = Array(u.lineArt!.strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)])
        #expect(points == line.map(Self.quantized))
        #expect(stroke.layer == LineLayer.outline.rawValue && stroke.weight == 255)
        let sky = try Self.region(u, 100, 20)
        #expect(Int(stroke.region) == sky)
        #expect(u.lineArt!.strokes.count == t.lineArt!.strokes.count + 1)
        Self.expectOthersUnchanged(t, u, outcome)
        // A slit from the frame inwards is the same: the area is not cut.
        let (v, slit) = try Self.apply(.draw(points: [SIMD2(150, 0), SIMD2(150, 25)]), to: t)
        #expect(slit.regionsSplit == 0 && v.regions.count == t.regions.count && slit.strokes == 1)
    }

    /// A second line that meets the first's free end closes a shape with it: the strokes of one edit
    /// are ink for the next.
    @Test func aLineClosesAShapeWithAnEarlierStroke() throws {
        let t = Self.scene
        // A bar from the frame: dangling, a stroke.
        let (u, first) = try Self.apply(.draw(points: [SIMD2(150, 0), SIMD2(150, 25)]), to: t)
        #expect(first.regionsSplit == 0)
        // A line from beside its end round to the frame: together they enclose a piece of the sky.
        let (v, second) = try Self.apply(.draw(points: [SIMD2(150.3, 25.3), SIMD2(170, 24), SIMD2(172, 0)]), to: u)
        #expect(second.regionsSplit == 1 && second.joins >= 1)
        let inside = try Self.region(v, 160, 12), outside = try Self.region(v, 100, 20), sky = try Self.region(t, 100, 20)
        #expect(inside != outside && v.regions[inside].colorIndex == t.regions[sky].colorIndex)
        // The bar is the shape's edge now, drawn as before, not a stroke.
        #expect(v.lineArt!.strokes.count == t.lineArt!.strokes.count)
        #expect(Self.ink(v).contains { Set([$0.left, $0.right]) == [inside, outside] && $0.points.contains(SIMD2(150, 0)) })
    }

    /// A loop drawn inside one cell and touching nothing makes an area of its own, and a hole in the
    /// cell round it; its line is the loop as given.
    @Test func aClosedLoopInsideACellMakesAnIsland() throws {
        let t = Self.scene
        let sky = try Self.region(t, 100, 20)
        let loop: [SIMD2<Float>] = (0..<12).map { i in
            let a = Float(i) / 12 * 2 * .pi
            return SIMD2(100 + 14 * cos(a), 25 + 11 * sin(a))
        }
        let (u, outcome) = try Self.apply(.draw(points: loop, closed: true), to: t)
        #expect(outcome.regionsSplit == 1)
        let inside = try Self.region(u, 100, 25), outer = try Self.region(u, 100, 5)
        #expect(inside != outer && u.regions[inside].colorIndex == t.regions[sky].colorIndex)
        #expect(u.polygons(ofRegion: outer).count == 2, "the cell round the loop has it as a hole")
        #expect(Self.inked(u, (loop + [loop[0]]).map(Self.quantized)), "the loop, closed, as drawn")
        #expect(abs(u.regions[outer].area + u.regions[inside].area - t.regions[sky].area) < 0.05)
        Self.expectOthersUnchanged(t, u, outcome)
    }

    /// A line crossing a boundary is cut there: the part in the sky and the part in the ground are
    /// separate lines, meeting the horizon at a vertex of it.
    @Test func aLineCrossingInkIsCutAtTheCrossing() throws {
        let t = Self.scene
        let h = Self.horizon
        let (u, outcome) = try Self.apply(.draw(points: [SIMD2(h.x, -8), SIMD2(h.x, 82)]), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.strokes == 1)
        #expect(Self.inked(u, [SIMD2(h.x, 0), h]), "the sky's part, from the frame to the horizon")
        #expect(Self.inked(u, [h, SIMD2(h.x, 82)]), "the ground's tail, a stroke")
        let ground = try Self.region(u, 100, 120), beside = try Self.region(u, 5, 100), other = try Self.region(u, 15, 100)
        #expect(beside == ground && other == ground, "the tail splits nothing")
        #expect(u.edges.count == t.edges.count + 3, "the frame and the horizon are cut, and the sky's cut is an edge")
        Self.expectOthersUnchanged(t, u, outcome)
    }

    /// A piece with no room for its number is not cut off, unless it has room for a detail area's:
    /// then it is one.
    @Test func aTinyPieceIsADetailAreaOrNoSplit() throws {
        let t = Self.scene
        let sky = try Self.region(t, 100, 20)
        func square(_ side: Float, at c: SIMD2<Float>) -> [SIMD2<Float>] {
            let h = side / 2
            return [SIMD2(-h, -h), SIMD2(h, -h), SIMD2(h, h), SIMD2(-h, h)].map { c + $0 }
        }
        // 3.2 across: room for a detail number (radius 1.6 against a floor of about 1.03), not for a
        // usual one (2.12).
        let (detail, made) = try Self.apply(.draw(points: square(3.2, at: SIMD2(100, 25)), closed: true), to: t)
        #expect(made.regionsSplit == 1 && made.detailAreas == 1 && made.tooSmall.isEmpty)
        let piece = try Self.region(detail, 100, 25)
        #expect(piece != sky && detail.isDetailRegion(piece) && detail.regions[piece].colorIndex == t.regions[sky].colorIndex)
        let digits = LabelSizing.digitCount(colorIndex: detail.regions[piece].colorIndex)
        #expect(detail.labels(ofRegion: piece).allSatisfy { $0.radius >= LabelSizing.minimumRadius(digits: digits, detail: true) - 1e-3 })
        let around = try Self.region(detail, 100, 5)
        #expect(detail.detailRegions == [UInt32(piece)] && !detail.isDetailRegion(around))
        // 1.6 across: nothing fits a number. The line stays a closed stroke and the sky whole.
        let tiny = square(1.6, at: SIMD2(100, 25))
        let (none, declined) = try Self.apply(.draw(points: tiny, closed: true), to: t)
        #expect(declined.regionsSplit == 0 && declined.strokes == 1 && declined.tooSmall.count == 1)
        #expect(none.regions.count == t.regions.count && none.detailRegions.isEmpty)
        let stroke = try #require(none.lineArt!.strokes.last)
        let points = Array(none.lineArt!.strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)])
        #expect(points == (tiny + [tiny[0]]).map(Self.quantized), "the loop, closed, as drawn")
        #expect(Int(stroke.region) == sky)
        #expect(abs(declined.tooSmall[0].x - 100) < 1 && abs(declined.tooSmall[0].y - 25) < 1)
    }

    /// A piece with room for its 2- or 3-digit number keeps the usual one: its room is measured
    /// finely before it is made a detail area, though those floors (3.17, 4.39) are above the
    /// vectorizer's fine-search radius (3). Each triangle here has a little more room than its
    /// floor, which the coarse search alone finds short of it.
    @Test func aPieceThatFitsItsLongerNumberIsNoDetailArea() throws {
        let work = try EditWork(Self.scene)
        for (color, corners) in [
            (UInt32(11), [SIMD2<Float>(10, 10), SIMD2(25, 10), SIMD2(16, 18)]),
            (UInt32(99), [SIMD2<Float>(10, 10), SIMD2(31, 10), SIMD2(16, 21)]),
        ] {
            let ring = corners.map(Lattice.point)
            let usual = Double(LabelSizing.minimumRadius(digits: LabelSizing.digitCount(colorIndex: color)))
            let poly = EditWork.flatPolygon([ring])
            let coarse = PolyLabel.find(poly, precision: Vectorizer.labelPrecision, seed: SIMD2(10, 10), keepOut: LabelKeepOut(rects: []))
            #expect(coarse.distance >= Double(Vectorizer.smallRegionRadius) && coarse.distance < usual, "\(coarse.distance)")
            let plan = try #require(work.labelPlan(rings: [ring], color: color, detail: false, hints: [], region: 0, keepOut: []))
            #expect(!plan.needsDetail && Double(plan.labels[0].radius) >= usual, "\(color): \(plan.labels[0].radius) of \(usual)")
            #expect(poly.signedDistance(Double(plan.labels[0].position.x), Double(plan.labels[0].position.y)) >= usual)
        }
        // So a line closing the first in a cell of number 12 cuts off a cell like it, not a detail area.
        let t = Self.rich
        let cell = try Self.region(t, 90, 15)
        #expect(t.regions[cell].colorIndex == 11 && !t.isDetailRegion(cell))
        let triangle = [SIMD2<Float>(82, 11), SIMD2(97, 11), SIMD2(88, 19)]
        let (u, outcome) = try Self.apply(.draw(points: triangle, closed: true), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.detailAreas == 0 && u.detailRegions == t.detailRegions)
        let piece = try Self.region(u, 89, 13)
        #expect(piece != cell && u.regions[piece].colorIndex == 11)
        #expect(u.labels(ofRegion: piece).allSatisfy { $0.radius >= LabelSizing.minimumRadius(digits: 2) })
    }

    /// A line laid along ink is that ink: nothing is drawn twice, and the cells are as they were.
    @Test func aLineAlongInkIsThatInk() throws {
        let t = Self.scene
        // The horizon between the disc and the square runs level at y = 72.
        let (u, outcome) = try Self.apply(.draw(points: [SIMD2(95, 72), SIMD2(110, 72)]), to: t)
        #expect(outcome.regionsSplit == 0 && u.regions.count == t.regions.count && u.lineArt!.strokes == t.lineArt!.strokes)
        #expect(u.regions.map(\.area) == t.regions.map(\.area) && u.palette == t.palette)
        func length(_ t: Template) -> Float {
            Self.ink(t).reduce(0) { total, item in total + zip(item.points, item.points.dropFirst()).reduce(0) { $0 + simdLength($1.1 - $1.0) } }
        }
        #expect(abs(length(u) - length(t)) < 0.01)
        #expect(Self.inked(u, [SIMD2(95, 72), SIMD2(110, 72)]), "the stretch drawn over is an edge of its own")
    }

    // MARK: - Erasing

    /// The eraser across the top of the disc: the ink between the disc and the sky is broken, so
    /// they become one (the sky, the larger, keeps its paint), and what is left of the disc's outline
    /// above the horizon is drawn inside it as strokes, cut exactly at the edge of the eraser's reach.
    @Test func erasingABoundaryMergesTheRegionsAndKeepsTheRestOfTheInk() throws {
        let t = Self.scene
        let sky = try Self.region(t, 100, 20), disc = try Self.region(t, 60, 72)
        #expect(t.regions[sky].area > t.regions[disc].area)
        let path: [SIMD2<Float>] = [SIMD2(55, 44), SIMD2(65, 44.5)]
        let (u, outcome) = try Self.apply(.erase(path: path, radius: 3), to: t)
        #expect(outcome.regionsMerged == 1 && u.regions.count == t.regions.count - 1)
        let merged = try Self.region(u, 100, 20)
        let top = try Self.region(u, 60, 60), bottom = try Self.region(u, 60, 90)
        #expect(merged == top && merged == bottom, "the whole disc joins the sky")
        #expect(u.regions[merged].colorIndex == t.regions[sky].colorIndex, "the larger keeps its paint")
        #expect(abs(u.regions[merged].area - (t.regions[sky].area + t.regions[disc].area)) < 0.05)
        #expect(outcome.continued[disc] == merged && outcome.continued[sky] == merged)
        // The disc's outline against the ground is the boundary of what it joined.
        let beneath = try Self.region(u, 60, 105)
        #expect(beneath != merged)
        // What survives of the outline between disc and sky: two arcs, ending where the eraser reached.
        let strokes = u.lineArt!.strokes.dropFirst(t.lineArt!.strokes.count)
        #expect(strokes.count == 2)
        let ab = path[1] - path[0]
        func distance(_ p: SIMD2<Float>) -> Float {
            simdLength(p - (path[0] + ab * min(max(simdDot(p - path[0], ab) / simdLengthSquared(ab), 0), 1)))
        }
        for s in strokes {
            #expect(s.layer == LineLayer.outline.rawValue && Int(s.region) == merged)
            let points = Array(u.lineArt!.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)])
            #expect(points.count >= 3)
            // Every point is out of the eraser's reach, the cut end at its edge.
            #expect(points.allSatisfy { distance($0) > 3 - 0.01 })
            #expect(points.contains { abs(distance($0) - 3) < 0.01 }, "one end is cut at the eraser's edge")
        }
        Self.expectOthersUnchanged(t, u, outcome)
    }

    /// The eraser cuts a stroke at the edge of its reach, and a pass that reaches no ink changes
    /// nothing.
    @Test func theEraserCutsStrokesAndMissesNothing() throws {
        let t = Self.scene
        #expect(t.lineArt!.strokes.count == 1, "the ground's detail line")
        let (u, outcome) = try Self.apply(.erase(path: [SIMD2(96, 119), SIMD2(104, 121)], radius: 4), to: t)
        #expect(outcome.regionsMerged == 0 && outcome.erased == 1)
        #expect(u.regions.count == t.regions.count && u.edges.count == t.edges.count)
        let kept = u.lineArt!.strokes
        #expect(kept.count == 2, "one stroke becomes two, a gap between")
        let spans = kept.map { s -> ClosedRange<Float> in
            let xs = u.lineArt!.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)].map(\.x)
            return xs.min()!...xs.max()!
        }.sorted { $0.lowerBound < $1.lowerBound }
        #expect(spans[0].upperBound > 90 && spans[0].upperBound < 100 && spans[1].lowerBound > 100 && spans[1].lowerBound < 112)
        #expect(spans[1].lowerBound - spans[0].upperBound > 7, "the gap is the eraser's reach")
        // Nothing within reach: nothing changes (the very template comes back).
        let (same, none) = try TemplateEditor.apply(.erase(path: [SIMD2(100, 10)], radius: 2), to: t)
        #expect(!none.changed && same == t && none.continued == Array(0..<t.regions.count))
    }

    /// Traced writing stays writing (`TemplateLineArt.writingStrokes`, so it keeps its light ink on dark
    /// paint) through edits: its pieces after a cut are writing, a drawn line never is.
    @Test func writingStaysWritingThroughEdits() throws {
        var t = Self.scene
        t.lineArt!.writingStrokes = [0]
        let (u, _) = try Self.apply(.draw(points: [SIMD2(100.3, 10.7), SIMD2(110.5, 30.1)]), to: t)
        #expect(u.lineArt!.strokes.count == 2 && u.lineArt!.writingStrokes == [0])
        let (v, _) = try Self.apply(.erase(path: [SIMD2(96, 119), SIMD2(104, 121)], radius: 4), to: u)
        let marked = v.lineArt!.strokes.indices.filter { v.lineArt!.isWritingStroke($0) }
        #expect(v.lineArt!.strokes.count == 3 && marked.count == 2)
        #expect(marked.allSatisfy { v.lineArt!.strokes[$0].layer == t.lineArt!.strokes[0].layer })
        #expect(try Template(encoded: v.encoded()).lineArt!.writingStrokes == v.lineArt!.writingStrokes)
    }

    /// Writing is no part of the drawing a line meets, on the note of `WritingTests.book` ("Hi
    /// you", traced): a line across the letters cuts the cells along itself alone, the letters it
    /// crosses cut with them, every piece still writing; one ending beside the "o" neither joins
    /// it nor closes it into a cell. Either way no area lies within the writing.
    @Test func aLineMeetingWritingLeavesItWritingAndNoCellBorder() throws {
        let t = try WritingTests.book().template
        let scale = Float(t.width) / Float(WritingTests.size.w)
        let box = SIMD4<Float>(66, 88, 158, 124) * scale
        func inBox(_ p: SIMD2<Float>) -> Bool { p.x > box.x && p.x < box.z && p.y > box.y && p.y < box.w }
        func writing(_ t: Template) -> (count: Int, length: Float) {
            let art = t.lineArt!
            var length: Float = 0
            for k in art.writingStrokes.map(Int.init) {
                let s = art.strokes[k]
                let points = art.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)]
                for (a, b) in zip(points, points.dropFirst()) { length += simdLength(b - a) }
            }
            return (art.writingStrokes.count, length)
        }
        func noAreaInTheWriting(_ u: Template) -> Bool {
            u.regions.allSatisfy { r in
                let b = r.bounds
                return !(Float(b.minX) > box.x && Float(b.maxX) < box.z && Float(b.minY) > box.y && Float(b.maxY) < box.w)
            }
        }
        let before = writing(t)
        #expect(before.count >= 6 && noAreaInTheWriting(t))

        // Across the note through the letters' middle (the "o" twice, the H, the i, the y, the u),
        // from the ground on one side to the other.
        let y = 111 * scale
        let (u, across) = try Self.apply(.draw(points: [SIMD2(30 * scale, y), SIMD2(330 * scale, y)], paints: []), to: t)
        #expect(across.regionsSplit >= 1)
        let after = writing(u)
        #expect(after.count > before.count, "the letters it crosses are cut, each piece writing")
        #expect(abs(after.length - before.length) < 0.005 * before.length, "\(after.length) of \(before.length)")
        #expect(noAreaInTheWriting(u))
        // The only boundary within the writing is the line.
        for e in u.edges { for p in u.points(of: e) where inBox(p) { #expect(abs(p.y - y) < 0.05, "an edge at \(p)") } }
        // A cell edge there cuts the letters as the line does.
        let (w, _) = try Self.apply(.cellEdge(points: [SIMD2(30 * scale, y), SIMD2(330 * scale, y)]), to: t)
        let edged = writing(w)
        #expect(edged.count > before.count && abs(edged.length - before.length) < 0.005 * before.length)

        // Ending 2 units above the "o" (its top at (128.5, 102) on the note), clear of the rest.
        let top = SIMD2<Float>(128.5, 102) * scale
        let (v, beside) = try Self.apply(.draw(points: [top - SIMD2(0, 13), top - SIMD2(0, 2)], paints: []), to: t)
        #expect(beside.joins == 0 && beside.regionsSplit == 0 && beside.strokes == 1)
        #expect(v.regions.count == t.regions.count && noAreaInTheWriting(v))
        #expect(v.lineArt!.writingStrokes == t.lineArt!.writingStrokes)
        let marked = { (t: Template) in t.lineArt!.writingStrokes.map { t.lineArt!.strokes[Int($0)] } }
        #expect(marked(v) == marked(t))
    }

    /// A tapped line goes from junction to junction: the square's outline against the sky, from where
    /// it meets the horizon on one side to the other, is one line; taking it out joins the square to
    /// the sky and leaves its outline against the ground as it was.
    @Test func aTappedLineGoesFromJunctionToJunction() throws {
        let t = Self.scene
        let sky = try Self.region(t, 100, 20), square = try Self.region(t, 140, 55)
        let outline = try #require(Self.ink(t).first { Set([$0.left, $0.right]) == [sky, square] })
        let tap = outline.points[outline.points.count / 2] + SIMD2(0, 0.3)
        let (u, outcome) = try Self.apply(.eraseLine(at: tap, reach: 4), to: t)
        #expect(outcome.regionsMerged == 1 && u.regions.count == t.regions.count - 1 && outcome.erased == 1)
        let merged = try Self.region(u, 100, 20)
        let upper = try Self.region(u, 140, 55), lower = try Self.region(u, 140, 85)
        #expect(merged == upper && merged == lower && outcome.continued[square] == merged)
        #expect(u.regions[merged].colorIndex == t.regions[sky].colorIndex)
        // The line was one chain of the drawing: no stroke is left of it, and its edge is gone.
        #expect(u.lineArt!.strokePoints == t.lineArt!.strokePoints && u.lineArt!.strokes.count == t.lineArt!.strokes.count)
        #expect(Self.ink(u).count == Self.ink(t).count - 1)
        Self.expectOthersUnchanged(t, u, outcome)
        // A tap on nothing does nothing.
        let (same, none) = try TemplateEditor.apply(.eraseLine(at: SIMD2(100, 10), reach: 2), to: t)
        #expect(!none.changed && same == t)
    }

    /// A tapped stroke is taken out whole, and takes no region with it.
    @Test func aTappedStrokeIsTakenOut() throws {
        let t = Self.scene
        let (u, outcome) = try Self.apply(.eraseLine(at: SIMD2(100, 119.5), reach: 3), to: t)
        #expect(outcome.erased == 1 && outcome.regionsMerged == 0 && u.regions.count == t.regions.count)
        #expect(u.lineArt!.strokes.isEmpty)
        Self.expectOthersUnchanged(t, u, outcome)
    }

    /// Erasing never touches paint edges: wherever the eraser passes, regions merge only through ink
    /// it broke, never because an undrawn edge lay between them, and a pass that reaches no ink
    /// changes nothing.
    @Test func erasingNeverMergesAcrossUndrawnEdges() throws {
        let t = Self.rich
        let art = t.lineArt!
        // Regions the ink joins, transitively: all that erasing could ever merge.
        var parent = Array(t.regions.indices)
        func find(_ a: Int) -> Int { parent[a] == a ? a : { parent[a] = find(parent[a]); return parent[a] }() }
        for (k, e) in t.edges.enumerated() where e.right != BoundaryEdge.outside && art.edgeLayers[k] != LineLayer.color.rawValue {
            parent[find(Int(e.left))] = find(Int(e.right))
        }
        let colorEdges = t.edges.indices.filter { art.edgeLayers[$0] == LineLayer.color.rawValue && t.edges[$0].right != BoundaryEdge.outside }
        #expect(colorEdges.count > 5)
        var untouched = 0
        for e in colorEdges.prefix(20) {
            let pts = Array(t.points(of: t.edges[e]))
            let (u, outcome) = try TemplateEditor.apply(.erase(path: [pts[pts.count / 2]], radius: 0.5), to: t)
            #expect(outcome.declined == nil)
            expectValid(u)
            if !outcome.changed {
                #expect(u == t)
                untouched += 1
            }
            let a = Int(t.edges[e].left), b = Int(t.edges[e].right)
            #expect(outcome.continued[a] != outcome.continued[b] || find(a) == find(b), "an undrawn edge's regions were merged")
        }
        #expect(untouched >= 1)
    }

    // MARK: - Filling

    /// A fill makes the closed shape under it one detail area of a paint: the one within a
    /// just-noticeable difference of the color, or else a new paint added last.
    @Test func aFillMakesOneDetailAreaOfAPaint() throws {
        let t = Self.scene
        let square = try Self.region(t, 140, 55)
        let paint = t.palette[Int(t.regions[square].colorIndex)].oklab
        // A color a hair from the square's paint reuses it: the palette is as it was.
        let (u, outcome) = try Self.apply(.fill(at: SIMD2(140, 55), color: paint + SIMD3(0.01, 0, 0)), to: t)
        #expect(outcome.fills == 1 && outcome.paintsAdded == 0 && u.palette == t.palette)
        let filled = try Self.region(u, 140, 55)
        #expect(u.detailRegions == [UInt32(filled)] && u.regions[filled].colorIndex == t.regions[square].colorIndex)
        #expect(u.regions.count == t.regions.count)
        Self.expectOthersUnchanged(t, u, outcome)

        // A color far from every paint is a new one, last, so no other number changes. The sky
        // reaches the frame: only the cell tapped is filled, not the background it joins.
        let magenta = SIMD3<Float>(0.62, 0.2, -0.1)
        let (v, added) = try Self.apply(.fill(at: SIMD2(100, 20), color: magenta), to: t)
        #expect(added.paintsAdded == 1 && v.palette.count == t.palette.count + 1)
        #expect(Array(v.palette.dropLast()) == t.palette && v.palette.last!.oklab == magenta)
        let sky = try Self.region(v, 100, 20)
        #expect(Int(v.regions[sky].colorIndex) == t.palette.count && v.isDetailRegion(sky) && v.regions.count == t.regions.count)
        #expect(v.regions.enumerated().allSatisfy { $0.offset == sky || $0.element.colorIndex == t.regions[$0.offset].colorIndex })
        Self.expectOthersUnchanged(t, v, added)
    }

    /// The shape under a fill is every region the ink round it encloses: found by flooding across the
    /// undrawn edges. A fill in one of several regions no ink separates joins them all; a shape that
    /// reaches the frame fills only the cell tapped.
    @Test func aFillTakesTheWholeShapeTheInkEncloses() throws {
        let t = Self.rich
        let art = t.lineArt!
        // The shape of a region, by the rule: undrawn edges lead on, drawn ones stop, the frame
        // makes the shape open.
        func shape(of start: Int) -> [Int] {
            var seen: Set = [start]
            var order = [start]
            var open = false
            var i = 0
            while i < order.count {
                let r = order[i]
                i += 1
                for (k, e) in t.edges.enumerated() where Int(e.left) == r || Int(e.right) == r {
                    if e.right == BoundaryEdge.outside { open = true; continue }
                    guard art.edgeLayers[k] == LineLayer.color.rawValue else { continue }
                    let other = Int(e.left) == r ? Int(e.right) : Int(e.left)
                    if seen.insert(other).inserted { order.append(other) }
                }
            }
            return open ? [start] : order.sorted()
        }
        let joined = try #require(t.regions.indices.first { shape(of: $0).count >= 2 })
        let members = shape(of: joined)
        let target = SIMD3<Float>(0.5, 0.15, 0.1)
        let tap = t.labels(ofRegion: joined).first!.position
        let (u, outcome) = try Self.apply(.fill(at: tap, color: target), to: t)
        #expect(u.regions.count == t.regions.count - (members.count - 1))
        #expect(outcome.regionsMerged == members.count - 1 && outcome.fills == 1)
        let area = try Self.region(u, tap.x, tap.y)
        #expect(u.isDetailRegion(area))
        #expect(abs(u.regions[area].area - members.reduce(0) { $0 + t.regions[$1].area }) < 0.1)
        #expect(members.allSatisfy { outcome.continued[$0] == area })
        // One area, one paint: that of the color asked.
        #expect(ColorScience.distance(u.palette[Int(u.regions[area].colorIndex)].oklab, target) < SegmentationParameters.jnd)
        Self.expectOthersUnchanged(t, u, outcome)
        // A shape that reaches the frame fills just the cell tapped.
        let open = try #require(t.regions.indices.first { r in
            t.edges.contains { $0.right == BoundaryEdge.outside && Int($0.left) == r } && shape(of: r).count == 1
        })
        let (v, one) = try Self.apply(.fill(at: t.labels(ofRegion: open).first!.position, color: target), to: t)
        #expect(one.regionsMerged == 0 && v.regions.count == t.regions.count)
    }

    // MARK: - Invariants

    /// Edits are exact, and the template stays what it is whatever is done to it: the same edits
    /// give the same bytes, which decode to the same template; the generator's bookkeeping (pipeline
    /// version, style) is as it was; and edits made one at a time or together agree.
    @Test func editsAreDeterministicAndRoundTrip() throws {
        let edits: [TemplateEditor.Edit] = [
            .draw(points: [SIMD2(15, -4), SIMD2(18.5, 30.25), SIMD2(15, 71)]),
            .draw(points: [SIMD2(100, 25), SIMD2(110.5, 31), SIMD2(104.1, 40)]),
            .erase(path: [SIMD2(55, 44), SIMD2(65, 44.5)], radius: 3),
            .fill(at: SIMD2(140, 55), color: SIMD3(0.7, -0.1, 0.1)),
            .eraseLine(at: SIMD2(10, 72), reach: 5),
        ]
        let (a, outcomesA) = try TemplateEditor.apply(edits, to: Self.scene)
        let (b, outcomesB) = try TemplateEditor.apply(edits, to: Self.scene)
        #expect(a.encoded() == b.encoded() && a == b && outcomesA == outcomesB)
        #expect(outcomesA.allSatisfy { $0.declined == nil && $0.changed })
        expectValid(a)
        let decoded = try Template(encoded: a.encoded())
        #expect(decoded == a && decoded.encoded() == a.encoded())
        #expect(a.pipelineVersion == Self.scene.pipelineVersion && a.lineArt?.style == .coloringBook)
        #expect(a.detailRegions.count >= 1)
        // Edge by edge the way a pipeline template is: the lower region on the left.
        #expect(a.edges.allSatisfy { $0.left < $0.right })
        var t = Self.scene
        for edit in edits { t = try TemplateEditor.apply(edit, to: t).template }
        #expect(t == a)
    }

    /// Edits that cannot be made leave the template as it was: a line that doubles back on itself,
    /// off the canvas, a tap off it. Hostile numbers are no trouble.
    @Test func editsThatCannotBeMadeLeaveTheTemplateAlone() throws {
        let t = Self.scene
        let (u, back) = try TemplateEditor.apply(.draw(points: [SIMD2(100, 10), SIMD2(100, 30), SIMD2(100, 20)]), to: t)
        #expect(!back.changed && back.declined != nil && u == t)
        for edit in [
            TemplateEditor.Edit.draw(points: []), .draw(points: [SIMD2(5, 5)]), .draw(points: [SIMD2(.nan, 3), SIMD2(4, .infinity)]),
            .draw(points: [SIMD2(-50, -50), SIMD2(-10, -10)]), .draw(points: [SIMD2(7, 7), SIMD2(7, 7)]),
            .draw(points: [SIMD2(1e30, 1e30), SIMD2(1e30, 2e30)]),
            .erase(path: [], radius: 3), .erase(path: [SIMD2(.nan, .nan)], radius: .nan), .eraseLine(at: SIMD2(.infinity, 0)),
            .fill(at: SIMD2(1e9, -1e9), color: SIMD3(0.5, 0, 0)), .fill(at: SIMD2(10, 10), color: SIMD3(.nan, 0, 0)),
        ] {
            let (same, outcome) = try TemplateEditor.apply(edit, to: t)
            #expect(same == t && !outcome.changed, "\(edit)")
        }
        // A classic template has no drawing to edit.
        var classic = t
        classic.lineArt = nil
        #expect(throws: TemplateEditor.Failure.self) { try TemplateEditor.apply(.draw(points: [SIMD2(1, 1), SIMD2(5, 5)]), to: classic) }
    }

    /// Cutting through the crowd leaves every region it did not touch bit for bit: outline, fill
    /// triangles, numbers, paint, strokes. Only the regions the line passes through, and those
    /// beside them that gained a vertex of their outline from it, are new.
    @Test func untouchedRegionsAreByteIdentical() throws {
        let t = Self.rich
        var rng = SplitMix64(seed: 5)
        var current = t
        var made = 0
        for _ in 0..<12 {
            let a = SIMD2(rng.nextFloat() * Float(t.width), rng.nextFloat() * Float(t.height))
            let b = a + SIMD2((rng.nextFloat() - 0.5) * 120, (rng.nextFloat() - 0.5) * 120)
            let mid = (a + b) / 2 + SIMD2((rng.nextFloat() - 0.5) * 30, (rng.nextFloat() - 0.5) * 30)
            let (next, outcome) = try TemplateEditor.apply(.draw(points: [a, mid, b]), to: current)
            if outcome.declined == nil, outcome.changed {
                Self.expectOthersUnchanged(current, next, outcome)
                made += 1
            }
            current = next
        }
        #expect(made >= 8)
        expectValid(current)
    }

    /// Random drawing, erasing and filling, in any order, over a crowded template: valid after every
    /// edit (an edit the exact arithmetic cannot make is declined, never made wrong), the paints
    /// only added to, every region numbered legibly.
    @Test func randomEditsKeepTheTemplateValid() throws {
        var made = 0, declined = 0
        for seed in [13, 14] as [UInt64] {
            var t = try Self.richBook(seed: seed)
            let palette = t.palette
            var rng = SplitMix64(seed: seed &* 7919)
            for step in 0..<70 {
                let edit = Self.randomEdit(t, &rng)
                let (next, outcome) = try TemplateEditor.apply(edit, to: t)
                if let why = outcome.declined {
                    declined += 1
                    // Only where lines lie closer than the lattice can tell apart.
                    let benign = ["the line", "the lines", "a line", "outlines", "the result is not valid: edges"].contains { why.reason.hasPrefix($0) }
                    #expect(benign, "seed \(seed) step \(step): \(edit) -> \(why)")
                    #expect(next == t)
                } else if outcome.changed {
                    made += 1
                }
                let report = next.validate(minLabelRadius: LabelSizing.minimumRadius)
                #expect(report.isValid, "seed \(seed) step \(step): \(edit) -> \(report)")
                #expect(Array(next.palette.prefix(palette.count)) == palette)
                t = next
            }
            #expect(try Template(encoded: t.encoded()) == t)
        }
        #expect(made >= 110 && declined <= 3, "\(made) edits made, \(declined) declined")
    }

    /// A random edit on `t`: lines between ink and across regions, loops, erasing, taps.
    static func randomEdit(_ t: Template, _ rng: inout SplitMix64) -> TemplateEditor.Edit {
        let w = Float(t.width), h = Float(t.height)
        func point(margin: Float = 0) -> SIMD2<Float> {
            SIMD2(-margin + rng.nextFloat() * (w + 2 * margin), -margin + rng.nextFloat() * (h + 2 * margin))
        }
        func inkVertex() -> SIMD2<Float> {
            let art = t.lineArt!
            let inked = t.edges.indices.filter { art.edgeLayers[$0] != LineLayer.color.rawValue }
            guard !inked.isEmpty else { return point() }
            let pts = t.points(of: t.edges[inked[Int(rng.next() % UInt64(inked.count))]])
            return pts[pts.startIndex + Int(rng.next() % UInt64(pts.count))]
        }
        func jitter(_ p: SIMD2<Float>, _ r: Float) -> SIMD2<Float> {
            p + SIMD2((rng.nextFloat() - 0.5) * 2 * r, (rng.nextFloat() - 0.5) * 2 * r)
        }
        switch rng.next() % 10 {
        case 0, 1, 2:
            let a = inkVertex(), b = inkVertex()
            return .draw(points: [jitter(a, 1.5), jitter((a + b) / 2, 25), jitter(b, 1.5)])
        case 3:
            var p = point(margin: 10)
            var pts = [p]
            for _ in 1..<(2 + Int(rng.next() % 5)) {
                p = jitter(p, 40)
                pts.append(p)
            }
            return .draw(points: pts)
        case 4:
            let c = point(), r = 3 + rng.nextFloat() * 30, n = 6 + Int(rng.next() % 10)
            let pts = (0..<n).map { i -> SIMD2<Float> in
                let a = Float(i) / Float(n) * 2 * .pi
                return c + SIMD2(cos(a), sin(a)) * r * (0.7 + 0.6 * rng.nextFloat())
            }
            return .draw(points: pts, closed: true)
        case 5:
            return .draw(points: [jitter(inkVertex(), 1), point()])
        case 6, 7:
            var p = jitter(inkVertex(), 6)
            var pts = [p]
            for _ in 1..<(1 + Int(rng.next() % 3)) {
                p = jitter(p, 15)
                pts.append(p)
            }
            return .erase(path: pts, radius: 1 + rng.nextFloat() * 10)
        case 8:
            return .eraseLine(at: jitter(inkVertex(), 3), reach: 8)
        default:
            let color: SIMD3<Float> = rng.next() % 2 == 0
                ? t.palette[Int(rng.next() % UInt64(t.palette.count))].oklab + SIMD3(0.004, 0, 0)
                : SIMD3(0.3 + rng.nextFloat() * 0.6, (rng.nextFloat() - 0.5) * 0.2, (rng.nextFloat() - 0.5) * 0.2)
            return .fill(at: point(), color: color)
        }
    }
}
