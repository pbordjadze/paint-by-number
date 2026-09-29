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
        // Original paint of every pixel touched, in first-touch order.
        var touched: [(index: Int, paint: UInt32)] = []
        var seen = Set<Int>()
        func record(_ changes: [(Int, UInt32)]) {
            for (i, old) in changes where seen.insert(i).inserted { touched.append((i, old)) }
        }
        var changes = pass(classes: &classes, width: w, height: h, colors: colors, palette: packed, element: element, strong: true)
        guard !changes.isEmpty else { return 0 }
        record(changes)
        for _ in 1..<max(2, maxPasses) {  // settling
            changes = pass(classes: &classes, width: w, height: h, colors: colors, palette: packed, element: element, strong: false)
            if changes.isEmpty { break }
            record(changes)
        }
        // Moves that left the pixel uncovered did not help (typically a corner where
        // several regions meet); undo them so repeated calls reach a fixed point. Undoing
        // one move can un-cover a neighbour's, hence the loop.
        var net = 0
        for _ in 0..<4 {
            let covered = coverage(labels: classes, width: w, height: h, element: element)
            var reverted = 0
            net = 0
            for t in touched where classes[t.index] != t.paint {
                if covered[t.index] == 0 {
                    classes[t.index] = t.paint
                    reverted += 1
                } else {
                    net += 1
                }
            }
            if reverted == 0 { break }
        }
        return net
    }

    struct StructuringElement {
        let radius: Int
        /// Linear offsets (dy * width + dx) are built per image; these are (dx, dy).
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

    private static func pass(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: [SIMD4<Float>],
        palette packed: [SIMD4<Float>],
        element: StructuringElement,
        strong: Bool
    ) -> [(Int, UInt32)] {
        let covered = coverage(labels: classes, width: w, height: h, element: element)
        var total: [(Int, UInt32)] = []
        for phase in 0..<4 {
            let px = phase & 1, py = phase >> 1
            let rowCount = (h - py + 1) / 2
            let counts: [[(Int, UInt32)]] = classes.withUnsafeMutableBufferPointer { cb in
                covered.withUnsafeBufferPointer { vb in
                    colors.withUnsafeBufferPointer { colb in
                        packed.withUnsafeBufferPointer { pb in
                            let c = UncheckedSendable(cb.baseAddress!)
                            let v = UncheckedSendable(vb.baseAddress!)
                            let col = UncheckedSendable(colb.baseAddress!)
                            let pal = UncheckedSendable(pb.baseAddress!)
                            return Parallel.mapBands(rowCount, minimumBandSize: 8) { rows -> [(Int, UInt32)] in
                                var changed: [(Int, UInt32)] = []
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
                                                changed.append((i, c.value[i]))
                                                c.value[i] = best
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
            for band in counts { total += band }
        }
        return total
    }

    /// 1 where both a disc and a 2×2 block of equal labels contain the pixel, else 0.
    static func coverage(labels: [UInt32], width w: Int, height h: Int, radiusSquared: Int) -> [UInt8] {
        coverage(labels: labels, width: w, height: h, element: StructuringElement(radiusSquared: radiusSquared))
    }

    /// Coverage by the disc and by a 2×2 square: the disc alone would accept 1-px bumps
    /// (a bump pixel is the arm of a cross), the square alone keeps pixel-square corners.
    /// Anchor bits: 1 = disc centred here is uniform, 2 = 2×2 block with this top-left
    /// corner is uniform.
    static func coverage(labels: [UInt32], width w: Int, height h: Int, element: StructuringElement) -> [UInt8] {
        let n = w * h
        let r = element.radius
        var anchor = [UInt8](repeating: 0, count: n)
        var covered = [UInt8](repeating: 0, count: n)
        guard w > 2 * r, h > 2 * r, w > 1, h > 1 else { return covered }
        let offsets = element.offsets.map { $0.1 * w + $0.0 }
        labels.withUnsafeBufferPointer { lb in
            anchor.withUnsafeMutableBufferPointer { ab in
                covered.withUnsafeMutableBufferPointer { cb in
                    offsets.withUnsafeBufferPointer { ob in
                        let l = UncheckedSendable(lb.baseAddress!)
                        let a = UncheckedSendable(ab.baseAddress!)
                        let c = UncheckedSendable(cb.baseAddress!)
                        let o = UncheckedSendable(ob.baseAddress!)
                        let m = ob.count
                        Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                            for y in rows {
                                let row = y * w
                                let discRow = y >= r && y < h - r
                                for x in 0..<w {
                                    let i = row + x
                                    let label = l.value[i]
                                    var bits: UInt8 = 0
                                    if x + 1 < w && y + 1 < h && l.value[i + 1] == label && l.value[i + w] == label
                                        && l.value[i + w + 1] == label {
                                        bits = 2
                                    }
                                    if discRow && x >= r && x < w - r {
                                        var uniform = true
                                        var k = 0
                                        while k < m {
                                            if l.value[i + o.value[k]] != label { uniform = false; break }
                                            k += 1
                                        }
                                        if uniform { bits |= 1 }
                                    }
                                    a.value[i] = bits
                                }
                            }
                        }
                        Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                            for y in rows {
                                let row = y * w
                                let interiorRow = y >= r && y < h - r
                                for x in 0..<w {
                                    let i = row + x
                                    // 2×2: blocks whose top-left is at (x|x-1, y|y-1).
                                    var square = a.value[i]
                                    if x > 0 { square |= a.value[i - 1] }
                                    if y > 0 {
                                        square |= a.value[i - w]
                                        if x > 0 { square |= a.value[i - w - 1] }
                                    }
                                    guard square & 2 != 0 else { continue }
                                    var hit = false
                                    if interiorRow && x >= r && x < w - r {
                                        var k = 0
                                        while k < m {
                                            if a.value[i + o.value[k]] & 1 != 0 { hit = true; break }
                                            k += 1
                                        }
                                    } else {
                                        for (dx, dy) in element.offsets {
                                            let xx = x + dx, yy = y + dy
                                            if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                                            if a.value[yy * w + xx] & 1 != 0 { hit = true; break }
                                        }
                                    }
                                    if hit { c.value[i] = 1 }
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
