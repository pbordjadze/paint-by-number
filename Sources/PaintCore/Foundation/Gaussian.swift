import Foundation

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
