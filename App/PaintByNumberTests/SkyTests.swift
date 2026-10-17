import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// Settings › Sky: Moon by default; Follow the Sky turns from Sun to Moon by the painter's own
/// clock, in whatever time zone the device keeps; each sky's voice is the same at every launch and
/// stays in range.
@MainActor
struct SkyTests {
    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    /// `hour`:`minute` on October 17, 2026, in `calendar`'s time zone.
    private func date(_ hour: Int, _ minute: Int = 0, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: hour, minute: minute)))
    }

    @Test func sunFromSixToSevenAndMoonTheRest() throws {
        let local = try calendar("America/New_York")
        #expect(Sky.at(try date(5, 59, in: local), calendar: local) == .moon)
        #expect(Sky.at(try date(6, in: local), calendar: local) == .sun)
        #expect(Sky.at(try date(12, in: local), calendar: local) == .sun)
        #expect(Sky.at(try date(18, 59, in: local), calendar: local) == .sun)
        #expect(Sky.at(try date(19, in: local), calendar: local) == .moon)
        #expect(Sky.at(try date(0, in: local), calendar: local) == .moon)
    }

    /// One moment is day for one painter and night for another: the sky is the local hour's.
    @Test func theSkyIsThePaintersOwn() throws {
        let noonInLondon = try date(12, in: try calendar("Europe/London"))
        #expect(Sky.at(noonInLondon, calendar: try calendar("Europe/London")) == .sun)
        #expect(Sky.at(noonInLondon, calendar: try calendar("Asia/Tokyo")) == .moon)
        #expect(Sky.at(noonInLondon, calendar: try calendar("America/Los_Angeles")) == .moon)
        #expect(Sky.at(noonInLondon, calendar: try calendar("Asia/Tbilisi")) == .sun)
    }

    @Test func settingDefaultsToTheMoon() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SkySetting.stored(in: defaults) == .moon)
        #expect(SkySetting.current(at: try date(12, in: try calendar("Europe/Paris")), in: defaults) == .moon)
        let night = try date(23, in: try calendar("Europe/Paris"))
        let paris = try calendar("Europe/Paris")
        #expect(SkySetting.followTheSky.sky(at: night, calendar: paris) == .moon)
        #expect(SkySetting.sun.sky(at: night, calendar: paris) == .sun)
        #expect(SkySetting.moon.sky(at: try date(12, in: paris), calendar: paris) == .moon)
        defaults.set("sun", forKey: SettingsKey.sky)
        #expect(SkySetting.stored(in: defaults) == .sun)
        #expect(SkySetting.current(in: defaults) == .sun)
        defaults.set("eclipse", forKey: SettingsKey.sky)
        #expect(SkySetting.stored(in: defaults) == .moon)
        // The persisted key and values: renaming one would forget every painter's choice.
        #expect(SettingsKey.sky == "sky")
        #expect(SkySetting.allCases.map(\.rawValue) == ["moon", "sun", "followTheSky"])
        #expect(SkySetting.allCases.allSatisfy { !$0.name.isEmpty })
    }

    @Test func eachSkysVoiceIsTheSameEveryLaunchAndInRange() {
        let rate = 44_100.0
        for frequency in SoundPlayer.scale(of: .sun) {
            let note = ToneSynth.kalimba(frequency: frequency, sampleRate: rate)
            #expect(note == ToneSynth.kalimba(frequency: frequency, sampleRate: rate))
            #expect(note.allSatisfy { $0.isFinite && abs($0) < 1 })
            #expect(abs(note.last ?? 1) < 1e-3, "a note ends in silence, with no click")
        }
        for frequency in SoundPlayer.scale(of: .moon) {
            let note = ToneSynth.celesta(frequency: frequency, sampleRate: rate)
            #expect(note == ToneSynth.celesta(frequency: frequency, sampleRate: rate))
            #expect(note.allSatisfy { $0.isFinite && abs($0) < 1 })
            #expect(abs(note.last ?? 1) < 1e-3)
            let twinkle = ToneSynth.twinkle(frequency: 2 * frequency, sampleRate: rate)
            #expect(twinkle.allSatisfy { $0.isFinite && abs($0) < 1 })
        }
        // The bell rings longer than the kalimba.
        #expect(ToneSynth.celesta(frequency: 440, sampleRate: rate).count > ToneSynth.kalimba(frequency: 440, sampleRate: rate).count)
    }

    /// By Moon the fill's sparkles are stars: the sparkle with shorter arms on its diagonals.
    @Test func theMoonsStarIsTheSparkleWithDiagonalArms() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let sparkle = Sparkle.cgPath(in: rect), star = Sparkle.starPath(in: rect)
        let diagonal = CGPoint(x: 50 + 30 * 0.7071, y: 50 - 30 * 0.7071)
        #expect(!sparkle.contains(diagonal))
        #expect(star.contains(diagonal))
        #expect(star.boundingBoxOfPath.insetBy(dx: -0.5, dy: -0.5).contains(sparkle.boundingBoxOfPath))
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(star.boundingBoxOfPath))
    }
}
