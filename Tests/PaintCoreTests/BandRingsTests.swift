import Foundation
import Testing
@testable import PaintCore

/// `BandRings.count`, the metric for gradients posterized into rings (`bandRings` in
/// `pbn generate`'s stats).
@Suite("Band rings")
struct BandRingsTests {

    static let size = 120
    static let rings = 8
    static let ringWidth: Float = 8

    static func radius(_ x: Int, _ y: Int) -> Float {
        let dx = Float(x) + 0.5 - Float(size) / 2, dy = Float(y) + 0.5 - Float(size) / 2
        return (dx * dx + dy * dy).squareRoot()
    }

    static func ring(_ x: Int, _ y: Int) -> Int { min(rings - 1, Int(radius(x, y) / ringWidth)) }

    /// Grey lightness of a radial ramp (a bokeh highlight), dark outside.
    static func ramp(_ r: Float) -> Float { 0.9 - 0.6 * min(r / (Float(rings) * ringWidth), 1) }

    /// Concentric regions, ring k painted with the ramp's colour at its middle.
    static func target() -> Segmentation {
        var labels = RegionMap(width: size, height: size, repeating: 0)
        for y in 0..<size {
            for x in 0..<size { labels[x, y] = UInt32(ring(x, y)) }
        }
        let palette = (0..<rings).map { k in
            PaletteColor(oklab: SIMD3(ramp((Float(k) + 0.5) * ringWidth), 0, 0), space: .sRGB)
        }
        return Segmentation(
            labels: labels, regionColor: (0..<rings).map(UInt32.init), palette: palette, colorSpace: .sRGB)
    }

    static func image(_ lightness: (Int, Int) -> Float) -> RGBAImage {
        var image = RGBAImage(width: size, height: size, fill: SIMD4(0, 0, 0, 255))
        for y in 0..<size {
            for x in 0..<size {
                let c = ColorScience.okLabToEncoded(SIMD3(lightness(x, y), 0, 0), space: .sRGB) * 255
                image[x, y] = SIMD4(UInt8(c.x.rounded()), UInt8(c.y.rounded()), UInt8(c.z.rounded()), 255)
            }
        }
        return image
    }

    @Test func rampSlicedIntoRingsCountsEveryRing() {
        // The photo is the smooth ramp; the regions are its posterization.
        let s = Self.target()
        let photo = Self.image { x, y in Self.ramp(Self.radius(x, y)) }
        #expect(BandRings.count(s, working: photo) == Self.rings)
    }

    @Test func hardEdgedTargetHasNoRings() {
        // Same regions and paints, but the photo itself steps by the whole paint difference
        // at every boundary: these are shapes, not bands.
        let s = Self.target()
        let photo = Self.image { x, y in s.palette[Int(s.regionColor[Int(s.labels[x, y])])].oklab.x }
        #expect(BandRings.count(s, working: photo) == 0)
    }

    @Test func thresholdsDecide() {
        let s = Self.target()
        let photo = Self.image { x, y in Self.ramp(Self.radius(x, y)) }
        // The ramp steps about 0.009 per pixel against paints 0.075 apart (12 %): weak below
        // a contrast of 0.25, not below 0.05.
        #expect(BandRings.count(s, working: photo, contrast: 0.05) == 0)
        #expect(BandRings.count(s, working: photo, contrast: 0.25, fraction: 1) == Self.rings)
    }

    @Test func degenerateInputsCountNothing() {
        let s = Self.target()
        // A working image of another size is not the one the regions were made from.
        let other = RGBAImage(width: Self.size, height: Self.size + 1, fill: SIMD4(128, 128, 128, 255))
        #expect(BandRings.count(s, working: other) == 0)
        // One region has no boundary at all.
        let single = Segmentation(
            labels: RegionMap(width: 4, height: 4, repeating: 0), regionColor: [0],
            palette: [PaletteColor(oklab: SIMD3(0.5, 0, 0), space: .sRGB)], colorSpace: .sRGB)
        #expect(BandRings.count(single, working: RGBAImage(width: 4, height: 4, fill: SIMD4(9, 9, 9, 255))) == 0)
        // Paint references outside the palette are malformed, not a crash.
        var broken = s
        broken.regionColor[3] = 99
        #expect(BandRings.count(broken, working: Self.image { _, _ in 0.5 }) == 0)
    }

    @Test func pipelineOutputIsCountedDeterministically() throws {
        // A noise-free sky ramp above flat ground with a red disc: the pipeline posterizes the
        // sky into bands, which are counted, while the disc and the ground are shapes; the
        // count is the same on every run.
        var image = RGBAImage(width: 240, height: 180, fill: SIMD4(0, 0, 0, 255))
        for y in 0..<180 {
            for x in 0..<240 {
                let t = Float(y) / 108
                var lab = y < 108 ? SIMD3<Float>(0.45 + 0.4 * t, -0.03, -0.1 + 0.06 * t) : SIMD3(0.5, -0.1, 0.08)
                let dx = Float(x - 170), dy = Float(y - 130)
                if dx * dx + dy * dy < 400 { lab = SIMD3(0.6, 0.18, 0.1) }
                let c = ColorScience.okLabToEncoded(lab, space: .sRGB) * 255
                image[x, y] = SIMD4(UInt8(c.x.rounded()), UInt8(c.y.rounded()), UInt8(c.z.rounded()), 255)
            }
        }
        let a = try TestScenes.segment(image)
        let b = try TestScenes.segment(image)
        let count = BandRings.count(a, working: image)
        #expect(count > 0 && count < a.regionCount)
        #expect(count == BandRings.count(b, working: image))
    }
}
