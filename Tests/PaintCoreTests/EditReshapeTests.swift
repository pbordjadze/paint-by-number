import Foundation
import Testing
@testable import PaintCore

/// Refine's Bend Line and Move Edge (`TemplateEditor.Edit.reshape`): the line under a drag's start,
/// from junction to junction, bent so its grabbed point goes where the finger lifts, its ends
/// held. On the editor's scene (`TemplateEditorTests`: the inked horizon runs straight from the
/// disc at (89, 72) to the square at (119, 72), the ground's detail stroke from (0.5, 119.5) to
/// (191.5, 121) touches nothing) and on Only This Area's base (`EditPaintAreaTests`: the sky split
/// at y = 40 along an undrawn boundary from frame to frame, two boxes drawn in the sky above it).
@Suite("Edit reshape")
struct EditReshapeTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    static let base = EditPaintAreaTests.base
    static let sky = SIMD2<Float>(104, 50), ground = SIMD2<Float>(104, 90)

    static func region(_ t: Template, _ p: SIMD2<Float>) throws -> Int { try TemplateEditorTests.region(t, p.x, p.y) }
    static func paint(_ t: Template, _ p: SIMD2<Float>) throws -> SIMD3<Float> {
        t.palette[Int(t.regions[try region(t, p)].colorIndex)].oklab
    }

    /// The edges of `t` between two regions.
    static func between(_ t: Template, _ a: Int, _ b: Int) -> [Int] {
        t.edges.indices.filter { Set([Int(t.edges[$0].left), Int(t.edges[$0].right)]) == Set([a, b]) }
    }

    static func declined(_ edit: Edit, on t: Template) throws -> String? {
        let (u, outcome) = try TemplateEditor.apply(edit, to: t)
        if outcome.declined != nil { #expect(u == t && !outcome.changed) }
        return outcome.declined?.reason
    }

    /// The horizon between the disc and the square bent up 12 units: the ground grows into the
    /// sky under it, both keep their paints, the line its ink and its ends; the bend is laid in
    /// steps of a few units, and the preview is the line laid.
    @Test func anInkedBoundaryBendsAndBothAreasFollow() throws {
        let t = Self.scene
        let edit = Edit.reshape(from: SIMD2(104, 72), to: SIMD2(104, 60))
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        #expect(outcome.reshaped == 1 && outcome.regionsSplit == 0 && outcome.regionsMerged == 0 && outcome.paintsAdded == 0)
        let sky = try Self.region(t, Self.sky), ground = try Self.region(t, Self.ground)
        #expect(try Self.region(u, SIMD2(104, 64)) == outcome.continued[ground], "the ground came up under the bend")
        #expect(try Self.region(u, SIMD2(104, 58)) == outcome.continued[sky])
        #expect(u.palette == t.palette && u.regions.count == t.regions.count)
        #expect(try Self.paint(u, SIMD2(104, 64)) == Self.paint(t, Self.ground))
        #expect(u.regions[outcome.continued[ground]].area > t.regions[ground].area + 100)
        #expect(u.regions[outcome.continued[sky]].area < t.regions[sky].area - 100)
        let line = try #require(Self.between(u, outcome.continued[sky], outcome.continued[ground]).first {
            Array(u.points(of: u.edges[$0])).contains(SIMD2(104, 60))
        })
        let pts = Array(u.points(of: u.edges[line]))
        #expect(u.lineArt!.edgeLayers[line] == LineLayer.outline.rawValue, "inked stays inked")
        #expect(Set([pts.first!, pts.last!]) == Set([SIMD2<Float>(89, 72), SIMD2(119, 72)]))
        #expect(pts.count >= 10 && zip(pts, pts.dropFirst()).allSatisfy { simdLength($1 - $0) <= 3.02 })
        #expect(u.lineArt!.strokes == t.lineArt!.strokes)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
        #expect(try TemplateEditor.apply(edit, to: t).template.encoded() == u.encoded())
        #expect(try Template(encoded: u.encoded()) == u)

        let preview = try #require(TemplateEditor.reshapedChain(on: t, from: SIMD2(104, 72), to: SIMD2(104, 60)))
        #expect(Set([preview.original.first!, preview.original.last!]) == Set([SIMD2<Float>(89, 72), SIMD2(119, 72)]))
        #expect(preview.original.count == 2)
        #expect(preview.moved == pts || preview.moved == pts.reversed())
    }

    /// The undrawn split across the sky moved down 4 units at x = 104 (clear of the disc and
    /// the square below it): the upper sky takes the room, the boundary stays undrawn and on the
    /// frame at both ends.
    @Test func anUndrawnBoundaryMoves() throws {
        let t = Self.base
        let upper = try Self.region(t, EditPaintAreaTests.upper), lower = try Self.region(t, EditPaintAreaTests.lower)
        let (u, outcome) = try TemplateEditorTests.apply(.reshape(from: SIMD2(104, 40), to: SIMD2(104, 44)), to: t)
        #expect(try Self.region(u, SIMD2(104, 43)) == outcome.continued[upper])
        #expect(try Self.region(u, SIMD2(104, 45)) == outcome.continued[lower])
        #expect(try Self.region(u, SIMD2(190, 41)) == outcome.continued[lower])
        #expect(u.palette == t.palette)
        let edges = Self.between(u, outcome.continued[upper], outcome.continued[lower])
        #expect(!edges.isEmpty && edges.allSatisfy { u.lineArt!.edgeLayers[$0] == LineLayer.color.rawValue })
        let ends = Set(edges.flatMap { [u.points(of: u.edges[$0]).first!, u.points(of: u.edges[$0]).last!] })
        #expect(ends.contains(SIMD2(0, 40)) && ends.contains(SIMD2(192, 40)))
        #expect(u.regions[outcome.continued[upper]].area > t.regions[upper].area)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    static func strokePoints(_ t: Template, _ k: Int) -> [SIMD2<Float>] {
        let s = t.lineArt!.strokes[k]
        return Array(t.lineArt!.strokePoints[Int(s.pointStart)..<Int(s.pointStart + s.pointCount)])
    }

    /// A short stroke drawn in the ground touches nothing at either end, both within the bend's
    /// spread: dragged, it moves whole, and nothing but it (and the ground's numbers, kept off
    /// it) changes.
    @Test func aShortStrokeFreeAtBothEndsMovesWhole() throws {
        let t = try TemplateEditorTests.apply(.draw(points: [SIMD2(60, 108), SIMD2(80, 108)]), to: Self.scene).0
        let k = try #require(t.lineArt!.strokes.indices.first { Self.strokePoints(t, $0).contains(SIMD2(60, 108)) })
        let stroke = t.lineArt!.strokes[k], before = Self.strokePoints(t, k)
        let (u, outcome) = try TemplateEditorTests.apply(.reshape(from: SIMD2(70, 108.5), to: SIMD2(70, 112)), to: t)
        #expect(outcome.reshaped == 1)
        let moved = u.lineArt!.strokes[k], after = Self.strokePoints(u, k)
        #expect(Int(moved.region) == outcome.continued[Int(stroke.region)] && moved.layer == stroke.layer && moved.weight == stroke.weight)
        #expect(after.contains(SIMD2(70, 112)), "the grabbed point lands under the finger")
        #expect(before.allSatisfy { after.contains($0 + SIMD2(0, 4)) }, "\(before) \(after)")
        #expect(u.polygons(ofRegion: Int(moved.region)) == t.polygons(ofRegion: Int(stroke.region)), "no outline moves")
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// The ground's detail stroke runs the canvas's width, free at both ends: grabbed in the
    /// middle, it bends only within the spread of the grab (24 units for a short drag), its ends
    /// and everything beyond the spread exactly where they were.
    @Test func aLongStrokeBendsOnlyNearTheGrab() throws {
        let t = Self.scene
        let before = Self.strokePoints(t, 0)
        let (u, outcome) = try TemplateEditorTests.apply(.reshape(from: SIMD2(96, 120.3), to: SIMD2(96, 126)), to: t)
        #expect(outcome.reshaped == 1)
        let after = Self.strokePoints(u, 0)
        #expect(after.contains(SIMD2(96, 126)))
        #expect(after.first == before.first && after.last == before.last)
        let far = after.filter { abs($0.x - 96) > 24.01 }
        #expect(far.count >= 2 && far.allSatisfy { before.contains($0) }, "beyond the spread the stroke is as it lay")
        #expect(before.filter { abs($0.x - 96) > 24.01 }.allSatisfy { after.contains($0) })
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// The undrawn split runs 192 units from frame to frame: grabbed in the middle and dragged 4
    /// units, it bends between x = 80 and 128, made vertices, and is as it lay beyond them; the
    /// preview says the same.
    @Test func aLongChainBendsOnlyNearTheGrab() throws {
        let t = Self.base
        let edit = Edit.reshape(from: SIMD2(104, 40), to: SIMD2(104, 44))
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        let upper = try Self.region(t, EditPaintAreaTests.upper), lower = try Self.region(t, EditPaintAreaTests.lower)
        let edges = Self.between(u, outcome.continued[upper], outcome.continued[lower])
        #expect(edges.count == 1)
        let pts = Array(u.points(of: u.edges[edges[0]]))
        #expect(Set([pts.first!, pts.last!]) == Set([SIMD2<Float>(0, 40), SIMD2(192, 40)]))
        #expect(pts.contains(SIMD2(80, 40)) && pts.contains(SIMD2(128, 40)) && pts.contains(SIMD2(104, 44)))
        #expect(pts.filter { $0.x <= 80 || $0.x >= 128 }.count == 4, "only the ends and where the bend ends, beyond it")
        #expect(pts.allSatisfy { $0.x > 80 && $0.x < 128 || $0.y == 40 })
        let preview = try #require(TemplateEditor.reshapedChain(on: t, from: SIMD2(104, 40), to: SIMD2(104, 44)))
        #expect(preview.moved == pts || preview.moved == pts.reversed())
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// A stroke drawn down from the horizon ends on it: bent, the horizon carries the stroke's end.
    @Test func aStrokeEndingOnTheLineIsCarried() throws {
        let drawn = try TemplateEditorTests.apply(.draw(points: [SIMD2(104, 72), SIMD2(104, 100)]), to: Self.scene).0
        #expect(drawn.lineArt!.strokes.count == 2)
        let (u, outcome) = try TemplateEditorTests.apply(.reshape(from: SIMD2(104, 72), to: SIMD2(104, 66)), to: drawn)
        #expect(outcome.reshaped == 2, "the line and the stroke it carries")
        let art = u.lineArt!
        let ends = art.strokes.map { s in
            [art.strokePoints[Int(s.pointStart)], art.strokePoints[Int(s.pointStart + s.pointCount) - 1]]
        }
        #expect(ends.contains { Set($0) == Set([SIMD2<Float>(104, 66), SIMD2(104, 100)]) })
        TemplateEditorTests.expectOthersUnchanged(drawn, u, outcome)
    }

    /// A box drawn in the sky is a loop through no junction, 76 units round: dragged 6 units at
    /// its top, it bends within 24 units either side, its bottom where it was.
    @Test func aLoopBendsNearTheGrab() throws {
        let t = Self.base
        let box = try Self.region(t, EditPaintAreaTests.inA)
        let (u, outcome) = try TemplateEditorTests.apply(.reshape(from: SIMD2(101, 12), to: SIMD2(101, 6)), to: t)
        #expect(try Self.region(u, SIMD2(101, 8)) == outcome.continued[box])
        let ring = u.polygons(ofRegion: outcome.continued[box])[0]
        #expect(ring.contains(SIMD2(90, 28)) && ring.contains(SIMD2(112, 28)) && ring.contains(SIMD2(90, 25)) && ring.contains(SIMD2(112, 25)),
            "the bottom stays, the bend ending 24 units from the grab")
        #expect(u.regions[outcome.continued[box]].area > t.regions[box].area)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// A bend far up into the sky stays a simple, smooth line between its junctions.
    @Test func aBigBendIsSmooth() throws {
        let t = Self.scene
        let (u, outcome) = try TemplateEditorTests.apply(.reshape(from: SIMD2(104, 72), to: SIMD2(110, 10)), to: t)
        #expect(outcome.reshaped == 1)
        let line = try #require(u.edges.indices.first { Array(u.points(of: u.edges[$0])).contains(SIMD2(110, 10)) })
        let pts = Array(u.points(of: u.edges[line]))
        #expect(pts.count >= 40 && zip(pts, pts.dropFirst()).allSatisfy { simdLength($1 - $0) <= 3.02 })
    }

    @Test func declines() throws {
        // Across the split at y = 40.
        #expect(try Self.declined(.reshape(from: SIMD2(104, 72), to: SIMD2(104, 30)), on: Self.base)?.contains("meet") == true)
        // Off the canvas.
        #expect(try Self.declined(.reshape(from: SIMD2(104, 72), to: SIMD2(104, -4)), on: Self.scene)?.contains("canvas") == true)
        // Near no line, and near the frame alone, which can't be grabbed.
        #expect(try Self.declined(.reshape(from: SIMD2(100, 20), to: SIMD2(100, 30)), on: Self.scene)?.contains("no line") == true)
        #expect(try Self.declined(.reshape(from: SIMD2(100, 1), to: SIMD2(100, 9)), on: Self.scene)?.contains("no line") == true)
        // A junction is held.
        #expect(try Self.declined(.reshape(from: SIMD2(89, 72), to: SIMD2(89, 60)), on: Self.scene)?.contains("held") == true)
        // A small box squeezed flat has no room for its number.
        let boxed = try TemplateEditorTests.apply(
            .draw(points: [SIMD2(100, 100), SIMD2(104, 100), SIMD2(104, 104), SIMD2(100, 104)], closed: true), to: Self.scene).0
        #expect(try Self.declined(.reshape(from: SIMD2(102, 100), to: SIMD2(102, 103.5)), on: boxed)?.contains("room") == true)
        // Grabbed and dropped in place: nothing.
        let (same, outcome) = try TemplateEditor.apply(.reshape(from: SIMD2(104, 72), to: SIMD2(104, 72)), to: Self.scene)
        #expect(!outcome.changed && outcome.declined == nil && same == Self.scene)
    }

    @Test func codingRoundTrips() throws {
        let edit = Edit.reshape(from: SIMD2(104, 72), to: SIMD2(104.5, 60.25), reach: 12)
        let data = try JSONEncoder().encode(edit)
        #expect(try JSONDecoder().decode(Edit.self, from: data) == edit)
        let bare = Data(#"{"kind": "reshape", "points": [[1, 2], [3, 4]]}"#.utf8)
        #expect(try JSONDecoder().decode(Edit.self, from: bare) == .reshape(from: SIMD2(1, 2), to: SIMD2(3, 4)))
        let one = Data(#"{"kind": "reshape", "points": [[1, 2]]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Edit.self, from: one) }
        #expect(TemplateEditor.recolored(edit, by: [.look(.moonlit, strength: 1)]) == edit)
    }

    /// On the crowded book, bends of lines all over the canvas either are laid, validating with
    /// everything they leave alone as it was, or are declined leaving the template as it was.
    @Test func bendsOnACrowdedBookValidate() throws {
        let t = TemplateEditorTests.rich
        var rng = SplitMix64(seed: 7)
        var made = 0
        for _ in 0..<24 {
            let e = Int(rng.next() % UInt64(t.edges.count))
            guard t.edges[e].right != BoundaryEdge.outside else { continue }
            let pts = Array(t.points(of: t.edges[e]))
            let k = (pts.count - 1) / 2
            let from = (pts[k] + pts[k + 1]) / 2
            let to = from + SIMD2(Float(Int(rng.next() % 13) - 6), Float(Int(rng.next() % 13) - 6))
            let (u, outcome) = try TemplateEditor.apply(.reshape(from: from, to: to), to: t)
            if outcome.declined != nil {
                #expect(u == t)
                continue
            }
            expectValid(u)
            TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
            if outcome.changed { made += 1 }
        }
        #expect(made >= 12)
    }
}
