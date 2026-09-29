import Foundation

/// Final palette polish once regions are settled: paints are refitted to the pixels they
/// actually cover, each region takes the paint closest to its own mean color, paints too
/// similar to tell apart are pushed apart (or merged as a last resort) and unused ones dropped.
///
/// Every change here only recolors whole regions, and regions that end up sharing a paint
/// simply fuse, so the size and thickness guarantees established earlier are preserved
/// (a union of regions is never smaller or thinner than its parts).
enum PaletteRefiner {

    static func refine(
        classes: inout [UInt32],
        regions: inout RegionRuns,
        adjacency: inout RegionAdjacency,
        lab: [SIMD4<Float>],
        importance: [Float],
        labelling: [UInt32],
        palette initial: [SIMD3<Float>],
        minDistance: Float,
        chromaScale: Float,
        iterations: Int,
        cancel: CancellationCheck = .none
    ) throws -> [SIMD3<Float>] {
        let unscale = SIMD3<Float>(1, 1 / chromaScale, 1 / chromaScale)
        let n = regions.count
        guard n > 0 else { return [] }
        // Per region: color sum and pixel count, and the importance-weighted equivalents
        // (paints are refitted toward what they cover in important areas, so a face does
        // not take on the hue of hair that happens to share its paint).
        //
        // Colors come from a region's core: the pixels that were labelled with its paint
        // before simplification. Specks it absorbed (the black stripes on a macaw's white
        // cheek) would otherwise drag it toward a muddy average and a wrong paint.
        struct Sums {
            var all = SIMD4<Double>.zero, allWeighted = SIMD4<Double>.zero, allChroma = 0.0
            var core = SIMD4<Double>.zero, coreWeighted = SIMD4<Double>.zero, coreChroma = 0.0
        }
        let regionSums: [Sums] = lab.withUnsafeBufferPointer { cb in
            importance.withUnsafeBufferPointer { ib in
                labelling.withUnsafeBufferPointer { ob in
                    regions.classOf.withUnsafeBufferPointer { paint in
                        regions.accumulate(Sums()) { s, r, i in
                            let c = SIMD4(Double(cb[i].x), Double(cb[i].y), Double(cb[i].z), 1)
                            let weight = Double(PaletteBuilder.paletteWeight(importance: ib[i]))
                            let chroma = (c.y * c.y + c.z * c.z).squareRoot() * weight
                            s.all += c
                            s.allWeighted += c * weight
                            s.allChroma += chroma
                            if ob[i] == paint[r] {
                                s.core += c
                                s.coreWeighted += c * weight
                                s.coreChroma += chroma
                            }
                        }
                    }
                }
            }
        }
        try cancel.throwIfCancelled()
        let all = regionSums.map(\.all), allWeighted = regionSums.map(\.allWeighted)
        let allChroma = regionSums.map(\.allChroma), core = regionSums.map(\.core)
        let coreWeighted = regionSums.map(\.coreWeighted), coreChroma = regionSums.map(\.coreChroma)
        var sums = all
        var weighted = allWeighted
        var weightedChroma = allChroma
        for r in 0..<n where core[r].w >= 0.25 * all[r].w && coreWeighted[r].w > 0 {
            let scale = allWeighted[r].w / coreWeighted[r].w
            sums[r] = core[r] * (all[r].w / core[r].w)
            weighted[r] = coreWeighted[r] * scale
            weightedChroma[r] = coreChroma[r] * scale
        }
        let means = sums.map { SIMD3(Float($0.x / $0.w), Float($0.y / $0.w), Float($0.z / $0.w)) }
        var cls = regions.classOf.map { Int($0) }
        var palette = initial
        let k = palette.count
        var used = [Bool](repeating: false, count: k)
        for r in 0..<n { used[cls[r]] = true }
        let separation = PaletteBuilder.Separation(minDistance: minDistance * 1.01, metric: unscale)

        // Paint j := mean of the pixels it covers, then nudge apart any that became too
        // similar to tell apart. Averaging pixels of slightly different hues shortens the
        // chroma vector, and flat paint already reads duller than textured photo, so the
        // paint keeps the pixels' average chroma (bounded) along the mean hue.
        func refit() {
            var acc = [SIMD4<Double>](repeating: .zero, count: k)
            var chroma = [Double](repeating: 0, count: k)
            for r in 0..<n {
                acc[cls[r]] += weighted[r]
                chroma[cls[r]] += weightedChroma[r]
            }
            for j in 0..<k where acc[j].w > 0 {
                var c = SIMD3(Float(acc[j].x / acc[j].w), Float(acc[j].y / acc[j].w), Float(acc[j].z / acc[j].w))
                let meanChroma = (c.y * c.y + c.z * c.z).squareRoot()
                // Near-neutral paints are left alone: there the pixels' chroma is mostly a
                // cast or noise, and boosting it would turn white teeth or grey stone minty.
                let vividness = min(max((meanChroma / chromaScale - 0.04) / 0.03, 0), 1)
                if vividness > 0 {
                    let boost = min(Float(chroma[j] / acc[j].w) / meanChroma, 1.2)
                    let factor = 1 + (boost - 1) * vividness
                    c.y *= factor
                    c.z *= factor
                }
                palette[j] = c
            }
            let active = (0..<k).filter { used[$0] }
            var colors = active.map { palette[$0] }
            separation.separate(&colors, weights: active.map { Float(acc[$0].w) })
            for (i, j) in active.enumerated() { palette[j] = colors[i] }
        }

        for _ in 0..<iterations {
            refit()
            var changed = false
            for r in 0..<n {
                let m = means[r]
                let current = ColorScience.distance(m, palette[cls[r]])
                var best = cls[r]
                var bestD = current - 0.004  // hysteresis: only clearly better paints win
                for j in 0..<k where used[j] {
                    let d = ColorScience.distance(m, palette[j])
                    if d < bestD { bestD = d; best = j }
                }
                if best != cls[r] { cls[r] = best; changed = true }
            }
            used = [Bool](repeating: false, count: k)
            for r in 0..<n { used[cls[r]] = true }
            if !changed { break }
        }
        refit()

        // Merge whatever could not be pushed apart.
        var weight = [Double](repeating: 0, count: k)
        for r in 0..<n { weight[cls[r]] += sums[r].w }
        while true {
            var bi = -1, bj = -1
            var best = minDistance
            for i in 0..<k where used[i] {
                for j in (i + 1)..<k where used[j] {
                    let d = ColorScience.distance(palette[i] * unscale, palette[j] * unscale)
                    if d < best { best = d; bi = i; bj = j }
                }
            }
            if bi < 0 { break }
            let wi = Float(weight[bi]), wj = Float(weight[bj])
            palette[bi] = (palette[bi] * wi + palette[bj] * wj) / (wi + wj)
            weight[bi] += weight[bj]
            used[bj] = false
            for r in 0..<n where cls[r] == bj { cls[r] = bi }
        }

        try cancel.throwIfCancelled()
        // Compact to used paints in a pleasant order.
        let usedIndices = (0..<k).filter { used[$0] }
        let finalColors = usedIndices.map { palette[$0] * unscale }
        let order = PaletteOrdering.order(finalColors)
        var remap = [UInt32](repeating: 0, count: k)
        for (newIndex, orderIndex) in order.enumerated() { remap[usedIndices[orderIndex]] = UInt32(newIndex) }
        // Recolor regions; neighbours that now share a paint fuse.
        regions.merge(roots: (0..<n).map { Int32($0) }, paint: cls.map { remap[$0] }, adjacency: &adjacency, classes: &classes)
        return order.map { finalColors[$0] }
    }
}
