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
        width w: Int, height h: Int,
        lab: [SIMD4<Float>],
        importance: [Float],
        labelling: [UInt32],
        palette initial: [SIMD3<Float>],
        minDistance: Float,
        chromaScale: Float,
        iterations: Int
    ) -> [SIMD3<Float>] {
        let unscale = SIMD3<Float>(1, 1 / chromaScale, 1 / chromaScale)
        let cc = RunComponents.label(classes, width: w, height: h)
        let n = cc.count
        guard n > 0 else { return [] }
        // Per region: color sum and pixel count, and the importance-weighted equivalents
        // (paints are refitted toward what they cover in important areas, so a face does
        // not take on the hue of hair that happens to share its paint).
        //
        // Colors come from a region's core: the pixels that were labelled with its paint
        // before simplification. Specks it absorbed (the black stripes on a macaw's white
        // cheek) would otherwise drag it toward a muddy average and a wrong paint.
        var all = [SIMD4<Double>](repeating: .zero, count: n)
        var core = [SIMD4<Double>](repeating: .zero, count: n)
        var coreWeighted = [SIMD4<Double>](repeating: .zero, count: n)
        var coreChroma = [Double](repeating: 0, count: n)
        var allWeighted = [SIMD4<Double>](repeating: .zero, count: n)
        var allChroma = [Double](repeating: 0, count: n)
        cc.labels.storage.withUnsafeBufferPointer { lb in
            lab.withUnsafeBufferPointer { cb in
                importance.withUnsafeBufferPointer { ib in
                    labelling.withUnsafeBufferPointer { ob in
                        for i in 0..<lb.count {
                            let c = SIMD4(Double(cb[i].x), Double(cb[i].y), Double(cb[i].z), 1)
                            let r = Int(lb[i])
                            let weight = Double(PaletteBuilder.paletteWeight(importance: ib[i]))
                            let chroma = (c.y * c.y + c.z * c.z).squareRoot() * weight
                            all[r] += c
                            allWeighted[r] += c * weight
                            allChroma[r] += chroma
                            if ob[i] == cc.classOf[r] {
                                core[r] += c
                                coreWeighted[r] += c * weight
                                coreChroma[r] += chroma
                            }
                        }
                    }
                }
            }
        }
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
        var cls = cc.classOf.map { Int($0) }
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
                if meanChroma > 0.02 * chromaScale {
                    let boost = min(Float(chroma[j] / acc[j].w) / meanChroma, 1.2)
                    c.y *= boost
                    c.z *= boost
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

        // Compact to used paints in a pleasant order.
        let usedIndices = (0..<k).filter { used[$0] }
        let finalColors = usedIndices.map { palette[$0] * unscale }
        let order = PaletteOrdering.order(finalColors)
        var remap = [UInt32](repeating: 0, count: k)
        for (newIndex, orderIndex) in order.enumerated() { remap[usedIndices[orderIndex]] = UInt32(newIndex) }
        let regionClass = cls.map { remap[$0] }
        let count = w * h
        classes.withUnsafeMutableBufferPointer { out in
            cc.labels.storage.withUnsafeBufferPointer { lb in
                regionClass.withUnsafeBufferPointer { rc in
                    let o = UncheckedSendable(out.baseAddress!)
                    let l = UncheckedSendable(lb.baseAddress!)
                    let c = UncheckedSendable(rc.baseAddress!)
                    Parallel.forEachBand(count, minimumBandSize: 16_384) { range in
                        for i in range { o.value[i] = c.value[Int(l.value[i])] }
                    }
                }
            }
        }
        return order.map { finalColors[$0] }
    }
}

/// Orders paints the way a kit would: hue families around the color wheel (starting at
/// red), each from light to dark, followed by the neutrals from white to black.
enum PaletteOrdering {
    /// Chroma below which a paint counts as neutral (grey, white, black).
    static let neutralChroma: Float = 0.028
    /// A hue gap wider than this starts a new family.
    static let familyGap: Float = 0.30
    /// Families wider than this are split at their largest internal gap.
    static let maxFamilySpan: Float = 1.05

    /// Returns indices into `palette` in display order.
    static func order(_ palette: [SIMD3<Float>]) -> [Int] {
        let lch = palette.map { ColorScience.lch($0) }
        var neutrals: [Int] = []
        var chromatic: [(index: Int, hue: Float)] = []
        for (i, c) in lch.enumerated() {
            if c.y < neutralChroma {
                neutrals.append(i)
            } else {
                var h = c.z
                if h < 0 { h += 2 * .pi }
                chromatic.append((i, h))
            }
        }
        neutrals.sort { lch[$0].x > lch[$1].x || (lch[$0].x == lch[$1].x && $0 < $1) }

        var families: [[(index: Int, hue: Float)]] = []
        if !chromatic.isEmpty {
            chromatic.sort { $0.hue < $1.hue || ($0.hue == $1.hue && $0.index < $1.index) }
            // Rotate so the sequence starts right after the widest hue gap; no family then
            // straddles the cut.
            let m = chromatic.count
            var widest = -1, widestGap: Float = -1
            for i in 0..<m {
                let next = chromatic[(i + 1) % m].hue + (i + 1 == m ? 2 * .pi : 0)
                let gap = next - chromatic[i].hue
                if gap > widestGap { widestGap = gap; widest = i }
            }
            var seq: [(index: Int, hue: Float)] = []
            for k in 1...m {
                var e = chromatic[(widest + k) % m]
                if widest + k >= m && widest + 1 < m { e.hue += 2 * .pi }
                seq.append(e)
            }
            var pending: [[(index: Int, hue: Float)]] = [[seq[0]]]
            for e in seq.dropFirst() {
                if e.hue - pending[pending.count - 1].last!.hue > familyGap {
                    pending.append([e])
                } else {
                    pending[pending.count - 1].append(e)
                }
            }
            // Split over-wide families at their largest internal gap.
            while let f = pending.popLast() {
                if f.count > 1 && f.last!.hue - f.first!.hue > maxFamilySpan {
                    var cut = 1, cutGap: Float = -1
                    for i in 1..<f.count where f[i].hue - f[i - 1].hue > cutGap {
                        cutGap = f[i].hue - f[i - 1].hue; cut = i
                    }
                    pending.append(Array(f[..<cut]))
                    pending.append(Array(f[cut...]))
                } else {
                    families.append(f)
                }
            }
            // Families around the wheel starting at red-pink (OKLab hue ≈ 0).
            func startHue(_ f: [(index: Int, hue: Float)]) -> Float {
                let mean = f.reduce(0) { $0 + $1.hue } / Float(f.count)
                var h = mean.truncatingRemainder(dividingBy: 2 * .pi)
                if h < 0 { h += 2 * .pi }
                // Treat deep pinks just below 360° as the start of the wheel.
                return h > 5.9 ? h - 2 * .pi : h
            }
            families.sort { startHue($0) < startHue($1) }
        }

        var result: [Int] = []
        for f in families {
            result += f.map(\.index).sorted { lch[$0].x > lch[$1].x || (lch[$0].x == lch[$1].x && $0 < $1) }
        }
        return result + neutrals
    }
}
