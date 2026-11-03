import Foundation
import Testing
@testable import PaintCore

@Suite("Kit paint")
struct KitPaintTests {
    static func paint(_ L: Float, _ a: Float, _ b: Float) -> PaletteColor {
        PaletteColor(oklab: SIMD3(L, a, b), space: .sRGB)
    }

    static func chroma(_ c: PaletteColor) -> Float { (c.oklab.y * c.oklab.y + c.oklab.z * c.oklab.z).squareRoot() }

    @Test func aMutedPaintGetsBolderAndSkinStaysClose() {
        // A muted blue, a muted green, light skin, medium skin, a near-white grey.
        let palette = [
            Self.paint(0.55, -0.03, -0.06), Self.paint(0.6, -0.06, 0.05), Self.paint(0.837, 0.033, 0.056),
            Self.paint(0.677, 0.060, 0.070), Self.paint(0.95, 0.002, 0.004),
        ]
        let mixed = KitPaint.mix(palette, space: .sRGB, minDistance: 0.04)
        let gain = zip(palette, mixed).map { Self.chroma($1) / Self.chroma($0) }
        #expect(gain[0] > 1.25 && gain[0] < 1.31)
        #expect(gain[1] > 1.25 && gain[1] < 1.31)
        #expect(gain[2] > 1.05 && gain[2] < 1.13)
        #expect(gain[3] > 1.05 && gain[3] < 1.13)
        // A near-grey keeps its hue's strength: an off-white never turns pink.
        #expect(abs(Self.chroma(mixed[4]) - Self.chroma(palette[4])) < 0.002)
        // White stays white, the darks go darker and the lights lighter, by a little.
        #expect(abs(mixed[4].oklab.x - palette[4].oklab.x) < 0.02)
        #expect(mixed[0].oklab.x > palette[0].oklab.x)
        #expect(mixed[2].oklab.x > palette[2].oklab.x && mixed[2].oklab.x - palette[2].oklab.x < 0.02)
    }

    @Test func paintsStayInGamutOrderedAndApart() {
        var rng = SplitMix64(seed: 11)
        var palette: [PaletteColor] = []
        for _ in 0..<40 {
            let rgb = SIMD3(Float(rng.next() % 256), Float(rng.next() % 256), Float(rng.next() % 256)) / 255
            palette.append(PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .displayP3), rgb: rgb))
        }
        // Two paints just apart, which the mix must not push together.
        palette.append(PaletteColor(oklab: SIMD3(0.97, 0, 0.01), space: .displayP3))
        palette.append(PaletteColor(oklab: SIMD3(0.99, 0, 0.01), space: .displayP3))
        let minDistance: Float = 0.02
        let mixed = KitPaint.mix(palette, space: .displayP3, minDistance: minDistance)
        #expect(mixed.count == palette.count)
        for (i, c) in mixed.enumerated() {
            #expect(all(c.rgb .>= 0) && all(c.rgb .<= 1))
            #expect(ColorScience.distance(c.oklab, ColorScience.encodedToOKLab(c.rgb, space: .displayP3)) < 1e-4)
            // Never neon: a paint is at most as vivid as the gain allows.
            #expect(Self.chroma(c) <= Self.chroma(palette[i]) * 1.3 + 1e-3)
            for j in mixed.indices where j > i {
                let before = ColorScience.distance(palette[i].oklab, palette[j].oklab)
                #expect(ColorScience.distance(c.oklab, mixed[j].oklab) >= min(before, minDistance) - 1e-4)
                // Lightness keeps its order (both paints greyish here keep it exactly).
                if Self.chroma(palette[i]) < 0.01, Self.chroma(palette[j]) < 0.01 {
                    #expect((palette[i].oklab.x < palette[j].oklab.x) == (c.oklab.x < mixed[j].oklab.x))
                }
            }
        }
    }

    @Test func kitTemplateKeepsTheRegionsAndMovesOnlyThePaints() throws {
        let image = TestScenes.colorful()
        let photo = try TemplateGenerator(settings: GenerationSettings(colorCount: 12)).generate(from: image, cancel: .none)
        let samePhoto = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .photo))
            .generate(from: image, cancel: .none)
        let kit = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .kit))
            .generate(from: image, cancel: .none)
        #expect(samePhoto.template.encoded() == photo.template.encoded())
        #expect(kit.template.regions == photo.template.regions)
        #expect(kit.template.edges == photo.template.edges)
        #expect(kit.template.palette.count == photo.template.palette.count)
        #expect(kit.template.palette != photo.template.palette)
        #expect(kit.template.validate().isValid)
    }

    @Test func settingsWithoutAMixDecodeAsThePhotos() throws {
        let plain = try JSONEncoder().encode(GenerationSettings())
        #expect(!String(decoding: plain, as: UTF8.self).contains("paintMix"))
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: plain).paintMix == nil)
        let kit = try JSONEncoder().encode(GenerationSettings(paintMix: .kit))
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: kit).paintMix == .kit)
        // A mix a later app knows and this one doesn't: the photo's.
        let later = Data(#"{"colorCount":24,"detail":0.5,"smoothness":0.5,"seed":1,"paintMix":"watercolor"}"#.utf8)
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: later).paintMix == nil)
        #expect(GenerationSettings(paintMix: .photo).normalized == GenerationSettings().normalized)
    }
}
