import Foundation

/// A drawn line of layered line art, in pixel coordinates (pixel centres at integers).
struct DrawnLine {
    var points: [SIMD2<Float>]
    /// Edge strength per point, 0...1.
    var strength: [Float]
    /// `LineLayer` raw value per point (outline, detail or texture).
    var layer: [UInt8]
    var closed: Bool
    /// Open ends attached to nothing (candidates for closing).
    var free: (Bool, Bool)
    /// Wall-only seals: point index → junction position the line passed through.
    var links: [(index: Int, to: SIMD2<Float>)]
    /// An eye's contour or iris: kept whatever happens to the cells around it.
    var eye: Bool

    var length: Float { StrokeGraph.length(points, closed: closed) }

    /// Arc length at each point.
    var arcLength: [Float] {
        var a = [Float](repeating: 0, count: points.count)
        for i in points.indices.dropFirst() { a[i] = a[i - 1] + simdLength(points[i] - points[i - 1]) }
        return a
    }

    /// The pieces where `keep` is true. Neighbouring pieces share their cut point; links
    /// inside a piece stay with it.
    func pieces(keeping keep: [Bool], freeCuts: Bool) -> [DrawnLine] {
        if keep.allSatisfy({ $0 }) { return [self] }
        guard keep.contains(true) else { return [] }
        var pts = points, str = strength, lay = layer, flags = keep
        var shifted = links
        if closed {
            // Start at the first dropped point and run once around, back to it.
            let s = keep.firstIndex(of: false)!
            func rotate<T>(_ a: [T]) -> [T] { Array(a[s...]) + Array(a[..<s]) + [a[s]] }
            pts = rotate(points); str = rotate(strength); lay = rotate(layer); flags = rotate(keep)
            shifted = links.map { ((($0.index - s) % points.count + points.count) % points.count, $0.to) }
        }
        var out: [DrawnLine] = []
        let n = pts.count
        var i = 0
        while i < n {
            guard flags[i] else { i += 1; continue }
            var j = i
            while j + 1 < n && flags[j + 1] { j += 1 }
            let a = max(i - 1, 0), b = min(j + 1, n - 1)
            if b > a {
                let startFree = a == 0 && !closed ? free.0 : freeCuts
                let endFree = b == n - 1 && !closed ? free.1 : freeCuts
                out.append(DrawnLine(
                    points: Array(pts[a...b]), strength: Array(str[a...b]), layer: Array(lay[a...b]), closed: false,
                    free: (startFree, endFree),
                    links: shifted.filter { $0.index >= a && $0.index <= b }.map { ($0.index - a, $0.to) }, eye: eye))
            }
            i = j + 1
        }
        return out
    }
}

/// Lines → layers, eyes, walls and closed ends.
enum LineLayering {
    /// Hysteresis along a line per layer: a stretch above `lowFraction` × the layer's
    /// threshold that stays at or above the threshold for `seedLength` somewhere belongs to
    /// that layer (the strongest layer wins). Outlines connect down to 60 % of their threshold,
    /// the others to half. The seed must be sustained because a faint line meeting a strong
    /// one rises into it over its last few pixels (the detector's lines are soft): that
    /// junction does not make the faint line strong.
    static let lowFraction: [Float] = [0.6, 0.5, 0.5]
    static let seedLength: Float = 5
    /// Stretches of a layer shorter than this (canvas units) take their neighbours' layer.
    static let minimumRun: Float = 6
    /// Not drawn: below the texture layer's hysteresis.
    static let none: UInt8 = 255

    /// `LineLayer` raw value per point, or `none`. `arc`: arc length at each point; `closing`:
    /// the length of a closed line's last segment, back to its first point.
    static func classify(_ strength: [Float], arc: [Float], closed: Bool, closing: Float = 0, thresholds: [Float]) -> [UInt8] {
        let n = strength.count
        var layer = [UInt8](repeating: none, count: n)
        guard n > 0 else { return layer }
        let total = arc[n - 1] + (closed ? closing : 0)
        // Arc length from point a to point b going forward (wrapping on closed lines).
        func span(_ a: Int, _ b: Int) -> Float { b >= a ? arc[b] - arc[a] : total - arc[a] + arc[b] }
        for (l, high) in thresholds.enumerated().reversed() {
            let low = lowFraction[l] * high
            // Runs above `low`; on a closed line start after a point below it (if any).
            let start = closed ? ((strength.firstIndex { $0 < low }).map { ($0 + 1) % n } ?? 0) : 0
            var k = 0
            while k < n {
                let i = (start + k) % n
                guard strength[i] >= low else { k += 1; continue }
                var end = k
                var seeded = false
                var seedStart = -1
                while end < n && strength[(start + end) % n] >= low {
                    let j = (start + end) % n
                    if strength[j] >= high {
                        if seedStart < 0 { seedStart = j }
                        // A line shorter than the seed length counts whole.
                        if span(seedStart, j) >= min(seedLength, 0.8 * total) { seeded = true }
                    } else {
                        seedStart = -1
                    }
                    end += 1
                }
                if seeded { for m in k..<end { layer[(start + m) % n] = UInt8(l) } }
                k = end
            }
        }
        return layer
    }

    /// Runs of equal values shorter than `minimumRun` take the value of their longer
    /// neighbour (the stronger one on ties). Ends of open lines are runs too.
    static func clean(_ layer: inout [UInt8], arc: [Float], closed: Bool) {
        let n = layer.count
        guard n > 2 else { return }
        for _ in 0..<4 {
            var runs: [(start: Int, end: Int, value: UInt8)] = []
            var i = 0
            while i < n {
                var j = i
                while j + 1 < n && layer[j + 1] == layer[i] { j += 1 }
                runs.append((i, j, layer[i]))
                i = j + 1
            }
            if closed && runs.count > 1 && runs.first!.value == runs.last!.value {
                // The wrap-around run counts as one.
                let first = runs.removeFirst()
                runs[runs.count - 1].end = first.end + n
            }
            guard runs.count > 1 else { return }
            func runLength(_ r: (start: Int, end: Int, value: UInt8)) -> Float {
                if r.end < n { return arc[r.end] - arc[r.start] }
                return arc[n - 1] - arc[r.start] + arc[r.end - n]
            }
            var changed = false
            for (k, r) in runs.enumerated() where runLength(r) < minimumRun {
                let hasPrev = closed || k > 0, hasNext = closed || k < runs.count - 1
                guard hasPrev || hasNext else { continue }
                let prev = runs[(k - 1 + runs.count) % runs.count], next = runs[(k + 1) % runs.count]
                let value: UInt8
                if hasPrev && hasNext {
                    let lp = runLength(prev), ln = runLength(next)
                    value = lp != ln ? (lp > ln ? prev.value : next.value) : min(prev.value, next.value)
                } else {
                    value = hasPrev ? prev.value : next.value
                }
                guard value != r.value else { continue }
                for m in r.start...r.end { layer[m % n] = value }
                changed = true
            }
            if !changed { return }
        }
    }

    /// Strokes → drawn lines with layers; stretches below the texture layer are cut out.
    static func layered(_ strokes: [StrokeGraph.Stroke], thresholds: [Float]) -> [DrawnLine] {
        var out: [DrawnLine] = []
        for s in strokes {
            var line = DrawnLine(
                points: s.points, strength: s.strength, layer: [], closed: s.closed, free: s.free, links: s.links, eye: false)
            let arc = line.arcLength
            let closing = s.closed ? simdLength(s.points[0] - s.points[s.points.count - 1]) : 0
            var layer = classify(s.strength, arc: arc, closed: s.closed, closing: closing, thresholds: thresholds)
            line.layer = layer
            clean(&layer, arc: arc, closed: s.closed)
            line.layer = layer
            out += line.pieces(keeping: layer.map { $0 != none }, freeCuts: false)
        }
        return out
    }

    // MARK: - Eyes

    /// Eye polygons (normalized to the photo) in pixel coordinates, densified to about one
    /// point per pixel.
    static func eyePolygons(_ eyes: [[SIMD2<Float>]], width w: Int, height h: Int) -> [[SIMD2<Float>]] {
        eyes.compactMap { poly in
            let pts = poly.filter { $0.x.isFinite && $0.y.isFinite }.map {
                SIMD2(min(max($0.x, 0), 1) * Float(w) - 0.5, min(max($0.y, 0), 1) * Float(h) - 0.5)
            }
            guard pts.count >= 3 else { return nil }
            var dense: [SIMD2<Float>] = []
            for i in pts.indices {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                let steps = max(1, Int(simdLength(b - a).rounded(.up)))
                for k in 0..<steps { dense.append(a + (b - a) * (Float(k) / Float(steps))) }
            }
            return dense.count >= 3 ? dense : nil
        }
    }

    /// Pixels whose centres lie inside any of the polygons (even-odd per polygon).
    static func fill(_ polygons: [[SIMD2<Float>]], width w: Int, height h: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: w * h)
        for poly in polygons {
            let minY = max(0, Int(poly.map(\.y).min()!.rounded(.down))), maxY = min(h - 1, Int(poly.map(\.y).max()!.rounded(.up)))
            guard minY <= maxY else { continue }
            for y in minY...maxY {
                let fy = Float(y)
                var xs: [Float] = []
                var j = poly.count - 1
                for i in poly.indices {
                    let a = poly[i], b = poly[j]
                    if (a.y > fy) != (b.y > fy) { xs.append(a.x + (fy - a.y) * (b.x - a.x) / (b.y - a.y)) }
                    j = i
                }
                xs.sort()
                var k = 0
                while k + 1 < xs.count {
                    let x0 = max(0, Int(xs[k].rounded(.up))), x1 = min(w - 1, Int(xs[k + 1].rounded(.down)))
                    if x0 <= x1 { for x in x0...x1 { mask[y * w + x] = true } }
                    k += 2
                }
            }
        }
        return mask
    }

    /// An eye is its contour and iris: other lines inside an eye are cleared, and the eye's
    /// polygons join as closed outlines at full strength.
    static func addEyes(_ lines: [DrawnLine], eyes polygons: [[SIMD2<Float>]], width w: Int, height h: Int) -> [DrawnLine] {
        guard !polygons.isEmpty else { return lines }
        let inside = fill(polygons, width: w, height: h)
        // Erode by one pixel so lines meeting the contour keep their ends on it.
        let interior = Morphology.square(inside, width: w, height: h, any: false)
        var out: [DrawnLine] = []
        for line in lines {
            let keep = line.points.map { p -> Bool in
                let x = min(max(Int(p.x.rounded()), 0), w - 1), y = min(max(Int(p.y.rounded()), 0), h - 1)
                return !interior[y * w + x]
            }
            out += line.pieces(keeping: keep, freeCuts: false)
        }
        for poly in polygons {
            out.append(DrawnLine(
                points: poly, strength: [Float](repeating: 1, count: poly.count),
                layer: [UInt8](repeating: LineLayer.outline.rawValue, count: poly.count), closed: true,
                free: (false, false), links: [], eye: true))
        }
        return out
    }

    // MARK: - Walls

    /// Rasterized lines: per pixel the strongest layer drawn there (`none` if no line), its
    /// strength and the line that drew it.
    struct Walls {
        var layer: [UInt8]
        var strength: [UInt8]
        var owner: [Int32]
        let width: Int
        let height: Int

        func isWall(_ i: Int) -> Bool { layer[i] != LineLayering.none }
    }

    /// Visits the 8-connected pixels of the segment a → b (pixel coordinates).
    @inline(__always)
    static func segment(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ body: (Int, Int) -> Void) {
        let ax = a.x.rounded(), ay = a.y.rounded(), bx = b.x.rounded(), by = b.y.rounded()
        let n = max(Int(max(abs(bx - ax), abs(by - ay))), 1)
        for k in 0...n {
            let t = Float(k) / Float(n)
            body(Int((ax + (bx - ax) * t).rounded()), Int((ay + (by - ay) * t).rounded()))
        }
    }

    static func walls(_ lines: [DrawnLine], width w: Int, height h: Int) -> Walls {
        var walls = Walls(
            layer: [UInt8](repeating: none, count: w * h), strength: [UInt8](repeating: 0, count: w * h),
            owner: [Int32](repeating: -1, count: w * h), width: w, height: h)
        for (id, line) in lines.enumerated() {
            func plot(_ x: Int, _ y: Int, _ k: Int) {
                guard x >= 0 && y >= 0 && x < w && y < h else { return }
                let i = y * w + x
                let s = UInt8(min(max(line.strength[k], 0), 1) * 255 + 0.5)
                if line.layer[k] < walls.layer[i] || walls.layer[i] == none {
                    walls.layer[i] = line.layer[k]
                    walls.owner[i] = Int32(id)
                }
                walls.strength[i] = max(walls.strength[i], s)
            }
            let p = line.points
            if p.count == 1 { plot(Int(p[0].x.rounded()), Int(p[0].y.rounded()), 0) }
            for k in 0..<(p.count - 1) { segment(p[k], p[k + 1]) { plot($0, $1, k) } }
            if line.closed && p.count > 2 { segment(p[p.count - 1], p[0]) { plot($0, $1, p.count - 1) } }
            for l in line.links { segment(p[l.index], l.to) { plot($0, $1, l.index) } }
        }
        return walls
    }

    /// Extends free ends along their tangent (cone ±40°) to the nearest line, boundary of
    /// the color segmentation (slightly less preferred) or frame within `reach` (per layer):
    /// an open stroke then closes cells. Returns the number of ends extended.
    static func closeFreeEnds(
        _ lines: inout [DrawnLine], walls: Walls, colorEdge: [Bool], reach: [Float]
    ) -> Int {
        let w = walls.width, h = walls.height
        let cosCone = Float(cos(40 * Double.pi / 180))
        var done = 0
        for k in lines.indices where !lines[k].closed && (lines[k].free.0 || lines[k].free.1) {
            for end in 0..<2 {
                let line = lines[k]
                guard end == 0 ? line.free.0 : line.free.1 else { continue }
                let pts = end == 0 ? line.points : line.points.reversed()
                let t = StrokeGraph.endTangent(pts)
                guard t != .zero else { continue }
                let endIndex = end == 0 ? 0 : line.points.count - 1
                let r = reach[Int(min(line.layer[endIndex], 2))]
                guard r >= 1.5 else { continue }
                let p = pts[0]
                let arc = line.arcLength
                var best: (score: Float, q: SIMD2<Float>)?
                let ri = Int(r.rounded(.up))
                let px = Int(p.x.rounded()), py = Int(p.y.rounded())
                for y in max(0, py - ri)...min(h - 1, py + ri) {
                    for x in max(0, px - ri)...min(w - 1, px + ri) {
                        let i = y * w + x
                        let frame = x == 0 || y == 0 || x == w - 1 || y == h - 1
                        let owner = walls.owner[i]
                        guard owner >= 0 || colorEdge[i] || frame else { continue }
                        let q = SIMD2(Float(x), Float(y))
                        let v = q - p
                        let d = simdLength(v)
                        guard d >= 1.5, d <= r else { continue }
                        let c = simdDot(v, t) / d
                        guard c >= cosCone else { continue }
                        if owner == Int32(k) {
                            // A curl may close on itself, but not on its own end.
                            var nearest = 0
                            var bestD = Float.infinity
                            for (m, lp) in line.points.enumerated() {
                                let dd = simdLengthSquared(lp - q)
                                if dd < bestD { bestD = dd; nearest = m }
                            }
                            let along = end == 0 ? arc[nearest] : arc[arc.count - 1] - arc[nearest]
                            if along < 3 * r { continue }
                        }
                        let score = d * (1 + 2 * (1 - c)) * (owner < 0 && !frame ? 1.15 : 1)
                        if best == nil || score < best!.score { best = (score, q) }
                    }
                }
                guard let q = best?.q else { continue }
                let n = max(Int(simdLength(q - p).rounded(.up)), 1)
                let ext = (1...n).map { p + (q - p) * (Float($0) / Float(n)) }
                let s = line.strength[endIndex], l = line.layer[endIndex]
                if end == 0 {
                    lines[k].points = ext.reversed() + line.points
                    lines[k].strength = [Float](repeating: s, count: n) + line.strength
                    lines[k].layer = [UInt8](repeating: l, count: n) + line.layer
                    lines[k].links = line.links.map { ($0.index + n, $0.to) }
                    lines[k].free.0 = false
                } else {
                    lines[k].points += ext
                    lines[k].strength += [Float](repeating: s, count: n)
                    lines[k].layer += [UInt8](repeating: l, count: n)
                    lines[k].free.1 = false
                }
                done += 1
            }
        }
        return done
    }
}
