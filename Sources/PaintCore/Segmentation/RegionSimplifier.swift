import Foundation

/// Turns a per-pixel palette labelling into paintable regions: every region is big enough
/// to tap and to hold a number, and has no hair-thin parts. Once the palette is final,
/// `enforceLabelRoom` (RegionSimplifier+LabelRoom.swift) makes room for numbers with more digits.
///
/// Each round (1) merges regions that are too small (importance- and texture-scaled area,
/// counting for less the closer a region's colour is to a neighbouring paint), too thin
/// (largest inscribed disc) or mere transition strips along blurred edges into their best
/// neighbour, smallest first (see `mergeRound`), then (2) peels pixels that no small disc
/// inside their region covers (tendrils, necks, 1-px slivers, pixel corners; see
/// `ThinPartRemoval`). The first round also smooths outlines (`BoundarySmoothing`). Rounds
/// repeat until nothing changes, so the size and radius guarantees hold on the returned map.
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
        _ = try clock.measure("segment.regions.thin") {
            try ThinPartRemoval.apply(
                classes: &classes, width: w, height: h,
                colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 3,
                cancel: cancel)
        }
        try cancel.throwIfCancelled()
        var regions = clock.measure("segment.regions.label") { RegionRuns(classes: classes, width: w, height: h) }
        try cancel.throwIfCancelled()
        // Pathologically fragmented input (sensor noise, dithering) would leave hundreds of
        // thousands of regions for the merge queue; a few colour-blind majority passes turn
        // speckle into blobs in linear time first.
        if regions.count > w * h / 20 {
            _ = try BoundarySmoothing.apply(
                classes: &classes, width: w, height: h, colors: colors.storage, palette: palette,
                radius: 2, passes: 4, fidelity: 0, cancel: cancel)
            _ = try ThinPartRemoval.apply(
                classes: &classes, width: w, height: h,
                colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 3,
                cancel: cancel)
            regions = RegionRuns(classes: classes, width: w, height: h)
            try cancel.throwIfCancelled()
        }
        var adjacency = clock.measure("segment.regions.adjacency") { RegionAdjacency(regions) }
        let maxAreaScale = Self.maxAreaScale(areaScale)
        var cleanupRounds = 5
        var round = 0
        while true {
            try cancel.throwIfCancelled()
            // The first round only has specks to deal with; inscribed discs matter once the
            // map is reasonably clean.
            let wide = round > 0
                ? clock.measure("segment.regions.disc") { hasInscribedDisc(regions, classes: classes, radius: p.minRadius) }
                : nil
            if wide != nil { try cancel.throwIfCancelled() }
            let merged = try clock.measure("segment.regions.merge") {
                try mergeRound(
                    &regions, adjacency: &adjacency, wide: wide, classes: &classes, colors: colors.storage,
                    areaScale: areaScale, maxAreaScale: maxAreaScale, palette: palette, parameters: p, cancel: cancel)
            }
            try cancel.throwIfCancelled()
            var smoothed = 0
            if round == 0 && p.boundaryPasses > 0 {
                smoothed = try clock.measure("segment.regions.smooth") {
                    try BoundarySmoothing.apply(
                        classes: &classes, width: w, height: h, colors: colors.storage, palette: palette,
                        radius: p.boundaryRadius, passes: p.boundaryPasses, fidelity: p.boundaryFidelity,
                        cancel: cancel)
                }
            }
            try cancel.throwIfCancelled()
            var peeled = 0
            if round < cleanupRounds {
                peeled = try clock.measure("segment.regions.thin") {
                    try ThinPartRemoval.apply(
                        classes: &classes, width: w, height: h,
                        colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 4,
                        cancel: cancel)
                }
            }
            if smoothed > 0 || peeled > 0 {
                try cancel.throwIfCancelled()
                regions = clock.measure("segment.regions.label") { RegionRuns(classes: classes, width: w, height: h) }
                try cancel.throwIfCancelled()
                adjacency = clock.measure("segment.regions.adjacency") { RegionAdjacency(regions) }
            }
            if merged == 0 && peeled == 0 && smoothed == 0 && wide != nil { return (regions, adjacency) }
            // Late peels only nudge single pixels at junctions; stop cleaning once that is all
            // that happens and let the remaining rounds settle sizes.
            if round >= 1 && peeled < w * h / 1000 { cleanupRounds = min(cleanupRounds, round + 1) }
            round += 1
        }
    }

    static func maxAreaScale(_ areaScale: [Float]) -> Float {
        areaScale.withUnsafeBufferPointer { b in
            Parallel.mapBands(b.count, minimumBandSize: 65_536) { range in b[range].max() ?? 0 }.max() ?? 0
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

    /// What merging a region into a neighbour costs: the colour distance to the neighbour's
    /// paint, less for a long shared border (`share` of the region's perimeter), so shapes
    /// stay compact. `mergeRound` and the recolour-or-merge choice of `enforceLabelRoom` must
    /// price a merge identically.
    @inline(__always)
    static func mergeCost(distance: Float, share: Float, parameters p: SegmentationParameters) -> Float {
        distance + p.mergeShareWeight * (1 - share)
    }

    struct Link {
        var region: Int32
        var length: Int32
        /// Colour step summed along the shared border (see `RegionAdjacency.boundarySteps`).
        var steps: Float
    }

    /// Merges every undersized, too-thin or transition-strip region into its best neighbour,
    /// smallest (relative to its own threshold) first. Rewrites merged regions' paint per
    /// pixel, updates the regions and their adjacency, and returns the number of merges.
    ///
    /// A region's size counts for less the closer its colour is to a neighbouring paint (a
    /// crumb nobody would miss), so the leftovers of fine texture merge while a small distinct
    /// spot such as an eye survives on the same area.
    ///
    /// Transition strips: a photo's edges are blurred over a few pixels, and where two paints
    /// meet, the blur's intermediate colours often fall nearest a third paint, which then
    /// forms a strip a few pixels wide along the whole edge. A region counts as such a strip
    /// only when it is elongated and narrow; its two dominant neighbours (the longest borders,
    /// together most of its outline) are open, i.e. neither is mostly wrapped by it nor
    /// smaller than it; its mean colour is a mix of their two paints (close to the line
    /// between them); and both of those borders are ramps rather than contours. So sharp-
    /// edged thin features (a pole, a twig), thin features of their own colour (a whisker
    /// between two greys) and the rings of an eye (pupil, iris, eye ring: each a soft-edged
    /// mix of its neighbours, but each around something smaller) are not strips. Strips
    /// merge whatever their area.
    static func mergeRound(
        _ regions: inout RegionRuns,
        adjacency: inout RegionAdjacency,
        wide: [Bool]?,
        classes: inout [UInt32],
        colors: [SIMD4<Float>],
        areaScale: [Float],
        maxAreaScale: Float,
        palette: [SIMD3<Float>],
        parameters p: SegmentationParameters,
        cancel: CancellationCheck = .none
    ) throws -> Int {
        let n = regions.count
        guard n > 1 else { return 0 }
        var thin = [Bool](repeating: false, count: n)
        if let wide { for r in 0..<n { thin[r] = !wide[r] } }
        var area = regions.area
        // Perimeter as the sum of shared borders (the image edge does not count, which only
        // makes regions along it look more compact and wider); the edge pixels separately,
        // for the whole outline where that matters.
        var perimeter = [Int32](repeating: 0, count: n)
        for k in adjacency.pairs.indices {
            let length = adjacency.lengths[k]
            let (a, b) = RegionAdjacency.regions(of: adjacency.pairs[k])
            perimeter[a] += length
            perimeter[b] += length
        }
        var edge = [Int32](repeating: 0, count: n)
        for y in 0..<regions.height {
            for k in regions.rowStart[y]..<regions.rowStart[y + 1] {
                let r = Int(regions.label[k])
                if y == 0 || y == regions.height - 1 { edge[r] += regions.end[k] - regions.start[k] }
                if regions.start[k] == 0 { edge[r] += 1 }
                if Int(regions.end[k]) == regions.width { edge[r] += 1 }
            }
        }
        // Shape alone: elongated (compactness 16·area/perimeter², 1 for a square) and narrower
        // than a strip (mean width 2·area/perimeter); the necessary half of the strip test.
        func narrow(_ r: Int) -> Bool {
            let a = Float(area[r]), pm = Float(perimeter[r])
            return pm > 0 && 16 * a < p.stripCompactness * pm * pm && 2 * a < p.stripWidth * pm
        }
        // Regions whose area alone guarantees a key ≥ 1 (the area-scale sum is at most
        // area × max scale, the contrast factor at least the floor) and that are neither thin
        // nor narrow never enter the queue, and neither does anything merged into them; their
        // colour and scale sums are never needed.
        let discArea = Double(Float.pi * p.minRadius * p.minRadius)
        let bigArea = max(Double(p.minArea) * Double(maxAreaScale), discArea) * 1.001 / Double(p.crumbFloor) + 1
        var big = [Bool](repeating: false, count: n)
        for r in 0..<n { big[r] = Double(area[r]) >= bigArea && !thin[r] && !narrow(r) }

        // OKLab sum and area-scale sum per queued region, accumulated in raster order.
        var sums = colors.withUnsafeBufferPointer { cb in
            areaScale.withUnsafeBufferPointer { ab in
                regions.accumulate(SIMD4<Double>.zero, include: big.map { !$0 }) { sum, _, i in
                    let c = cb[i]
                    sum += SIMD4(Double(c.x), Double(c.y), Double(c.z), Double(ab[i]))
                }
            }
        }
        let steps = adjacency.boundarySteps(regions, colors: colors)
        try cancel.throwIfCancelled()

        // Neighbour lists of queued regions (merged lists of big ones are never read).
        var links = [[Link]](repeating: [], count: n)
        for k in adjacency.pairs.indices {
            let (a, b) = RegionAdjacency.regions(of: adjacency.pairs[k])
            let length = adjacency.lengths[k]
            if !big[a] { links[a].append(Link(region: Int32(b), length: length, steps: steps[k])) }
            if !big[b] { links[b].append(Link(region: Int32(a), length: length, steps: steps[k])) }
        }

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
        // Area relative to the region's own minimum (base × its mean area scale, never below
        // the disc the radius rule demands, so the contrast factor has a footing at high
        // detail where the area rule alone asks for less than that disc).
        func relativeArea(_ r: Int) -> Float {
            let minimum = max(Double(p.minArea) * sums[r].w / Double(area[r]), discArea)
            return Float(Double(area[r]) / minimum)
        }
        func meanColor(_ r: Int) -> SIMD3<Float> {
            let s = sums[r] / Double(area[r])
            return SIMD3(Float(s.x), Float(s.y), Float(s.z))
        }
        // How visible the region is: its colour distance to the closest neighbouring paint.
        func contrastFactor(_ r: Int, neighbours: [Link]) -> Float {
            let mean = meanColor(r)
            var closest = Float.infinity
            for l in neighbours {
                let t = find(Int(l.region))
                if t != r { closest = min(closest, ColorScience.distance(mean, palette[Int(cls[t])])) }
            }
            return min(max(closest / p.crumbContrast, p.crumbFloor), 1)
        }
        func mergeKey(_ r: Int, neighbours: [Link]) -> Float { relativeArea(r) * contrastFactor(r, neighbours: neighbours) }
        // The transition-strip test (see above) on a compacted neighbour list.
        func isStrip(_ r: Int, neighbours: [Link]) -> Bool {
            guard narrow(r), neighbours.count >= 2 else { return false }
            // The two neighbours with the longest borders must own most of the perimeter: a
            // strip along an edge has one on each side.
            var first = 0, second = -1
            for k in 1..<neighbours.count {
                if neighbours[k].length > neighbours[first].length {
                    second = first
                    first = k
                } else if second < 0 || neighbours[k].length > neighbours[second].length {
                    second = k
                }
            }
            let a = neighbours[first], b = neighbours[second]
            let pm = Float(perimeter[r])
            guard Float(b.length) >= 0.15 * pm, Float(a.length + b.length) >= 0.5 * pm else { return false }
            // A strip runs between two open areas that extend beyond it. A region that owns
            // most of a neighbour's outline wraps it (an iris around its pupil), and one whose
            // neighbour is smaller than itself is a rim around a small feature or one ring of
            // a nest (pupil, iris, eye ring): a feature of its own, whatever its colour.
            for l in [a, b] {
                let t = Int(l.region)
                if Float(l.length) >= p.stripEnclosure * Float(perimeter[t] + edge[t]) { return false }
                if Float(area[t]) < p.stripNeighbourArea * Float(area[r]) { return false }
            }
            let pa = palette[Int(cls[Int(a.region)])], pb = palette[Int(cls[Int(b.region)])]
            let ab = pb - pa
            let ab2 = (ab * ab).sum()
            guard ab2 > 0 else { return false }  // the same paint on both sides: an extremum, not a mix
            // The mean colour projects well inside the segment between the two paints and lies
            // close to it, relative to its distance from the nearer paint.
            let m = meanColor(r)
            let t = ((m - pa) * ab).sum() / ab2
            guard t >= 0.15, t <= 0.85 else { return false }
            let off = ColorScience.distance(m, pa + t * ab)
            guard off <= p.stripMixture * min(ColorScience.distance(m, pa), ColorScience.distance(m, pb)) else {
                return false
            }
            let own = palette[Int(cls[r])]
            for l in [a, b] {
                let difference = ColorScience.distance(own, palette[Int(cls[Int(l.region)])])
                if l.steps > p.stripContrast * difference * Float(l.length) { return false }
            }
            return true
        }

        try cancel.throwIfCancelled()
        var heap = MinHeap()
        for r in 0..<n where !big[r] {
            let key = mergeKey(r, neighbours: links[r])
            if key < 1 || thin[r] || narrow(r) { heap.push(key, Int32(r), 0) }
        }

        var merges = 0
        var compacted: [Link] = []
        var pops = 0
        while let item = heap.pop() {
            pops &+= 1
            if pops & 4095 == 0 { try cancel.throwIfCancelled() }
            let r = Int(item.region)
            if Int(parent[r]) != r || stamp[r] != item.stamp { continue }

            // Compact the neighbour list: resolve merged ids, drop self links, sum borders.
            var list = links[r]
            for k in list.indices { list[k].region = Int32(find(Int(list[k].region))) }
            list.removeAll { Int($0.region) == r }
            guard !list.isEmpty else { links[r] = []; continue }
            list.sort { $0.region < $1.region }
            compacted.removeAll(keepingCapacity: true)
            for l in list {
                if let last = compacted.last, last.region == l.region {
                    compacted[compacted.count - 1].length += l.length
                    compacted[compacted.count - 1].steps += l.steps
                } else {
                    compacted.append(l)
                }
            }
            guard thin[r] || mergeKey(r, neighbours: compacted) < 1 || isStrip(r, neighbours: compacted) else {
                links[r] = compacted
                continue
            }

            // Best neighbour: closest paint to this region's mean color, favouring long
            // shared borders so shapes stay compact.
            let mean = meanColor(r)
            var best = compacted[0]
            var bestCost = Float.infinity
            for l in compacted {
                let dc = ColorScience.distance(mean, palette[Int(cls[Int(l.region)])])
                let cost = mergeCost(distance: dc, share: Float(l.length) / Float(perimeter[r]), parameters: p)
                if cost < bestCost { bestCost = cost; best = l }
            }
            let target = Int(best.region)

            let root = area[target] >= area[r] ? target : r
            let other = root == target ? r : target
            parent[other] = Int32(root)
            area[root] = area[r] + area[target]
            perimeter[root] = perimeter[r] + perimeter[target] - 2 * best.length
            edge[root] = edge[r] + edge[target]
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
                let newKey = mergeKey(root, neighbours: links[root])
                if newKey < 1 || narrow(root) { heap.push(newKey, Int32(root), stamp[root]) }
            }
        }
        guard merges > 0 else { return 0 }
        for r in 0..<n { parent[r] = Int32(find(r)) }
        try cancel.throwIfCancelled()
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
