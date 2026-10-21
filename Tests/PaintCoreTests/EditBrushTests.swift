import Foundation
import Testing
@testable import PaintCore

/// Refine's Paint Brush (`TemplateEditor.Edit.brush`): what lies within the radius of a stroke
/// takes a paint, its outline laid as a closed cell edge, ink untouched, and areas of that paint
/// across an undrawn boundary one area. On the editor's scene (`TemplateEditorTests`: sky above an
/// inked horizon at y ≈ 72, ground below, an outlined disc and square straddling it) and on Only
/// This Area's base (`EditPaintAreaTests`: the sky split at y = 40 along an undrawn boundary, its
/// lower part a shade of the sky's paint).
@Suite("Edit brush")
struct EditBrushTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    static let base = EditPaintAreaTests.base
    static let upper = EditPaintAreaTests.upper, lower = EditPaintAreaTests.lower
    static let ground = SIMD2<Float>(100, 130)
    static let magenta = SIMD3<Float>(0.62, 0.2, -0.1)

    static func region(_ t: Template, _ p: SIMD2<Float>) throws -> Int { try TemplateEditorTests.region(t, p.x, p.y) }
    static func paint(_ t: Template, _ p: SIMD2<Float>) throws -> SIMD3<Float> {
        t.palette[Int(t.regions[try region(t, p)].colorIndex)].oklab
    }

    /// Painted with the upper sky's paint along the undrawn split below it, the upper sky grows
    /// down into the lower one: one area still, no paint added or lost, no new cell, no ink.
    @Test func aStrokeAlongACellsEdgeGrowsIt() throws {
        let t = Self.base
        let skyPaint = try Self.paint(t, Self.upper)
        let stroke = Edit.brush(path: [SIMD2(20, 40), SIMD2(80, 40)], radius: 5, color: skyPaint)
        let (u, outcome) = try TemplateEditorTests.apply(stroke, to: t)
        #expect(outcome.changed && outcome.recolored >= 1 && outcome.paintsAdded == 0 && outcome.strokes == 0)
        let sky = try Self.region(u, Self.upper)
        #expect(try Self.region(u, SIMD2(50, 43)) == sky, "the stroke's lower half is the sky's now")
        #expect(try Self.region(u, SIMD2(50, 37)) == sky && Self.region(u, Self.lower) != sky)
        #expect(try Self.region(u, SIMD2(40, 48)) == Self.region(u, Self.lower), "past the stroke the lower sky stays")
        #expect(u.regions.count == t.regions.count && u.palette == t.palette)
        #expect(u.lineArt!.strokes == t.lineArt!.strokes)
        let skyBefore = try Self.region(t, Self.upper)
        #expect(u.regions[sky].area > t.regions[skyBefore].area)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
        #expect(try TemplateEditor.apply(stroke, to: t).template.encoded() == u.encoded())
    }

    /// A dab in the ground makes a cell of a new paint, added last, inside it: the ground has a
    /// hole for it, and nothing else changes.
    @Test func aDabMakesANewCellInsideAnArea() throws {
        let t = Self.scene
        let ground = try Self.region(t, Self.ground)
        let dab = Edit.brush(path: [SIMD2(100, 100)], radius: 8, color: Self.magenta)
        let (u, outcome) = try TemplateEditorTests.apply(dab, to: t)
        #expect(outcome.regionsSplit == 1 && outcome.paintsAdded == 1 && outcome.recolored == 1)
        #expect(u.palette == t.palette + [PaletteColor(oklab: Self.magenta, space: t.colorSpace)])
        let cell = try Self.region(u, SIMD2(100, 100))
        #expect(try Self.region(u, Self.ground) != cell && Int(u.regions[cell].colorIndex) == t.palette.count)
        #expect(!u.isDetailRegion(cell))
        #expect(abs(u.regions[cell].area - .pi * 64) < 4, "a disc of radius 8: \(u.regions[cell].area)")
        let groundNow = try Self.region(u, Self.ground)
        #expect(u.polygons(ofRegion: groundNow).count == t.polygons(ofRegion: ground).count + 1)
        #expect(u.regions[groundNow].colorIndex == t.regions[ground].colorIndex)
        let between = u.edges.indices.filter { e in
            Set([Int(u.edges[e].left), Int(u.edges[e].right)]) == Set([cell, groundNow])
        }
        #expect(!between.isEmpty && between.allSatisfy { u.lineArt!.edgeLayers[$0] == LineLayer.color.rawValue })
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
        #expect(try Template(encoded: u.encoded()) == u)
        #expect(try TemplateEditor.apply(dab, to: t).template.encoded() == u.encoded())
    }

    /// Across the inked horizon: a cell of the paint on either side, the horizon still inked
    /// between them, the paint added once.
    @Test func aStrokeAcrossInkLeavesTwoCells() throws {
        let t = Self.scene
        let stroke = Edit.brush(path: [SIMD2(100, 60), SIMD2(100, 85)], radius: 6, color: Self.magenta)
        let (u, outcome) = try TemplateEditorTests.apply(stroke, to: t)
        #expect(outcome.regionsSplit == 2 && outcome.paintsAdded == 1 && outcome.recolored == 2 && outcome.regionsMerged == 0)
        let above = try Self.region(u, SIMD2(100, 64)), below = try Self.region(u, SIMD2(100, 80))
        #expect(above != below && u.regions.count == t.regions.count + 2)
        #expect(Int(u.regions[above].colorIndex) == t.palette.count && Int(u.regions[below].colorIndex) == t.palette.count)
        let between = u.edges.indices.filter { e in Set([Int(u.edges[e].left), Int(u.edges[e].right)]) == Set([above, below]) }
        #expect(!between.isEmpty && between.allSatisfy { u.lineArt!.edgeLayers[$0] != LineLayer.color.rawValue }, "the horizon")
        #expect(u.lineArt!.strokes == t.lineArt!.strokes)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// A dab over a whole box drawn in the sky paints the box, untouched by its outline, and the
    /// sky round it: two cells of the brush's paint, the box's ink between them.
    @Test func aCellWhollyInsideIsPainted() throws {
        let t = Self.base
        let box = try Self.region(t, EditPaintAreaTests.inA)
        let (u, outcome) = try TemplateEditorTests.apply(.brush(path: [SIMD2(101, 20)], radius: 16, color: Self.magenta), to: t)
        let boxNow = try Self.region(u, EditPaintAreaTests.inA), around = try Self.region(u, SIMD2(101, 8))
        #expect(outcome.recolored == 2 && boxNow != around && outcome.continued[box] == boxNow)
        #expect(u.polygons(ofRegion: boxNow) == t.polygons(ofRegion: box), "the box keeps its outline")
        #expect(Int(u.regions[boxNow].colorIndex) == t.palette.count && Int(u.regions[around].colorIndex) == t.palette.count)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// A stroke round a loop leaves the ground it encloses as it was, an area of its own inside
    /// the ring of paint.
    @Test func aLoopLeavesWhatItEncloses() throws {
        let t = Self.scene
        let loop: [SIMD2<Float>] = [SIMD2(60, 105), SIMD2(140, 105), SIMD2(140, 138), SIMD2(60, 138), SIMD2(60, 105)]
        let (u, outcome) = try TemplateEditorTests.apply(.brush(path: loop, radius: 3, color: Self.magenta), to: t)
        let ring = try Self.region(u, SIMD2(100, 105)), enclosed = try Self.region(u, SIMD2(100, 125))
        let ground = try Self.region(u, SIMD2(20, 125))
        #expect(Set([ring, enclosed, ground]).count == 3 && outcome.paintsAdded == 1)
        #expect(Int(u.regions[ring].colorIndex) == t.palette.count)
        #expect(u.regions[enclosed].colorIndex == u.regions[ground].colorIndex)
        #expect(u.polygons(ofRegion: ring).count == 2, "a ring round the enclosed ground")
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
    }

    /// A dab half off the canvas paints the half on it, a cell against the frame; one wholly off
    /// it changes nothing.
    @Test func aDabHalfOffTheCanvasPaintsTheHalfOnIt() throws {
        let t = Self.scene
        let (u, outcome) = try TemplateEditorTests.apply(.brush(path: [SIMD2(0, 110)], radius: 10, color: Self.magenta), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.paintsAdded == 1)
        let cell = try Self.region(u, SIMD2(3, 110))
        #expect(Int(u.regions[cell].colorIndex) == t.palette.count)
        #expect(abs(u.regions[cell].area - .pi * 50) < 4, "half a disc of radius 10: \(u.regions[cell].area)")
        #expect(u.polygons(ofRegion: cell).allSatisfy { $0.allSatisfy { $0.x >= 0 && $0.x <= 10.01 } })
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)

        let (same, off) = try TemplateEditor.apply(.brush(path: [SIMD2(-50, 110), SIMD2(-30, 20)], radius: 10, color: Self.magenta), to: t)
        #expect(!off.changed && off.declined == nil && same == t)
    }

    /// A stroke of the paint its area has changes nothing; one too fine for a number, even a
    /// detail area's, is declined.
    @Test func nothingNewIsNothingAndTooFineIsDeclined() throws {
        let t = Self.scene
        let groundPaint = try Self.paint(t, Self.ground)
        let (same, outcome) = try TemplateEditor.apply(.brush(path: [SIMD2(100, 100), SIMD2(140, 105)], radius: 6, color: groundPaint), to: t)
        #expect(!outcome.changed && outcome.declined == nil && same == t)
        let (fine, declined) = try TemplateEditor.apply(.brush(path: [SIMD2(100, 100), SIMD2(140, 105)], radius: 0.5, color: Self.magenta), to: t)
        #expect(declined.declined?.reason.contains("no room for a number") == true && fine == t)
        var trail = EditTrail(base: t)
        if case .declined = trail.add(.brush(path: [SIMD2(100, 100)], radius: 0.5, color: Self.magenta)) {} else {
            Issue.record("not declined")
        }
        #expect(trail.edits.isEmpty)
    }

    /// A long stroke over many cells of the crowded book gives a template that validates, the
    /// same bytes each time.
    @Test func aLongStrokeOverACrowdedBookValidates() throws {
        let t = TemplateEditorTests.rich
        let path = (0...29).map { k in SIMD2<Float>(20 + Float(k) * 6.5, 80 + 40 * sin(Float(k) * 0.4)) }
        let stroke = Edit.brush(path: path, radius: 7, color: Self.magenta)
        let (u, outcome) = try TemplateEditorTests.apply(stroke, to: t)
        #expect(outcome.changed && outcome.recolored > 0)
        #expect(try TemplateEditor.apply(stroke, to: t).template.encoded() == u.encoded())
        // The stroke's middle is the brush's paint, but where a cell's part inside it was too thin
        // for a number and stayed uncut.
        let paint = u.palette.firstIndex { $0.oklab == Self.magenta }
        let painted = path.filter { p in u.region(at: p).map { Int(u.regions[$0].colorIndex) } == paint }
        #expect(painted.count * 4 >= path.count * 3, "\(painted.count) of \(path.count)")
    }

    /// The outline of a disc: one ring, the footprint on its left, within a fortieth of the radius
    /// of the circle and its vertices clear of the frame lines.
    @Test func theOutlineOfADabIsACircle() {
        let unit = Lattice.unit
        let centre = LatticePoint(50 * unit, 40 * unit)
        let footprint = BrushFootprint(path: [centre], radius: 10 * unit)!
        let rings = footprint.outline(width: 100 * unit, height: 80 * unit)
        #expect(rings.count == 1 && Lattice.area2(rings[0]) > 0)
        for p in rings[0] {
            let d = Double(Lattice.distanceSquared(p, centre)).squareRoot() / Double(unit)
            #expect(abs(d - 10) < 0.3, "\(d)")
        }
        let ring = BrushFootprint(path: [LatticePoint(0, 40 * unit)], radius: 10 * unit)!.outline(width: 100 * unit, height: 80 * unit)
        #expect(ring.count == 1 && ring[0].allSatisfy { $0.x != 0 })
    }

    /// Kept in a file with its radius and color; a look laid before it leaves its color as sent.
    @Test func itIsKeptInFiles() throws {
        let edit = Edit.brush(path: [SIMD2(1, 2), SIMD2(30, 40.5)], radius: 6, color: SIMD3(0.5, 0.25, -0.125))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode([edit]), as: UTF8.self)
        #expect(json == #"[{"color":[0.5,0.25,-0.125],"kind":"brush","points":[[1,2],[30,40.5]],"radius":6}]"#)
        #expect(try JSONDecoder().decode([Edit].self, from: Data(json.utf8)) == [edit])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Edit.self, from: Data(#"{"kind":"brush","points":[[1,2]]}"#.utf8)) }
        let look = TemplateEditor.look(.moonlit, strength: 1, on: Self.scene)
        #expect(!TemplateEditor.isRecolor(edit) && TemplateEditor.recolored(edit, by: [look]) == edit)
    }

    /// Refine's brush sends its stroke in canvas units, thinned, its radius 12 points on screen
    /// (2.4 units at 5 points to a unit); no touch sends nothing.
    @Test func theGestureIsTheStrokeAtTheBrushsSize() throws {
        let screen = RefineGesturesTests.screen
        #expect(abs(screen.brushRadius - 12 / 960) < 1e-6)
        let samples = (0...20).map { RefineGesturesTests.p(100 + Float($0) * 2, 100) }
        let edit = try #require(RefineGestures.brush(samples, on: screen, color: Self.magenta))
        guard case .brush(let path, let radius, let color) = edit else { Issue.record("\(edit)"); return }
        #expect(path.count == 2 && simdLength(path[0] - SIMD2(100, 100)) < 1e-3 && simdLength(path[1] - SIMD2(140, 100)) < 1e-3)
        #expect(abs(radius - 2.4) < 1e-4 && color == Self.magenta)
        #expect(RefineGestures.brush([], on: screen, color: Self.magenta) == nil)
        // The app's Size: twice the radius on screen, twice the reach.
        guard case .brush(_, let wide, _)? = RefineGestures.brush(samples, on: screen, color: Self.magenta, radius: 24),
              case .brush(_, let standard, _) = edit
        else { Issue.record("not a brush"); return }
        #expect(abs(wide - 2 * standard) < 1e-3)
    }
}
