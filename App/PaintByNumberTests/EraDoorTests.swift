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
        #if UNRELEASED
        #expect(years.first == 1, "SideStore's wheel reaches back to 0001")
        #expect(years.contains(EraYear.byzantium) && years.contains(EraYear.stainedGlass))
        #expect(years.count < 60, "a few flicks from end to end")
        #else
        #expect(years.first == EraYear.byzantium)
        #expect(years.count < 30, "the far end is a flick away, not a long scroll")
        #endif
        #expect(years.last == EraYear.present)
        #expect(years == years.sorted() && Set(years).count == years.count)
        #expect(Array(years.suffix(7)) == Array(EraYear.present - 6...EraYear.present))
        #expect(EraClock.text(of: EraYear.byzantium) == "0547")
        #expect(EraClock.nearest(to: EraYear.present) == EraYear.present)
        #expect(EraClock.nearest(to: 547) == 547)
        #expect(EraClock.nearest(to: 1750) == 1800, "a tie takes the later year")
    }

    /// Stained Glass (painting-company row 366): 1248 opens it in SideStore and Debug builds, and
    /// the wheel lights the eras' years and draws a wheel resting beside one on to it.
    @Test func eachEraHasItsYear() {
        #expect(Era.opened(by: 547) == .byzantium)
        #expect(Era.opened(by: EraYear.present) == .moonlight)
        #expect(Era.opened(by: 1600) == nil)
        #if UNRELEASED
        #expect(Era.opened(by: 1248) == .glass)
        #expect(Era.opened(by: 1502) == .watercolor)
        #expect(Era.opened(by: 1000) == .frame)
        #expect(EraYear.modes == [547, 1000, 1248, 1502])
        #expect(EraClock.isLit(1502) && EraClock.pulled(from: 1500) == 1502 && EraClock.pulled(from: 1600) == 1502)
        #expect(EraClock.isLit(1248) && EraClock.isLit(547) && !EraClock.isLit(1300))
        #expect(EraClock.pulled(from: 1200) == 1248 && EraClock.pulled(from: 1300) == 1248)
        #expect(EraClock.pulled(from: 500) == 547 && EraClock.pulled(from: 600) == 547)
        #expect(EraClock.pulled(from: 1248) == nil && EraClock.pulled(from: 1000) == nil)
        #expect(EraClock.pulled(from: 1100) == 1000 && EraClock.pulled(from: 900) == 1000)
        #expect(EraClock.pulled(from: EraYear.present) == nil)
        #else
        #expect(Era.opened(by: 1248) == nil)
        #expect(Era.opened(by: 1502) == nil)
        #expect(Era.opened(by: 1000) == nil)
        #expect(EraYear.modes == [547])
        #expect(!EraClock.isLit(547) && EraClock.pulled(from: 600) == nil, "the release's wheel is as it was")
        #endif
    }

    #if UNRELEASED
    @Test func theGlassEraOutlivesTheLaunch() throws {
        let defaults = try freshDefaults()
        let door = EraDoor(defaults: defaults)
        door.go(to: .glass)
        #expect(defaults.string(forKey: EraDoor.key) == "glass")
        door.covered()
        door.passed()
        #expect(EraDoor(defaults: defaults).shown == .glass)
    }

    /// Watercolor (painting-company row 373) is kept across launches as Stained Glass is.
    @Test func theWatercolorEraOutlivesTheLaunch() throws {
        let defaults = try freshDefaults()
        let door = EraDoor(defaults: defaults)
        door.go(to: .watercolor)
        #expect(defaults.string(forKey: EraDoor.key) == "watercolor")
        door.covered()
        door.passed()
        #expect(EraDoor(defaults: defaults).shown == .watercolor)
    }
    #endif
}
