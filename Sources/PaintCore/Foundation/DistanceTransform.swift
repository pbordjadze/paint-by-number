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
        var feature = [UInt8](repeating: 0, count: n)
        feature.withUnsafeMutableBufferPointer { buf in
            let p = UncheckedSendable(buf.baseAddress!)
            Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                for i in range { p.value[i] = isFeature(i) ? 1 : 0 }
            }
        }
        let f = try! squaredDistances(feature, width: width, height: height, cancel: .none)
        return Grid(width: width, height: height, storage: f.map { Float($0) })
    }

    /// For every pixel, the Euclidean distance from its center to the nearest edge of its
    /// region (pixels sharing its label), treating the image border as an edge.
    ///
    /// This is the radius of the largest disc centred on the pixel that stays inside the
    /// region, which drives label placement ("pole of inaccessibility") and thin-region
    /// detection.
    public static func interiorDistance(labels: RegionMap, cancel: CancellationCheck = .none) throws -> Grid<Float> {
        let w = labels.width, h = labels.height, n = w * h
        guard n > 0 else { return Grid(width: w, height: h, storage: []) }
        var isBoundary = [UInt8](repeating: 1, count: n)
        labels.storage.withUnsafeBufferPointer { l in
            isBoundary.withUnsafeMutableBufferPointer { o in
                let lp = UncheckedSendable(l.baseAddress!)
                let op = UncheckedSendable(o.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows where y > 0 && y < h - 1 {
                        let row = lp.value + y * w, up = row - w, down = row + w
                        let out = op.value + y * w
                        for x in 1..<max(w - 1, 1) {
                            let v = row[x]
                            out[x] = (row[x - 1] != v || row[x + 1] != v || up[x] != v || down[x] != v) ? 1 : 0
                        }
                    }
                }
            }
        }
        let d = try squaredDistances(isBoundary, width: w, height: h, cancel: cancel)
        var out = [Float](unsafeUninitializedCapacity: n) { _, count in count = n }
        d.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!)
                let o = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(n, minimumBandSize: 16_384) { range in
                    for i in range { o.value[i] = Float(s.value[i]).squareRoot() + 0.5 }
                }
            }
        }
        return Grid(width: w, height: h, storage: out)
    }

    // MARK: - Separable implementation

    /// Squared distances to the nearest nonzero `feature` pixel.
    static func squaredDistances(_ feature: [UInt8], width: Int, height: Int, cancel: CancellationCheck) throws -> [Double] {
        let n = width * height
        guard width > 0, height > 0 else { return [] }
        let waveRows = Parallel.waveRows(width: width)
        var f = [Double](unsafeUninitializedCapacity: n) { _, count in count = n }
        // Distance (in rows) to the nearest feature seen so far in each column.
        let none = Int32.max
        var run = [Int32](repeating: none, count: width)
        try feature.withUnsafeBufferPointer { fb in
            try f.withUnsafeMutableBufferPointer { buf in
                try run.withUnsafeMutableBufferPointer { rb in
                    let base = UncheckedSendable(buf.baseAddress!)
                    let feat = UncheckedSendable(fb.baseAddress!)
                    let runs = UncheckedSendable(rb.baseAddress!)
                    // Columns: on a binary image the lower envelope of parabolas is simply the
                    // squared distance to the nearest feature in the column, found by one sweep
                    // down and one up (bands of whole columns walk rows, so memory stays
                    // sequential; rows go in waves for cancellation).
                    var y0 = 0
                    while y0 < height {
                        let y1 = min(height, y0 + waveRows)
                        Parallel.forEachBand(width, minimumBandSize: 64) { cols in
                            let c0 = cols.lowerBound, span = cols.count
                            let run = runs.value + c0
                            for y in y0..<y1 {
                                let fr = feat.value + y * width + c0, out = base.value + y * width + c0
                                for k in 0..<span {
                                    run[k] = fr[k] != 0 ? 0 : (run[k] == none ? none : run[k] + 1)
                                    out[k] = Double(run[k])
                                }
                            }
                        }
                        y0 = y1
                        try cancel.throwIfCancelled()
                    }
                    for x in 0..<width { runs.value[x] = none }
                    var y1 = height
                    while y1 > 0 {
                        let y0 = max(0, y1 - waveRows)
                        Parallel.forEachBand(width, minimumBandSize: 64) { cols in
                            let c0 = cols.lowerBound, span = cols.count
                            let run = runs.value + c0
                            for y in stride(from: y1 - 1, through: y0, by: -1) {
                                let fr = feat.value + y * width + c0, out = base.value + y * width + c0
                                for k in 0..<span {
                                    run[k] = fr[k] != 0 ? 0 : (run[k] == none ? none : run[k] + 1)
                                    let d = min(out[k], Double(run[k]))
                                    out[k] = d == Double(none) ? .infinity : d * d
                                }
                            }
                        }
                        y1 = y0
                        try cancel.throwIfCancelled()
                    }
                    try Parallel.forEachBand(height, minimumBandSize: 8, wave: waveRows, cancel: cancel) { rows in
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
        }
        return f
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
