/// The pieces a mosaic is set from in stone: each tile as pieces a pair of nippers can cut, and the
/// pieces cut to fill the joints the engine left wider than a mosaicist would.
enum BookPieces {
    typealias Point = BookGeometry.Point

    /// A tile as the pieces nippers can cut: convex ones. A slight notch is trimmed away (the
    /// tile becomes its convex hull); a real one splits the tile into convex pieces (its
    /// triangulation merged back while each union stays convex: Hertel and Mehlhorn), each cut
    /// leaving a joint, and a chip too small to cut is left to the grout.
    static func cuttable(_ tile: [Point], medianArea: Double, joint: Double, minimumWidth: Double) -> [[Point]] {
        let hull = BookGeometry.hull(tile)
        let area = BookGeometry.area(tile), hullArea = BookGeometry.area(hull)
        guard hull.count >= 3 else { return [] }
        if area >= 0.95 * hullArea { return [hull] }
        var pieces = BookGeometry.triangles(tile)
        guard !pieces.isEmpty else { return [hull] }
        func corners(_ piece: [Int]) -> [Point] { piece.map { tile[$0] } }
        func nearlyConvex(_ piece: [Int]) -> Bool {
            let c = corners(piece)
            return BookGeometry.area(c) >= 0.995 * BookGeometry.area(BookGeometry.hull(c))
        }
        // join the pair whose union is largest while it stays convex, until no pair does
        while true {
            var best: (a: Int, b: Int, union: [Int], area: Double)?
            for a in pieces.indices {
                for b in (a + 1)..<pieces.count {
                    guard let union = BookGeometry.join(pieces[a], pieces[b]), nearlyConvex(union) else { continue }
                    let ua = BookGeometry.area(corners(union))
                    if best == nil || ua > best!.area { best = (a, b, union, ua) }
                }
            }
            guard let best else { break }
            pieces.remove(at: best.b)
            pieces.remove(at: best.a)
            pieces.append(best.union)
        }
        let sorted = pieces.map { BookGeometry.hull(corners($0)) }
            .enumerated()
            .sorted { BookGeometry.area($0.element) != BookGeometry.area($1.element)
                ? BookGeometry.area($0.element) > BookGeometry.area($1.element) : $0.offset < $1.offset }
            .map(\.element)
        var out: [[Point]] = []
        for piece in sorted {
            if !out.isEmpty,
               BookGeometry.area(piece) < 0.12 * medianArea || BookGeometry.minimumWidth(piece) < minimumWidth { continue }
            guard let cut = BookGeometry.inset(piece, by: joint / 2) else { continue }
            out.append(cut)
        }
        return out.isEmpty ? [hull] : out
    }

    /// Which piece covers each pixel's centre (-1: none), on a raster `pixel` units square.
    static func labels(_ pieces: [[Point]], w: Int, h: Int, pixel: Double) -> [Int32] {
        var label = [Int32](repeating: -1, count: w * h)
        for (index, piece) in pieces.enumerated() {
            var lo = Point(.infinity, .infinity), hi = -lo
            for c in piece { lo = pointwiseMin(lo, c); hi = pointwiseMax(hi, c) }
            let x0 = max(0, Int((lo.x / pixel).rounded(.down))), x1 = min(w - 1, Int((hi.x / pixel).rounded(.up)))
            let y0 = max(0, Int((lo.y / pixel).rounded(.down))), y1 = min(h - 1, Int((hi.y / pixel).rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 where BookGeometry.contains(piece, Point((Double(x) + 0.5) * pixel, (Double(y) + 0.5) * pixel)) {
                    label[y * w + x] = Int32(index)
                }
            }
        }
        return label
    }

    /// The pieces cut to fit, as a mosaicist cuts each tessera to its neighbours: each grows into
    /// the room nearest it (up to `reach` from its edge), stopping half a joint short of the line
    /// where its room meets a neighbour's. A piece whose grown hull would cross into a
    /// neighbour's room keeps its shape. Convex pieces in, convex pieces out, in the same order.
    static func fitted(_ pieces: [[Point]], width: Double, height: Double, pixel: Double, joint: Double, reach: Double) -> [[Point]] {
        let w = max(1, Int((width / pixel).rounded(.up))), h = max(1, Int((height / pixel).rounded(.up)))
        let n = w * h
        var near = labels(pieces, w: w, h: h, pixel: pixel)
        var dist = near.map { $0 >= 0 ? Float(0) : .infinity }
        Chamfer.run(&dist, w: w, h: h, carrying: &near)
        let reachPx = Float(reach / pixel)
        // how far each pixel is from where two pieces' rooms meet
        var seam = [Float](repeating: .infinity, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard dist[i] <= reachPx else { continue }
                if (x < w - 1 && dist[i + 1] <= reachPx && near[i + 1] != near[i])
                    || (y < h - 1 && dist[i + w] <= reachPx && near[i + w] != near[i])
                    || (x > 0 && dist[i - 1] <= reachPx && near[i - 1] != near[i])
                    || (y > 0 && dist[i - w] <= reachPx && near[i - w] != near[i]) {
                    seam[i] = 0.5
                }
            }
        }
        var none = [Int32](repeating: 0, count: n)
        Chamfer.run(&seam, w: w, h: h, carrying: &none)
        let half = Float(joint / pixel / 2)
        var room = [[(Point, Float)]](repeating: [], count: pieces.count)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard near[i] >= 0, dist[i] > 0, dist[i] <= reachPx, seam[i] >= half + 0.5 else { continue }
                room[Int(near[i])].append((Point((Double(x) + 0.5) * pixel, (Double(y) + 0.5) * pixel), dist[i]))
            }
        }
        // the hull may not reach into a neighbour's room: a piece that would tries a shorter reach
        func clear(_ grown: [Point], _ index: Int) -> Bool {
            var lo = Point(.infinity, .infinity), hi = -lo
            for c in grown { lo = pointwiseMin(lo, c); hi = pointwiseMax(hi, c) }
            let x0 = max(0, Int(lo.x / pixel)), x1 = min(w - 1, Int(hi.x / pixel))
            let y0 = max(0, Int(lo.y / pixel)), y1 = min(h - 1, Int(hi.y / pixel))
            for y in y0...max(y0, y1) {
                for x in x0...max(x0, x1) {
                    let i = y * w + x
                    guard near[i] != Int32(index), near[i] >= 0, dist[i] <= reachPx else { continue }
                    if BookGeometry.contains(grown, Point((Double(x) + 0.5) * pixel, (Double(y) + 0.5) * pixel)) { return false }
                }
            }
            return true
        }
        return pieces.enumerated().map { index, piece in
            guard !room[index].isEmpty else { return piece }
            for share in [Float(1), 0.6, 0.35] {
                let points = room[index].filter { $0.1 <= reachPx * share }.map(\.0)
                guard !points.isEmpty else { continue }
                let grown = BookGeometry.simplified(BookGeometry.hull(piece + points))
                if clear(grown, index) { return grown }
            }
            return piece
        }
    }

    /// A piece cut to fill a wide joint, and the piece beside it whose stone it is cut from.
    struct Filler: Sendable, Equatable {
        var corners: [Point]
        var neighbour: Int
    }

    /// Pieces cut to fill the joints wider than `joint` between `pieces` (convex, in canvas units),
    /// the way a mosaicist closes the gaps: on a raster of `pixel` units, the room more than a joint
    /// from every piece and the canvas's edge, opened so only what a piece `minimumWidth` across
    /// fits stays, is split into cells about `targetArea` in size (seeded farthest first, each
    /// pixel to its nearest seed). Each cell becomes its convex hull, a joint from its neighbours;
    /// a cell that isn't nearly convex, or whose hull would touch a piece, is split again, and one
    /// too small or narrow to cut is left to the grout. Each takes the stone of the piece nearest
    /// most of its pixels.
    static func fillers(_ pieces: [[Point]], width: Double, height: Double, pixel: Double, joint: Double,
                        minimumWidth: Double, targetArea: Double) -> [Filler] {
        let w = max(1, Int((width / pixel).rounded(.up))), h = max(1, Int((height / pixel).rounded(.up)))
        let n = w * h
        // 1. which piece covers each pixel's centre
        let label = labels(pieces, w: w, h: h, pixel: pixel)
        // 2. how far each pixel is from the nearest piece, and which piece that is
        var near = label
        var dist = label.map { $0 >= 0 ? Float(0) : .infinity }
        Chamfer.run(&dist, w: w, h: h, carrying: &near)
        // the canvas's edge holds the room off too, as a piece would
        for y in 0..<h {
            for x in 0..<w {
                let e = Float(min(min(x, w - 1 - x), min(y, h - 1 - y))) + 0.5
                if e < dist[y * w + x] { dist[y * w + x] = e }
            }
        }
        // 3. the room: farther than a joint from everything
        let jointPx = Float(joint / pixel)
        let room = dist.map { $0 >= jointPx + 0.5 }
        // 4. opened by a disc minimumWidth across: only where a piece that wide fits
        let r = Float(minimumWidth / pixel / 2)
        var inner = room.map { $0 ? Float.infinity : 0 }
        var none = [Int32](repeating: 0, count: n)
        Chamfer.run(&inner, w: w, h: h, carrying: &none)
        var fromCore = inner.map { $0 >= r ? Float(0) : .infinity }
        Chamfer.run(&fromCore, w: w, h: h, carrying: &none)
        var open = [Bool](repeating: false, count: n)
        for i in 0..<n where room[i] && fromCore[i] <= r { open[i] = true }

        let pixelArea = pixel * pixel
        let target = max(4, targetArea / pixelArea)
        let minArea = 0.12 * target
        var out: [Filler] = []

        func emit(_ cell: [Int], depth: Int) {
            guard Double(cell.count) >= minArea else { return }
            let centres = cell.map { Point((Double($0 % w) + 0.5) * pixel, (Double($0 / w) + 0.5) * pixel) }
            let hull = BookGeometry.simplified(BookGeometry.hull(centres))
            // the hull of the pixels' centres is about half a pixel inside the cell's own edge
            var perimeter = 0.0
            for k in hull.indices {
                let d = hull[(k + 1) % hull.count] - hull[k]
                perimeter += ((d * d).sum()).squareRoot()
            }
            let hullPx = (BookGeometry.area(hull) + perimeter * pixel / 2) / pixelArea + 1
            let cut = BookGeometry.inset(hull, by: max(joint / 2 - pixel / 2, 0)) ?? []
            var good = hull.count >= 3 && Double(cell.count) >= 0.88 * hullPx && cut.count >= 3
                && BookGeometry.minimumWidth(cut) >= minimumWidth && BookGeometry.area(cut) >= minArea * pixelArea
            if good {
                // the hull may not reach nearer a piece than half a joint
                var lo = Point(.infinity, .infinity), hi = -lo
                for c in cut { lo = pointwiseMin(lo, c); hi = pointwiseMax(hi, c) }
                let x0 = max(0, Int(lo.x / pixel)), x1 = min(w - 1, Int(hi.x / pixel))
                let y0 = max(0, Int(lo.y / pixel)), y1 = min(h - 1, Int(hi.y / pixel))
                check: for y in y0...max(y0, y1) {
                    for x in x0...max(x0, x1) where dist[y * w + x] < jointPx * 0.5 + 0.5
                        && BookGeometry.contains(cut, Point((Double(x) + 0.5) * pixel, (Double(y) + 0.5) * pixel)) {
                        good = false
                        break check
                    }
                }
            }
            if good {
                var votes: [Int32: Int] = [:]
                for i in cell where near[i] >= 0 { votes[near[i], default: 0] += 1 }
                guard let neighbour = votes.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else { return }
                out.append(Filler(corners: cut, neighbour: Int(neighbour)))
                return
            }
            guard depth < 4, Double(cell.count) >= 2 * minArea else { return }
            for part in split(cell, into: 2) { emit(part, depth: depth + 1) }
        }

        /// Farthest-first seeds from the pixel deepest in the cell, each pixel to its nearest.
        func split(_ cell: [Int], into count: Int) -> [[Int]] {
            guard count > 1 else { return [cell] }
            func point(_ i: Int) -> SIMD2<Float> { SIMD2(Float(i % w), Float(i / w)) }
            var first = cell[0]
            for i in cell where inner[i] > inner[first] { first = i }
            var seeds = [point(first)]
            var nearest = cell.map { p -> Float in let d = point(p) - seeds[0]; return (d * d).sum() }
            while seeds.count < count {
                var far = 0
                for k in nearest.indices where nearest[k] > nearest[far] { far = k }
                let s = point(cell[far])
                seeds.append(s)
                for k in cell.indices {
                    let d = point(cell[k]) - s
                    nearest[k] = min(nearest[k], (d * d).sum())
                }
            }
            var parts = [[Int]](repeating: [], count: count)
            for p in cell {
                let q = point(p)
                var best = 0, bestD = Float.infinity
                for (k, s) in seeds.enumerated() {
                    let d = q - s, dd = (d * d).sum()
                    if dd < bestD { bestD = dd; best = k }
                }
                parts[best].append(p)
            }
            return parts.filter { !$0.isEmpty }
        }

        // 5. each stretch of room, split into cells about a piece's size
        var seen = [Bool](repeating: false, count: n)
        var stack: [Int] = []
        for start in 0..<n where open[start] && !seen[start] {
            var component: [Int] = []
            seen[start] = true
            stack.append(start)
            while let p = stack.popLast() {
                component.append(p)
                let x = p % w, y = p / w
                if x > 0, open[p - 1], !seen[p - 1] { seen[p - 1] = true; stack.append(p - 1) }
                if x < w - 1, open[p + 1], !seen[p + 1] { seen[p + 1] = true; stack.append(p + 1) }
                if y > 0, open[p - w], !seen[p - w] { seen[p - w] = true; stack.append(p - w) }
                if y < h - 1, open[p + w], !seen[p + w] { seen[p + w] = true; stack.append(p + w) }
            }
            component.sort()
            let cells = max(1, Int((Double(component.count) / target).rounded()))
            for cell in split(component, into: cells) { emit(cell, depth: 0) }
        }
        return out
    }
}

/// A two-pass chamfer distance transform (steps 1 and √2) on a raster, carrying with each
/// pixel the label of the source it is nearest.
enum Chamfer {
    static func run(_ d: inout [Float], w: Int, h: Int, carrying label: inout [Int32]) {
        let diagonal = Float(2).squareRoot()
        @inline(__always) func relax(_ i: Int, _ j: Int, _ step: Float) {
            let c = d[j] + step
            if c < d[i] { d[i] = c; label[i] = label[j] }
        }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if x > 0 { relax(i, i - 1, 1) }
                if y > 0 {
                    relax(i, i - w, 1)
                    if x > 0 { relax(i, i - w - 1, diagonal) }
                    if x < w - 1 { relax(i, i - w + 1, diagonal) }
                }
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                if x < w - 1 { relax(i, i + 1, 1) }
                if y < h - 1 {
                    relax(i, i + w, 1)
                    if x < w - 1 { relax(i, i + w + 1, diagonal) }
                    if x > 0 { relax(i, i + w - 1, diagonal) }
                }
            }
        }
    }
}
