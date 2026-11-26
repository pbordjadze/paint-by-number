import Foundation

/// Zen Mode's little personality (painting-company row 394), shown only in how it moves: no
/// words anywhere. Zen Mode was merged on October 5, 2026, which makes it a Libra, the sign of
/// the scales: its days sway around a balanced middle, the release's own motion, and never far.
///
/// `temperament(year:month:day:)` is a pure function of the calendar date (no network, no stored
/// state, the same all day on every device), so each day Zen has its own mood, and a new one at
/// midnight, for ever:
/// - **pace**: how long a fill shows before it flies on (`pause`) and how long the flight takes
///   (`flight`), together, so an unhurried day is unhurried in both;
/// - **closeness**: how much of the view the next area is framed to fill;
/// - **taste**: which area it picks, the nearest by default, a day that likes broad strokes
///   leaning toward larger ones a little farther off, a fussy one toward small ones.
/// Every value stays in a narrow band around the release's (`balanced`), slower more than
/// faster, so no day feels hurried. Zen's birthday is its slowest, roomiest, broadest day.
public struct ZenTemperament: Equatable, Sendable {
    /// Seconds a fill shows before Zen Mode flies on (a fill that finished a color waits for its
    /// shine instead, whatever the day).
    public var pause: Double
    /// Seconds the camera's flight to the next area takes.
    public var flight: Double
    /// The share of the view's shorter side the next area is framed to span, at most.
    public var closeness: Double
    /// Which area comes next: the one with the least distance² ÷ area^taste, so 0 is the
    /// nearest, above 0 leans toward larger areas, below toward smaller.
    public var taste: Double

    public init(pause: Double, flight: Double, closeness: Double, taste: Double) {
        self.pause = pause
        self.flight = flight
        self.closeness = closeness
        self.taste = taste
    }

    /// The release's motion, Libra's middle: what Zen Mode did before it had a personality.
    public static let balanced = ZenTemperament(pause: 0.35, flight: 0.55, closeness: 0.45, taste: 0)

    /// The bands each day's values keep to.
    public static let pauses = 0.30...0.50
    public static let flights = 0.50...0.70
    public static let closenesses = 0.40...0.50
    public static let tastes = -0.10...0.20

    /// Zen Mode's birthday (month, day).
    public static let birthday = (month: 10, day: 5)

    /// The temperament of a calendar date (Gregorian, the painter's own time zone).
    public static func of(year: Int, month: Int, day: Int) -> ZenTemperament {
        if month == birthday.month && day == birthday.day {
            return swayed(pace: 1, closeness: -1, taste: 1)
        }
        let n = dayOfYear(year: year, month: month, day: day)
        var random = SplitMix64(seed: UInt64(bitPattern: Int64(truncatingIfNeeded: year &* 400 &+ n)) ^ 0x5A45_4E4C_4942_5241)
        func unit() -> Double { Double(random.next() >> 11) / Double(1 << 53) * 2 - 1 }
        return swayed(pace: unit(), closeness: unit(), taste: unit())
    }

    /// Each sway in -1...1 moves its value from the balanced middle to a band's end.
    static func swayed(pace: Double, closeness: Double, taste: Double) -> ZenTemperament {
        func toward(_ middle: Double, _ band: ClosedRange<Double>, _ s: Double) -> Double {
            let s = min(max(s, -1), 1)
            return s >= 0 ? middle + (band.upperBound - middle) * s : middle + (middle - band.lowerBound) * s
        }
        let b = balanced
        return ZenTemperament(
            pause: toward(b.pause, pauses, pace),
            flight: toward(b.flight, flights, pace),
            closeness: toward(b.closeness, closenesses, closeness),
            taste: toward(b.taste, tastes, taste))
    }

    /// 0 for January 1. Out-of-range input is clamped, never trapped on.
    static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let m = min(max(month, 1), 12)
        let d = min(max(day, 1), lengths[m - 1])
        return lengths.prefix(m - 1).reduce(0, +) + d - 1
    }

    /// How far an area is from Zen's liking: its label's distance² from `point` over its area to
    /// the day's taste (the least wins).
    public func score(distanceSquared: Float, area: Float) -> Float {
        guard taste != 0 else { return distanceSquared }
        return distanceSquared / Float(pow(Double(max(area, 1)), taste))
    }
}
