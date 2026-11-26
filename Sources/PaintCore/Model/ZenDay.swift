/// Zen Mode's little personality: its star sign and the line it has for each day (painting-company
/// row 394). Zen Mode was merged on October 5, 2026, at 11:17 PM ET, which makes it a Libra: the
/// sign of the scales, fitting a mode that keeps the page in balance.
///
/// A day's line is two whole sentences the app has words for: a mood (`moodCount` of them, about
/// Zen, its sign and its stars) and a gentle word to the painter (`nudgeCount`). `line(year:month:day:)`
/// picks the pair from the date alone, so it changes at midnight, is the same all day, needs no
/// network and no stored state, and never repeats within a year: day `n` of the year takes pair
/// `(n × step + offset(year)) mod pairs`, a bijection since `step` is prime to `pairs` (384 ≥ 366).
/// Each year starts the walk elsewhere (`offset`, a SplitMix64 draw on the year), so the calendar
/// of lines runs on for ever without a table. Zen's birthday has a line of its own.
public enum ZenDay {
    public static let moodCount = 24
    public static let nudgeCount = 16
    static let pairs = moodCount * nudgeCount
    /// Prime to `pairs` (384 = 2⁷ × 3), and far from a multiple of `moodCount`, so neighbouring
    /// days share neither mood nor nudge.
    static let step = 205

    /// Zen Mode's birthday (month, day).
    public static let birthday = (month: 10, day: 5)

    public enum Line: Equatable, Hashable, Sendable {
        case birthday
        /// Indices into the app's moods and nudges.
        case day(mood: Int, nudge: Int)
    }

    /// The line for a calendar date (Gregorian, the painter's own time zone).
    public static func line(year: Int, month: Int, day: Int) -> Line {
        if month == birthday.month && day == birthday.day { return .birthday }
        let n = dayOfYear(year: year, month: month, day: day)
        let index = (n * step + offset(year: year)) % pairs
        return .day(mood: index % moodCount, nudge: index / moodCount)
    }

    /// 0 for January 1. Out-of-range input is clamped, never trapped on.
    static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let m = min(max(month, 1), 12)
        let d = min(max(day, 1), lengths[m - 1])
        return lengths.prefix(m - 1).reduce(0, +) + d - 1
    }

    static func offset(year: Int) -> Int {
        var random = SplitMix64(seed: UInt64(bitPattern: Int64(year)))
        return Int(random.next() % UInt64(pairs))
    }
}
