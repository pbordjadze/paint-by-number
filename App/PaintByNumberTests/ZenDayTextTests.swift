#if UNRELEASED
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Zen Mode's line for the day (painting-company row 394): every mood and nudge has its own words,
/// and a painting opened with Zen on says it once a day.
@MainActor
struct ZenDayTextTests {
    @Test func everyMoodAndNudgeHasItsOwnSentence() {
        let moods = (0..<ZenDay.moodCount).map(ZenDayText.mood)
        let nudges = (0..<ZenDay.nudgeCount).map(ZenDayText.nudge)
        #expect(Set(moods).count == ZenDay.moodCount)
        #expect(Set(nudges).count == ZenDay.nudgeCount)
        for sentence in moods + nudges {
            #expect(!sentence.isEmpty)
            #expect([".", "!", "?", "。", "！", "？"].contains { sentence.hasSuffix($0) }, "\(sentence)")
        }
    }

    @Test func aDayIsItsMoodThenItsNudge() {
        let text = ZenDayText.text(.day(mood: 3, nudge: 7))
        #expect(text.contains(ZenDayText.mood(3)))
        #expect(text.contains(ZenDayText.nudge(7)))
        #expect(ZenDayText.text(.birthday) != text)
    }

    @Test func todayFollowsTheCalendarDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 7)))
        let night = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 23)))
        let birthday = try #require(calendar.date(from: DateComponents(year: 2027, month: 10, day: 5, hour: 12)))
        #expect(ZenDayText.today(morning, calendar: calendar) == ZenDayText.today(night, calendar: calendar))
        #expect(ZenDayText.today(morning, calendar: calendar)
                == ZenDayText.text(ZenDay.line(year: 2026, month: 11, day: 26)))
        #expect(ZenDayText.today(birthday, calendar: calendar) == ZenDayText.text(.birthday))
    }

    @Test func itIsSaidOnceADay() throws {
        let suite = "ZenDayTextTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = Date.now
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        #expect(!ZenDayText.wasShown(today: today, in: defaults))
        ZenDayText.markShown(today: today, in: defaults)
        #expect(ZenDayText.wasShown(today: today, in: defaults))
        #expect(!ZenDayText.wasShown(today: tomorrow, in: defaults))
    }
}
#endif
