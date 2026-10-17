import Foundation

/// The two skies the app keeps, a gentle nod to astrology (Paul, October 17, 2026; decided with
/// the Lamplit Table, the Lamp's jury for the app's screens and controls): by Sun painting plays a
/// brighter kalimba, by Moon a celesta-like bell on the same five notes, lower and minor
/// (`SoundPlayer`), and the fill's two sparkles become stars (`CanvasView.popSparkles`). Only
/// the sun and the moon keeping the hours: nothing here tells the painter anything about
/// themselves. Debug and SideStore builds only for now (`current`).
nonisolated enum Sky: String, Sendable {
    case sun, moon

    /// Sun from 6 a.m. to 7 p.m. by the painter's own clock, all year, and Moon the rest: first
    /// light, and the lamps after supper. The device keeps its local time zone, so this needs
    /// no location.
    static let sunrise = 6
    static let nightfall = 19

    /// The sky at `date` in `calendar`'s time zone (the device's, following it as it travels).
    static func at(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Sky {
        (sunrise..<nightfall).contains(calendar.component(.hour, from: date)) ? .sun : .moon
    }

    /// The sky painting plays in at `date`: what a sound or a sparkle asks for. Sun and Moon
    /// are in Debug and SideStore builds only for now (`UNRELEASED`; Paul, October 17, 2026:
    /// "ship it only to SideStore for now"): the release has no Sky row and keeps the Sun, whose
    /// voice there is the kalimba the app first shipped (`SoundPlayer.scale(of:)`), with no stars.
    static func current(at date: Date = .now, in defaults: UserDefaults = .standard) -> Sky {
        #if UNRELEASED
        SkySetting.stored(in: defaults).sky(at: date)
        #else
        .sun
        #endif
    }
}

#if UNRELEASED
extension Sky {
    /// `hour` o'clock as the painter's locale writes it ("7 PM", "19 Uhr"), for Settings.
    static func clockText(_ hour: Int, calendar: Calendar = .autoupdatingCurrent) -> String {
        (calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now).formatted(.dateTime.hour())
    }

    /// The SF Symbol Settings shows for the sky.
    var symbol: String {
        switch self {
        case .sun: "sun.max"
        case .moon: "moon.stars"
        }
    }
}

/// Settings › Sky, a theme and nothing to do with the light or dark appearance (an
/// accessibility choice, the system's) or the paper (Settings › Paper): Moon, the default, and
/// Sun keep their sky at every hour; Follow the Sky takes the sky of the hour (Paul, October 17,
/// 2026: "moon should be default, with sun or “auto” as options").
nonisolated enum SkySetting: String, CaseIterable, Identifiable, Sendable {
    case moon, sun, followTheSky

    static let `default` = SkySetting.moon

    var id: String { rawValue }

    var name: String {
        switch self {
        case .followTheSky: String(localized: "sky.followTheSky", defaultValue: "Follow the Sky",
                                   comment: "Choice of the Sky setting: Sun by day and Moon by night, by the painter's own clock")
        case .sun: String(localized: "sky.sun", defaultValue: "Sun",
                          comment: "Choice of the Sky setting: the daytime sounds at every hour")
        case .moon: String(localized: "sky.moon", defaultValue: "Moon",
                           comment: "Choice of the Sky setting: the nighttime sounds, and stars for sparkles, at every hour")
        }
    }

    func sky(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Sky {
        switch self {
        case .followTheSky: Sky.at(date, calendar: calendar)
        case .sun: .sun
        case .moon: .moon
        }
    }

    /// The stored setting (`SettingsKey.sky`), or the default.
    static func stored(in defaults: UserDefaults = .standard) -> SkySetting {
        defaults.string(forKey: SettingsKey.sky).flatMap(SkySetting.init(rawValue:)) ?? .default
    }
}
#endif
