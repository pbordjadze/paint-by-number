#if canImport(FoundationEssentials) && !canImport(Darwin)
import FoundationEssentials
#else
import Foundation
#endif

/// Framing a window's pieces by hand (painting-company row 366, Paul's interface of November 22,
/// 2026): the pieces are cut, outlined thinly and numbered from the start, and the painter leads
/// them a chunk at a time. A stroke that leaves the leaded part (the window's border, or pieces
/// already framed), goes round some bare pieces and comes back to the leaded part closes a frame;
/// the bare pieces it cut off are framed, ready to take their glass.
///
/// The stroke is a wall across the bare part of the window: whatever bare part it parts from the
/// largest is the chunk it took, and a piece is in the chunk when most of it is. A stroke that
/// doesn't start and end on the leaded part, or parts nothing off, frames nothing; but one across
/// the last bare piece of its part frames it, since there is nothing left to part it from.
public enum GlassFraming {
    /// The bare pieces `stroke` (canvas units) frames, in order; none when it closes no frame.
    /// `framed` says which pieces are leaded already (its count is the template's pieces);
    /// `reach` is how near the leaded part an end must be, and the wall's half width, in canvas
    /// units.
    public static func framed(by stroke: [SIMD2<Float>], in template: Template, framed: [Bool],
                              reach: Float) -> [Int] {
        let w = template.width, h = template.height
        let pieces = template.regions.count
        guard stroke.count >= 2, framed.count == pieces, w > 0, h > 0, reach > 0 else { return [] }
        let map = template.regionMap
        func leaded(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < w, y < h else { return true }
            let r = Int(map[x, y])
            return r >= pieces || framed[r]
        }
        guard let first = stroke.first, let last = stroke.last,
              touches(first, reach: reach, leaded: leaded), touches(last, reach: reach, leaded: leaded)
        else { return [] }

        // The wall: the stroke drawn `reach` wide, only where the window is bare.
        var wall = [Bool](repeating: false, count: w * h)
        let r = max(1, Int(reach.rounded(.up)))
        for (a, b) in zip(stroke, stroke.dropFirst()) {
            let d = b - a
            let steps = max(1, Int(((d * d).sum().squareRoot() / max(1, reach * 0.5)).rounded(.up)))
            for k in 0...steps {
                let p = a + d * (Float(k) / Float(steps))
                let cx = Int(p.x.rounded(.down)), cy = Int(p.y.rounded(.down))
                // A finger past the canvas's edge walls nothing there.
                let y0 = max(0, cy - r), y1 = min(h - 1, cy + r), x0 = max(0, cx - r), x1 = min(w - 1, cx + r)
                guard y0 <= y1, x0 <= x1 else { continue }
                for y in y0...y1 {
                    for x in x0...x1 {
                        let dx = Float(x) + 0.5 - p.x, dy = Float(y) + 0.5 - p.y
                        if dx * dx + dy * dy <= reach * reach { wall[y * w + x] = true }
                    }
                }
            }
        }

        // The bare part's pieces of land, 4-connected: before the wall stands (`blob`) and after
        // (`land`).
        func components(walled: Bool) -> (labels: [Int32], sizes: [Int]) {
            var labels = [Int32](repeating: -1, count: w * h)
            var sizes: [Int] = []
            var stack: [Int] = []
            func open(_ i: Int) -> Bool { labels[i] < 0 && !(walled && wall[i]) && !leaded(i % w, i / w) }
            for start in 0..<(w * h) where open(start) {
                let id = Int32(sizes.count)
                var size = 0
                labels[start] = id
                stack.append(start)
                while let i = stack.popLast() {
                    size += 1
                    let x = i % w, y = i / w
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && ny >= 0 && nx < w && ny < h {
                        let j = ny * w + nx
                        if open(j) {
                            labels[j] = id
                            stack.append(j)
                        }
                    }
                }
                sizes.append(size)
            }
            return (labels, sizes)
        }
        let (land, sizes) = components(walled: true)
        let blob = components(walled: false).labels
        let rest = sizes.count >= 2 ? sizes.indices.max(by: { sizes[$0] < sizes[$1] }) : nil

        // Each bare piece: how much of it is in the chunk, against how much of it isn't; whether
        // the wall crosses it; and the bare blob it lies in, with how many pieces that blob holds.
        var inside = [Int](repeating: 0, count: pieces)
        var outside = [Int](repeating: 0, count: pieces)
        var crossed = [Bool](repeating: false, count: pieces)
        var blobOf = [Int32](repeating: -1, count: pieces)
        var blobPieces: [Int32: Set<Int>] = [:]
        for y in 0..<h {
            for x in 0..<w {
                let p = Int(map[x, y])
                guard p < pieces, !framed[p] else { continue }
                let i = y * w + x
                blobOf[p] = blob[i]
                blobPieces[blob[i], default: []].insert(p)
                if wall[i] { crossed[p] = true }
                guard let rest else { continue }
                if land[i] >= 0 && Int(land[i]) != rest { inside[p] += 1 } else if land[i] == Int32(rest) { outside[p] += 1 }
            }
        }
        // The last bare piece of a blob has nothing to be parted from: a stroke from the lead
        // across it frames it, or no window could be finished.
        return (0..<pieces).filter { p in
            guard !framed[p] else { return false }
            if inside[p] > 0 && inside[p] >= outside[p] { return true }
            return crossed[p] && blobPieces[blobOf[p]]?.count == 1
        }
    }

    /// Whether `p` lies within `reach` of the leaded part (the border counts).
    private static func touches(_ p: SIMD2<Float>, reach: Float, leaded: (Int, Int) -> Bool) -> Bool {
        let r = Int(reach.rounded(.up))
        let cx = Int(p.x.rounded(.down)), cy = Int(p.y.rounded(.down))
        for y in (cy - r)...(cy + r) {
            for x in (cx - r)...(cx + r) {
                let dx = Float(x) + 0.5 - p.x, dy = Float(y) + 0.5 - p.y
                if dx * dx + dy * dy <= reach * reach && leaded(x, y) { return true }
            }
        }
        return false
    }
}
