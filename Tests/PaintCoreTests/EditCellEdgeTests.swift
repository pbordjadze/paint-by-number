import Foundation
import Testing
@testable import PaintCore

/// Refine's Cell Edge (`TemplateEditor.Edit.cellEdge`): a split that takes no paints, so one cell
/// becomes two of the paint it had, along an undrawn boundary, for the painter to paint one of
/// them. On the editor's scene (`TemplateEditorTests`: sky above y ≈ 72).
@Suite("Edit cell edge")
struct EditCellEdgeTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    /// Across the sky, frame to frame.
    static let across: [SIMD2<Float>] = [SIMD2(0, 30), SIMD2(192, 30)]
    static let upper = SIMD2<Float>(100, 10), lower = SIMD2<Float>(100, 50)
    static let magenta = SIMD3<Float>(0.62, 0.2, -0.1)

    static func region(_ t: Template, _ p: SIMD2<Float>) throws -> Int { try TemplateEditorTests.region(t, p.x, p.y) }

    /// Both pieces keep the sky's paint, the boundary between them is undrawn, no paint is added
    /// or changed, and nothing else changes.
    @Test func aCellEdgeDividesACellAndBothKeepItsPaint() throws {
        let t = Self.scene
        let sky = try Self.region(t, Self.upper)
        let (u, outcome) = try TemplateEditorTests.apply(.cellEdge(points: Self.across), to: t)
        #expect(outcome.changed && outcome.regionsSplit == 1 && outcome.pieces.count == 2)
        #expect(outcome.strokes == 0 && outcome.recolored == 0 && outcome.paintsAdded == 0 && outcome.regionsMerged == 0)
        #expect(u.palette == t.palette && u.regions.count == t.regions.count + 1)
        #expect(u.lineArt!.strokes == t.lineArt!.strokes, "a cell edge leaves no ink")
        let above = try Self.region(u, Self.upper), below = try Self.region(u, Self.lower)
        #expect(above != below)
        #expect(u.regions[above].colorIndex == t.regions[sky].colorIndex && u.regions[below].colorIndex == t.regions[sky].colorIndex)
        #expect(!u.isDetailRegion(above) && !u.isDetailRegion(below))
        let between = u.edges.indices.filter { e in
            let l = Int(u.edges[e].left), r = u.edges[e].right
            return r != BoundaryEdge.outside && Set([l, Int(r)]) == Set([above, below])
        }
        #expect(!between.isEmpty && between.allSatisfy { u.lineArt!.edgeLayers[$0] == LineLayer.color.rawValue })
        #expect(between.allSatisfy { u.lineArt!.edgeWeights[$0] == 0 }, "one paint on both sides: no color difference")
        #expect(u.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
        TemplateEditorTests.expectOthersUnchanged(t, u, outcome)
        #expect(try Template(encoded: u.encoded()) == u)
        // The photo has nothing to give it, and the same edit gives the same bytes.
        let photo = EditSplitTests.flatPhoto(t, oklab: t.palette[Int(t.regions[sky].colorIndex)].oklab)
        #expect(TemplateEditor.painted(.cellEdge(points: Self.across), on: t, photo: photo) == .cellEdge(points: Self.across))
        #expect(try TemplateEditor.apply(.cellEdge(points: Self.across), to: t).template.encoded() == u.encoded())
    }

    /// A split laid the same way, with no paints from the photo, leaves one paint on both sides
    /// and is declined for it; a cell edge is made for that.
    @Test func aSplitLaidTheSameWayIsDeclinedForItsOnePaint() throws {
        let (same, split) = try TemplateEditor.apply(.split(points: Self.across), to: Self.scene)
        #expect(split.declined?.reason.contains("same paint") == true && same == Self.scene)
        let (_, edge) = try TemplateEditor.apply(.cellEdge(points: Self.across), to: Self.scene)
        #expect(edge.changed && edge.declined == nil)
    }

    /// A cell edge that closes nothing leaves nothing, not even a stroke, and says so.
    @Test func aCellEdgeThatDividesNothingIsDeclined() throws {
        let t = Self.scene
        let (u, outcome) = try TemplateEditor.apply(.cellEdge(points: [SIMD2(80, 20), SIMD2(110, 25)]), to: t)
        #expect(outcome.declined?.reason.contains("divides no area") == true && !outcome.changed && u == t)
        var trail = EditTrail(base: t)
        if case .declined = trail.add(.cellEdge(points: [SIMD2(80, 20), SIMD2(110, 25)])) {} else { Issue.record("not declined") }
        #expect(trail.edits.isEmpty)
    }

    /// The painter then paints one piece: it takes the new paint and the other keeps the sky's.
    /// Painted back to the sky's paint, it meets the other across their undrawn boundary and the
    /// two are one area again, the new paint, its only area gone, leaving the palette.
    @Test func onePieceTakesAPaintAndPaintedBackRejoins() throws {
        let t = Self.scene
        let skyPaint = t.regions[try Self.region(t, Self.upper)].colorIndex
        var trail = EditTrail(base: t)
        #expect(trail.add(.cellEdge(points: Self.across)).isMade)
        let divided = trail.template
        #expect(trail.add(.paintArea(at: Self.lower, color: Self.magenta)).isMade)
        let painted = trail.template
        expectValid(painted)
        let above = try Self.region(painted, Self.upper), below = try Self.region(painted, Self.lower)
        #expect(above != below && painted.regions[above].colorIndex == skyPaint)
        #expect(painted.palette == t.palette + [PaletteColor(oklab: Self.magenta, space: t.colorSpace)])
        #expect(Int(painted.regions[below].colorIndex) == t.palette.count)
        #expect(painted.regions.count == divided.regions.count)
        #expect(try TemplateEditor.apply([.cellEdge(points: Self.across), .paintArea(at: Self.lower, color: Self.magenta)], to: t).template
            == painted)

        let (back, outcome) = try TemplateEditorTests.apply(.paintArea(at: Self.lower, color: t.palette[Int(skyPaint)].oklab), to: painted)
        #expect(outcome.regionsMerged == 1 && outcome.paintsMerged == 1)
        #expect(try Self.region(back, Self.upper) == Self.region(back, Self.lower))
        #expect(back.regions.count == t.regions.count && back.palette == t.palette)
        #expect(back.regions[try Self.region(back, Self.upper)].colorIndex == skyPaint)
    }

    /// Kept in a file as a split is, with no paints; a missing `closed` is false.
    @Test func itIsKeptInFiles() throws {
        let edit = Edit.cellEdge(points: [SIMD2(0, 30), SIMD2(192, 30.5)], closed: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode([edit]), as: UTF8.self)
        #expect(json == #"[{"closed":true,"kind":"cellEdge","points":[[0,30],[192,30.5]]}]"#)
        #expect(try JSONDecoder().decode([Edit].self, from: Data(json.utf8)) == [edit])
        let old = Data(#"{"kind": "cellEdge", "points": [[1, 2], [30, 40]]}"#.utf8)
        #expect(try JSONDecoder().decode(Edit.self, from: old) == .cellEdge(points: [SIMD2(1, 2), SIMD2(30, 40)]))
        #expect(try JSONDecoder().decode(Edit.self, from: old) == .cellEdge(points: [SIMD2(1, 2), SIMD2(30, 40)], closed: false))
    }

    /// No colors to bring through a look: laid after one, it is as sent, and it is no recolor.
    @Test func aLookLeavesItAsSent() {
        let edit = Edit.cellEdge(points: Self.across)
        let look = TemplateEditor.look(.moonlit, strength: 1, on: Self.scene)
        #expect(!TemplateEditor.isRecolor(edit) && TemplateEditor.recolored(edit, by: [look]) == edit)
    }
}
