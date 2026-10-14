import Foundation

/// A spot in the picture, in pixels of the working image (origin top-left, +y down).
public struct Point: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// The length of (dx, dy): plain arithmetic and a square root, as `norm` in `making_of_pets.py`,
/// so a comparison turns the same way there and here (a C library's `hypot` rounds differently).
func norm(_ dx: Double, _ dy: Double) -> Double {
    (dx * dx + dy * dy).squareRoot()
}

/// `x` as an index: truncated toward zero like Python's `int()`, and 0 for what no index could be.
func truncated(_ x: Double) -> Int {
    x.isFinite ? Int(max(-1e15, min(1e15, x.rounded(.towardZero)))) : 0
}

/// `numpy.interp(x, xp, fp)` for a nondecreasing `xp`, with `fp[j]` given by `value(j)`: the end
/// values outside `xp`, the exact value at a point of `xp` (the last of equal ones), the line
/// between neighbours otherwise.
func interp(_ x: Double, _ xp: [Double], _ value: (Int) -> Double) -> Double {
    guard let last = xp.indices.last else { return 0 }
    if x < xp[0] { return value(0) }
    if x > xp[last] { return value(last) }
    var lo = 0
    var hi = xp.count
    while hi - lo > 1 {                 // the last j with xp[j] <= x
        let mid = (lo + hi) / 2
        if xp[mid] <= x { lo = mid } else { hi = mid }
    }
    if lo == last || xp[lo] == x { return value(lo) }
    let slope = (value(lo + 1) - value(lo)) / (xp[lo + 1] - xp[lo])
    return slope * (x - xp[lo]) + value(lo)
}

/// A line through points, with the distance along it to each of them.
public struct Polyline: Sendable, Equatable {
    public let points: [Point]
    /// Distance along the line to each point, summed in order.
    public let cumulative: [Double]

    public init(_ points: [Point]) {
        self.points = points
        var total = 0.0
        var cumulative = points.isEmpty ? [] : [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            total += norm(b.x - a.x, b.y - a.y)
            cumulative.append(total)
        }
        self.cumulative = cumulative
    }

    public var length: Double { cumulative.last ?? 0 }

    /// The line drawn from its other end. Its distances are summed from there, not mirrored.
    public var reversed: Polyline { Polyline(points.reversed()) }

    /// Where `dist` along the line is.
    func point(at dist: Double) -> Point {
        Point(interp(dist, cumulative) { points[$0].x }, interp(dist, cumulative) { points[$0].y })
    }

    /// How many points are at or behind `dist` along the line (`numpy.searchsorted` to the right).
    func pointsBehind(_ dist: Double) -> Int {
        var lo = 0
        var hi = cumulative.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= dist { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// How far right the line runs over the 2 px after `dist` along it.
    func ahead(at dist: Double) -> Double {
        interp(min(dist + 2, length), cumulative) { points[$0].x } - interp(dist, cumulative) { points[$0].x }
    }
}
