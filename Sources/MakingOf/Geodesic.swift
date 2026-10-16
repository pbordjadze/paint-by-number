/// When a front reaches each cell of a plane: the fast-sweeping solution of the eikonal equation on
/// the eight-neighbor grid (`geodesic` in `making_of_fields.py`, bit for bit: only `+`, `min` and
/// the closed-form row pass, in the same order).
///
/// A front starts from seeds, each at its own moment (or from a whole field of starting moments),
/// and crosses a cell in `cost` seconds; a diagonal step costs the square root of 2 of the cell it
/// enters. A round is four sweeps, down, right, up and left. Each sweep takes the rows one after
/// the other, a row from the one before it (straight and diagonally), and then settles the row
/// itself in closed form: a running minimum of the times minus the cumulative cost, once each way.
/// Rows depend on each other, so a sweep runs on one core; the show runs different fields on
/// different cores.
enum Geodesic {
    /// A front's start: it reaches the cell (`x`, `y`) truncated to a cell, kept inside the plane,
    /// at `time`.
    struct Seed: Sendable, Equatable {
        var time: Double
        var x: Double
        var y: Double
    }

    private static let diagonal = 2.0.squareRoot()

    /// The time each cell is reached: from `seeds`, or from `start` (infinity where nothing starts) as
    /// well, over `sweeps` rounds. `cost` is positive.
    static func field(cost: Plane<Double>, seeds: [Seed] = [], start: Plane<Double>? = nil, sweeps: Int) -> Plane<Double> {
        let (w, h) = (cost.width, cost.height)
        var times = start?.data ?? [Double](repeating: .infinity, count: w * h)
        precondition(times.count == w * h, "a start for every cell")
        guard w > 0, h > 0 else { return Plane(width: w, height: h, data: times) }
        for seed in seeds {
            let i = min(max(truncated(seed.y), 0), h - 1) * w + min(max(truncated(seed.x), 0), w - 1)
            times[i] = min(times[i], seed.time)
        }
        // the sweeps along x take the planes turned a quarter, to run along rows
        var costAcross = [Double](repeating: 0, count: w * h)
        var across = [Double](repeating: 0, count: w * h)
        cost.data.withUnsafeBufferPointer { cost in
            costAcross.withUnsafeMutableBufferPointer { transpose(cost.baseAddress!, into: $0.baseAddress!, width: w, height: h) }
        }
        times.withUnsafeMutableBufferPointer { times in
            cost.data.withUnsafeBufferPointer { cost in
                costAcross.withUnsafeBufferPointer { costAcross in
                    across.withUnsafeMutableBufferPointer { across in
                        let t = times.baseAddress!, a = across.baseAddress!
                        for _ in 0..<sweeps {
                            sweep(t, cost: cost.baseAddress!, width: w, height: h, backwards: false)
                            transpose(t, into: a, width: w, height: h)
                            sweep(a, cost: costAcross.baseAddress!, width: h, height: w, backwards: false)
                            transpose(a, into: t, width: h, height: w)
                            sweep(t, cost: cost.baseAddress!, width: w, height: h, backwards: true)
                            transpose(t, into: a, width: w, height: h)
                            sweep(a, cost: costAcross.baseAddress!, width: h, height: w, backwards: true)
                            transpose(a, into: t, width: h, height: w)
                        }
                    }
                }
            }
        }
        return Plane(width: w, height: h, data: times)
    }

    /// One sweep down the rows of `times` (up if `backwards`), in place. The first row of the sweep
    /// has nothing before it and is left as it is.
    private static func sweep(
        _ times: UnsafeMutablePointer<Double>, cost: UnsafePointer<Double>, width w: Int, height h: Int, backwards: Bool
    ) {
        guard h > 1 else { return }
        for k in 1..<h {
            let y = backwards ? h - 1 - k : k
            let before = backwards ? y + 1 : y - 1
            settle(row: times + y * w, after: times + before * w, cost: cost + y * w, width: w)
        }
    }

    /// A row from the row before it, then from itself.
    private static func settle(
        row: UnsafeMutablePointer<Double>, after before: UnsafePointer<Double>, cost c: UnsafePointer<Double>, width w: Int
    ) {
        let d = diagonal
        // from the row before: straight, and diagonally from either side
        row[0] = min(row[0], w > 1 ? min(before[0] + c[0], before[1] + d * c[0]) : before[0] + c[0])
        if w > 2 {
            for x in 1..<(w - 1) {
                let reach = min(before[x] + c[x], min(before[x - 1] + d * c[x], before[x + 1] + d * c[x]))
                row[x] = min(row[x], reach)
            }
        }
        if w > 1 { row[w - 1] = min(row[w - 1], min(before[w - 1] + c[w - 1], before[w - 2] + d * c[w - 1])) }
        // from itself, rightward and then leftward: the closed form of crossing the cells in turn
        var run = 0.0
        var low = Double.infinity
        for x in 0..<w {
            run += c[x]
            low = min(low, row[x] - run)
            row[x] = run + low
        }
        var back = 0.0
        low = .infinity
        for x in stride(from: w - 1, through: 0, by: -1) {
            back += c[x]
            low = min(low, row[x] - back)
            row[x] = back + low
        }
    }

    /// `source`, `width` by `height`, turned into `target`, `height` by `width`, cell (x, y) to (y, x).
    static func transpose(
        _ source: UnsafePointer<Double>, into target: UnsafeMutablePointer<Double>, width w: Int, height h: Int
    ) {
        let tile = 32
        for y0 in stride(from: 0, to: h, by: tile) {
            for x0 in stride(from: 0, to: w, by: tile) {
                for y in y0..<min(y0 + tile, h) {
                    for x in x0..<min(x0 + tile, w) { target[x * h + y] = source[y * w + x] }
                }
            }
        }
    }
}
