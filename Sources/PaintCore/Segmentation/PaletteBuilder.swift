import Foundation

/// Chooses the paint colors: weighted k-means++ in OKLab over a color histogram.
///
/// Clustering histogram bins instead of pixels makes k-means cheap enough for several
/// refinement passes, and compressing bin weights with a power < 1 stops large flat areas
/// (sky, backdrop) from absorbing most clusters while small, distinctive colors (eyes, a
/// red flower, lips) vanish.
enum PaletteBuilder {

    struct Samples {
        var colors: [SIMD3<Float>]
        var weights: [Float]
    }

    static func build(
        colors: Grid<SIMD4<Float>>,
        importance: [Float],
        parameters p: SegmentationParameters,
        cancel: CancellationCheck
    ) throws -> [SIMD3<Float>] {
        let samples = histogram(colors: colors, importance: importance, gamma: p.histogramGamma)
        guard !samples.colors.isEmpty else { return [] }
        let k = min(p.colorCount, samples.colors.count)
        // Separation is judged in true OKLab, not the chroma-stretched working space.
        let separation = Separation(
            minDistance: p.minPaletteDistance * 1.1,
            metric: SIMD3(1, 1 / p.chromaScale, 1 / p.chromaScale))
        var rng = SplitMix64(seed: p.seed)
        var centers = seedPlusPlus(samples, k: k, rng: &rng)
        centers = lloyd(samples, centers: centers, iterations: 30, separation: separation)
        try cancel.throwIfCancelled()

        // Refill if separation left gaps, then escape k-means' local minima by swapping the
        // least useful paint for the most useful missing one.
        for _ in 0..<3 {
            var added = false
            while centers.count < k, let c = bestAddition(samples, centers: centers, separation: separation) {
                centers.append(c)
                added = true
            }
            if added { centers = lloyd(samples, centers: centers, iterations: 20, separation: separation) }
            let swapped = improveBySwapping(samples, centers: &centers, separation: separation, cancel: cancel)
            try cancel.throwIfCancelled()
            if !swapped && centers.count == k { break }
        }
        let weights = clusterWeights(samples, centers: centers)
        _ = mergeClose(&centers, weights: weights, separation: separation)
        return centers
    }

    // MARK: - Local search

    /// Weighted squared distance of every sample to its nearest and second-nearest center.
    static func nearestTwo(_ s: Samples, centers: [SIMD3<Float>]) -> (d1: [Float], d2: [Float], index: [Int32]) {
        let m = s.colors.count
        var d1 = [Float](repeating: .infinity, count: m)
        var d2 = [Float](repeating: .infinity, count: m)
        var index = [Int32](repeating: 0, count: m)
        for i in 0..<m {
            let c = s.colors[i]
            var a = Float.infinity, b = Float.infinity, ai = 0
            for (j, center) in centers.enumerated() {
                let d = distanceSquared(c, center)
                if d < a { b = a; a = d; ai = j } else if d < b { b = d }
            }
            d1[i] = a; d2[i] = b; index[i] = Int32(ai)
        }
        return (d1, d2, index)
    }

    /// The sample color whose addition as a center reduces the weighted error most.
    /// Candidates are the samples contributing most to the current error.
    static func bestAddition(_ s: Samples, centers: [SIMD3<Float>], separation: Separation) -> SIMD3<Float>? {
        bestAddition(s, d1: nearestTwo(s, centers: centers).d1, centers: centers, separation: separation)?.color
    }

    static func bestAddition(
        _ s: Samples, d1: [Float], centers: [SIMD3<Float>], separation: Separation
    ) -> (color: SIMD3<Float>, gain: Float)? {
        let m = s.colors.count
        var order = Array(0..<m)
        order.sort { s.weights[$0] * d1[$0] > s.weights[$1] * d1[$1] || (s.weights[$0] * d1[$0] == s.weights[$1] * d1[$1] && $0 < $1) }
        var candidates: [Int] = []
        for i in order where candidates.count < 48 {
            if centers.allSatisfy({ separation.isDistinct(s.colors[i], $0) }) { candidates.append(i) }
        }
        guard !candidates.isEmpty else { return nil }
        let gains = Parallel.mapBands(candidates.count, minimumBandSize: 4) { range -> [Float] in
            range.map { ci in
                let c = s.colors[candidates[ci]]
                var gain: Float = 0
                for i in 0..<m {
                    let d = distanceSquared(s.colors[i], c)
                    if d < d1[i] { gain += s.weights[i] * (d1[i] - d) }
                }
                return gain
            }
        }.flatMap { $0 }
        var best = 0
        for i in 1..<gains.count where gains[i] > gains[best] { best = i }
        return (s.colors[candidates[best]], gains[best])
    }

    /// Swaps centers while replacing the least useful one by the best addition lowers the
    /// weighted error. Returns whether any swap was kept.
    static func improveBySwapping(
        _ s: Samples, centers: inout [SIMD3<Float>], separation: Separation, cancel: CancellationCheck
    ) -> Bool {
        guard centers.count > 1 else { return false }
        var improved = false
        var cost = totalCost(s, centers: centers)
        for _ in 0..<(2 * centers.count) {
            if cancel.isCancelled { break }
            let (d1, d2, index) = nearestTwo(s, centers: centers)
            guard let addition = bestAddition(s, d1: d1, centers: centers, separation: separation) else { break }
            var loss = [Float](repeating: 0, count: centers.count)
            for i in 0..<s.colors.count { loss[Int(index[i])] += s.weights[i] * (d2[i] - d1[i]) }
            var victim = 0
            for j in 1..<centers.count where loss[j] < loss[victim] { victim = j }
            if Tune.debug { debugLog("swap: gain \(addition.gain) loss \(loss[victim]) cost \(cost) add \(addition.color) victim \(centers[victim])") }
            // Cheap estimate first; confirm with a real k-means run.
            guard addition.gain > loss[victim] * 1.05 else { break }
            var trial = centers
            trial[victim] = addition.color
            trial = lloyd(s, centers: trial, iterations: 15, separation: separation)
            let trialCost = totalCost(s, centers: trial)
            if Tune.debug { debugLog("  trial cost \(trialCost)") }
            guard trialCost < cost * 0.995 else { break }
            centers = trial
            cost = trialCost
            improved = true
        }
        return improved
    }

    static func totalCost(_ s: Samples, centers: [SIMD3<Float>]) -> Float {
        var cost: Float = 0
        for i in 0..<s.colors.count {
            var best = Float.infinity
            for c in centers { best = min(best, distanceSquared(s.colors[i], c)) }
            cost += s.weights[i] * best
        }
        return cost
    }

    // MARK: - Histogram

    /// Bins a regular subsample of the image into a 64³ OKLab grid. Each bin keeps its
    /// weighted mean color; its weight is (Σ pixel weights)^gamma.
    static func histogram(colors: Grid<SIMD4<Float>>, importance: [Float], gamma: Float) -> Samples {
        let w = colors.width, h = colors.height, n = w * h
        guard n > 0 else { return Samples(colors: [], weights: []) }
        let step = max(1, Int((Double(n) / 120_000).squareRoot().rounded(.up)))
        let levels = 64
        var index = [Int32](repeating: -1, count: levels * levels * levels)
        var sums: [SIMD4<Float>] = []  // xyz = weighted color sum, w = weight sum
        sums.reserveCapacity(8192)
        colors.storage.withUnsafeBufferPointer { c in
            importance.withUnsafeBufferPointer { imp in
                var y = step / 2
                while y < h {
                    var x = step / 2
                    while x < w {
                        let i = y * w + x
                        let lab = c[i]
                        let lq = min(max(Int(lab.x * Float(levels)), 0), levels - 1)
                        let aq = min(max(Int((lab.y + 0.4) * Float(levels) / 0.8), 0), levels - 1)
                        let bq = min(max(Int((lab.z + 0.4) * Float(levels) / 0.8), 0), levels - 1)
                        let key = (lq * levels + aq) * levels + bq
                        var slot = Int(index[key])
                        if slot < 0 {
                            slot = sums.count
                            index[key] = Int32(slot)
                            sums.append(.zero)
                        }
                        let weight = 0.25 + imp[i]
                        sums[slot] += SIMD4(lab.x * weight, lab.y * weight, lab.z * weight, weight)
                        x += step
                    }
                    y += step
                }
            }
        }
        var out = Samples(colors: [], weights: [])
        out.colors.reserveCapacity(sums.count)
        out.weights.reserveCapacity(sums.count)
        for s in sums where s.w > 0 {
            out.colors.append(SIMD3(s.x, s.y, s.z) / s.w)
            out.weights.append(pow(s.w, gamma))
        }
        return out
    }

    // MARK: - k-means

    static func seedPlusPlus(_ s: Samples, k: Int, rng: inout SplitMix64) -> [SIMD3<Float>] {
        let m = s.colors.count
        // First center: the heaviest bin (deterministic and always a real, common color).
        var first = 0
        for i in 1..<m where s.weights[i] > s.weights[first] { first = i }
        var centers = [s.colors[first]]
        var d2 = s.colors.map { distanceSquared($0, s.colors[first]) }
        while centers.count < k {
            var total: Double = 0
            for i in 0..<m { total += Double(s.weights[i] * d2[i]) }
            guard total > 0 else { break }
            let target = Double(rng.nextFloat()) * total
            var acc: Double = 0
            var pick = m - 1
            for i in 0..<m {
                acc += Double(s.weights[i] * d2[i])
                if acc >= target { pick = i; break }
            }
            let c = s.colors[pick]
            centers.append(c)
            for i in 0..<m { d2[i] = min(d2[i], distanceSquared(s.colors[i], c)) }
        }
        return centers
    }

    static func assign(_ s: Samples, centers: [SIMD3<Float>]) -> [Int32] {
        let m = s.colors.count
        var assignment = [Int32](repeating: 0, count: m)
        let packed = centers.map { SIMD4($0, 0) }
        s.colors.withUnsafeBufferPointer { cb in
            assignment.withUnsafeMutableBufferPointer { ab in
                packed.withUnsafeBufferPointer { pb in
                    let cp = UncheckedSendable(cb.baseAddress!)
                    let ap = UncheckedSendable(ab.baseAddress!)
                    let pp = UncheckedSendable(pb.baseAddress!)
                    let k = pb.count
                    Parallel.forEachBand(m, minimumBandSize: 2048) { range in
                        for i in range {
                            let c = SIMD4(cp.value[i], 0)
                            var best = 0
                            var bestD = Float.infinity
                            for j in 0..<k {
                                let d = c - pp.value[j]
                                let dd = (d * d).sum()
                                if dd < bestD { bestD = dd; best = j }
                            }
                            ap.value[i] = Int32(best)
                        }
                    }
                }
            }
        }
        return assignment
    }

    /// Weighted Lloyd iterations; after each update, centers closer than the separation
    /// distance are pushed apart so the palette keeps its size instead of collapsing.
    static func lloyd(
        _ s: Samples, centers initial: [SIMD3<Float>], iterations: Int, separation: Separation
    ) -> [SIMD3<Float>] {
        var centers = initial
        var assignment: [Int32] = []
        for _ in 0..<iterations {
            let next = assign(s, centers: centers)
            if next == assignment { break }
            assignment = next
            var sums = [SIMD4<Double>](repeating: .zero, count: centers.count)
            for i in 0..<s.colors.count {
                let c = s.colors[i], w = Double(s.weights[i])
                sums[Int(assignment[i])] += SIMD4(Double(c.x) * w, Double(c.y) * w, Double(c.z) * w, w)
            }
            for j in 0..<centers.count where sums[j].w > 0 {
                centers[j] = SIMD3(Float(sums[j].x / sums[j].w), Float(sums[j].y / sums[j].w), Float(sums[j].z / sums[j].w))
            }
            separation.separate(&centers, weights: sums.map { Float($0.w) })
        }
        return centers
    }

    static func clusterWeights(_ s: Samples, centers: [SIMD3<Float>]) -> [Float] {
        let assignment = assign(s, centers: centers)
        var weights = [Float](repeating: 0, count: centers.count)
        for i in 0..<s.colors.count { weights[Int(assignment[i])] += s.weights[i] }
        return weights
    }

    /// Repeatedly merges the closest pair of centers (weighted mean) while it is closer than
    /// the separation distance. Returns whether anything was merged.
    @discardableResult
    static func mergeClose(_ centers: inout [SIMD3<Float>], weights initial: [Float], separation: Separation) -> Bool {
        var weights = initial.map { max($0, 1e-6) }
        var merged = false
        let limit = separation.minDistance * separation.minDistance
        while centers.count > 1 {
            var bi = 0, bj = 0
            var best = Float.infinity
            for i in 0..<centers.count {
                for j in (i + 1)..<centers.count {
                    let d = separation.distanceSquared(centers[i], centers[j])
                    if d < best { best = d; bi = i; bj = j }
                }
            }
            guard best < limit else { break }
            let wi = weights[bi], wj = weights[bj]
            centers[bi] = (centers[bi] * wi + centers[bj] * wj) / (wi + wj)
            weights[bi] = wi + wj
            centers.remove(at: bj)
            weights.remove(at: bj)
            merged = true
        }
        return merged
    }

    /// Minimum distance between paints, measured after scaling differences by `metric`.
    struct Separation {
        var minDistance: Float
        var metric: SIMD3<Float>

        @inline(__always)
        func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
            let d = (a - b) * metric
            return (d * d).sum()
        }

        @inline(__always)
        func isDistinct(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
            distanceSquared(a, b) >= minDistance * minDistance
        }

        /// Pushes pairs of centers that are too close apart along their difference, the
        /// lighter (less used) one moving more. Returns whether all pairs end up distinct.
        @discardableResult
        func separate(_ centers: inout [SIMD3<Float>], weights: [Float], sweeps: Int = 24) -> Bool {
            let limit = minDistance * minDistance
            for _ in 0..<sweeps {
                var moved = false
                for i in 0..<centers.count {
                    for j in (i + 1)..<centers.count {
                        let t2 = distanceSquared(centers[i], centers[j])
                        if t2 >= limit { continue }
                        var d = centers[i] - centers[j]
                        var t = t2.squareRoot()
                        if t < 1e-6 {
                            d = SIMD3(centers[i].x < 0.5 ? 1e-3 : -1e-3, 0, 0)
                            t = distanceSquared(d, .zero).squareRoot()
                        }
                        // Scale the difference so the pair lands just past the limit.
                        let step = d * (minDistance * 1.001 / t - 1)
                        let wi = max(weights[i], 1e-6), wj = max(weights[j], 1e-6)
                        centers[i] += step * (wj / (wi + wj))
                        centers[j] -= step * (wi / (wi + wj))
                        centers[i].x = min(max(centers[i].x, 0), 1)
                        centers[j].x = min(max(centers[j].x, 0), 1)
                        moved = true
                    }
                }
                if !moved { return true }
            }
            for i in 0..<centers.count {
                for j in (i + 1)..<centers.count where !isDistinct(centers[i], centers[j]) { return false }
            }
            return true
        }
    }

    @inline(__always)
    static func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d * d).sum()
    }
}
