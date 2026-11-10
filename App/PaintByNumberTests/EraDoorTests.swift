import Foundation
import Ravenna
import Testing
@testable import PaintByNumber

/// The secret door (painting-company row 234): the clock set back to 547 opens Ravenna under a
/// passage, the choice outlives the launch, and set forward again it leaves nothing stored.
@MainActor
struct EraDoorTests {
    private func freshDefaults() throws -> UserDefaults {
        let suite = "EraDoorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aClosedDoorShowsPaintByMoonlightAndStoresNothing() throws {
        let defaults = try freshDefaults()
        let door = EraDoor(defaults: defaults)
        #expect(door.shown == .moonlight)
        #expect(door.passage == nil)
        #expect(defaults.object(forKey: EraDoor.key) == nil)
    }

    @Test func theClockSetBackOpensByzantiumOnceThePassageCovers() throws {
        let defaults = try freshDefaults()
        let door = EraDoor(defaults: defaults)
        door.go(to: .byzantium)
        #expect(door.passage == .byzantium)
        #expect(door.shown == .moonlight, "the old era stays until the passage covers it")
        #expect(defaults.string(forKey: EraDoor.key) == "byzantium")
        door.covered()
        #expect(door.shown == .byzantium)
        door.passed()
        #expect(door.passage == nil)
        #expect(EraDoor(defaults: defaults).shown == .byzantium, "the next launch opens in the era")
    }

    @Test func theClockSetForwardLeavesNoTrace() throws {
        let defaults = try freshDefaults()
        let door = EraDoor(defaults: defaults)
        door.go(to: .byzantium)
        door.covered()
        door.passed()
        door.go(to: .moonlight)
        #expect(defaults.object(forKey: EraDoor.key) == nil)
        door.covered()
        door.passed()
        #expect(door.shown == .moonlight)
        #expect(EraDoor(defaults: defaults).shown == .moonlight)
    }

    @Test func aSecondTurnToTheSameEraIsNoSecondPassage() throws {
        let door = EraDoor(defaults: try freshDefaults())
        door.go(to: .moonlight)
        #expect(door.passage == nil, "Paint by Moonlight is already here")
        door.go(to: .byzantium)
        door.go(to: .byzantium)
        #expect(door.passage == .byzantium)
    }

    @Test func onlyTheErasYearsOpenAnything() {
        #expect(EraYear.byzantium == 547)
        #expect(EraYear.opensByzantium(547))
        for year in [0, 546, 548, 1547, EraYear.present] {
            #expect(!EraYear.opensByzantium(year), "\(year)")
        }
        #expect(EraYear.returnsToThePresent(EraYear.present))
        #expect(EraYear.returnsToThePresent(EraYear.present + 1))
        #expect(!EraYear.returnsToThePresent(547))
        #expect(!EraYear.returnsToThePresent(EraYear.present - 1))
    }

    @Test func theWheelStartsAt0547AndEndsAtThePresent() {
        let years = EraClock.years
        #expect(years.first == EraYear.byzantium)
        #expect(years.last == EraYear.present)
        #expect(years == years.sorted() && Set(years).count == years.count)
        #expect(years.count < 30, "the far end is a flick away, not a long scroll")
        #expect(Array(years.suffix(7)) == Array(EraYear.present - 6...EraYear.present))
        #expect(EraClock.text(of: EraYear.byzantium) == "0547")
        #expect(EraClock.nearest(to: EraYear.present) == EraYear.present)
        #expect(EraClock.nearest(to: 547) == 547)
        #expect(EraClock.nearest(to: 1550) == 1600, "a tie takes the later year")
    }
}
