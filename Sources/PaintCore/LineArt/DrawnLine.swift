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

    /// A closed outline at full strength, every point in the outline layer, with no free ends;
    /// `eye` marks an eye's contour or iris.
    static func closedOutline(_ polygon: [SIMD2<Float>], eye: Bool) -> DrawnLine {
        DrawnLine(
            points: polygon, strength: [Float](repeating: 1, count: polygon.count),
            layer: [UInt8](repeating: LineLayer.outline.rawValue, count: polygon.count), closed: true,
            free: (false, false), links: [], eye: eye)
    }

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
