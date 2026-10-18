import Foundation
import Testing
@testable import PaintCore

/// The Color Splitter's edit (`TemplateEditor.Edit.split`): it divides the paint along an undrawn
/// boundary and draws nothing, its pieces end with different paints, and a split that divides no
/// area changes nothing. On the editor's scene (`TemplateEditorTests`: sky above y ≈ 72).
@Suite("Edit split")
struct EditSplitTests {
    typealias Edit = TemplateEditor.Edit

    static let scene = TemplateEditorTests.scene
    /// Across the sky, frame to frame.
    static let across: [SIMD2<Float>] = [SIMD2(0, 30), SIMD2(192, 30)]

    /// A photo of the scene's size all in one color: the sky's paint, so both sides of a split
    /// across the sky read the same.
    static func flatPhoto(_ t: Template, oklab: SIMD3<Float>) -> RGBAImage {
        let rgb = ColorScience.okLabToEncoded(oklab, space: .sRGB)
        let px = (0..<3).map { UInt8(min(max(rgb[$0] * 255, 0), 255).rounded()) }
        var pixels = [UInt8](repeating: 255, count: t.width * t.height * 4)
        for i in 0..<(t.width * t.height) { pixels.replaceSubrange(i * 4..<i * 4 + 3, with: px) }
        return RGBAImage(width: t.width, height: t.height, pixels: pixels)
    }

    @Test func aSplitDividesThePaintAndDrawsNothing() throws {
        let t = Self.scene
        let sky = try TemplateEditorTests.region(t, 100, 5)
        let photo = Self.flatPhoto(t, oklab: t.palette[Int(t.regions[sky].colorIndex)].oklab)
        let edit = TemplateEditor.painted(.split(points: Self.across), on: t, photo: photo)
        guard case .split(_, false, let paints) = edit else { Issue.record("\(edit)"); return }
        #expect(paints.count == 2)
        let (u, outcome) = try TemplateEditorTests.apply(edit, to: t)
        #expect(outcome.changed && outcome.declined == nil && outcome.regionsSplit == 1)
        #expect(outcome.strokes == 0 && u.lineArt!.strokes.count == t.lineArt!.strokes.count, "a split leaves no ink")
        let above = try TemplateEditorTests.region(u, 100, 10), below = try TemplateEditorTests.region(u, 100, 50)
        #expect(above != below)
        let pa = u.regions[above].colorIndex, pb = u.regions[below].colorIndex
        #expect(pa != pb, "the two sides are told apart")
        // The photo is one color: one side keeps the sky's paint, the other takes a shade of it.
        let d = ColorScience.distance(u.palette[Int(pa)].oklab, u.palette[Int(pb)].oklab)
        #expect(abs(d - EditWork.splitShadeStep) < 1e-3, "\(d)")
        #expect(u.palette.count == t.palette.count + 1)
        // Every edge between the two is undrawn.
        let between = u.edges.indices.filter { e in
            let l = Int(u.edges[e].left), r = u.edges[e].right
            return r != BoundaryEdge.outside && Set([l, Int(r)]) == Set([above, below])
        }
        #expect(!between.isEmpty && between.allSatisfy { u.lineArt!.edgeLayers[$0] == LineLayer.color.rawValue })
        #expect(u.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
        // Laid again from its paints alone, the same template.
        #expect(try TemplateEditorTests.apply(edit, to: t).0 == u)
    }

    /// A split that closes nothing leaves nothing, not even a stroke, and says so.
    @Test func aSplitThatDividesNothingIsDeclined() throws {
        let t = Self.scene
        let (u, outcome) = try TemplateEditor.apply(.split(points: [SIMD2(80, 20), SIMD2(110, 25)]), to: t)
        #expect(outcome.declined != nil && !outcome.changed && u == t)
    }

    /// Without paints a split keeps the region's paint on both sides, which divides nothing the
    /// painter could see: declined.
    @Test func aSplitWithoutDifferentPaintsIsDeclined() throws {
        let (u, outcome) = try TemplateEditor.apply(.split(points: Self.across), to: Self.scene)
        #expect(outcome.declined?.reason.contains("same paint") == true && u == Self.scene)
    }

    @Test func aShadeLeansTowardThePhoto() {
        let paint = SIMD3<Float>(0.6, 0.05, 0.02)
        let step = EditWork.splitShadeStep
        let far = paint + SIMD3(0, 0.1, 0)
        #expect(EditWork.shade(of: paint, toward: far) == far, "a photo far enough is taken as it is")
        let near = EditWork.shade(of: paint, toward: paint + SIMD3(0, 0.005, 0))
        #expect(abs(ColorScience.distance(near, paint) - step) < 1e-5 && near.y > paint.y)
        #expect(EditWork.shade(of: paint, toward: paint) == paint + SIMD3(step, 0, 0), "lighter where the photo is the paint")
        let white = SIMD3<Float>(0.95, 0, 0)
        #expect(EditWork.shade(of: white, toward: white) == white - SIMD3(step, 0, 0), "darker near white")
        let nearWhite = SIMD3<Float>(0.99, 0, 0)
        let past = EditWork.shade(of: nearWhite, toward: SIMD3(1, 0, 0))
        #expect(past.x <= 1 && abs(ColorScience.distance(past, nearWhite) - step) < 1e-5, "never past white: \(past)")
    }

    @Test func splitsAreKeptInFiles() throws {
        let split = Edit.split(points: Self.across, closed: false, paints: [.init(at: SIMD2(100, 10), color: SIMD3(0.7, 0, 0))])
        let data = try JSONEncoder().encode([split])
        #expect(try JSONDecoder().decode([Edit].self, from: data) == [split])
        #expect(String(decoding: data, as: UTF8.self).contains(#""kind":"split""#))
        let old = Data(#"{"kind": "split", "points": [[1, 2], [30, 40]]}"#.utf8)
        #expect(try JSONDecoder().decode(Edit.self, from: old) == .split(points: [SIMD2(1, 2), SIMD2(30, 40)]))
    }
}
