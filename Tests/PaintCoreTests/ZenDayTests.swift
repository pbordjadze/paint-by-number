import Testing
@testable import PaintCore

@Suite("Zen Mode's day")
struct ZenDayTests {
    private static let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    private func everyDay(of year: Int) -> [(month: Int, day: Int)] {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        return (1...12).flatMap { month in
            (1...(month == 2 && leap ? 29 : Self.lengths[month - 1])).map { (month, $0) }
        }
    }

    @Test(arguments: [2026, 2027, 2028, 2100, 2400])
    func noLineRepeatsWithinAYear(year: Int) {
        let lines = everyDay(of: year).map { ZenDay.line(year: year, month: $0.month, day: $0.day) }
        #expect(lines.count == (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 366 : 365))
        #expect(Set(lines).count == lines.count)
        #expect(lines.filter { $0 == .birthday }.count == 1)
    }

    @Test func everyMoodAndNudgeIsInRangeAndUsed() {
        var moods = Set<Int>(), nudges = Set<Int>()
        for (month, day) in everyDay(of: 2027) {
            guard case let .day(mood, nudge) = ZenDay.line(year: 2027, month: month, day: day) else { continue }
            #expect((0..<ZenDay.moodCount).contains(mood))
            #expect((0..<ZenDay.nudgeCount).contains(nudge))
            moods.insert(mood); nudges.insert(nudge)
        }
        #expect(moods.count == ZenDay.moodCount)
        #expect(nudges.count == ZenDay.nudgeCount)
    }

    @Test func neighbouringDaysShareNeitherHalf() {
        let days = everyDay(of: 2027).map { ZenDay.line(year: 2027, month: $0.month, day: $0.day) }
        for (a, b) in zip(days, days.dropFirst()) {
            guard case let .day(m1, n1) = a, case let .day(m2, n2) = b else { continue }
            #expect(m1 != m2)
            #expect(n1 != n2)
        }
    }

    @Test func birthdayAndPinnedDays() {
        #expect(ZenDay.line(year: 2026, month: 10, day: 5) == .birthday)
        #expect(ZenDay.line(year: 2031, month: 10, day: 5) == .birthday)
        // The same date gives the same line on any device; another year, another line.
        #expect(ZenDay.line(year: 2026, month: 11, day: 26) == ZenDay.line(year: 2026, month: 11, day: 26))
        #expect(ZenDay.line(year: 2026, month: 11, day: 26) != ZenDay.line(year: 2027, month: 11, day: 26))
    }

    @Test func oddDatesNeverTrap() {
        for (y, m, d) in [(2026, 0, 0), (2026, 13, 40), (2027, 2, 29), (-5, 6, 1), (Int.max, 12, 31), (Int.min, 1, 1)] {
            if case let .day(mood, nudge) = ZenDay.line(year: y, month: m, day: d) {
                #expect((0..<ZenDay.moodCount).contains(mood) && (0..<ZenDay.nudgeCount).contains(nudge))
            }
        }
    }
}
