import Foundation
import Testing
@testable import PaintCore

@Suite("Beauty paint")
struct BeautyPaintTests {
    static func paint(_ L: Float, chroma: Float, hue degrees: Float) -> PaletteColor { LivelyPaintTests.paint(L, chroma: chroma, hue: degrees) }
    static func chroma(_ c: PaletteColor) -> Float { LivelyPaintTests.chroma(c) }
    static func hue(_ c: PaletteColor) -> Float { LivelyPaintTests.hue(c) }

    /// A hue-less black takes a touch of indigo; a mid grey and a white stay as they are.
    @Test func blacksAreMixedFromColorAndGreysStayGrey() {
        let greys = [Self.paint(0.2, chroma: 0.004, hue: 60), Self.paint(0.45, chroma: 0.004, hue: 90), Self.paint(0.95, chroma: 0.004, hue: 250)]
        let mixed = BeautyPaint.mix(greys, shares: [0.3, 0.4, 0.3], space: .sRGB, minDistance: 0.02)
        #expect(Self.chroma(mixed[0]) > 0.012 && (260...300).contains(Self.hue(mixed[0])))
        #expect(Self.chroma(mixed[1]) < 0.008)
        #expect(Self.chroma(mixed[2]) < 0.008)
    }

    /// A dark brown keeps its warm hue (no navy chocolate).
    @Test func darkBrownsStayWarm() {
        let brown = Self.paint(0.25, chroma: 0.04, hue: 55)
        let mixed = BeautyPaint.mix([brown], space: .sRGB, minDistance: 0.02)
        #expect(abs(Self.hue(mixed[0]) - 55) < 3)
    }

    /// A khaki turns toward sienna and gets more chroma; skin held as skin stays near its hue.
    @Test func mudIsCleanedButSkinIsKept() {
        let khaki = Self.paint(0.5, chroma: 0.07, hue: 75)
        let skin = Self.paint(0.7, chroma: 0.07, hue: 60)
        let mixed = BeautyPaint.mix([khaki, skin], shares: [0.5, 0.5], hold: [0, 1], space: .sRGB, minDistance: 0.02)
        #expect(Self.hue(mixed[0]) < 70)
        #expect(Self.chroma(mixed[0]) > Self.chroma(khaki) * 1.2)
        #expect(abs(Self.hue(mixed[1]) - 60) < 2)
        #expect(Self.chroma(mixed[1]) < Self.chroma(skin) * 1.15)
    }

    /// The subject gets bolder than a background of the same soft color; a vivid background
    /// keeps its chroma.
    @Test func theSubjectComesForward() {
        let a = Self.paint(0.5, chroma: 0.07, hue: 140), b = Self.paint(0.52, chroma: 0.07, hue: 145)
        let mixed = BeautyPaint.mix([a, b], shares: [0.5, 0.5], importance: [0.95, 0.2], space: .sRGB, minDistance: 0.02)
        #expect(Self.chroma(mixed[0]) > Self.chroma(mixed[1]) + 0.01)
        let vivid = Self.paint(0.55, chroma: 0.16, hue: 25)
        let kept = BeautyPaint.mix([a, vivid], shares: [0.5, 0.5], importance: [0.95, 0.2], space: .sRGB, minDistance: 0.02)
        #expect(Self.chroma(kept[1]) >= Self.chroma(vivid) - 0.002)
    }

    /// A face's paints (lips, an ear's flush) stay near the photo's chroma, however bold rich
    /// paint made them; the same red off the face isn't held, and a pale face's lit side keeps
    /// kit paint's lift (painting-company row 363).
    @Test func aFaceStaysNearThePhoto() {
        let photo = [Self.paint(0.5, chroma: 0.1, hue: 16), Self.paint(0.5, chroma: 0.1, hue: 16), Self.paint(0.75, chroma: 0.03, hue: 55)]
        let rich = [Self.paint(0.5, chroma: 0.18, hue: 16), Self.paint(0.5, chroma: 0.18, hue: 16), Self.paint(0.8, chroma: 0.055, hue: 55)]
        let mixed = BeautyPaint.mix(
            rich, shares: [0.1, 0.1, 0.8], faceShare: [0.9, 0, 0.9], photo: photo, space: .sRGB, minDistance: 0.02)
        #expect(Self.chroma(mixed[0]) <= 0.1 * BeautyPaint.faceGain + 0.002)
        #expect(abs(Self.hue(mixed[0]) - 16) < 3)
        #expect(Self.chroma(mixed[1]) > 0.18)
        let unheld = BeautyPaint.mix(rich, shares: [0.1, 0.1, 0.8], faceShare: [0.9, 0, 0.9], space: .sRGB, minDistance: 0.02)
        #expect(abs(Self.chroma(mixed[2]) - Self.chroma(unheld[2])) < 1e-4)
    }

    /// Paints never come closer than the floor where they weren't.
    @Test func paintsStayApart() {
        let palette = (0..<8).map { Self.paint(0.3 + 0.01 * Float($0), chroma: 0.004 * Float($0), hue: 40 * Float($0)) }
        let mixed = BeautyPaint.mix(palette, space: .sRGB, minDistance: 0.02)
        for i in palette.indices {
            for j in palette.indices where j > i {
                let before = ColorScience.distance(palette[i].oklab, palette[j].oklab)
                let after = ColorScience.distance(mixed[i].oklab, mixed[j].oklab)
                #expect(after >= min(before, 0.02) - 1e-5)
            }
        }
    }

    @Test func beautyTemplateKeepsTheRegions() throws {
        let image = TestScenes.colorful()
        let rich = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .rich)).generate(from: image, cancel: .none)
        let beauty = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .beauty))
            .generate(from: image, cancel: .none)
        #expect(beauty.template.regions == rich.template.regions)
        #expect(beauty.template.edges == rich.template.edges)
        #expect(beauty.template.palette != rich.template.palette)
        #expect(beauty.template.validate().isValid)
        let again = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .beauty))
            .generate(from: image, cancel: .none)
        #expect(again.template.encoded() == beauty.template.encoded())
        let coded = try JSONEncoder().encode(GenerationSettings(paintMix: .beauty))
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: coded).paintMix == .beauty)
    }
}
