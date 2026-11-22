import Foundation

/// Framing a window's pieces by hand (painting-company row 366, Paul's interface of November 22,
/// 2026): the pieces are cut, outlined thinly and numbered from the start, and the painter leads
/// them a chunk at a time. A stroke that leaves the leaded part (the window's border, or pieces
/// already framed), goes round some bare pieces and comes back to the leaded part closes a frame;
/// the bare pieces it cut off are framed, ready to take their glass.
///
/// The stroke is a wall across the bare part of the window: whatever bare part it parts from the
/// largest is the chunk it took, and a piece is in the chunk when most of it is. A stroke that
/// doesn't start and end on the leaded part, or parts nothing off, frames nothing.
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
                for y in max(0, cy - r)...min(h - 1, cy + r) where y >= 0 {
                    for x in max(0, cx - r)...min(w - 1, cx + r) where x >= 0 {
                        let dx = Float(x) + 0.5 - p.x, dy = Float(y) + 0.5 - p.y
                        if dx * dx + dy * dy <= reach * reach { wall[y * w + x] = true }
                    }
                }
            }
        }

        // The bare part's pieces of land once the wall stands, 4-connected.
        var land = [Int32](repeating: -1, count: w * h)
        var sizes: [Int] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where land[start] < 0 && !wall[start] && !leaded(start % w, start / w) {
            let id = Int32(sizes.count)
            var size = 0
            land[start] = id
            stack.append(start)
            while let i = stack.popLast() {
                size += 1
                let x = i % w, y = i / w
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < w && ny < h {
                    let j = ny * w + nx
                    if land[j] < 0 && !wall[j] && !leaded(nx, ny) {
                        land[j] = id
                        stack.append(j)
                    }
                }
            }
            sizes.append(size)
        }
        guard sizes.count >= 2, let rest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) else { return [] }

        // Each bare piece: how much of it is in the chunk, against how much of it isn't.
        var inside = [Int](repeating: 0, count: pieces)
        var outside = [Int](repeating: 0, count: pieces)
        for y in 0..<h {
            for x in 0..<w {
                let p = Int(map[x, y])
                guard p < pieces, !framed[p] else { continue }
                let i = y * w + x
                if land[i] >= 0 && Int(land[i]) != rest { inside[p] += 1 } else if land[i] == Int32(rest) { outside[p] += 1 }
            }
        }
        return (0..<pieces).filter { !framed[$0] && inside[$0] > 0 && inside[$0] >= outside[$0] }
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
