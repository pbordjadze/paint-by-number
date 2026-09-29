import Foundation

/// Removal of hair-thin region parts (tendrils, necks, 1-px slivers along edges) and of
/// sharp pixel corners.
///
/// A morphological opening per region with a small disc decides what is thin: pixels not
/// covered by any disc lying entirely inside their region are handed to the neighbouring
/// paint that dominates their 8-neighbourhood (color breaks ties). A disc (rather than a
/// square) also clips the corners of blocky shapes, so texture crumbs come out rounded
/// instead of as pixel squares. Updates run in four interleaved phases so each pixel sees its
/// neighbours' new values, which keeps the result coherent (no saw-tooth) and independent of
/// thread count.
enum ThinPartRemoval {

    /// One strong pass (uncovered pixels must leave their paint) followed by settling passes
    /// (uncovered pixels move only to a paint with strictly more neighbour support). Settling
    /// strictly lowers the number of unlike neighbour pairs, so it converges; where several
    /// regions meet at a sharp corner and a pixel is uncovered whatever its paint, it simply
    /// returns to a stable choice. A uniform disc of one paint always lies inside a single
    /// region, so coverage is computed on the paint map directly.
    /// - Parameter radiusSquared: The structuring element is every offset with
    ///   dx² + dy² ≤ radiusSquared (1: cross, 2: 3×3 square, 5: 5×5 without corners).
    /// - Returns: The number of pixels whose paint differs from before.
    static func apply(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: [SIMD4<Float>],
        palette: [SIMD3<Float>],
        radiusSquared: Int,
        maxPasses: Int
    ) -> Int {
        let element = StructuringElement(radiusSquared: radiusSquared)
        guard element.radius > 0, w > 2 * element.radius, h > 2 * element.radius else { return 0 }
        let packed = palette.map { SIMD4($0, 0) }
        var candidates = uncoveredPixels(labels: classes, width: w, height: h, element: element)
        guard !candidates.isEmpty else { return 0 }

        // Only pixels near a change can change coverage, so after the first full pass the
        // work is usually local to the (few) uncovered pixels and their surroundings.
        let n = w * h
        var touched: [(pixel: Int, before: UInt32)] = []
        var mark = [UInt8](repeating: 0, count: n)  // bit 0: touched, bit 1: queued
        let reach = max(2 * element.radius, 2)
        let rows = RowDivider(width: w)
        var changes = process(candidates, classes: &classes, w: w, h: h, colors: colors, palette: packed, strong: true)
        func record() {
            for (i, old) in changes where mark[i] & 1 == 0 {
                mark[i] |= 1
                touched.append((i, old))
            }
        }
        record()
        var passes = 1
        while !changes.isEmpty && passes < maxPasses {
            // Both ways find exactly the uncovered pixels; a full scan is cheaper for many changes.
            if changes.count * (2 * reach + 1) * (2 * reach + 1) > n / 16 {
                candidates = uncoveredPixels(labels: classes, width: w, height: h, element: element)
            } else {
                var next: [Int] = []
                for i in candidates where mark[i] & 2 == 0 {
                    mark[i] |= 2
                    next.append(i)
                }
                for (i, _) in changes {
                    let y = rows.row(i), x = i - y * w
                    for yy in max(0, y - reach)...min(h - 1, y + reach) {
                        for xx in max(0, x - reach)...min(w - 1, x + reach) {
                            let j = yy * w + xx
                            if mark[j] & 2 == 0 {
                                mark[j] |= 2
                                next.append(j)
                            }
                        }
                    }
                }
                for i in next { mark[i] &= 1 }
                next.sort()
                candidates = filter(next, classes: classes, w: w, h: h) { i, labels in
                    !isCovered(i, rows: rows, h: h, labels: labels, element: element)
                }
            }
            changes = process(candidates, classes: &classes, w: w, h: h, colors: colors, palette: packed, strong: false)
            record()
            passes += 1
        }

        // Moves that left the pixel uncovered did not help (typically a corner where
        // several regions meet); undo them so repeated calls reach a fixed point. Undoing
        // one move can un-cover a neighbour's, hence the loop.
        touched.sort { $0.pixel < $1.pixel }
        let pixels = touched.map(\.pixel)
        let original = touched.map(\.before)
        // Positions in `pixels` to examine: all at first, then only those near a revert
        // (nothing else can have changed coverage).
        var check: [Int]? = nil
        var net = 0
        for _ in 0..<4 {
            let revert: [Int]
            if check == nil && pixels.count > n / 64 {
                // Many moves: one full coverage scan beats per-pixel checks.
                let open = uncoveredPixels(labels: classes, width: w, height: h, element: element)
                var list: [Int] = []
                var q = 0
                for k in pixels.indices {
                    while q < open.count && open[q] < pixels[k] { q += 1 }
                    if q < open.count && open[q] == pixels[k] && classes[pixels[k]] != original[k] { list.append(k) }
                }
                revert = list
            } else {
                let positions = check ?? Array(pixels.indices)
                revert = classes.withUnsafeBufferPointer { cb in
                    let l = UncheckedSendable(cb.baseAddress!)
                    return Parallel.mapBands(positions.count, minimumBandSize: 1024) { range -> [Int] in
                        var out: [Int] = []
                        for q in range {
                            let k = positions[q]
                            if l.value[pixels[k]] != original[k]
                                && !isCovered(pixels[k], rows: rows, h: h, labels: l.value, element: element) {
                                out.append(k)
                            }
                        }
                        return out
                    }.flatMap { $0 }
                }
            }
            for k in revert { classes[pixels[k]] = original[k] }
            net = 0
            for k in pixels.indices where classes[pixels[k]] != original[k] { net += 1 }
            if revert.isEmpty { break }
            for k in revert {
                let i = pixels[k]
                let y = rows.row(i), x = i - y * w
                for yy in max(0, y - reach)...min(h - 1, y + reach) {
                    for xx in max(0, x - reach)...min(w - 1, x + reach) { mark[yy * w + xx] |= 2 }
                }
            }
            check = pixels.indices.filter { mark[pixels[$0]] & 2 != 0 }
            for k in revert {
                let i = pixels[k]
                let y = rows.row(i), x = i - y * w
                for yy in max(0, y - reach)...min(h - 1, y + reach) {
                    for xx in max(0, x - reach)...min(w - 1, x + reach) { mark[yy * w + xx] &= 1 }
                }
            }
        }
        return net
    }

    /// `pixels` (ascending) that satisfy `keep`, evaluated in parallel on the current paint map.
    private static func filter(
        _ pixels: [Int], classes: [UInt32], w: Int, h: Int, _ keep: (Int, UnsafePointer<UInt32>) -> Bool
    ) -> [Int] {
        classes.withUnsafeBufferPointer { cb in
            pixels.withUnsafeBufferPointer { pb in
                let l = UncheckedSendable(cb.baseAddress!)
                return Parallel.mapBands(pb.count, minimumBandSize: 1024) { range -> [Int] in
                    var out: [Int] = []
                    for k in range where keep(pb[k], l.value) { out.append(pb[k]) }
                    return out
                }.flatMap { $0 }
            }
        }
    }

    struct StructuringElement {
        let radius: Int
        /// Offsets (dx, dy) of the disc.
        let offsets: [(Int, Int)]

        init(radiusSquared: Int) {
            let r = Int(Double(max(radiusSquared, 0)).squareRoot())
            radius = r
            var list: [(Int, Int)] = []
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= radiusSquared { list.append((dx, dy)) }
            }
            offsets = list
        }
    }

    /// Coverage of a single pixel (same definition as `uncoveredPixels`).
    @inline(__always)
    static func isCovered(_ i: Int, rows: RowDivider, h: Int, labels: UnsafePointer<UInt32>, element: StructuringElement) -> Bool {
        let w = rows.width
        let y = rows.row(i), x = i - y * w
        let label = labels[i]
        @inline(__always) func uniformSquare(_ ax: Int, _ ay: Int) -> Bool {
            if ax < 0 || ay < 0 || ax + 1 >= w || ay + 1 >= h { return false }
            let a = ay * w + ax
            return labels[a] == label && labels[a + 1] == label && labels[a + w] == label && labels[a + w + 1] == label
        }
        guard uniformSquare(x, y) || uniformSquare(x - 1, y) || uniformSquare(x, y - 1) || uniformSquare(x - 1, y - 1)
        else { return false }
        let r = element.radius
        for (dx, dy) in element.offsets {
            let ax = x + dx, ay = y + dy
            if ax < r || ay < r || ax >= w - r || ay >= h - r { continue }
            var uniform = true
            for (ex, ey) in element.offsets where labels[(ay + ey) * w + ax + ex] != label {
                uniform = false
                break
            }
            if uniform { return true }
        }
        return false
    }

    /// Reassigns the given pixels in four interleaved phases (x mod 2, y mod 2): pixels of
    /// one phase are never 8-neighbours, so each phase runs in parallel deterministically
    /// and sees the previous phases' results. Returns (index, previous paint) of changes.
    private static func process(
        _ candidates: [Int],
        classes: inout [UInt32],
        w: Int, h: Int,
        colors: [SIMD4<Float>],
        palette packed: [SIMD4<Float>],
        strong: Bool
    ) -> [(Int, UInt32)] {
        let rows = RowDivider(width: w)
        var phases: [[Int]] = [[], [], [], []]
        for i in candidates {
            let y = rows.row(i)
            phases[(i - y * w) & 1 | (y & 1) << 1].append(i)
        }
        var total: [(Int, UInt32)] = []
        for list in phases where !list.isEmpty {
            let bands: [[(Int, UInt32)]] = classes.withUnsafeMutableBufferPointer { cb in
                colors.withUnsafeBufferPointer { colb in
                    packed.withUnsafeBufferPointer { pb in
                        list.withUnsafeBufferPointer { lb in
                            let c = UncheckedSendable(cb.baseAddress!)
                            let col = UncheckedSendable(colb.baseAddress!)
                            let pal = UncheckedSendable(pb.baseAddress!)
                            let l = UncheckedSendable(lb.baseAddress!)
                            return Parallel.mapBands(lb.count, minimumBandSize: 1024) { range -> [(Int, UInt32)] in
                                var changed: [(Int, UInt32)] = []
                                withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 8) { cand in
                                    withUnsafeTemporaryAllocation(of: Float.self, capacity: 8) { wts in
                                        for k in range {
                                            let i = l.value[k]
                                            let y = rows.row(i)
                                            let best = dominantNeighbourClass(
                                                i, x: i - y * w, y: y, w: w, h: h, classes: c.value,
                                                color: col.value[i], palette: pal.value, includeOwn: !strong,
                                                cand: cand.baseAddress!, wts: wts.baseAddress!)
                                            if best != c.value[i] {
                                                changed.append((i, c.value[i]))
                                                c.value[i] = best
                                            }
                                        }
                                    }
                                }
                                return changed
                            }
                        }
                    }
                }
            }
            for band in bands { total += band }
        }
        return total
    }

    /// Pixels (ascending) not covered both by a uniform disc and by a uniform 2×2 square:
    /// the disc alone would accept 1-px bumps (a bump pixel is the arm of a cross), the
    /// square alone keeps pixel-square corners. Anchor bits: 1 = disc centred here is
    /// uniform, 2 = 2×2 block with this top-left corner is uniform. Written as byte-wise row
    /// operations so the compiler vectorizes them.
    static func uncoveredPixels(labels: [UInt32], width w: Int, height h: Int, element: StructuringElement) -> [Int] {
        let n = w * h
        let r = element.radius
        guard w > 2 * r, h > 2 * r, w > 1, h > 1 else { return Array(0..<n) }
        let around = element.offsets.filter { $0 != (0, 0) }
        var anchor = [UInt8](repeating: 0, count: n)
        return labels.withUnsafeBufferPointer { lb in
            anchor.withUnsafeMutableBufferPointer { ab in
                let l = UncheckedSendable(lb.baseAddress!)
                let a = UncheckedSendable(ab.baseAddress!)
                @inline(__always) func same(_ u: UInt32, _ v: UInt32) -> UInt8 { u == v ? 1 : 0 }
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    var disc = [UInt8](repeating: 0, count: w)
                    disc.withUnsafeMutableBufferPointer { db in
                        let d = db.baseAddress!
                        for y in rows {
                            let row = l.value + y * w
                            let out = a.value + y * w
                            if y + 1 < h {
                                let down = row + w
                                for x in 0..<(w - 1) {
                                    let v = row[x]
                                    out[x] = (same(row[x + 1], v) & same(down[x], v) & same(down[x + 1], v)) << 1
                                }
                            }
                            guard y >= r && y < h - r else { continue }
                            for x in r..<(w - r) { d[x] = 1 }
                            for (dx, dy) in around {
                                let src = row + dy * w + dx
                                for x in r..<(w - r) { d[x] &= same(src[x], row[x]) }
                            }
                            for x in r..<(w - r) { out[x] |= d[x] }
                        }
                    }
                }
                return Parallel.mapBands(h, minimumBandSize: 16) { rows -> [Int] in
                    var found: [Int] = []
                    var square = [UInt8](repeating: 0, count: w)
                    var hit = [UInt8](repeating: 0, count: w)
                    square.withUnsafeMutableBufferPointer { sb in
                        hit.withUnsafeMutableBufferPointer { hb in
                            let sq = sb.baseAddress!, ht = hb.baseAddress!
                            for y in rows {
                                let row = a.value + y * w
                                // 2×2 blocks whose top-left is at (x|x-1, y|y-1).
                                if y > 0 {
                                    let up = row - w
                                    for x in 0..<w { sq[x] = row[x] | up[x] }
                                } else {
                                    for x in 0..<w { sq[x] = row[x] }
                                }
                                for x in 0..<w { ht[x] = 0 }
                                for (dx, dy) in element.offsets where y + dy >= 0 && y + dy < h {
                                    let src = a.value + (y + dy) * w + dx
                                    for x in max(0, -dx)..<min(w, w - dx) { ht[x] |= src[x] }
                                }
                                ht[0] &= sq[0] >> 1
                                for x in 1..<w { ht[x] &= (sq[x] | sq[x - 1]) >> 1 }
                                for x in 0..<w where ht[x] & 1 == 0 { found.append(y * w + x) }
                            }
                        }
                    }
                    return found
                }.flatMap { $0 }
            }
        }
    }

    /// The paint with the most weight among the 8 neighbours (edge neighbours 1, corners
    /// 0.7). Without `includeOwn` the pixel's own paint is excluded and near-ties go to the
    /// paint closest to `color`; with it, the own paint is kept unless another strictly wins.
    @inline(__always)
    static func dominantNeighbourClass(
        _ i: Int, x: Int, y: Int, w: Int, h: Int,
        classes: UnsafeMutablePointer<UInt32>,
        color: SIMD4<Float>, palette: UnsafePointer<SIMD4<Float>>,
        includeOwn: Bool,
        cand: UnsafeMutablePointer<UInt32>, wts: UnsafeMutablePointer<Float>
    ) -> UInt32 {
        let own = classes[i]
        var ownWeight: Float = 0
        var count = 0
        @inline(__always) func add(_ j: Int, _ weight: Float) {
            let c = classes[j]
            if c == own { ownWeight += weight; return }
            var m = 0
            while m < count {
                if cand[m] == c {
                    wts[m] += weight
                    return
                }
                m += 1
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
