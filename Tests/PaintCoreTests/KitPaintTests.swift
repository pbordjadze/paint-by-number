import Foundation
import Testing
@testable import PaintCore

@Suite("Kit paint")
struct KitPaintTests {
    static func paint(_ L: Float, _ a: Float, _ b: Float) -> PaletteColor {
        PaletteColor(oklab: SIMD3(L, a, b), space: .sRGB)
    }

    static func chroma(_ c: PaletteColor) -> Float { (c.oklab.y * c.oklab.y + c.oklab.z * c.oklab.z).squareRoot() }

    @Test func aMutedPaintGetsBolderAndAFacesSkinStaysClose() {
        // A muted blue, a muted green, light skin, medium skin, a near-white grey, dark skin.
        let palette = [
            Self.paint(0.55, -0.03, -0.06), Self.paint(0.6, -0.06, 0.05), Self.paint(0.837, 0.033, 0.056),
            Self.paint(0.677, 0.060, 0.070), Self.paint(0.95, 0.002, 0.004), Self.paint(0.38, 0.037, 0.044),
        ]
        // The skins are paints on a face.
        // The photo's skin there at 40°.
        let skinHue = SIMD2<Float>(0.766_044, 0.642_788)
        let mixed = KitPaint.mix(
            palette, space: .sRGB, minDistance: 0.04, faces: KitPaint.Faces(share: [0, 0, 0.6, 0.6, 0, 0.6], skinHue: skinHue))
        let gain = zip(palette, mixed).map { Self.chroma($1) / Self.chroma($0) }
        #expect(gain[0] > 1.25 && gain[0] < 1.31)
        #expect(gain[1] > 1.25 && gain[1] < 1.31)
        #expect(gain[2] > 0.98 && gain[2] < 1.08)  // lifted to the sRGB edge: chroma clipped
        #expect(gain[3] > 1.0 && gain[3] < 1.08)
        // A near-grey keeps its hue's strength: an off-white never turns pink.
        #expect(abs(Self.chroma(mixed[4]) - Self.chroma(palette[4])) < 0.002)
        // White stays white, the darks go darker and the lights lighter, by a little.
        #expect(abs(mixed[4].oklab.x - palette[4].oklab.x) < 0.02)
        #expect(mixed[0].oklab.x > palette[0].oklab.x)
        // Medium skin is lifted a little and turned most of the way to the face's own hue (from
        // 49° toward 40°); pale skin is barely lifted and dark skin not at all.
        #expect(mixed[3].oklab.x - palette[3].oklab.x > 0.03 && mixed[3].oklab.x - palette[3].oklab.x < 0.08)
        #expect(mixed[2].oklab.x - palette[2].oklab.x < 0.02)
        func hue(_ c: PaletteColor) -> Float { atan2(c.oklab.z, c.oklab.y) }
        #expect(hue(mixed[3]) < hue(palette[3]) - 0.1 && hue(mixed[3]) > atan2(skinHue.y, skinHue.x) - 0.01)
        #expect(mixed[5].oklab.x <= palette[5].oklab.x + 0.002)
        // A red by a face of skin at 57°, 30° from the red's hue, keeps its own.
        let red = Self.paint(0.4, 0.087, 0.05)
        let face57 = KitPaint.Faces(share: [0.6], skinHue: SIMD2(0.544_639, 0.838_671))
        let byFace = KitPaint.mix([red], space: .sRGB, minDistance: 0.04, faces: face57)[0]
        #expect(abs(hue(byFace) - hue(red)) < 0.01)
        // The same tan off any face (a fox's coat) is held back only a little, and not lifted.
        let coat = KitPaint.mix([palette[3]], space: .sRGB, minDistance: 0.04)[0]
        #expect(Self.chroma(coat) / Self.chroma(palette[3]) > 1.15)
        #expect(abs(hue(coat) - hue(palette[3])) < 0.01)
    }

    /// kodim04's face: fair skin in dim light, its skin at L 0.52 with chroma 0.042, painted as
    /// a kit paints fair skin on its lit side, and only on a pale face.
    @Test func aPaleFacesLitSideIsPaintedLighterAndPeach() {
        func hue(_ c: PaletteColor) -> Float { atan2(c.oklab.z, c.oklab.y) * 180 / .pi }
        func paint(_ L: Float, _ chroma: Float, _ degrees: Float) -> PaletteColor {
            Self.paint(L, chroma * cos(degrees * .pi / 180), chroma * sin(degrees * .pi / 180))
        }
        // The lit cheek (64°, yellower than the face), the shadow, blond hair at 77°.
        let palette = [paint(0.6, 0.037, 64), paint(0.4, 0.045, 56), paint(0.73, 0.035, 77)]
        let skinHue = SIMD2<Float>(cos(57 * .pi / 180), sin(57 * .pi / 180))
        let share: [Float] = [0.6, 0.6, 0.6]
        let pale = KitPaint.mix(
            palette, space: .sRGB, minDistance: 0.02,
            faces: KitPaint.Faces(share: share, skinHue: skinHue, skinLightness: 0.52, pallor: 1))
        let tanned = KitPaint.mix(
            palette, space: .sRGB, minDistance: 0.02,
            faces: KitPaint.Faces(share: share, skinHue: skinHue, skinLightness: 0.52, pallor: 0))
        // The lit cheek: lighter, a cleaner chroma, turned past the face's hue toward peach.
        #expect(pale[0].oklab.x - tanned[0].oklab.x > 0.04)
        #expect(Self.chroma(pale[0]) > 0.043)
        #expect(hue(pale[0]) < 55 && hue(pale[0]) > 45)
        #expect(hue(tanned[0]) > 56)
        // The shadow is the tanned face's.
        #expect(ColorScience.distance(pale[1].oklab, tanned[1].oklab) < 0.002)
        // The hair is lifted with the cheek, so the two keep apart, and stays blond.
        #expect(abs(hue(pale[2]) - hue(palette[2])) < 1)
        #expect(pale[2].oklab.x > tanned[2].oklab.x)
        // A darker face's lit paint beside the fair one (chroma 0.08 at L 0.55) keeps its colour.
        let darker = paint(0.55, 0.08, 55)
        let faces = KitPaint.Faces(share: [0.6], skinHue: skinHue, skinLightness: 0.52, pallor: 1)
        let mixed = KitPaint.mix([darker], space: .sRGB, minDistance: 0.02, faces: faces)[0]
        let unpaled = KitPaint.mix([darker], space: .sRGB, minDistance: 0.02, faces: KitPaint.Faces(
            share: [0.6], skinHue: skinHue, skinLightness: 0.52, pallor: 0))[0]
        #expect(ColorScience.distance(mixed.oklab, unpaled.oklab) < 0.002)
    }

    /// A pale face's lit paints up to its highlights keep their order of lightness.
    @Test func aPaleFacesPaintsKeepTheirLightnessOrder() {
        let faces = KitPaint.Faces(share: [0.6], skinHue: SIMD2(0.642_788, 0.766_044), skinLightness: 0.52, pallor: 1)
        var last: Float = 0
        for i in 0...60 {
            let L = 0.4 + 0.01 * Float(i)
            let mixed = KitPaint.mix([Self.paint(L, 0.032, 0.038)], space: .sRGB, minDistance: 0.02, faces: faces)[0]
            #expect(mixed.oklab.x > last)
            last = mixed.oklab.x
        }
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
            }
        }
    }

    /// A grey scale, warm and cool greys alternating: every grey is mixed alike, so the scale
    /// keeps its order and nothing bunches up at white.
    @Test func greysKeepTheirOrder() {
        var palette: [PaletteColor] = []
        for i in 0..<18 {
            let L: Float = 0.08 + 0.05 * Float(i)
            let tint: SIMD2<Float> = i % 2 == 0 ? SIMD2(0.008, 0.01) : SIMD2(-0.004, -0.008)
            palette.append(Self.paint(L, tint.x, tint.y))
        }
        let mixed = KitPaint.mix(palette, space: .sRGB, minDistance: 0.04)
        for i in 1..<mixed.count {
            #expect(mixed[i].oklab.x > mixed[i - 1].oklab.x)
            #expect(ColorScience.distance(mixed[i].oklab, mixed[i - 1].oklab) >= 0.04)
        }
    }

    @Test func facesCountEachPaintsPixelsOnAFaceAndReadItsSkin() throws {
        // Four pixels, three regions, two paints: paint 0 has one of its two pixels on a face,
        // the pixel by the eye (a 0.1-wide eye reaches 0.4 of the canvas).
        let labels = RegionMap(width: 2, height: 2, storage: [0, 1, 2, 2])
        let segmentation = Segmentation(
            labels: labels, regionColor: [0, 0, 1], palette: [Self.paint(0.5, 0, 0), Self.paint(0.7, 0, 0)], colorSpace: .sRGB)
        let eye: [SIMD2<Float>] = [SIMD2(0.2, 0.2), SIMD2(0.3, 0.2), SIMD2(0.3, 0.3)]
        // The face's pixel is skin (234, 192, 160: hue 59°), the rest blue.
        let photo = RGBAImage(width: 2, height: 2, pixels: [234, 192, 160, 255] + [UInt8](repeating: 0, count: 3).flatMap { _ in [40, 60, 200, 255] })
        let importance: [Float] = [0.95, 0.5, 0.75, 0.75]
        let faces = KitPaint.faces(of: segmentation, importance: importance, eyes: [eye], photo: photo)
        #expect(faces.share == [0.5, 0])
        let hue = try #require(faces.skinHue)
        #expect(abs(atan2(hue.y, hue.x) * 180 / .pi - 59) < 2)
        // Fair skin, well lit: chroma 0.06 at lightness 0.82, pale for its lightness.
        #expect(abs(faces.skinLightness - 0.82) < 0.02)
        #expect(faces.pallor == 1)
        // A face's importance with no eye near (an animal's box, a busy centre) is no face.
        #expect(KitPaint.faces(of: segmentation, importance: importance, eyes: [], photo: photo) == KitPaint.Faces(share: [0, 0]))
        let far: [SIMD2<Float>] = [SIMD2(10, 10), SIMD2(10.01, 10.01)]
        #expect(KitPaint.faces(of: segmentation, importance: importance, eyes: [far], photo: photo).share == [0, 0])
        #expect(KitPaint.faces(of: segmentation, importance: [1], eyes: [eye], photo: photo).share == [0, 0])
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
