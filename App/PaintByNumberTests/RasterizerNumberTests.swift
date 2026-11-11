import CoreGraphics
import PaintCore
import Testing
@testable import PaintByNumber

/// `TemplateRasterizer` fills each number as its glyphs' outlines (never a text draw, which queues
/// an accessibility label per number when VoiceOver is on: painting-company row 320).
struct RasterizerNumberTests {
    /// Every unpainted area's number is drawn in ink, centred on its label as the text was.
    @Test func numbersAreDrawnCentredOnTheirLabels() throws {
        let t = Fixtures.stripes(count: 3, stripeWidth: 80, height: 120)
        let scale = 2
        let image = try #require(TemplateRasterizer.image(t, style: .template, maxPixelSize: scale * max(t.width, t.height)))
        record(image, "numbers")
        let px = PixelReader(image)
        for label in t.labels {
            let cx = Int(label.position.x) * scale, cy = Int(label.position.y) * scale
            var inked: [(x: Int, y: Int)] = []
            for y in (cy - 70)...(cy + 70) {
                for x in (cx - 70)...(cx + 70) where luma(px[x, y]) < 128 { inked.append((x, y)) }
            }
            #expect(inked.count > 20, "region \(label.region)'s number is drawn")
            guard let minX = inked.map(\.x).min(), let maxX = inked.map(\.x).max(),
                  let minY = inked.map(\.y).min(), let maxY = inked.map(\.y).max() else { continue }
            // Centred by its advance as the text was, so a digit's ink sits a little to a side; drawn
            // upside down, it would sit a cap height off.
            #expect(abs((minX + maxX) / 2 - cx) <= 12, "centred across")
            #expect(abs((minY + maxY) / 2 - cy) <= 8, "centred down, upright in the y-down page")
            // An area's corner, away from its number, stays paper.
            #expect(luma(px[cx - 30 * scale, cy - 50 * scale]) > 200)
        }
    }

    /// A painted area's number goes, as before.
    @Test func paintedAreasLoseTheirNumbers() throws {
        let t = Fixtures.stripes(count: 3, stripeWidth: 80, height: 120)
        let image = try #require(TemplateRasterizer.image(
            t, painted: [true, false, false], style: .template, maxPixelSize: 2 * max(t.width, t.height)))
        let px = PixelReader(image)
        let cx = Int(t.labels[0].position.x) * 2, cy = Int(t.labels[0].position.y) * 2
        // The painted stripe is one paint all through where its number was.
        let paint = px[cx, cy - 100]
        let marked = (-70...70).flatMap { dy in (-70...70).map { dx in px[cx + dx, cy + dy] } }
            .filter { maxDifference($0, paint) > 24 }
        #expect(marked.isEmpty)
    }
}
