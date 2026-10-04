import Foundation

/// What each per-pixel accumulator of `PhotoAnalyzer.analyze` sums, one lane each.
private enum Lane: Int, CaseIterable {
    /// Pixels above the chroma threshold.
    case chromatic
    /// The sum of chroma and of its squares (for the chroma spread).
    case chromaSum, chromaSquares
    /// Busy pixels whose gradient is incoherent.
    case texture
    /// Busy pixels whose gradient is coherent.
    case structure
    /// Pixels inside gentle ramps.
    case ramp
    /// Pixels above `PhotoAnalyzer.subjectImportance`.
    case subject
    /// The sum of the importance weights.
    case importance
}

private extension [Double] {
    subscript(lane: Lane) -> Double {
        @inline(__always) get { self[lane.rawValue] }
        @inline(__always) set { self[lane.rawValue] = newValue }
    }
}

/// Photo features for the candidate rule (`AutoSettings.analyze`). Thresholds are in the
/// pipeline's working space (OKLab with chroma × `chromaScale`) and per working pixel; they
/// are starting values kept through tuning (`docs/auto-tuning.md`) except where a constant
/// says otherwise.
enum PhotoAnalyzer {
    /// Paint-count curve: Lloyd iterations per k after k-means++ seeding.
    static let curveIterations = 10
    /// A pixel is chromatic above this chroma (true OKLab), scaled down with lightness below
    /// `chromaticLightness` (to at most `chromaticFloor` of it): a dark pixel can't hold much
    /// absolute chroma, so a fixed 0.04 rated a night photo with an orange lamp and a blue
    /// sky (mean lightness 0.2) 0.008 chromatic and the monochrome cut took its colours; with
    /// the relative test it reads 0.23. Grey copies of colour photos still read 0, and so do
    /// near-black pixels' chroma noise (the floor).
    static let chromaticChroma: Float = 0.04
    static let chromaticLightness: Float = 0.5
    static let chromaticFloor: Float = 0.25
    /// Busy pixels: the summed mean step magnitude of both axes over the analysis structure
    /// window is above this (about one just-noticeable difference per pixel and axis: foliage,
    /// gravel, fur, contours; not JPEG noise on a flat wall). Texture is busy pixels with less
    /// than `textureCoherence` of that coherent, structure the rest.
    static let textureStep: Float = 0.04
    static let textureCoherence: Float = 0.5
    /// Radius of the analysis structure window, as a fraction of the frame's side (at least
    /// 2 px): wider than the pipeline's, so the steps of fine texture cancel inside it.
    static let structureRadius: Float = 0.005
    /// Ramps: the mean per-axis step stays below `rampStep` (no edge, no texture) while the
    /// image blurred over a window of about 1/60 of the frame still slopes by `rampSlope` to
    /// `rampStep` per pixel (a gradient that persists: sky, skin, bokeh; a quarter of the
    /// lightness range across a 640-px frame is 0.0004 per pixel), and slopes at a scale of a
    /// few pixels by at least `rampAgreement` of that.
    static let rampStep: Float = 0.004
    static let rampSlope: Float = 0.0003
    static let rampAgreement: Float = 0.5
    /// Importance above which a pixel belongs to the subject.
    static let subjectImportance: Float = 0.6
    /// Cells per side of the grid the importance entropy is measured on.
    static let entropyCells = 32
    /// The noise histogram: `noiseBins` bins of Laplacian magnitude, `noiseBin` wide.
    static let noiseBins = 2000
    static let noiseBin: Float = 0.0002
    /// The palette curve keeps 4 decimals (0.0001 ΔE, a two-hundredth of a just-noticeable
    /// difference): the color rule reads its slope, and at 3 decimals one quantum between
    /// 8 and 12 paints was 0.00025 ΔE per paint against a 0.0004 threshold, so the knee
    /// jumped between a few coarse values (tuned on the 69-photo corpus,
    /// `docs/auto-tuning.md`).
    static let curvePlaces = 4

    static func analyze(
        _ working: AutoWorking, source: (width: Int, height: Int), hints: SubjectHints?, cancel: CancellationCheck
    ) throws -> PhotoAnalysis {
        let w = working.image.width, h = working.image.height, n = w * h
        let p = working.parameters
        let curve = try paletteCurve(working, cancel: cancel)
        try cancel.throwIfCancelled()

        let side = Float(n).squareRoot()
        let structure = try StructureMap(
            working.lab, radius: max(2, Int((side * structureRadius).rounded())), cancel: cancel)
        try cancel.throwIfCancelled()
        let rampRadius = max(2, Int((side / 60).rounded()))
        let coarse = try BoxBlur.apply(working.lab.storage, width: w, height: h, radius: rampRadius, passes: 2, cancel: cancel)
        let fine = try BoxBlur.apply(working.lab.storage, width: w, height: h, radius: 2, passes: 2, cancel: cancel)
        try cancel.throwIfCancelled()

        // Per-pixel features, summed over fixed chunks in chunk order (the result does not
        // depend on the number of cores); the noise histogram counts are integers.
        let lanes = Lane.allCases.count
        let chunk = 16_384
        let chunks = (n + chunk - 1) / chunk
        var sums = [Double](repeating: 0, count: chunks * lanes)
        var histograms = [Int32](repeating: 0, count: chunks * noiseBins)
        let chromaScale = p.chromaScale
        working.lab.storage.withUnsafeBufferPointer { labBuffer in
            structure.horizontal.withUnsafeBufferPointer { hb in
                structure.vertical.withUnsafeBufferPointer { vb in
                    working.weights.withUnsafeBufferPointer { wb in
                        coarse.withUnsafeBufferPointer { cb in
                            fine.withUnsafeBufferPointer { fb in
                                sums.withUnsafeMutableBufferPointer { sb in
                                    histograms.withUnsafeMutableBufferPointer { hgb in
                                        let lab = UncheckedSendable(labBuffer), hor = UncheckedSendable(hb)
                                        let ver = UncheckedSendable(vb), weight = UncheckedSendable(wb)
                                        let co = UncheckedSendable(cb), fi = UncheckedSendable(fb)
                                        let out = UncheckedSendable(sb.baseAddress!), hist = UncheckedSendable(hgb.baseAddress!)
                                        Parallel.forEachChunk(n, chunk: chunk) { range in
                                            let c = range.lowerBound / chunk
                                            var acc = [Double](repeating: 0, count: lanes)
                                            let bins = hist.value + c * noiseBins
                                            // Slope per pixel of a blurred image across ±r (clamped at the frame).
                                            @inline(__always) func slope(_ buffer: UnsafeBufferPointer<SIMD4<Float>>, x: Int, y: Int, r: Int) -> Float {
                                                let x0 = max(x - r, 0), x1 = min(x + r, w - 1)
                                                let y0 = max(y - r, 0), y1 = min(y + r, h - 1)
                                                var gx = buffer[y * w + x1] - buffer[y * w + x0]
                                                var gy = buffer[y1 * w + x] - buffer[y0 * w + x]
                                                gx.w = 0
                                                gy.w = 0
                                                let sx = x1 > x0 ? (gx * gx).sum().squareRoot() / Float(x1 - x0) : 0
                                                let sy = y1 > y0 ? (gy * gy).sum().squareRoot() / Float(y1 - y0) : 0
                                                return (sx * sx + sy * sy).squareRoot()
                                            }
                                            for i in range {
                                                let x = i % w, y = i / w
                                                let v = lab.value[i]
                                                let chroma = (v.y * v.y + v.z * v.z).squareRoot() / chromaScale
                                                let lightness = min(1, max(v.x / chromaticLightness, chromaticFloor))
                                                if chroma > chromaticChroma * lightness { acc[Lane.chromatic] += 1 }
                                                acc[Lane.chromaSum] += Double(chroma)
                                                acc[Lane.chromaSquares] += Double(chroma * chroma)
                                                var a = hor.value[i], b = ver.value[i]
                                                let total = a.w + b.w
                                                a.w = 0
                                                b.w = 0
                                                let coherent = (a * a).sum().squareRoot() + (b * b).sum().squareRoot()
                                                if total > textureStep {
                                                    acc[coherent < textureCoherence * total ? Lane.texture : Lane.structure] += 1
                                                }
                                                // A ramp slopes alike at both scales; flat ground next to an
                                                // edge slopes only at the coarse one.
                                                let step = total / 2
                                                if step < rampStep {
                                                    let wide = slope(co.value, x: x, y: y, r: rampRadius)
                                                    if wide >= rampSlope && wide <= rampStep
                                                        && slope(fi.value, x: x, y: y, r: 2) >= rampAgreement * wide {
                                                        acc[Lane.ramp] += 1
                                                    }
                                                }
                                                if weight.value[i] > subjectImportance { acc[Lane.subject] += 1 }
                                                acc[Lane.importance] += Double(weight.value[i])
                                                // Noise: the Laplacian of lightness where the photo is flat or
                                                // gently sloped at a scale of a few pixels (texture slopes there).
                                                if x > 0, y > 0, x < w - 1, y < h - 1,
                                                   slope(fi.value, x: x, y: y, r: 2) < rampStep {
                                                    let l = lab.value
                                                    let laplacian = abs(4 * v.x - l[i - 1].x - l[i + 1].x - l[i - w].x - l[i + w].x)
                                                    bins[min(Int(laplacian / noiseBin), noiseBins - 1)] += 1
                                                }
                                            }
                                            for k in 0..<lanes { out.value[c * lanes + k] = acc[k] }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        try cancel.throwIfCancelled()
        var total = [Double](repeating: 0, count: lanes)
        var histogram = [Int](repeating: 0, count: noiseBins)
        for c in 0..<chunks {
            for k in 0..<lanes { total[k] += sums[c * lanes + k] }
            for b in 0..<noiseBins { histogram[b] += Int(histograms[c * noiseBins + b]) }
        }
        let count = Double(max(n, 1))
        let meanChroma = total[Lane.chromaSum] / count
        let chromaVariance = max(total[Lane.chromaSquares] / count - meanChroma * meanChroma, 0)
        let noise = noiseSigma(histogram: histogram)

        let hints = hints ?? SubjectHints()
        return PhotoAnalysis(
            sourceWidth: source.width, sourceHeight: source.height,
            paletteCurve: curve.map { quantized($0, places: curvePlaces) },
            chromaticFraction: quantized(Float(total[Lane.chromatic] / count)),
            chromaSpread: quantized(Float(chromaVariance.squareRoot())),
            structureDensity: quantized(Float(total[Lane.structure] / count)),
            textureFraction: quantized(Float(total[Lane.texture] / count)),
            smoothFraction: quantized(Float(total[Lane.ramp] / count)),
            noise: quantized(noise, places: 4),
            subjectCoverage: quantized(Float(total[Lane.subject] / count)),
            importanceEntropy: quantized(entropy(working.weights, width: w, height: h)),
            meanImportance: quantized(Float(total[Lane.importance] / count)),
            faceCoverage: quantized(min(hints.faces.reduce(0) { $0 + $1.clippedArea }, 1)),
            animalCoverage: quantized(min(hints.animals.reduce(0) { $0 + $1.clippedArea }, 1)))
    }

    /// The noise σ of a histogram of absolute Laplacians (`noiseBins` bins of `noiseBin`): the
    /// median absolute Laplacian → σ (for Gaussian noise the 4-neighbour Laplacian has σ·√20,
    /// and its median absolute value is 0.6745 of that); 0 when nothing was counted.
    static func noiseSigma(histogram: [Int]) -> Float {
        var noise: Float = 0
        let samples = histogram.reduce(0, +)
        if samples > 0 {
            var cumulative = 0
            for b in 0..<noiseBins {
                cumulative += histogram[b]
                if 2 * cumulative >= samples {
                    noise = (Float(b) + 0.5) * noiseBin / (0.6745 * Float(20).squareRoot())
                    break
                }
            }
        }
        return noise
    }

    /// Features are stored and compared at `places` decimals, so tiny floating-point
    /// differences between devices cannot flip a decision.
    @inline(__always)
    static func quantized(_ value: Float, places: Int = 3) -> Float {
        guard value.isFinite else { return 0 }
        let scale = Float(pow(10, Double(places)))
        return (value * scale).rounded() / scale
    }

    /// Weighted mean ΔE (true OKLab) of the palette histogram's samples to their nearest of k
    /// paints, for each k of `AutoSettings.paletteCurveKs`: the pipeline's histogram and
    /// k-means++ seeding (seeded per k), plain Lloyd iterations.
    static func paletteCurve(_ working: AutoWorking, cancel: CancellationCheck) throws -> [Float] {
        let p = working.parameters
        let samples = try PaletteBuilder.histogram(
            colors: working.lab, importance: working.weights, gamma: p.histogramGamma, chromaScale: p.chromaScale,
            saliency: p.paletteSaliency)
        let ks = AutoSettings.paletteCurveKs
        guard !samples.colors.isEmpty else { return ks.map { _ in 0 } }
        let metric = SIMD3<Float>(1, 1 / p.chromaScale, 1 / p.chromaScale)
        let free = PaletteBuilder.Separation(minDistance: 0, metric: metric)
        let errors = Parallel.mapBands(ks.count) { range in
            range.map { index -> Float in
                if cancel.isCancelled { return 0 }
                let k = min(ks[index], samples.colors.count)
                var rng = SplitMix64(seed: p.seed &+ UInt64(ks[index]))
                let seeds = PaletteBuilder.seedPlusPlus(samples, k: k, rng: &rng)
                let centers = PaletteBuilder.lloyd(samples, centers: seeds, iterations: curveIterations, separation: free)
                var error = 0.0, weight = 0.0
                for i in 0..<samples.colors.count {
                    var best = Float.infinity
                    for c in centers { best = min(best, free.distanceSquared(samples.colors[i], c)) }
                    error += Double(samples.weights[i]) * Double(best.squareRoot())
                    weight += Double(samples.weights[i])
                }
                return weight > 0 ? Float(error / weight) : 0
            }
        }.flatMap { $0 }
        try cancel.throwIfCancelled()
        return errors
    }

    /// How widely the importance mass spreads over a grid of cells: the share of cells it
    /// effectively covers (exp of its Shannon entropy over the cell count), 1 when it is
    /// spread evenly, toward 0 when it sits in one spot. The mass is each cell's mean above
    /// the least important cell's: every importance map has a floor (the fallback's is 0.2,
    /// and its busy-or-central terms add at most 0.8), and counting the floor rated every
    /// corpus photo 0.986–0.999 as normalized entropy. Normalized entropy without the floor
    /// still only spanned 0.95–0.99 (a logarithm of 1024 cells); the covered share spreads
    /// the same photos over 0.72–0.96.
    static func entropy(_ weights: [Float], width w: Int, height h: Int) -> Float {
        let cellsX = min(entropyCells, w), cellsY = min(entropyCells, h)
        guard cellsX * cellsY > 1 else { return 1 }
        var mass = [Double](repeating: 0, count: cellsX * cellsY)
        var area = [Int](repeating: 0, count: cellsX * cellsY)
        for y in 0..<h {
            let cy = y * cellsY / h
            for x in 0..<w {
                let cell = cy * cellsX + x * cellsX / w
                mass[cell] += Double(weights[y * w + x])
                area[cell] += 1
            }
        }
        for c in mass.indices { mass[c] /= Double(max(area[c], 1)) }
        let floor = mass.min() ?? 0
        for c in mass.indices { mass[c] -= floor }
        let total = mass.reduce(0, +)
        guard total > 1e-6 else { return 1 }
        var entropy = 0.0
        for m in mass where m > 0 {
            let q = m / total
            entropy -= q * log(q)
        }
        return Float(exp(entropy) / Double(mass.count))
    }
}
