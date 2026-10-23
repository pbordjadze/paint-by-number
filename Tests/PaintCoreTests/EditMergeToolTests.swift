import Foundation
import Testing
@testable import PaintCore

/// Refine's Merge (`TemplateEditor.Edit.merge`): a drag across cells joins them into the first,
/// the boundaries between them gone, ink and all. On the editor's scene (`TemplateEditorTests`:
/// sky above an inked horizon at y ≈ 72, ground below, an outlined disc round (60, 72) and square
/// over x 120..<168 straddling it, each of the four the only area of its paint) and on Only This
/// Area's base (`EditPaintAreaTests`: two boxes of the sky's paint drawn in the sky, the sky split
/// below them).
@Suite("Edit merge")
struct EditMergeToolTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    static let base = EditPaintAreaTests.base
    static let sky = SIMD2<Float>(100, 30), ground = SIMD2<Float>(100, 120)
    static let disc = SIMD2<Float>(60, 72), square = SIMD2<Float>(144, 69)
    static let inA = EditPaintAreaTests.inA, inB = EditPaintAreaTests.inB, upper = EditPaintAreaTests.upper
    static let magenta = SIMD3<Float>(0.62, 0.2, -0.1)

    static func region(_ t: Template, _ p: SIMD2<Float>) throws -> Int { try TemplateEditorTests.region(t, p.x, p.y) }

    /// The palette without the paints `gone`.
    static func palette(_ t: Template, without gone: Set<Int>) -> [PaletteColor] {
        t.palette.indices.filter { !gone.contains($0) }.map { t.palette[$0] }
    }

    /// Down across the inked horizon: the sky and the ground are one area of the sky's paint, the
    /// horizon gone with no stroke left of it, the disc and the square islands in it now, and the
    /// ground's paint, with no area left, out of the palette.
    @Test func aMergeAcrossInkTakesTheInkAway() throws {
        let t = Self.scene
        let sky = try Self.region(t, Self.sky), ground = try Self.region(t, Self.ground)
        let horizon = t.edges.indices.filter { e in
            Set([Int(t.edges[e].left), Int(t.edges[e].right)]) == Set([sky, ground])
        }
        #expect(!horizon.isEmpty && horizon.allSatisfy { t.lineArt!.edgeLayers[$0] != LineLayer.color.rawValue })
        let (u, outcome) = try TemplateEditorTests.apply(.merge(points: [Self.sky, Self.ground]), to: t)
        #expect(outcome.changed && outcome.regionsMerged == 1 && outcome.paintsMerged == 1 && outcome.strokes == 0)
        let joined = try Self.region(u, Self.sky)
        #expect(try Self.region(u, Self.ground) == joined && u.regions.count == t.regions.count - 1)
        #expect(u.palette == Self.palette(t, without: [Int(t.regions[ground].colorIndex)]))
        #expect(u.palette[Int(u.regions[joined].colorIndex)] == t.palette[Int(t.regions[sky].colorIndex)])
        #expect(u.lineArt!.strokes.count == t.lineArt!.strokes.count, "the horizon leaves no stroke")
        for e in horizon { #expect(!TemplateEditorTests.inked(u, Array(t.points(of: t.edges[e])))) }
        #expect(u.polygons(ofRegion: joined).count == 3, "the frame, and the disc and square as islands")
        #expect(outcome.continued[sky] == joined && outcome.continued[ground] == joined)
        #expect(!u.isDetailRegion(joined))
        #expect(try Template(encoded: u.encoded()) == u)
        #expect(try TemplateEditor.apply(.merge(points: [Self.sky, Self.ground]), to: t).template.encoded() == u.encoded())
    }

    /// Disc, sky, square along one drag: one area of the disc's paint, the sky's and the square's
    /// paints leaving the palette and the numbers after them closing up.
    @Test func threeAreasTakeTheFirstsPaint() throws {
        let t = Self.scene
        let disc = try Self.region(t, Self.disc), sky = try Self.region(t, Self.sky), square = try Self.region(t, Self.square)
        #expect(try Self.region(t, SIMD2(100, 69)) == sky)
        let (u, outcome) = try TemplateEditorTests.apply(.merge(points: [Self.disc, SIMD2(100, 69), Self.square]), to: t)
        #expect(outcome.regionsMerged == 2 && outcome.paintsMerged == 2)
        let joined = try Self.region(u, Self.disc)
        #expect(try Self.region(u, Self.sky) == joined && Self.region(u, Self.square) == joined)
        #expect(u.regions.count == t.regions.count - 2)
        #expect(u.palette == Self.palette(t, without: [Int(t.regions[sky].colorIndex), Int(t.regions[square].colorIndex)]))
        #expect(u.palette[Int(u.regions[joined].colorIndex)] == t.palette[Int(t.regions[disc].colorIndex)])
        let ground = try Self.region(u, Self.ground), groundBefore = try Self.region(t, Self.ground)
        #expect(u.palette[Int(u.regions[ground].colorIndex)] == t.palette[Int(t.regions[groundBefore].colorIndex)])
        for label in u.labels {
            #expect(Int(u.regions[Int(label.region)].colorIndex) < u.palette.count)
        }
    }

    /// A box painted its own paint, merged with the sky round it: from the box, the sky takes the
    /// box's paint and the sky's paint goes; from the sky, the box is gone from the sky's rings
    /// and its paint goes.
    @Test func anAreaJoinsTheOneRoundIt() throws {
        let t = try TemplateEditor.apply(.paintArea(at: Self.inA, color: Self.magenta), to: Self.base).template
        let box = try Self.region(t, Self.inA), sky = try Self.region(t, Self.upper)
        let skyPaint = t.palette[Int(t.regions[sky].colorIndex)]
        #expect(t.polygons(ofRegion: sky).count == 3, "the sky round both boxes")

        let (fromBox, a) = try TemplateEditorTests.apply(.merge(points: [Self.inA, Self.upper]), to: t)
        let joinedA = try Self.region(fromBox, Self.upper)
        #expect(try a.regionsMerged == 1 && Self.region(fromBox, Self.inA) == joinedA && a.continued[box] == joinedA)
        #expect(fromBox.palette[Int(fromBox.regions[joinedA].colorIndex)].oklab == Self.magenta)
        // The sky's paint is the boxes' too: box B keeps it, so it stays.
        #expect(fromBox.palette == t.palette && a.paintsMerged == 0)
        #expect(fromBox.polygons(ofRegion: joinedA).count == 2, "box B is still an island")

        let (fromSky, b) = try TemplateEditorTests.apply(.merge(points: [Self.upper, Self.inA]), to: t)
        let joinedB = try Self.region(fromSky, Self.upper)
        #expect(try b.regionsMerged == 1 && Self.region(fromSky, Self.inA) == joinedB)
        #expect(fromSky.palette[Int(fromSky.regions[joinedB].colorIndex)] == skyPaint)
        #expect(b.paintsMerged == 1 && fromSky.palette == Self.palette(t, without: [t.palette.count - 1]))
        #expect(fromSky.polygons(ofRegion: joinedB).count == 2)
        #expect(fromSky.lineArt!.strokes.count == t.lineArt!.strokes.count, "box A's outline leaves no stroke")
    }

    /// Two areas of one paint (a box and the sky round it) become one, and nothing else changes:
    /// every other region is as it was, bit for bit, and the palette too.
    @Test func othersStayAsTheyWere() throws {
        let t = Self.base
        let (u, outcome) = try TemplateEditorTests.apply(.merge(points: [Self.upper, SIMD2(101, 20)]), to: t)
        #expect(outcome.regionsMerged == 1 && outcome.paintsMerged == 0 && u.palette == t.palette)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
        let box = try Self.region(t, Self.inB), joined = try Self.region(u, Self.upper)
        #expect(TemplateEditorTests.snapshot(t, box) == TemplateEditorTests.snapshot(u, outcome.continued[box]))
        #expect(try Self.region(u, Self.inA) == joined && u.polygons(ofRegion: joined).count == 2)
    }

    /// The joined area is a detail area when the first was: a filled box (a detail area) dragged
    /// out into the sky stays one; the sky dragged into it does not become one.
    @Test func theFirstDecidesADetailArea() throws {
        let t = try TemplateEditor.apply(.fill(at: Self.inA, color: Self.magenta), to: Self.base).template
        #expect(t.isDetailRegion(try Self.region(t, Self.inA)))
        let fromBox = try TemplateEditorTests.apply(.merge(points: [Self.inA, Self.upper]), to: t).0
        #expect(fromBox.isDetailRegion(try Self.region(fromBox, Self.upper)))
        let fromSky = try TemplateEditorTests.apply(.merge(points: [Self.upper, Self.inA]), to: t).0
        #expect(!fromSky.isDetailRegion(try Self.region(fromSky, Self.upper)))
    }

    /// The probe Refine lights a drag with finds what the merge then joins, the kept area first,
    /// and nothing for a drag that joins none.
    @Test func theProbeFindsWhatTheMergeJoins() throws {
        let t = Self.scene
        let probe = try TemplateEditor.MergeProbe(t)
        let points = [Self.sky, Self.ground]
        #expect(probe.areas(along: points) == [try Self.region(t, Self.sky), try Self.region(t, Self.ground)])
        let merged = try TemplateEditor.apply(.merge(points: points), to: t).template
        #expect(try Self.region(merged, Self.sky) == (try Self.region(merged, Self.ground)))
        #expect(probe.areas(along: [Self.ground, Self.sky]) == [try Self.region(t, Self.ground), try Self.region(t, Self.sky)])
        #expect(probe.areas(along: [Self.sky, SIMD2(150, 20)]).isEmpty)
        #expect(probe.areas(along: []).isEmpty)
    }

    /// Points off the canvas are left out; a drag within one area, a tap, or one wholly off the
    /// canvas joins nothing and is declined, a drag or tap within one area saying so.
    @Test func aMergeOfFewerThanTwoAreasIsDeclined() throws {
        let t = Self.scene
        let offAndOn: [SIMD2<Float>] = [SIMD2(-40, 30), Self.sky, Self.ground, SIMD2(300, 120)]
        let (u, outcome) = try TemplateEditorTests.apply(.merge(points: offAndOn), to: t)
        #expect(outcome.regionsMerged == 1)
        let clipped = try TemplateEditor.apply(.merge(points: [SIMD2(0, 30), Self.sky, Self.ground, SIMD2(192, 120)]), to: t).template
        #expect(u == clipped)
        let inOne: [[SIMD2<Float>]] = [[Self.sky, SIMD2(150, 20)], [Self.sky]]
        for points in inOne {
            let (same, declined) = try TemplateEditor.apply(.merge(points: points), to: t)
            #expect(declined.declined?.reason == TemplateEditor.mergeStaysInOneArea && !declined.changed && same == t, "\(points)")
        }
        let none: [[SIMD2<Float>]] = [[SIMD2(-40, 30), SIMD2(-10, 130)], []]
        for points in none {
            let (same, declined) = try TemplateEditor.apply(.merge(points: points), to: t)
            #expect(declined.declined?.reason == "the merge joins no areas" && !declined.changed && same == t, "\(points)")
        }
        #expect(try TemplateEditor.apply(.merge(points: [SIMD2(.nan, 1), Self.sky]), to: t).1.declined != nil)
    }

    /// Kept in a file by its points; it brings no color through a look.
    @Test func itIsKeptInFiles() throws {
        let edit = Edit.merge(points: [SIMD2(0, 30), SIMD2(192, 30.5)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode([edit]), as: UTF8.self)
        #expect(json == #"[{"kind":"merge","points":[[0,30],[192,30.5]]}]"#)
        #expect(try JSONDecoder().decode([Edit].self, from: Data(json.utf8)) == [edit])
        let look = TemplateEditor.look(.moonlit, strength: 1, on: Self.scene)
        #expect(!TemplateEditor.isRecolor(edit) && TemplateEditor.recolored(edit, by: [look]) == edit)
    }

    /// Refine's Merge sends its drag in canvas units, thinned; no touch sends nothing.
    @Test func theGestureIsTheDrag() throws {
        let screen = RefineGesturesTests.screen
        let samples = (0...20).map { RefineGesturesTests.p(100, 30 + Float($0) * 4.5) }
        let edit = try #require(RefineGestures.merge(samples, on: screen))
        guard case .merge(let path) = edit else { Issue.record("\(edit)"); return }
        #expect(path.count == 2 && simdLength(path[0] - SIMD2(100, 30)) < 1e-3 && simdLength(path[1] - SIMD2(100, 120)) < 1e-3)
        #expect(RefineGestures.merge([], on: screen) == nil)
        let (u, _) = try TemplateEditorTests.apply(edit, to: Self.scene)
        #expect(u.regions.count == Self.scene.regions.count - 1)
    }
}
