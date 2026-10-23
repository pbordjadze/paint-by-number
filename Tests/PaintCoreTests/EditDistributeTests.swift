import Testing
@testable import PaintCore

extension EditWork {
    /// `distribute` as it was before it tried the box round the cut-off pieces: the whole
    /// region's box, always. The reference the faster one must match pixel for pixel.
    mutating func distributeAsBefore(region r: Int, among pieces: [(id: Int, rings: [[LatticePoint]], pole: SIMD2<Float>)]) {
        let w = t.width, h = t.height
        var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min
        for piece in pieces {
            for ring in piece.rings {
                for p in ring {
                    x0 = min(x0, Int(p.x / Lattice.unit) - 1); x1 = max(x1, Int(p.x / Lattice.unit) + 1)
                    y0 = min(y0, Int(p.y / Lattice.unit) - 1); y1 = max(y1, Int(p.y / Lattice.unit) + 1)
                }
            }
        }
        x0 = max(x0, 0); y0 = max(y0, 0); x1 = min(x1, w - 1); y1 = min(y1, h - 1)
        guard x0 <= x1, y0 <= y1 else { return }
        let bw = x1 - x0 + 1, bh = y1 - y0 + 1
        var owner = [Int](repeating: -1, count: bw * bh)
        for (k, piece) in pieces.enumerated() {
            fillCentresAsBefore(of: piece.rings, x0: x0, y0: y0, width: bw, height: bh) { owner[$0] = k }
        }
        var unresolved: [Int] = []
        for y in 0..<bh {
            for x in 0..<bw where t.regionMap[x0 + x, y0 + y] == UInt32(r) && owner[y * bw + x] < 0 {
                unresolved.append(y * bw + x)
            }
        }
        while !unresolved.isEmpty {
            var assigned: [(Int, Int)] = []
            var rest: [Int] = []
            for i in unresolved {
                let x = i % bw, y = i / bw
                var taken = -1
                for (dx, dy) in [(-1, 0), (0, -1), (1, 0), (0, 1)] where taken < 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < bw, ny < bh, t.regionMap[x0 + nx, y0 + ny] == UInt32(r) else { continue }
                    taken = owner[ny * bw + nx]
                }
                if taken >= 0 { assigned.append((i, taken)) } else { rest.append(i) }
            }
            for (i, k) in assigned { owner[i] = k }
            if assigned.isEmpty { break }
            unresolved = rest
        }
        var counts = [Int](repeating: 0, count: pieces.count)
        for y in 0..<bh {
            for x in 0..<bw where t.regionMap[x0 + x, y0 + y] == UInt32(r) && owner[y * bw + x] >= 0 {
                counts[owner[y * bw + x]] += 1
            }
        }
        for (k, piece) in pieces.enumerated() where counts[k] == 0 {
            let px = min(max(Int(piece.pole.x.rounded(.down)), 0), w - 1), py = min(max(Int(piece.pole.y.rounded(.down)), 0), h - 1)
            if px >= x0, px <= x1, py >= y0, py <= y1 {
                owner[(py - y0) * bw + px - x0] = k
                t.regionMap[px, py] = UInt32(piece.id)
            }
        }
        for y in 0..<bh {
            for x in 0..<bw where t.regionMap[x0 + x, y0 + y] == UInt32(r) && owner[y * bw + x] >= 0 {
                t.regionMap[x0 + x, y0 + y] = UInt32(pieces[owner[y * bw + x]].id)
            }
        }
    }

    func fillCentresAsBefore(of rings: [[LatticePoint]], x0: Int, y0: Int, width: Int, height: Int, _ body: (Int) -> Void) {
        let unit = Double(Lattice.unit)
        var rows = [[(x: Double, up: Bool)]](repeating: [], count: height)
        for ring in rings where ring.count >= 3 {
            var j = ring.count - 1
            for i in 0..<ring.count {
                var a = ring[j], b = ring[i]
                j = i
                guard a.y != b.y else { continue }
                let up = b.y > a.y
                if !up { swap(&a, &b) }
                let first = max(Int(Lattice.floorDiv(a.y - Lattice.unit / 2 + Lattice.unit - 1, Lattice.unit)), y0)
                let last = min(Int(Lattice.floorDiv(b.y - Lattice.unit / 2 - 1, Lattice.unit)), y0 + height - 1)
                guard first <= last else { continue }
                for y in first...last {
                    let centre = Double(Int64(y) * Lattice.unit + Lattice.unit / 2)
                    let x = Double(a.x) + Double(b.x - a.x) * (centre - Double(a.y)) / Double(b.y - a.y)
                    rows[y - y0].append((x / unit, up))
                }
            }
        }
        for (row, crossings) in rows.enumerated() where crossings.count >= 2 {
            let sorted = crossings.sorted { $0.x < $1.x }
            var k = 0
            while k + 1 < sorted.count {
                let from = sorted[k].x, to = sorted[k + 1].x
                let lo = max(Int((from - 0.5).rounded(.up)), x0), hi = min(Int((to - 0.5).rounded(.up)) - 1, x0 + width - 1)
                if lo <= hi { for x in lo...hi { body(row * width + x - x0) } }
                k += 2
            }
        }
    }
}

/// A cut hands out the pixels of the region it cuts (`EditWork.distribute`) exactly as the whole
/// region's box did, though it walks only the box round the cut-off pieces where that gives the
/// same: a raster running past its outline (as edges along a painter's line do, by up to 2.5 px)
/// once let the small box reach pixels the whole box never walked.
@Suite("Edit distribute")
struct EditDistributeTests {
    typealias Piece = (id: Int, rings: [[LatticePoint]], pole: SIMD2<Float>)

    static func rect(_ x0: Int64, _ y0: Int64, _ x1: Int64, _ y1: Int64) -> [LatticePoint] {
        [LatticePoint(x0, y0), LatticePoint(x1, y0), LatticePoint(x1, y1), LatticePoint(x0, y1)]
    }

    /// Pixels of the region beyond the whole box stay the region's.
    @Test func pixelsBeyondTheWholeBoxStay() throws {
        var work = try EditWork(TemplateEditorTests.scene)
        let w = work.t.width, h = work.t.height
        for y in 0..<h { for x in 0..<w { work.t.regionMap[x, y] = 1 } }
        for y in 10..<30 { for x in 10..<40 { work.t.regionMap[x, y] = 0 } }
        work.t.regionMap[8, 20] = 0
        work.t.regionMap[9, 20] = 0
        let u = Lattice.unit
        let pieces: [Piece] = [
            (id: 0, rings: [Self.rect(25 * u, 10 * u, 40 * u, 30 * u)], pole: SIMD2(32, 20)),
            (id: 7, rings: [Self.rect(10 * u, 10 * u, 25 * u, 30 * u)], pole: SIMD2(17, 20)),
        ]
        var old = work
        old.distributeAsBefore(region: 0, among: pieces)
        work.distribute(region: 0, among: pieces)
        #expect(work.t.regionMap[8, 20] == 0)
        #expect(old.t.regionMap.storage == work.t.regionMap.storage)
    }

    /// Cuts of every kind (strips, slants, holes, at the canvas's edge) on rasters running up to
    /// 3 px past their outline give the same region map both ways.
    @Test func everyCutGivesWhatTheWholeBoxGave() throws {
        let scene = TemplateEditorTests.scene
        let u = Lattice.unit
        var rng = SplitMix64(seed: 99)
        func rnd(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        var differ: [Int] = []
        for trial in 0..<4000 {
            var work = try EditWork(scene)
            let w = work.t.width, h = work.t.height
            for y in 0..<h { for x in 0..<w { work.t.regionMap[x, y] = 1 } }
            let D = trial % 4
            // r's outline: a rectangle, sometimes at the canvas edge.
            let rx0 = Int64(rnd(3) == 0 ? 0 : 1 + rnd(30)), ry0 = Int64(rnd(3) == 0 ? 0 : 1 + rnd(30))
            let rx1 = min(Int64(w), rx0 + 12 + Int64(rnd(60))), ry1 = min(Int64(h), ry0 + 12 + Int64(rnd(50)))
            func j() -> Int64 { Int64(rnd(Int(u))) }
            let R0 = LatticePoint(rx0 * u + (rx0 == 0 ? 0 : j()), ry0 * u + (ry0 == 0 ? 0 : j()))
            let R1 = LatticePoint(rx1 * u - (rx1 == Int64(w) ? 0 : j()), ry1 * u - (ry1 == Int64(h) ? 0 : j()))
            var pieces: [Piece] = []
            switch rnd(5) {
            case 0:
                // Vertical or horizontal split; the smaller side is cut off.
                if rnd(2) == 0 {
                    let s = R0.x + (R1.x - R0.x) * Int64(2 + rnd(7)) / 10
                    let a = Self.rect(R0.x, R0.y, s, R1.y), b = Self.rect(s, R0.y, R1.x, R1.y)
                    let big = (s - R0.x) >= (R1.x - s)
                    pieces = [(0, [big ? a : b], .zero), (7, [big ? b : a], .zero)]
                } else {
                    let s = R0.y + (R1.y - R0.y) * Int64(2 + rnd(7)) / 10
                    let a = Self.rect(R0.x, R0.y, R1.x, s), b = Self.rect(R0.x, s, R1.x, R1.y)
                    let big = (s - R0.y) >= (R1.y - s)
                    pieces = [(0, [big ? a : b], .zero), (7, [big ? b : a], .zero)]
                }
            case 1:
                // A hole cut off, maybe touching an extreme side.
                let ix0 = R0.x + (rnd(3) == 0 ? 0 : (R1.x - R0.x) * Int64(1 + rnd(4)) / 10)
                let iy0 = R0.y + (rnd(3) == 0 ? 0 : (R1.y - R0.y) * Int64(1 + rnd(4)) / 10)
                let ix1 = ix0 + (R1.x - R0.x) * Int64(1 + rnd(4)) / 10, iy1 = iy0 + (R1.y - R0.y) * Int64(1 + rnd(4)) / 10
                if ix0 == R0.x || iy0 == R0.y {
                    // An L-shaped remainder is hard: use a strip instead.
                    let s = R0.x + (R1.x - R0.x) / 4
                    pieces = [(0, [Self.rect(s, R0.y, R1.x, R1.y)], .zero), (7, [Self.rect(R0.x, R0.y, s, R1.y)], .zero)]
                } else {
                    let inner = Self.rect(ix0, iy0, ix1, iy1)
                    pieces = [(0, [Self.rect(R0.x, R0.y, R1.x, R1.y), Array(inner.reversed())], .zero), (7, [inner], .zero)]
                }
            case 3:
                // A slanted cut, top to bottom.
                let a = R0.x + Int64(rnd(Int(R1.x - R0.x - 1)) + 1), b = R0.x + Int64(rnd(Int(R1.x - R0.x - 1)) + 1)
                let left = [R0, LatticePoint(a, R0.y), LatticePoint(b, R1.y), LatticePoint(R0.x, R1.y)]
                let right = [LatticePoint(a, R0.y), LatticePoint(R1.x, R0.y), R1, LatticePoint(b, R1.y)]
                let leftBig = (a + b - 2 * R0.x) >= (2 * R1.x - a - b)
                pieces = [(0, [leftBig ? left : right], .zero), (7, [leftBig ? right : left], .zero)]
            case 4:
                // A slanted quadrilateral cut out of the middle.
                let wx = R1.x - R0.x, wy = R1.y - R0.y
                func px(_ f: Int) -> Int64 { R0.x + wx * Int64(f) / 20 + Int64(rnd(Int(u))) }
                func py(_ f: Int) -> Int64 { R0.y + wy * Int64(f) / 20 + Int64(rnd(Int(u))) }
                let quad = [LatticePoint(px(2 + rnd(4)), py(2 + rnd(4))), LatticePoint(px(14 + rnd(4)), py(2 + rnd(4))),
                            LatticePoint(px(14 + rnd(4)), py(14 + rnd(4))), LatticePoint(px(2 + rnd(4)), py(14 + rnd(4)))]
                pieces = [(0, [Self.rect(R0.x, R0.y, R1.x, R1.y), Array(quad.reversed())], .zero), (7, [quad], .zero)]
            default:
                // Three strips.
                let s = R0.x + (R1.x - R0.x) / 5, t2 = R1.x - (R1.x - R0.x) / 5
                pieces = [(0, [Self.rect(s, R0.y, t2, R1.y)], .zero), (7, [Self.rect(R0.x, R0.y, s, R1.y)], .zero),
                          (8, [Self.rect(t2, R0.y, R1.x, R1.y)], .zero)]
            }
            for k in pieces.indices {
                let ring = pieces[k].rings[0]
                let cx = Float(ring.map(\.x).reduce(0, +)) / Float(ring.count) / Float(u)
                let cy = Float(ring.map(\.y).reduce(0, +)) / Float(ring.count) / Float(u)
                pieces[k].pole = SIMD2(cx, cy)
            }
            // The raster: centres inside the outline, then pixels up to D beyond it, then a few gone.
            let px0 = Int(R0.x / u), py0 = Int(R0.y / u), px1 = Int(R1.x / u), py1 = Int(R1.y / u)
            for y in max(py0 - D - 1, 0)...min(py1 + D + 1, h - 1) {
                for x in max(px0 - D - 1, 0)...min(px1 + D + 1, w - 1) {
                    let cx = Int64(x) * u + u / 2, cy = Int64(y) * u + u / 2
                    let inside = cx >= R0.x && cx < R1.x && cy >= R0.y && cy < R1.y
                    let dx = cx < R0.x ? Double(R0.x - cx) / Double(u) : cx >= R1.x ? Double(cx - R1.x) / Double(u) : 0
                    let dy = cy < R0.y ? Double(R0.y - cy) / Double(u) : cy >= R1.y ? Double(cy - R1.y) / Double(u) : 0
                    if inside {
                        if rnd(40) != 0 { work.t.regionMap[x, y] = 0 }
                    } else if max(dx, dy) <= Double(D) + 0.5, rnd(2) == 0 {
                        work.t.regionMap[x, y] = 0
                    }
                }
            }
            var old = work
            old.distributeAsBefore(region: 0, among: pieces)
            work.distribute(region: 0, among: pieces)
            if old.t.regionMap.storage != work.t.regionMap.storage { differ.append(trial) }
        }
        #expect(differ.isEmpty, "trials that differ: \(differ.prefix(10))")
    }
}
