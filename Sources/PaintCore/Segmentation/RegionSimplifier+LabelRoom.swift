import Foundation

extension RegionSimplifier {

    /// Makes every region wide enough for its final number. `simplify` guarantees room for
    /// one digit; a region whose paint ends up with a longer number (`LabelSizing`) needs a
    /// disc of `minRadius(digits:)`. Each too-thin region either takes the paint closest to
    /// its mean colour among those whose number it has room for, keeping its shape, or merges
    /// into its best neighbour (as in `simplify`), whichever costs less colour (merges also
    /// pay for a short shared border); recolouring only within
    /// `SegmentationParameters.labelRecolorLimit`. Recolouring comes first: it often frees a paint and
    /// thereby shortens later numbers.
    ///
    /// Paints left without regions are dropped, keeping the kit order (`kept` lists the
    /// surviving indices into `palette`, ascending). This terminates and keeps every earlier
    /// guarantee: a union of regions is never smaller or thinner than its parts, a recoloured
    /// region's number gets shorter, and dropping paints only lowers numbers. Paints are not
    /// refitted here, since that could reorder them and lengthen a number again.
    ///
    /// - Parameter palette: The final palette in working (chroma-stretched) OKLab, in kit order.
    static func enforceLabelRoom(
        classes: inout [UInt32],
        regions: inout RegionRuns,
        adjacency: inout RegionAdjacency,
        colors: [SIMD4<Float>],
        areaScale: [Float],
        palette: [SIMD3<Float>],
        parameters p: SegmentationParameters,
        cancel: CancellationCheck
    ) throws -> (merges: Int, recolors: Int, kept: [Int]) {
        let maxAreaScale = Self.maxAreaScale(areaScale)
        let maxDigits = LabelSizing.digitCount(of: max(palette.count, 1))
        var current = palette
        var kept = Array(palette.indices)
        var merges = 0, recolors = 0
        while true {
            try cancel.throwIfCancelled()
            let n = regions.count
            // Longest number each region has room for (discs of larger radius contain smaller ones).
            var room = [Int](repeating: 0, count: n)
            for digits in 1...maxDigits {
                let wide = hasInscribedDisc(regions, classes: classes, radius: p.minRadius(digits: digits))
                for r in 0..<n where wide[r] { room[r] = digits }
            }
            try cancel.throwIfCancelled()
            let thin = (0..<n).map { room[$0] < LabelSizing.digitCount(colorIndex: regions.classOf[$0]) }
            guard n > 1, thin.contains(true) else { return (merges, recolors, kept) }

            let recolor = recolorings(regions, adjacency: adjacency, thin: thin, room: room, colors: colors, palette: current, parameters: p)
            if recolor.contains(where: { $0 != nil }) {
                recolors += recolor.count(where: { $0 != nil })
                // Recoloured regions fuse with neighbours that already have their new paint.
                regions.merge(
                    roots: (0..<n).map { Int32($0) }, paint: (0..<n).map { recolor[$0] ?? regions.classOf[$0] },
                    adjacency: &adjacency, classes: &classes)
            } else {
                let merged = try mergeRound(
                    &regions, adjacency: &adjacency, wide: thin.map { !$0 }, classes: &classes, colors: colors,
                    areaScale: areaScale, maxAreaScale: maxAreaScale, palette: current, parameters: p, cancel: cancel)
                if merged == 0 { return (merges, recolors, kept) }
                merges += merged
            }

            var used = [Bool](repeating: false, count: current.count)
            for c in regions.classOf { used[Int(c)] = true }
            guard used.contains(false) else { continue }
            var remap = [UInt32](repeating: 0, count: current.count)
            var next: UInt32 = 0
            for j in current.indices where used[j] {
                remap[j] = next
                next += 1
            }
            // Order-preserving and injective: neighbours keep distinct paints, nothing fuses.
            regions.merge(
                roots: (0..<regions.count).map { Int32($0) }, paint: regions.classOf.map { remap[Int($0)] },
                adjacency: &adjacency, classes: &classes)
            current = current.indices.filter { used[$0] }.map { current[$0] }
            kept = kept.indices.filter { used[$0] }.map { kept[$0] }
        }
    }

    /// For each thin region, the paint to recolour it with, or nil where merging into a
    /// neighbour (`mergeCost`, as in `mergeRound`) is cheaper, or no paint whose number fits is
    /// within the recolour limit.
    private static func recolorings(
        _ regions: RegionRuns, adjacency: RegionAdjacency, thin: [Bool], room: [Int],
        colors: [SIMD4<Float>], palette: [SIMD3<Float>], parameters p: SegmentationParameters
    ) -> [UInt32?] {
        let n = regions.count
        let sums = colors.withUnsafeBufferPointer { cb in
            regions.accumulate(SIMD4<Double>.zero, include: thin) { sum, _, i in
                let c = cb[i]
                sum += SIMD4(Double(c.x), Double(c.y), Double(c.z), 1)
            }
        }
        let mean = sums.map { s in s.w > 0 ? SIMD3(Float(s.x / s.w), Float(s.y / s.w), Float(s.z / s.w)) : .zero }
        var perimeter = [Int32](repeating: 0, count: n)
        for k in adjacency.pairs.indices {
            let (a, b) = RegionAdjacency.regions(of: adjacency.pairs[k])
            if thin[a] { perimeter[a] += adjacency.lengths[k] }
            if thin[b] { perimeter[b] += adjacency.lengths[k] }
        }
        var cheapestMerge = [Float](repeating: .infinity, count: n)
        func consider(_ r: Int, into t: Int, length: Int32) {
            let cost = mergeCost(
                distance: ColorScience.distance(mean[r], palette[Int(regions.classOf[t])]),
                share: Float(length) / Float(perimeter[r]), parameters: p)
            cheapestMerge[r] = min(cheapestMerge[r], cost)
        }
        for k in adjacency.pairs.indices {
            let (a, b) = RegionAdjacency.regions(of: adjacency.pairs[k])
            if thin[a] { consider(a, into: b, length: adjacency.lengths[k]) }
            if thin[b] { consider(b, into: a, length: adjacency.lengths[k]) }
        }
        var result = [UInt32?](repeating: nil, count: n)
        for r in 0..<n where thin[r] {
            var best: UInt32?
            var bestCost = min(cheapestMerge[r], SegmentationParameters.labelRecolorLimit)
            for j in palette.indices where LabelSizing.digitCount(colorIndex: UInt32(j)) <= room[r] {
                let cost = ColorScience.distance(mean[r], palette[j])
                if cost < bestCost { bestCost = cost; best = UInt32(j) }
            }
            result[r] = best
        }
        return result
    }
}
