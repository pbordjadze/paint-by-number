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

    /// Returns the number of merges; `classes` is rewritten per pixel.
    static func apply(
        classes: inout [UInt32],
        components cc: Components,
        texture: [Float],
        importance: [Float],
        palette: [SIMD3<Float>],
        metric: SIMD3<Float>,
        tolerance: Float
    ) -> Int {
        let n = cc.count
        guard n > 1, tolerance > 0 else { return 0 }
        let w = cc.labels.width, h = cc.labels.height
        let labels = cc.labels.storage
        var textureSum = [Double](repeating: 0, count: n)
        var importanceSum = [Double](repeating: 0, count: n)
        for i in 0..<labels.count {
            let r = Int(labels[i])
            textureSum[r] += Double(texture[i])
            importanceSum[r] += Double(importance[i])
        }
        var area = cc.area
        let cls = cc.classOf
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
            return r
        }
        func difference(_ a: UInt32, _ b: UInt32) -> Float {
            let d = (palette[Int(a)] - palette[Int(b)]) * metric
            return (d * d).sum().squareRoot()
        }

        var edges: [(a: Int32, b: Int32, key: Float)] = []
        let adjacency = RegionSimplifier.adjacencyLists(labels, width: w, height: h, count: n)
        for a in 0..<n {
            for link in adjacency[a] where Int(link.region) > a {
                edges.append((Int32(a), link.region, difference(cls[a], cls[Int(link.region)])))
            }
        }
        edges.sort { $0.key < $1.key || ($0.key == $1.key && ($0.a, $0.b) < ($1.a, $1.b)) }

        var merges = 0
        for e in edges {
            if e.key > tolerance { break }
            let a = find(Int(e.a)), b = find(Int(e.b))
            if a == b { continue }
            let total = Double(area[a] + area[b])
            let tex = Float((textureSum[a] + textureSum[b]) / total)
            let imp = Float((importanceSum[a] + importanceSum[b]) / total)
            let limit = tolerance * min(tex, 1) * min(max(2 * (1 - imp), 0), 1)
            if difference(cls[a], cls[b]) > limit { continue }
            let (root, other) = area[a] >= area[b] ? (a, b) : (b, a)
            parent[other] = root
            area[root] += area[other]
            textureSum[root] += textureSum[other]
            importanceSum[root] += importanceSum[other]
            merges += 1
        }
        guard merges > 0 else { return 0 }
        var regionClass = [UInt32](repeating: 0, count: n)
        for r in 0..<n { regionClass[r] = cls[find(r)] }
        let count = labels.count
        classes.withUnsafeMutableBufferPointer { out in
            labels.withUnsafeBufferPointer { lb in
                regionClass.withUnsafeBufferPointer { cb in
                    let o = UncheckedSendable(out.baseAddress!)
                    let l = UncheckedSendable(lb.baseAddress!)
                    let c = UncheckedSendable(cb.baseAddress!)
                    Parallel.forEachBand(count, minimumBandSize: 16_384) { range in
                        for i in range { o.value[i] = c.value[Int(l.value[i])] }
                    }
                }
            }
        }
        return merges
    }
}
