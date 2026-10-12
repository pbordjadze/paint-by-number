import Foundation

/// The pixel-exact region map (`Template.regionMap`) of an edited template. The generator makes
/// the map first and the outlines after, smoothing them: a pixel may lie a little outside its
/// region's polygon. An edit keeps that relation: the pixels of a region it splits go to the
/// piece whose outline holds their centre (those the old outline left outside every piece to
/// the neighbouring pixels' piece), and the pixels of regions it merges go to the merged one.
/// Pixels of the regions an edit leaves alone are never touched.
extension EditWork {
    /// Hands the pixels of region `r` to `pieces` (`pieces[0]` is `r` itself).
    mutating func distribute(region r: Int, among pieces: [(id: Int, rings: [[LatticePoint]], pole: SIMD2<Float>)]) {
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
            fillCentres(of: piece.rings, x0: x0, y0: y0, width: bw, height: bh) { owner[$0] = k }
        }
        // Pixels of the region that no outline holds take the piece of a neighbouring pixel.
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
            // The next round's pixels see this round's assignments, not those of the same round.
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
        // A piece too narrow to hold a pixel centre of its region still owns the pixel its
        // number sits on, so that it can be tapped.
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

    /// Calls `body` with the index (in a `width` × `height` box at `x0`, `y0`) of each pixel
    /// whose centre lies inside `rings` (even-odd). The crossing of an outline with a row of
    /// centres is computed from its end points in a fixed order, so two pieces sharing an outline
    /// agree about the pixels on it.
    private func fillCentres(of rings: [[LatticePoint]], x0: Int, y0: Int, width: Int, height: Int, _ body: (Int) -> Void) {
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
                // Rows whose centre y satisfies a.y <= centre < b.y.
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
                // Centres at x + 0.5 in [from, to).
                let lo = max(Int((from - 0.5).rounded(.up)), x0), hi = min(Int((to - 0.5).rounded(.up)) - 1, x0 + width - 1)
                if lo <= hi { for x in lo...hi { body(row * width + x - x0) } }
                k += 2
            }
        }
    }

    /// Gives the pixels of `regions` to `keep`.
    mutating func relabelPixels(of regions: Set<Int>, to keep: Int) {
        let set = Set(regions.map { UInt32($0) })
        for i in t.regionMap.storage.indices where set.contains(t.regionMap.storage[i]) {
            t.regionMap.storage[i] = UInt32(keep)
        }
    }

    /// A stroke an edit made or moved, or lies in a region it cut, must touch the pixels of its region (`Template.validate`),
    /// as the strokes of a generated template do, whose regions are the pixels. A region cut from
    /// another can lie, in outline, over a few pixels the old outline had already left to a
    /// neighbour; where a stroke lies over such pixels, the nearest pixel whose centre the region's
    /// outline holds is the region's.
    mutating func claimPixelsUnderStrokes() {
        let w = t.width, h = t.height
        var outlines: [Int: [[LatticePoint]]] = [:]
        var counts: [UInt32: Int]?
        for i in strokes.indices where strokes[i].alive && (i >= originalStrokeCount || movedStrokes.contains(i) || regionTouched[strokes[i].region]) {
            let region = strokes[i].region
            for p in strokes[i].points {
                let px = Int(p.x.rounded(.down)), py = Int(p.y.rounded(.down))
                var touches = false
                for y in max(0, py - 1)...min(h - 1, py + 1) where !touches {
                    for x in max(0, px - 1)...min(w - 1, px + 1) where t.regionMap[x, y] == UInt32(region) {
                        touches = true
                        break
                    }
                }
                if touches { continue }
                if outlines[region] == nil { outlines[region] = polygons(of: region) }
                if counts == nil {
                    var c: [UInt32: Int] = [:]
                    for v in t.regionMap.storage { c[v, default: 0] += 1 }
                    counts = c
                }
                // Nearest first: the pixels around the point, by the distance of their centres.
                var candidates: [(d: Float, x: Int, y: Int)] = []
                for y in max(0, py - 1)...min(h - 1, py + 1) {
                    for x in max(0, px - 1)...min(w - 1, px + 1) {
                        let dx = Float(x) + 0.5 - p.x, dy = Float(y) + 0.5 - p.y
                        candidates.append((dx * dx + dy * dy, x, y))
                    }
                }
                candidates.sort { $0.d != $1.d ? $0.d < $1.d : ($0.y != $1.y ? $0.y < $1.y : $0.x < $1.x) }
                let centre = { (c: (d: Float, x: Int, y: Int)) in
                    LatticePoint(Int64(c.x) * Lattice.unit + Lattice.unit / 2, Int64(c.y) * Lattice.unit + Lattice.unit / 2)
                }
                // Not a pixel another stroke of its region leans on.
                func spare(_ c: (d: Float, x: Int, y: Int)) -> Bool {
                    let donor = t.regionMap[c.x, c.y]
                    guard (counts?[donor] ?? 0) > 1 else { return false }
                    for other in strokes where other.alive && other.region == Int(donor) {
                        for q in other.points {
                            let qx = Int(q.x.rounded(.down)), qy = Int(q.y.rounded(.down))
                            guard abs(qx - c.x) <= 1, abs(qy - c.y) <= 1 else { continue }
                            var others = false
                            for y in max(0, qy - 1)...min(h - 1, qy + 1) where !others {
                                for x in max(0, qx - 1)...min(w - 1, qx + 1) where (x != c.x || y != c.y) && t.regionMap[x, y] == donor {
                                    others = true
                                    break
                                }
                            }
                            if !others { return false }
                        }
                    }
                    return true
                }
                let pick = candidates.first { c in spare(c) && Lattice.contains(outlines[region]!, centre(c)) == .inside }
                    ?? candidates.first(where: spare)
                guard let pick else { continue }
                counts?[t.regionMap[pick.x, pick.y], default: 0] -= 1
                counts?[UInt32(region), default: 0] += 1
                t.regionMap[pick.x, pick.y] = UInt32(region)
            }
        }
    }
}
