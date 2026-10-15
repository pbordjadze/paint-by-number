import Foundation
import Testing
@testable import PaintByNumber

/// A painting whose reopen at launch never settled (the app ended opening it) isn't reopened at
/// the next launch: the gallery shows instead, once.
@MainActor
struct ReopenGuardTests {
    @Test func aReopenThatNeverSettledSkipsTheNextOneOnce() throws {
        let suite = "PBNTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let guardian = ReopenGuard(defaults: defaults)

        #expect(guardian.mayReopen())
        guardian.begin()
        #expect(!guardian.mayReopen())
        #expect(guardian.mayReopen())

        guardian.begin()
        guardian.settled()
        #expect(guardian.mayReopen())
    }
}
