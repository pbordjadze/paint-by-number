import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Refine's tools: the Pencil's double tap, and what a tap of Fill does. Its geometry and
/// gestures are PaintCore's (`RefineGeometryTests`, `RefineGesturesTests`).
struct RefineToolTests {
    /// The Pencil's double tap switches between drawing (the Pen or Shapes) and the Eraser; Fill,
    /// the Color Splitter, Text and Colors have no partner.
    @Test func thePencilSwitchesPenAndEraser() {
        #expect(RefineTool.pen.pencilPartner == .eraser && RefineTool.eraser.pencilPartner == .pen)
        #expect(RefineTool.shape.pencilPartner == .eraser && RefineTool.smartEraser.pencilPartner == .pen)
        #expect(RefineTool.splitter.pencilPartner == nil && RefineTool.text.pencilPartner == nil)
        #expect(RefineTool.fill.pencilPartner == nil && !RefineTool.fill.erases)
        #expect(RefineTool.colors.pencilPartner == nil && !RefineTool.colors.erases)
    }

    /// Colors' changes to the edits: a look and the photo's colors start from the edits without
    /// looks and repaints, a repaint of the color the last one repainted takes its place, and the
    /// look shown is the last one laid.
    @Test func colorsChangeTheirOwnEditsAlone() {
        let red = SIMD3<Float>(0.6, 0.2, 0.1), blue = SIMD3<Float>(0.6, -0.05, -0.2)
        let drawn = TemplateEditor.Edit.draw(points: [SIMD2(1, 1), SIMD2(5, 5)])
        let moonlit = TemplateEditor.Edit.look(.moonlit, strength: 0.5)
        let repaint = TemplateEditor.Edit.repaint(from: red, to: blue, family: true)
        let edits = [drawn, moonlit, repaint]
        #expect(RefineColors.withoutColors(edits) == [drawn])
        #expect(RefineColors.look(in: edits)?.look == .moonlit && RefineColors.look(in: edits)?.strength == 0.5)
        #expect(RefineColors.look(in: [drawn]) == nil)
        #expect(RefineColors.repaint(from: red, to: red, family: false).replacesLast(of: edits))
        #expect(!RefineColors.repaint(from: blue, to: red, family: true).replacesLast(of: edits))
        #expect(!RefineColors.repaint(from: red, to: blue, family: true).replacesLast(of: [drawn]))
        #expect(!RefineColors.look(.sepia, strength: 1).replacesLast(of: edits))
    }

    /// A look's chip shows four of the painting's paints, darkest to lightest, in that look.
    @Test func aLooksChipShowsFourPaints() {
        let palette = (0..<10).map { PaletteColor(oklab: SIMD3(0.1 + 0.08 * Float($0), 0.05, -0.02), space: .sRGB) }
        #expect(RefineColorsPanel.preview(of: nil, on: palette).count == 4)
        #expect(RefineColorsPanel.preview(of: .starryNight, on: palette).count == 4)
        #expect(RefineColorsPanel.preview(of: .moonlit, on: []).isEmpty)
    }

    /// The row offers five looks, Moonlit first (Paul, October 18); the rest are kept for later.
    @Test func theRowOffersFiveLooks() {
        #expect(RefineColorsPanel.offered == [.moonlit, .goldenHour, .pastel, .garden, .starryNight])
        #expect(Set(RefineColorsPanel.offered).isSubset(of: Set(TemplateEditor.Look.allCases)))
    }

    /// A picked paint glows in every area that uses it, including separated areas.
    @Test func aPickedPaintFindsExactlyItsAreas() {
        var template = Fixtures.stripes(count: 4)
        template.regions[0].colorIndex = 2
        template.regions[3].colorIndex = 2
        #expect(RefinePaintGlow.areas(of: 2, in: template) == [0, 2, 3])
        #expect(RefinePaintGlow.areas(of: 1, in: template) == [1])
        // Paint zero is still in the palette, but no area uses it.
        #expect(RefinePaintGlow.areas(of: 0, in: template).isEmpty)
    }

    /// The Studio's groups hold every tool once, at most five on screen, the Pen first; Colors is
    /// Paints', Fill is Areas'.
    @Test func theStudioGroupsHoldEveryToolOnce() {
        let all = RefineGroup.allCases.flatMap(\.tools)
        #expect(Set(all).count == all.count)
        #expect(RefineGroup.allCases.allSatisfy { !$0.tools.isEmpty && $0.tools.count <= 5 })
        #expect(RefineGroup.lines.tools.first == .pen)
        for tool in [RefineTool.pen, .shape, .eraser, .smartEraser, .text, .fill, .colors] {
            #expect(all.contains(tool), "\(tool) is in no group")
        }
        #expect(RefineGroup.of(.colors) == .paints && RefineGroup.of(.fill) == .areas && RefineGroup.of(.text) == .lines)
        #expect(all.contains(.splitter) == RefineView.offersSplitter)
    }

    /// A card counts the areas of its paint, separate ones too, as the glow finds them.
    @Test func anAreaCardCountsItsPaintsAreas() {
        var template = Fixtures.stripes(count: 4)
        template.regions[0].colorIndex = 2
        template.regions[3].colorIndex = 2
        #expect(RefineAreaCard.areaCount(of: 2, in: template) == 3)
        #expect(RefineAreaCard.areaCount(of: 1, in: template) == 1)
        #expect(RefineAreaCard.areaCount(of: 0, in: template) == 0)
        #expect(RefineAreaCard.subtitle(paint: 1, count: 3) == "Paint 2 · 3 areas")
        #expect(RefineAreaCard.subtitle(paint: 0, count: 1) == "Paint 1 · 1 area")
    }

    /// Only numbers near their floor count as tiny, top to bottom; the zoom frames each one.
    @Test func tinyNumbersAreThoseNearTheirFloor() {
        var template = Fixtures.stripes(count: 3)
        #expect(RefineTinyAreas.find(in: template).isEmpty)
        let region = Int(template.labels[0].region)
        template.labels[0].radius = LabelSizing.minimumRadius(digits: 1)
        let found = RefineTinyAreas.find(in: template)
        #expect(found.map(\.region) == [region])
        let rect = RefineTinyAreas.focus(on: found[0].label, in: template)
        let p = found[0].label.position
        #expect(rect.contains(CGPoint(x: CGFloat(p.x) / CGFloat(template.width), y: CGFloat(p.y) / CGFloat(template.height))))
    }

    /// The sparkles stay within a shape's smaller side.
    @Test func aShapesExtentIsItsSmallerSide() {
        #expect(CreateModel.extent(of: [SIMD2(0, 0), SIMD2(10, 4), SIMD2(3, 2)]) == 4)
        #expect(CreateModel.extent(of: [SIMD2(5, 5)]) == 0)
        #expect(CreateModel.extent(of: []) == 0)
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
