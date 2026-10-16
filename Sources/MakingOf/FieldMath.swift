import PaintCore

/// What the field show does to a field between computing it and using it: `shrink`, `grow` and
/// `paced` of `making_of_fields.py`. Each output cell is computed whole by one task, from the
/// field alone, so none depends on how many cores share the work.
enum FieldMath {
    // MARK: Size

    /// `values` (cell `i` of a plane `width` by `height`) at 1 / `FieldShow.scale` of its size, each
    /// cell the mean of its block (the last odd row or column dropped): the block's rows are added
    /// and then the sums of the rows, as numpy's `mean` does it.
    static func shrink(width: Int, height: Int, _ value: (Int) -> Double) -> Plane<Double> {
        let scale = FieldShow.scale
        let (w, h) = (width / scale, height / scale)
        var out = [Double](repeating: 0, count: w * h)
        let cells = Double(scale * scale)
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0.0
                for dy in 0..<scale {
                    var row = 0.0
                    for dx in 0..<scale { row += value((y * scale + dy) * width + x * scale + dx) }
                    sum += row
                }
                out[y * w + x] = sum / cells
            }
        }
        return Plane(width: w, height: h, data: out)
    }

    /// `field` at the picture's `size`, bilinear between the centres of its cells.
    static func grow(_ field: Plane<Double>, to size: (width: Int, height: Int)) -> [Double] {
        let (w, h) = (field.width, field.height)
        precondition(w >= 2 && h >= 2, "a field has two cells each way to grow from")
        let scale = Double(FieldShow.scale)
        // where each output row and column falls between the field's cells
        func cuts(_ n: Int, of count: Int) -> [(cell: Int, blend: Double)] {
            (0..<n).map { i in
                let at = min(max((Double(i) + 0.5) / scale - 0.5, 0), Double(count - 1))
                let cell = min(truncated(at), count - 2)
                return (cell, at - Double(cell))
            }
        }
        let columns = cuts(size.width, of: w)
        let rows = cuts(size.height, of: h)
        var out = [Double](repeating: 0, count: size.width * size.height)
        field.data.withUnsafeBufferPointer { field in
            out.withUnsafeMutableBufferPointer { buffer in
                let out = UncheckedSendable(buffer.baseAddress!)
                FieldBands.forEach(size.height) { band in
                    for y in band {
                        let (y0, ty) = rows[y]
                        let upper = field.baseAddress! + y0 * w, lower = upper + w
                        let row = out.value + y * size.width
                        for x in 0..<size.width {
                            let (x0, tx) = columns[x]
                            let (a, b, c, d) = (upper[x0], upper[x0 + 1], lower[x0], lower[x0 + 1])
                            let top = a + (b - a) * tx, bottom = c + (d - c) * tx
                            row[x] = top + (bottom - top) * ty
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: Pacing

    /// `times` mapped into `lo`...`hi` mostly by their rank among the cells of `over` (a mask; every
    /// finite cell if nil), so the change covers them at an even pace however the field bunches;
    /// `mix` of the pace is the rank and the rest the plain stretch, so a fast front still looks
    /// fast. Cells of one time share their mean rank; the earliest maps to `lo`, the latest and
    /// infinity to `hi`. With no cell to rank, everything is at `hi`.
    ///
    /// The rank is interpolated between `FieldShow.paceKnots` + 1 times picked evenly from the
    /// sorted cells (`sampled`), so how the cells are sorted is not visible; the arithmetic is
    /// `paced` in `making_of_fields.py`, bit for bit.
    static func paced(_ times: inout [Double], from lo: Double, to hi: Double, over: [Bool]? = nil, mix: Double = FieldShow.paceMix) {
        guard let sorted = sampled(times, over: over, at: FieldShow.paceKnots) else {
            for i in times.indices { times[i] = hi }
            return
        }
        // equal times make one knot, with the mean of their ranks
        var knots: [Double] = [], sums: [Double] = [], counts: [Double] = []
        for (i, value) in sorted.enumerated() {
            if value != knots.last {
                knots.append(value)
                sums.append(0)
                counts.append(0)
            }
            sums[sums.count - 1] += Double(i) / Double(FieldShow.paceKnots)
            counts[counts.count - 1] += 1
        }
        var means = zip(sums, counts).map { $0 / $1 }
        means[0] = 0
        means[means.count - 1] = 1

        let (first, last) = (knots[0], knots[knots.count - 1])
        let span = max(last - first, 1e-9)
        knots.withUnsafeBufferPointer { knots in
            means.withUnsafeBufferPointer { rank in
                times.withUnsafeMutableBufferPointer { buffer in
                    let out = UncheckedSendable(buffer.baseAddress!)
                    FieldBands.forEach(buffer.count) { cells in
                        var near = 0
                        for i in cells {
                            let t = out.value[i].isFinite ? out.value[i] : last
                            let byRank = knots.count > 1 ? interpolated(t, knots, rank, near: &near) : 1
                            let plain = min(max((t - first) / span, 0), 1)
                            out.value[i] = lo + (mix * byRank + (1 - mix) * plain) * (hi - lo)
                        }
                    }
                }
            }
        }
    }

    /// The finite cells of `times` that `over` allows, sorted, at the ranks `i * (n - 1) / ranks` of
    /// `n` cells for `i` in 0...`ranks`; nil if there are none. Not all the cells are sorted: they are
    /// counted into buckets of equal width, and only the buckets the ranks fall in are.
    private static func sampled(_ times: [Double], over: [Bool]?, at ranks: Int) -> [Double]? {
        var low = Double.infinity, high = -Double.infinity, count = 0
        for i in times.indices where times[i].isFinite && (over?[i] ?? true) {
            low = min(low, times[i])
            high = max(high, times[i])
            count += 1
        }
        guard count > 0 else { return nil }
        let buckets = 1 << 16
        let width = Double(buckets) / (high - low)
        let scale = width.isFinite ? width : 0                       // every cell of one time is one bucket
        func bucket(_ time: Double) -> Int { min(Int((time - low) * scale), buckets - 1) }

        var starts = [Int](repeating: 0, count: buckets + 1)         // where each bucket begins among the sorted cells
        for i in times.indices where times[i].isFinite && (over?[i] ?? true) { starts[bucket(times[i]) + 1] += 1 }
        for b in 0..<buckets { starts[b + 1] += starts[b] }
        let wanted = (0...ranks).map { $0 * (count - 1) / ranks }
        var kept = [Int](repeating: -1, count: buckets)              // where the cells of a bucket with a rank in it are kept
        var keeping = 0
        var b = 0
        for rank in wanted {
            while starts[b + 1] <= rank { b += 1 }
            if kept[b] < 0 {
                kept[b] = keeping
                keeping += starts[b + 1] - starts[b]
            }
        }
        var cells = [Double](repeating: 0, count: keeping)
        var next = kept
        for i in times.indices where times[i].isFinite && (over?[i] ?? true) {
            let b = bucket(times[i])
            if next[b] >= 0 {
                cells[next[b]] = times[i]
                next[b] += 1
            }
        }
        for b in 0..<buckets where kept[b] >= 0 { cells[kept[b]..<(kept[b] + starts[b + 1] - starts[b])].sort() }
        b = 0
        return wanted.map { rank in
            while starts[b + 1] <= rank { b += 1 }
            return cells[kept[b] + rank - starts[b]]
        }
    }

    /// `numpy.interp(t, knots, rank)` for increasing `knots`. `near` is where the last call found its
    /// knot, which is a good guess where the next will, the field being smooth.
    @inline(__always)
    private static func interpolated(
        _ t: Double, _ knots: UnsafeBufferPointer<Double>, _ rank: UnsafeBufferPointer<Double>, near j: inout Int
    ) -> Double {
        let last = knots.count - 1
        if t < knots[0] { return rank[0] }
        if t > knots[last] { return rank[last] }
        // the last knot at or before t: a few steps from the last one, else bisecting
        var steps = 0
        while j < last && knots[j + 1] <= t && steps < 8 {
            j += 1
            steps += 1
        }
        while j > 0 && knots[j] > t && steps < 8 {
            j -= 1
            steps += 1
        }
        if steps == 8 {
            var (lo, hi) = (0, knots.count)
            while lo < hi {
                let mid = (lo + hi) / 2
                if knots[mid] <= t { lo = mid + 1 } else { hi = mid }
            }
            j = lo - 1
        }
        if j == last || knots[j] == t { return rank[j] }
        let slope = (rank[j + 1] - rank[j]) / (knots[j + 1] - knots[j])
        return slope * (t - knots[j]) + rank[j]
    }

    // MARK: Sums

    /// The sum of `values` as numpy adds a contiguous array: eight running sums for a block of up to
    /// 128, two halves (the first a multiple of eight) above that. A fixed order, so it never
    /// depends on the cores, and the same rounding as the reference.
    static func sum(_ values: UnsafeBufferPointer<Double>) -> Double {
        pairwise(values.baseAddress!, values.count)
    }

    private static func pairwise(_ a: UnsafePointer<Double>, _ n: Int) -> Double {
        if n < 8 {
            var sum = 0.0
            for i in 0..<n { sum += a[i] }
            return sum
        }
        if n <= 128 {
            var r = (0..<8).map { a[$0] }
            var i = 8
            while i < n - n % 8 {
                for j in 0..<8 { r[j] += a[i + j] }
                i += 8
            }
            var sum = ((r[0] + r[1]) + (r[2] + r[3])) + ((r[4] + r[5]) + (r[6] + r[7]))
            while i < n {
                sum += a[i]
                i += 1
            }
            return sum
        }
        var half = n / 2
        half -= half % 8
        return pairwise(a, half) + pairwise(a + half, n - half)
    }

    /// The mean and the (population) standard deviation of `values`, as numpy's `mean()` and `std()`.
    static func meanAndDeviation(_ values: [Double]) -> (mean: Double, deviation: Double) {
        let count = Double(values.count)
        let mean = values.withUnsafeBufferPointer { sum($0) } / count
        let squares = values.map { ($0 - mean) * ($0 - mean) }
        let variance = squares.withUnsafeBufferPointer { sum($0) } / count
        return (mean, variance.squareRoot())
    }
}
