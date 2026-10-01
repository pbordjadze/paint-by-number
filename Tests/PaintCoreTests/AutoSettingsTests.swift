import Foundation
import Testing
@testable import PaintCore

@Suite("Auto settings")
struct AutoSettingsTests {

    // MARK: - Fixtures

    /// 400 × 266 images (under the draft size, so analysis sees them enlarged 1.5× exactly as
    /// the create flow's drafts are).
    static let width = 400, height = 266

    static func image(_ color: (Int, Int) -> SIMD3<Float>) -> RGBAImage {
        var image = RGBAImage(width: width, height: height, fill: SIMD4(0, 0, 0, 255))
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x, y)
                image[x, y] = SIMD4(UInt8(min(max(c.x, 0), 255)), UInt8(min(max(c.y, 0), 255)), UInt8(min(max(c.z, 0), 255)), 255)
            }
        }
        return image
    }

    static let flat = image { _, _ in SIMD3(120, 140, 160) }
    /// A sky-like lightness ramp across the frame.
    static let ramp = image { x, _ in
        let t = Float(x) / Float(width - 1)
        return SIMD3(70 + 130 * t, 110 + 110 * t, 190 + 50 * t)
    }
    static let checkerboard = image { x, y in (x / 2 + y / 2) % 2 == 0 ? SIMD3(60, 110, 50) : SIMD3(150, 190, 120) }
    static let rectangle = image { x, y in
        x > 100 && x < 300 && y > 70 && y < 200 ? SIMD3(200, 40, 40) : SIMD3(230, 230, 220)
    }
    static func noisy(_ amplitude: Float, seed: UInt64 = 3) -> RGBAImage {
        var rng = SplitMix64(seed: seed)
        return image { _, _ in
            // Sum of four uniforms: close enough to Gaussian.
            var n: Float = 0
            for _ in 0..<4 { n += rng.nextFloat() - 0.5 }
            return SIMD3(repeating: 128 + amplitude * n)
        }
    }

    static func analyze(_ image: RGBAImage, importance: Grid<Float>? = nil, hints: SubjectHints? = nil) throws -> PhotoAnalysis {
        try AutoSettings.analyze(image, importance: importance, hints: hints, cancel: .none)
    }

    static func analysis(
        curve: [Float] = [0.06, 0.05, 0.044, 0.036, 0.031, 0.026, 0.023], chromatic: Float = 0.6, spread: Float = 0.02,
        structure: Float = 0.05, texture: Float = 0.1, smooth: Float = 0.1, noise: Float = 0.001, subject: Float = 0.3,
        faces: Float = 0, source: Int = 4000
    ) -> PhotoAnalysis {
        PhotoAnalysis(
            sourceWidth: source, sourceHeight: source * 3 / 4, paletteCurve: curve, chromaticFraction: chromatic,
            chromaSpread: spread, structureDensity: structure, textureFraction: texture, smoothFraction: smooth, noise: noise,
            subjectCoverage: subject, importanceEntropy: 0.9, faceCoverage: faces, animalCoverage: 0, labels: [:])
    }

    static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func inside(_ settings: GenerationSettings, _ preference: PaintingLength) -> Bool {
        preference.colorBand.contains(settings.colorCount) && preference.detailBand.contains(settings.detail)
            && AutoSettings.smoothnessBand.contains(settings.smoothness)
    }

    // MARK: - Analysis

    @Test func flatImageHasAFlatCurveAndNoRampsOrTexture() throws {
        let a = try Self.analyze(Self.flat)
        #expect(a.paletteCurve.count == AutoSettings.paletteCurveKs.count)
        #expect(a.paletteCurve.allSatisfy { $0 < 0.002 })
        #expect(a.smoothFraction == 0)
        #expect(a.textureFraction == 0)
        #expect(a.structureDensity == 0)
        #expect(a.noise < 0.001)
        #expect(a.sourceWidth == Self.width && a.sourceHeight == Self.height)
    }

    @Test func gentleRampIsSmooth() throws {
        let a = try Self.analyze(Self.ramp)
        #expect(a.smoothFraction > 0.8)
        #expect(a.textureFraction == 0)
        // A ramp needs many paints: the curve keeps falling.
        #expect(a.paletteCurve[0] > a.paletteCurve[a.paletteCurve.count - 1] + 0.01)
    }

    @Test func checkerboardIsTextureAndRectangleIsStructure() throws {
        let checker = try Self.analyze(Self.checkerboard)
        let rect = try Self.analyze(Self.rectangle)
        #expect(checker.textureFraction > 0.8)
        #expect(rect.textureFraction < 0.05)
        #expect(rect.structureDensity > 2 * checker.structureDensity)
        #expect(rect.structureDensity > 0.01 && checker.structureDensity < 0.05)
        #expect(checker.smoothFraction < 0.05 && rect.smoothFraction < 0.05)
    }

    @Test func noiseRaisesNoise() throws {
        let clean = try Self.analyze(Self.flat)
        let light = try Self.analyze(Self.noisy(6))
        let heavy = try Self.analyze(Self.noisy(18))
        #expect(light.noise > clean.noise)
        #expect(heavy.noise > light.noise)
    }

    @Test func hotspotImportanceLowersEntropy() throws {
        let disc = Self.image { x, y in
            let dx = Float(x - Self.width / 2), dy = Float(y - Self.height / 2)
            return dx * dx + dy * dy < 60 * 60 ? SIMD3(250, 240, 200) : SIMD3(40, 50, 60)
        }
        let flatMap = Grid<Float>(width: 40, height: 27, repeating: 0.5)
        var hotspot = Grid<Float>(width: 40, height: 27, repeating: 0)
        for y in 9..<18 { for x in 14..<26 { hotspot[x, y] = 1 } }
        let even = try Self.analyze(disc, importance: flatMap)
        let focused = try Self.analyze(disc, importance: hotspot)
        #expect(even.importanceEntropy > 0.99)
        #expect(focused.importanceEntropy < even.importanceEntropy - 0.2)
        #expect(focused.subjectCoverage > 0.05 && even.subjectCoverage == 0)
    }

    @Test func hintsAreCopiedClampedAndQuantized() throws {
        let hints = SubjectHints(
            faces: [NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3), NormalizedRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5)],
            animals: [NormalizedRect(x: -1, y: -1, width: 5, height: 5)],
            labels: ["portrait": 0.81234])
        let a = try Self.analyze(Self.flat, hints: hints)
        #expect(a.faceCoverage == 0.07)  // 0.06 + the 0.01 inside the frame
        #expect(a.animalCoverage == 1)
        #expect(a.labels == ["portrait": 0.812])
        let none = try Self.analyze(Self.flat)
        #expect(none.faceCoverage == 0 && none.animalCoverage == 0 && none.labels.isEmpty)
    }

    @Test func featuresAreQuantized() throws {
        let a = try Self.analyze(SegmentationTests.colorful(width: 300, height: 200))
        let values = a.paletteCurve + [a.chromaticFraction, a.chromaSpread, a.structureDensity, a.textureFraction,
                                       a.smoothFraction, a.noise, a.subjectCoverage, a.importanceEntropy]
        for v in values { #expect(v == (v * 1000).rounded() / 1000) }
    }

    // MARK: - Candidates

    @Test func monochromeGetsFewerColorsThanColorful() throws {
        let colorful = SegmentationTests.colorful(width: 300, height: 200)
        var gray = colorful
        for i in 0..<(gray.width * gray.height) {
            let l = (UInt32(gray.pixels[i * 4]) * 3 + UInt32(gray.pixels[i * 4 + 1]) * 6 + UInt32(gray.pixels[i * 4 + 2])) / 10
            for c in 0..<3 { gray.pixels[i * 4 + c] = UInt8(l) }
        }
        let a = try Self.analyze(colorful), b = try Self.analyze(gray)
        #expect(b.chromaticFraction < AutoSettings.monochromeFraction)
        for preference in PaintingLength.allCases {
            let colors = AutoSettings.candidates(for: a, preference: preference, maxCandidates: 1)[0].settings.colorCount
            let grays = AutoSettings.candidates(for: b, preference: preference, maxCandidates: 1)[0].settings.colorCount
            #expect(grays < colors, "\(preference)")
        }
        // The same rule on otherwise equal features.
        let mono = AutoSettings.center(for: Self.analysis(chromatic: 0.05, spread: 0.01), preference: .detailed)
        let vivid = AutoSettings.center(for: Self.analysis(chromatic: 0.8, spread: 0.09), preference: .detailed)
        #expect(mono.colorCount < vivid.colorCount)
    }

    @Test func longerPaintingsCenterHigher() {
        for a in [Self.analysis(), Self.analysis(texture: 0.5, source: 600), Self.analysis(subject: 0.8)] {
            let centers = PaintingLength.allCases.map { AutoSettings.center(for: a, preference: $0) }
            #expect(centers[0].detail < centers[1].detail && centers[1].detail < centers[2].detail)
            #expect(centers[0].colorCount <= centers[1].colorCount && centers[1].colorCount <= centers[2].colorCount)
        }
        // Where the photo's own color count lies outside a band, the bands order the colors.
        let rich = Self.analysis(curve: [0.2, 0.18, 0.16, 0.13, 0.11, 0.08, 0.06])
        let colors = PaintingLength.allCases.map { AutoSettings.center(for: rich, preference: $0).colorCount }
        #expect(colors[0] < colors[1] && colors[1] < colors[2])
    }

    @Test func candidatesStartAtTheCenterStayInsideTheBandsAndRespectTheLimit() {
        let analyses = [Self.analysis(), Self.analysis(curve: [0.02, 0.019, 0.018, 0.018, 0.017, 0.017, 0.017]),
                        Self.analysis(curve: [0.3, 0.25, 0.2, 0.15, 0.12, 0.09, 0.07], texture: 0.6, noise: 0.02)]
        for a in analyses {
            for preference in PaintingLength.allCases {
                let center = AutoSettings.center(for: a, preference: preference)
                for limit in 0...10 {
                    let list = AutoSettings.candidates(for: a, preference: preference, maxCandidates: limit)
                    #expect(list.count <= max(1, limit) && !list.isEmpty)
                    #expect(list[0].settings == center)
                    #expect(Set(list.map(\.settings)).count == list.count)
                    #expect(list.allSatisfy { Self.inside($0.settings, preference) && $0.score == nil })
                    // Single-axis moves before diagonals; smoothness is one value per photo.
                    let moves = list.map {
                        ($0.settings.colorCount != center.colorCount ? 1 : 0) + ($0.settings.detail != center.detail ? 1 : 0)
                    }
                    #expect(moves == moves.sorted() && moves.filter { $0 == 0 }.count == 1)
                    #expect(list.allSatisfy { $0.settings.smoothness == center.smoothness })
                }
                #expect(AutoSettings.candidates(for: a, preference: preference, maxCandidates: 5).count == 5)
            }
        }
    }

    @Test func candidateRuleIsDeterministicAndReadsTheFeatures() throws {
        let a = Self.analysis()
        let first = AutoSettings.candidates(for: a, preference: .relaxed, maxCandidates: 9).map(\.settings)
        #expect(first == AutoSettings.candidates(for: a, preference: .relaxed, maxCandidates: 9).map(\.settings))
        let base = AutoSettings.center(for: a, preference: .relaxed)
        #expect(base.colorCount % 2 == 0)
        #expect(AutoSettings.center(for: Self.analysis(faces: 0.2), preference: .relaxed).colorCount > base.colorCount)
        #expect(AutoSettings.center(for: Self.analysis(smooth: 0.6), preference: .relaxed).colorCount > base.colorCount)
        #expect(AutoSettings.center(for: Self.analysis(subject: 0.7), preference: .relaxed).detail > base.detail)
        #expect(AutoSettings.center(for: Self.analysis(texture: 0.5), preference: .relaxed).detail < base.detail)
        #expect(AutoSettings.center(for: Self.analysis(source: 640), preference: .relaxed).detail < base.detail)
        #expect(AutoSettings.center(for: Self.analysis(texture: 0.5), preference: .relaxed).smoothness > base.smoothness)
        #expect(AutoSettings.center(for: Self.analysis(noise: 0.01), preference: .relaxed).smoothness > base.smoothness)
        #expect(AutoSettings.center(for: Self.analysis(structure: 0.3), preference: .relaxed).smoothness < base.smoothness)
    }

    @Test func kneeFindsWhereAnotherPaintStopsPaying() {
        // Gains per paint: 0.004, 0.002, 0.001, 0.0005, 0.0002, … → crosses 0.0004 between the
        // midpoints 28 and 40.
        let curve: [Float] = [0.1, 0.084, 0.076, 0.068, 0.064, 0.0608, 0.0592]
        let knee = AutoSettings.knee(curve)
        #expect(knee > 28 && knee < 40)
        #expect(AutoSettings.knee([0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]) == 8)
        #expect(AutoSettings.knee([0.5, 0.45, 0.4, 0.3, 0.2, 0.1, 0.05]) == 64)
    }

    // MARK: - Scoring

    @Test func paintingTimeOutsideTheBandCostsAtEqualFidelity() throws {
        let image = SegmentationTests.scene(width: 240, height: 160)
        let output = try TemplateGenerator().generate(from: image, cancel: .none)
        let t = output.template
        let working = Resample.area(image, width: t.width, height: t.height)
        let importance = AutoSettings.importance(for: working, map: nil)
        // A canvas on which this many regions take about an hour (inside Relaxed's band), and
        // one so large its estimate is far above the band.
        let regions = Double(t.regions.count)
        func canvas(seconds: Double) -> (width: Int, height: Int) {
            let ratio = pow(seconds / PaintingTime.estimate(regionCount: t.regions.count), 1 / AutoSettings.regionAreaExponent)
            return (Int((Double(t.width) * ratio.squareRoot()).rounded()), Int((Double(t.height) * ratio.squareRoot()).rounded()))
        }
        let inside = AutoSettings.score(output, working: working, importance: importance, preference: .relaxed,
                                        fullSize: canvas(seconds: 3600))
        let above = AutoSettings.score(output, working: working, importance: importance, preference: .relaxed,
                                       fullSize: canvas(seconds: 6 * 3600))
        #expect(regions > 0)
        #expect(PaintingLength.relaxed.timeBand.contains(inside.estimatedSeconds))
        #expect(inside.bandPenalty == 0)
        #expect(above.estimatedSeconds > PaintingLength.relaxed.timeBand.upperBound)
        #expect(above.bandPenalty > 0)
        #expect(above.fidelity == inside.fidelity && above.regions == inside.regions)
        #expect(above.total > inside.total)
        // The same template is too small a painting for Detailed.
        let detailed = AutoSettings.score(output, working: working, importance: importance, preference: .detailed,
                                          fullSize: canvas(seconds: 3600))
        #expect(detailed.bandPenalty > 0 && detailed.total > inside.total)
    }

    @Test func scoreMeasuresTheTemplate() throws {
        let image = SegmentationTests.scene(width: 240, height: 160)
        let output = try TemplateGenerator().generate(from: image, cancel: .none)
        let t = output.template
        let working = Resample.area(image, width: t.width, height: t.height)
        let s = AutoSettings.score(output, working: working, importance: AutoSettings.importance(for: working, map: nil),
                                   preference: .relaxed)
        #expect(s.regions == t.regions.count)
        #expect(s.tinyRegions == t.regions.filter { $0.inscribedRadius < 3 }.count)
        #expect(s.fidelity > 0 && s.fidelity < 0.1)
        #expect(s.fidelityP95 >= s.fidelity)
        #expect(s.minLabelRoom >= LabelSizing.minimumRadius - 1e-3)
        #expect(s.estimatedSeconds == PaintingTime.estimate(regionCount: t.regions.count))
        #expect(s.total >= s.fidelity + 0.5 * s.fidelityP95)
    }

    @Test func paintingTimeEstimate() {
        #expect(PaintingTime.estimate(regionCount: 1200) == 3600)
        #expect(PaintingTime.estimate(regionCount: 0) == 0)
    }

    /// A segmentation of vertical stripes, each with its mean colour as paint.
    static func stripes(_ image: RGBAImage, width stripe: Int) -> Segmentation {
        let w = image.width, h = image.height, count = (w + stripe - 1) / stripe
        var labels = RegionMap(width: w, height: h, repeating: 0)
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        let lab = ColorScience.okLabImage(from: image)
        for y in 0..<h {
            for x in 0..<w {
                labels[x, y] = UInt32(x / stripe)
                let v = lab[x, y]
                sums[x / stripe] += SIMD3(v.x, v.y, v.z)
            }
        }
        let palette = (0..<count).map { r in
            PaletteColor(oklab: sums[r] / Float(h * min(stripe, w - r * stripe)), space: .sRGB)
        }
        return Segmentation(labels: labels, regionColor: (0..<count).map(UInt32.init), palette: palette, colorSpace: .sRGB)
    }

    @Test func bandRingsCountsARampsRingsNotHardContours() {
        let ramp = Self.image { x, _ in SIMD3(repeating: 40 + 180 * Float(x) / Float(Self.width - 1)) }
        let bars = Self.image { x, _ in SIMD3(repeating: 40 + 180 * Float(x / 40) / Float(Self.width / 40 - 1)) }
        let rampRings = BandRings.count(Self.stripes(ramp, width: 40), working: ramp)
        let barRings = BandRings.count(Self.stripes(bars, width: 40), working: bars)
        #expect(rampRings == 10)
        #expect(barRings == 0)
        // One region, or a working image of another size, has no rings.
        #expect(BandRings.count(Self.stripes(ramp, width: Self.width), working: ramp) == 0)
        #expect(BandRings.count(Self.stripes(ramp, width: 40), working: Self.flat.cropped(width: 10)) == 0)
    }

    // MARK: - Choosing

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func increment() { lock.withLock { value += 1 } }
    }

    @Test func choosePicksAWinnerInsideTheBandsAfterOneFirstDraft() throws {
        let image = SegmentationTests.scene(width: 360, height: 240)
        for preference in PaintingLength.allCases {
            let drafts = Counter()
            let decision = try AutoSettings.choose(
                image: image, importance: nil, hints: nil, preference: preference, maxCandidates: 5, cancel: .none,
                firstDraft: { output in
                    #expect(output.template.regions.count > 0)
                    drafts.increment()
                })
            #expect(drafts.count == 1)
            #expect(decision.preference == preference)
            #expect(decision.candidates.count == 5)
            #expect(decision.candidates.allSatisfy { $0.score != nil })
            #expect(decision.candidates.indices.contains(decision.winner))
            #expect(Self.inside(decision.settings, preference))
            let best = decision.candidates.compactMap { $0.score?.total }.min()!
            #expect(decision.candidates[decision.winner].score!.total <= best + AutoSettings.tieTolerance)
        }
    }

    @Test func chooseIsByteIdenticalAcrossRuns() throws {
        let image = SegmentationTests.colorful(width: 300, height: 200)
        let hints = SubjectHints(faces: [NormalizedRect(x: 0.4, y: 0.2, width: 0.3, height: 0.4)], labels: ["flower": 0.5])
        let runs = try (0..<2).map { _ in
            try Self.json(AutoSettings.choose(
                image: image, importance: nil, hints: hints, preference: .relaxed, maxCandidates: 5, cancel: .none,
                firstDraft: nil))
        }
        #expect(runs[0] == runs[1])
    }

    @Test func chooseStopsWhenCancelled() throws {
        let image = SegmentationTests.scene(width: 360, height: 240)
        // Cancelled during the remaining candidates: the first draft still arrived once.
        let drafts = Counter()
        #expect(throws: CancellationError.self) {
            try AutoSettings.choose(
                image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 5,
                cancel: CancellationCheck { drafts.count > 0 }, firstDraft: { _ in drafts.increment() })
        }
        #expect(drafts.count == 1)
        // Cancelled from the start: nothing runs.
        let none = Counter()
        #expect(throws: CancellationError.self) {
            try AutoSettings.choose(
                image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 5,
                cancel: CancellationCheck { true }, firstDraft: { _ in none.increment() })
        }
        #expect(none.count == 0)
        // Cancelled after a few checks, wherever that lands.
        for after in [3, 20, 60] {
            let checks = Counter()
            do {
                _ = try AutoSettings.choose(
                    image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 5,
                    cancel: CancellationCheck {
                        checks.increment()
                        return checks.count > after
                    }, firstDraft: nil)
                Issue.record("not cancelled after \(after) checks")
            } catch is CancellationError {}
        }
    }

    @Test func draftImageMatchesTheCreateFlow() {
        let big = RGBAImage(width: 1536, height: 1024, fill: SIMD4(10, 20, 30, 255))
        let draft = AutoSettings.draftImage(from: big)
        #expect(draft.width == 426 && draft.height == 284)
        #expect(AutoSettings.draftImage(from: Self.flat) == Self.flat)
    }

    // MARK: - Fixture

    /// `Fixtures/auto-parrots.json` pins the decision for the bundled parrots photo at Relaxed
    /// with 5 candidates and no importance map; `auto-parrots-draft.ppm` is that photo
    /// (decoded by Pillow) at the draft size. Regenerate both, only when a change to Auto or
    /// the pipeline is meant to move the decision, with the release pbn:
    ///
    ///     python3 -c "from PIL import Image; Image.open('App/PaintByNumber/Resources/Samples/parrots.jpg').convert('RGB').save('/tmp/parrots.ppm')"
    ///     .build/release/pbn suggest /tmp/parrots.ppm --length relaxed --candidates 5 --out /tmp/auto-parrots
    ///     cp /tmp/auto-parrots/decision.json Tests/PaintCoreTests/Fixtures/auto-parrots.json
    ///     cp /tmp/auto-parrots/draft.ppm Tests/PaintCoreTests/Fixtures/auto-parrots-draft.ppm
    ///
    /// Settings, winner and analysis must match exactly; scores to 1e-4, since libm differs
    /// between platforms.
    @Test func parrotsDecisionIsPinned() throws {
        func fixture(_ name: String) throws -> Data {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
            return try Data(contentsOf: url)
        }
        let pinned = try JSONDecoder().decode(AutoDecision.self, from: fixture("auto-parrots.json"))
        let draft = try Netpbm.read(fixture("auto-parrots-draft.ppm"))
        let decision = try AutoSettings.choose(
            image: draft, sourceSize: (pinned.analysis.sourceWidth, pinned.analysis.sourceHeight), importance: nil,
            hints: nil, preference: .relaxed, maxCandidates: 5, cancel: .none, firstDraft: nil)
        #expect(decision.analysis == pinned.analysis)
        #expect(decision.preference == pinned.preference)
        #expect(decision.winner == pinned.winner)
        #expect(decision.candidates.map(\.settings) == pinned.candidates.map(\.settings))
        for (a, b) in zip(decision.candidates, pinned.candidates) {
            let s = try #require(a.score), p = try #require(b.score)
            #expect(s.regions == p.regions && s.tinyRegions == p.tinyRegions && s.bandRings == p.bandRings)
            for (x, y) in [(s.fidelity, p.fidelity), (s.fidelityP95, p.fidelityP95), (s.minLabelRoom, p.minLabelRoom),
                           (s.bandPenalty, p.bandPenalty), (s.total, p.total)] {
                #expect(abs(x - y) <= 1e-4)
            }
            #expect(s.estimatedSeconds == p.estimatedSeconds)
        }
    }
}

private extension RGBAImage {
    func cropped(width w: Int) -> RGBAImage {
        var out = RGBAImage(width: w, height: height, fill: SIMD4(0, 0, 0, 255))
        for y in 0..<height { for x in 0..<w { out[x, y] = self[x, y] } }
        return out
    }
}
