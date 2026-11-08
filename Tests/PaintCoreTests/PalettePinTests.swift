import Foundation
import Testing
@testable import PaintCore

/// A base made again with its paints pinned (`TemplateGenerator.generate(…palette:)`, the app's
/// re-makes of a refined painting, painting-company row 278): the paints come back bit for bit and
/// in their order, those no area takes leaving; without a pin nothing changes. And the edits
/// carried onto such a base (`EditPlacement.swift`): scaled to its canvas, a repaint sent on to
/// the nearest paint.
@Suite("Palette pin")
struct PalettePinTests {
    static let classic = GenerationSettings(colorCount: 12, detail: 0.3, lineArt: LineArtSettings(style: .classic))

    static func generate(
        _ image: RGBAImage, _ settings: GenerationSettings = classic, palette: [PaletteColor]? = nil
    ) throws -> Template {
        try TemplateGenerator(settings: settings).generate(from: image, cancel: .none, palette: palette).template
    }

    /// `kept` is `pinned` with some paints left out, the rest bit for bit in their order.
    static func isOrderedSubset(_ kept: [PaletteColor], of pinned: [PaletteColor]) -> Bool {
        var k = 0
        for paint in pinned where k < kept.count && kept[k] == paint { k += 1 }
        return k == kept.count
    }

    @Test func noPinIsByteForByteTheTemplateWithout() throws {
        let image = TestScenes.colorful()
        let base = try Self.generate(image)
        #expect(try Self.generate(image, palette: nil).encoded() == base.encoded())
        #expect(try Self.generate(image, palette: []).encoded() == base.encoded())
    }

    @Test func pinnedPaintsComeBackBitForBitInOrder() throws {
        let image = TestScenes.colorful()
        let base = try Self.generate(image)
        let again = try Self.generate(image, palette: base.palette)
        #expect(Self.isOrderedSubset(again.palette, of: base.palette))
        #expect(again.palette.count >= base.palette.count - 2, "nearly every paint has its areas again")
        #expect(again.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
        // Deterministic like any generation.
        #expect(try Self.generate(image, palette: base.palette).encoded() == again.encoded())
    }

    /// A photo changed in one corner (as a Writing mark paints its letters out) and another
    /// canvas size (Detail): the paints are still the pinned ones, and far from the change the
    /// picture keeps them.
    @Test func aChangedPhotoAndCanvasKeepThePinnedPaints() throws {
        let image = TestScenes.colorful()
        let base = try Self.generate(image)
        var changed = image
        for y in 0..<40 { for x in 0..<60 { changed[x, y] = SIMD4(250, 250, 250, 255) } }
        let remade = try Self.generate(changed, palette: base.palette)
        #expect(Self.isOrderedSubset(remade.palette, of: base.palette))
        let free = try Self.generate(changed)
        // Far from the corner, more pixels keep their paint pinned than chosen anew.
        func kept(_ t: Template) -> Int {
            var same = 0
            for y in 100..<base.height { for x in 150..<base.width {
                let a = base.palette[Int(base.regions[Int(base.regionMap[x, y])].colorIndex)]
                let b = t.palette[Int(t.regions[Int(t.regionMap[x, y])].colorIndex)]
                if a == b { same += 1 }
            } }
            return same
        }
        #expect(kept(remade) > kept(free))
        let farArea = (base.height - 100) * (base.width - 150)
        #expect(Double(kept(remade)) > 0.8 * Double(farArea))

        // The working size is capped at 1.5 times the photo's: a photo large enough for Detail to
        // move it.
        let big = TestScenes.colorful(width: 1000, height: 660)
        var coarse = Self.classic
        coarse.detail = 0
        var detailed = coarse
        detailed.detail = 0.1
        let small = try Self.generate(big, coarse)
        let larger = try Self.generate(big, detailed, palette: small.palette)
        #expect(larger.width > small.width)
        #expect(Self.isOrderedSubset(larger.palette, of: small.palette))
    }

    /// Kit paint mixes the paints it chooses bolder than the colors the segmentation fits: the
    /// same photo pinned is the template made before, byte for byte, and a changed one keeps the
    /// pinned paints and, far from the change, the areas' paints, as with the photo's paints.
    @Test func kitPaintKeepsPinnedPaints() throws {
        let image = TestScenes.colorful()
        var kit = Self.classic
        kit.paintMix = .kit
        let base = try Self.generate(image, kit)
        #expect(try Self.generate(image, kit, palette: base.palette).encoded() == base.encoded())

        var changed = image
        for y in 0..<40 { for x in 0..<60 { changed[x, y] = SIMD4(250, 250, 250, 255) } }
        let remade = try Self.generate(changed, kit, palette: base.palette)
        #expect(Self.isOrderedSubset(remade.palette, of: base.palette))
        #expect(!remade.palette.isEmpty)
        var same = 0, far = 0
        for y in 100..<base.height { for x in 150..<base.width {
            far += 1
            let a = base.palette[Int(base.regions[Int(base.regionMap[x, y])].colorIndex)]
            let b = remade.palette[Int(remade.regions[Int(remade.regionMap[x, y])].colorIndex)]
            if a == b { same += 1 }
        } }
        #expect(Double(same) > 0.8 * Double(far), "kept \(same) of \(far)")
        #expect(remade.validate(minLabelRadius: LabelSizing.minimumRadius).isValid)
    }

    @Test func editsScaleToAnotherCanvas() {
        typealias Edit = TemplateEditor.Edit
        let a = SIMD2<Float>(10, 20), b = SIMD2<Float>(30, 40)
        #expect(Edit.merge(points: [a, b]).scaled(x: 2, y: 3) == .merge(points: [SIMD2(20, 60), SIMD2(60, 120)]))
        #expect(Edit.erase(path: [a], radius: 4).scaled(x: 2, y: 2) == .erase(path: [SIMD2(20, 40)], radius: 8))
        #expect(Edit.paintArea(at: a, color: SIMD3(0.5, 0, 0)).scaled(x: 0.5, y: 0.5)
            == .paintArea(at: SIMD2(5, 10), color: SIMD3(0.5, 0, 0)))
        let draw = Edit.draw(points: [a, b], closed: true, paints: [TemplateEditor.Paint(at: a, color: SIMD3(0.4, 0.1, 0))])
        #expect(draw.scaled(x: 2, y: 2) == .draw(
            points: [SIMD2(20, 40), SIMD2(60, 80)], closed: true, paints: [TemplateEditor.Paint(at: SIMD2(20, 40), color: SIMD3(0.4, 0.1, 0))]))
        #expect(Edit.eraseLine(at: a).scaled(x: 2, y: 2) == .eraseLine(at: SIMD2(20, 40), reach: TemplateEditor.tapReach * 2))
        let repaint = Edit.repaint(from: SIMD3(0.5, 0, 0), to: SIMD3(0.6, 0.1, 0), family: true)
        #expect(repaint.scaled(x: 2, y: 2) == repaint)
        #expect(Edit.merge(points: [a]).scaled(x: 1, y: 1) == .merge(points: [a]))
        #expect(Edit.merge(points: [a]).scaled(x: .nan, y: 2) == .merge(points: [a]))
    }

    @Test func aRepaintGoesToTheNearestNewPaint() {
        let old = [SIMD3<Float>(0.3, 0, 0), SIMD3(0.7, 0.1, 0)].map { PaletteColor(oklab: $0, space: .sRGB) }
        let new = [SIMD3<Float>(0.72, 0.09, 0), SIMD3(0.5, 0, 0), SIMD3(0.31, 0, 0.01)].map { PaletteColor(oklab: $0, space: .sRGB) }
        let map = TemplateEditor.nearestPaints(from: old, to: new)
        #expect(map[old[0].oklab] == new[2].oklab && map[old[1].oklab] == new[0].oklab)
        let repaint = TemplateEditor.Edit.repaint(from: old[1].oklab, to: SIMD3(0.2, 0.2, 0), family: false)
        #expect(repaint.repainting(map) == .repaint(from: new[0].oklab, to: SIMD3(0.2, 0.2, 0), family: false))
        #expect(repaint.isRepainted(by: map))
        let other = TemplateEditor.Edit.repaint(from: SIMD3(0.9, 0, 0), to: SIMD3(0.2, 0.2, 0), family: false)
        #expect(other.repainting(map) == other && !other.isRepainted(by: map))
        #expect(TemplateEditor.nearestPaints(from: old, to: []).isEmpty)
    }
}
