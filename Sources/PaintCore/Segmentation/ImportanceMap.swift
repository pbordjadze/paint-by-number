import Foundation

/// Per-pixel importance (0...1) at working resolution. Important areas get paint budget,
/// smaller regions and gentler smoothing.
///
/// On device the map comes from Vision (subject mask, faces, saliency). Without one, a
/// photographic prior stands in: subjects tend to sit near the middle, and they carry
/// structure (edges that survive a light blur) where backgrounds are flat or blurred.
enum ImportanceMap {

    static func make(_ map: Grid<Float>?, lab: Grid<SIMD4<Float>>) -> [Float] {
        if let map, map.width > 0, map.height > 0 {
            return resample(map, width: lab.width, height: lab.height)
        }
        return fallback(lab)
    }

    /// Bilinear resampling to `width × height`, clamped to 0...1.
    static func resample(_ map: Grid<Float>, width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        let mw = map.width, mh = map.height
        let sx = Float(mw) / Float(width), sy = Float(mh) / Float(height)
        map.storage.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(height, minimumBandSize: 16) { rows in
                    for y in rows {
                        let fy = min(max((Float(y) + 0.5) * sy - 0.5, 0), Float(mh - 1))
                        let y0 = Int(fy), y1 = min(y0 + 1, mh - 1)
                        let ty = fy - Float(y0)
                        for x in 0..<width {
                            let fx = min(max((Float(x) + 0.5) * sx - 0.5, 0), Float(mw - 1))
                            let x0 = Int(fx), x1 = min(x0 + 1, mw - 1)
                            let tx = fx - Float(x0)
                            let top = s.value[y0 * mw + x0] * (1 - tx) + s.value[y0 * mw + x1] * tx
                            let bottom = s.value[y1 * mw + x0] * (1 - tx) + s.value[y1 * mw + x1] * tx
                            let v = top * (1 - ty) + bottom * ty
                            d.value[y * width + x] = v.isFinite ? min(max(v, 0), 1) : 0.5
                        }
                    }
                }
            }
        }
        return out
    }

    /// Mild center bias plus density of structure (gradients of a lightly blurred image,
    /// averaged over a few percent of the frame), normalized so busy areas approach 1.
    static func fallback(_ lab: Grid<SIMD4<Float>>) -> [Float] {
        let w = lab.width, h = lab.height, n = w * h
        guard n > 0 else { return [] }
        let side = Float(n).squareRoot()
        let blurred = boxBlur(lab.storage, width: w, height: h, radius: max(1, Int(side / 400)), passes: 2)
        var gradient = [SIMD4<Float>](repeating: .zero, count: n)
        blurred.withUnsafeBufferPointer { b in
            gradient.withUnsafeMutableBufferPointer { g in
                let bp = UncheckedSendable(b.baseAddress!)
                let gp = UncheckedSendable(g.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let up = max(y - 1, 0) * w, down = min(y + 1, h - 1) * w, row = y * w
                        for x in 0..<w {
                            let right = bp.value[row + min(x + 1, w - 1)]
                            let left = bp.value[row + max(x - 1, 0)]
                            let dx: SIMD4<Float> = right - left
                            let dy: SIMD4<Float> = bp.value[down + x] - bp.value[up + x]
                            let mx: Float = (dx * dx).sum().squareRoot()
                            let my: Float = (dy * dy).sum().squareRoot()
                            gp.value[row + x] = SIMD4(mx + my, 0, 0, 0)
                        }
                    }
                }
            }
        }
        let density = boxBlur(gradient, width: w, height: h, radius: max(2, Int(side / 30)), passes: 2)

        // Normalize by a high percentile so a few very sharp edges don't flatten the rest.
        var sample: [Float] = []
        let stride = max(1, n / 20_000)
        var i = 0
        while i < n { sample.append(density[i].x); i += stride }
        sample.sort()
        let reference = max(sample[min(sample.count - 1, Int(Float(sample.count) * 0.9))], 1e-4)

        var out = [Float](repeating: 0, count: n)
        density.withUnsafeBufferPointer { d in
            out.withUnsafeMutableBufferPointer { o in
                let dp = UncheckedSendable(d.baseAddress!)
                let op = UncheckedSendable(o.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    let falloff: Float = -1 / (2 * 0.3 * 0.3)
                    for y in rows {
                        let v: Float = (Float(y) + 0.5) / Float(h) - 0.45
                        for x in 0..<w {
                            let u: Float = (Float(x) + 0.5) / Float(w) - 0.5
                            let center: Float = exp((u * u + v * v) * falloff)
                            let structure: Float = min(dp.value[y * w + x].x / reference, 1)
                            let value: Float = 0.2 + 0.4 * center + 0.4 * structure
                            op.value[y * w + x] = min(value, 1)
                        }
                    }
                }
            }
        }
        return out
    }

    /// Repeated box blur (≈ Gaussian after 2–3 passes) with edge-normalized windows.
    static func boxBlur(_ input: [SIMD4<Float>], width w: Int, height h: Int, radius r: Int, passes: Int) -> [SIMD4<Float>] {
        var a = input
        var b = [SIMD4<Float>](repeating: .zero, count: input.count)
        for _ in 0..<passes {
            a.withUnsafeBufferPointer { src in
                b.withUnsafeMutableBufferPointer { dst in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    Parallel.forEachBand(h, minimumBandSize: 8) { rows in
                        for y in rows {
                            let row = y * w
                            var acc = SIMD4<Float>.zero
                            for x in 0..<min(r, w) { acc += s.value[row + x] }
                            for x in 0..<w {
                                if x + r < w { acc += s.value[row + x + r] }
                                if x - r - 1 >= 0 { acc -= s.value[row + x - r - 1] }
                                let count = Float(min(x + r, w - 1) - max(x - r, 0) + 1)
                                d.value[row + x] = acc / count
                            }
                        }
                    }
                }
            }
            b.withUnsafeBufferPointer { src in
                a.withUnsafeMutableBufferPointer { dst in
                    let s = UncheckedSendable(src.baseAddress!)
                    let d = UncheckedSendable(dst.baseAddress!)
                    Parallel.forEachBand(w, minimumBandSize: 32) { cols in
                        var acc = [SIMD4<Float>](repeating: .zero, count: cols.count)
                        let c0 = cols.lowerBound
                        for y in 0..<min(r, h) {
                            for x in cols { acc[x - c0] += s.value[y * w + x] }
                        }
                        for y in 0..<h {
                            let count = Float(min(y + r, h - 1) - max(y - r, 0) + 1)
                            let add = y + r < h ? (y + r) * w : -1
                            let sub = y - r - 1 >= 0 ? (y - r - 1) * w : -1
                            for x in cols {
                                if add >= 0 { acc[x - c0] += s.value[add + x] }
                                if sub >= 0 { acc[x - c0] -= s.value[sub + x] }
                                d.value[y * w + x] = acc[x - c0] / count
                            }
                        }
                    }
                }
            }
        }
        return a
    }
}
