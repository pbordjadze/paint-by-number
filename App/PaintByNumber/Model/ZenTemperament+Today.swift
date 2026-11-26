import Foundation
import PaintCore

extension ZenTemperament {
    /// Zen Mode's temperament today, in the painter's calendar and time zone (PaintCore's
    /// `ZenTemperament.of`). Debug builds take `-zenDate YYYY-MM-DD` in its place, so a
    /// measurement can fly by a chosen day's motion (the birthday, 2026-10-05, is the slowest).
    nonisolated static func today(_ now: Date = .now, timeZone: TimeZone = .current) -> ZenTemperament {
        #if DEBUG
        if let pinned = UserDefaults.standard.string(forKey: "zenDate") {
            let parts = pinned.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3 { return of(year: parts[0], month: parts[1], day: parts[2]) }
        }
        #endif
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.dateComponents([.year, .month, .day], from: now)
        return of(year: date.year ?? 2026, month: date.month ?? 1, day: date.day ?? 1)
    }
}
