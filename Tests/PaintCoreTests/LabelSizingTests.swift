import Foundation
import Testing
@testable import PaintCore

@Suite("Label sizing")
struct LabelSizingTests {

    /// The worst free radius, at the pixel centre, of the pixel-exact outline around any
    /// region the raster calls wide enough (`interiorDistance` ≥ `radius` there): pixels
    /// nearer than `radius − ½` are interior, so they and their 4-neighbours are in the
    /// region; anything else may not be.
    static func latticeWorst(_ radius: Float) -> Float {
        let reach = max(radius - 0.5, 0)
        let k = Int(radius) + 4
        var region = Set<SIMD2<Int>>()
        for dy in -k...k {
            for dx in -k...k where Float(dx * dx + dy * dy) < reach * reach {
                for o in [SIMD2(0, 0), SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1)] {
                    region.insert(SIMD2(dx, dy) &+ o)
                }
            }
        }
        var best = Float.infinity
        for dy in -(k + 1)...(k + 1) {
            for dx in -(k + 1)...(k + 1) where !region.contains(SIMD2(dx, dy)) {
                let ex = max(Float(abs(dx)) - 0.5, 0), ey = max(Float(abs(dy)) - 0.5, 0)
                best = min(best, (ex * ex + ey * ey).squareRoot())
            }
        }
        return best
    }

    @Test func minimumRadiusIsAchievable() {
        // Whatever the detail and digit count, a region meeting its raster minimum keeps at
        // least the guaranteed room once smoothed: the vectorizer only accepts polygons within
        // the tolerance of the raster minimum, and falls back to the pixel outline otherwise.
        #expect(abs(Self.latticeWorst(2.7) - 1.5 * Float(2).squareRoot()) < 1e-5)
        let tolerance = SegmentationParameters.vectorRadiusTolerance
        for detail in Array(stride(from: Float(0), to: 1, by: 0.01)) + [1] {
            let p = SegmentationParameters(settings: GenerationSettings(detail: detail), width: 1000, height: 1000)
            for digits in 1...3 {
                let raster = p.minRadius(digits: digits)
                let guaranteed = min(tolerance * raster, Self.latticeWorst(raster))
                #expect(guaranteed >= LabelSizing.minimumRadius(digits: digits) - 1e-5, "detail \(detail), \(digits) digits")
            }
        }
    }

    @Test func minimalRegionsGetTheSameFontSize() {
        for digits in 1...3 {
            let size = LabelSizing.fittedFontSize(radius: LabelSizing.minimumRadius(digits: digits), digits: digits)
            #expect(abs(size - LabelSizing.minimumFontSize) < 1e-5)
        }
        #expect(LabelSizing.fontSize(radius: 0.01, digits: 3) == LabelSizing.minimumFontSize)
        #expect(LabelSizing.fontSize(radius: 100, digits: 1, maximum: 5) == 5)
        // The floor wins over a renderer's cap.
        #expect(LabelSizing.fontSize(radius: 0, digits: 2, maximum: 1) == LabelSizing.minimumFontSize)
        #expect(LabelSizing.fontSize(radius: 10, digits: 2) == LabelSizing.fittedFontSize(radius: 10, digits: 2))
    }

    @Test func digitCounts() {
        for (number, digits) in [(1, 1), (9, 1), (10, 2), (99, 2), (100, 3), (150, 3)] {
            #expect(LabelSizing.digitCount(of: number) == digits)
        }
        #expect(LabelSizing.digitCount(colorIndex: 8) == 1)
        #expect(LabelSizing.digitCount(colorIndex: 9) == 2)
        #expect(LabelSizing.digitCount(colorIndex: 99) == 3)
        #expect(LabelSizing.roomFactor(digits: 1) == 1)
        #expect(LabelSizing.roomFactor(digits: 1) < LabelSizing.roomFactor(digits: 2))
        #expect(LabelSizing.roomFactor(digits: 2) < LabelSizing.roomFactor(digits: 3))
    }

    @Test func svgNeverDropsNumbers() throws {
        // A one-pixel island has far too little room for its number; it is drawn at the floor.
        var rows = Array(repeating: Array(repeating: UInt32(0), count: 20), count: 16)
        rows[8][10] = 1
        for y in 2..<5 { for x in 2..<18 { rows[y][x] = 2 } }
        let t = try VectorizerTests.vectorize(VectorizerTests.segmentation(rows))
        #expect(t.labels.contains { $0.radius < 1 })
        let svg = SVGExport.render(t)
        #expect(svg.components(separatedBy: "<text").count - 1 == t.labels.count)
        var sizes: [Float] = []
        var rest = Substring(svg)
        while let range = rest.range(of: "font-size=\"") {
            rest = rest[range.upperBound...]
            let end = rest.firstIndex(of: "\"")!
            sizes.append(Float(rest[..<end])!)
        }
        #expect(sizes.count == t.labels.count)
        #expect(sizes.allSatisfy { $0 >= LabelSizing.minimumFontSize - 0.01 })
    }
}
