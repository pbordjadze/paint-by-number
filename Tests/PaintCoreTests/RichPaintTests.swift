import Foundation
import Testing
@testable import PaintCore

@Suite("Rich paint")
struct RichPaintTests {
    static func paint(_ L: Float, chroma: Float, hue degrees: Float) -> PaletteColor { LivelyPaintTests.paint(L, chroma: chroma, hue: degrees) }

    /// A 32 × 16 canvas in two regions of one paint: the left half a face (`left`, with an eye
    /// at its middle and a face's importance), the right half something else (`right`).
    static func scene(left: SIMD3<UInt8>, right: SIMD3<UInt8>, filler: Int = 9) -> (Segmentation, [Float], [[SIMD2<Float>]], RGBAImage) {
        let w = 32, h = 16
        var labels = RegionMap(width: w, height: h, repeating: 0)
        var pixels: [UInt8] = []
        var importance: [Float] = []
        for y in 0..<h {
            for x in 0..<w {
                let face = x < w / 2
                labels.storage[y * w + x] = face ? 0 : 1
                let c = face ? left : right
                pixels += [c.x, c.y, c.z, 255]
                importance.append(face ? 0.95 : 0.5)
            }
        }
        let photo = RGBAImage(width: w, height: h, pixels: pixels)
        // The two halves' mean, as a segmentation that found them alike would paint them.
        let mean = (ColorScience.encodedToOKLab(SIMD3<Float>(left) / 255, space: photo.colorSpace)
            + ColorScience.encodedToOKLab(SIMD3<Float>(right) / 255, space: photo.colorSpace)) / 2
        // Nine greys first, so the shared paint is number 10: a split's new number is no longer.
        let greys = (0..<filler).map { PaletteColor(oklab: SIMD3(0.1 * Float($0 + 1), 0, 0), space: photo.colorSpace) }
        let segmentation = Segmentation(
            labels: labels, regionColor: [UInt32(filler), UInt32(filler)],
            palette: greys + [PaletteColor(oklab: mean, space: photo.colorSpace)], colorSpace: photo.colorSpace)
        // An eye a tenth of the canvas wide at the left half's middle: the face reaches 12.8 px.
        let eye: [SIMD2<Float>] = [SIMD2(0.2, 0.5), SIMD2(0.25, 0.47), SIMD2(0.3, 0.5), SIMD2(0.25, 0.53)]
        return (segmentation, importance, [eye], photo)
    }

    /// Girl with a Pearl Earring's cheek in shadow and her ochre jacket, one khaki paint.
    @Test func aFaceTakesItsOwnPaintFromWhatItSharedOneWith() {
        let skin = SIMD3<UInt8>(160, 124, 100), ochre = SIMD3<UInt8>(158, 130, 84)
        var (segmentation, importance, eyes, photo) = Self.scene(left: skin, right: ochre)
        let shared = segmentation.palette[9]
        #expect(FacePaints.split(&segmentation, importance: importance, eyes: eyes, photo: photo, minRadius: { _ in 3 }) == 1)
        // The face's region takes the new, last paint; the jacket keeps its number.
        #expect(segmentation.regionColor == [10, 9])
        #expect(segmentation.palette.count == 11)
        let skinLab = ColorScience.encodedToOKLab(SIMD3<Float>(skin) / 255, space: photo.colorSpace)
        let ochreLab = ColorScience.encodedToOKLab(SIMD3<Float>(ochre) / 255, space: photo.colorSpace)
        #expect(ColorScience.distance(segmentation.palette[10].oklab, skinLab) < 0.004)
        #expect(ColorScience.distance(segmentation.palette[9].oklab, ochreLab) < 0.004)
        #expect(ColorScience.distance(shared.oklab, skinLab) > 0.008)
        // The shared paint as number 9 of nine: the new paint is number 10, and the face's
        // region takes it only with room for two digits (it holds a disc of 7.5, no larger).
        var short = Self.scene(left: skin, right: ochre, filler: 8)
        #expect(FacePaints.split(&short.0, importance: short.1, eyes: short.2, photo: short.3, minRadius: { $0 == 2 ? 8 : 3 }) == 0)
        #expect(short.0.regionColor == [8, 8])
        #expect(FacePaints.split(&short.0, importance: short.1, eyes: short.2, photo: short.3, minRadius: { $0 == 2 ? 7 : 3 }) == 1)
        #expect(short.0.regionColor == [9, 8])
        let labels = short.0.labels
        #expect(FacePaints.roomy(labels, among: [true, true], radius: 7.5) == [true, true])
        #expect(FacePaints.roomy(labels, among: [true, false], radius: 7.6) == [false, false])
    }

    /// Painting-company row 344's review: a split's paints stay a just-noticeable difference apart.
    @Test func splitPaintsStayAJustNoticeableDifferenceApart() {
        let skin = SIMD3<UInt8>(160, 124, 100), near = SIMD3<UInt8>(158, 127, 95)
        var (close, importance, eyes, photo) = Self.scene(left: skin, right: near)
        let gap = ColorScience.distance(
            ColorScience.encodedToOKLab(SIMD3<Float>(skin) / 255, space: photo.colorSpace),
            ColorScience.encodedToOKLab(SIMD3<Float>(near) / 255, space: photo.colorSpace))
        #expect(gap >= FacePaints.apart && gap < SegmentationParameters.jnd)
        #expect(FacePaints.split(&close, importance: importance, eyes: eyes, photo: photo, minRadius: { _ in 3 }) == 1)
        #expect(ColorScience.distance(close.palette[10].oklab, close.palette[9].oklab) >= SegmentationParameters.jnd)
        // A paint already where the jacket's half would land: the paint stays whole.
        let ochre = SIMD3<UInt8>(158, 130, 84)
        var (taken, _, _, _) = Self.scene(left: skin, right: ochre)
        taken.palette[0] = PaletteColor(
            oklab: ColorScience.encodedToOKLab(SIMD3<Float>(ochre) / 255, space: photo.colorSpace), space: photo.colorSpace)
        #expect(FacePaints.split(&taken, importance: importance, eyes: eyes, photo: photo, minRadius: { _ in 3 }) == 0)
        #expect(taken.regionColor == [9, 9] && taken.palette.count == 10)
    }

    @Test func onlyAFacesSkinThatDiffersSplits() {
        let skin = SIMD3<UInt8>(160, 124, 100)
        // The neck in the same light: one paint still, mixed as the face is.
        var (neck, importance, eyes, photo) = Self.scene(left: skin, right: SIMD3(161, 125, 100))
        #expect(FacePaints.split(&neck, importance: importance, eyes: eyes, photo: photo, minRadius: { _ in 3 }) == 0)
        #expect(neck.regionColor == [9, 9] && neck.palette.count == 10)
        // A headscarf's blue across the brow is no skin.
        var scarf = Self.scene(left: SIMD3(90, 120, 170), right: SIMD3(70, 100, 150))
        #expect(FacePaints.split(&scarf.0, importance: scarf.1, eyes: scarf.2, photo: scarf.3, minRadius: { _ in 3 }) == 0)
        // No eye, no face; maps of another size are no maps.
        var (plain, _, _, _) = Self.scene(left: skin, right: SIMD3(158, 130, 84))
        let whole = plain.palette
        #expect(FacePaints.split(&plain, importance: importance, eyes: [], photo: photo, minRadius: { _ in 3 }) == 0)
        #expect(FacePaints.split(&plain, importance: [1], eyes: eyes, photo: photo, minRadius: { _ in 3 }) == 0)
        #expect(plain.palette == whole)
        // A face's importance without the pixels (an eye near, the map low): no face.
        let low = [Float](repeating: 0.5, count: importance.count)
        #expect(FacePaints.split(&plain, importance: low, eyes: eyes, photo: photo, minRadius: { _ in 3 }) == 0)
    }

    /// The muddy face (painting-company row 344): a pale face's cheek in shadow, L 0.58 with
    /// chroma 0.052 at 65°, which kit paint leaves a grey brown.
    @Test func aPaleFacesShadowIsMixedWarm() {
        let cheek = Self.paint(0.58, chroma: 0.052, hue: 65)
        let hue56 = SIMD2<Float>(0.559_193, 0.829_038)
        let pale = KitPaint.Faces(share: [1], skinHue: hue56, skinLightness: 0.75, pallor: 1)
        let kit = KitPaint.mix([cheek], space: .sRGB, minDistance: 0.04, faces: pale)[0]
        let rich = KitPaint.mix([cheek], space: .sRGB, minDistance: 0.04, faces: pale, warmShadows: true)[0]
        // More chroma for its lightness (about a tenth of it), pinker and never past 40°, and
        // lifted a part of the way to the skin's mean.
        #expect(LivelyPaintTests.chroma(rich) > LivelyPaintTests.chroma(kit) + 0.008)
        #expect(LivelyPaintTests.chroma(rich) < 0.12 * rich.oklab.x)
        #expect(LivelyPaintTests.hue(rich) < LivelyPaintTests.hue(kit) - 5 && LivelyPaintTests.hue(rich) >= 39.5)
        #expect(rich.oklab.x > kit.oklab.x + 0.02 && rich.oklab.x < 0.75)
        // Tanned and dark skin has its colour: as kit paint mixes it.
        let tanned = KitPaint.Faces(share: [1], skinHue: hue56, skinLightness: 0.55, pallor: 0)
        let dark = Self.paint(0.42, chroma: 0.05, hue: 55)
        #expect(
            KitPaint.mix([dark], space: .sRGB, minDistance: 0.04, faces: tanned, warmShadows: true)
                == KitPaint.mix([dark], space: .sRGB, minDistance: 0.04, faces: tanned))
        // The brown-black beside a pale face stays as it was, and so does a paint off the face.
        let black = Self.paint(0.28, chroma: 0.03, hue: 60)
        let off = KitPaint.Faces(share: [1, 0], skinHue: hue56, skinLightness: 0.75, pallor: 1)
        #expect(
            KitPaint.mix([black, cheek], space: .sRGB, minDistance: 0.04, faces: off, warmShadows: true)
                == KitPaint.mix([black, cheek], space: .sRGB, minDistance: 0.04, faces: off))
        // Lighter paints stay lighter.
        let shades = [0.45, 0.52, 0.58, 0.65, 0.72, 0.8].map { Self.paint(Float($0), chroma: 0.05, hue: 62) }
        let face = KitPaint.Faces(share: shades.map { _ in 1 }, skinHue: hue56, skinLightness: 0.75, pallor: 1)
        let mixed = KitPaint.mix(shades, space: .sRGB, minDistance: 0, faces: face, warmShadows: true)
        for (darker, lighter) in zip(mixed, mixed.dropFirst()) { #expect(darker.oklab.x < lighter.oklab.x) }
    }

    @Test func richTurnsFurtherAndLeavesABroadBackgroundCalm() {
        // Greens at 140°: a background over most of the painting, a light and a dark shade.
        let greens = [Self.paint(0.55, chroma: 0.08, hue: 140), Self.paint(0.78, chroma: 0.08, hue: 140), Self.paint(0.32, chroma: 0.06, hue: 140)]
        let shares: [Float] = [0.8, 0.1, 0.1]
        let lively = LivelyPaint.mix(greens, shares: shares, space: .sRGB, minDistance: 0.04)
        let rich = LivelyPaint.mix(greens, shares: shares, space: .sRGB, minDistance: 0.04, strength: .rich)
        // The background is lively paint's; the small shades get more chroma, and the light one
        // turns further toward yellow.
        #expect(ColorScience.distance(rich[0].oklab, lively[0].oklab) < 0.0005)
        #expect(LivelyPaintTests.chroma(rich[1]) > LivelyPaintTests.chroma(lively[1]))
        #expect(LivelyPaintTests.hue(rich[1]) < LivelyPaintTests.hue(lively[1]) - 2)
        // The strength left out is lively paint's, to the bit.
        #expect(LivelyPaint.mix(greens, shares: shares, space: .sRGB, minDistance: 0.04, strength: .lively) == lively)
    }

    @Test func richTemplateWithoutAFaceKeepsTheRegions() throws {
        let image = TestScenes.colorful()
        let photo = try TemplateGenerator(settings: GenerationSettings(colorCount: 12)).generate(from: image, cancel: .none)
        let rich = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .rich))
            .generate(from: image, cancel: .none)
        #expect(rich.template.regions == photo.template.regions)
        #expect(rich.template.edges == photo.template.edges)
        #expect(rich.template.palette.count == photo.template.palette.count)
        #expect(rich.template.palette != photo.template.palette)
        #expect(rich.template.validate().isValid)
        let again = try TemplateGenerator(settings: GenerationSettings(colorCount: 12, paintMix: .rich))
            .generate(from: image, cancel: .none)
        #expect(again.template.encoded() == rich.template.encoded())
        let coded = try JSONEncoder().encode(GenerationSettings(paintMix: .rich))
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: coded).paintMix == .rich)
    }
}
