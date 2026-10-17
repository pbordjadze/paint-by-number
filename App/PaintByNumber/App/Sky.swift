import Foundation

/// The two skies the app keeps, a gentle nod to astrology (Paul, October 17, 2026; decided with
/// the Lamplit Table, the Lamp's jury for the app's screens and controls): by Sun painting plays a
/// brighter kalimba, by Moon a celesta-like bell on the same five notes, lower and minor
/// (`SoundPlayer`), and the fill's two sparkles become stars (`CanvasView.popSparkles`). Only
/// the sun and the moon keeping the hours: nothing here tells the painter anything about
/// themselves.
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

/// Settings › Sky: Follow the Sky (the default) takes the sky of the hour; Sun and Moon keep
/// theirs at every hour.
nonisolated enum SkySetting: String, CaseIterable, Identifiable, Sendable {
    case followTheSky, sun, moon

    static let `default` = SkySetting.followTheSky

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

    var symbol: String {
        switch self {
        case .followTheSky: "sun.horizon"
        case .sun: Sky.sun.symbol
        case .moon: Sky.moon.symbol
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

    /// The sky the stored setting gives at `date`: what a sound or a sparkle asks for.
    static func current(at date: Date = .now, in defaults: UserDefaults = .standard) -> Sky {
        stored(in: defaults).sky(at: date)
    }
}
