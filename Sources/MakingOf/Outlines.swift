import PaintCore

/// A line to draw, as a polyline in pixels of the working image, in `value` of ink (0 paper,
/// 1 full ink). Where lines cross, the darker wins. `stroke` is the line's index in the template's.
public struct InkLine: Sendable, Equatable {
    public var stroke: Int
    public var points: [Point]
    public var value: Double

    public init(stroke: Int, points: [Point], value: Double) {
        self.stroke = stroke
        self.points = points
        self.value = value
    }
}

/// How the template's lines are drawn: first in the ink step, as stair-stepped pixel outlines (the
/// way tracing starts), burnt along their paths like a fuse (`FieldShow.burning`); then in the
/// template step the outlines relax into the template's smooth curves, as a second fuse reaches them.
///
/// Every line has a `Stroke`: when the fuse runs along it, its stair-stepped points paired one for
/// one with its smooth ones, and when the ripple reaches each. `staircase` and `relaxed` are pure, so
/// the show can seek (and hold still for Reduce Motion). `making_of_reveal.py` is the reference and
/// equals this bit for bit.
public enum StrokeSchedule {
    public struct Stroke: Sendable, Equatable {
        /// The line's index in the template's strokes.
        public var index: Int
        /// When the fuse first reaches the line, and how long it takes to run all of it.
        public var start: Double
        public var duration: Double
        public var jagged: [Point]
        public var smooth: [Point]
        /// When the template step's ripple reaches each point.
        public var relax: [Double]
    }

    /// A smooth polyline as the stair-stepped outline it was fitted to: resampled every `spacing`
    /// px, snapped to the `grid`, with a corner added wherever a snapped step moves in both
    /// directions (across, then down). Each jagged point is paired with the smooth one it came
    /// from (a corner with the smooth point of the step it ends), so one relaxes into the other.
    public static func staircase(_ points: [Point], grid: Double, spacing: Double = ScheduleStyle.standard.staircaseSpacing)
        -> (jagged: [Point], smooth: [Point])
    {
        precondition(points.count >= 2, "a line has two points at least")
        let line = Polyline(points)
        let total = line.length
        let n = max(2, truncated(total / spacing) + 1)
        let step = total / Double(n - 1)
        let smooth: [Point] = (0..<n).map { i in
            let at = i == n - 1 ? total : Double(i) * step
            return Point(interp(at, line.cumulative) { points[$0].x }, interp(at, line.cumulative) { points[$0].y })
        }
        let snapped = smooth.map { Point(($0.x / grid).rounded(.toNearestOrEven) * grid, ($0.y / grid).rounded(.toNearestOrEven) * grid) }
        var jagged = [snapped[0]]
        var paired = [smooth[0]]
        for i in 1..<n {
            let a = jagged[jagged.count - 1]
            let b = snapped[i]
            if a == b { continue }
            if a.x != b.x && a.y != b.y {
                jagged.append(Point(b.x, a.y))
                paired.append(smooth[i])
            }
            jagged.append(b)
            paired.append(smooth[i])
        }
        if jagged.count < 2 {
            jagged.append(snapped[n - 1])
            paired.append(smooth[n - 1])
        }
        return (jagged, paired)
    }

    /// The template step's lines: every point of `strokes` on its way from its stair-stepped place to
    /// the smooth curve, as far as the ripple has reached it (`Stroke.relax`), a point taking
    /// `relaxTime` seconds from then to being smooth, in full ink. `t = .infinity` is the finished
    /// template, `-.infinity` the outlines before any of it.
    static func relaxed(_ strokes: [Stroke], at t: Double, over relaxTime: Double) -> [InkLine] {
        strokes.map { stroke in
            let points = (0..<stroke.jagged.count).map { i -> Point in
                let m = ease((t - stroke.relax[i]) / relaxTime)
                let (a, b) = (stroke.jagged[i], stroke.smooth[i])
                return Point(a.x * (1 - m) + b.x * m, a.y * (1 - m) + b.y * m)     // exactly each end at 0 and 1
            }
            return InkLine(stroke: stroke.index, points: points, value: 1)
        }
    }
}
