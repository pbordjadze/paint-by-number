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
/// preference, so the same pixels always get the same settings; decisions are reproducible
/// and never stored. A re-encoded copy of a photo moves the scores a little, so the rule's
/// thresholds are ramps, the knee is a fitted curve and a neighbour must beat the center by
/// more than that (`tieMargin`); a JPEG re-save still changes about one suggestion in six
/// materially. The constants were tuned by eye on contact sheets (`tools/auto_sheet.py`,
/// `docs/wave2/log/auto-tuning.md`).
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
    /// get a quarter more paints. Like every threshold of the rule it is a ramp
    /// (`ramp(_:at:)`), not a step: a re-saved photo whose spread fell from 0.030 to 0.029 lost
    /// 6 of its 40 paints to the step.
    static let colorfulSpread: Float = 0.03
    static let colorfulFactor: Float = 1.25
    /// Monochrome and sepia photos need fewer: the palette curve of a grey photo keeps
    /// falling along lightness alone, so its knee sits with colour photos' (23–27 against
    /// 27–37 on grey copies of six corpus photos). The cut fades in below
    /// `monochromeFraction` chromatic pixels and is full at none, rather than a step:
    /// photos with small vivid parts (regatta sails at 0.108, a cake at 0.149, sky over
    /// clouds at 0.139) lost the paints their subject needed to a 0.15 cliff.
    static let monochromeFraction: Float = 0.15
    static let monochromeFactor: Float = 0.6
    /// Detail: a subject filling the frame gets more, busy texture less. A small source gets
    /// no less (the spec's −0.1 under 900 px): its canvas is enlarged to 1.5 times whatever
    /// the detail, so detail still sets how fine its areas are, and on the corpus's 105
    /// decisions for photos under 900 px the score chose more detail than the center 77
    /// times and less never, while those photos already fell short of the time bands.
    static let fillingSubject: Float = 0.5
    static let fillingSubjectDetail: Float = 0.15
    static let busyTexture: Float = 0.35
    static let busyTextureDetail: Float = -0.15
    /// A map that protects less of the frame gets more detail, so the painting keeps its
    /// length: the bands and detail centers were tuned on the pipeline's fallback map (mean
    /// importance about 0.6), and at like settings a Vision-like map (0.25 base, mean about
    /// 0.4) gives about half the areas (`regionAreaExponent`). On the corpus's full templates
    /// at 28 colours a large photo's median reached 30 minutes at detail 0.5 under the
    /// fallback, 0.7 under the Vision stand-in and about 0.9 under a uniform 0.25 map: about
    /// one unit of detail per unit of mean importance.
    static let referenceImportance: Float = 0.6
    static let detailPerImportance: Float = 1
    /// Smoothness: texture and noise soften; strong structure (the top third of the
    /// corpus, as for `colorfulSpread`) stays crisp.
    static let smoothnessBase: Float = 0.4
    static let smoothnessPerTexture: Float = 0.5
    static let smoothnessForNoise: Float = 0.3
    /// `noise` is a σ estimate (median absolute Laplacian / 3.02), measured on the draft. The
    /// draft's reduction averages sensor noise away: Gaussian noise of σ 12/255 added to a
    /// 2048-px photo reads 0.0017, to a 768-px one 0.0036, while fine texture the texture
    /// term already counts reads up to 0.006 (grass, river stones). Scaling the term to σ
    /// (0.0033) raised the smoothness of clean photos by 0.1–0.2 for their texture, so the
    /// reference stays at 0.01 and the term at most +0.18.
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
        colors += faceColors * ramp(a.faceCoverage, at: faceCoverage)
        colors *= 1 + (colorfulFactor - 1) * ramp(a.chromaSpread, at: colorfulSpread)
        colors *= monochromeFactor + (1 - monochromeFactor) * min(a.chromaticFraction / monochromeFraction, 1)
        // Ramps get no extra paints (the spec's +2 per tenth of the frame in ramps beyond 30 %
        // was meant for W3's gradient-aware allocation, which did not land): on the corpus's
        // 32 decisions for photos with ramps, the candidate with 1.3 times the paints lowered
        // ΔE by only 0.0005 and raised the share of ring regions by 0.8 points; the colour
        // neighbours already offer more paints where they pay.

        var detail = preference.detailCenter
        detail += fillingSubjectDetail * ramp(a.subjectCoverage, at: fillingSubject)
        detail += busyTextureDetail * ramp(a.textureFraction, at: busyTexture)
        detail += detailPerImportance * (referenceImportance - a.meanImportance)

        var smoothness = smoothnessBase + smoothnessPerTexture * a.textureFraction
            + smoothnessForNoise * min(a.noise / noiseReference, 1)
        smoothness += structuredSmoothness * ramp(a.structureDensity, at: structuredDensity)

        return GenerationSettings(
            colorCount: clamp(evenColors(colors), preference.colorBand),
            detail: clamp(hundredths(min(max(detail, 0), 1)), preference.detailBand),
            smoothness: hundredths(min(max(smoothness, smoothnessBand.lowerBound), smoothnessBand.upperBound)))
    }

    /// The paint count at which one more paint lowers the palette curve's mean ΔE by
    /// `marginalGain`, on a power law `error = A · k^−b` fitted to the whole curve (least
    /// squares in log–log): `k = (A·b / marginalGain)^(1 / (b + 1))`, within 8…64. Each point
    /// of the curve is its own k-means run, so reading the gain between neighbouring points
    /// (the first rule) moved the knee by a tenth on average when a photo was re-saved as JPEG
    /// q92, up to 26 → 35 paints; the fit moves it by 2 % on the same 33 photos, at the same
    /// level (median ratio 0.99).
    static func knee(_ curve: [Float]) -> Float {
        let ks = paletteCurveKs.map(Double.init)
        let range = Float(ks[0])...Float(ks[ks.count - 1])
        guard curve.count == ks.count else { return Float(ks[ks.count / 2]) }
        let xs = ks.map { log($0) }, ys = curve.map { log(max(Double($0), 1e-4)) }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - mx) * (y - my)
            sxx += (x - mx) * (x - mx)
        }
        let b = -sxy / sxx
        guard b > 1e-6 else { return range.lowerBound }
        let a = exp(my + b * mx)
        let k = pow(a * b / Double(marginalGain), 1 / (b + 1))
        return clamp(Float(k), range)
    }

    // MARK: - Scoring

    /// Weight of the 95th-percentile colour error next to the mean.
    static let p95Weight: Float = 0.5
    /// Weights of the share of regions that are ramp rings and tiny crumbs.
    static let ringWeight: Float = 0.02
    static let tinyWeight: Float = 0.01
    /// Regions under this inscribed radius are crumbs.
    static let tinyRadius: Float = 3
    /// What one more paint must buy. Past the palette curve's knee a paint gains the score
    /// almost nothing (median 0.00002 from the center's colours to 1.3 times them over the
    /// corpus's decisions, 0.00018 from 0.75 times them to the center), so without a price
    /// the noise between candidates drifted Relaxed to its 40-paint ceiling with no visible
    /// gain; this price keeps the knee's colours unless more buy a visible improvement.
    static let paintWeight: Float = 0.0001
    /// Band penalty above the band: this × ln(estimate / upper edge)², so a quarter over
    /// costs 0.007 ΔE and twice the band's time 0.07: a Quick painting must not run long.
    /// At 0.05 (+36 % for 0.005) busy photos chose candidates well past the band (a
    /// 163-minute Detailed hedgehog, a 53-minute Relaxed portrait) over ones inside it
    /// that looked the same.
    static let bandPenaltyWeight: Float = 0.15
    /// Below the band the photo itself may hold too little for the length asked (a simple
    /// 768-px photo reaches 10–20 minutes at any detail), and every candidate pays: this
    /// weight still prefers the longer of two candidates, but no longer lets 6 more regions
    /// outweigh 0.004 ΔE (at 0.05 Detailed chose 20 colours over Relaxed's 26).
    static let belowBandWeight: Float = 0.01
    /// Scores within this of the best are a tie, because a photo's re-encode moves them that
    /// much: a JPEG q92 re-save of 33 corpus photos (99 decisions) changed the difference
    /// between a neighbour's total and the center's by a median 0.003 (p90 0.010), from the
    /// colour error, its 95th percentile and the region estimate together. The center (the
    /// rule's prior) wins every tie; when a neighbour beats it by more, the tied neighbours go
    /// to the painting time nearest the middle of the band (geometric mean of its edges), as
    /// they do when the center's own estimate runs over the band (busy grass, tulips and
    /// river stones then kept a 60–70-minute Relaxed center over a shorter neighbour).
    /// Re-saved photos whose suggestion changed materially (colours by more than 15 %, detail
    /// or smoothness by 0.1 or more), out of 99: 54 with a 0.001 window, 43 at 0.004, 15 at
    /// 0.006, 12 at 0.008; 0.006 keeps neighbours that win clearly (22 of the 99), and 16 with
    /// the over-band exception.
    static let tieMargin: Float = 0.006
    /// Region counts grow with the canvas as area^(a + b × detail + c × mean importance),
    /// not in proportion: minimum areas are fractions of the canvas but label room is in
    /// pixels, so the count grows only where the pixel floors hold the draft back: the more
    /// detail asks for, and the more of the frame the importance map protects (unimportant
    /// areas need larger regions, `SegmentationParameters.areaScale`). Least squares over
    /// 1104 draft/full pairs: the 69 corpus photos at 28 colours and detail 0.1, 0.4, 0.7 and
    /// 1, each under four maps: the pipeline's fallback (mean 0.6, what `pbn` uses without a
    /// map), uniform 0.25 and 0.4, and a Vision stand-in built like `SubjectImportance`'s
    /// (0.25 base, an attention blob, a 0.75 subject mask and faces near 1; W3's hand-made
    /// maps for four photos; mean 0.36–0.63). rms error of the log count 0.22 with no bias
    /// by map (±0.04), against 0.35 for the detail-only fit (0.29 + 0.42 × detail, tuned on
    /// fallback maps), which overestimated a uniform-0.25 map's count 1.4-fold.
    static let regionAreaExponent: (base: Double, perDetail: Double, perImportance: Double) = (-0.18, 0.42, 0.77)

    /// How `total` is made of the score's terms, for reports.
    public static var scoreFormula: String {
        "total = fidelity + \(p95Weight) × p95 + \(ringWeight) × rings/regions + \(tinyWeight) × tiny/regions"
            + " + \(paintWeight) × paints"
            + " + \(bandPenaltyWeight) × ln(time / band top)² above the band (\(belowBandWeight) × … below it);"
            + " ties within \(tieMargin) → the center unless it runs over the band, else the time nearest the band's middle"
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
    ///   - detail: The detail the template was generated at (the default settings' unless
    ///     given); with `fullSize` it sets how the region count grows to the full canvas.
    public static func score(
        _ output: TemplateGenerator.Output, working: RGBAImage, importance: [Float], preference: PaintingLength,
        fullSize: (width: Int, height: Int)? = nil, detail: Float = GenerationSettings().detail
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
            estimatedRegions *= pow(ratio, regionExponent(detail: detail, meanImportance: meanImportance(weights)))
        }
        let seconds = PaintingTime.estimate(regionCount: Int(estimatedRegions.rounded()))
        let band = preference.timeBand
        var penalty: Float = 0
        if seconds > band.upperBound || seconds < band.lowerBound {
            let above = seconds > band.upperBound
            let distance = Float(log(max(seconds, 1) / (above ? band.upperBound : band.lowerBound)))
            penalty = (above ? bandPenaltyWeight : belowBandWeight) * distance * distance
        }
        let perRegion = 1 / Float(max(regions, 1))
        let total = fidelity.mean + p95Weight * fidelity.p95 + ringWeight * Float(rings) * perRegion
            + tinyWeight * Float(tiny) * perRegion + paintWeight * Float(t.palette.count) + penalty
        return AutoScore(
            fidelity: fidelity.mean, fidelityP95: fidelity.p95, regions: regions, tinyRegions: tiny, bandRings: rings,
            minLabelRoom: room.isFinite ? room : 0, estimatedSeconds: seconds, bandPenalty: penalty, total: total)
    }

    /// The exponent of the canvas area ratio that turns a draft's region count into the full
    /// template's (`regionAreaExponent`), within 0…1.
    static func regionExponent(detail: Float, meanImportance: Float) -> Double {
        let e = regionAreaExponent
        let value = e.base + e.perDetail * Double(min(max(detail, 0), 1))
            + e.perImportance * Double(min(max(meanImportance, 0), 1))
        return min(max(value, 0), 1)
    }

    /// Mean of importance weights, to hundredths (summed in fixed chunks, in order).
    static func meanImportance(_ weights: [Float]) -> Float {
        guard !weights.isEmpty else { return 0.5 }
        let chunk = 16_384
        var total = 0.0
        var start = 0
        while start < weights.count {
            var sum: Float = 0
            for i in start..<min(start + chunk, weights.count) { sum += weights[i] }
            total += Double(sum)
            start += chunk
        }
        return (Float(total / Double(weights.count)) * 100).rounded() / 100
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
            return Self.score(
                output, working: working.image, importance: working.weights, preference: preference, fullSize: full,
                detail: settings.detail)
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

        return AutoDecision(
            analysis: analysis, preference: preference, candidates: candidates,
            winner: winner(of: candidates, preference: preference))
    }

    /// The lowest total, with `tieMargin`: the center when its total is within the margin of
    /// the best and its painting time doesn't run over the band; otherwise, of the candidates
    /// within the margin, the estimated painting time nearest the middle of the preference's
    /// band (on a log scale), then the earlier candidate.
    static func winner(of candidates: [AutoCandidate], preference: PaintingLength) -> Int {
        let totals = candidates.map { $0.score?.total ?? .infinity }
        guard let best = totals.min(), best.isFinite else { return 0 }
        let band = preference.timeBand
        if totals[0] <= best + tieMargin, candidates[0].score!.estimatedSeconds <= band.upperBound { return 0 }
        let middle = (band.lowerBound * band.upperBound).squareRoot()
        func distance(_ i: Int) -> Double { abs(log(max(candidates[i].score!.estimatedSeconds, 1) / middle)) }
        var winner = -1
        for i in candidates.indices where totals[i] <= best + tieMargin {
            if winner < 0 || distance(i) < distance(winner) { winner = i }
        }
        return winner
    }

    // MARK: - Helpers

    /// 0 below `threshold` − `rampWidth`/2, 1 above `threshold` + `rampWidth`/2, linear in
    /// between (relative to the threshold): the rule's thresholds fade in, so a feature that a
    /// re-encode nudges across one moves the center a little instead of a whole step.
    static let rampWidth: Float = 0.3
    @inline(__always) static func ramp(_ value: Float, at threshold: Float) -> Float {
        let half = rampWidth / 2 * threshold
        return min(max((value - threshold + half) / (2 * half), 0), 1)
    }

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
