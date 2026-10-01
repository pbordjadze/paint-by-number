import Foundation

/// The draft photo at the working size the candidates are segmented at, with what analysis
/// and scoring read from it: the pipeline's own OKLab (chroma stretched) and importance
/// weights, so Auto measures what the pipeline sees.
struct AutoWorking {
    let image: RGBAImage
    let parameters: SegmentationParameters
    let lab: Grid<SIMD4<Float>>
    let weights: [Float]

    /// The draft enlarged (or reduced) to the working size `settings` give it, as the
    /// generator does.
    init(draft: RGBAImage, settings: GenerationSettings, importance: Grid<Float>?, cancel: CancellationCheck) throws {
        let size = settings.workingSize(sourceWidth: draft.width, sourceHeight: draft.height)
        try self.init(
            working: Resample.area(draft, width: size.width, height: size.height, cancel: cancel), importance: importance,
            cancel: cancel)
    }

    /// An image already at its working size. The fields read here (chroma scale, structure
    /// radius, histogram knobs, seed) depend only on the size, not on the settings.
    init(working: RGBAImage, importance: Grid<Float>?, cancel: CancellationCheck) throws {
        image = working
        parameters = SegmentationParameters(settings: GenerationSettings(), width: working.width, height: working.height)
        lab = try WorkingImage.okLab(image, chromaScale: parameters.chromaScale, cancel: cancel)
        let structure = try StructureMap(lab, radius: parameters.structureRadius, cancel: cancel)
        weights = try ImportanceMap.make(importance, structure: structure, cancel: cancel)
    }
}

/// Photo features for the candidate rule (`AutoSettings.analyze`). Thresholds are in the
/// pipeline's working space (OKLab with chroma × `chromaScale`) and per working pixel; they
/// are starting values (see `docs/wave2/01-suggested-settings.md`).
enum PhotoAnalyzer {
    /// Paint-count curve: Lloyd iterations per k after k-means++ seeding.
    static let curveIterations = 10
    /// A pixel is chromatic above this chroma (true OKLab).
    static let chromaticChroma: Float = 0.04
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
        let lanes = 7
        let noiseBins = 2000, noiseBin: Float = 0.0002
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
                                                if chroma > chromaticChroma { acc[0] += 1 }
                                                acc[1] += Double(chroma)
                                                acc[2] += Double(chroma * chroma)
                                                var a = hor.value[i], b = ver.value[i]
                                                let total = a.w + b.w
                                                a.w = 0
                                                b.w = 0
                                                let coherent = (a * a).sum().squareRoot() + (b * b).sum().squareRoot()
                                                if total > textureStep {
                                                    acc[coherent < textureCoherence * total ? 3 : 4] += 1
                                                }
                                                // A ramp slopes alike at both scales; flat ground next to an
                                                // edge slopes only at the coarse one.
                                                let step = total / 2
                                                if step < rampStep {
                                                    let wide = slope(co.value, x: x, y: y, r: rampRadius)
                                                    if wide >= rampSlope && wide <= rampStep
                                                        && slope(fi.value, x: x, y: y, r: 2) >= rampAgreement * wide {
                                                        acc[5] += 1
                                                    }
                                                }
                                                if weight.value[i] > subjectImportance { acc[6] += 1 }
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
        let meanChroma = total[1] / count
        let chromaVariance = max(total[2] / count - meanChroma * meanChroma, 0)

        // Median absolute Laplacian → noise σ (for Gaussian noise the 4-neighbour Laplacian has
        // σ·√20, and its median absolute value is 0.6745 of that).
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

        let hints = hints ?? SubjectHints()
        return PhotoAnalysis(
            sourceWidth: source.width, sourceHeight: source.height,
            paletteCurve: curve.map(quantized),
            chromaticFraction: quantized(Float(total[0] / count)),
            chromaSpread: quantized(Float(chromaVariance.squareRoot())),
            structureDensity: quantized(Float(total[4] / count)),
            textureFraction: quantized(Float(total[3] / count)),
            smoothFraction: quantized(Float(total[5] / count)),
            noise: quantized(noise),
            subjectCoverage: quantized(Float(total[6] / count)),
            importanceEntropy: quantized(entropy(working.weights, width: w, height: h)),
            faceCoverage: quantized(min(hints.faces.reduce(0) { $0 + $1.clippedArea }, 1)),
            animalCoverage: quantized(min(hints.animals.reduce(0) { $0 + $1.clippedArea }, 1)),
            labels: hints.labels.mapValues(quantized))
    }

    /// Features are stored and compared at 3 decimals, so tiny floating-point differences
    /// between devices cannot flip a decision.
    @inline(__always)
    static func quantized(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return (value * 1000).rounded() / 1000
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

    /// Normalized Shannon entropy of the importance mass over a grid of cells: 1 when it is
    /// spread evenly, toward 0 when it sits in one spot.
    static func entropy(_ weights: [Float], width w: Int, height h: Int) -> Float {
        let cellsX = min(entropyCells, w), cellsY = min(entropyCells, h)
        guard cellsX * cellsY > 1 else { return 1 }
        var mass = [Double](repeating: 0, count: cellsX * cellsY)
        for y in 0..<h {
            let cy = y * cellsY / h
            for x in 0..<w { mass[cy * cellsX + x * cellsX / w] += Double(weights[y * w + x]) }
        }
        let total = mass.reduce(0, +)
        guard total > 0 else { return 1 }
        var entropy = 0.0
        for m in mass where m > 0 {
            let q = m / total
            entropy -= q * log(q)
        }
        return Float(entropy / log(Double(mass.count)))
    }
}
