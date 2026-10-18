import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Refine's tools: the Pencil's double tap, and what a tap of Fill does. Its geometry and
/// gestures are PaintCore's (`RefineGeometryTests`, `RefineGesturesTests`).
struct RefineToolTests {
    /// The Pencil's double tap switches between drawing (the Pen or Shapes) and the Eraser; Fill
    /// has no partner.
    @Test func thePencilSwitchesPenAndEraser() {
        #expect(RefineTool.pen.pencilPartner == .eraser && RefineTool.eraser.pencilPartner == .pen)
        #expect(RefineTool.shape.pencilPartner == .eraser && RefineTool.smartEraser.pencilPartner == .pen)
        #expect(RefineTool.more.pencilPartner == nil && RefineTool.text.pencilPartner == nil)
        #expect(RefineTool.fill.pencilPartner == nil && !RefineTool.fill.erases)
    }

    /// A tap anywhere in the detail area a fill made takes out the fills made there (not those
    /// elsewhere); a tap in another area, or in a detail area no fill made, is a new fill. On three
    /// stripes 20 units wide, the middle one a detail area.
    @Test func aTapInAFilledAreaClearsItsFills() {
        var t = Fixtures.stripes(count: 3, stripeWidth: 20, height: 40)
        t.detailRegions = [1]
        let color = SIMD3<Float>(0.6, 0.05, 0.05)
        let inMiddle = TemplateEditor.Edit.fill(at: SIMD2(30, 20), color: color)
        let again = TemplateEditor.Edit.fill(at: SIMD2(27, 8), color: color)
        let onLeft = TemplateEditor.Edit.fill(at: SIMD2(6, 20), color: color)
        let drawn = TemplateEditor.Edit.draw(points: [SIMD2(1, 1), SIMD2(5, 5)])
        let edits = [inMiddle, onLeft, drawn, again]
        #expect(EditFills.cleared(by: SIMD2(36, 36), edits: edits, on: t) == [0, 3])
        #expect(EditFills.cleared(by: SIMD2(10, 20), edits: edits, on: t).isEmpty)
        #expect(EditFills.cleared(by: SIMD2(36, 36), edits: [onLeft, drawn], on: t).isEmpty)
        #expect(EditFills.cleared(by: SIMD2(-5, 99), edits: edits, on: t).isEmpty)
    }
}
