import PaintCore

/// When each of the template's numbers comes in, in the last step: just after the last pet to work
/// near it has been there, else late in the step, and never before its area has cleared to paper
/// nor before the outlines have relaxed at it. `making_of_reveal.py` is the reference and equals
/// this bit for bit.
public struct NumberSchedule: Sendable, Equatable {
    /// When each number starts to come in, in the order given.
    public let times: [Double]
    private let fade: Double

    /// - Parameters:
    ///   - numbers: the numbers' places and sizes (x, y, size), in pixels of the working image.
    ///   - clear: when each region of `regions` clears to paper (`Arrival.regionMinimum` of the
    ///     template step's field over them).
    ///   - regions: which of those regions each pixel is in.
    ///   - relaxArrival: the template step's `Arrival.field`.
    ///   - visits: the template step's visits (`CrewPlan.visits[5]`).
    public init(
        numbers: [(x: Double, y: Double, size: Double)], clear: [Double], regions: Plane<Int32>,
        relaxArrival: Plane<Double>, visits: [Visit], timing: ScheduleTiming, petHeight: Double,
        style: ScheduleStyle = .standard
    ) {
        let (width, height) = (relaxArrival.width, relaxArrival.height)
        precondition(regions.width == width && regions.height == height, "regions and field cover the same picture")
        let lateStart = timing.start(ScheduleTiming.templateStep) + style.numberLate * timing.step
        let latest = timing.end - style.numberEndMargin
        times = numbers.map { number in
            let x = min(max(truncated(number.x), 0), width - 1)
            let y = min(max(truncated(number.y), 0), height - 1)
            let clearAt = clear[Int(regions[x, y])]
            let near = visits.filter { norm($0.x - number.x, $0.y - number.y) < style.numberNear * petHeight }
            let at = near.isEmpty
                ? max(clearAt, lateStart)
                : near.reduce(Double.infinity) { min($0, $1.time) } + style.numberAfterPet
            let relaxedAt = relaxArrival[x, y] + style.numberAfterRelax
            return min(max(at, clearAt + style.numberAfterClear, relaxedAt), latest)
        }
        fade = style.numberFade
    }

    /// How much of number `i` is in at time `t` (0...1).
    public func alpha(_ i: Int, at t: Double) -> Double {
        let x = min(max((t - times[i]) / fade, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Which number owns each pixel, -1 for none: a disc about each number's place, as big as the
    /// number (at least `numberDiscMinimum` px), the later number winning where discs overlap.
    public static func discs(
        numbers: [(x: Double, y: Double, size: Double)], width: Int, height: Int, style: ScheduleStyle = .standard
    ) -> Plane<Int32> {
        var owner = Plane<Int32>(width: width, height: height, repeating: -1)
        for (i, number) in numbers.enumerated() {
            let r = max(number.size * style.numberDisc, style.numberDiscMinimum)
            let x0 = truncated(max(number.x - r, 0)), x1 = truncated(min(number.x + r + 1, Double(width)))
            let y0 = truncated(max(number.y - r, 0)), y1 = truncated(min(number.y + r + 1, Double(height)))
            if x0 >= x1 || y0 >= y1 { continue }
            for y in y0..<y1 {
                let dy = Double(y) - number.y
                for x in x0..<x1 {
                    let dx = Double(x) - number.x
                    if dx * dx + dy * dy <= r * r { owner[x, y] = Int32(i) }
                }
            }
        }
        return owner
    }
}
