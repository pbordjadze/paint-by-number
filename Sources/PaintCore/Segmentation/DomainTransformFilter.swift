import Foundation

/// Edge-preserving smoothing with the recursive-filter domain transform (Gastal & Oliveira,
/// "Domain Transform for Edge-Aware Image and Video Processing", 2011).
///
/// Cost is O(pixels) independent of the spatial sigma, so wide supports that flatten
/// texture (skin pores, foliage, fabric weave) into painterly patches are as cheap as
/// narrow ones, while color edges stop the diffusion.
enum DomainTransformFilter {

    /// - Parameters:
    ///   - sigmaSpatial: Spatial standard deviation in pixels.
    ///   - sigmaRange: Range standard deviation in OKLab units.
    ///   - edgeScale: Optional per-pixel factors (0...1) on the horizontal and vertical
    ///     gradient terms; below 1 the filter smooths across that gradient more freely.
    ///   - stiffness: Optional per-pixel factor `1 + sharpening · importance` (≥ 1)
    ///     stretching the domain there, which shrinks the effective spatial sigma (used to
    ///     keep detail in important areas).
    static func filter(
        _ input: Grid<SIMD4<Float>>,
        sigmaSpatial: Float,
        sigmaRange: Float,
        iterations: Int,
        edgeScale: (horizontal: [Float], vertical: [Float])? = nil,
        stiffness: (importance: [Float], sharpening: Float)? = nil,
        cancel: CancellationCheck
    ) throws -> Grid<SIMD4<Float>> {
        let w = input.width, h = input.height, n = w * h
        guard n > 1, sigmaSpatial > 0.1, sigmaRange > 0, iterations > 0 else { return input }
        let ratio = sigmaSpatial / sigmaRange

        // Domain-transform derivatives: 1 + σs/σr·|∇I| along each axis (index = pixel whose
        // left/upper neighbour the step comes from), with the optional scales applied.
        // Fresh buffers are written in waves below (no up-front fill), so the filter stays
        // cancellable at large sizes.
        var dH = [Float](uninitializedCount: n)
        var dV = [Float](uninitializedCount: n)
        var out = [SIMD4<Float>](uninitializedCount: n)
        let noScale: [Float] = []
        let eh = edgeScale?.horizontal ?? noScale, ev = edgeScale?.vertical ?? noScale
        let st = stiffness?.importance ?? noScale, sharpening = stiffness?.sharpening ?? 0
        let scaled = edgeScale != nil, stiff = stiffness != nil
        let waveRows = Parallel.waveRows(width: w)
        try input.storage.withUnsafeBufferPointer { g in
            try out.withUnsafeMutableBufferPointer { ob in
                let copy = UncheckedSendable(ob.baseAddress!)
                try dH.withUnsafeMutableBufferPointer { dh in
                    try dV.withUnsafeMutableBufferPointer { dv in
                        try eh.withUnsafeBufferPointer { ehb in
                            try ev.withUnsafeBufferPointer { evb in
                                try st.withUnsafeBufferPointer { sb in
                                    let gp = UncheckedSendable(g.baseAddress!)
                                    let hp = UncheckedSendable(dh.baseAddress!)
                                    let vp = UncheckedSendable(dv.baseAddress!)
                                    let ehp = UncheckedSendable(ehb), evp = UncheckedSendable(evb), sp = UncheckedSendable(sb)
                                    try Parallel.forEachBand(h, minimumBandSize: 8, wave: waveRows, cancel: cancel) { rows in
                                        for y in rows {
                                            let row = y * w
                                            (copy.value + row).initialize(from: gp.value + row, count: w)
                                            hp.value[row] = 1
                                            if y == 0 { for x in 0..<w { vp.value[x] = 1 } }
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
                                            if scaled {
                                                for i in row..<(row + w) {
                                                    hp.value[i] = 1 + (hp.value[i] - 1) * ehp.value[i]
                                                    vp.value[i] = 1 + (vp.value[i] - 1) * evp.value[i]
                                                }
                                            }
                                            if stiff {
                                                for i in row..<(row + w) {
                                                    let factor = 1 + sharpening * sp.value[i]
                                                    hp.value[i] *= factor
                                                    vp.value[i] *= factor
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var weights = [Float](uninitializedCount: n)
        let count = Float(iterations)
        for i in 0..<iterations {
            try cancel.throwIfCancelled()
            // Per-iteration sigma so the cascade's total variance equals σs² (eq. 14).
            let sigmaI = sigmaSpatial * Float(3).squareRoot() * exp2(count - Float(i) - 1)
                / (exp2(2 * count) - 1).squareRoot()
            let logA = -Float(2).squareRoot() / sigmaI

            try computeWeights(dH, logA: logA, into: &weights, cancel: cancel)
            try out.withUnsafeMutableBufferPointer { o in
                try weights.withUnsafeBufferPointer { wt in
                    let op = UncheckedSendable(o.baseAddress!)
                    let wp = UncheckedSendable(wt.baseAddress!)
                    try Parallel.forEachBand(h, minimumBandSize: 8, wave: waveRows, cancel: cancel) { rows in
                        // Each row is a serial recursion; four rows side by side keep the
                        // pipeline busy.
                        var y = rows.lowerBound
                        while y + 4 <= rows.upperBound {
                            let r0 = op.value + y * w, r1 = r0 + w, r2 = r1 + w, r3 = r2 + w
                            let w0 = wp.value + y * w, w1 = w0 + w, w2 = w1 + w, w3 = w2 + w
                            var x = 1
                            while x < w {
                                r0[x] += w0[x] * (r0[x - 1] - r0[x])
                                r1[x] += w1[x] * (r1[x - 1] - r1[x])
                                r2[x] += w2[x] * (r2[x - 1] - r2[x])
                                r3[x] += w3[x] * (r3[x - 1] - r3[x])
                                x += 1
                            }
                            x = w - 2
                            while x >= 0 {
                                r0[x] += w0[x + 1] * (r0[x + 1] - r0[x])
                                r1[x] += w1[x + 1] * (r1[x + 1] - r1[x])
                                r2[x] += w2[x + 1] * (r2[x + 1] - r2[x])
                                r3[x] += w3[x + 1] * (r3[x + 1] - r3[x])
                                x -= 1
                            }
                            y += 4
                        }
                        while y < rows.upperBound {
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
                            y += 1
                        }
                    }
                }
            }

            try cancel.throwIfCancelled()
            try computeWeights(dV, logA: logA, into: &weights, cancel: cancel)
            try out.withUnsafeMutableBufferPointer { o in
                try weights.withUnsafeBufferPointer { wt in
                    let op = UncheckedSendable(o.baseAddress!)
                    let wp = UncheckedSendable(wt.baseAddress!)
                    // Columns are independent; sweeping whole rows of a column band keeps
                    // memory access sequential. Rows go in waves for cancellation.
                    var y0 = 1
                    while y0 < h {
                        let y1 = min(h, y0 + waveRows)
                        Parallel.forEachBand(w, minimumBandSize: 32) { cols in
                            for y in y0..<y1 {
                                let cur = op.value + y * w, prev = cur - w, wr = wp.value + y * w
                                for x in cols { cur[x] += wr[x] * (prev[x] - cur[x]) }
                            }
                        }
                        y0 = y1
                        try cancel.throwIfCancelled()
                    }
                    var y1 = h - 1
                    while y1 > 0 {
                        let y0 = max(0, y1 - waveRows)
                        Parallel.forEachBand(w, minimumBandSize: 32) { cols in
                            for y in stride(from: y1 - 1, through: y0, by: -1) {
                                let cur = op.value + y * w, next = cur + w, wr = wp.value + (y + 1) * w
                                for x in cols { cur[x] += wr[x] * (next[x] - cur[x]) }
                            }
                        }
                        y1 = y0
                        if y1 > 0 { try cancel.throwIfCancelled() }
                    }
                }
            }
        }
        return Grid(width: w, height: h, storage: out)
    }

    private static func computeWeights(_ d: [Float], logA: Float, into weights: inout [Float], cancel: CancellationCheck) throws {
        let n = d.count
        try d.withUnsafeBufferPointer { src in
            try weights.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let o = UncheckedSendable(dst.baseAddress!)
                try Parallel.forEachBand(n, minimumBandSize: 16_384, wave: Parallel.wavePixels, cancel: cancel) { range in
                    for i in range { o.value[i] = exp(logA * s.value[i]) }
                }
            }
        }
    }
}
