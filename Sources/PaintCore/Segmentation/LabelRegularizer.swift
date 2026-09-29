import Foundation

/// Pixel → palette assignment with a contrast-sensitive Potts prior.
///
/// Nearest-color assignment alone dithers wherever the smoothed image sits between two
/// palette colors (gradients, soft texture). A few sweeps of iterated conditional modes
/// over the energy Σ|c(p) − palette(l_p)|² + λ Σ w_pq [l_p ≠ l_q] straighten band edges and
/// dissolve speckle, while w_pq (small across real color edges) keeps true contours.
enum LabelRegularizer {

    static func assignNearest(_ colors: Grid<SIMD4<Float>>, palette: [SIMD3<Float>]) -> [UInt32] {
        let n = colors.count
        var out = [UInt32](repeating: 0, count: n)
        let packed = palette.map { SIMD4($0, 0) }
        colors.storage.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                packed.withUnsafeBufferPointer { pal in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    let pp = UncheckedSendable(pal.baseAddress!)
                    let k = pal.count
                    Parallel.forEachBand(n, minimumBandSize: 8192) { range in
                        for i in range {
                            let c = s.value[i]
                            var best = 0
                            var bestD = Float.infinity
                            for j in 0..<k {
                                let e = c - pp.value[j]
                                let dd = (e * e).sum()
                                if dd < bestD { bestD = dd; best = j }
                            }
                            d.value[i] = UInt32(best)
                        }
                    }
                }
            }
        }
        return out
    }

    /// Iterated conditional modes over the 8-neighbourhood. Pixels are updated in four
    /// interleaved phases (x mod 2, y mod 2) so no two neighbours change simultaneously,
    /// which keeps the sweep convergent and the result independent of thread count.
    static func regularize(
        _ labels: inout [UInt32],
        colors: Grid<SIMD4<Float>>,
        palette: [SIMD3<Float>],
        strength: Float,
        edgeSigma: Float,
        iterations: Int,
        cancel: CancellationCheck
    ) throws {
        let w = colors.width, h = colors.height
        guard w > 1, h > 1, strength > 0, palette.count > 1 else { return }
        let packed = palette.map { SIMD4($0, 0) }
        let invSigma2 = 1 / (edgeSigma * edgeSigma)
        let diagonal: Float = 0.70710678
        for _ in 0..<iterations {
            try cancel.throwIfCancelled()
            for phase in 0..<4 {
                let px = phase & 1, py = phase >> 1
                let rowCount = (h - py + 1) / 2
                labels.withUnsafeMutableBufferPointer { lb in
                    colors.storage.withUnsafeBufferPointer { cb in
                        packed.withUnsafeBufferPointer { pb in
                            let lp = UncheckedSendable(lb.baseAddress!)
                            let cp = UncheckedSendable(cb.baseAddress!)
                            let pp = UncheckedSendable(pb.baseAddress!)
                            Parallel.forEachBand(rowCount, minimumBandSize: 8) { rows in
                                withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 8) { nl in
                                    withUnsafeTemporaryAllocation(of: Float.self, capacity: 8) { nw in
                                        for r in rows {
                                            let y = r * 2 + py
                                            var x = px
                                            while x < w {
                                                sweepPixel(
                                                    x: x, y: y, w: w, h: h, labels: lp.value, colors: cp.value,
                                                    palette: pp.value, strength: strength, invSigma2: invSigma2,
                                                    diagonal: diagonal, nl: nl.baseAddress!, nw: nw.baseAddress!)
                                                x += 2
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

    @inline(__always)
    private static func sweepPixel(
        x: Int, y: Int, w: Int, h: Int,
        labels: UnsafeMutablePointer<UInt32>, colors: UnsafePointer<SIMD4<Float>>,
        palette: UnsafePointer<SIMD4<Float>>, strength: Float, invSigma2: Float, diagonal: Float,
        nl: UnsafeMutablePointer<UInt32>, nw: UnsafeMutablePointer<Float>
    ) {
        let i = y * w + x
        let current = labels[i]
        // Interior pixels (all 8 neighbours agree) cannot change; most pixels are interior.
        if x > 0 && y > 0 && x + 1 < w && y + 1 < h {
            let up = i - w, down = i + w
            if labels[up - 1] == current && labels[up] == current && labels[up + 1] == current
                && labels[i - 1] == current && labels[i + 1] == current
                && labels[down - 1] == current && labels[down] == current && labels[down + 1] == current {
                return
            }
        }
        let c = colors[i]
        var count = 0
        var differs = false
        // Gather neighbours with contrast-sensitive weights.
        for dy in -1...1 {
            let yy = y + dy
            if yy < 0 || yy >= h { continue }
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let xx = x + dx
                if xx < 0 || xx >= w { continue }
                let j = yy * w + xx
                let l = labels[j]
                if l != current { differs = true }
                let e = c - colors[j]
                let base: Float = (dx != 0 && dy != 0) ? diagonal : 1
                nl[count] = l
                nw[count] = strength * base / (1 + (e * e).sum() * invSigma2)
                count += 1
            }
        }
        guard differs else { return }
        var total: Float = 0
        for k in 0..<count { total += nw[k] }

        @inline(__always) func energy(_ label: UInt32) -> Float {
            let e = c - palette[Int(label)]
            var agree: Float = 0
            for k in 0..<count where nl[k] == label { agree += nw[k] }
            return (e * e).sum() + total - agree
        }

        var best = current
        var bestE = energy(current)
        for k in 0..<count {
            let l = nl[k]
            if l == best || l == current { continue }
            var seen = false
            for m in 0..<k where nl[m] == l { seen = true; break }
            if seen { continue }
            let e = energy(l)
            if e < bestE { bestE = e; best = l }
        }
        labels[i] = best
    }
}
