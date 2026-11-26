#if UNRELEASED
import Foundation
import PaintCore

/// The words of Zen Mode's day (`ZenDay`, its doc comment: a Libra, a mood and a nudge for each
/// date). Played lovingly, never preachy: a mood is about Zen and its stars, a nudge leaves the
/// painter free ("hope built in, never forced"), and any mood reads well beside any nudge.
enum ZenDayText {
    /// Today's line, in the painter's calendar and time zone.
    static func today(_ now: Date = .now, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let date = gregorian.dateComponents([.year, .month, .day], from: now)
        return text(ZenDay.line(year: date.year ?? 2026, month: date.month ?? 1, day: date.day ?? 1))
    }

    /// The day (year, month, day) Zen last said its line, so a painting opened with Zen on says it
    /// once a day; not a preference.
    private static let shownKey = "zenDayShown"

    static func dayStamp(_ now: Date = .now, calendar: Calendar = .current) -> String {
        let date = calendar.dateComponents([.year, .month, .day], from: now)
        return "\(date.year ?? 0)-\(date.month ?? 0)-\(date.day ?? 0)"
    }

    static func wasShown(today now: Date = .now, in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: shownKey) == dayStamp(now)
    }

    static var wasShownToday: Bool { wasShown() }

    static func markShown(today now: Date = .now, in defaults: UserDefaults = .standard) {
        defaults.set(dayStamp(now), forKey: shownKey)
    }

    static func markShownToday() { markShown() }

    static func text(_ line: ZenDay.Line) -> String {
        switch line {
        case .birthday:
            String(localized: "zen.day.birthday",
                   defaultValue: "It’s Zen’s birthday today. All it wants is for you to take your time.",
                   comment: "Painting screen, Zen Mode's line on its birthday (October 5), shown in a toast; Zen is Zen Mode, spoken of as a little character")
        case let .day(mood, nudge):
            String(localized: "zen.day.line", defaultValue: "\(self.mood(mood)) \(self.nudge(nudge))",
                   comment: "Painting screen, Zen Mode's line for the day in a toast: its mood today (first argument, a sentence) and a gentle word to the painter (second, a sentence)")
        }
    }

    /// Zen's mood: Zen is Zen Mode, a Libra, spoken of as a little character.
    static func mood(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "zen.mood.0", defaultValue: "Zen feels perfectly balanced, as Libras like to.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 1: String(localized: "zen.mood.1", defaultValue: "Venus, Zen’s ruling planet, is in a good mood.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 2: String(localized: "zen.mood.2", defaultValue: "Zen woke up wanting to drift slowly.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 3: String(localized: "zen.mood.3", defaultValue: "The scales tip gently toward blue today.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, whose sign is the scales)")
        case 4: String(localized: "zen.mood.4", defaultValue: "Zen is in a corners-first sort of mood.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 5: String(localized: "zen.mood.5", defaultValue: "Zen asked the stars about today. They said hello.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 6: String(localized: "zen.mood.6", defaultValue: "Mercury is up to something. Zen isn’t worried.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character); the planet Mercury")
        case 7: String(localized: "zen.mood.7", defaultValue: "Zen dreamed of wide skies and long brushstrokes.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 8: String(localized: "zen.mood.8", defaultValue: "Zen feels unhurried today, even for Zen.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 9: String(localized: "zen.mood.9", defaultValue: "Libras weigh things carefully. Today Zen weighs nothing at all.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character); a play on weighing")
        case 10: String(localized: "zen.mood.10", defaultValue: "The moon is being quiet, so Zen is too.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 11: String(localized: "zen.mood.11", defaultValue: "Zen’s lucky color today is whichever one you pick.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character); you is the painter")
        case 12: String(localized: "zen.mood.12", defaultValue: "Zen is humming something with no words.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 13: String(localized: "zen.mood.13", defaultValue: "The stars say it’s a good day for in-between colors.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra); in-between colors are subtle ones, between two others")
        case 14: String(localized: "zen.mood.14", defaultValue: "Zen feels like tea that has steeped just long enough.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 15: String(localized: "zen.mood.15", defaultValue: "Zen has decided today is a soft day.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 16: String(localized: "zen.mood.16", defaultValue: "The planets are lined up, roughly. Close enough, says Zen.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 17: String(localized: "zen.mood.17", defaultValue: "Zen is in the mood to wander a little, then settle.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 18: String(localized: "zen.mood.18", defaultValue: "Zen counted the areas left, then happily forgot the number.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character); areas are the numbered areas of the painting")
        case 19: String(localized: "zen.mood.19", defaultValue: "Zen feels rested, like paper before the first stroke.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 20: String(localized: "zen.mood.20", defaultValue: "Being a Libra, Zen can’t pick a favorite color. It likes them all.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character); Libras are said to be indecisive")
        case 21: String(localized: "zen.mood.21", defaultValue: "Zen’s horoscope says patience pays, a little at a time.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        case 22: String(localized: "zen.mood.22", defaultValue: "Zen is feeling a little sparkly today.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character)")
        default: String(localized: "zen.mood.23", defaultValue: "A calm breeze is blowing through Zen’s part of the sky.", comment: "Zen Mode's mood of the day (Zen is Zen Mode, a Libra, spoken of as a little character); its part of the sky is its star sign")
        }
    }

    /// A gentle word to the painter, never an instruction they must follow.
    static func nudge(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "zen.nudge.0", defaultValue: "No rush. The page will wait.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 1: String(localized: "zen.nudge.1", defaultValue: "One area is plenty.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order. An area is one numbered area of the painting")
        case 2: String(localized: "zen.nudge.2", defaultValue: "Stop whenever you like. It all keeps.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order. It all keeps: the painting is saved")
        case 3: String(localized: "zen.nudge.3", defaultValue: "Any amount of painting counts.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 4: String(localized: "zen.nudge.4", defaultValue: "Let the page do the moving.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order. Zen Mode moves the page to the next area itself")
        case 5: String(localized: "zen.nudge.5", defaultValue: "A little today is still a little more.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 6: String(localized: "zen.nudge.6", defaultValue: "Missed a spot? Zen will find it.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm. Zen is Zen Mode, which flies to the areas left")
        case 7: String(localized: "zen.nudge.7", defaultValue: "Nothing here needs to be perfect.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 8: String(localized: "zen.nudge.8", defaultValue: "Your pace is the right pace.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 9: String(localized: "zen.nudge.9", defaultValue: "Go make some tea. Zen will keep your place.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm and optional")
        case 10: String(localized: "zen.nudge.10", defaultValue: "Small areas are good company.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order. Areas are the numbered areas of the painting")
        case 11: String(localized: "zen.nudge.11", defaultValue: "It’s fine to just watch for a while.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 12: String(localized: "zen.nudge.12", defaultValue: "Whatever kind of day it’s been, this part is easy.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; kind to someone on a rough day, never an order")
        case 13: String(localized: "zen.nudge.13", defaultValue: "Paint a little or a lot. Both suit Zen.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, never an order")
        case 14: String(localized: "zen.nudge.14", defaultValue: "Every color finds its place in the end.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; calm, hopeful")
        default: String(localized: "zen.nudge.15", defaultValue: "You’re doing nicely.", comment: "Zen Mode's gentle word to the painter for the day, after its mood; warm, never an order")
        }
    }
}
#endif
