import Foundation

/// The 4-connected regions of a paint map in run-length form: every row is a sequence of
/// horizontal runs, each labelled with its region. Label maps in this stage consist of long
/// runs of equal paint, so unioning runs instead of pixels (and extracting rows in parallel)
/// is several times faster than per-pixel labelling, and region-level edits (merging,
/// recoloring) only touch runs. Regions are numbered in raster order of their first pixel,
/// exactly like `ConnectedComponents.label`.
struct RegionRuns: Sendable {
    let width: Int
    let height: Int
    /// Runs of row y are `rowStart[y]..<rowStart[y + 1]`, left to right.
    var rowStart: [Int]
    /// Pixel columns `start[k]..<end[k]` of run k.
    var start: [Int32]
    var end: [Int32]
    /// Region of run k. After merges, neighbouring runs of a row may share a region.
    var label: [UInt32]
    /// Per region: paint, pixel count and bounds.
    var classOf: [UInt32]
    var area: [Int]
    var bounds: [PixelBounds]

    var count: Int { classOf.count }
    var runCount: Int { label.count }

    init(classes: [UInt32], width w: Int, height h: Int) {
        width = w
        height = h
        rowStart = [Int](repeating: 0, count: h + 1)
        start = []
        end = []
        label = []
        classOf = []
        area = []
        bounds = []
        guard w > 0, h > 0 else { return }

        // 1. Runs per row.
        var rowCount = [Int](repeating: 0, count: h)
        classes.withUnsafeBufferPointer { cb in
            rowCount.withUnsafeMutableBufferPointer { rb in
                let c = UncheckedSendable(cb.baseAddress!)
                let r = UncheckedSendable(rb.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                    for y in rows {
                        let row = c.value + y * w
                        var count = 1
                        for x in 1..<max(w, 1) where row[x] != row[x - 1] { count += 1 }
                        r.value[y] = count
                    }
                }
            }
        }
        for y in 0..<h { rowStart[y + 1] = rowStart[y] + rowCount[y] }
        let runs = rowStart[h]
        start = [Int32](repeating: 0, count: runs)
        end = [Int32](repeating: 0, count: runs)
        var runClass = [UInt32](repeating: 0, count: runs)
        classes.withUnsafeBufferPointer { cb in
            rowStart.withUnsafeBufferPointer { rsb in
                start.withUnsafeMutableBufferPointer { sb in
                    end.withUnsafeMutableBufferPointer { eb in
                        runClass.withUnsafeMutableBufferPointer { kb in
                            let c = UncheckedSendable(cb.baseAddress!)
                            let rs = UncheckedSendable(rsb.baseAddress!)
                            let s = UncheckedSendable(sb.baseAddress!)
                            let e = UncheckedSendable(eb.baseAddress!)
                            let k = UncheckedSendable(kb.baseAddress!)
                            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = c.value + y * w
                                    var r = rs.value[y]
                                    var x0 = 0
                                    for x in 1...w where x == w || row[x] != row[x - 1] {
                                        s.value[r] = Int32(x0)
                                        e.value[r] = Int32(x)
                                        k.value[r] = row[x0]
                                        r += 1
                                        x0 = x
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Union runs overlapping a run of the same paint in the row above; the root of
        // every component is its smallest run index, i.e. its first run in raster order.
        // Bands of rows are unioned in parallel (each touches only its own runs), then the
        // band seams serially.
        var parent = (0..<runs).map { Int32($0) }
        let bandRows = max(16, (h + Parallel.bandCount - 1) / Parallel.bandCount)
        let seams = Array(stride(from: bandRows, to: h, by: bandRows))
        parent.withUnsafeMutableBufferPointer { pb in
            start.withUnsafeBufferPointer { sb in
                end.withUnsafeBufferPointer { eb in
                    runClass.withUnsafeBufferPointer { kb in
                        rowStart.withUnsafeBufferPointer { rsb in
                            let p = UncheckedSendable(pb.baseAddress!)
                            let s = UncheckedSendable(sb), e = UncheckedSendable(eb)
                            let k = UncheckedSendable(kb), rs = UncheckedSendable(rsb)
                            @inline(__always) func find(_ x: Int32) -> Int32 {
                                var r = x
                                while p.value[Int(r)] != r { r = p.value[Int(r)] }
                                var c = x
                                while p.value[Int(c)] != r {
                                    let next = p.value[Int(c)]
                                    p.value[Int(c)] = r
                                    c = next
                                }
                                return r
                            }
                            @inline(__always) func unionRows(_ y: Int) {
                                var a = rs.value[y - 1], b = rs.value[y]
                                let aEnd = rs.value[y], bEnd = rs.value[y + 1]
                                while a < aEnd && b < bEnd {
                                    if k.value[a] == k.value[b] && s.value[a] < e.value[b] && s.value[b] < e.value[a] {
                                        let ra = find(Int32(a)), rb = find(Int32(b))
                                        if ra != rb {
                                            if ra < rb { p.value[Int(rb)] = ra } else { p.value[Int(ra)] = rb }
                                        }
                                    }
                                    if e.value[a] < e.value[b] { a += 1 } else if e.value[b] < e.value[a] { b += 1 } else { a += 1; b += 1 }
                                }
                            }
                            Parallel.forEachChunk(h, chunk: bandRows) { rows in
                                for y in rows where y > rows.lowerBound { unionRows(y) }
                            }
                            for y in seams { unionRows(y) }
                        }
                    }
                }
            }
        }

        // 3. Number regions by first run in raster order (roots, in run order); gather
        // statistics.
        var root = [Int32](repeating: 0, count: runs)
        parent.withUnsafeBufferPointer { pb in
            root.withUnsafeMutableBufferPointer { rb in
                let p = UncheckedSendable(pb.baseAddress!), out = UncheckedSendable(rb.baseAddress!)
                Parallel.forEachBand(runs, minimumBandSize: 8192) { range in
                    for r in range {
                        var x = p.value[r]
                        while p.value[Int(x)] != x { x = p.value[Int(x)] }
                        out.value[r] = x
                    }
                }
            }
        }
        var id = [UInt32](repeating: 0, count: runs)
        for r in 0..<runs where Int(root[r]) == r {
            id[r] = UInt32(classOf.count)
            classOf.append(runClass[r])
        }
        let n = classOf.count
        label = [UInt32](repeating: 0, count: runs)
        area = [Int](repeating: 0, count: n)
        bounds = [PixelBounds](repeating: .empty, count: n)
        for y in 0..<h {
            for r in rowStart[y]..<rowStart[y + 1] {
                let l = id[Int(root[r])]
                label[r] = l
                let li = Int(l)
                area[li] += Int(end[r] - start[r])
                bounds[li].include(x: Int(start[r]), y: y)
                bounds[li].include(x: Int(end[r]) - 1, y: y)
            }
        }
    }

    /// Per-pixel region labels.
    func labelMap() -> RegionMap {
        let w = width, h = height
        var labels = [UInt32](uninitializedCount: w * h)
        labels.withUnsafeMutableBufferPointer { lb in
            rowStart.withUnsafeBufferPointer { rsb in
                start.withUnsafeBufferPointer { sb in
                    end.withUnsafeBufferPointer { eb in
                        label.withUnsafeBufferPointer { rlb in
                            let l = UncheckedSendable(lb.baseAddress!)
                            let rs = UncheckedSendable(rsb.baseAddress!)
                            let s = UncheckedSendable(sb.baseAddress!)
                            let e = UncheckedSendable(eb.baseAddress!)
                            let rl = UncheckedSendable(rlb.baseAddress!)
                            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = l.value + y * w
                                    for r in rs.value[y]..<rs.value[y + 1] {
                                        let v = rl.value[r]
                                        for x in Int(s.value[r])..<Int(e.value[r]) { row[x] = v }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return RegionMap(width: w, height: h, storage: labels)
    }

    func components() -> Components {
        Components(labels: labelMap(), classOf: classOf, area: area, bounds: bounds)
    }

    /// Per-region accumulation over pixels: `add(&value, region, pixelIndex)` sees each region's
    /// pixels in raster order (so floating-point sums equal those of a plain image scan);
    /// regions run in parallel. Regions without `include` keep `zero`.
    func accumulate<T>(_ zero: T, include: [Bool]? = nil, _ add: (inout T, Int, Int) -> Void) -> [T] {
        let n = count
        // Runs regrouped by region (CSR), each as first pixel index and length.
        var offset = [Int](repeating: 0, count: n + 1)
        for k in 0..<runCount where include?[Int(label[k])] ?? true { offset[Int(label[k]) + 1] += 1 }
        for r in 0..<n { offset[r + 1] += offset[r] }
        var cursor = offset
        var first = [Int](repeating: 0, count: offset[n])
        var length = [Int32](repeating: 0, count: offset[n])
        for y in 0..<height {
            for k in rowStart[y]..<rowStart[y + 1] {
                let r = Int(label[k])
                guard include?[r] ?? true else { continue }
                first[cursor[r]] = y * width + Int(start[k])
                length[cursor[r]] = end[k] - start[k]
                cursor[r] += 1
            }
        }
        var out = [T](repeating: zero, count: n)
        out.withUnsafeMutableBufferPointer { ob in
            // Small chunks, handed out dynamically: one huge region must not stall a band.
            Parallel.forEachChunk(n, chunk: 32) { regions in
                for r in regions where offset[r] < offset[r + 1] {
                    var value = zero
                    for k in offset[r]..<offset[r + 1] {
                        let i0 = first[k]
                        for i in i0..<(i0 + Int(length[k])) { add(&value, r, i) }
                    }
                    ob[r] = value
                }
            }
        }
        return out
    }

    /// Per-region sums of two per-pixel quantities (see `accumulate`).
    func sums(_ a: [Float], _ b: [Float]) -> [SIMD2<Double>] {
        a.withUnsafeBufferPointer { ab in
            b.withUnsafeBufferPointer { bb in
                accumulate(SIMD2<Double>.zero) { sum, _, i in sum += SIMD2(Double(ab[i]), Double(bb[i])) }
            }
        }
    }

    /// Applies merges: `roots[r]` is the region old region r was merged into (its own id if
    /// it was not merged) and `paint[roots[r]]` the merged region's paint. Merged regions that
    /// now touch a region of the same paint fuse with it, as they do in the paint map.
    mutating func merge(roots: [Int32], paint: [UInt32], adjacency: inout RegionAdjacency, classes: inout [UInt32]) {
        let n = count
        var join = (0..<n).map { Int32($0) }
        func find(_ x: Int) -> Int {
            var r = x
            while Int(join[r]) != r { r = Int(join[r]) }
            var c = x
            while Int(join[c]) != r {
                let next = Int(join[c])
                join[c] = Int32(r)
                c = next
            }
            return r
        }
        for key in adjacency.pairs {
            let a = Int(roots[Int(key >> 32)]), b = Int(roots[Int(key & 0xFFFF_FFFF)])
            guard a != b, paint[a] == paint[b] else { continue }
            let ja = find(a), jb = find(b)
            if ja != jb { join[max(ja, jb)] = Int32(min(ja, jb)) }
        }
        // Old regions are numbered by first pixel, so numbering groups by their smallest
        // member keeps raster order.
        var id = [Int32](repeating: -1, count: n)
        var group = [UInt32](repeating: 0, count: n)
        var newClass: [UInt32] = []
        for r in 0..<n {
            let g = find(Int(roots[r]))
            if id[g] < 0 {
                id[g] = Int32(newClass.count)
                newClass.append(paint[Int(roots[r])])
            }
            group[r] = UInt32(id[g])
        }
        regroup(group, classOf: newClass, classes: &classes)
        adjacency = adjacency.regrouped(group)
    }

    /// Rewrites the regions after merges: `group[r]` is the region that old region r now
    /// belongs to (numbered in raster order of first pixel, i.e. by smallest member, with
    /// all members sharing `classOf[group]`), and repaints the pixels of regions whose paint
    /// changed.
    private mutating func regroup(_ group: [UInt32], classOf newClass: [UInt32], classes: inout [UInt32]) {
        let n = count, m = newClass.count
        var newArea = [Int](repeating: 0, count: m)
        var newBounds = [PixelBounds](repeating: .empty, count: m)
        var recolor = [UInt32](repeating: .max, count: n)
        var recolored = 0
        for r in 0..<n {
            let g = Int(group[r])
            newArea[g] += area[r]
            newBounds[g].formUnion(bounds[r])
            if newClass[g] != classOf[r] {
                recolor[r] = newClass[g]
                recolored += 1
            }
        }
        let anyRecolor = recolored > 0
        let w = width
        label.withUnsafeMutableBufferPointer { lb in
            group.withUnsafeBufferPointer { gb in
                recolor.withUnsafeBufferPointer { cb in
                    classes.withUnsafeMutableBufferPointer { pb in
                        rowStart.withUnsafeBufferPointer { rsb in
                            start.withUnsafeBufferPointer { sb in
                                end.withUnsafeBufferPointer { eb in
                                    let l = UncheckedSendable(lb.baseAddress!)
                                    let g = UncheckedSendable(gb.baseAddress!)
                                    let c = UncheckedSendable(cb.baseAddress!)
                                    let px = UncheckedSendable(pb.baseAddress!)
                                    let rs = UncheckedSendable(rsb.baseAddress!)
                                    let s = UncheckedSendable(sb.baseAddress!)
                                    let e = UncheckedSendable(eb.baseAddress!)
                                    Parallel.forEachBand(height, minimumBandSize: 16) { rows in
                                        for y in rows {
                                            let row = px.value + y * w
                                            for k in rs.value[y]..<rs.value[y + 1] {
                                                let old = Int(l.value[k])
                                                if anyRecolor, c.value[old] != .max {
                                                    let v = c.value[old]
                                                    for x in Int(s.value[k])..<Int(e.value[k]) { row[x] = v }
                                                }
                                                l.value[k] = g.value[old]
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        classOf = newClass
        area = newArea
        bounds = newBounds
    }
}

/// Shared border lengths (4-neighbour pixel pairs) of adjacent regions.
struct RegionAdjacency: Sendable {
    /// Region pairs `low << 32 | high`, ascending, each listed once.
    var pairs: [UInt64]
    var lengths: [Int32]

    @inline(__always) static func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
        a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
    }

    init(_ runs: RegionRuns) {
        let h = runs.height, n = runs.count
        struct Entry { var low: UInt32, high: UInt32, length: Int32 }
        let bands: [[Entry]] = runs.rowStart.withUnsafeBufferPointer { rsb in
            runs.start.withUnsafeBufferPointer { sb in
                runs.end.withUnsafeBufferPointer { eb in
                    runs.label.withUnsafeBufferPointer { lb in
                        let rs = UncheckedSendable(rsb), s = UncheckedSendable(sb)
                        let e = UncheckedSendable(eb), l = UncheckedSendable(lb)
                        return Parallel.mapBands(h, minimumBandSize: 16) { rows -> [Entry] in
                            var out: [Entry] = []
                            @inline(__always) func emit(_ a: UInt32, _ b: UInt32, _ length: Int32) {
                                out.append(a < b ? Entry(low: a, high: b, length: length) : Entry(low: b, high: a, length: length))
                            }
                            for y in rows {
                                let a0 = rs.value[y], a1 = rs.value[y + 1]
                                for k in a0..<(a1 - 1) where l.value[k] != l.value[k + 1] {
                                    emit(l.value[k], l.value[k + 1], 1)
                                }
                                guard y + 1 < h else { continue }
                                var a = a0, b = a1
                                let bEnd = rs.value[y + 2]
                                while a < a1 && b < bEnd {
                                    let la = l.value[a], lb = l.value[b]
                                    let ea = e.value[a], eb = e.value[b]
                                    if la != lb {
                                        let overlap = min(ea, eb) - max(s.value[a], s.value[b])
                                        if overlap > 0 { emit(la, lb, overlap) }
                                    }
                                    if ea < eb { a += 1 } else if eb < ea { b += 1 } else { a += 1; b += 1 }
                                }
                            }
                            return out
                        }
                    }
                }
            }
        }
        // Bucket by low region (counting sort), then sum per high region within each bucket.
        var offset = [Int](repeating: 0, count: n + 1)
        for band in bands { for entry in band { offset[Int(entry.low) + 1] += 1 } }
        for r in 0..<n { offset[r + 1] += offset[r] }
        var cursor = offset
        var high = [UInt32](repeating: 0, count: offset[n])
        var length = [Int32](repeating: 0, count: offset[n])
        for band in bands {
            for entry in band {
                let k = cursor[Int(entry.low)]
                high[k] = entry.high
                length[k] = entry.length
                cursor[Int(entry.low)] = k + 1
            }
        }
        pairs = []
        lengths = []
        pairs.reserveCapacity(offset[n] / 2)
        lengths.reserveCapacity(offset[n] / 2)
        var slot = [Int32](repeating: -1, count: n)
        for low in 0..<n where offset[low] < offset[low + 1] {
            let first = pairs.count
            for k in offset[low]..<offset[low + 1] {
                let b = Int(high[k])
                let at = Int(slot[b])
                if at >= first {
                    lengths[at] += length[k]
                } else {
                    slot[b] = Int32(pairs.count)
                    pairs.append(UInt64(low) << 32 | UInt64(b))
                    lengths.append(length[k])
                }
            }
            // Ascending within the bucket (buckets are small).
            var i = first + 1
            while i < pairs.count {
                let p = pairs[i], q = lengths[i]
                var j = i - 1
                while j >= first && pairs[j] > p {
                    pairs[j + 1] = pairs[j]
                    lengths[j + 1] = lengths[j]
                    j -= 1
                }
                pairs[j + 1] = p
                lengths[j + 1] = q
                i += 1
            }
        }
    }

    /// Adjacency after regions were grouped (`group[r]`: new region of old region r).
    func regrouped(_ group: [UInt32]) -> RegionAdjacency {
        var entries: [(key: UInt64, length: Int32)] = []
        entries.reserveCapacity(pairs.count)
        for k in pairs.indices {
            let a = group[Int(pairs[k] >> 32)], b = group[Int(pairs[k] & 0xFFFF_FFFF)]
            if a != b { entries.append((Self.key(a, b), lengths[k])) }
        }
        entries.sort { $0.key < $1.key }
        var out = RegionAdjacency(pairs: [], lengths: [])
        for e in entries {
            if let last = out.pairs.last, last == e.key {
                out.lengths[out.lengths.count - 1] += e.length
            } else {
                out.pairs.append(e.key)
                out.lengths.append(e.length)
            }
        }
        return out
    }

    private init(pairs: [UInt64], lengths: [Int32]) {
        self.pairs = pairs
        self.lengths = lengths
    }
}
