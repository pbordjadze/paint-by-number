import Foundation

/// Edge map → one-pixel centerlines: the raster half of layered line art.
///
/// 1. The 8-bit map is resampled to the working size (area average when shrinking, linear
///    when enlarging) and its 3-px frame cleared (the canvas edge is not a line).
/// 2. Ridges: a pixel is on a line's centre when the (lightly smoothed) response is not
///    smaller than both neighbours across the line, the direction of the Hessian's most
///    negative eigenvector, and curves down there. A soft, wide line (HED draws 5–10 px)
///    and a crisp one both give their centre, and close lines do not merge. Ridges hugging
///    the frame and parallel to it (a vignette, a dark rim) are dropped.
/// 3. Hysteresis: ridge pixels above half the texture threshold that are 8-connected to one
///    above it, the thresholds scaled mildly by importance (more lines on the subject).
/// 4. A 3×3 closing seals one-pixel breaks; thinning leaves 8-connected one-pixel lines.
enum LineDetection {
    /// Cleared border, working pixels.
    static let frame = 3
    /// Ridges within this many pixels of a side and parallel to it are not drawing.
    static let frameParallel = 12
    /// Gaussian scales of the response smoothing (working pixels) and of the Hessian (map pixels).
    static let responseSigma: Float = 0.8
    static let ridgeSigma: Float = 1.5
    /// Least downward curvature across a ridge (response units per pixel², at the Hessian's
    /// scale); a faint soft line (strength 0.05, a few pixels wide) curves at least twenty
    /// times as much at any map scale.
    static let minimumCurvature: Float = 1e-4
    /// Hysteresis: candidates above this fraction of the seed threshold join a line.
    static let lowFraction: Float = 0.5
    /// Importance scaling of the extraction thresholds: × (1 + gain) at importance 0 down to
    /// × (1 − gain) at importance 1.
    static let importanceGain: Float = 0.15

    /// Edge strength per working pixel, 0...1.
    static func strength(_ edges: EdgeMap, width w: Int, height h: Int) -> [Float] {
        let mw = edges.width, mh = edges.height
        let xw = Resample.Weights(inCount: mw, outCount: w), yw = Resample.Weights(inCount: mh, outCount: h)
        var horizontal = [Float](uninitializedCount: w * mh)
        edges.values.withUnsafeBufferPointer { src in
            horizontal.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(mh, minimumBandSize: 16) { rows in
                    for y in rows {
                        let row = s.value + y * mw, out = d.value + y * w
                        for x in 0..<w {
                            var acc: Float = 0
                            for k in xw.start[x]..<xw.start[x + 1] { acc += Float(row[Int(xw.index[k])]) * xw.weight[k] }
                            out[x] = acc / 255
                        }
                    }
                }
            }
        }
        var out = [Float](uninitializedCount: w * h)
        horizontal.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let o = d.value + y * w
                        for x in 0..<w { o[x] = 0 }
                        for k in yw.start[y]..<yw.start[y + 1] {
                            let row = s.value + Int(yw.index[k]) * w, wt = yw.weight[k]
                            for x in 0..<w { o[x] += row[x] * wt }
                        }
                        let border = y < frame || y >= h - frame
                        for x in 0..<w where border || x < frame || x >= w - frame { o[x] = 0 }
                    }
                }
            }
        }
        return out
    }

    /// Ridge pixels of `response` and the smoothed response itself. `scale` is how many
    /// working pixels one edge-map pixel spans (the line widths scale with it).
    static func ridges(
        _ response: [Float], width w: Int, height h: Int, scale: Float, cancel: CancellationCheck
    ) throws -> (ridge: [Bool], smooth: [Float]) {
        let s = max(scale, 1)
        // Resampling already interpolates an enlarged map; only the Hessian, which must span a
        // line's width to find its centre, grows with the map's pixels.
        let rs = Gaussian.filter(response, width: w, height: h, sigma: responseSigma, orderX: 0, orderY: 0)
        try cancel.throwIfCancelled()
        let sigma = ridgeSigma * s
        let hxx = Gaussian.filter(response, width: w, height: h, sigma: sigma, orderX: 2, orderY: 0)
        let hyy = Gaussian.filter(response, width: w, height: h, sigma: sigma, orderX: 0, orderY: 2)
        let hxy = Gaussian.filter(response, width: w, height: h, sigma: sigma, orderX: 1, orderY: 1)
        try cancel.throwIfCancelled()
        var ridge = [Bool](repeating: false, count: w * h)
        let m = frameParallel
        rs.withUnsafeBufferPointer { rsb in
            ridge.withUnsafeMutableBufferPointer { out in
                let r = UncheckedSendable(rsb.baseAddress!), o = UncheckedSendable(out.baseAddress!)
                // Bilinear, clamped to the canvas (callers guarantee w, h ≥ 2).
                @inline(__always) func sample(_ x: Float, _ y: Float) -> Float {
                    let cx = min(max(x, 0), Float(w - 1)), cy = min(max(y, 0), Float(h - 1))
                    let x0 = min(Int(cx), w - 2), y0 = min(Int(cy), h - 2)
                    let x1 = x0 + 1, y1 = y0 + 1
                    let fx = cx - Float(x0), fy = cy - Float(y0)
                    let top = r.value[y0 * w + x0] * (1 - fx) + r.value[y0 * w + x1] * fx
                    let bottom = r.value[y1 * w + x0] * (1 - fx) + r.value[y1 * w + x1] * fx
                    return top * (1 - fy) + bottom * fy
                }
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        for x in 0..<w {
                            let i = y * w + x
                            let a = hxx[i], b = hyy[i], c = hxy[i]
                            let disc = ((a - b) * (a - b) + 4 * c * c).squareRoot()
                            let lam = 0.5 * (a + b - disc)
                            // A plateau (a saturated map) curves by rounding error only.
                            guard lam < -minimumCurvature else { continue }
                            var vx: Float, vy: Float
                            if abs(a - lam) < abs(b - lam) { vx = lam - b; vy = c } else { vx = c; vy = lam - a }
                            let n = (vx * vx + vy * vy).squareRoot()
                            if n > 1e-12 { vx /= n; vy /= n } else { vx = 1; vy = 0 }
                            let v = r.value[i]
                            guard v >= sample(Float(x) + vx, Float(y) + vy), v >= sample(Float(x) - vx, Float(y) - vy) else { continue }
                            let nearSide = x < m || x >= w - m, nearTop = y < m || y >= h - m
                            if nearSide && abs(vx) > 0.8 { continue }
                            if nearTop && abs(vy) > 0.8 { continue }
                            o.value[i] = true
                        }
                    }
                }
            }
        }
        return (ridge, rs)
    }

    /// Hysteresis on the ridges, closing and thinning: the one-pixel line mask.
    static func lines(
        ridge: [Bool], smooth rs: [Float], importance: [Float]?, width w: Int, height h: Int,
        threshold: Float, cancel: CancellationCheck
    ) throws -> [Bool] {
        let n = w * h
        var candidate = [Bool](repeating: false, count: n)
        var stack: [Int32] = []
        for i in 0..<n where ridge[i] {
            let scale = 1 + importanceGain * (1 - 2 * (importance?[i] ?? 0.5))
            let v = rs[i]
            if v > lowFraction * threshold * scale {
                candidate[i] = true
                if v > threshold * scale { stack.append(Int32(i)) }
            }
        }
        try cancel.throwIfCancelled()
        var keep = [Bool](repeating: false, count: n)
        for s in stack { keep[Int(s)] = true }
        while let top = stack.popLast() {
            let i = Int(top), y = i / w, x = i - y * w
            for dy in -1...1 {
                let yy = y + dy
                guard yy >= 0 && yy < h else { continue }
                for dx in -1...1 {
                    let xx = x + dx
                    guard xx >= 0 && xx < w else { continue }
                    let j = yy * w + xx
                    if candidate[j] && !keep[j] { keep[j] = true; stack.append(Int32(j)) }
                }
            }
        }
        try cancel.throwIfCancelled()
        var mask = Morphology.close3x3(keep, width: w, height: h)
        for i in 0..<n where keep[i] { mask[i] = true }
        try cancel.throwIfCancelled()
        Thinning.thin(&mask, width: w, height: h)
        return mask
    }
}

extension LineDetection {
    /// Window (working pixels at a 1500-px canvas; it scales with the canvas) over which line
    /// density is measured, and the centerline pixels per pixel from which lines count as
    /// crowded there (lines about 16 px apart); clutter is 1 at twice that. A lone line
    /// crosses a window once, under the onset at any window size.
    static let clutterWindow: Float = 31
    static let clutterDensity: Float = 0.06

    /// How crowded the centerlines of `mask` are around each pixel, 0...1.
    static func clutter(_ mask: [Bool], width w: Int, height h: Int, cancel: CancellationCheck) throws -> [Float] {
        let radius = max(1, Int((clutterWindow * Float(max(w, h)) / 1500 / 2).rounded()))
        let onset = clutterDensity * clutterWindow / Float(2 * radius + 1)
        let density = try BoxBlur.apply(mask.map { $0 ? 1 : 0 }, width: w, height: h, radius: radius, passes: 1, cancel: cancel)
        let crowded = density.map { min(max($0 / onset - 1, 0), 1) }
        return try BoxBlur.apply(crowded, width: w, height: h, radius: max(1, radius / 2), passes: 2, cancel: cancel)
    }
}

/// Separable Gaussian filtering and its derivatives, with clamped borders (like
/// `scipy.ndimage.gaussian_filter(mode="nearest")`, truncated at 4 σ).
enum Gaussian {
    static func kernel(sigma: Float, order: Int) -> [Float] {
        let radius = max(1, Int(4 * sigma + 0.5))
        let s2 = sigma * sigma
        var g = (-radius...radius).map { x -> Float in exp(-Float(x * x) / (2 * s2)) }
        let sum = g.reduce(0, +)
        g = g.map { $0 / sum }
        switch order {
        case 1: return (-radius...radius).enumerated().map { k, x in -Float(x) / s2 * g[k] }
        case 2: return (-radius...radius).enumerated().map { k, x in (Float(x * x) / (s2 * s2) - 1 / s2) * g[k] }
        default: return g
        }
    }

    static func filter(_ input: [Float], width w: Int, height h: Int, sigma: Float, orderX: Int, orderY: Int) -> [Float] {
        let kx = kernel(sigma: sigma, order: orderX), ky = kernel(sigma: sigma, order: orderY)
        let rx = kx.count / 2, ry = ky.count / 2
        var tmp = [Float](uninitializedCount: w * h)
        input.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let row = s.value + y * w, out = d.value + y * w
                        for x in 0..<w {
                            var acc: Float = 0
                            for k in 0..<kx.count {
                                let xx = min(max(x + k - rx, 0), w - 1)
                                acc += row[xx] * kx[kx.count - 1 - k]
                            }
                            out[x] = acc
                        }
                    }
                }
            }
        }
        var out = [Float](uninitializedCount: w * h)
        tmp.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let o = d.value + y * w
                        for x in 0..<w { o[x] = 0 }
                        for k in 0..<ky.count {
                            let yy = min(max(y + k - ry, 0), h - 1)
                            let row = s.value + yy * w, wt = ky[ky.count - 1 - k]
                            for x in 0..<w { o[x] += row[x] * wt }
                        }
                    }
                }
            }
        }
        return out
    }
}

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
