import Foundation

/// Merges neighbouring regions of similar paint inside busy texture.
///
/// Texture (rushing water, stained stone, gravel, foliage) survives the size rules as a
/// camouflage of mid-sized patches in near-identical shades; an illustrator would paint it
/// as a few larger shapes. Neighbours are merged in order of paint similarity while their
/// difference stays below a tolerance that grows with the local texture density and
/// vanishes in important areas, so faces and clean contours are untouched. A union of
/// regions is never smaller or thinner than its parts, so all region guarantees hold.
enum TextureConsolidation {

    /// Updates `classes`, `regions` and `adjacency`.
    static func apply(
        classes: inout [UInt32],
        regions: inout RegionRuns,
        adjacency: inout RegionAdjacency,
        texture: [Float],
        importance: [Float],
        palette: [SIMD3<Float>],
        metric: SIMD3<Float>,
        tolerance: Float
    ) {
        let n = regions.count
        guard n > 1, tolerance > 0 else { return }
        let sums = regions.sums(texture, importance)
        var textureSum = sums.map(\.x)
        var importanceSum = sums.map(\.y)
        var area = regions.area
        let cls = regions.classOf
        var sets = DisjointSet(count: n)
        func difference(_ a: UInt32, _ b: UInt32) -> Float {
            let d = (palette[Int(a)] - palette[Int(b)]) * metric
            return (d * d).sum().squareRoot()
        }

        var edges: [(a: Int32, b: Int32, key: Float)] = []
        for key in adjacency.pairs {
            let (a, b) = RegionAdjacency.regions(of: key)
            let d = difference(cls[a], cls[b])
            if d <= tolerance { edges.append((Int32(a), Int32(b), d)) }
        }
        edges.sort { $0.key < $1.key || ($0.key == $1.key && ($0.a, $0.b) < ($1.a, $1.b)) }

        var merged = false
        for e in edges {
            let a = sets.find(Int(e.a)), b = sets.find(Int(e.b))
            if a == b { continue }
            let total = Double(area[a] + area[b])
            let tex = Float((textureSum[a] + textureSum[b]) / total)
            let imp = Float((importanceSum[a] + importanceSum[b]) / total)
            let limit = tolerance * min(tex, 1) * min(max(2 * (1 - imp), 0), 1)
            if difference(cls[a], cls[b]) > limit { continue }
            let (root, other) = area[a] >= area[b] ? (a, b) : (b, a)
            sets.parent[other] = root
            area[root] += area[other]
            textureSum[root] += textureSum[other]
            importanceSum[root] += importanceSum[other]
            merged = true
        }
        guard merged else { return }
        var roots = [Int32](repeating: 0, count: n)
        var paint = cls
        for r in 0..<n {
            let root = sets.find(r)
            roots[r] = Int32(root)
            paint[r] = cls[root]
        }
        regions.merge(roots: roots, paint: paint, adjacency: &adjacency, classes: &classes)
    }
}
