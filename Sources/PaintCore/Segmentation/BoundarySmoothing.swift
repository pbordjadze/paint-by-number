import Foundation

/// Flowing region outlines: a color-guarded mode filter on boundary pixels.
///
/// Each boundary pixel takes the paint with the most (distance-weighted) votes in a small
/// disc around it, unless its own color argues strongly for its current paint. Iterated, this
/// behaves like curvature flow: jagged corners round off, notches fill and saw-tooth edges
/// straighten, while real color edges (large color penalty for switching) stay put.
enum BoundarySmoothing {

    /// - Parameters:
    ///   - radius: Vote disc radius in pixels.
    ///   - fidelity: Weight of the squared color distance (working OKLab) against votes;
    ///     votes are normalized to 1 over the disc.
    /// - Returns: Number of changed pixels over all passes.
    static func apply(
        classes: inout [UInt32],
        width w: Int, height h: Int,
        colors: [SIMD4<Float>],
        palette: [SIMD3<Float>],
        radius: Int,
        passes: Int,
        fidelity: Float
    ) -> Int {
        guard radius > 0, passes > 0, w > 2, h > 2 else { return 0 }
        var offsets: [(dx: Int, dy: Int, weight: Float)] = []
        var total: Float = 0
        let sigma2 = Float(radius * radius) * 0.5
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius && (dx != 0 || dy != 0) {
                let wgt = exp(-Float(dx * dx + dy * dy) / (2 * sigma2))
                offsets.append((dx, dy, wgt))
                total += wgt
            }
        }
        offsets = offsets.map { ($0.dx, $0.dy, $0.weight / total) }
        let steps = offsets.map { $0.dy * w + $0.dx }
        let packed = palette.map { SIMD4($0, 0) }
        let n = w * h
        var changedTotal = 0
        // A pixel whose disc saw no change in the previous pass faces the same vote as then,
        // so after the first pass only the surroundings of changed pixels are revisited.
        var near: [UInt8] = []
        let rowOf = RowDivider(width: w)
        for pass in 0..<passes {
            let moves: [[(Int, UInt32)]] = classes.withUnsafeBufferPointer { cb in
                colors.withUnsafeBufferPointer { colb in
                    packed.withUnsafeBufferPointer { pb in
                        offsets.withUnsafeBufferPointer { ob in
                            near.withUnsafeBufferPointer { nb in
                                let c = UncheckedSendable(cb.baseAddress!)
                                let col = UncheckedSendable(colb.baseAddress!)
                                let pal = UncheckedSendable(pb.baseAddress!)
                                let off = UncheckedSendable(ob.baseAddress!)
                                let nearby = UncheckedSendable(nb)
                                let m = ob.count
                                return Parallel.mapBands(h, minimumBandSize: 8) { rows -> [(Int, UInt32)] in
                                    var moved: [(Int, UInt32)] = []
                                    var boundary = [UInt8](repeating: 0, count: w)
                                    withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 16) { labelBuffer in
                                        withUnsafeTemporaryAllocation(of: Float.self, capacity: 16) { voteBuffer in
                                            boundary.withUnsafeMutableBufferPointer { bb in
                                                let labels = labelBuffer.baseAddress!, votes = voteBuffer.baseAddress!
                                                let b = bb.baseAddress!
                                                for y in rows {
                                                    let row = c.value + y * w
                                                    Self.boundaryMask(row, w: w, up: y > 0, down: y + 1 < h, into: b)
                                                    if pass > 0 {
                                                        let flags = nearby.value.baseAddress! + y * w
                                                        for x in 0..<w { b[x] &= flags[x] }
                                                    }
                                                    for x in 0..<w where b[x] != 0 {
                                                        let i = y * w + x
                                                        let own = row[x]
                                                        var k = 0
                                                        @inline(__always) func vote(_ l: UInt32, _ weight: Float) {
                                                            var slot = 0
                                                            while slot < k && labels[slot] != l { slot += 1 }
                                                            if slot == k {
                                                                if k == 16 { return }
                                                                labels[k] = l
                                                                votes[k] = 0
                                                                k += 1
                                                            }
                                                            votes[slot] += weight
                                                        }
                                                        if x >= radius && y >= radius && x < w - radius && y < h - radius {
                                                            for j in 0..<m { vote(c.value[i + steps[j]], off.value[j].weight) }
                                                        } else {
                                                            for j in 0..<m {
                                                                let xx = x + off.value[j].dx, yy = y + off.value[j].dy
                                                                if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                                                                vote(c.value[yy * w + xx], off.value[j].weight)
                                                            }
                                                        }
                                                        let color = col.value[i]
                                                        @inline(__always) func score(_ l: UInt32, _ v: Float) -> Float {
                                                            let e = color - pal.value[Int(l)]
                                                            return v - fidelity * (e * e).sum()
                                                        }
                                                        var ownVotes: Float = 0
                                                        for s in 0..<k where labels[s] == own { ownVotes = votes[s] }
                                                        var best = own
                                                        var bestScore = score(own, ownVotes) + 0.02
                                                        for s in 0..<k where labels[s] != own {
                                                            let sc = score(labels[s], votes[s])
                                                            if sc > bestScore { bestScore = sc; best = labels[s] }
                                                        }
                                                        if best != own { moved.append((i, best)) }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    return moved
                                }
                            }
                        }
                    }
                }
            }
            let count = moves.reduce(0) { $0 + $1.count }
            changedTotal += count
            if count == 0 { break }
            let last = pass + 1 == passes
            if !last {
                if near.isEmpty { near = [UInt8](repeating: 0, count: n) } else { near.withUnsafeMutableBufferPointer { $0.update(repeating: 0) } }
            }
            for band in moves {
                for (i, v) in band {
                    classes[i] = v
                    guard !last else { continue }
                    let y = rowOf.row(i), x = i - y * w
                    for yy in max(0, y - radius)...min(h - 1, y + radius) {
                        for xx in max(0, x - radius)...min(w - 1, x + radius) { near[yy * w + xx] = 1 }
                    }
                }
            }
        }
        return changedTotal
    }

    /// 1 where the pixel has a 4-neighbour of another paint.
    @inline(__always)
    private static func boundaryMask(_ row: UnsafePointer<UInt32>, w: Int, up: Bool, down: Bool, into b: UnsafeMutablePointer<UInt8>) {
        @inline(__always) func differs(_ u: UInt32, _ v: UInt32) -> UInt8 { u != v ? 1 : 0 }
        b[0] = differs(row[1], row[0])
        for x in 1..<(w - 1) { b[x] = differs(row[x - 1], row[x]) | differs(row[x + 1], row[x]) }
        b[w - 1] = differs(row[w - 2], row[w - 1])
        if up {
            let above = row - w
            for x in 0..<w { b[x] |= differs(above[x], row[x]) }
        }
        if down {
            let below = row + w
            for x in 0..<w { b[x] |= differs(below[x], row[x]) }
        }
    }
}
