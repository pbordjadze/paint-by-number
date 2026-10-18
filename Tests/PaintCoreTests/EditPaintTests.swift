import Foundation
import Testing
@testable import PaintCore

/// A drawn line's paints (`TemplateEditor.Paint`): the pieces it cuts take the photo's colors,
/// a draw without paints is laid as it always was, and a draw with them passes through the
/// junctions it crosses beside. On the editor's scene (`TemplateEditorTests`).
@Suite("Edit paints")
struct EditPaintTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    /// A rectangle in the sky, crossing nothing.
    static let box: [SIMD2<Float>] = [SIMD2(90, 12), SIMD2(112, 12), SIMD2(112, 28), SIMD2(90, 28)]
    static let inBox = SIMD2<Float>(101, 20)

    static func draw(_ paints: [TemplateEditor.Paint]?) -> Edit { .draw(points: box, closed: true, paints: paints) }

    @Test func aPieceTakesThePaintNearestItsPhoto() throws {
        let t = Self.scene
        let sky = try TemplateEditorTests.region(t, 100, 5), ground = try TemplateEditorTests.region(t, 100, 130)
        #expect(t.regions[sky].colorIndex != t.regions[ground].colorIndex)
        let groundPaint = t.palette[Int(t.regions[ground].colorIndex)].oklab
        let (u, outcome) = try TemplateEditorTests.apply(Self.draw([.init(at: Self.inBox, color: groundPaint)]), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.recolored == 1 && outcome.paintsAdded == 0)
        #expect(u.palette == t.palette)
        let piece = try TemplateEditorTests.region(u, Self.inBox.x, Self.inBox.y)
        #expect(u.regions[piece].colorIndex == t.regions[ground].colorIndex)
        #expect(u.regions[try TemplateEditorTests.region(u, 100, 5)].colorIndex == t.regions[sky].colorIndex)
        #expect(Set(outcome.pieces) == [piece, try TemplateEditorTests.region(u, 100, 5)])
        #expect(u.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    @Test func aColorThePaletteLacksIsANewPaintAddedLast() throws {
        let t = Self.scene
        let purple = SIMD3<Float>(0.55, 0.2, -0.2)
        let tolerance = TemplateEditor.paintTolerance(t.palette)
        #expect(t.palette.allSatisfy { ColorScience.distance($0.oklab, purple) > tolerance })
        let (u, outcome) = try TemplateEditorTests.apply(Self.draw([.init(at: Self.inBox, color: purple)]), to: t)
        #expect(outcome.paintsAdded == 1 && outcome.recolored == 1)
        #expect(u.palette.count == t.palette.count + 1 && Array(u.palette.prefix(t.palette.count)) == t.palette)
        #expect(ColorScience.distance(u.palette.last!.oklab, purple) < 1e-6)
        let piece = try TemplateEditorTests.region(u, Self.inBox.x, Self.inBox.y)
        #expect(Int(u.regions[piece].colorIndex) == t.palette.count)
        #expect(u.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    /// Where the photo agrees with the paint, nothing is recolored, and the draw is what a draw
    /// without paints makes (it crosses nothing, so nothing is nudged).
    @Test func aPhotoThatAgreesChangesNoPaint() throws {
        let t = Self.scene
        let sky = try TemplateEditorTests.region(t, 100, 5)
        let own = t.palette[Int(t.regions[sky].colorIndex)].oklab
        let (u, outcome) = try TemplateEditorTests.apply(Self.draw([.init(at: Self.inBox, color: own + SIMD3(0.005, 0, 0))]), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.recolored == 0 && outcome.paintsAdded == 0)
        let (plain, _) = try TemplateEditorTests.apply(Self.draw(nil), to: t)
        #expect(u == plain)
    }

    /// Paul, October 18: "colors should get recalculated when a new line is drawn". Each side's
    /// photo within the book's tolerance of the sky's paint, so each alone keeps it, but the two
    /// told apart: the sides part, the box taking its photo's color.
    @Test func sidesThePhotoTellsApartPart() throws {
        let t = Self.scene
        let sky = try TemplateEditorTests.region(t, 100, 5)
        let own = t.palette[Int(t.regions[sky].colorIndex)].oklab
        let inside = own + SIMD3(-EditWork.splitShadeStep, 0, 0), outside = own + SIMD3(0.004, 0, 0)
        let tolerance = TemplateEditor.paintTolerance(t.palette)
        let nearest = { (c: SIMD3<Float>) in t.palette.map { ColorScience.distance($0.oklab, c) }.min()! }
        #expect(nearest(inside) == ColorScience.distance(own, inside) && nearest(inside) <= tolerance,
                "alone, the box's photo keeps the sky's paint")
        let paints: [TemplateEditor.Paint] = [.init(at: Self.inBox, color: inside), .init(at: SIMD2(100, 5), color: outside)]
        let (u, outcome) = try TemplateEditorTests.apply(Self.draw(paints), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.recolored == 1)
        let box = try TemplateEditorTests.region(u, Self.inBox.x, Self.inBox.y), rest = try TemplateEditorTests.region(u, 100, 5)
        #expect(u.regions[rest].colorIndex == t.regions[sky].colorIndex)
        #expect(u.regions[box].colorIndex != u.regions[rest].colorIndex)
        #expect(ColorScience.distance(u.palette[Int(u.regions[box].colorIndex)].oklab, inside) <= SegmentationParameters.jnd)
        #expect(u.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
        #expect(try TemplateEditorTests.apply(Self.draw(paints), to: t).0 == u)
    }

    /// Sides whose photos are closer than `splitShadeStep` keep the one paint.
    @Test func sidesThePhotoHoldsAsOneKeepTheirPaint() throws {
        let t = Self.scene
        let sky = try TemplateEditorTests.region(t, 100, 5)
        let own = t.palette[Int(t.regions[sky].colorIndex)].oklab
        let paints: [TemplateEditor.Paint] = [
            .init(at: Self.inBox, color: own + SIMD3(-0.012, 0, 0)), .init(at: SIMD2(100, 5), color: own + SIMD3(0.012, 0, 0))]
        let (u, outcome) = try TemplateEditorTests.apply(Self.draw(paints), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.recolored == 0 && u.palette == t.palette)
    }

    @Test func aPaintOutsideThePiecesChangesNothing() throws {
        let t = Self.scene
        let (u, outcome) = try TemplateEditorTests.apply(
            Self.draw([.init(at: SIMD2(100, 130), color: SIMD3(0.55, 0.2, -0.2))]), to: t)
        #expect(outcome.regionsSplit == 1 && outcome.recolored == 0 && u.palette == t.palette)
    }

    /// The app reads the paints from the photo: a magenta patch where the box is drawn gives the
    /// box a magenta paint.
    @Test func paintedReadsThePhotoUnderEachPiece() throws {
        let t = Self.scene
        var pixels = [UInt8](repeating: 255, count: t.width * t.height * 4)
        for y in 14..<27 {
            for x in 92..<111 { pixels.replaceSubrange((y * t.width + x) * 4..<(y * t.width + x) * 4 + 3, with: [230, 0, 200]) }
        }
        let photo = RGBAImage(width: t.width, height: t.height, pixels: pixels)
        let magenta = ColorScience.encodedToOKLab(SIMD3(230, 0, 200) / 255, space: .sRGB)
        let edit = TemplateEditor.painted(Self.draw(nil), on: t, photo: photo)
        guard case .draw(let points, true, let paints?) = edit else { Issue.record("not a painted draw: \(edit)"); return }
        #expect(points == Self.box && paints.count == 2)
        #expect(paints.contains { ColorScience.distance($0.color, magenta) < 0.02 })
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        #expect(outcome.recolored >= 1)
        let piece = try TemplateEditorTests.region(u, Self.inBox.x, Self.inBox.y)
        #expect(ColorScience.distance(u.palette[Int(u.regions[piece].colorIndex)].oklab, magenta) <= TemplateEditor.paintTolerance(t.palette))
        // Laid again from its paints alone, the same template.
        #expect(try TemplateEditorTests.apply(edit, to: t).0 == u)
        // Other edits come back as they were.
        let fill = Edit.fill(at: Self.inBox, color: magenta)
        #expect(TemplateEditor.painted(fill, on: t, photo: photo) == fill)
    }

    /// A line with paints crossing an edge just beside a junction passes through the junction; a
    /// line without them is laid as drawn. Here a line across the horizon 1.5 from where it meets
    /// the disc, its ends free (clear of ink by more than `inkWidth`), so it is a stroke either way.
    @Test func aDrawWithPaintsPassesThroughAJunctionBeside() throws {
        let t = Self.scene
        let horizon = ends(of: 6, in: t)
        let j = horizon[0].x > horizon[1].x ? horizon[0] : horizon[1]
        #expect(abs(j.x - 33) < 1 && abs(j.y - 72.5) < 1, "the horizon meets the disc")
        let pts = Array(t.points(of: t.edges[6]))
        let next = pts[0] == j ? pts[1] : pts[pts.count - 2]
        let q = j + 1.5 * (next - j) / simdLength(next - j)
        let line = [q - SIMD2(0, 12), q + SIMD2(0, 12)]
        let (plain, plainOutcome) = try TemplateEditorTests.apply(.draw(points: line), to: t)
        let (nudged, outcome) = try TemplateEditorTests.apply(.draw(points: line, paints: []), to: t)
        #expect(plainOutcome.changed && outcome.changed && plainOutcome.joins == 0 && outcome.joins == 0)
        #expect(plainOutcome.regionsSplit == 0 && outcome.regionsSplit == 0)
        // Drawn as given, the line cuts the horizon where it crosses; nudged, it passes through the
        // junction and the horizon stays whole.
        #expect(plain.edges.count == t.edges.count + 1 && nudged.edges.count == t.edges.count)
        #expect(!plain.lineArt!.strokePoints.contains(j) && nudged.lineArt!.strokePoints.contains(j))
        #expect(nudged.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    private func ends(of e: Int, in t: Template) -> [SIMD2<Float>] {
        let p = Array(t.points(of: t.edges[e]))
        return [p[0], p[p.count - 1]]
    }

    @Test func paintsAreKeptInFilesAndOldDrawsHaveNone() throws {
        let painted = Edit.draw(points: Self.box, closed: true, paints: [.init(at: Self.inBox, color: SIMD3(0.5, 0.1, -0.05))])
        let data = try JSONEncoder().encode([painted, Self.draw([]), Self.draw(nil)])
        #expect(try JSONDecoder().decode([Edit].self, from: data) == [painted, Self.draw([]), Self.draw(nil)])
        let old = Data(#"{"kind": "draw", "points": [[1, 2], [30, 40]], "closed": false}"#.utf8)
        #expect(try JSONDecoder().decode(Edit.self, from: old) == .draw(points: [SIMD2(1, 2), SIMD2(30, 40)], closed: false, paints: nil))
        let written = String(decoding: try JSONEncoder().encode(Self.draw(nil)), as: UTF8.self)
        #expect(!written.contains("paints"), "a draw without paints is written as before")
    }
}
