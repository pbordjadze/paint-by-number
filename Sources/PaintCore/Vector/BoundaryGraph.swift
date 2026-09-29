/// The planar graph of region boundaries on the pixel-corner lattice, before smoothing.
///
/// Corners are the integer points `(x, y)` with `0...width` × `0...height`. A lattice
/// segment between two adjacent corners is a boundary when the pixels on its two sides
/// differ (pixels outside the canvas all belong to `BoundaryEdge.outside`). A corner is a
/// *junction* when three or four of its segments are boundaries: that is exactly when three
/// or more distinct regions meet there, or when two regions meet diagonally
/// (checkerboard `A B / B A`). Edges are maximal chains of boundary segments between
/// junctions; boundary cycles without any junction become closed edges.
///
/// Chains are stored as chain codes (one direction per unit step) so they stay compact
/// and exact; smoothing turns them into float polylines later.
struct BoundaryGraph: Sendable {
    /// Unit-step direction codes. Canvas y points down, so `south` is +y.
    static let east: UInt8 = 0, south: UInt8 = 1, west: UInt8 = 2, north: UInt8 = 3
    static let dx: [Int] = [1, 0, -1, 0]
    static let dy: [Int] = [0, 1, 0, -1]

    let width: Int
    let height: Int

    /// Per edge, in canonical orientation: `left < right` (see `BoundaryEdge`), so border
    /// edges always have `right == BoundaryEdge.outside`.
    var edgeLeft: [UInt32] = []
    var edgeRight: [UInt32] = []
    var edgeStart: [SIMD2<Int32>] = []
    var edgeEnd: [SIMD2<Int32>] = []
    var edgeStepStart: [Int32] = []
    var edgeStepCount: [Int32] = []
    /// No junction anywhere on the chain: it starts and ends at the same (non-junction) corner.
    var edgeClosed: [Bool] = []
    /// Twice the signed shoelace area swept by the lattice chain (exact).
    var edgeArea2: [Int64] = []
    var steps: [UInt8] = []

    /// Linear corner indices `y * (width + 1) + x` of all junctions, ascending.
    var junctions: [Int32] = []
    /// Four slots per junction, one per outgoing direction: `edge * 2` when the edge starts
    /// there leaving in that direction, `edge * 2 + 1` when it ends there arriving from
    /// that direction, `-1` when that lattice segment is not a boundary.
    var junctionSlots: [Int32] = []

    var edgeCount: Int { edgeLeft.count }

    func firstStep(_ e: Int) -> UInt8 { steps[Int(edgeStepStart[e])] }
    func lastStep(_ e: Int) -> UInt8 { steps[Int(edgeStepStart[e] + edgeStepCount[e]) - 1] }

    func junctionIndex(x: Int, y: Int) -> Int? {
        let key = Int32(y * (width + 1) + x)
        var lo = 0, hi = junctions.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if junctions[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo < junctions.count && junctions[lo] == key ? lo : nil
    }

    /// Lattice corners of an edge in order (closed edges repeat their first corner).
    func latticePoints(_ e: Int, into out: inout [SIMD2<Int32>]) {
        out.removeAll(keepingCapacity: true)
        var p = edgeStart[e]
        out.append(p)
        let start = Int(edgeStepStart[e]), count = Int(edgeStepCount[e])
        for k in start..<(start + count) {
            let d = Int(steps[k])
            p &+= SIMD2(Int32(BoundaryGraph.dx[d]), Int32(BoundaryGraph.dy[d]))
            out.append(p)
        }
    }
}

/// Pixel access with everything outside the canvas mapped to `BoundaryEdge.outside`.
struct LabelLattice {
    let labels: UnsafeBufferPointer<UInt32>
    let width: Int
    let height: Int

    @inline(__always)
    func at(_ x: Int, _ y: Int) -> UInt32 {
        (x >= 0 && y >= 0 && x < width && y < height) ? labels[y * width + x] : BoundaryEdge.outside
    }

    /// Bit `d` is set when the lattice segment leaving corner `(cx, cy)` in direction `d`
    /// separates two different regions.
    @inline(__always)
    func mask(_ cx: Int, _ cy: Int) -> UInt8 {
        let nw = at(cx - 1, cy - 1), ne = at(cx, cy - 1), sw = at(cx - 1, cy), se = at(cx, cy)
        var m: UInt8 = 0
        if ne != se { m |= 1 }
        if sw != se { m |= 2 }
        if nw != sw { m |= 4 }
        if nw != ne { m |= 8 }
        return m
    }

    /// Region on the `left` side (see `BoundaryEdge`) of the unit step leaving `(cx, cy)` in direction `d`.
    @inline(__always)
    func left(_ cx: Int, _ cy: Int, _ d: UInt8) -> UInt32 {
        switch d {
        case 0: return at(cx, cy)
        case 1: return at(cx - 1, cy)
        case 2: return at(cx - 1, cy - 1)
        default: return at(cx, cy - 1)
        }
    }

    @inline(__always)
    func right(_ cx: Int, _ cy: Int, _ d: UInt8) -> UInt32 {
        switch d {
        case 0: return at(cx, cy - 1)
        case 1: return at(cx, cy)
        case 2: return at(cx - 1, cy)
        default: return at(cx - 1, cy - 1)
        }
    }
}

extension BoundaryGraph {

    static func build(labels map: RegionMap) -> BoundaryGraph {
        let w = map.width, h = map.height
        var g = BoundaryGraph(width: w, height: h)
        guard w > 0, h > 0 else { return g }
        map.storage.withUnsafeBufferPointer { buf in
            let lat = LabelLattice(labels: buf, width: w, height: h)
            g.findJunctions(lat)
            g.trace(lat)
        }
        return g
    }

    private mutating func findJunctions(_ lat: LabelLattice) {
        let w = width
        let rows = height + 1
        let bands = Parallel.mapBands(rows, minimumBandSize: 32) { range -> [Int32] in
            var found: [Int32] = []
            for cy in range {
                for cx in 0...w where lat.mask(cx, cy).nonzeroBitCount >= 3 {
                    found.append(Int32(cy * (w + 1) + cx))
                }
            }
            return found
        }
        junctions = Array(bands.joined())
        junctionSlots = [Int32](repeating: -1, count: junctions.count * 4)
    }

    private mutating func trace(_ lat: LabelLattice) {
        let w = width, h = height
        var hVisited = [Bool](repeating: false, count: w * (h + 1))
        var vVisited = [Bool](repeating: false, count: (w + 1) * h)
        var chain: [UInt8] = []
        chain.reserveCapacity(1024)

        @inline(__always) func visit(_ cx: Int, _ cy: Int, _ d: UInt8) -> Bool {
            // Marks the segment and reports whether it was already visited.
            switch d {
            case 0:
                let i = cy * w + cx
                defer { hVisited[i] = true }
                return hVisited[i]
            case 2:
                let i = cy * w + cx - 1
                defer { hVisited[i] = true }
                return hVisited[i]
            case 1:
                let i = cy * (w + 1) + cx
                defer { vVisited[i] = true }
                return vVisited[i]
            default:
                let i = (cy - 1) * (w + 1) + cx
                defer { vVisited[i] = true }
                return vVisited[i]
            }
        }

        @inline(__always) func isVisited(_ cx: Int, _ cy: Int, _ d: UInt8) -> Bool {
            switch d {
            case 0: return hVisited[cy * w + cx]
            case 2: return hVisited[cy * w + cx - 1]
            case 1: return vVisited[cy * (w + 1) + cx]
            default: return vVisited[(cy - 1) * (w + 1) + cx]
            }
        }

        // Open chains, started from every junction in raster order.
        for j in 0..<junctions.count {
            let sx = Int(junctions[j]) % (w + 1), sy = Int(junctions[j]) / (w + 1)
            let m = lat.mask(sx, sy)
            for d0 in 0..<UInt8(4) where m & (1 << d0) != 0 && !isVisited(sx, sy, d0) {
                chain.removeAll(keepingCapacity: true)
                var cx = sx, cy = sy, d = d0
                var area2: Int64 = 0
                while true {
                    _ = visit(cx, cy, d)
                    chain.append(d)
                    let nx = cx + BoundaryGraph.dx[Int(d)], ny = cy + BoundaryGraph.dy[Int(d)]
                    area2 += Int64(cx * ny - nx * cy)
                    cx = nx; cy = ny
                    let cm = lat.mask(cx, cy)
                    if cm.nonzeroBitCount >= 3 { break }
                    d = UInt8((cm & ~(1 << ((d + 2) & 3))).trailingZeroBitCount)
                }
                let l = lat.left(sx, sy, d0), r = lat.right(sx, sy, d0)
                appendEdge(
                    chain: chain, start: SIMD2(Int32(sx), Int32(sy)), end: SIMD2(Int32(cx), Int32(cy)),
                    left: l, right: r, area2: area2, closed: false)
            }
        }

        // Junction-free cycles. Scanning horizontal segments in raster order finds each
        // cycle at the top-left corner of its topmost row, a canonical, deterministic start.
        for cy in 0...h {
            for cx in 0..<w where !hVisited[cy * w + cx] && lat.at(cx, cy - 1) != lat.at(cx, cy) {
                chain.removeAll(keepingCapacity: true)
                var x = cx, y = cy, d: UInt8 = 0
                var area2: Int64 = 0
                while true {
                    _ = visit(x, y, d)
                    chain.append(d)
                    let nx = x + BoundaryGraph.dx[Int(d)], ny = y + BoundaryGraph.dy[Int(d)]
                    area2 += Int64(x * ny - nx * y)
                    x = nx; y = ny
                    if x == cx && y == cy { break }
                    let cm = lat.mask(x, y)
                    d = UInt8((cm & ~(1 << ((d + 2) & 3))).trailingZeroBitCount)
                }
                let p = SIMD2(Int32(cx), Int32(cy))
                appendEdge(
                    chain: chain, start: p, end: p,
                    left: lat.left(cx, cy, 0), right: lat.right(cx, cy, 0), area2: area2, closed: true)
            }
        }
    }

    /// Appends a traced chain in canonical orientation (`left < right`) and registers its
    /// ends in the junction slots.
    private mutating func appendEdge(
        chain: [UInt8], start: SIMD2<Int32>, end: SIMD2<Int32>,
        left: UInt32, right: UInt32, area2: Int64, closed: Bool
    ) {
        let e = Int32(edgeLeft.count)
        edgeStepStart.append(Int32(steps.count))
        edgeStepCount.append(Int32(chain.count))
        edgeClosed.append(closed)
        if left < right {
            steps.append(contentsOf: chain)
            edgeLeft.append(left); edgeRight.append(right)
            edgeStart.append(start); edgeEnd.append(end)
            edgeArea2.append(area2)
        } else {
            for d in chain.reversed() { steps.append((d + 2) & 3) }
            edgeLeft.append(right); edgeRight.append(left)
            edgeStart.append(end); edgeEnd.append(start)
            edgeArea2.append(-area2)
        }
        guard !closed else { return }
        let ei = Int(e)
        let s = edgeStart[ei], t = edgeEnd[ei]
        if let js = junctionIndex(x: Int(s.x), y: Int(s.y)) {
            junctionSlots[js * 4 + Int(firstStep(ei))] = e * 2
        }
        if let jt = junctionIndex(x: Int(t.x), y: Int(t.y)) {
            junctionSlots[jt * 4 + Int((lastStep(ei) + 2) & 3)] = e * 2 + 1
        }
    }
}

// MARK: - Rings

/// Rings of every region, derived from the lattice topology (independent of smoothing).
struct RingTopology: Sendable {
    var ringEdges: [EdgeRef] = []
    var rings: [Ring] = []
    var regionRingStart: [UInt32] = []
    var regionRingCount: [UInt32] = []
}

extension BoundaryGraph {

    /// Assembles each region's boundary into closed rings: the outer ring first, then holes.
    ///
    /// Every ring keeps its region on the `left` of each traversed edge, which makes outer
    /// rings positively oriented and holes negatively oriented (see `BoundaryEdge`). At a
    /// junction, a ring leaves along the boundary segment that turns most sharply towards
    /// its region, so rings never cut between diagonally touching pixels (4-connectivity)
    /// and stay simple apart from touching themselves at checkerboard junctions.
    func assembleRings(labels map: RegionMap, regionCount: Int) -> RingTopology {
        // Directed edge references per region (CSR), in edge order.
        var refStart = [Int](repeating: 0, count: regionCount + 1)
        for e in 0..<edgeCount {
            refStart[Int(edgeLeft[e]) + 1] += 1
            if edgeRight[e] != BoundaryEdge.outside { refStart[Int(edgeRight[e]) + 1] += 1 }
        }
        for r in 0..<regionCount { refStart[r + 1] += refStart[r] }
        var refs = [UInt32](repeating: 0, count: refStart[regionCount])
        var fill = refStart
        for e in 0..<edgeCount {
            let l = Int(edgeLeft[e])
            refs[fill[l]] = UInt32(e) << 1
            fill[l] += 1
            if edgeRight[e] != BoundaryEdge.outside {
                let r = Int(edgeRight[e])
                refs[fill[r]] = UInt32(e) << 1 | 1
                fill[r] += 1
            }
        }

        struct Band {
            var ringEdges: [EdgeRef] = []
            var rings: [Ring] = []
            var ringCounts: [UInt32] = []
        }

        let bands: [Band] = map.storage.withUnsafeBufferPointer { buf in
            let lat = LabelLattice(labels: buf, width: width, height: height)
            return Parallel.mapBands(regionCount, minimumBandSize: 64) { range -> Band in
                var band = Band()
                var used: [Bool] = []
                var ring: [UInt32] = []
                var ringsOfRegion: [(refs: [UInt32], area2: Int64)] = []
                for r in range {
                    let lo = refStart[r], hi = refStart[r + 1]
                    used.removeAll(keepingCapacity: true)
                    used.append(contentsOf: repeatElement(false, count: hi - lo))
                    ringsOfRegion.removeAll(keepingCapacity: true)
                    for k in lo..<hi where !used[k - lo] {
                        ring.removeAll(keepingCapacity: true)
                        var area2: Int64 = 0
                        var cur = refs[k]
                        var guardCount = 0
                        repeat {
                            guard let slot = self.refSlot(cur, refs: refs, lo: lo, hi: hi) else { break }
                            used[slot - lo] = true
                            ring.append(cur)
                            let e = Int(cur >> 1)
                            area2 += cur & 1 == 0 ? edgeArea2[e] : -edgeArea2[e]
                            cur = self.nextRef(cur, region: UInt32(r), lat: lat)
                            guardCount += 1
                        } while cur != refs[k] && guardCount <= hi - lo
                        ringsOfRegion.append((ring, area2))
                    }
                    // Outer ring first (largest positive area), then holes in discovery order.
                    var outer = 0
                    for (i, ring) in ringsOfRegion.enumerated() where ring.area2 > ringsOfRegion[outer].area2 {
                        outer = i
                    }
                    var order = [outer]
                    for i in ringsOfRegion.indices where i != outer { order.append(i) }
                    for i in order {
                        let refsOfRing = ringsOfRegion[i].refs
                        band.rings.append(Ring(
                            edgeStart: UInt32(band.ringEdges.count), edgeCount: UInt32(refsOfRing.count),
                            isHole: ringsOfRegion[i].area2 < 0))
                        for ref in refsOfRing { band.ringEdges.append(EdgeRef(edge: ref >> 1, reversed: ref & 1 != 0)) }
                    }
                    band.ringCounts.append(UInt32(ringsOfRegion.count))
                }
                return band
            }
        }

        var topo = RingTopology()
        topo.regionRingStart.reserveCapacity(regionCount)
        topo.regionRingCount.reserveCapacity(regionCount)
        for band in bands {
            let edgeBase = UInt32(topo.ringEdges.count)
            var ringCursor = UInt32(topo.rings.count)
            topo.ringEdges.append(contentsOf: band.ringEdges)
            for ring in band.rings {
                topo.rings.append(Ring(edgeStart: ring.edgeStart + edgeBase, edgeCount: ring.edgeCount, isHole: ring.isHole))
            }
            for count in band.ringCounts {
                topo.regionRingStart.append(ringCursor)
                topo.regionRingCount.append(count)
                ringCursor += count
            }
        }
        return topo
    }

    /// Index of `ref` within the region's reference list `refs[lo..<hi]`.
    private func refSlot(_ ref: UInt32, refs: [UInt32], lo: Int, hi: Int) -> Int? {
        // Region reference lists are sorted by edge (then direction), so binary search.
        var a = lo, b = hi
        while a < b {
            let mid = (a + b) >> 1
            if refs[mid] < ref { a = mid + 1 } else { b = mid }
        }
        return a < hi && refs[a] == ref ? a : nil
    }

    /// The reference following `ref` in the ring of `region`.
    private func nextRef(_ ref: UInt32, region: UInt32, lat: LabelLattice) -> UInt32 {
        let e = Int(ref >> 1)
        if edgeClosed[e] { return ref }
        let reversed = ref & 1 != 0
        let p = reversed ? edgeStart[e] : edgeEnd[e]
        let arrive = reversed ? (firstStep(e) + 2) & 3 : lastStep(e)
        let cx = Int(p.x), cy = Int(p.y)
        guard let j = junctionIndex(x: cx, y: cy) else { return ref }
        for turn: UInt8 in [1, 0, 3] {
            let d = (arrive + turn) & 3
            if lat.left(cx, cy, d) == region && lat.right(cx, cy, d) != region {
                let code = junctionSlots[j * 4 + Int(d)]
                if code >= 0 { return UInt32(code) }
            }
        }
        return ref
    }
}
