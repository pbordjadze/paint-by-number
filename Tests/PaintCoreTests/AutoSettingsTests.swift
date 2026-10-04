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
            subjectCoverage: subject, importanceEntropy: 0.9, meanImportance: 0.5, faceCoverage: faces, animalCoverage: 0)
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
        // The fallback map (no Vision) has a floor everywhere; the entropy reads what rises
        // above it, so a lone subject no longer rates as flat.
        let fallback = try Self.analyze(disc)
        #expect(fallback.importanceEntropy < 0.95)
        #expect(fallback.importanceEntropy > focused.importanceEntropy)
    }

    @Test func hintsAreCopiedClampedAndQuantized() throws {
        let hints = SubjectHints(
            faces: [NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3), NormalizedRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5)],
            animals: [NormalizedRect(x: -1, y: -1, width: 5, height: 5)])
        let a = try Self.analyze(Self.flat, hints: hints)
        #expect(a.faceCoverage == 0.07)  // 0.06 + the 0.01 inside the frame
        #expect(a.animalCoverage == 1)
        let none = try Self.analyze(Self.flat)
        #expect(none.faceCoverage == 0 && none.animalCoverage == 0)
    }

    @Test func hintsDecodeWithMissingLists() throws {
        let faces = try JSONDecoder().decode(SubjectHints.self, from: Data(#"{"faces": [{"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4}]}"#.utf8))
        #expect(faces == SubjectHints(faces: [NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)]))
        #expect(try JSONDecoder().decode(SubjectHints.self, from: Data("{}".utf8)) == SubjectHints())
        // Hints written when scene labels existed still decode: the key is ignored.
        #expect(try JSONDecoder().decode(SubjectHints.self, from: Data(#"{"labels": {"flower": 0.5}}"#.utf8)) == SubjectHints())
        let full = SubjectHints(animals: [NormalizedRect(x: 0, y: 0, width: 1, height: 1)])
        #expect(try JSONDecoder().decode(SubjectHints.self, from: Self.json(full)) == full)
    }

    @Test func featuresAreQuantized() throws {
        let a = try Self.analyze(TestScenes.colorful(width: 300, height: 200))
        let values = [a.chromaticFraction, a.chromaSpread, a.structureDensity, a.textureFraction, a.smoothFraction,
                      a.subjectCoverage, a.importanceEntropy]
        for v in values { #expect(v == (v * 1000).rounded() / 1000) }
        // The palette curve's slope and the noise level are read at 4 decimals.
        for v in a.paletteCurve + [a.noise] { #expect(v == (v * 10000).rounded() / 10000) }
    }

    // MARK: - Candidates

    @Test func monochromeGetsFewerColorsThanColorful() throws {
        let colorful = TestScenes.colorful(width: 300, height: 200)
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
        // The cut fades in: a photo with a few vivid parts loses fewer paints than a grey one,
        // and none once a seventh of it is chromatic.
        let colors = [0, 0.05, 0.1, 0.15, 0.3].map {
            AutoSettings.center(for: Self.analysis(chromatic: Float($0)), preference: .detailed).colorCount
        }
        #expect(colors == colors.sorted() && colors[0] < colors[2] && colors[2] < colors[3])
        #expect(colors[3] == colors[4])
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
        // Ramps get no extra paints without gradient-aware allocation.
        #expect(AutoSettings.center(for: Self.analysis(smooth: 0.6), preference: .relaxed).colorCount == base.colorCount)
        #expect(AutoSettings.center(for: Self.analysis(subject: 0.7), preference: .relaxed).detail > base.detail)
        #expect(AutoSettings.center(for: Self.analysis(texture: 0.5), preference: .relaxed).detail < base.detail)
        #expect(AutoSettings.center(for: Self.analysis(source: 640), preference: .relaxed).detail == base.detail)
        #expect(AutoSettings.center(for: Self.analysis(texture: 0.5), preference: .relaxed).smoothness > base.smoothness)
        #expect(AutoSettings.center(for: Self.analysis(noise: 0.01), preference: .relaxed).smoothness > base.smoothness)
        #expect(AutoSettings.center(for: Self.analysis(structure: 0.3), preference: .relaxed).smoothness < base.smoothness)
    }

    @Test func kneeFindsWhereAnotherPaintStopsPaying() {
        // A power law through this curve loses 0.0004 per paint at about 39 paints.
        let curve: [Float] = [0.1, 0.084, 0.076, 0.068, 0.064, 0.0608, 0.0592]
        let knee = AutoSettings.knee(curve)
        #expect(knee > 37 && knee < 41)
        // One point off by 3 % (each point is its own k-means run) barely moves it.
        var bumped = curve
        bumped[4] *= 1.03
        #expect(abs(AutoSettings.knee(bumped) / knee - 1) < 0.05)
        #expect(AutoSettings.knee([0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]) == 8)
        #expect(AutoSettings.knee([0.5, 0.45, 0.4, 0.3, 0.2, 0.1, 0.05]) == 64)
    }

    // MARK: - Scoring

    @Test func paintingTimeOutsideTheBandCostsAtEqualFidelity() throws {
        let image = TestScenes.scene(width: 240, height: 160)
        let output = try TemplateGenerator().generate(from: image, cancel: .none)
        let t = output.template
        let working = Resample.area(image, width: t.width, height: t.height)
        let importance = AutoSettings.importance(for: working, map: nil)
        // A canvas on which this many regions take about half an hour (inside Relaxed's band),
        // and one so large its estimate is far above the band.
        let regions = Double(t.regions.count)
        func canvas(seconds: Double) -> (width: Int, height: Int) {
            let ratio = pow(seconds / PaintingTime.estimate(regionCount: t.regions.count), 1 / AutoSettings.regionExponent(detail: 0.5, meanImportance: AutoSettings.meanImportance(importance)))
            return (Int((Double(t.width) * ratio.squareRoot()).rounded()), Int((Double(t.height) * ratio.squareRoot()).rounded()))
        }
        let inside = AutoSettings.score(output, working: working, importance: importance, preference: .relaxed,
                                        fullSize: canvas(seconds: 1800))
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
                                          fullSize: canvas(seconds: 1800))
        #expect(detailed.bandPenalty > 0 && detailed.total > inside.total)
        // Too short costs less than too long by the same factor: the photo may hold no more.
        let band = PaintingLength.relaxed.timeBand
        let short = AutoSettings.score(output, working: working, importance: importance, preference: .relaxed,
                                       fullSize: canvas(seconds: band.lowerBound / 2))
        let long = AutoSettings.score(output, working: working, importance: importance, preference: .relaxed,
                                      fullSize: canvas(seconds: band.upperBound * 2))
        #expect(short.bandPenalty > 0 && short.bandPenalty < long.bandPenalty / 2)
    }

    @Test func theCenterWinsTiesAndOtherTiesGoToTheBandsMiddle() {
        func candidate(total: Float, minutes: Double) -> AutoCandidate {
            AutoCandidate(settings: GenerationSettings(), score: AutoScore(
                fidelity: 0.04, fidelityP95: 0.1, regions: Int(minutes * 20), tinyRegions: 0, bandRings: 0,
                minLabelRoom: 3, estimatedSeconds: minutes * 60, bandPenalty: 0, total: total))
        }
        let margin = AutoSettings.tieMargin
        let center = candidate(total: 0.1000, minutes: 30)
        // Neighbours better by less than the margin don't move the center…
        let close = candidate(total: 0.1000 - 0.9 * margin, minutes: 60)
        #expect(AutoSettings.winner(of: [center, close], preference: .detailed) == 0)
        // …one better by more does; neighbours tied with it go to the band's middle.
        let short = candidate(total: 0.1000 - 2 * margin, minutes: 15)
        let long = candidate(total: 0.1000 - 1.5 * margin, minutes: 60)
        #expect(AutoSettings.winner(of: [center, short, long], preference: .quick) == 1)
        #expect(AutoSettings.winner(of: [center, short, long], preference: .detailed) == 2)
        #expect(AutoSettings.winner(of: [center, long, short], preference: .quick) == 2)
        // A center that runs over its band keeps no tie.
        let overlong = candidate(total: 0.1000, minutes: 70)
        let shorter = candidate(total: 0.1000 - 0.5 * margin, minutes: 40)
        #expect(AutoSettings.winner(of: [center, shorter], preference: .relaxed) == 0)
        #expect(AutoSettings.winner(of: [overlong, shorter], preference: .relaxed) == 1)
        // Outside the margin the lower total wins.
        let worse = candidate(total: 0.1000 - 0.5 * margin, minutes: 60)
        #expect(AutoSettings.winner(of: [center, short, worse], preference: .detailed) == 1)
    }

    @Test func thresholdsFadeIn() {
        #expect(AutoSettings.ramp(0.025, at: 0.03) == 0 && AutoSettings.ramp(0.036, at: 0.03) == 1)
        #expect(abs(AutoSettings.ramp(0.03, at: 0.03) - 0.5) < 1e-5)
        let a = AutoSettings.ramp(0.029, at: 0.03), b = AutoSettings.ramp(0.031, at: 0.03)
        #expect(a > 0 && a < b && b < 1)
    }

    @Test func regionCountsGrowFasterWithDetailAndImportance() {
        func e(_ d: Float, _ m: Float) -> Double { AutoSettings.regionExponent(detail: d, meanImportance: m) }
        #expect(e(0, 0.5) < e(0.5, 0.5) && e(0.5, 0.5) < e(1, 0.5))
        #expect(e(0.5, 0.25) < e(0.5, 0.4) && e(0.5, 0.4) < e(0.5, 0.6))
        #expect(e(0, 0) == 0 && e(1, 1) == 1)
        #expect(e(2, 0.5) == e(1, 0.5))
        #expect(AutoSettings.meanImportance([0.2, 0.4, 0.6]) == 0.4)
    }

    @Test func timeBandsAreOrderedAndOverlap() {
        let bands = PaintingLength.allCases.map(\.timeBand)
        for (a, b) in zip(bands, bands.dropFirst()) {
            #expect(a.lowerBound < b.lowerBound && a.upperBound < b.upperBound)
            #expect(b.lowerBound < a.upperBound)
        }
    }

    @Test func scoreMeasuresTheTemplate() throws {
        let image = TestScenes.scene(width: 240, height: 160)
        let output = try TemplateGenerator().generate(from: image, cancel: .none)
        let t = output.template
        let working = Resample.area(image, width: t.width, height: t.height)
        let s = AutoSettings.score(output, working: working, importance: AutoSettings.importance(for: working, map: nil),
                                   preference: .relaxed)
        #expect(s.regions == t.regions.count)
        #expect(s.tinyRegions == t.regions.filter { $0.inscribedRadius < AutoSettings.tinyRadius }.count)
        #expect(s.fidelity > 0 && s.fidelity < 0.1)
        #expect(s.fidelityP95 >= s.fidelity)
        #expect(s.minLabelRoom >= LabelSizing.minimumRadius - 1e-3)
        #expect(s.estimatedSeconds == PaintingTime.estimate(regionCount: t.regions.count))
        #expect(s.total >= s.fidelity + AutoSettings.p95Weight * s.fidelityP95)
    }

    @Test func paintingTimeEstimate() {
        #expect(PaintingTime.estimate(regionCount: 1200) == 3600)
        #expect(PaintingTime.estimate(regionCount: 0) == 0)
    }

    // MARK: - Choosing

    @Test func choosePicksAWinnerInsideTheBandsAfterOneFirstDraft() throws {
        let image = TestScenes.scene(width: 360, height: 240)
        for preference in PaintingLength.allCases {
            let drafts = LockedCounter()
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
            #expect(decision.candidates[decision.winner].score!.total <= best + AutoSettings.tieMargin)
        }
    }

    @Test func chooseIsByteIdenticalAcrossRuns() throws {
        let image = TestScenes.colorful(width: 300, height: 200)
        let hints = SubjectHints(faces: [NormalizedRect(x: 0.4, y: 0.2, width: 0.3, height: 0.4)])
        let runs = try (0..<2).map { _ in
            try Self.json(AutoSettings.choose(
                image: image, importance: nil, hints: hints, preference: .relaxed, maxCandidates: 5, cancel: .none,
                firstDraft: nil))
        }
        #expect(runs[0] == runs[1])
    }

    @Test func chooseStopsWhenCancelled() throws {
        let image = TestScenes.scene(width: 360, height: 240)
        // Cancelled during the remaining candidates: the first draft still arrived once.
        let drafts = LockedCounter()
        #expect(throws: CancellationError.self) {
            try AutoSettings.choose(
                image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 5,
                cancel: CancellationCheck { drafts.count > 0 }, firstDraft: { _ in drafts.increment() })
        }
        #expect(drafts.count == 1)
        // Cancelled from the start: nothing runs.
        let none = LockedCounter()
        #expect(throws: CancellationError.self) {
            try AutoSettings.choose(
                image: image, importance: nil, hints: nil, preference: .relaxed, maxCandidates: 5,
                cancel: CancellationCheck { true }, firstDraft: { _ in none.increment() })
        }
        #expect(none.count == 0)
        // Cancelled after a few checks, wherever that lands.
        for after in [3, 20, 60] {
            let checks = LockedCounter()
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

    /// `Fixtures/auto-parrots.json` pins the decision for the corpus's parrots photo at Relaxed
    /// with 5 candidates and no importance map; `auto-parrots-draft.ppm` is that photo
    /// (decoded by Pillow) at the draft size. Regenerate both, only when a change to Auto or
    /// the pipeline is meant to move the decision, with the release pbn:
    ///
    ///     python3 -c "from PIL import Image; Image.open('Tests/Corpus/parrots.jpg').convert('RGB').save('/tmp/parrots.ppm')"
    ///     .build/release/pbn suggest /tmp/parrots.ppm --length relaxed --candidates 5 --out /tmp/auto-parrots
    ///     cp /tmp/auto-parrots/decision.json Tests/PaintCoreTests/Fixtures/auto-parrots.json
    ///     cp /tmp/auto-parrots/draft.ppm Tests/PaintCoreTests/Fixtures/auto-parrots-draft.ppm
    ///
    /// Settings, winner and analysis must match exactly; scores to 1e-4, since libm differs
    /// between platforms.
    @Test func parrotsDecisionIsPinned() throws {
        let pinned = try JSONDecoder().decode(AutoDecision.self, from: TestFixtures.data("auto-parrots.json"))
        let draft = try Netpbm.read(TestFixtures.data("auto-parrots-draft.ppm"))
        // The fixture was written by pbn, whose templates are classic unless told otherwise.
        let decision = try AutoSettings.choose(
            image: draft, sourceSize: (pinned.analysis.sourceWidth, pinned.analysis.sourceHeight), importance: nil,
            hints: nil, preference: .relaxed, maxCandidates: 5, lineArt: LineArtSettings(style: .classic), cancel: .none,
            firstDraft: nil)
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
