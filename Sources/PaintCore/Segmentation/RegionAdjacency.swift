import Foundation

/// Shared border lengths (4-neighbour pixel pairs) of adjacent regions.
struct RegionAdjacency: Sendable {
    /// Region pairs `low << 32 | high`, ascending, each listed once.
    var pairs: [UInt64]
    var lengths: [Int32]
    /// Colour steps summed over each pair's border (see `boundarySteps`), once measured;
    /// merges regroup them with the lengths, a fresh labelling starts over.
    var steps: [Float]?

    @inline(__always) static func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
        a < b ? UInt64(a) << 32 | UInt64(b) : UInt64(b) << 32 | UInt64(a)
    }

    /// The two regions of a pair `key`, the lower number first.
    @inline(__always) static func regions(of key: UInt64) -> (low: Int, high: Int) {
        (Int(key >> 32), Int(key & 0xFFFF_FFFF))
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
        var entries: [(key: UInt64, length: Int32, steps: Float)] = []
        entries.reserveCapacity(pairs.count)
        for k in pairs.indices {
            let (low, high) = Self.regions(of: pairs[k])
            let a = group[low], b = group[high]
            if a != b { entries.append((Self.key(a, b), lengths[k], steps?[k] ?? 0)) }
        }
        entries.sort { $0.key < $1.key }
        var out = RegionAdjacency(pairs: [], lengths: [], steps: steps == nil ? nil : [])
        for e in entries {
            if let last = out.pairs.last, last == e.key {
                out.lengths[out.lengths.count - 1] += e.length
                out.steps?[out.lengths.count - 1] += e.steps
            } else {
                out.pairs.append(e.key)
                out.lengths.append(e.length)
                out.steps?.append(e.steps)
            }
        }
        return out
    }

    private init(pairs: [UInt64], lengths: [Int32], steps: [Float]?) {
        self.pairs = pairs
        self.lengths = lengths
        self.steps = steps
    }

    /// Colour step summed over each pair's shared border (in the order of `pairs`): the
    /// working-space distance between the two pixels of every 4-neighbour pair on the
    /// border, so `boundarySteps / lengths` is the mean step across it. A real contour
    /// carries most of the paint difference within a pixel or two; the boundary a smooth
    /// ramp is sliced at barely changes colour. Measured once per labelling and kept in
    /// `steps` through merges.
    mutating func boundarySteps(_ runs: RegionRuns, colors: [SIMD4<Float>]) -> [Float] {
        if let steps { return steps }
        let measured = Self.measureSteps(pairs: pairs, runs: runs, colors: colors)
        steps = measured
        return measured
    }

    private static func measureSteps(pairs: [UInt64], runs: RegionRuns, colors: [SIMD4<Float>]) -> [Float] {
        let w = runs.width, h = runs.height, m = pairs.count
        guard m > 0, h > 0 else { return [] }
        // Fixed row chunks, each summing into its own slice, added up in chunk order: the
        // floating-point result then does not depend on the number of cores.
        let chunkRows = 32
        let chunks = (h + chunkRows - 1) / chunkRows
        var partial = [Float](repeating: 0, count: chunks * m)
        runs.rowStart.withUnsafeBufferPointer { rsb in
            runs.start.withUnsafeBufferPointer { sb in
                runs.end.withUnsafeBufferPointer { eb in
                    runs.label.withUnsafeBufferPointer { lb in
                        pairs.withUnsafeBufferPointer { pb in
                            colors.withUnsafeBufferPointer { cb in
                                partial.withUnsafeMutableBufferPointer { partialBuffer in
                                    let rs = UncheckedSendable(rsb), s = UncheckedSendable(sb)
                                    let e = UncheckedSendable(eb), l = UncheckedSendable(lb)
                                    let keys = UncheckedSendable(pb), c = UncheckedSendable(cb)
                                    let out = UncheckedSendable(partialBuffer.baseAddress!)
                                    Parallel.forEachChunk(h, chunk: chunkRows) { rows in
                                        let sum = out.value + (rows.lowerBound / chunkRows) * m
                                        @inline(__always) func slot(_ a: UInt32, _ b: UInt32) -> Int {
                                            // Pairs are ascending, so the index is a binary search.
                                            let key = RegionAdjacency.key(a, b)
                                            var lo = 0, hi = m
                                            while lo < hi {
                                                let mid = (lo + hi) >> 1
                                                if keys.value[mid] < key { lo = mid + 1 } else { hi = mid }
                                            }
                                            // Runs and pairs describe the same labelling, so
                                            // every border belongs to a listed pair.
                                            precondition(lo < m && keys.value[lo] == key, "border of an unlisted region pair")
                                            return lo
                                        }
                                        @inline(__always) func step(_ i: Int, _ j: Int) -> Float {
                                            var d = c.value[i] - c.value[j]
                                            d.w = 0
                                            return (d * d).sum().squareRoot()
                                        }
                                        for y in rows {
                                            let a0 = rs.value[y], a1 = rs.value[y + 1]
                                            let row = y * w
                                            for k in a0..<(a1 - 1) where l.value[k] != l.value[k + 1] {
                                                let x = Int(e.value[k])
                                                sum[slot(l.value[k], l.value[k + 1])] += step(row + x - 1, row + x)
                                            }
                                            guard y + 1 < h else { continue }
                                            var a = a0, b = a1
                                            let bEnd = rs.value[y + 2]
                                            while a < a1 && b < bEnd {
                                                let la = l.value[a], lb = l.value[b]
                                                let ea = e.value[a], eb = e.value[b]
                                                if la != lb {
                                                    let x0 = Int(max(s.value[a], s.value[b])), x1 = Int(min(ea, eb))
                                                    if x0 < x1 {
                                                        var total: Float = 0
                                                        for x in x0..<x1 { total += step(row + x, row + w + x) }
                                                        sum[slot(la, lb)] += total
                                                    }
                                                }
                                                if ea < eb { a += 1 } else if eb < ea { b += 1 } else { a += 1; b += 1 }
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
        var out = [Float](repeating: 0, count: m)
        for chunk in 0..<chunks {
            let base = chunk * m
            for k in 0..<m { out[k] += partial[base + k] }
        }
        return out
    }
}
