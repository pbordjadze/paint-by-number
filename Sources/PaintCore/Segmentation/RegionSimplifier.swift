import Foundation

/// Turns a per-pixel palette labelling into paintable regions: every region is big enough
/// to tap and to hold a number, and has no hair-thin parts.
///
/// Each round (1) merges regions that are too small (importance- and texture-scaled area)
/// or too thin (largest inscribed disc) into their best neighbour, smallest first, then
/// (2) peels pixels that no small disc inside their region covers (tendrils, necks, 1-px
/// slivers, pixel corners; see `ThinPartRemoval`). The first round also smooths outlines
/// (`BoundarySmoothing`). Rounds repeat until nothing changes, so the size and radius
/// guarantees hold on the returned map.
///
/// Regions are kept in run-length form (`RegionRuns`) with their adjacency; merges update
/// both directly, so only pixel-level edits (peeling, smoothing) need a fresh labelling.
enum RegionSimplifier {

    static func simplify(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: Grid<SIMD4<Float>>,
        areaScale: [Float],
        palette: [SIMD3<Float>],
        parameters p: SegmentationParameters,
        cancel: CancellationCheck,
        clock: StageClock = StageClock()
    ) throws -> (regions: RegionRuns, adjacency: RegionAdjacency) {
        // Pixel specks and hairlines dissolve far more cheaply at pixel level than as
        // thousands of one-pixel regions in the merge queue.
        _ = clock.measure("segment.regions.thin") {
            ThinPartRemoval.apply(
                classes: &classes, width: w, height: h,
                colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 3)
        }
        try cancel.throwIfCancelled()
        var regions = clock.measure("segment.regions.label") { RegionRuns(classes: classes, width: w, height: h) }
        // Pathologically fragmented input (sensor noise, dithering) would leave hundreds of
        // thousands of regions for the merge queue; a few colour-blind majority passes turn
        // speckle into blobs in linear time first.
        if regions.count > w * h / 20 {
            _ = BoundarySmoothing.apply(
                classes: &classes, width: w, height: h, colors: colors.storage, palette: palette,
                radius: 2, passes: 4, fidelity: 0)
            _ = ThinPartRemoval.apply(
                classes: &classes, width: w, height: h,
                colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 3)
            regions = RegionRuns(classes: classes, width: w, height: h)
        }
        var adjacency = clock.measure("segment.regions.label") { RegionAdjacency(regions) }
        let maxAreaScale = areaScale.withUnsafeBufferPointer { b in
            Parallel.mapBands(b.count, minimumBandSize: 65_536) { range in b[range].max() ?? 0 }.max() ?? 0
        }
        var cleanupRounds = 5
        var round = 0
        while true {
            try cancel.throwIfCancelled()
            // The first round only has specks to deal with; inscribed discs matter once the
            // map is reasonably clean.
            let wide = round > 0
                ? clock.measure("segment.regions.disc") { hasInscribedDisc(regions, classes: classes, radius: p.minRadius) }
                : nil
            let merged = clock.measure("segment.regions.merge") {
                mergeRound(
                    &regions, adjacency: &adjacency, wide: wide, classes: &classes, colors: colors.storage,
                    areaScale: areaScale, maxAreaScale: maxAreaScale, palette: palette, parameters: p)
            }
            try cancel.throwIfCancelled()
            var smoothed = 0
            if round == 0 && p.boundaryPasses > 0 {
                smoothed = clock.measure("segment.regions.smooth") {
                    BoundarySmoothing.apply(
                        classes: &classes, width: w, height: h, colors: colors.storage, palette: palette,
                        radius: p.boundaryRadius, passes: p.boundaryPasses, fidelity: p.boundaryFidelity)
                }
            }
            try cancel.throwIfCancelled()
            var peeled = 0
            if round < cleanupRounds {
                peeled = clock.measure("segment.regions.thin") {
                    ThinPartRemoval.apply(
                        classes: &classes, width: w, height: h,
                        colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 4)
                }
            }
            if smoothed > 0 || peeled > 0 {
                try cancel.throwIfCancelled()
                clock.measure("segment.regions.label") {
                    regions = RegionRuns(classes: classes, width: w, height: h)
                    adjacency = RegionAdjacency(regions)
                }
            }
            if merged == 0 && peeled == 0 && smoothed == 0 && wide != nil { return (regions, adjacency) }
            // Late peels only nudge single pixels at junctions; stop cleaning once that is all
            // that happens and let the remaining rounds settle sizes.
            if round >= 1 && peeled < w * h / 1000 { cleanupRounds = min(cleanupRounds, round + 1) }
            round += 1
        }
    }

    /// Whether each region's largest inscribed disc reaches `radius`, in the exact sense of
    /// `DistanceTransform.interiorDistance` (max over the region ≥ radius).
    ///
    /// interiorDistance(p) = |p − nearest boundary pixel| + ½, so it reaches `radius` iff no
    /// boundary pixel (one with a differently labelled 4-neighbour, or on the image edge)
    /// lies within √((radius − ½)²) of p. That is a small local test, much cheaper than a
    /// full distance transform every round. 4-neighbours share a region exactly when they
    /// share a paint, so the test runs on the paint map; the disc, a union of centred
    /// horizontal spans, is checked with byte-wise span erosions.
    static func hasInscribedDisc(_ regions: RegionRuns, classes: [UInt32], radius: Float) -> [Bool] {
        let w = regions.width, h = regions.height, n = w * h
        var result = [Bool](repeating: false, count: regions.count)
        let reach = max(radius - 0.5, 0)
        let limit = reach * reach
        let r = Int(reach.rounded(.up))
        guard w > 2 * r, h > 2 * r else {
            if limit <= 0 { for i in 0..<regions.count { result[i] = true } }
            return result
        }
        guard w >= 3, h >= 3 else { return result }  // no interior pixels
        // Row dy of the disc spans dx ∈ -span[dy + r]...span[dy + r] (-1: empty row).
        let span: [Int] = (-r...r).map { (dy: Int) -> Int in
            (0...r).last { (dx: Int) -> Bool in Float(dx * dx + dy * dy) < limit } ?? -1
        }
        let maxSpan = max(span.max() ?? 0, 0)
        // Map k (at offset k·n): interior pixels whose ±k horizontal neighbours are all interior.
        var eroded = [UInt8](repeating: 0, count: (maxSpan + 1) * n)
        let bands: [[Bool]] = classes.withUnsafeBufferPointer { cb in
            eroded.withUnsafeMutableBufferPointer { mb in
                let c = UncheckedSendable(cb.baseAddress!)
                let maps = UncheckedSendable(mb.baseAddress!)
                Parallel.forEachBand(h - 2, minimumBandSize: 16) { rows in
                    for yy in rows {
                        let row = c.value + (yy + 1) * w
                        let up = row - w, down = row + w
                        let dst = maps.value + (yy + 1) * w
                        for x in 1..<(w - 1) {
                            let v = row[x]
                            let same = (row[x - 1] == v) && (row[x + 1] == v) && (up[x] == v) && (down[x] == v)
                            dst[x] = same ? 1 : 0
                        }
                    }
                }
                if maxSpan > 0 {
                    for k in 1...maxSpan {
                        Parallel.forEachBand(h, minimumBandSize: 32) { rows in
                            for y in rows {
                                let src = maps.value + (k - 1) * n + y * w, dst = maps.value + k * n + y * w
                                if k == 1 {
                                    for x in 1..<(w - 1) { dst[x] = src[x - 1] & src[x] & src[x + 1] }
                                } else {
                                    for x in k..<(w - k) { dst[x] = src[x - 1] & src[x + 1] }
                                }
                            }
                        }
                    }
                }
                return regions.rowStart.withUnsafeBufferPointer { rsb in
                    regions.start.withUnsafeBufferPointer { sb in
                        regions.end.withUnsafeBufferPointer { eb in
                            regions.label.withUnsafeBufferPointer { lb in
                                let rs = UncheckedSendable(rsb), s = UncheckedSendable(sb)
                                let e = UncheckedSendable(eb), l = UncheckedSendable(lb)
                                return Parallel.mapBands(h - 2 * r, minimumBandSize: 32) { rows -> [Bool] in
                                    var found = [Bool](repeating: false, count: regions.count)
                                    var ok = [UInt8](repeating: 0, count: w)
                                    ok.withUnsafeMutableBufferPointer { okb in
                                        let okp = okb.baseAddress!
                                        for yy in rows {
                                            let y = yy + r
                                            let centre = maps.value + y * w
                                            for x in r..<(w - r) { okp[x] = centre[x] }
                                            for dy in -r...r where span[dy + r] >= 0 {
                                                let src = maps.value + span[dy + r] * n + (y + dy) * w
                                                for x in r..<(w - r) { okp[x] &= src[x] }
                                            }
                                            for k in rs.value[y]..<rs.value[y + 1] {
                                                let region = Int(l.value[k])
                                                if found[region] { continue }
                                                let x0 = max(Int(s.value[k]), r), x1 = min(Int(e.value[k]), w - r)
                                                var x = x0
                                                while x < x1 && okp[x] == 0 { x += 1 }
                                                if x < x1 { found[region] = true }
                                            }
                                        }
                                    }
                                    return found
                                }
                            }
                        }
                    }
                }
            }
        }
        for band in bands {
            for i in 0..<result.count where band[i] { result[i] = true }
        }
        return result
    }

    // MARK: - Merging

    struct Link {
        var region: Int32
        var length: Int32
    }

    /// Merges every undersized or too-thin region into its best neighbour, smallest (relative
    /// to its own threshold) first. Rewrites merged regions' paint per pixel, updates the
    /// regions and their adjacency, and returns the number of merges.
    static func mergeRound(
        _ regions: inout RegionRuns,
        adjacency: inout RegionAdjacency,
        wide: [Bool]?,
        classes: inout [UInt32],
        colors: [SIMD4<Float>],
        areaScale: [Float],
        maxAreaScale: Float,
        palette: [SIMD3<Float>],
        parameters p: SegmentationParameters
    ) -> Int {
        let n = regions.count
        guard n > 1 else { return 0 }
        var thin = [Bool](repeating: false, count: n)
        if let wide { for r in 0..<n { thin[r] = !wide[r] } }
        // Regions whose area alone guarantees a relative area ≥ 1 (the area-scale sum is at
        // most area × max scale) and that are wide never enter the queue, and neither does
        // anything merged into them; their colour and scale sums are never needed.
        let bigArea = Double(p.minArea) * Double(maxAreaScale) * 1.001 + 1
        var big = [Bool](repeating: false, count: n)
        for r in 0..<n { big[r] = Double(regions.area[r]) >= bigArea && !thin[r] }

        // OKLab sum and area-scale sum per queued region, accumulated in raster order.
        var sums = colors.withUnsafeBufferPointer { cb in
            areaScale.withUnsafeBufferPointer { ab in
                regions.accumulate(SIMD4<Double>.zero, include: big.map { !$0 }) { sum, _, i in
                    let c = cb[i]
                    sum += SIMD4(Double(c.x), Double(c.y), Double(c.z), Double(ab[i]))
                }
            }
        }

        // Neighbour lists of queued regions (merged lists of big ones are never read).
        var links = [[Link]](repeating: [], count: n)
        for k in adjacency.pairs.indices {
            let a = Int(adjacency.pairs[k] >> 32), b = Int(adjacency.pairs[k] & 0xFFFF_FFFF)
            let length = adjacency.lengths[k]
            if !big[a] { links[a].append(Link(region: Int32(b), length: length)) }
            if !big[b] { links[b].append(Link(region: Int32(a), length: length)) }
        }

        var area = regions.area
        var cls = regions.classOf
        var parent = (0..<n).map { Int32($0) }
        var stamp = [Int32](repeating: 0, count: n)

        func find(_ x: Int) -> Int {
            var r = x
            while Int(parent[r]) != r { r = Int(parent[r]) }
            var c = x
            while Int(parent[c]) != r {
                let next = Int(parent[c])
                parent[c] = Int32(r)
                c = next
            }
            return r
        }
        // Area relative to the region's own minimum (base × its mean area scale).
        func relativeArea(_ r: Int) -> Float {
            Float(Double(area[r]) * Double(area[r]) / (Double(p.minArea) * sums[r].w))
        }

        var heap = MinHeap()
        for r in 0..<n where !big[r] {
            let key = relativeArea(r)
            if key < 1 || thin[r] { heap.push(key, Int32(r), 0) }
        }

        var merges = 0
        var compacted: [Link] = []
        while let item = heap.pop() {
            let r = Int(item.region)
            if Int(parent[r]) != r || stamp[r] != item.stamp { continue }
            let key = relativeArea(r)
            guard key < 1 || thin[r] else { continue }

            // Compact the neighbour list: resolve merged ids, drop self links, sum lengths.
            var list = links[r]
            for k in list.indices { list[k].region = Int32(find(Int(list[k].region))) }
            list.removeAll { Int($0.region) == r }
            guard !list.isEmpty else { links[r] = []; continue }
            list.sort { $0.region < $1.region }
            compacted.removeAll(keepingCapacity: true)
            var perimeter: Int32 = 0
            for l in list {
                perimeter += l.length
                if let last = compacted.last, last.region == l.region {
                    compacted[compacted.count - 1].length += l.length
                } else {
                    compacted.append(l)
                }
            }

            // Best neighbour: closest paint to this region's mean color, favouring long
            // shared borders so shapes stay compact.
            let s = sums[r] / Double(area[r])
            let mean = SIMD3(Float(s.x), Float(s.y), Float(s.z))
            var target = -1
            var bestCost = Float.infinity
            for l in compacted {
                let t = Int(l.region)
                let dc = ColorScience.distance(mean, palette[Int(cls[t])])
                let share = Float(l.length) / Float(perimeter)
                let cost = dc + p.mergeShareWeight * (1 - share)
                if cost < bestCost { bestCost = cost; target = t }
            }

            let root = area[target] >= area[r] ? target : r
            let other = root == target ? r : target
            parent[other] = Int32(root)
            area[root] = area[r] + area[target]
            sums[root] = sums[r] + sums[target]
            cls[root] = cls[target]
            thin[root] = false  // re-checked by the next round's inscribed-disc test
            big[root] = big[r] || big[target]
            if big[root] {
                links[root] = []
            } else if root == target {
                links[root].append(contentsOf: compacted)
            } else {
                links[root] = compacted + links[other]
            }
            links[other] = []
            stamp[root] &+= 1
            merges += 1
            if !big[root] {
                let newKey = relativeArea(root)
                if newKey < 1 { heap.push(newKey, Int32(root), stamp[root]) }
            }
        }
        guard merges > 0 else { return 0 }
        for r in 0..<n { parent[r] = Int32(find(r)) }
        regions.merge(roots: parent, paint: cls, adjacency: &adjacency, classes: &classes)
        return merges
    }
}

/// Binary min-heap of (key, region, stamp) used for smallest-first merging. Ties break on
/// region id so the merge order is fully deterministic.
struct MinHeap {
    struct Item {
        var key: Float
        var region: Int32
        var stamp: Int32
    }

    private var items: [Item] = []

    @inline(__always)
    private static func less(_ a: Item, _ b: Item) -> Bool {
        a.key < b.key || (a.key == b.key && a.region < b.region)
    }

    mutating func push(_ key: Float, _ region: Int32, _ stamp: Int32) {
        items.append(Item(key: key, region: region, stamp: stamp))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if !Self.less(items[i], items[parent]) { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> Item? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            let n = items.count
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < n && Self.less(items[l], items[m]) { m = l }
                if r < n && Self.less(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return first
    }
}
