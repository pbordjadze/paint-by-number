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
        guard !palette.isEmpty else { return out }
        let px = palette.map(\.x), py = palette.map(\.y), pz = palette.map(\.z)
        colors.storage.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let d = UncheckedSendable(dst.baseAddress!)
                let k = palette.count
                Parallel.forEachBand(n, minimumBandSize: 8192) { range in
                    // Eight pixels at a time against one paint; (dx² + dy²) + dz² is exactly the
                    // lane-sequential sum of a SIMD4 difference with a zero fourth lane.
                    var i = range.lowerBound
                    while i + 8 <= range.upperBound {
                        var x = SIMD8<Float>(), y = SIMD8<Float>(), z = SIMD8<Float>()
                        for l in 0..<8 {
                            let c = s.value[i + l]
                            x[l] = c.x; y[l] = c.y; z[l] = c.z
                        }
                        var best = SIMD8<UInt32>(repeating: 0)
                        var bestD = SIMD8<Float>(repeating: .infinity)
                        for j in 0..<k {
                            let dx = x - px[j], dy = y - py[j], dz = z - pz[j]
                            let dd = dx * dx + dy * dy + dz * dz
                            let closer = dd .< bestD
                            bestD.replace(with: dd, where: closer)
                            best.replace(with: UInt32(j), where: closer)
                        }
                        for l in 0..<8 { d.value[i + l] = best[l] }
                        i += 8
                    }
                    while i < range.upperBound {
                        let c = s.value[i]
                        var best = 0
                        var bestD = Float.infinity
                        for j in 0..<k {
                            let dx = c.x - px[j], dy = c.y - py[j], dz = c.z - pz[j]
                            let dd = dx * dx + dy * dy + dz * dz
                            if dd < bestD { bestD = dd; best = j }
                        }
                        d.value[i] = UInt32(best)
                        i += 1
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
        // A pixel's update depends only on its own and its 8 neighbours' labels, and it leaves
        // the pixel at a fixed point of that update. So after the first sweep a pixel is only
        // revisited if something in its 3×3 window changed since its last visit. Steps are
        // numbered sweep × 4 + phase; `changedAt` holds each pixel's last change, `rowChangedAt`
        // the latest change per row.
        var changedAt = [Int16](repeating: -1, count: w * h)
        var rowChangedAt = [Int16](repeating: -1, count: h)
        for sweep in 0..<iterations {
            try cancel.throwIfCancelled()
            for phase in 0..<4 {
                let px = phase & 1, py = phase >> 1
                let rowCount = (h - py + 1) / 2
                let step = Int16(sweep * 4 + phase)
                let lastVisit = step - 4
                labels.withUnsafeMutableBufferPointer { lb in
                    colors.storage.withUnsafeBufferPointer { cb in
                        packed.withUnsafeBufferPointer { pb in
                            changedAt.withUnsafeMutableBufferPointer { chb in
                                rowChangedAt.withUnsafeMutableBufferPointer { rcb in
                                    let lp = UncheckedSendable(lb.baseAddress!)
                                    let cp = UncheckedSendable(cb.baseAddress!)
                                    let pp = UncheckedSendable(pb.baseAddress!)
                                    let ch = UncheckedSendable(chb.baseAddress!)
                                    let rc = UncheckedSendable(rcb.baseAddress!)
                                    Parallel.forEachBand(rowCount, minimumBandSize: 8) { rows in
                                        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 8) { nl in
                                            withUnsafeTemporaryAllocation(of: Float.self, capacity: 8) { nw in
                                                for r in rows {
                                                    let y = r * 2 + py
                                                    let y0 = max(y - 1, 0), y1 = min(y + 1, h - 1)
                                                    if sweep > 0 {
                                                        var latest = rc.value[y0]
                                                        for yy in y0...y1 { latest = max(latest, rc.value[yy]) }
                                                        if latest <= lastVisit { continue }
                                                    }
                                                    var x = px
                                                    while x < w {
                                                        if sweep > 0 {
                                                            let x0 = max(x - 1, 0), x1 = min(x + 1, w - 1)
                                                            var latest: Int16 = -1
                                                            for yy in y0...y1 {
                                                                let row = ch.value + yy * w
                                                                for xx in x0...x1 { latest = max(latest, row[xx]) }
                                                            }
                                                            if latest <= lastVisit { x += 2; continue }
                                                        }
                                                        if sweepPixel(
                                                            x: x, y: y, w: w, h: h, labels: lp.value, colors: cp.value,
                                                            palette: pp.value, strength: strength, invSigma2: invSigma2,
                                                            diagonal: diagonal, nl: nl.baseAddress!, nw: nw.baseAddress!) {
                                                            ch.value[y * w + x] = step
                                                            rc.value[y] = step
                                                        }
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
        }
    }

    @inline(__always)
    private static func sweepPixel(
        x: Int, y: Int, w: Int, h: Int,
        labels: UnsafeMutablePointer<UInt32>, colors: UnsafePointer<SIMD4<Float>>,
        palette: UnsafePointer<SIMD4<Float>>, strength: Float, invSigma2: Float, diagonal: Float,
        nl: UnsafeMutablePointer<UInt32>, nw: UnsafeMutablePointer<Float>
    ) -> Bool {
        let i = y * w + x
        let current = labels[i]
        // Interior pixels (all 8 neighbours agree) cannot change; most pixels are interior.
        if x > 0 && y > 0 && x + 1 < w && y + 1 < h {
            let up = i - w, down = i + w
            if labels[up - 1] == current && labels[up] == current && labels[up + 1] == current
                && labels[i - 1] == current && labels[i + 1] == current
                && labels[down - 1] == current && labels[down] == current && labels[down + 1] == current {
                return false
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
        guard differs else { return false }
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
        return best != current
    }
}
