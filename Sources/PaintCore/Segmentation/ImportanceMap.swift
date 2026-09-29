import Foundation

/// Per-pixel importance (0...1) at working resolution. Important areas get paint budget,
/// smaller regions and gentler smoothing.
///
/// On device the map comes from Vision (subject mask, faces, saliency). Without one, a
/// photographic prior stands in: subjects tend to sit near the middle, and they carry
/// structure (coherent contours) where backgrounds are flat, blurred or merely textured.
enum ImportanceMap {

    static func make(_ map: Grid<Float>?, structure: StructureMap, cancel: CancellationCheck = .none) throws -> [Float] {
        if let map, map.width > 0, map.height > 0 {
            return resample(map, width: structure.width, height: structure.height)
        }
        return try fallback(structure: structure.coherentMagnitude(), width: structure.width, height: structure.height, cancel: cancel)
    }

    /// Bilinear resampling to `width × height`, clamped to 0...1.
    static func resample(_ map: Grid<Float>, width: Int, height: Int) -> [Float] {
        var out = [Float](uninitializedCount: width * height)
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

    /// Mild center bias plus density of structure — coherent gradients (see `StructureMap`),
    /// averaged over a few percent of the frame and normalized so the busiest contours
    /// approach 1. Texture does not count as structure, so a rushing river or a gravel path
    /// is not mistaken for the subject.
    static func fallback(structure: [Float], width w: Int, height h: Int, cancel: CancellationCheck = .none) throws -> [Float] {
        let n = w * h
        guard n > 0 else { return [] }
        let side = Float(n).squareRoot()
        let density = try BoxBlur.apply(structure, width: w, height: h, radius: max(2, Int(side / 30)), passes: 2, cancel: cancel)

        // Normalize by a high percentile so a few very sharp edges don't flatten the rest.
        var sample: [Float] = []
        let stride = max(1, n / 20_000)
        var i = 0
        while i < n { sample.append(density[i]); i += stride }
        sample.sort()
        let reference = max(sample[min(sample.count - 1, Int(Float(sample.count) * 0.9))], 1e-4)

        var out = [Float](uninitializedCount: n)
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
                            let busy: Float = min(dp.value[y * w + x] / reference, 1)
                            let value: Float = 0.2 + 0.4 * center + 0.4 * busy
                            op.value[y * w + x] = min(value, 1)
                        }
                    }
                }
            }
        }
        return out
    }
}
