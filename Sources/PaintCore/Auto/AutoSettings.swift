import Foundation

/// Suggested settings ("Auto"): generation settings chosen for one photo.
///
/// 1. `analyze` measures the photo at the draft size with the pipeline's own stages (palette
///    histogram, structure map, importance).
/// 2. `candidates` turns the features into a center setting and a few neighbours around it
///    (a documented rule, not a learned model).
/// 3. `choose` runs every candidate through the pipeline at the draft size and `score`s each
///    template against the photo: importance-weighted colour error, rings, crumbs, and the
///    distance of its painting time from the preference's band. The lowest total wins.
///
/// The rule is fixed and its inputs are the photo, its importance and hints and the
/// preference, so the same photo always gets the same settings; decisions are reproducible
/// and never stored. The constants are starting values, tuned by eye on contact sheets
/// (`tools/auto_sheet.py`).
public enum AutoSettings {
    public static let paletteCurveKs = [8, 12, 16, 24, 32, 48, 64]

    /// Working long side of drafts. The draft photo is reduced to a third less than this,
    /// and the generator enlarges small inputs up to 1.5×, as the create flow's drafts do.
    public static let draftLongSide = 640.0

    /// The photo reduced to the draft size (unchanged when it already is that small).
    public static func draftImage(from image: RGBAImage) -> RGBAImage {
        let long = Double(max(image.width, image.height))
        guard long > 0 else { return image }
        let scale = min(1, draftLongSide / 1.5 / long)
        guard scale < 1 else { return image }
        return Resample.area(
            image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)))
    }

    // MARK: - Analysis

    /// Measures the features the candidate rule reads (see `PhotoAnalysis`). Runs at the draft
    /// size: larger inputs are reduced first.
    /// - Parameter sourceSize: The original photo's size when `image` is already a reduced
    ///   draft; nil means `image` is the photo itself.
    public static func analyze(
        _ image: RGBAImage, sourceSize: (width: Int, height: Int)? = nil, importance: Grid<Float>?, hints: SubjectHints?,
        cancel: CancellationCheck
    ) throws -> PhotoAnalysis {
        let working = try AutoWorking(
            draft: draftImage(from: image), settings: GenerationSettings(), importance: importance, cancel: cancel)
        return try PhotoAnalyzer.analyze(
            working, source: sourceSize ?? (image.width, image.height), hints: hints, cancel: cancel)
    }

    // MARK: - Candidates

    /// Colors: the paint count where one more paint lowers the palette curve's mean ΔE by
    /// less than this.
    static let marginalGain: Float = 0.0004
    /// Faces need skin tones: extra paints when they cover more than `faceCoverage`.
    static let faceCoverage: Float = 0.05
    static let faceColors: Float = 4
    /// Colourful photos (chroma spread in the top third of the corpus: Kodak 01–24, which
    /// includes the six samples, and scikit-image's astronaut, chelsea, coffee and rocket)
    /// get a quarter more paints.
    static let colorfulSpread: Float = 0.03
    static let colorfulFactor: Float = 1.25
    /// Monochrome and sepia photos (few chromatic pixels) need fewer.
    static let monochromeFraction: Float = 0.15
    static let monochromeFactor: Float = 0.6
    /// Ramps need steps: two paints per tenth of the frame in gentle ramps beyond 30 %.
    static let rampThreshold: Float = 0.3
    static let rampColorsPerTenth: Float = 2
    /// Detail: a subject filling the frame gets more, busy texture less, and a small source
    /// has nothing more to resolve.
    static let fillingSubject: Float = 0.5
    static let fillingSubjectDetail: Float = 0.15
    static let busyTexture: Float = 0.35
    static let busyTextureDetail: Float = -0.15
    static let smallSourceSide = 900
    static let smallSourceDetail: Float = -0.1
    /// Smoothness: texture and noise soften; strong structure (the top third of the
    /// corpus, as for `colorfulSpread`) stays crisp.
    static let smoothnessBase: Float = 0.4
    static let smoothnessPerTexture: Float = 0.5
    static let smoothnessForNoise: Float = 0.3
    static let noiseReference: Float = 0.01
    static let structuredDensity: Float = 0.083
    static let structuredSmoothness: Float = -0.1
    /// Smoothness a suggestion may use.
    public static let smoothnessBand: ClosedRange<Float> = 0.25...0.8
    /// Neighbours: colours × these factors, detail ± this step.
    static let colorFactors: (lower: Float, upper: Float) = (0.75, 1.3)
    static let detailStep: Float = 0.2

    /// The prior: a center and up to `maxCandidates` settings around it, deterministic. The
    /// center comes first, then the four single-axis moves (fewer colors, more colors, less
    /// detail, more detail), then the diagonals; every candidate lies inside the preference's
    /// bands, and duplicates left by clamping to them are skipped.
    public static func candidates(for analysis: PhotoAnalysis, preference: PaintingLength, maxCandidates: Int) -> [AutoCandidate] {
        let center = center(for: analysis, preference: preference)
        let colorBand = preference.colorBand, detailBand = preference.detailBand
        func colors(_ value: Float) -> Int { clamp(evenColors(value), colorBand) }
        func detail(_ value: Float) -> Float { clamp(hundredths(value), detailBand) }
        let c = Float(center.colorCount)
        let cs = [center.colorCount, colors(c * colorFactors.lower), colors(c * colorFactors.upper)]
        let ds = [center.detail, detail(center.detail - detailStep), detail(center.detail + detailStep)]
        let order = [(0, 0), (1, 0), (2, 0), (0, 1), (0, 2), (1, 1), (1, 2), (2, 1), (2, 2)]
        var out: [AutoCandidate] = []
        for (ci, di) in order where out.count < max(1, maxCandidates) {
            var settings = center
            settings.colorCount = cs[ci]
            settings.detail = ds[di]
            if !out.contains(where: { $0.settings == settings }) { out.append(AutoCandidate(settings: settings)) }
        }
        return out
    }

    /// The center of the candidates (see the rule on the constants above).
    static func center(for a: PhotoAnalysis, preference: PaintingLength) -> GenerationSettings {
        var colors = Float(clamp(Int(knee(a.paletteCurve).rounded()), preference.colorBand))
        if a.faceCoverage > faceCoverage { colors += faceColors }
        if a.chromaSpread >= colorfulSpread { colors *= colorfulFactor }
        if a.chromaticFraction < monochromeFraction { colors *= monochromeFactor }
        colors += rampColorsPerTenth * max(0, a.smoothFraction - rampThreshold) / 0.1

        var detail = preference.detailCenter
        if a.subjectCoverage > fillingSubject { detail += fillingSubjectDetail }
        if a.textureFraction > busyTexture { detail += busyTextureDetail }
        if max(a.sourceWidth, a.sourceHeight) < smallSourceSide { detail += smallSourceDetail }

        var smoothness = smoothnessBase + smoothnessPerTexture * a.textureFraction
            + smoothnessForNoise * min(a.noise / noiseReference, 1)
        if a.structureDensity >= structuredDensity { smoothness += structuredSmoothness }

        return GenerationSettings(
            colorCount: clamp(evenColors(colors), preference.colorBand),
            detail: clamp(hundredths(min(max(detail, 0), 1)), preference.detailBand),
            smoothness: hundredths(min(max(smoothness, smoothnessBand.lowerBound), smoothnessBand.upperBound)))
    }

    /// The smallest paint count at which the palette curve's gain per added paint falls below
    /// `marginalGain`, interpolated between the gains of consecutive sampled ks (each
    /// assigned to the middle of its interval); the largest k when it never does.
    static func knee(_ curve: [Float]) -> Float {
        let ks = paletteCurveKs.map(Float.init)
        guard curve.count == ks.count else { return ks[ks.count / 2] }
        var previous: (k: Float, gain: Float)?
        for i in 0..<(ks.count - 1) {
            let gain = (curve[i] - curve[i + 1]) / (ks[i + 1] - ks[i])
            let middle = (ks[i] + ks[i + 1]) / 2
            if gain < marginalGain {
                guard let previous else { return ks[0] }
                return previous.k + (previous.gain - marginalGain) / (previous.gain - gain) * (middle - previous.k)
            }
            previous = (middle, gain)
        }
        return ks[ks.count - 1]
    }

    // MARK: - Scoring

    /// Weight of the 95th-percentile colour error next to the mean.
    static let p95Weight: Float = 0.5
    /// Weights of the share of regions that are ramp rings and tiny crumbs.
    static let ringWeight: Float = 0.02
    static let tinyWeight: Float = 0.01
    /// Regions under this inscribed radius are crumbs.
    static let tinyRadius: Float = 3
    /// Band penalty: this × ln(estimate / nearest band edge)², so twice or half the band's
    /// time costs about as much as 0.024 ΔE.
    static let bandPenaltyWeight: Float = 0.05
    /// Totals this close are a tie, which the template with fewer regions wins.
    static let tieTolerance: Float = 0.002
    /// Region counts grow with the canvas roughly as area^0.6, not in proportion: minimum
    /// areas are fractions of the canvas but label room is in pixels. Measured on the six
    /// samples at detail 0.3–0.7 (639 × 426 drafts against 1152 × 768 templates).
    static let regionAreaExponent = 0.6

    /// How `total` is made of the score's terms, for reports.
    public static var scoreFormula: String {
        "total = fidelity + \(p95Weight) × p95 + \(ringWeight) × rings/regions + \(tinyWeight) × tiny/regions"
            + " + \(bandPenaltyWeight) × ln(time / band edge)² outside the band; ties within \(tieTolerance) → fewer regions"
    }

    /// The pipeline's importance weights for a working image (the map `score` expects): the
    /// given map resampled, or the pipeline's own estimate without one.
    public static func importance(for working: RGBAImage, map: Grid<Float>?) -> [Float] {
        guard working.width > 0, working.height > 0,
              let prepared = try? AutoWorking(working: working, importance: map, cancel: .none)
        else { return [Float](repeating: 0.5, count: working.width * working.height) }
        return prepared.weights
    }

    /// Measures a candidate's template against its photo.
    /// - Parameters:
    ///   - working: The photo at the template's size (the image the generator segmented).
    ///   - importance: Per-pixel importance at that size (`importance(for:map:)`).
    ///   - fullSize: The canvas the full-resolution template will have; the painting time is
    ///     estimated for it. Nil means the template's own canvas.
    public static func score(
        _ output: TemplateGenerator.Output, working: RGBAImage, importance: [Float], preference: PaintingLength,
        fullSize: (width: Int, height: Int)? = nil
    ) -> AutoScore {
        let t = output.template
        let w = t.width, h = t.height, n = w * h
        let image = working.width == w && working.height == h ? working : Resample.area(working, width: w, height: h)
        let weights = importance.count == n ? importance : [Float](repeating: 0.5, count: n)
        let fidelity = colorError(t, image: image, weights: weights)

        let regions = t.regions.count
        let tiny = t.regions.reduce(0) { $0 + ($1.inscribedRadius < tinyRadius ? 1 : 0) }
        var room = Float.infinity
        for label in t.labels {
            let digits = LabelSizing.digitCount(colorIndex: t.regions[Int(label.region)].colorIndex)
            room = min(room, label.radius / LabelSizing.roomFactor(digits: digits))
        }
        let rings = BandRings.count(output.segmentation, working: image)

        var estimatedRegions = Double(regions)
        if let fullSize, n > 0 {
            let ratio = Double(fullSize.width * fullSize.height) / Double(n)
            estimatedRegions *= pow(ratio, regionAreaExponent)
        }
        let seconds = PaintingTime.estimate(regionCount: Int(estimatedRegions.rounded()))
        let band = preference.timeBand
        var penalty: Float = 0
        if seconds > band.upperBound || seconds < band.lowerBound {
            let edge = seconds > band.upperBound ? band.upperBound : band.lowerBound
            let distance = Float(log(max(seconds, 1) / edge))
            penalty = bandPenaltyWeight * distance * distance
        }
        let perRegion = 1 / Float(max(regions, 1))
        let total = fidelity.mean + p95Weight * fidelity.p95 + ringWeight * Float(rings) * perRegion
            + tinyWeight * Float(tiny) * perRegion + penalty
        return AutoScore(
            fidelity: fidelity.mean, fidelityP95: fidelity.p95, regions: regions, tinyRegions: tiny, bandRings: rings,
            minLabelRoom: room.isFinite ? room : 0, estimatedSeconds: seconds, bandPenalty: penalty, total: total)
    }

    /// Importance-weighted mean and 95th percentile of the true-OKLab distance between every
    /// pixel and its region's paint. Weights are the palette's (`PaletteBuilder.paletteWeight`),
    /// so the subject's error counts most; sums run over fixed chunks added in order.
    static func colorError(_ t: Template, image: RGBAImage, weights: [Float]) -> (mean: Float, p95: Float) {
        let n = t.width * t.height
        guard n > 0, !t.regions.isEmpty else { return (0, 0) }
        let lab = ColorScience.okLabImage(from: image)
        let paint = t.regions.map { t.palette[Int($0.colorIndex)].oklab }
        let bins = 1000, binWidth: Float = 0.0005
        let chunk = 16_384
        let chunks = (n + chunk - 1) / chunk
        var partial = [Double](repeating: 0, count: chunks * (bins + 2))
        lab.storage.withUnsafeBufferPointer { lb in
            t.regionMap.storage.withUnsafeBufferPointer { mb in
                weights.withUnsafeBufferPointer { wb in
                    paint.withUnsafeBufferPointer { pb in
                        partial.withUnsafeMutableBufferPointer { ob in
                            let l = UncheckedSendable(lb), m = UncheckedSendable(mb), wt = UncheckedSendable(wb)
                            let pt = UncheckedSendable(pb), out = UncheckedSendable(ob.baseAddress!)
                            Parallel.forEachChunk(n, chunk: chunk) { range in
                                let slot = out.value + (range.lowerBound / chunk) * (bins + 2)
                                for i in range {
                                    let v = l.value[i]
                                    let e = ColorScience.distance(SIMD3(v.x, v.y, v.z), pt.value[Int(m.value[i])])
                                    let weight = Double(PaletteBuilder.paletteWeight(importance: wt.value[i]))
                                    slot[bins] += weight * Double(e)
                                    slot[bins + 1] += weight
                                    slot[min(Int(e / binWidth), bins - 1)] += weight
                                }
                            }
                        }
                    }
                }
            }
        }
        var total = [Double](repeating: 0, count: bins + 2)
        for c in 0..<chunks {
            for k in 0..<(bins + 2) { total[k] += partial[c * (bins + 2) + k] }
        }
        let weight = total[bins + 1]
        guard weight > 0 else { return (0, 0) }
        var cumulative = 0.0, p95 = Float(bins) * binWidth
        for b in 0..<bins {
            cumulative += total[b]
            if cumulative >= 0.95 * weight {
                p95 = Float(b + 1) * binWidth
                break
            }
        }
        return (Float(total[bins] / weight), p95)
    }

    // MARK: - Choosing

    /// Runs the candidates on `image` (already reduced to the draft size), in parallel and
    /// cancellable, and picks the winner. `firstDraft` is called as soon as the center
    /// candidate finishes so the app can show something immediately.
    ///
    /// Inputs larger than the draft size are reduced to it first. `sourceSize` is the original
    /// photo's size when `image` is a reduced draft (nil: `image` is the photo itself); it
    /// sets the analysis's source size and the canvas the painting time is estimated for.
    /// Candidates run at most as many at a time as there are cores, each with its own
    /// parallel pipeline. Deterministic for the same image, importance, hints and preference.
    public static func choose(
        image: RGBAImage, sourceSize: (width: Int, height: Int)? = nil, importance: Grid<Float>?, hints: SubjectHints?,
        preference: PaintingLength, maxCandidates: Int, cancel: CancellationCheck,
        firstDraft: (@Sendable (TemplateGenerator.Output) -> Void)?
    ) throws -> AutoDecision {
        // Checks only see task cancellation on the calling thread; once it sees one, the
        // latch stops the candidates running on other threads too.
        let latch = CancellationLatch()
        let check = CancellationCheck { latch.isSet || (cancel.isCancelled && latch.set()) }
        try check.throwIfCancelled()
        let source = sourceSize ?? (image.width, image.height)
        let draft = draftImage(from: image)
        let shared = try AutoWorking(draft: draft, settings: GenerationSettings(), importance: importance, cancel: check)
        let analysis = try PhotoAnalyzer.analyze(shared, source: source, hints: hints, cancel: check)
        var candidates = Self.candidates(for: analysis, preference: preference, maxCandidates: maxCandidates)

        func generate(_ settings: GenerationSettings) throws -> TemplateGenerator.Output {
            try TemplateGenerator(settings: settings).generate(from: draft, importance: importance, cancel: check)
        }
        func score(_ output: TemplateGenerator.Output, _ settings: GenerationSettings) throws -> AutoScore {
            let size = settings.workingSize(sourceWidth: draft.width, sourceHeight: draft.height)
            let working = size.width == shared.image.width && size.height == shared.image.height
                ? shared
                : try AutoWorking(draft: draft, settings: settings, importance: importance, cancel: check)
            let full = settings.workingSize(sourceWidth: source.width, sourceHeight: source.height)
            return Self.score(output, working: working.image, importance: working.weights, preference: preference, fullSize: full)
        }

        let center = try generate(candidates[0].settings)
        // The generator's last check can precede a cancellation; a cancelled suggestion
        // must not show its draft.
        try check.throwIfCancelled()
        firstDraft?(center)
        candidates[0].score = try score(center, candidates[0].settings)
        try check.throwIfCancelled()

        let others = candidates.dropFirst().map(\.settings)
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let results = Parallel.mapBands(others.count, minimumBandSize: (others.count + cores - 1) / cores) { range in
            range.map { i in Result { try score(generate(others[i]), others[i]) } }
        }.joined()
        for (i, result) in results.enumerated() { candidates[i + 1].score = try result.get() }
        try check.throwIfCancelled()

        return AutoDecision(analysis: analysis, preference: preference, candidates: candidates, winner: winner(of: candidates))
    }

    /// The lowest total; totals within `tieTolerance` of it go to the fewest regions, then to
    /// the earlier candidate.
    static func winner(of candidates: [AutoCandidate]) -> Int {
        let totals = candidates.map { $0.score?.total ?? .infinity }
        guard let best = totals.min(), best.isFinite else { return 0 }
        var winner = -1
        for (i, c) in candidates.enumerated() where totals[i] <= best + tieTolerance {
            if winner < 0 || c.score!.regions < candidates[winner].score!.regions { winner = i }
        }
        return winner
    }

    // MARK: - Helpers

    @inline(__always) static func evenColors(_ value: Float) -> Int { 2 * Int((value / 2).rounded()) }
    @inline(__always) static func hundredths(_ value: Float) -> Float { (value * 100).rounded() / 100 }
    @inline(__always) static func clamp<T: Comparable>(_ value: T, _ band: ClosedRange<T>) -> T {
        min(max(value, band.lowerBound), band.upperBound)
    }
}

/// Set once, read by every candidate's cancellation checks.
private final class CancellationLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isSet: Bool { lock.withLock { cancelled } }

    /// Sets the latch; returns true so it can end a check expression.
    func set() -> Bool {
        lock.withLock { cancelled = true }
        return true
    }
}
