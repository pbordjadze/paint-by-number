import Foundation
import Testing
@testable import PaintCore

@Suite("Segmentation")
struct SegmentationTests {

    // MARK: - Invariants

    @Test(arguments: [Float(0), 0.5, 1])
    func invariantsAcrossDetail(detail: Float) throws {
        let settings = GenerationSettings(colorCount: 16, detail: detail, smoothness: 0.5)
        let s = try TestScenes.segment(TestScenes.scene(), settings: settings)
        TestScenes.checkInvariants(s, settings: settings)
        #expect(s.regionCount > 1)
        #expect(s.palette.count > 3 && s.palette.count <= 16)
    }

    @Test(arguments: [Float(0), 1])
    func invariantsAcrossSmoothness(smoothness: Float) throws {
        let settings = GenerationSettings(colorCount: 24, detail: 0.5, smoothness: smoothness)
        TestScenes.checkInvariants(try TestScenes.segment(TestScenes.scene(seed: 3), settings: settings), settings: settings)
    }

    @Test(arguments: [6, 24, 60, 150])
    func paletteSpacing(colors: Int) throws {
        let settings = GenerationSettings(colorCount: colors, detail: 0.5)
        let image = TestScenes.colorful()
        let p = SegmentationParameters(settings: settings, width: image.width, height: image.height)
        #expect(p.minPaletteDistance >= SegmentationParameters.jnd)
        #expect(p.minPaletteDistance == (colors <= 24 ? 0.04 : max(0.02, 0.04 * (24 / Float(colors)).squareRoot())))
        let s = try TestScenes.segment(image, settings: settings)
        TestScenes.checkInvariants(s, settings: settings)
        #expect(s.palette.count <= colors)
    }

    @Test func minPaletteDistanceNeverBelowJND() {
        for n in GenerationSettings.colorCountRange {
            let p = SegmentationParameters(settings: GenerationSettings(colorCount: n), width: 100, height: 100)
            #expect(p.minPaletteDistance >= SegmentationParameters.jnd)
            if n >= 96 { #expect(p.minPaletteDistance == SegmentationParameters.jnd) }
        }
    }

    @Test func highColorScene() throws {
        let settings = GenerationSettings(colorCount: 150, detail: 1)
        let image = TestScenes.colorful()
        let s = try TestScenes.segment(image, settings: settings)
        TestScenes.checkInvariants(s, settings: settings)
        #expect(s.palette.count >= 100)
        #expect(s.regionColor.contains { $0 >= 99 })
        let again = try TestScenes.segment(image, settings: settings)
        #expect(again.labels == s.labels)
        #expect(again.regionColor == s.regionColor)
        #expect(again.palette == s.palette)
    }

    @Test func bandFusingKeepsThePaintBudget() throws {
        // A smooth two-axis gradient above the colourful tiles: fusing the gradient's bands
        // frees paints, which are re-spent, so a 150-colour request delivers about as many
        // paints as without the band stage.
        var image = TestScenes.colorful(width: 480, height: 320)
        for y in 0..<160 {
            for x in 0..<480 {
                let t = Float(x) / 480, u = Float(y) / 320
                image[x, y] = SIMD4(UInt8(40 + 200 * t), UInt8(60 + 150 * u), UInt8(200 - 120 * t * u), 255)
            }
        }
        let settings = GenerationSettings(colorCount: 150, detail: 1)
        let p = SegmentationParameters(settings: settings, width: image.width, height: image.height)
        var unfused = p
        unfused.bandNearTolerance = 0
        unfused.bandNearImportantTolerance = 0
        unfused.bandTolerance = 0
        func segment(_ p: SegmentationParameters) throws -> Segmentation {
            try Segmenter.segment(image, importance: nil, parameters: p, cancel: .none, clock: StageClock(), progress: { _ in })
                .segmentation
        }
        let fused = try segment(p), plain = try segment(unfused)
        TestScenes.checkInvariants(fused, settings: settings)
        #expect(fused.regionCount < plain.regionCount)
        #expect(fused.palette.count + plain.palette.count / 25 >= plain.palette.count)
    }

    @Test func freedPaintsAreRespent() throws {
        // Two separate regions share paint 1 although their colours are far apart, and paint 2
        // is unused (as after band fusing): the refit gives one of them the free paint, so
        // both end up close to their own colour and no paint is lost.
        let w = 60, h = 20
        var classes = [UInt32](repeating: 0, count: w * h)
        var lab = [SIMD4<Float>](repeating: .zero, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let band = x / 20
                classes[y * w + x] = band == 1 ? 0 : 1
                lab[y * w + x] = SIMD4([Float(0.15), 0.5, 0.95][band], 0, 0, 0)
            }
        }
        var regions = RegionRuns(classes: classes, width: w, height: h)
        var adjacency = RegionAdjacency(regions)
        let palette = try PaletteRefiner.refine(
            classes: &classes, regions: &regions, adjacency: &adjacency, lab: lab,
            importance: [Float](repeating: 0.5, count: w * h), labelling: classes,
            palette: [SIMD3(0.5, 0, 0), SIMD3(0.55, 0, 0), SIMD3(0.3, 0, 0)], minDistance: 0.04, chromaScale: 1.6,
            iterations: 3)
        #expect(palette.count == 3)
        for (x, l) in [(10, Float(0.15)), (30, 0.5), (50, 0.95)] {
            #expect(abs(palette[Int(classes[10 * w + x])].x - l) < 0.01)
        }
    }

    /// `GenerationSettings.minPaletteDistance` is the floor tools/regression.py holds templates
    /// to, so it must be the one segmentation enforces.
    @Test(arguments: [12, 24, 150])
    func paletteHonoursThePublishedFloor(colorCount: Int) throws {
        let settings = GenerationSettings(colorCount: colorCount, detail: 1)
        #expect(SegmentationParameters(settings: settings, width: 160, height: 120).minPaletteDistance
            == settings.minPaletteDistance)
        let s = try TestScenes.segment(TestScenes.scene(seed: 5), settings: settings)
        TestScenes.checkInvariants(s, settings: settings, checksRoom: false)
    }

    @Test func publishedPaletteFloor() {
        #expect(GenerationSettings(colorCount: 12).minPaletteDistance == 0.04)
        #expect(GenerationSettings(colorCount: 24).minPaletteDistance == 0.04)
        // 150 colours would pack paints 0.016 apart; the floor holds them one JND (0.02) apart.
        #expect(GenerationSettings(colorCount: 150).minPaletteDistance == SegmentationParameters.jnd)
        // Clamped like every other setting.
        #expect(GenerationSettings(colorCount: 1000).minPaletteDistance
            == GenerationSettings(colorCount: 150).minPaletteDistance)
    }

    @Test func lowDetailHasLargerRegions() throws {
        // Small distinct spots (9 px, white on grass) in an unimportant area: the fine
        // regime keeps them, the bold one folds them into the grass.
        var image = TestScenes.scene(width: 400, height: 300)
        for k in 0..<10 {
            let x0 = 40 + 33 * k, y0 = 266
            for y in y0..<(y0 + 9) {
                for x in x0..<(x0 + 9) { image[x, y] = SIMD4(250, 250, 250, 255) }
            }
        }
        let nowhere = Grid<Float>(width: 1, height: 1, repeating: 0)
        let boldSettings = GenerationSettings(colorCount: 16, detail: 0)
        let bold = try TestScenes.segment(image, settings: boldSettings, importance: nowhere)
        let fine = try TestScenes.segment(image, settings: GenerationSettings(colorCount: 16, detail: 1), importance: nowhere)
        TestScenes.checkInvariants(bold, settings: boldSettings)
        #expect(bold.regionCount + 8 <= fine.regionCount)
        // On the plain scene (no small features to drop) the detail slider must at least
        // not run backwards beyond a region or two of noise.
        let plain = TestScenes.scene(width: 200, height: 150)
        let plainBold = try TestScenes.segment(plain, settings: boldSettings)
        let plainFine = try TestScenes.segment(plain, settings: GenerationSettings(colorCount: 16, detail: 1))
        #expect(plainBold.regionCount <= plainFine.regionCount + 2)
    }

    @Test func importanceIsHonoured() throws {
        let image = TestScenes.scene(width: 200, height: 150, seed: 11)
        var important = Grid<Float>(width: 50, height: 40, repeating: 0.25)
        for y in 10..<30 { for x in 10..<40 { important[x, y] = 1 } }
        let s = try TestScenes.segment(image, importance: important)
        TestScenes.checkInvariants(s, settings: GenerationSettings())
        // Importance maps of any size are accepted, including degenerate ones.
        _ = try TestScenes.segment(image, importance: Grid(width: 0, height: 0, repeating: 0))
        _ = try TestScenes.segment(image, importance: Grid(width: 1, height: 1, repeating: 2))
    }

    @Test func salientSmallColorGetsAPaint() throws {
        // A small, strongly colored disc on a large gradient must keep its own paint.
        var image = RGBAImage(width: 180, height: 120, fill: SIMD4(0, 0, 0, 255))
        for y in 0..<120 {
            for x in 0..<180 {
                let t = Float(x) / 180
                image[x, y] = SIMD4(UInt8(60 + 150 * t), UInt8(70 + 140 * t), UInt8(80 + 120 * t), 255)
                let dx = x - 120, dy = y - 60
                if dx * dx + dy * dy < 36 { image[x, y] = SIMD4(220, 20, 60, 255) }
            }
        }
        let settings = GenerationSettings(colorCount: 12)
        let s = try TestScenes.segment(image, settings: settings)
        TestScenes.checkInvariants(s, settings: settings)
        let red = ColorScience.encodedToOKLab(SIMD3(220, 20, 60) / 255, space: .sRGB)
        let center = s.palette[Int(s.regionColor[Int(s.labels[120, 60])])].oklab
        #expect(ColorScience.distance(center, red) < 0.08)
    }

    @Test func deterministic() throws {
        let image = TestScenes.scene(seed: 5)
        let a = try TestScenes.segment(image)
        let b = try TestScenes.segment(image)
        #expect(a.labels == b.labels)
        #expect(a.regionColor == b.regionColor)
        #expect(a.palette == b.palette)
    }

    @Test func neutralsComeLastLightToDark() throws {
        let s = try TestScenes.segment(TestScenes.scene())
        let lch = s.palette.map { ColorScience.lch($0.oklab) }
        let firstNeutral = try #require(lch.firstIndex(where: { $0.y < PaletteOrdering.neutralChroma }))
        #expect(lch[firstNeutral...].allSatisfy { $0.y < PaletteOrdering.neutralChroma })
        let lightness = lch[firstNeutral...].map(\.x)
        #expect(lightness == lightness.sorted(by: >))
    }

    // MARK: - Edge cases

    @Test(arguments: [(1, 1), (3, 2), (2, 7), (1, 40)])
    func tinyImages(size: (Int, Int)) throws {
        var rng = SplitMix64(seed: 9)
        var image = RGBAImage(width: size.0, height: size.1, fill: SIMD4(0, 0, 0, 255))
        for y in 0..<size.1 {
            for x in 0..<size.0 {
                image[x, y] = SIMD4(UInt8(rng.next() & 255), UInt8(rng.next() & 255), UInt8(rng.next() & 255), 255)
            }
        }
        let s = try TestScenes.segment(image)
        TestScenes.checkInvariants(s, settings: GenerationSettings(), checksRoom: false)
        #expect(s.width == size.0 && s.height == size.1)
    }

    @Test func emptyImage() throws {
        let s = try TestScenes.segment(RGBAImage(width: 0, height: 0, pixels: []))
        #expect(s.regionCount == 0)
        #expect(s.palette.isEmpty)
    }

    @Test func uniformImage() throws {
        let s = try TestScenes.segment(RGBAImage(width: 64, height: 48, fill: SIMD4(30, 120, 200, 255)))
        TestScenes.checkInvariants(s, settings: GenerationSettings(), checksRoom: false)
        #expect(s.regionCount == 1)
        #expect(s.palette.count == 1)
        let expected = ColorScience.encodedToOKLab(SIMD3(30, 120, 200) / 255, space: .sRGB)
        #expect(ColorScience.distance(s.palette[0].oklab, expected) < 0.01)
    }

    @Test func transparentPixelsBecomePaper() throws {
        let s = try TestScenes.segment(TestScenes.scene(alpha: true))
        TestScenes.checkInvariants(s, settings: GenerationSettings())
        // The fully transparent left quarter is painted white.
        let paint = s.palette[Int(s.regionColor[Int(s.labels[5, 60])])].oklab
        #expect(paint.x > 0.97 && ColorScience.lch(paint).y < 0.02)
    }

    @Test func displayP3Input() throws {
        var image = TestScenes.scene(seed: 2)
        image.colorSpace = .displayP3
        let s = try TestScenes.segment(image)
        #expect(s.colorSpace == .displayP3)
        TestScenes.checkInvariants(s, settings: GenerationSettings())
    }

    @Test func cancellation() {
        let cancelled = CancellationCheck { true }
        let image = TestScenes.scene()
        let p = SegmentationParameters(settings: GenerationSettings(), width: image.width, height: image.height)
        #expect(throws: CancellationError.self) {
            _ = try Segmenter.segment(
                image, importance: nil, parameters: p, cancel: cancelled, clock: StageClock(), progress: { _ in })
        }
    }

    @Test func progressIsMonotonic() throws {
        final class Recorder: @unchecked Sendable { var values: [Float] = [] }
        let recorder = Recorder()
        let image = TestScenes.scene()
        let p = SegmentationParameters(settings: GenerationSettings(), width: image.width, height: image.height)
        _ = try Segmenter.segment(
            image, importance: nil, parameters: p, cancel: .none, clock: StageClock(),
            progress: { recorder.values.append($0) })
        #expect(recorder.values == recorder.values.sorted())
        #expect(recorder.values.last == 1)
    }

    // MARK: - Building blocks

    @Test func runComponentsMatchPixelComponents() {
        var rng = SplitMix64(seed: 21)
        for (w, h, k) in [(1, 1, 1), (7, 1, 3), (1, 9, 2), (37, 23, 3), (64, 48, 5)] {
            let classes = (0..<(w * h)).map { _ in UInt32(rng.next() % UInt64(k)) }
            let reference = ConnectedComponents.label(Grid(width: w, height: h, storage: classes))
            let runs = RegionRuns(classes: classes, width: w, height: h)
            #expect(runs.labelMap() == reference.labels)
            #expect(runs.classOf == reference.classOf)
            #expect(runs.area == reference.area)
        }
    }

    @Test func inscribedDiscTestMatchesDistanceTransform() {
        var rng = SplitMix64(seed: 4)
        let w = 60, h = 45
        let classes = TestScenes.blobbyClasses(width: w, height: h, cell: 5, kinds: 3, rng: &rng)
        let regions = RegionRuns(classes: classes, width: w, height: h)
        let labels = regions.labelMap()
        let d = DistanceTransform.interiorDistance(labels: labels)
        var best = [Float](repeating: 0, count: regions.count)
        for i in 0..<d.count { best[Int(labels.storage[i])] = max(best[Int(labels.storage[i])], d.storage[i]) }
        for radius in [Float(0.5), 1, 1.5, 2, 2.75, 3.5, 4.2] {
            let wide = RegionSimplifier.hasInscribedDisc(regions, classes: classes, radius: radius)
            for r in 0..<regions.count { #expect(wide[r] == (best[r] >= radius)) }
        }
    }

    @Test func enforceLabelRoomUsesDigitCount() throws {
        // Paints 0–9 own wide stripes along the top; four equal discs sit on paint 12. Each
        // disc has room for one digit but not two. The disc showing "2" (paint 1) stays as it
        // is. The one showing "11" looks almost like paint 8 and takes it ("9"). The two
        // showing "12" merge into the background: one looks like it, the other like no paint
        // with a 1-digit number (recolouring it would change its colour visibly). The unused
        // paints are dropped.
        let w = 120, h = 60
        let p = SegmentationParameters(settings: GenerationSettings(colorCount: 13, detail: 0.5), width: w, height: h)
        let palette = (0..<12).map { SIMD3<Float>(0.3 + 0.05 * Float($0), 0.02 * Float($0 % 3), 0) } + [SIMD3(0.5, -0.1, 0.1)]
        let discRadius: Float = 3.2
        let discs: [(x: Int, paint: UInt32, color: SIMD3<Float>)] = [
            (15, 1, palette[1]), (45, 10, palette[8] + SIMD3(0.01, 0, 0)),
            (75, 11, palette[12]), (105, 11, SIMD3(0.9, 0.2, 0.2)),
        ]
        var classes = [UInt32](repeating: 12, count: w * h)
        var colors = [SIMD4<Float>](repeating: SIMD4(palette[12], 0), count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                if y < 12 {
                    classes[y * w + x] = UInt32(x / 12)
                    colors[y * w + x] = SIMD4(palette[x / 12], 0)
                }
                for disc in discs {
                    let dx = Float(x - disc.x), dy = Float(y - 40)
                    if dx * dx + dy * dy <= discRadius * discRadius {
                        classes[y * w + x] = disc.paint
                        colors[y * w + x] = SIMD4(disc.color, 0)
                    }
                }
            }
        }
        let d = DistanceTransform.interiorDistance(labels: RegionRuns(classes: classes, width: w, height: h).labelMap())
        let discBest = (12 * w..<(w * h)).filter { classes[$0] == 1 }.map { d.storage[$0] }.max() ?? 0
        #expect(discBest >= p.minRadius(digits: 1))
        #expect(discBest < p.minRadius(digits: 2))

        var regions = RegionRuns(classes: classes, width: w, height: h)
        var adjacency = RegionAdjacency(regions)
        let result = try RegionSimplifier.enforceLabelRoom(
            classes: &classes, regions: &regions, adjacency: &adjacency, colors: colors,
            areaScale: [Float](repeating: 1, count: w * h), palette: palette, parameters: p, cancel: .none)
        #expect(result.recolors == 1)
        #expect(result.merges == 2)
        #expect(result.kept == Array(0..<10) + [12])
        #expect(regions.count == 13)
        #expect(classes[40 * w + 15] == 1)
        #expect(classes[40 * w + 45] == 8)
        #expect(classes[40 * w + 75] == 10)
        #expect(classes[40 * w + 105] == 10)
        #expect(classes[40 * w + 2] == 10)
        let labels = regions.labelMap()
        for i in 0..<(w * h) { #expect(classes[i] == regions.classOf[Int(labels.storage[i])]) }
    }

    @Test func thinPartsArePeeled() {
        // A 1-px line of paint 1 across a field of paint 0 disappears; a thick bar stays.
        let w = 40, h = 30
        var classes = [UInt32](repeating: 0, count: w * h)
        for x in 5..<35 { classes[10 * w + x] = 1 }
        for y in 18..<24 { for x in 5..<35 { classes[y * w + x] = 2 } }
        let colors = [SIMD4<Float>](repeating: SIMD4(0.5, 0, 0, 0), count: w * h)
        let palette: [SIMD3<Float>] = [SIMD3(0.5, 0, 0), SIMD3(0.2, 0, 0), SIMD3(0.8, 0, 0)]
        _ = try! ThinPartRemoval.apply(
            classes: &classes, width: w, height: h, colors: colors, palette: palette, radiusSquared: 1, maxPasses: 4)
        #expect(!classes.contains(1))
        #expect(classes[20 * w + 20] == 2)
    }

    @Test func paletteOrderingGroupsHues() {
        func lab(_ l: Float, _ c: Float, _ hDeg: Float) -> SIMD3<Float> {
            let h = hDeg * .pi / 180
            return SIMD3(l, c * cos(h), c * sin(h))
        }
        let palette = [
            lab(0.5, 0.0, 0), lab(0.6, 0.15, 140), lab(0.7, 0.15, 25), lab(0.4, 0.15, 25),
            lab(0.9, 0.0, 0), lab(0.5, 0.15, 142), lab(0.6, 0.12, 260),
        ]
        let order = PaletteOrdering.order(palette)
        #expect(order == [2, 3, 1, 5, 6, 4, 0])
    }
}
