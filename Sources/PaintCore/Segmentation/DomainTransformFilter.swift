import Foundation

/// Edge-preserving smoothing with the recursive-filter domain transform (Gastal & Oliveira,
/// "Domain Transform for Edge-Aware Image and Video Processing", 2011).
///
/// Cost is O(pixels) independent of the spatial sigma, so wide supports that flatten
/// texture (skin pores, foliage, fabric weave) into painterly patches are as cheap as
/// narrow ones, while color edges stop the diffusion.
enum DomainTransformFilter {

    /// - Parameters:
    ///   - guide: Image whose edges stop the smoothing (usually `input` or a denoised copy).
    ///   - sigmaSpatial: Spatial standard deviation in pixels.
    ///   - sigmaRange: Range standard deviation in OKLab units.
    ///   - stiffness: Optional per-pixel factor (≥ 1) stretching the domain there, which
    ///     shrinks the effective spatial sigma (used to keep detail in important areas).
    static func filter(
        _ input: Grid<SIMD4<Float>>,
        guide: Grid<SIMD4<Float>>,
        sigmaSpatial: Float,
        sigmaRange: Float,
        iterations: Int,
        stiffness: [Float]? = nil,
        cancel: CancellationCheck
    ) throws -> Grid<SIMD4<Float>> {
        let w = input.width, h = input.height, n = w * h
        guard n > 1, sigmaSpatial > 0.1, sigmaRange > 0, iterations > 0 else { return input }
        let ratio = sigmaSpatial / sigmaRange

        // Domain-transform derivatives: 1 + σs/σr·|∇I| along each axis (index = pixel whose
        // left/upper neighbour the step comes from).
        var dH = [Float](repeating: 1, count: n)
        var dV = [Float](repeating: 1, count: n)
        guide.storage.withUnsafeBufferPointer { g in
            dH.withUnsafeMutableBufferPointer { dh in
                dV.withUnsafeMutableBufferPointer { dv in
                    let gp = UncheckedSendable(g.baseAddress!)
                    let hp = UncheckedSendable(dh.baseAddress!)
                    let vp = UncheckedSendable(dv.baseAddress!)
                    Parallel.forEachBand(h, minimumBandSize: 8) { rows in
                        for y in rows {
                            let row = y * w
                            var x = 1
                            while x < w {
                                let d = gp.value[row + x] - gp.value[row + x - 1]
                                hp.value[row + x] = 1 + ratio * (d * d).sum().squareRoot()
                                x += 1
                            }
                            if y > 0 {
                                for x in 0..<w {
                                    let d = gp.value[row + x] - gp.value[row + x - w]
                                    vp.value[row + x] = 1 + ratio * (d * d).sum().squareRoot()
                                }
                            }
                        }
                    }
                    if let stiffness {
                        stiffness.withUnsafeBufferPointer { sb in
                            let sp = UncheckedSendable(sb.baseAddress!)
                            Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                                for i in range {
                                    hp.value[i] *= sp.value[i]
                                    vp.value[i] *= sp.value[i]
                                }
                            }
                        }
                    }
                }
            }
        }

        var out = input.storage
        var weights = [Float](repeating: 0, count: n)
        let count = Float(iterations)
        for i in 0..<iterations {
            try cancel.throwIfCancelled()
            // Per-iteration sigma so the cascade's total variance equals σs² (eq. 14).
            let sigmaI = sigmaSpatial * Float(3).squareRoot() * exp2(count - Float(i) - 1)
                / (exp2(2 * count) - 1).squareRoot()
            let logA = -Float(2).squareRoot() / sigmaI

            computeWeights(dH, logA: logA, into: &weights)
            out.withUnsafeMutableBufferPointer { o in
                weights.withUnsafeBufferPointer { wt in
                    let op = UncheckedSendable(o.baseAddress!)
                    let wp = UncheckedSendable(wt.baseAddress!)
                    Parallel.forEachBand(h, minimumBandSize: 8) { rows in
                        for y in rows {
                            let row = op.value + y * w
                            let wr = wp.value + y * w
                            var x = 1
                            while x < w {
                                row[x] += wr[x] * (row[x - 1] - row[x])
                                x += 1
                            }
                            x = w - 2
                            while x >= 0 {
                                row[x] += wr[x + 1] * (row[x + 1] - row[x])
                                x -= 1
                            }
                        }
                    }
                }
            }

            computeWeights(dV, logA: logA, into: &weights)
            out.withUnsafeMutableBufferPointer { o in
                weights.withUnsafeBufferPointer { wt in
                    let op = UncheckedSendable(o.baseAddress!)
                    let wp = UncheckedSendable(wt.baseAddress!)
                    // Columns are independent; sweeping whole rows of a column band keeps
                    // memory access sequential.
                    Parallel.forEachBand(w, minimumBandSize: 32) { cols in
                        var y = 1
                        while y < h {
                            let cur = op.value + y * w, prev = cur - w, wr = wp.value + y * w
                            for x in cols { cur[x] += wr[x] * (prev[x] - cur[x]) }
                            y += 1
                        }
                        y = h - 2
                        while y >= 0 {
                            let cur = op.value + y * w, next = cur + w, wr = wp.value + (y + 1) * w
                            for x in cols { cur[x] += wr[x] * (next[x] - cur[x]) }
                            y -= 1
                        }
                    }
                }
            }
        }
        return Grid(width: w, height: h, storage: out)
    }

    private static func computeWeights(_ d: [Float], logA: Float, into weights: inout [Float]) {
        let n = d.count
        d.withUnsafeBufferPointer { src in
            weights.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let o = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                    for i in range { o.value[i] = exp(logA * s.value[i]) }
                }
            }
        }
    }
}
