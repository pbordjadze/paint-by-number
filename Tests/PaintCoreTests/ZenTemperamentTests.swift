import Testing
@testable import PaintCore

@Suite("Zen Mode's temperament")
struct ZenTemperamentTests {
    private func everyDay(of year: Int) -> [(month: Int, day: Int)] {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...12).flatMap { m in (1...lengths[m - 1]).map { (m, $0) } }
    }

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    private func isInBands(_ t: ZenTemperament) -> Bool {
        ZenTemperament.pauses.contains(t.pause) && ZenTemperament.flights.contains(t.flight)
            && ZenTemperament.closenesses.contains(t.closeness) && ZenTemperament.tastes.contains(t.taste)
            && (0...1).contains(t.wander)
    }

    @Test(arguments: [2026, 2027, 2028, 2100])
    func everyDayStaysInItsBandsAndDaysFeelDifferent(year: Int) {
        let days = everyDay(of: year).map { ZenTemperament.of(year: year, month: $0.month, day: $0.day) }
        #expect(days.allSatisfy(isInBands))
        for (a, b) in zip(days, days.dropFirst()) { #expect(a != b) }
        // Most days lean clearly calm or lively, and the year has plenty of each.
        let calm = days.filter { $0.flight > 0.8 }.count
        let lively = days.filter { $0.wander > 0.5 }.count
        #expect(calm > days.count / 5 && lively > days.count / 5)
        #expect(days.filter { abs($0.flight - 0.55) < 0.05 && $0.wander < 0.1 }.count < days.count / 5)
    }

    @Test func calmLingersAndLivelyWanders() {
        let calm = ZenTemperament.mood(1, closeness: 0)
        #expect(close(calm.pause, 0.90) && close(calm.flight, 1.10) && close(calm.taste, 0.45) && calm.wander == 0)
        let lively = ZenTemperament.mood(-1, closeness: 0)
        #expect(close(lively.pause, 0.25) && close(lively.flight, 0.45) && close(lively.taste, -0.20) && lively.wander == 1)
        #expect(ZenTemperament.mood(0, closeness: 0) == .balanced)
    }

    @Test func theSameDateIsTheSameMoodAndOctober5IsTheCalmest() {
        #expect(ZenTemperament.of(year: 2026, month: 11, day: 26) == ZenTemperament.of(year: 2026, month: 11, day: 26))
        #expect(ZenTemperament.of(year: 2026, month: 11, day: 26) != ZenTemperament.of(year: 2027, month: 11, day: 26))
        let calmest = ZenTemperament.of(year: 2031, month: 10, day: 5)
        #expect(close(calmest.pause, ZenTemperament.pauses.upperBound) && close(calmest.flight, ZenTemperament.flights.upperBound))
    }

    @Test func tasteAndWanderChooseAmongAreas() {
        let diagonal: Float = 1000
        let near = (d2: Float(100 * 100), area: Float(10))
        let farBig = (d2: Float(180 * 180), area: Float(5000))
        let across = (d2: Float(350 * 350), area: Float(10))
        let b = ZenTemperament.balanced
        // The balanced middle takes the nearest.
        #expect(b.score(distanceSquared: near.d2, area: near.area, diagonal: diagonal)
                < b.score(distanceSquared: farBig.d2, area: farBig.area, diagonal: diagonal))
        // A calm day the large area farther off.
        let calm = ZenTemperament.mood(1, closeness: 0)
        #expect(calm.score(distanceSquared: near.d2, area: near.area, diagonal: diagonal)
                > calm.score(distanceSquared: farBig.d2, area: farBig.area, diagonal: diagonal))
        // A lively day flies across the painting rather than next door.
        let lively = ZenTemperament.mood(-1, closeness: 0)
        #expect(lively.score(distanceSquared: across.d2, area: across.area, diagonal: diagonal)
                < lively.score(distanceSquared: near.d2, area: near.area, diagonal: diagonal))
    }

    @Test func oddDatesNeverTrap() {
        for (y, m, d) in [(2026, 0, 0), (2026, 13, 40), (2027, 2, 29), (-5, 6, 1), (Int.max, 12, 31), (Int.min, 1, 1)] {
            #expect(isInBands(ZenTemperament.of(year: y, month: m, day: d)))
        }
        #expect(ZenTemperament.balanced.score(distanceSquared: 9, area: 0, diagonal: 0) == 9)
        #expect(ZenTemperament.mood(-1, closeness: 0).score(distanceSquared: 9, area: 0, diagonal: 0).isFinite)
    }
}
