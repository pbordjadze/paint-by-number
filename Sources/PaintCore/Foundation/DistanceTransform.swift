import Foundation

/// Exact Euclidean distance transforms (Felzenszwalb & Huttenlocher, 2012), O(n).
public enum DistanceTransform {

    /// Squared Euclidean distance from every pixel to the nearest pixel for which
    /// `isFeature` is true. Pixels with no feature anywhere get `.infinity`.
    public static func squaredEDT(
        width: Int,
        height: Int,
        isFeature: (Int) -> Bool
    ) -> Grid<Float> {
        let n = width * height
        var f = [Double](repeating: 0, count: n)
        f.withUnsafeMutableBufferPointer { buf in
            let p = UncheckedSendable(buf.baseAddress!)
            Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                for i in range { p.value[i] = isFeature(i) ? 0 : .infinity }
            }
        }
        transform2D(&f, width: width, height: height)
        return Grid(width: width, height: height, storage: f.map { Float($0) })
    }

    /// For every pixel, the Euclidean distance from its center to the nearest edge of its
    /// region (pixels sharing its label), treating the image border as an edge.
    ///
    /// This is the radius of the largest disc centred on the pixel that stays inside the
    /// region, which drives label placement ("pole of inaccessibility") and thin-region
    /// detection.
    public static func interiorDistance(labels: RegionMap) -> Grid<Float> {
        let w = labels.width, h = labels.height
        let isBoundary: [Bool] = labels.storage.withUnsafeBufferPointer { l in
            var out = [Bool](repeating: false, count: w * h)
            out.withUnsafeMutableBufferPointer { o in
                let lp = UncheckedSendable(l.baseAddress!)
                let op = UncheckedSendable(o.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let row = y * w
                        for x in 0..<w {
                            let i = row + x
                            let v = lp.value[i]
                            var b = x == 0 || y == 0 || x == w - 1 || y == h - 1
                            if !b {
                                b = lp.value[i - 1] != v || lp.value[i + 1] != v
                                    || lp.value[i - w] != v || lp.value[i + w] != v
                            }
                            op.value[i] = b
                        }
                    }
                }
            }
            return out
        }
        var d = squaredEDT(width: w, height: h) { isBoundary[$0] }
        d.storage.withUnsafeMutableBufferPointer { buf in
            let p = UncheckedSendable(buf.baseAddress!)
            Parallel.forEachBand(w * h, minimumBandSize: 16_384) { range in
                for i in range { p.value[i] = p.value[i].squareRoot() + 0.5 }
            }
        }
        return d
    }

    // MARK: - Separable implementation

    static func transform2D(_ f: inout [Double], width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        // Columns first (strided), then rows (contiguous).
        f.withUnsafeMutableBufferPointer { buf in
            let base = UncheckedSendable(buf.baseAddress!)
            Parallel.forEachBand(width, minimumBandSize: 8) { cols in
                var line = [Double](repeating: 0, count: height)
                var out = [Double](repeating: 0, count: height)
                var v = [Int](repeating: 0, count: height)
                var z = [Double](repeating: 0, count: height + 1)
                for x in cols {
                    for y in 0..<height { line[y] = base.value[y * width + x] }
                    transform1D(line, count: height, out: &out, v: &v, z: &z)
                    for y in 0..<height { base.value[y * width + x] = out[y] }
                }
            }
            Parallel.forEachBand(height, minimumBandSize: 8) { rows in
                var line = [Double](repeating: 0, count: width)
                var out = [Double](repeating: 0, count: width)
                var v = [Int](repeating: 0, count: width)
                var z = [Double](repeating: 0, count: width + 1)
                for y in rows {
                    let row = base.value + y * width
                    for x in 0..<width { line[x] = row[x] }
                    transform1D(line, count: width, out: &out, v: &v, z: &z)
                    for x in 0..<width { row[x] = out[x] }
                }
            }
        }
    }

    /// 1D squared distance transform of sampled function `f` (lower envelope of parabolas).
    @inline(__always)
    static func transform1D(
        _ f: [Double], count n: Int, out d: inout [Double], v: inout [Int], z: inout [Double]
    ) {
        // Skip leading infinite samples: parabolas rooted at +inf never contribute.
        var first = 0
        while first < n && f[first] == .infinity { first += 1 }
        if first == n {
            for q in 0..<n { d[q] = .infinity }
            return
        }
        var k = 0
        v[0] = first
        z[0] = -.infinity
        z[1] = .infinity
        if first + 1 < n {
            for q in (first + 1)..<n {
                let fq = f[q]
                if fq == .infinity { continue }
                let qd = Double(q)
                var s: Double
                while true {
                    let vk = v[k]
                    let vd = Double(vk)
                    s = ((fq + qd * qd) - (f[vk] + vd * vd)) / (2 * qd - 2 * vd)
                    if s <= z[k] && k > 0 { k -= 1 } else { break }
                }
                if s <= z[k] {
                    // k == 0 and the new parabola dominates everywhere.
                    v[0] = q
                    z[0] = -.infinity
                    z[1] = .infinity
                    continue
                }
                k += 1
                v[k] = q
                z[k] = s
                z[k + 1] = .infinity
            }
        }
        k = 0
        for q in 0..<n {
            let qd = Double(q)
            while z[k + 1] < qd { k += 1 }
            let dv = qd - Double(v[k])
            d[q] = dv * dv + f[v[k]]
        }
    }
}
