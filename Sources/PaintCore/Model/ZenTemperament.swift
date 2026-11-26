import Foundation

/// Zen Mode's daily temperament (painting-company row 394), shown only in how it moves, never in
/// words, and different enough from day to day to be felt.
///
/// `of(year:month:day:)` is a pure function of the calendar date (no network, no stored state,
/// the same all day on every device), so each day Zen has its own mood, and a new one at
/// midnight, for ever. A day's **mood** runs from calm (+1) to lively (-1), pushed toward its
/// ends so most days lean clearly one way:
/// - a calm day lingers after a fill (`pause` up to 0.9 s), glides slowly (`flight` up to 1.1 s)
///   and likes broad areas (`taste` up to 0.45: a large area well farther off over a small one
///   beside it);
/// - a lively day moves on quickly (0.25 s, a 0.45 s flight), likes small areas (`taste` down to
///   -0.2) and wanders (`wander` up to 1): it would rather fly a good way across the painting
///   than to the area beside the last;
/// - and, apart from the mood, how close it frames the next area (`closeness`, 0.35 to 0.55 of
///   the view).
/// A mood of 0 is the release's motion (`balanced`). October 5 is the calmest day of all.
public struct ZenTemperament: Equatable, Sendable {
    /// Seconds a fill shows before Zen Mode flies on (a fill that finished a color waits for its
    /// shine instead, whatever the day).
    public var pause: Double
    /// Seconds the camera's flight to the next area takes.
    public var flight: Double
    /// The share of the view's shorter side the next area is framed to span, at most.
    public var closeness: Double
    /// Leaning toward larger areas (above 0) or smaller (below), as `score` weighs them.
    public var taste: Double
    /// How far it likes to go: 0 the nearest area, 1 a distance of `wanderReach` of the
    /// painting's diagonal.
    public var wander: Double

    public init(pause: Double, flight: Double, closeness: Double, taste: Double, wander: Double = 0) {
        self.pause = pause
        self.flight = flight
        self.closeness = closeness
        self.taste = taste
        self.wander = wander
    }

    /// The release's motion: what Zen Mode did before it had a temperament.
    public static let balanced = ZenTemperament(pause: 0.35, flight: 0.55, closeness: 0.45, taste: 0)

    /// Each value's band: (lively end, calm end) for the mood's, (low, high) for closeness.
    public static let pauses = 0.25...0.90
    public static let flights = 0.45...1.10
    public static let closenesses = 0.35...0.55
    public static let tastes = -0.20...0.45
    /// The share of the painting's diagonal the liveliest day likes to fly.
    public static let wanderReach: Float = 0.35

    /// The calmest day (month, day).
    public static let calmestDay = (month: 10, day: 5)

    /// The temperament of a calendar date (Gregorian, the painter's own time zone).
    public static func of(year: Int, month: Int, day: Int) -> ZenTemperament {
        if month == calmestDay.month && day == calmestDay.day { return mood(1, closeness: -1) }
        let n = dayOfYear(year: year, month: month, day: day)
        var random = SplitMix64(seed: UInt64(bitPattern: Int64(truncatingIfNeeded: year &* 400 &+ n)) ^ 0x5A45_4E4C_4942_5241)
        func unit() -> Double { Double(random.next() >> 11) / Double(1 << 53) * 2 - 1 }
        let u = unit()
        // Toward the ends: a square root keeps few days near the middle.
        let mood = (u < 0 ? -1 : 1) * abs(u).squareRoot()
        return Self.mood(mood, closeness: unit())
    }

    /// A day of mood `m` (calm +1 … lively -1) and closeness sway `c` (-1 … 1).
    static func mood(_ m: Double, closeness c: Double) -> ZenTemperament {
        func toward(_ middle: Double, _ band: ClosedRange<Double>, _ s: Double) -> Double {
            let s = min(max(s, -1), 1)
            return s >= 0 ? middle + (band.upperBound - middle) * s : middle + (middle - band.lowerBound) * s
        }
        let b = balanced
        let m = min(max(m, -1), 1)
        return ZenTemperament(
            pause: toward(b.pause, pauses, m),
            flight: toward(b.flight, flights, m),
            closeness: toward(b.closeness, closenesses, c),
            taste: toward(b.taste, tastes, m),
            wander: max(0, -m))
    }

    /// 0 for January 1. Out-of-range input is clamped, never trapped on.
    static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let m = min(max(month, 1), 12)
        let d = min(max(day, 1), lengths[m - 1])
        return lengths.prefix(m - 1).reduce(0, +) + d - 1
    }

    /// How far an area is from Zen's liking (the least wins): its label's distance from where Zen
    /// is, off from the distance the day likes (`wander` × `wanderReach` × `diagonal`), squared,
    /// over its area to the day's taste. At the balanced middle, the distance² alone.
    public func score(distanceSquared: Float, area: Float, diagonal: Float) -> Float {
        var d2 = distanceSquared
        if wander > 0 {
            let liked = Float(wander) * Self.wanderReach * max(diagonal, 0)
            let off = distanceSquared.squareRoot() - liked
            d2 = off * off
        }
        guard taste != 0 else { return d2 }
        return d2 / Float(pow(Double(max(area, 1)), taste))
    }
}
