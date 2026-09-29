import Foundation

/// Turns a per-pixel palette labelling into paintable regions: every region is big enough
/// to tap and to hold a number, and has no hair-thin parts.
///
/// Each round (1) merges regions that are too small (importance-scaled area) or too thin
/// (largest inscribed disc) into their best neighbour, smallest first, and (2) peels pixels
/// that no k×k square inside their region covers (tendrils, necks, 1-px slivers along
/// edges) and hands them to the neighbour whose color suits them best. Rounds repeat until
/// neither step changes anything, so the guarantees hold on the returned map.
enum RegionSimplifier {

    static func simplify(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: Grid<SIMD4<Float>>,
        areaScale: [Float],
        palette: [SIMD3<Float>],
        parameters p: SegmentationParameters,
        cancel: CancellationCheck
    ) throws -> Components {
        var cleanupRounds = 5
        var cc = components(classes, w, h)
        if Tune.debug { debugLog("initial regions \(cc.count)") }
        var round = 0
        while true {
            try cancel.throwIfCancelled()
            // The first round only has specks to deal with; inscribed radii matter once the
            // map is reasonably clean, and they are expensive to measure.
            let t0 = ContinuousClock.now
            let wide = round > 0 ? hasInscribedDisc(cc, radius: p.minRadius) : nil
            let t1 = ContinuousClock.now
            let merged = mergeRound(
                cc, wide: wide, classes: &classes, colors: colors.storage, areaScale: areaScale,
                palette: palette, parameters: p)
            let t2 = ContinuousClock.now
            if merged > 0 { cc = components(classes, w, h) }
            let t3 = ContinuousClock.now
            var peeled = 0
            if round < cleanupRounds {
                peeled = ThinPartRemoval.apply(
                    classes: &classes, width: w, height: h,
                    colors: colors.storage, palette: palette, radiusSquared: p.openingRadiusSquared, maxPasses: 4)
                if peeled > 0 { cc = components(classes, w, h) }
            }
            let t4 = ContinuousClock.now
            if Tune.debug { debugLog("round \(round): merged \(merged) peeled \(peeled) regions \(cc.count)  edt \(t1 - t0) merge \(t2 - t1) cc \(t3 - t2) peel+cc \(t4 - t3)") }
            if merged == 0 && peeled == 0 && wide != nil { return cc }
            // Late peels only nudge single pixels at junctions; stop cleaning once that is all
            // that happens and let the remaining rounds settle sizes.
            if round >= 2 && peeled < w * h / 2000 { cleanupRounds = min(cleanupRounds, round + 1) }
            round += 1
        }
    }

    static func components(_ classes: [UInt32], _ w: Int, _ h: Int) -> Components {
        ConnectedComponents.label(Grid(width: w, height: h, storage: classes))
    }

    /// Whether each region's largest inscribed disc reaches `radius`, in the exact sense of
    /// `DistanceTransform.interiorDistance` (max over the region ≥ radius).
    ///
    /// interiorDistance(p) = |p − nearest boundary pixel| + ½, so it reaches `radius` iff no
    /// boundary pixel (one with a differently labelled 4-neighbour, or on the image edge)
    /// lies within √((radius − ½)²) of p. That is a small local test, much cheaper than a
    /// full distance transform every round.
    static func hasInscribedDisc(_ cc: Components, radius: Float) -> [Bool] {
        let labels = cc.labels.storage
        let w = cc.labels.width, h = cc.labels.height, n = w * h
        var result = [Bool](repeating: false, count: cc.count)
        let reach = max(radius - 0.5, 0)
        let limit = reach * reach
        let r = Int(reach.rounded(.up))
        var offsets: [Int] = []
        for dy in -r...r {
            for dx in -r...r where Float(dx * dx + dy * dy) < limit { offsets.append(dy * w + dx) }
        }
        guard w > 2 * r, h > 2 * r else {
            if limit <= 0 { for i in 0..<cc.count { result[i] = true } }
            return result
        }
        var interior = [UInt8](repeating: 0, count: n)
        var ok = [UInt8](repeating: 0, count: n)
        labels.withUnsafeBufferPointer { lb in
            interior.withUnsafeMutableBufferPointer { ib in
                ok.withUnsafeMutableBufferPointer { ob in
                    offsets.withUnsafeBufferPointer { offb in
                        let l = UncheckedSendable(lb.baseAddress!)
                        let ip = UncheckedSendable(ib.baseAddress!)
                        let op = UncheckedSendable(ob.baseAddress!)
                        let off = UncheckedSendable(offb.baseAddress!)
                        let m = offb.count
                        Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                            for y in rows where y > 0 && y < h - 1 {
                                for x in 1..<(w - 1) {
                                    let i = y * w + x
                                    let v = l.value[i]
                                    if l.value[i - 1] == v && l.value[i + 1] == v && l.value[i - w] == v && l.value[i + w] == v {
                                        ip.value[i] = 1
                                    }
                                }
                            }
                        }
                        Parallel.forEachBand(h - 2 * r, minimumBandSize: 16) { rows in
                            for yy in rows {
                                let y = yy + r
                                for x in r..<(w - r) {
                                    let i = y * w + x
                                    if ip.value[i] == 0 { continue }
                                    var all = true
                                    var k = 0
                                    while k < m {
                                        if ip.value[i + off.value[k]] == 0 { all = false; break }
                                        k += 1
                                    }
                                    if all { op.value[i] = 1 }
                                }
                            }
                        }
                    }
                }
            }
        }
        for i in 0..<n where ok[i] != 0 { result[Int(labels[i])] = true }
        return result
    }

    // MARK: - Merging

    struct Link {
        var region: Int32
        var length: Int32
    }

    /// Merges every undersized or too-thin region into its best neighbour, smallest (relative
    /// to its own threshold) first. Writes the merged classes back per pixel and returns the
    /// number of merges.
    static func mergeRound(
        _ cc: Components,
        wide: [Bool]?,
        classes: inout [UInt32],
        colors: [SIMD4<Float>],
        areaScale: [Float],
        palette: [SIMD3<Float>],
        parameters p: SegmentationParameters
    ) -> Int {
        let n = cc.count
        guard n > 1 else { return 0 }
        let w = cc.labels.width, h = cc.labels.height
        let labels = cc.labels.storage

        var sums = [SIMD4<Double>](repeating: .zero, count: n)  // OKLab sum, area-scale sum
        labels.withUnsafeBufferPointer { lb in
            colors.withUnsafeBufferPointer { cb in
                areaScale.withUnsafeBufferPointer { ib in
                    for i in 0..<lb.count {
                        let c = cb[i]
                        sums[Int(lb[i])] += SIMD4(Double(c.x), Double(c.y), Double(c.z), Double(ib[i]))
                    }
                }
            }
        }
        var area = cc.area
        var cls = cc.classOf
        var adjacency = adjacencyLists(labels, width: w, height: h, count: n)
        var parent = (0..<n).map { Int32($0) }
        var stamp = [Int32](repeating: 0, count: n)
        var thin = [Bool](repeating: false, count: n)
        if let wide { for r in 0..<n { thin[r] = !wide[r] } }

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
        for r in 0..<n {
            let key = relativeArea(r)
            if key < 1 || thin[r] { heap.push(key, Int32(r), 0) }
        }

        var merges = 0
        while let item = heap.pop() {
            let r = Int(item.region)
            if Int(parent[r]) != r || stamp[r] != item.stamp { continue }
            let key = relativeArea(r)
            guard key < 1 || thin[r] else { continue }

            // Compact the neighbour list: resolve merged ids, drop self links, sum lengths.
            var links = adjacency[r]
            for k in links.indices { links[k].region = Int32(find(Int(links[k].region))) }
            links.removeAll { Int($0.region) == r }
            guard !links.isEmpty else { adjacency[r] = []; continue }
            links.sort { $0.region < $1.region }
            var compacted: [Link] = []
            compacted.reserveCapacity(links.count)
            var perimeter: Int32 = 0
            for l in links {
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
            thin[root] = false  // verified by the next round's distance transform
            if root == target {
                adjacency[root].append(contentsOf: compacted)
            } else {
                adjacency[root] = compacted + adjacency[other]
            }
            adjacency[other] = []
            stamp[root] &+= 1
            merges += 1
            let newKey = relativeArea(root)
            if newKey < 1 { heap.push(newKey, Int32(root), stamp[root]) }
        }
        guard merges > 0 else { return 0 }

        var classOfRegion = [UInt32](repeating: 0, count: n)
        for r in 0..<n { classOfRegion[r] = cls[find(r)] }
        let count = labels.count
        classes.withUnsafeMutableBufferPointer { out in
            labels.withUnsafeBufferPointer { lb in
                classOfRegion.withUnsafeBufferPointer { cr in
                    let o = UncheckedSendable(out.baseAddress!)
                    let l = UncheckedSendable(lb.baseAddress!)
                    let c = UncheckedSendable(cr.baseAddress!)
                    Parallel.forEachBand(count, minimumBandSize: 16_384) { range in
                        for i in range { o.value[i] = c.value[Int(l.value[i])] }
                    }
                }
            }
        }
        return merges
    }

    /// Neighbour lists with shared border lengths (4-neighbour pixel pairs).
    static func adjacencyLists(_ labels: [UInt32], width w: Int, height h: Int, count n: Int) -> [[Link]] {
        var keys: [UInt64] = []
        var counts: [Int32] = []
        keys.reserveCapacity(labels.count / 8)
        counts.reserveCapacity(labels.count / 8)
        labels.withUnsafeBufferPointer { lb in
            var lastH = -1, lastV = -1
            for y in 0..<h {
                let row = y * w
                for x in 0..<w {
                    let i = row + x
                    let a = lb[i]
                    if x + 1 < w {
                        let b = lb[i + 1]
                        if a != b {
                            let key = a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
                            if lastH >= 0 && keys[lastH] == key {
                                counts[lastH] += 1
                            } else {
                                lastH = keys.count; keys.append(key); counts.append(1)
                            }
                        }
                    }
                    if y + 1 < h {
                        let b = lb[i + w]
                        if a != b {
                            let key = a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
                            if lastV >= 0 && keys[lastV] == key {
                                counts[lastV] += 1
                            } else {
                                lastV = keys.count; keys.append(key); counts.append(1)
                            }
                        }
                    }
                }
            }
        }
        var order = Array(0..<keys.count)
        order.sort { keys[$0] < keys[$1] }
        var adjacency = [[Link]](repeating: [], count: n)
        var k = 0
        while k < order.count {
            let key = keys[order[k]]
            var total: Int32 = 0
            while k < order.count && keys[order[k]] == key {
                total += counts[order[k]]
                k += 1
            }
            let a = Int(key >> 32), b = Int(key & 0xFFFF_FFFF)
            adjacency[a].append(Link(region: Int32(b), length: total))
            adjacency[b].append(Link(region: Int32(a), length: total))
        }
        return adjacency
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
