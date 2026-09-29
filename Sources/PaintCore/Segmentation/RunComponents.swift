import Foundation

/// 4-connected component labelling on horizontal runs. Label maps in this stage consist of
/// long runs of equal paint, so unioning runs instead of pixels (and extracting/filling rows
/// in parallel) is several times faster than per-pixel labelling. Output is identical to
/// `ConnectedComponents.label`: components numbered in raster order of their first pixel.
enum RunComponents {

    static func label(_ classes: [UInt32], width w: Int, height h: Int) -> Components {
        let n = w * h
        guard n > 0 else {
            return Components(labels: RegionMap(width: w, height: h, repeating: 0), classOf: [], area: [], bounds: [])
        }
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
        var rowStart = [Int](repeating: 0, count: h + 1)
        for y in 0..<h { rowStart[y + 1] = rowStart[y] + rowCount[y] }
        let runs = rowStart[h]
        var start = [Int32](repeating: 0, count: runs)
        var end = [Int32](repeating: 0, count: runs)
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

        // 2. Union runs overlapping a run of the same paint in the row above.
        var parent = [Int32](repeating: 0, count: runs)
        for i in 0..<runs { parent[i] = Int32(i) }
        parent.withUnsafeMutableBufferPointer { pb in
            let p = pb.baseAddress!
            @inline(__always) func find(_ x: Int32) -> Int32 {
                var r = x
                while p[Int(r)] != r { r = p[Int(r)] }
                var c = x
                while p[Int(c)] != r {
                    let next = p[Int(c)]
                    p[Int(c)] = r
                    c = next
                }
                return r
            }
            for y in 1..<max(h, 1) {
                var a = rowStart[y - 1], b = rowStart[y]
                let aEnd = rowStart[y], bEnd = rowStart[y + 1]
                while a < aEnd && b < bEnd {
                    if runClass[a] == runClass[b] && start[a] < end[b] && start[b] < end[a] {
                        let ra = find(Int32(a)), rb = find(Int32(b))
                        if ra != rb {
                            if ra < rb { p[Int(rb)] = ra } else { p[Int(ra)] = rb }
                        }
                    }
                    if end[a] < end[b] { a += 1 } else if end[b] < end[a] { b += 1 } else { a += 1; b += 1 }
                }
            }
        }

        // 3. Number components by first run in raster order; gather statistics.
        var id = [Int32](repeating: -1, count: runs)
        var runLabel = [UInt32](repeating: 0, count: runs)
        var classOf: [UInt32] = []
        var area: [Int] = []
        var bounds: [PixelBounds] = []
        for y in 0..<h {
            for r in rowStart[y]..<rowStart[y + 1] {
                var root = Int(parent[r])
                while Int(parent[root]) != root { root = Int(parent[root]) }
                var label = id[root]
                if label < 0 {
                    label = Int32(classOf.count)
                    id[root] = label
                    classOf.append(runClass[r])
                    area.append(0)
                    bounds.append(.empty)
                }
                runLabel[r] = UInt32(label)
                let l = Int(label)
                area[l] += Int(end[r] - start[r])
                bounds[l].include(x: Int(start[r]), y: y)
                bounds[l].include(x: Int(end[r]) - 1, y: y)
            }
        }

        // 4. Paint labels back per row.
        var labels = [UInt32](repeating: 0, count: n)
        labels.withUnsafeMutableBufferPointer { lb in
            rowStart.withUnsafeBufferPointer { rsb in
                start.withUnsafeBufferPointer { sb in
                    end.withUnsafeBufferPointer { eb in
                        runLabel.withUnsafeBufferPointer { rlb in
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
        return Components(
            labels: RegionMap(width: w, height: h, storage: labels), classOf: classOf, area: area, bounds: bounds)
    }
}
