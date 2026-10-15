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

/// How the template's lines are drawn: first in the ink step, as stair-stepped pixel outlines
/// (the way tracing starts), laid down along their paths (the pets walk some) while the grey
/// lifts; then in the template step the outlines relax into the template's smooth curves,
/// rippling out from where the crew works.
///
/// Every line has a `Stroke`: when it is drawn, its stair-stepped points paired one for one with
/// its smooth ones, and when the ripple reaches each. `lines(at:)` is a pure function of time, so
/// the show can seek (and hold still for Reduce Motion): the pen at time t is each line's prefix
/// at the ink value it has by then. `making_of_reveal.py` is the reference and equals this bit
/// for bit.
public struct StrokeSchedule: Sendable {
    public struct Stroke: Sendable, Equatable {
        /// The line's index in the template's strokes.
        public var index: Int
        /// Whether a pet walks along it, drawing it under its feet.
        public var walked: Bool
        public var start: Double
        public var duration: Double
        public var jagged: [Point]
        public var smooth: [Point]
        /// The distance along `smooth` to each of its points.
        public var cumulative: [Double]
        /// When the template step's ripple reaches each point.
        public var relax: [Double]

        public var length: Double { cumulative.last ?? 0 }
    }

    public let strokes: [Stroke]
    private let timing: ScheduleTiming
    private let crew: ShowSpec.Crew
    private let outlines: ShowSpec.Outlines
    private let petHeight: Double
    private let style: ScheduleStyle

    /// - Parameters:
    ///   - strokes: the template's lines, in pixels of the working image (the plan's inputs).
    ///   - traces: the lines the crew walks (`CrewPlan.traces`), drawn from their start to end by the pet.
    ///   - inkArrival: the ink step's `Arrival.field`, which a line the crew doesn't walk begins after.
    ///   - relaxArrival: the template step's, which a point relaxes after.
    ///   - streams: each such line's wait is a draw from the `.strokes` stream of its index.
    public init(
        strokes lines: [Polyline], traces: [Trace], inkArrival: Plane<Double>, relaxArrival: Plane<Double>,
        spec: ShowSpec, petHeight: Double, streams: ShowStreams, style: ScheduleStyle = .standard
    ) {
        let timing = ScheduleTiming(spec)
        let (width, height) = (inkArrival.width, inkArrival.height)
        precondition(relaxArrival.width == width && relaxArrival.height == height, "both fields cover the picture")
        let pace = timing.pace(style)
        let inkStart = timing.start(ScheduleTiming.inkStep)
        let inkEnd = inkStart + timing.step - style.inkEndMargin
        let walkedBy = Dictionary(traces.map { ($0.stroke, $0) }, uniquingKeysWith: { $1 })
        var strokes: [Stroke] = []
        for (n, line) in lines.enumerated() {
            let trace = walkedBy[n]
            let points = trace?.line.points ?? line.points
            let (jagged, smooth) = Self.staircase(points, grid: spec.outlines.grid, spacing: style.staircaseSpacing)
            let cumulative = Polyline(smooth).cumulative
            var start = trace?.start ?? 0
            var duration = trace?.duration ?? 0
            if trace == nil {
                let x = Self.pixel(points[0].x, below: width)
                let y = Self.pixel(points[0].y, below: height)
                var rng = streams.stream(.strokes, n)
                let wait = rng.uniform(0, style.strokeJitter)
                start = max(inkArrival[x, y] + wait, inkStart + style.strokeEarliest)
                duration = min(
                    max((cumulative.last ?? 0) / (style.strokeSpeed * Double(width) * pace), style.strokeMinTime),
                    style.strokeMaxTime / pace)
                if start + duration > inkEnd { start = max(inkStart, inkEnd - duration) }
            }
            let relax = smooth.map { relaxArrival[Self.pixel($0.x, below: width), Self.pixel($0.y, below: height)] }
            strokes.append(Stroke(
                index: n, walked: trace != nil, start: start, duration: duration, jagged: jagged, smooth: smooth,
                cumulative: cumulative, relax: relax))
        }
        self.strokes = strokes
        self.timing = timing
        crew = spec.crew
        outlines = spec.outlines
        self.petHeight = petHeight
        self.style = style
    }

    /// A line walked to the end can fall a rounding short of its length (about 4e-15 px): within this
    /// of it, it is whole.
    private static let wholeWithin = 1e-9

    /// The pixel a coordinate falls in, kept inside the picture.
    private static func pixel(_ v: Double, below n: Int) -> Int {
        min(max(truncated(v), 0), n - 1)
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

    // MARK: Lines at a time

    /// The lines at time `t` of the show: none before the ink step, then the ink step's, the
    /// template step's relaxing ones, and the finished smooth ones from the show's end on.
    public func lines(at t: Double) -> [InkLine] {
        if t < timing.start(ScheduleTiming.inkStep) { return [] }
        if t < timing.start(ScheduleTiming.templateStep) { return inked(at: t) }
        return relaxed(at: t < timing.end ? t : .infinity)
    }

    /// The ink step's lines: each line begun, drawn along its stair-stepped outline as far as it has
    /// got. A walked line is in full ink under the pet's feet; the others darken from grey to ink.
    public func inked(at t: Double) -> [InkLine] {
        var lines: [InkLine] = []
        for stroke in strokes where t >= stroke.start {
            var drawn: Double
            if stroke.walked {
                drawn = crew.traced(t - stroke.start, stroke.length, petHeight)
            } else {
                drawn = Self.ease((t - stroke.start) / stroke.duration) * stroke.length
            }
            if stroke.length - drawn < Self.wholeWithin { drawn = stroke.length }
            let count = Self.pointsBehind(stroke.cumulative, drawn)
            if count < 2 { continue }
            let u = min(max((t - stroke.start) / (stroke.duration + outlines.inkRamp), 0), 1)
            let value = stroke.walked ? 1.0 : style.inkGrey * (1 - u) + u
            lines.append(InkLine(stroke: stroke.index, points: Array(stroke.jagged[..<count]), value: value))
        }
        return lines
    }

    /// The template step's lines: every point on its way from its stair-stepped place to the
    /// smooth curve, as far as the ripple from the crew has reached it, in full ink. `t = .infinity`
    /// is the finished template, `-.infinity` the outlines before any of it.
    public func relaxed(at t: Double) -> [InkLine] {
        strokes.map { stroke in
            let points = (0..<stroke.jagged.count).map { i -> Point in
                let m = Self.ease((t - stroke.relax[i]) / outlines.relax)
                let (a, b) = (stroke.jagged[i], stroke.smooth[i])
                return Point(a.x * (1 - m) + b.x * m, a.y * (1 - m) + b.y * m)     // exactly each end at 0 and 1
            }
            return InkLine(stroke: stroke.index, points: points, value: 1)
        }
    }

    private static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// How many of the ascending `distances` are at or before `d` (`numpy.searchsorted` to the right).
    private static func pointsBehind(_ distances: [Double], _ d: Double) -> Int {
        var lo = 0
        var hi = distances.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if distances[mid] <= d { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
