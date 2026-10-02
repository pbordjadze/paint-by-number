import Foundation

/// The color segmentation split into cells by drawn lines (every cell keeps its paint).
///
/// 1. Wall pixels (the rasterized lines) are taken out of the paint map. Paint boundaries
///    running within 2.5 px of a wall leave thin strips between boundary and wall; those
///    pixels (outside the opening of their paint by a 5-px disc) go to the paints beside
///    them on their side of the wall, so the paint boundary lands on the line.
/// 2. Cells are the 4-connected components of equal paint between the walls.
/// 3. Cells too small for their number merge into a neighbour in their enclosed area (never
///    across a wall), smallest first, preferring long shared borders and close paints.
/// 4. Wall pixels go to the cells beside them (majority of their assigned neighbours).
/// 5. No cell stays too small for its number: the rest merge across a line, into a cell of
///    the same paint when there is one (across the weakest line first), else into the
///    closest paint.
///
/// Room is measured like the vectorizer's guarantee: the cell's largest
/// `DistanceTransform.interiorDistance`, which must reach `SegmentationParameters.minRadius(digits:)`.
struct CellMap {
    /// Cell per pixel; -1 on walls not yet assigned.
    var label: [Int32]
    /// Palette index per cell.
    var color: [UInt32]
    let width: Int
    let height: Int

    var count: Int { color.count }

    /// Classes of the border between two neighbouring cells, by the strongest line near it:
    /// `LineLayer` raw values 0...2, 3 for no line (only the paint changes).
    struct Pair {
        var border: Int32 = 0
        var lines = SIMD4<Int32>(repeating: 0)
    }

    static let snapRadiusSquared = 4
    static let snapBand: Float = 2.5
    /// A same-paint pair is kept apart when a blocking line runs along this many border pixels.
    static let joinBlock: Int32 = 4

    // MARK: - Split

    static func split(paint: [UInt32], walls: LineLayering.Walls) -> CellMap {
        let w = walls.width, h = walls.height, n = w * h
        let wallValue = UInt32.max
        var color = [UInt32](uninitializedCount: n)
        for i in 0..<n { color[i] = walls.isWall(i) ? wallValue : paint[i] }
        snapThinNearWalls(&color, width: w, height: h, wallValue: wallValue)
        let components = ConnectedComponents.label(Grid(width: w, height: h, storage: color))
        var cellOf = [Int32](repeating: -1, count: components.count)
        var cellColor: [UInt32] = []
        for (c, cls) in components.classOf.enumerated() where cls != wallValue {
            cellOf[c] = Int32(cellColor.count)
            cellColor.append(cls)
        }
        let label = components.labels.storage.map { cellOf[Int($0)] }
        return CellMap(label: label, color: cellColor, width: w, height: h)
    }

    /// Pixels of a paint that no disc of that paint (OpenCV's 5×5 ellipse) covers and that
    /// lie within `snapBand` of a wall are handed to the paints around them, growing ring by
    /// ring over 4-neighbours that are not walls (the most frequent paint wins, then the
    /// lowest); pixels nothing reaches keep their paint.
    static func snapThinNearWalls(_ color: inout [UInt32], width w: Int, height h: Int, wallValue: UInt32) {
        let n = w * h
        let disc: [(Int, Int)] = (-2...2).flatMap { dy in (-2...2).compactMap { dx in
            (abs(dy) == 2 && dx != 0) ? nil : (dx, dy)
        } }
        let src = color
        @inline(__always) func at(_ x: Int, _ y: Int) -> UInt32 {
            src[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)]
        }
        // Disc centres lying entirely inside their paint (walls are no paint).
        var core = [Bool](repeating: false, count: n)
        core.withUnsafeMutableBufferPointer { out in
            let o = UncheckedSendable(out.baseAddress!)
            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                for y in rows {
                    for x in 0..<w {
                        let c = src[y * w + x]
                        guard c != wallValue else { continue }
                        var inside = true
                        for (dx, dy) in disc where at(x + dx, y + dy) != c { inside = false; break }
                        o.value[y * w + x] = inside
                    }
                }
            }
        }
        let wallDistance = DistanceTransform.squaredEDT(width: w, height: h) { src[$0] == wallValue }
        let band2 = snapBand * snapBand
        let hole = UInt32.max - 1
        var out = src
        var holes = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let c = src[i]
                guard c != wallValue, wallDistance.storage[i] <= band2 else { continue }
                var covered = false
                for (dx, dy) in disc {
                    let xx = x + dx, yy = y + dy
                    guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
                    if core[yy * w + xx] && src[yy * w + xx] == c { covered = true; break }
                }
                if !covered { out[i] = hole; holes += 1 }
            }
        }
        guard holes > 0 else { return }
        var pending = (0..<n).filter { out[$0] == hole }
        for _ in 0..<64 where !pending.isEmpty {
            var updates: [(Int, UInt32)] = []
            for i in pending {
                let y = i / w, x = i - y * w
                var values: [UInt32] = []
                if y > 0 { values.append(out[i - w]) }
                if y < h - 1 { values.append(out[i + w]) }
                if x > 0 { values.append(out[i - 1]) }
                if x < w - 1 { values.append(out[i + 1]) }
                var best = hole, bestCount = 0
                for v in values where v != hole && v != wallValue {
                    let c = values.filter { $0 == v }.count
                    if c > bestCount || (c == bestCount && v < best) { best = v; bestCount = c }
                }
                if bestCount > 0 { updates.append((i, best)) }
            }
            if updates.isEmpty { break }
            for (i, v) in updates { out[i] = v }
            pending = pending.filter { out[$0] == hole }
        }
        for i in pending { out[i] = src[i] }
        color = out
    }

    // MARK: - Measures

    /// Largest interior distance per cell (walls, while unassigned, bound cells like another cell).
    func rooms() -> [Float] {
        let n = width * height
        let sentinel = UInt32(count)
        var labels = [UInt32](uninitializedCount: n)
        for i in 0..<n { labels[i] = label[i] < 0 ? sentinel : UInt32(label[i]) }
        let distance = DistanceTransform.interiorDistance(labels: RegionMap(width: width, height: height, storage: labels))
        var room = [Float](repeating: 0, count: count)
        for i in 0..<n where label[i] >= 0 {
            let c = Int(label[i])
            if distance.storage[i] > room[c] { room[c] = distance.storage[i] }
        }
        return room
    }

    /// Area and bounds per cell.
    func extents() -> (area: [Int], bounds: [PixelBounds]) {
        var area = [Int](repeating: 0, count: count)
        var bounds = [PixelBounds](repeating: .empty, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let c = label[y * width + x]
                guard c >= 0 else { continue }
                area[Int(c)] += 1
                bounds[Int(c)].include(x: x, y: y)
            }
        }
        return (area, bounds)
    }

    /// The interior-distance room of the pixels in `bounds` that `member` accepts.
    func room(bounds: PixelBounds, member: (Int32) -> Bool) -> Float {
        let bw = bounds.width, bh = bounds.height
        guard bw > 0, bh > 0 else { return 0 }
        let x0 = Int(bounds.minX), y0 = Int(bounds.minY)
        var inside = [Bool](repeating: false, count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw { inside[y * bw + x] = member(label[(y0 + y) * width + x0 + x]) }
        }
        var feature = [UInt8](repeating: 0, count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw where inside[y * bw + x] {
                let gx = x0 + x, gy = y0 + y
                let edge = gx == 0 || gy == 0 || gx == width - 1 || gy == height - 1
                    || x == 0 || !inside[y * bw + x - 1] || x == bw - 1 || !inside[y * bw + x + 1]
                    || y == 0 || !inside[(y - 1) * bw + x] || y == bh - 1 || !inside[(y + 1) * bw + x]
                if edge { feature[y * bw + x] = 1 }
            }
        }
        let d2 = try! DistanceTransform.squaredDistances(feature, width: bw, height: bh, cancel: .none)
        var best: Double = -1
        for i in 0..<(bw * bh) where inside[i] && d2[i] > best { best = d2[i] }
        return best < 0 ? 0 : Float(best).squareRoot() + 0.5
    }

    /// Neighbouring cells (4-adjacent pixels of different cells) with their border length and
    /// the strongest line within a pixel of each border step (`near`: `LineLayer` raw value
    /// per pixel, 255 for none). Keys are `low << 32 | high`.
    func pairs(near: [UInt8]) -> [UInt64: Pair] {
        var out: [UInt64: Pair] = [:]
        @inline(__always) func add(_ i: Int, _ j: Int) {
            let a = label[i], b = label[j]
            guard a >= 0, b >= 0, a != b else { return }
            let key = UInt64(UInt32(min(a, b))) << 32 | UInt64(UInt32(max(a, b)))
            let l = Int(min(min(near[i], near[j]), 3))
            out[key, default: Pair()].border += 1
            out[key]!.lines[l] += 1
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if x + 1 < width { add(i, i + 1) }
                if y + 1 < height { add(i, i + width) }
            }
        }
        return out
    }

    /// The strongest line class that runs along a fair share of a border (3: none).
    static func separation(_ p: Pair) -> Int {
        let enough = max(1, min(joinBlock, p.border / 3))
        for l in 0..<3 where p.lines[l] >= enough { return l }
        return 3
    }

    /// Per pixel, the strongest layer within one pixel (3×3), from a layer raster.
    static func near(_ layer: [UInt8], width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: LineLayering.none, count: w * h)
        layer.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                let s = UncheckedSendable(src.baseAddress!), d = UncheckedSendable(dst.baseAddress!)
                Parallel.forEachBand(h, minimumBandSize: 32) { rows in
                    for y in rows {
                        for x in 0..<w {
                            var v = LineLayering.none
                            for yy in max(0, y - 1)...min(h - 1, y + 1) {
                                for xx in max(0, x - 1)...min(w - 1, x + 1) { v = min(v, s.value[yy * w + xx]) }
                            }
                            d.value[y * w + x] = v
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: - Merges

    /// Applies `target` (each cell's representative, roots map to themselves) and renumbers
    /// the surviving cells in order.
    mutating func merge(_ target: [Int]) {
        func root(_ k: Int) -> Int {
            var r = k
            while target[r] != r { r = target[r] }
            return r
        }
        var newID = [Int32](repeating: -1, count: count)
        var colors: [UInt32] = []
        for k in 0..<count where target[k] == k {
            newID[k] = Int32(colors.count)
            colors.append(color[k])
        }
        let lut = (0..<count).map { newID[root($0)] }
        for i in label.indices where label[i] >= 0 { label[i] = lut[Int(label[i])] }
        color = colors
    }

    /// Step 3: cells too small for their number merge into a neighbour in their enclosed
    /// area (walls unassigned, so never across a line), smallest room first. The neighbour
    /// maximizes border length / (paint difference + 0.03); a merged cell's room is measured
    /// again when it still falls short.
    mutating func mergeSmallWithinAreas(need: (UInt32) -> Float, palette: [SIMD3<Float>]) -> Int {
        var room = rooms()
        let (area, boundsOf) = extents()
        _ = area
        var bounds = boundsOf
        var adjacency = [[Int: Int32]](repeating: [:], count: count)
        for (key, pair) in pairs(near: [UInt8](repeating: LineLayering.none, count: width * height)) {
            let a = Int(key >> 32), b = Int(key & 0xFFFF_FFFF)
            adjacency[a][b] = pair.border
            adjacency[b][a] = pair.border
        }
        var parent = Array(0..<count)
        var heap = Heap<(Float, Int)> { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        for k in 0..<count where room[k] < need(color[k]) { heap.push((room[k], k)) }
        var merges = 0
        func root(_ k: Int) -> Int {
            var r = k
            while parent[r] != r { r = parent[r] }
            return r
        }
        while let (r, k) = heap.pop() {
            guard parent[k] == k, r == room[k], room[k] < need(color[k]) else { continue }
            let neighbours = adjacency[k]
            guard !neighbours.isEmpty else { continue }
            var best = -1
            var bestScore: Float = -1
            for b in neighbours.keys.sorted() {
                let score = Float(neighbours[b]!) / (simdDistance(palette[Int(color[b])], palette[Int(color[k])]) + 0.03)
                if score > bestScore { best = b; bestScore = score }
            }
            let t = best
            parent[k] = t
            bounds[t].formUnion(bounds[k])
            for (b, length) in adjacency[k] where b != t {
                adjacency[b][k] = nil
                adjacency[b][t, default: 0] += length
                adjacency[t][b, default: 0] += length
            }
            adjacency[t][k] = nil
            adjacency[k] = [:]
            merges += 1
            if room[t] < need(color[t]) {
                room[t] = self.room(bounds: bounds[t]) { $0 >= 0 && root(Int($0)) == t }
                heap.push((room[t], t))
            }
        }
        merge(parent)
        return merges
    }

    /// Step 4: wall pixels join the cells beside them, ring by ring (the most frequent
    /// assigned 4-neighbour, then the lowest cell).
    mutating func assignWalls() {
        let w = width, h = height
        var pending = label.indices.filter { label[$0] < 0 }
        while !pending.isEmpty {
            var updates: [(Int, Int32)] = []
            for i in pending {
                let y = i / w, x = i - y * w
                var values: [Int32] = []
                if y > 0 { values.append(label[i - w]) }
                if y < h - 1 { values.append(label[i + w]) }
                if x > 0 { values.append(label[i - 1]) }
                if x < w - 1 { values.append(label[i + 1]) }
                var best: Int32 = -1, bestCount = 0
                for v in values where v >= 0 {
                    let c = values.filter { $0 == v }.count
                    if c > bestCount || (c == bestCount && v < best) { best = v; bestCount = c }
                }
                if bestCount > 0 { updates.append((i, best)) }
            }
            // A canvas made only of walls has no cell to grow from.
            if updates.isEmpty { break }
            for (i, v) in updates { label[i] = v }
            pending = pending.filter { label[$0] < 0 }
        }
    }

    /// Step 5 (walls assigned): cells still too small for their number merge across a line,
    /// into the same paint when a neighbour has it (across the weakest line, then the longest
    /// border), else into the closest paint. Repeats until every cell holds its number.
    mutating func mergeTiny(
        need: (UInt32) -> Float, palette: [SIMD3<Float>], near: [UInt8], keep: (Int) -> Bool = { _ in false }
    ) -> Int {
        var merges = 0
        while true {
            let room = rooms()
            let tiny = (0..<count).filter { room[$0] < need(color[$0]) }
                .sorted { room[$0] != room[$1] ? room[$0] < room[$1] : $0 < $1 }
            guard !tiny.isEmpty else { return merges }
            var neighbours = [[(cell: Int, pair: Pair)]](repeating: [], count: count)
            for (key, pair) in pairs(near: near).sorted(by: { $0.key < $1.key }) {
                let a = Int(key >> 32), b = Int(key & 0xFFFF_FFFF)
                neighbours[a].append((b, pair))
                neighbours[b].append((a, pair))
            }
            var target = Array(0..<count)
            func root(_ k: Int) -> Int {
                var r = k
                while target[r] != r { r = target[r] }
                return r
            }
            var progress = false
            for k in tiny {
                let options = neighbours[k]
                guard !options.isEmpty else { continue }
                let ck = palette[Int(color[k])]
                let same = options.filter { color[$0.cell] == color[k] }
                let pool = same.isEmpty ? options : same
                let best = pool.min { a, b in
                    let da = same.isEmpty ? simdDistance(palette[Int(color[a.cell])], ck) : 0
                    let db = same.isEmpty ? simdDistance(palette[Int(color[b.cell])], ck) : 0
                    if da != db { return da < db }
                    let sa = Self.separation(a.pair), sb = Self.separation(b.pair)
                    if sa != sb { return sa > sb }
                    if a.pair.border != b.pair.border { return a.pair.border > b.pair.border }
                    return a.cell < b.cell
                }!
                let t = root(best.cell)
                if t != k {
                    target[k] = t
                    merges += 1
                    progress = true
                }
            }
            guard progress else { return merges }
            merge(target)
        }
    }

    /// `keepColorEdges` off: neighbouring cells with no line between them whose paints are
    /// within `tolerance` merge (the larger cell keeps its paint; each merge is checked
    /// against the paints the groups have, so colours don't drift along a chain).
    mutating func mergeCloseColors(tolerance: Float, palette: [SIMD3<Float>], near: [UInt8]) -> Int {
        var total = 0
        for _ in 0..<12 {
            var area = extents().area
            let candidates = pairs(near: near).compactMap { key, pair -> (Float, Int, Int)? in
                guard Self.separation(pair) == 3 else { return nil }
                let a = Int(key >> 32), b = Int(key & 0xFFFF_FFFF)
                let d = simdDistance(palette[Int(color[a])], palette[Int(color[b])])
                return d <= tolerance ? (d, a, b) : nil
            }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : ($0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2) }
            var target = Array(0..<count)
            func root(_ k: Int) -> Int {
                var r = k
                while target[r] != r { r = target[r] }
                return r
            }
            var merged = 0
            for (_, a, b) in candidates {
                let ra = root(a), rb = root(b)
                guard ra != rb, simdDistance(palette[Int(color[ra])], palette[Int(color[rb])]) <= tolerance else { continue }
                let (big, small) = area[ra] >= area[rb] ? (ra, rb) : (rb, ra)
                target[small] = big
                area[big] += area[small]
                merged += 1
            }
            guard merged > 0 else { break }
            total += merged
            merge(target)
        }
        return total
    }

    /// Same-paint joins: neighbouring cells of one paint become one cell unless a blocking
    /// line (`blocking`: per `LineLayer` raw value) runs along `joinBlock` or more pixels of
    /// their border. Joins go longest border first and never unite two groups holding a
    /// separated pair, so no blocking line ends up inside a cell.
    mutating func joinSamePaint(near: [UInt8], blocking: [Bool]) -> Int {
        let all = pairs(near: near).sorted { $0.key < $1.key }
        var parent = Array(0..<count)
        var apart = [Set<Int>](repeating: [], count: count)
        var candidates: [(border: Int32, a: Int, b: Int)] = []
        for (key, pair) in all {
            let a = Int(key >> 32), b = Int(key & 0xFFFF_FFFF)
            guard color[a] == color[b] else { continue }
            var blocked: Int32 = 0
            for l in 0..<3 where blocking[l] { blocked += pair.lines[l] }
            if blocked >= Self.joinBlock {
                apart[a].insert(b)
                apart[b].insert(a)
            } else {
                candidates.append((pair.border, a, b))
            }
        }
        // Longest border first; the sort is stable over the key order.
        let order = candidates.indices.sorted { candidates[$0].border != candidates[$1].border ? candidates[$0].border > candidates[$1].border : $0 < $1 }
        func root(_ k: Int) -> Int {
            var r = k
            while parent[r] != r { r = parent[r] }
            return r
        }
        var joins = 0
        for index in order {
            var ra = root(candidates[index].a), rb = root(candidates[index].b)
            guard ra != rb, !apart[ra].contains(where: { root($0) == rb }) else { continue }
            if apart[rb].count > apart[ra].count { swap(&ra, &rb) }
            parent[rb] = ra
            apart[ra].formUnion(apart[rb])
            joins += 1
        }
        merge(parent)
        return joins
    }

    // MARK: - Finish

    /// Renumbers cells in raster order of their first pixel, splitting any cell that is not
    /// 4-connected into its components. Returns whether every cell was connected.
    @discardableResult
    mutating func renumber() -> Bool {
        let before = count
        let components = ConnectedComponents.label(Grid(width: width, height: height, storage: label.map { UInt32(bitPattern: $0) }))
        color = components.classOf.map { color[Int($0)] }
        label = components.labels.storage.map { Int32($0) }
        return components.count == before
    }

    /// Drops paints no cell uses (keeping the kit order); returns the kept palette indices.
    mutating func compactPalette(paletteCount: Int) -> [Int] {
        var used = [Bool](repeating: false, count: paletteCount)
        for c in color { used[Int(c)] = true }
        let kept = (0..<paletteCount).filter { used[$0] }
        var newIndex = [UInt32](repeating: 0, count: paletteCount)
        for (k, old) in kept.enumerated() { newIndex[old] = UInt32(k) }
        color = color.map { newIndex[Int($0)] }
        return kept
    }
}

/// Binary min-heap with a caller-supplied order.
struct Heap<Element> {
    private var items: [Element] = []
    private let less: (Element, Element) -> Bool

    init(_ less: @escaping (Element, Element) -> Bool) { self.less = less }

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ e: Element) {
        items.append(e)
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            guard less(items[i], items[p]) else { break }
            items.swapAt(i, p)
            i = p
        }
    }

    mutating func pop() -> Element? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count && less(items[l], items[m]) { m = l }
            if r < items.count && less(items[r], items[m]) { m = r }
            if m == i { break }
            items.swapAt(i, m)
            i = m
        }
        return top
    }
}

@inline(__always) func simdDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d = a - b
    return (d * d).sum().squareRoot()
}
