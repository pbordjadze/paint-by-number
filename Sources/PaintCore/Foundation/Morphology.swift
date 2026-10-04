/// Binary morphology on `[Bool]` masks.
enum Morphology {
    /// 3×3 dilation followed by 3×3 erosion (outside the canvas counts as set for the
    /// erosion, as for scipy's `binary_closing` with its default border).
    static func close3x3(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        let dilated = square(mask, width: w, height: h, any: true)
        return square(dilated, width: w, height: h, any: false)
    }

    /// 3×3 neighbourhood test per pixel: `any` (dilation) or all (erosion; outside counts as set).
    static func square(_ mask: [Bool], width w: Int, height h: Int, any: Bool) -> [Bool] {
        var out = [Bool](repeating: false, count: w * h)
        mask.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 32) { rows in
                    for y in rows {
                        for x in 0..<w {
                            var result = !any
                            loop: for dy in -1...1 {
                                let yy = y + dy
                                for dx in -1...1 {
                                    let xx = x + dx
                                    let v = (yy < 0 || yy >= h || xx < 0 || xx >= w) ? !any : s.value[yy * w + xx]
                                    if any && v { result = true; break loop }
                                    if !any && !v { result = false; break loop }
                                }
                            }
                            d.value[y * w + x] = result
                        }
                    }
                }
            }
        }
        return out
    }
}

/// Zhang–Suen thinning to one-pixel, 8-connected lines, then removal of the staircase
/// corners it leaves (a pixel whose two perpendicular 4-neighbours already touch
/// diagonally), so that only true ends and junctions have other than two neighbours.
enum Thinning {
    static func thin(_ mask: inout [Bool], width w: Int, height h: Int) {
        guard w > 2, h > 2 else { return }
        // Pixels on the canvas border are cleared first: the 8-neighbourhood test needs a ring.
        for x in 0..<w { mask[x] = false; mask[(h - 1) * w + x] = false }
        for y in 0..<h { mask[y * w] = false; mask[y * w + w - 1] = false }
        var active = (0..<(w * h)).filter { mask[$0] }
        var remove: [Int] = []
        @inline(__always) func neighbours(_ i: Int) -> UInt8 {
            // Bits clockwise from north: P2 (N), P3 (NE), P4 (E), P5 (SE), P6 (S), P7 (SW), P8 (W), P9 (NW).
            var b: UInt8 = 0
            if mask[i - w] { b |= 1 }
            if mask[i - w + 1] { b |= 2 }
            if mask[i + 1] { b |= 4 }
            if mask[i + w + 1] { b |= 8 }
            if mask[i + w] { b |= 16 }
            if mask[i + w - 1] { b |= 32 }
            if mask[i - 1] { b |= 64 }
            if mask[i - w - 1] { b |= 128 }
            return b
        }
        let table = lookup
        var changed = true
        while changed {
            changed = false
            for pass in 0..<2 {
                remove.removeAll(keepingCapacity: true)
                for i in active where mask[i] {
                    if table[Int(neighbours(i))] & (1 << pass) != 0 { remove.append(i) }
                }
                if !remove.isEmpty { changed = true }
                for i in remove { mask[i] = false }
            }
            active = active.filter { mask[$0] }
        }
        // Staircase corners, in raster order.
        for i in active where mask[i] {
            let b = neighbours(i)
            let n = b & 1 != 0, e = b & 4 != 0, s = b & 16 != 0, wst = b & 64 != 0
            guard (n && e) || (e && s) || (s && wst) || (wst && n) else { continue }
            if b.nonzeroBitCount >= 2 && crossings(b) == 1 { mask[i] = false }
        }
    }

    /// Transitions from unset to set around the 8-neighbourhood.
    @inline(__always)
    static func crossings(_ b: UInt8) -> Int {
        var count = 0
        for k in 0..<8 where b & (1 << k) == 0 && b & (1 << ((k + 1) % 8)) != 0 { count += 1 }
        return count
    }

    /// Bit 0: removable in the first sub-iteration, bit 1: in the second.
    static let lookup: [UInt8] = (0..<256).map { v in
        let b = UInt8(v)
        func p(_ k: Int) -> Bool { b & (1 << k) != 0 }
        let count = b.nonzeroBitCount
        guard count >= 2 && count <= 6 && crossings(b) == 1 else { return 0 }
        let p2 = p(0), p4 = p(2), p6 = p(4), p8 = p(6)
        var out: UInt8 = 0
        if !(p2 && p4 && p6) && !(p4 && p6 && p8) { out |= 1 }
        if !(p2 && p4 && p8) && !(p2 && p6 && p8) { out |= 2 }
        return out
    }
}
