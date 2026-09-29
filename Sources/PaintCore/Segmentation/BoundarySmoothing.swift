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
        let packed = palette.map { SIMD4($0, 0) }
        var changedTotal = 0
        for _ in 0..<passes {
            var next = classes
            let changed: [Int] = classes.withUnsafeBufferPointer { cb in
                next.withUnsafeMutableBufferPointer { nb in
                    colors.withUnsafeBufferPointer { colb in
                        packed.withUnsafeBufferPointer { pb in
                            offsets.withUnsafeBufferPointer { ob in
                                let c = UncheckedSendable(cb.baseAddress!)
                                let o = UncheckedSendable(nb.baseAddress!)
                                let col = UncheckedSendable(colb.baseAddress!)
                                let pal = UncheckedSendable(pb.baseAddress!)
                                let off = UncheckedSendable(ob.baseAddress!)
                                let m = ob.count
                                return Parallel.mapBands(h, minimumBandSize: 8) { rows -> Int in
                                    var count = 0
                                    var labels = [UInt32](repeating: 0, count: 16)
                                    var votes = [Float](repeating: 0, count: 16)
                                    for y in rows {
                                        for x in 0..<w {
                                            let i = y * w + x
                                            let own = c.value[i]
                                            let boundary = (x > 0 && c.value[i - 1] != own) || (x + 1 < w && c.value[i + 1] != own)
                                                || (y > 0 && c.value[i - w] != own) || (y + 1 < h && c.value[i + w] != own)
                                            if !boundary { continue }
                                            var k = 0
                                            for j in 0..<m {
                                                let xx = x + off.value[j].dx, yy = y + off.value[j].dy
                                                if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                                                let l = c.value[yy * w + xx]
                                                var slot = 0
                                                while slot < k && labels[slot] != l { slot += 1 }
                                                if slot == k {
                                                    if k == labels.count { continue }
                                                    labels[k] = l
                                                    votes[k] = 0
                                                    k += 1
                                                }
                                                votes[slot] += off.value[j].weight
                                            }
                                            let color = col.value[i]
                                            func score(_ l: UInt32, _ v: Float) -> Float {
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
                                            if best != own {
                                                o.value[i] = best
                                                count += 1
                                            }
                                        }
                                    }
                                    return count
                                }
                            }
                        }
                    }
                }
            }
            let sum = changed.reduce(0, +)
            classes = next
            changedTotal += sum
            if sum == 0 { break }
        }
        return changedTotal
    }
}
