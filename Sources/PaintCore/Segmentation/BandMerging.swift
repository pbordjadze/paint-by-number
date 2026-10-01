import Foundation

/// Fuses the bands a smooth gradient is posterized into.
///
/// Nearest-paint labelling slices a smooth ramp (sky, bokeh, a shaded cheek) wherever its
/// colour crosses the midpoint between two paints, so a gradient comes out as nested rings
/// of near-identical shades: a target, not a picture. A ring boundary has a tell: the colour
/// barely changes across it (the pixel step is a small fraction of the paint difference),
/// whereas a real contour carries most of that difference within a pixel or two. Neighbours
/// separated by such weak boundaries are fused, closest paints first, as long as the paints
/// of everything fused stay within a tolerance. Paints too close to tell apart in paint fuse
/// anywhere; a wider tolerance applies to narrow bands (the rings of a bokeh highlight, the
/// contour lines of a shaded forehead) and shrinks with importance, so a wide sky band or the
/// modelling of the subject keeps its distinct tones. Fused regions are unions of regions, so
/// every size and thickness guarantee holds.
enum BandMerging {

    /// - Parameters:
    ///   - labelling: Paint of every pixel before region simplification, the reference the
    ///     palette refit treats as a region's own colour; absorbed bands are rewritten to
    ///     the fused paint so the refit centres it on the whole ramp rather than one band.
    ///   - metric: Per-axis scale turning working colours into true OKLab.
    ///   - tolerance: Largest OKLab spread of the paints fused into one region: `near` for
    ///     paints too close to tell apart (anywhere), `band` for narrow bands at importance 0
    ///     (falling to `near` at importance 1).
    ///   - bandWidth: Mean width (area over half the perimeter, canvas units) up to which a
    ///     region counts as a narrow band.
    ///   - contrast: A boundary is weak when the mean colour step across it is below this
    ///     fraction of the paint difference.
    /// - Returns: The number of merges; `classes`, `labelling`, `regions` and `adjacency`
    ///   are updated.
    static func apply(
        classes: inout [UInt32],
        labelling: inout [UInt32],
        regions: inout RegionRuns,
        adjacency: inout RegionAdjacency,
        colors: [SIMD4<Float>],
        importance: [Float],
        palette: [SIMD3<Float>],
        metric: SIMD3<Float>,
        tolerance: (near: Float, band: Float),
        bandWidth: Float,
        contrast: Float,
        cancel: CancellationCheck = .none
    ) throws -> Int {
        let n = regions.count
        let maxTolerance = max(tolerance.near, tolerance.band)
        guard n > 1, maxTolerance > 0, !adjacency.pairs.isEmpty else { return 0 }
        let cls = regions.classOf
        let paints = palette.map { $0 * metric }
        @inline(__always) func distance(_ a: UInt32, _ b: UInt32) -> Float {
            ColorScience.distance(paints[Int(a)], paints[Int(b)])
        }
        let importanceSum = importance.withUnsafeBufferPointer { ib in
            regions.accumulate(0.0) { sum, _, i in sum += Double(ib[i]) }
        }
        try cancel.throwIfCancelled()
        let steps = adjacency.boundarySteps(regions, colors: colors)
        try cancel.throwIfCancelled()

        struct Link {
            var region: Int32
            var length: Int32
        }
        // Weak boundaries between paints close enough to fuse, closest first; and every
        // region's borders, for the perimeter of what gets fused.
        var edges: [(a: Int32, b: Int32, key: Float)] = []
        var links = [[Link]](repeating: [], count: n)
        var perimeter = [Int](repeating: 0, count: n)
        for k in adjacency.pairs.indices {
            let a = Int(adjacency.pairs[k] >> 32), b = Int(adjacency.pairs[k] & 0xFFFF_FFFF)
            let length = adjacency.lengths[k]
            links[a].append(Link(region: Int32(b), length: length))
            links[b].append(Link(region: Int32(a), length: length))
            perimeter[a] += Int(length)
            perimeter[b] += Int(length)
            let d = distance(cls[a], cls[b])
            guard d <= maxTolerance else { continue }
            // Steps and the paint difference compared in the same (working) space.
            let difference = ColorScience.distance(palette[Int(cls[a])], palette[Int(cls[b])])
            guard steps[k] <= contrast * difference * Float(length) else { continue }
            edges.append((Int32(a), Int32(b), d))
        }
        guard !edges.isEmpty else { return 0 }
        edges.sort { $0.key < $1.key || ($0.key == $1.key && ($0.a, $0.b) < ($1.a, $1.b)) }

        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
            return r
        }
        var area = regions.area
        var weight = importanceSum
        var largest = Array(0..<n)
        // Distinct paints fused into each root and their spread (the largest pairwise
        // distance), so a chain of bands cannot creep across the whole ramp.
        var members = (0..<n).map { [cls[$0]] }
        var spread = [Float](repeating: 0, count: n)
        func width(_ r: Int) -> Float { perimeter[r] > 0 ? 2 * Float(area[r]) / Float(perimeter[r]) : .infinity }

        var merges = 0
        for e in edges {
            let a = find(Int(e.a)), b = find(Int(e.b))
            if a == b { continue }
            var limit = tolerance.near
            if min(width(a), width(b)) <= bandWidth {
                let imp = Float((weight[a] + weight[b]) / Double(area[a] + area[b]))
                limit = max(limit, lerp(tolerance.band, tolerance.near, imp))
            }
            var joined = max(spread[a], spread[b])
            for x in members[a] {
                for y in members[b] { joined = max(joined, distance(x, y)) }
            }
            if joined > limit { continue }
            let (root, other) = area[a] >= area[b] ? (a, b) : (b, a)
            var shared = 0
            for l in links[other] where find(Int(l.region)) == root { shared += Int(l.length) }
            parent[other] = root
            area[root] += area[other]
            weight[root] += weight[other]
            perimeter[root] += perimeter[other] - 2 * shared
            links[root].append(contentsOf: links[other])
            links[other] = []
            if regions.area[largest[other]] > regions.area[largest[root]] { largest[root] = largest[other] }
            for paint in members[other] where !members[root].contains(paint) { members[root].append(paint) }
            members[other] = []
            spread[root] = joined
            merges += 1
        }
        guard merges > 0 else { return 0 }
        try cancel.throwIfCancelled()

        var roots = [Int32](repeating: 0, count: n)
        var paint = cls
        for r in 0..<n {
            let root = find(r)
            roots[r] = Int32(root)
            paint[r] = cls[largest[root]]
        }
        rewriteLabelling(&labelling, regions: regions, roots: roots, paint: paint)
        regions.merge(roots: roots, paint: paint, adjacency: &adjacency, classes: &classes)
        return merges
    }

    /// Rewrites the reference labelling of absorbed regions' own pixels to the fused paint
    /// (pixels of other paints they had absorbed earlier stay foreign).
    private static func rewriteLabelling(_ labelling: inout [UInt32], regions: RegionRuns, roots: [Int32], paint: [UInt32]) {
        let w = regions.width, h = regions.height
        let cls = regions.classOf
        labelling.withUnsafeMutableBufferPointer { lb in
            regions.rowStart.withUnsafeBufferPointer { rsb in
                regions.start.withUnsafeBufferPointer { sb in
                    regions.end.withUnsafeBufferPointer { eb in
                        regions.label.withUnsafeBufferPointer { rlb in
                            let out = UncheckedSendable(lb.baseAddress!)
                            let rs = UncheckedSendable(rsb), s = UncheckedSendable(sb)
                            let e = UncheckedSendable(eb), rl = UncheckedSendable(rlb)
                            Parallel.forEachBand(h, minimumBandSize: 16) { rows in
                                for y in rows {
                                    let row = out.value + y * w
                                    for k in rs.value[y]..<rs.value[y + 1] {
                                        let r = Int(rl.value[k])
                                        let old = cls[r], new = paint[Int(roots[r])]
                                        guard new != old else { continue }
                                        for x in Int(s.value[k])..<Int(e.value[k]) where row[x] == old { row[x] = new }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
