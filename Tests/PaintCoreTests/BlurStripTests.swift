import Foundation
import Testing
@testable import PaintCore

/// A soft edge leaves its paints in strips on both sides of the line a detector draws on it
/// (`CellMap.mergeBlurStrips`): the red fox's tail, blurred by the lens, was painted in a band
/// outside its outline.
@Suite("Blur strips")
struct BlurStripTests {
    static let width = 320, height = 240
    static let center = SIMD2<Float>(160, 120)
    static let radius: Float = 70
    static let ground = SIMD3<Float>(245, 246, 248)
    static let subject = SIMD3<Float>(176, 140, 98)

    /// A tan disc on white: its edge blurred by a Gaussian of `blur` pixels (the share of the disc
    /// at distance `d` outside its edge is `erfc(d / (blur √2)) / 2`), or sharp with a dark rim of
    /// `rim` pixels inside it. The drawing is a ring on the edge, as a learned detector draws a
    /// line: a Gaussian profile of 2 px, 0.95 at its centre.
    static func scene(blur: Float, rim: Float = 0) -> (photo: RGBAImage, edges: EdgeMap) {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var edges = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let d = simdLength(SIMD2(Float(x) + 0.5, Float(y) + 0.5) - center) - radius
                let share = blur > 0 ? Float(erfc(Double(d / (blur * Float(2).squareRoot())))) / 2 : (d <= 0 ? 1 : 0)
                var color = ground + (subject - ground) * share
                if rim > 0, d <= 0, d > -rim { color = SIMD3(52, 40, 36) }
                for c in 0..<3 { pixels[(y * width + x) * 4 + c] = UInt8(min(max(color[c].rounded(), 0), 255)) }
                edges[y * width + x] = UInt8((0.95 * exp(-d * d / 8) * 255).rounded())
            }
        }
        return (RGBAImage(width: width, height: height, pixels: pixels), EdgeMap(width: width, height: height, values: edges))
    }

    /// The scene's book, with the line-art thresholds `LineArtTests` uses.
    static func generate(blur: Float, rim: Float = 0) throws -> TemplateGenerator.Output {
        let (photo, edges) = scene(blur: blur, rim: rim)
        let lineArt = LineArtSettings(
            outlineThreshold: 0.8, detailThreshold: 0.5, minimumStrokeLength: 10, gapBridging: 6, lineSmoothing: 0.5)
        return try TemplateGenerator(settings: GenerationSettings(colorCount: 8, detail: 0.5, lineArt: lineArt))
            .generate(from: photo, lineArt: LineArtInput(edges: edges), cancel: .none)
    }

    /// The paint at `depth` canvas units outside (positive) or inside the disc's edge, round it.
    static func paints(_ t: Template, depth: ClosedRange<Float>, around: Int = 72) -> [UInt32] {
        let scale = Float(t.width) / Float(width)
        var out: [UInt32] = []
        for k in 0..<around {
            let angle = Float(k) / Float(around) * 2 * .pi
            let direction = SIMD2(cos(angle), sin(angle))
            for d in stride(from: depth.lowerBound, through: depth.upperBound, by: 1) {
                let point = center * scale + direction * (radius * scale + d)
                if let region = t.region(at: point) { out.append(t.regions[region].colorIndex) }
            }
        }
        return out
    }

    /// The sharp edge's ramp is a pixel or two: nothing to merge, and the book is a disc on the
    /// ground, as ever.
    @Test func aSharpEdgeIsTwoAreas() throws {
        let out = try Self.generate(blur: 0)
        expectValid(out.template)
        #expect(out.template.regions.count == 2)
        #expect(out.lineArtStats?.blurStripsMerged == 0)
    }

    /// A lens blurs the edge over about 25 canvas px (σ = 6.5 of a 320-px photo, which the
    /// pipeline works at 1.5×): the segmentation cuts the ramp into a paler tan inside the line
    /// and a pale beige outside it, a strip each along the line. The paint stops at the line: all
    /// of the ground outside it is the ground's paint and all of the disc inside it the disc's.
    @Test func aBlurredEdgeStopsAtTheLine() throws {
        let out = try Self.generate(blur: 6.5)
        let t = out.template
        expectValid(t)
        let stats = try #require(out.lineArtStats)
        #expect(stats.blurStripsMerged > 0, "\(stats.blurStripsMerged) strips, \(t.regions.count) cells")
        let scale = Float(t.width) / Float(Self.width)
        let ground = try #require(t.region(at: SIMD2(2, 2)).map { t.regions[$0].colorIndex })
        let disc = try #require(t.region(at: Self.center * scale).map { t.regions[$0].colorIndex })
        #expect(ground != disc)
        let outside = Self.paints(t, depth: 4 * scale...16 * scale)
        let inside = Self.paints(t, depth: (-16 * scale)...(-4 * scale))
        #expect(!outside.isEmpty && !inside.isEmpty)
        #expect(outside.filter { $0 != ground }.isEmpty, "\(outside.filter { $0 != ground }.count) of \(outside.count) outside")
        #expect(inside.filter { $0 != disc }.isEmpty, "\(inside.filter { $0 != disc }.count) of \(inside.count) inside")
        #expect(t.regions.count == 2, "\(t.regions.count) cells")
    }

    /// A dark rim just inside the line is darker than the cells either side of it, not the blur
    /// between them: it stays a cell of its own, in its own paint.
    @Test func aRimIsNotABlurStrip() throws {
        let out = try Self.generate(blur: 0, rim: 9)
        let t = out.template
        expectValid(t)
        #expect(out.lineArtStats?.blurStripsMerged == 0)
        let scale = Float(t.width) / Float(Self.width)
        let rim = Self.paints(t, depth: (-7 * scale)...(-3 * scale))
        let disc = try #require(t.region(at: Self.center * scale).map { t.regions[$0].colorIndex })
        #expect(!rim.isEmpty && rim.allSatisfy { $0 != disc })
        #expect(t.regions.count >= 3, "\(t.regions.count) cells")
    }
}
