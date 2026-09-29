import Foundation

/// Removal of hair-thin region parts (tendrils, necks, 1-px slivers along edges).
///
/// A morphological opening per region with a `k`×`k` square decides what is thin: pixels
/// not covered by any such square lying entirely inside their region are handed to the
/// neighbouring paint that dominates their 8-neighbourhood (color breaks ties). Updates run
/// in four interleaved phases so each pixel sees its neighbours' new values, which keeps the
/// result coherent (no saw-tooth) and independent of thread count.
enum ThinPartRemoval {

    /// One strong pass (uncovered pixels must leave their paint) followed by settling passes
    /// (uncovered pixels move only to a paint with strictly more neighbour support). Settling
    /// strictly lowers the number of unlike neighbour pairs, so it converges; where several
    /// regions meet at a sharp corner and a pixel is uncovered whatever its paint, it simply
    /// returns to a stable choice. A uniform square of one paint always lies inside a single
    /// region, so coverage is computed on the paint map directly.
    /// Returns the number of pixels whose paint differs from before.
    static func apply(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: [SIMD4<Float>],
        palette: [SIMD3<Float>],
        size k: Int,
        maxPasses: Int
    ) -> Int {
        guard k >= 2, w >= k, h >= k else { return 0 }
        let packed = palette.map { SIMD4($0, 0) }
        let before = classes
        var changed = pass(classes: &classes, width: w, height: h, colors: colors, palette: packed, size: k, strong: true)
        guard changed > 0 else { return 0 }
        for _ in 1..<max(2, maxPasses) {
            changed = pass(classes: &classes, width: w, height: h, colors: colors, palette: packed, size: k, strong: false)
            if changed == 0 { break }
        }
        // Moves that left the pixel uncovered did not help (typically a corner where
        // several regions meet); undo them so repeated calls reach a fixed point.
        let covered = coverage(labels: classes, width: w, height: h, size: k)
        var net = 0
        for i in 0..<classes.count where classes[i] != before[i] {
            if covered[i] == 0 { classes[i] = before[i] } else { net += 1 }
        }
        return net
    }

    private static func pass(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: [SIMD4<Float>],
        palette packed: [SIMD4<Float>],
        size k: Int,
        strong: Bool
    ) -> Int {
        let covered = coverage(labels: classes, width: w, height: h, size: k)
        var total = 0
        for phase in 0..<4 {
            let px = phase & 1, py = phase >> 1
            let rowCount = (h - py + 1) / 2
            let counts: [Int] = classes.withUnsafeMutableBufferPointer { cb in
                covered.withUnsafeBufferPointer { vb in
                    colors.withUnsafeBufferPointer { colb in
                        packed.withUnsafeBufferPointer { pb in
                            let c = UncheckedSendable(cb.baseAddress!)
                            let v = UncheckedSendable(vb.baseAddress!)
                            let col = UncheckedSendable(colb.baseAddress!)
                            let pal = UncheckedSendable(pb.baseAddress!)
                            return Parallel.mapBands(rowCount, minimumBandSize: 8) { rows -> Int in
                                var changed = 0
                                for r in rows {
                                    let y = 2 * r + py
                                    var x = px
                                    while x < w {
                                        let i = y * w + x
                                        if v.value[i] == 0 {
                                            let best = dominantNeighbourClass(
                                                i, x: x, y: y, w: w, h: h, classes: c.value,
                                                color: col.value[i], palette: pal.value, includeOwn: !strong)
                                            if best != c.value[i] {
                                                c.value[i] = best
                                                changed += 1
                                            }
                                        }
                                        x += 2
                                    }
                                }
                                return changed
                            }
                        }
                    }
                }
            }
            total += counts.reduce(0, +)
        }
        return total
    }

    /// 1 where a `k`×`k` square of equal labels contains the pixel, else 0.
    static func coverage(labels: [UInt32], width w: Int, height h: Int, size k: Int) -> [UInt8] {
        let n = w * h
        var run = [UInt8](repeating: 1, count: n)  // equal-label run to the right, capped at k
        var anchor = [UInt8](repeating: 0, count: n)  // top-left corners of uniform squares
        var horizontal = [UInt8](repeating: 0, count: n)
        var covered = [UInt8](repeating: 0, count: n)
        labels.withUnsafeBufferPointer { lb in
            run.withUnsafeMutableBufferPointer { rb in
                anchor.withUnsafeMutableBufferPointer { ab in
                    horizontal.withUnsafeMutableBufferPointer { hb in
                        covered.withUnsafeMutableBufferPointer { cb in
                            let l = UncheckedSendable(lb.baseAddress!)
                            let rp = UncheckedSendable(rb.baseAddress!)
                            let ap = UncheckedSendable(ab.baseAddress!)
                            let hp = UncheckedSendable(hb.baseAddress!)
                            let cp = UncheckedSendable(cb.baseAddress!)
                            let cap = UInt8(k)
                            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = y * w
                                    var x = w - 2
                                    while x >= 0 {
                                        let i = row + x
                                        if l.value[i] == l.value[i + 1] { rp.value[i] = min(cap, rp.value[i + 1] + 1) }
                                        x -= 1
                                    }
                                }
                            }
                            Parallel.forEachBand(h - k + 1, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = y * w
                                    for x in 0...(w - k) {
                                        let i = row + x
                                        let label = l.value[i]
                                        var uniform = true
                                        var j = i
                                        for _ in 0..<k {
                                            if rp.value[j] < cap || l.value[j] != label { uniform = false; break }
                                            j += w
                                        }
                                        if uniform { ap.value[i] = 1 }
                                    }
                                }
                            }
                            // Dilate the anchors by the square (separable OR).
                            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = y * w
                                    for x in 0..<w {
                                        var v: UInt8 = 0
                                        var dx = 0
                                        while dx < k && dx <= x { v |= ap.value[row + x - dx]; dx += 1 }
                                        hp.value[row + x] = v
                                    }
                                }
                            }
                            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = y * w
                                    for x in 0..<w {
                                        var v: UInt8 = 0
                                        var dy = 0
                                        while dy < k && dy <= y { v |= hp.value[row - dy * w + x]; dy += 1 }
                                        cp.value[row + x] = v
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return covered
    }

    /// The paint with the most weight among the 8 neighbours (edge neighbours 1, corners
    /// 0.7). Without `includeOwn` the pixel's own paint is excluded and near-ties go to the
    /// paint closest to `color`; with it, the own paint is kept unless another strictly wins.
    @inline(__always)
    static func dominantNeighbourClass(
        _ i: Int, x: Int, y: Int, w: Int, h: Int,
        classes: UnsafeMutablePointer<UInt32>,
        color: SIMD4<Float>, palette: UnsafePointer<SIMD4<Float>>,
        includeOwn: Bool
    ) -> UInt32 {
        let own = classes[i]
        var ownWeight: Float = 0
        var cand = SIMD8<UInt32>(repeating: 0)
        var wts = SIMD8<Float>(repeating: 0)
        var count = 0
        @inline(__always) func add(_ j: Int, _ weight: Float) {
            let c = classes[j]
            if c == own { ownWeight += weight; return }
            for m in 0..<count where cand[m] == c {
                wts[m] += weight
                return
            }
            cand[count] = c
            wts[count] = weight
            count += 1
        }
        let left = x > 0, right = x + 1 < w, up = y > 0, down = y + 1 < h
        if left { add(i - 1, 1) }
        if right { add(i + 1, 1) }
        if up { add(i - w, 1) }
        if down { add(i + w, 1) }
        if left && up { add(i - w - 1, 0.7) }
        if right && up { add(i - w + 1, 0.7) }
        if left && down { add(i + w - 1, 0.7) }
        if right && down { add(i + w + 1, 0.7) }
        guard count > 0 else { return own }
        if includeOwn {
            var best = own
            var bestWeight = ownWeight + 0.05
            for m in 0..<count where wts[m] > bestWeight {
                best = cand[m]
                bestWeight = wts[m]
            }
            return best
        }
        var best = 0
        var bestD = Float.infinity
        for m in 0..<count {
            let e = color - palette[Int(cand[m])]
            let d = (e * e).sum()
            if wts[m] > wts[best] + 0.05 || (abs(wts[m] - wts[best]) <= 0.05 && d < bestD) {
                best = m
                bestD = d
            }
        }
        return cand[best]
    }
}
