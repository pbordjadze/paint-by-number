import Foundation

/// The paintings of a painter's own photos that need no purchase (Paul, October 22: "3 free at
/// first, then one per day"): three to begin with and, once one is used, one back at each
/// midnight, never more than three waiting. Library pictures, paintings someone sent and paintings
/// made again never take one (`UnlimitedPaintings`).
///
/// Counted on the device alone, in UserDefaults: a reinstall starts over and a changed clock
/// moves the days, which is accepted rather than sending anything anywhere. A clock set back
/// counts from the new today, so it never stalls the next free painting.
nonisolated struct FreePaintings: Codable, Equatable, Sendable {
    static let most = 3

    /// Free paintings left, as of `since`.
    private(set) var left: Int
    /// The start of the day the next free painting counts from; nil while `most` are left.
    private(set) var since: Date?

    init(left: Int = Self.most, since: Date? = nil) {
        self.left = min(max(left, 0), Self.most)
        self.since = self.left < Self.most ? since : nil
    }

    /// Kept in bounds however it was stored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(left: try container.decode(Int.self, forKey: .left),
                  since: try container.decodeIfPresent(Date.self, forKey: .since))
    }

    /// The count as of `now`: one back for each midnight passed since `since`.
    func at(_ now: Date, calendar: Calendar) -> FreePaintings {
        guard left < Self.most, let since else { return FreePaintings() }
        let today = calendar.startOfDay(for: now)
        guard since <= today else { return FreePaintings(left: left, since: today) }
        let days = calendar.dateComponents([.day], from: since, to: today).day ?? 0
        guard left + days < Self.most else { return FreePaintings() }
        return FreePaintings(left: left + days, since: calendar.date(byAdding: .day, value: days, to: since) ?? today)
    }

    /// Takes one free painting as of `now`; false, changing nothing but the day's count, when
    /// none is left.
    mutating func use(at now: Date, calendar: Calendar) -> Bool {
        let current = at(now, calendar: calendar)
        guard current.left > 0 else {
            self = current
            return false
        }
        self = FreePaintings(left: current.left - 1, since: current.since ?? calendar.startOfDay(for: now))
        return true
    }
}
