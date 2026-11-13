import Foundation
import Testing
@testable import PaintCore

@Suite("Lively paint")
struct LivelyPaintTests {
    static func paint(_ L: Float, chroma: Float, hue degrees: Float) -> PaletteColor {
        let h = degrees * .pi / 180
        return PaletteColor(oklab: SIMD3(L, chroma * cos(h), chroma * sin(h)), space: .sRGB)
    }

    static func chroma(_ c: PaletteColor) -> Float { (c.oklab.y * c.oklab.y + c.oklab.z * c.oklab.z).squareRoot() }

    /// A paint's hue in degrees, 0..<360.
    static func hue(_ c: PaletteColor) -> Float {
        let h = atan2(c.oklab.z, c.oklab.y) * 180 / .pi
        return h < 0 ? h + 360 : h
    }

    @Test func aFamilysLightsTurnWarmAndItsMainPaintKeepsItsHue() {
        // Greens at 140°: the main one, a light and a dark shade of it.
        let greens = [Self.paint(0.55, chroma: 0.08, hue: 140), Self.paint(0.78, chroma: 0.08, hue: 140), Self.paint(0.32, chroma: 0.06, hue: 140)]
        let mixed = LivelyPaint.mix(greens, shares: [0.8, 0.1, 0.1], space: .sRGB, minDistance: 0.04)
        // The light shade goes toward yellow by more than 8°, the dark one toward blue by less
        // (its pole is across the wheel), and the main paint stays within 3°.
        #expect(Self.hue(mixed[1]) < 132 && Self.hue(mixed[1]) > 115)
        #expect(Self.hue(mixed[2]) > 141 && Self.hue(mixed[2]) < 152)
        #expect(abs(Self.hue(mixed[0]) - 140) < 3)
        // Lightness is kit paint's, and each is a little more colourful.
        for (kit, lively) in zip(greens, mixed) {
            #expect(abs(lively.oklab.x - kit.oklab.x) < 0.01)
            #expect(Self.chroma(lively) > Self.chroma(kit) && Self.chroma(lively) < Self.chroma(kit) * 1.13)
        }
    }

    @Test func aPaintAloneInItsFamilyAGreyAndSkinKeepTheirHue() {
        // A red, a blue and a grey: no two share a family.
        let palette = [Self.paint(0.5, chroma: 0.09, hue: 25), Self.paint(0.6, chroma: 0.09, hue: 250), Self.paint(0.5, chroma: 0.012, hue: 60)]
        let mixed = LivelyPaint.mix(palette, space: .sRGB, minDistance: 0.04)
        #expect(abs(Self.hue(mixed[0]) - 25) < 1)
        #expect(abs(Self.hue(mixed[1]) - 250) < 1)
        #expect(mixed[2] == palette[2])
        // A face's skin, a light and a dark shade of it, is held whole; the same two off any
        // face (a coat's fur) turn.
        let skin = [Self.paint(0.7, chroma: 0.07, hue: 55), Self.paint(0.45, chroma: 0.07, hue: 55)]
        let held = LivelyPaint.mix(skin, hold: [1, 1], space: .sRGB, minDistance: 0.04)
        #expect(ColorScience.distance(held[0].oklab, skin[0].oklab) < 0.002)
        #expect(ColorScience.distance(held[1].oklab, skin[1].oklab) < 0.002)
        #expect(Self.hue(LivelyPaint.mix(skin, space: .sRGB, minDistance: 0.04)[0]) > 58)
    }

    /// What the critics of rounds 1 and 2 saw: a macaw's yellow chest gone peach, a red flower
    /// magenta, a chocolate cake plum, a blue wall turquoise.
    @Test func signatureColorsStay() {
        // A vivid light yellow beside darker ochres: orange is out of gamut at its lightness.
        let yellows = [Self.paint(0.88, chroma: 0.18, hue: 100), Self.paint(0.6, chroma: 0.1, hue: 85), Self.paint(0.45, chroma: 0.08, hue: 80)]
        let chest = LivelyPaint.mix(yellows, space: .sRGB, minDistance: 0.04)[0]
        #expect(Self.chroma(chest) >= Self.chroma(yellows[0]) - 0.003)
        #expect(abs(Self.hue(chest) - Self.hue(yellows[0])) < 6)
        // A vivid red below pale pinks.
        let reds = [Self.paint(0.55, chroma: 0.2, hue: 28), Self.paint(0.8, chroma: 0.07, hue: 20), Self.paint(0.86, chroma: 0.05, hue: 30)]
        #expect(abs(Self.hue(LivelyPaint.mix(reds, space: .sRGB, minDistance: 0.04)[0]) - 28) < 5)
        // Dark browns below a tan, and a light blue above a navy.
        let browns = [Self.paint(0.6, chroma: 0.06, hue: 60), Self.paint(0.3, chroma: 0.05, hue: 50), Self.paint(0.24, chroma: 0.035, hue: 45)]
        let cake = LivelyPaint.mix(browns, space: .sRGB, minDistance: 0.04)
        #expect(abs(Self.hue(cake[1]) - 50) < 7 && abs(Self.hue(cake[2]) - 45) < 7)
        let blues = [Self.paint(0.71, chroma: 0.11, hue: 243), Self.paint(0.46, chroma: 0.1, hue: 247), Self.paint(0.31, chroma: 0.1, hue: 263)]
        let wall = LivelyPaint.mix(blues, shares: [0.6, 0.2, 0.2], space: .sRGB, minDistance: 0.04)
        #expect(abs(Self.hue(wall[0]) - 243) < 6)
        // The navy deepens to the cool pole and never past it.
        #expect(Self.hue(wall[2]) >= 262 && Self.hue(wall[2]) <= 266.5)
    }

    @Test func paintsStayInGamutApartAndAsColorful() {
        var rng = SplitMix64(seed: 23)
        var palette: [PaletteColor] = []
        var shares: [Float] = []
        for _ in 0..<40 {
            let rgb = SIMD3(Float(rng.next() % 256), Float(rng.next() % 256), Float(rng.next() % 256)) / 255
            palette.append(PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .displayP3), rgb: rgb))
            shares.append(Float(rng.next() % 100) / 100)
        }
        let minDistance: Float = 0.02
        for shares in [shares, []] {
            let mixed = LivelyPaint.mix(palette, shares: shares, space: .displayP3, minDistance: minDistance)
            #expect(mixed.count == palette.count)
            for (i, c) in mixed.enumerated() {
                #expect(all(c.rgb .>= 0) && all(c.rgb .<= 1))
                #expect(ColorScience.distance(c.oklab, ColorScience.encodedToOKLab(c.rgb, space: .displayP3)) < 1e-4)
                #expect(abs(c.oklab.x - palette[i].oklab.x) < 0.02)
                #expect(Self.chroma(c) >= Self.chroma(palette[i]) - 0.004)
                #expect(Self.chroma(c) <= Self.chroma(palette[i]) * 1.12 + 1e-3)
                for j in mixed.indices where j > i {
                    let before = ColorScience.distance(palette[i].oklab, palette[j].oklab)
                    #expect(ColorScience.distance(c.oklab, mixed[j].oklab) >= min(before, minDistance) - 1e-4)
                }
            }
        }
        // Shares that aren't the palette's, or aren't numbers, count every paint alike.
        let alike = LivelyPaint.mix(palette, space: .displayP3, minDistance: minDistance)
        #expect(LivelyPaint.mix(palette, shares: [1], space: .displayP3, minDistance: minDistance) == alike)
        #expect(LivelyPaint.mix(palette, shares: shares.map { _ in Float.nan }, space: .displayP3, minDistance: minDistance) == alike)
        #expect(LivelyPaint.mix([], space: .sRGB, minDistance: minDistance).isEmpty)
    }

    @Test func sharesCountEachPaintsPixels() {
        let labels = RegionMap(width: 2, height: 2, storage: [0, 1, 2, 2])
        let grey = PaletteColor(oklab: SIMD3(0.5, 0, 0), space: .sRGB)
        let segmentation = Segmentation(labels: labels, regionColor: [0, 0, 1], palette: [grey, grey, grey], colorSpace: .sRGB)
        #expect(LivelyPaint.shares(of: segmentation) == [0.5, 0.5, 0])
    }

    @Test func livelyTemplateKeepsTheRegionsAndIsKitPaintsWithHuesSpread() throws {
        let image = TestScenes.colorful()
        let kit = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .kit)).generate(from: image, cancel: .none)
        let lively = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .lively))
            .generate(from: image, cancel: .none)
        #expect(lively.template.regions == kit.template.regions)
        #expect(lively.template.edges == kit.template.edges)
        #expect(lively.template.palette.count == kit.template.palette.count)
        #expect(lively.template.palette != kit.template.palette)
        #expect(lively.template.validate().isValid)
        #expect(LivelyPaint.shares(of: lively.template).reduce(0, +) > 0.99)
        // A painting remade with its own paints pinned is the painting it was.
        let again = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .lively))
            .generate(from: image, cancel: .none, palette: lively.template.palette)
        #expect(again.template.encoded() == lively.template.encoded())
        let settings = try JSONEncoder().encode(GenerationSettings(paintMix: .lively))
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: settings).paintMix == .lively)
        // The other mixes through the same door.
        let palette = kit.template.palette
        #expect(PaintMix.photo.mixed(palette, space: .sRGB, minDistance: 0.04) == palette)
        #expect(PaintMix.kit.mixed(palette, space: .sRGB, minDistance: 0.04) == KitPaint.mix(palette, space: .sRGB, minDistance: 0.04))
    }
}
