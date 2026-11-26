import Testing
@testable import PaintCore

@Suite("Zen Mode's temperament")
struct ZenTemperamentTests {
    private func everyDay(of year: Int) -> [(month: Int, day: Int)] {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...12).flatMap { m in (1...lengths[m - 1]).map { (m, $0) } }
    }

    private func isInBands(_ t: ZenTemperament) -> Bool {
        ZenTemperament.pauses.contains(t.pause) && ZenTemperament.flights.contains(t.flight)
            && ZenTemperament.closenesses.contains(t.closeness) && ZenTemperament.tastes.contains(t.taste)
    }

    @Test(arguments: [2026, 2027, 2028, 2100])
    func everyDayStaysInItsBandsAndDaysDiffer(year: Int) {
        let days = everyDay(of: year).map { ZenTemperament.of(year: year, month: $0.month, day: $0.day) }
        #expect(days.allSatisfy(isInBands))
        // Each day its own mood: neighbours never move alike.
        for (a, b) in zip(days, days.dropFirst()) { #expect(a != b) }
        // The year sways both ways round the middle on every axis.
        let b = ZenTemperament.balanced
        #expect(days.contains { $0.pause > b.pause + 0.05 } && days.contains { $0.pause < b.pause - 0.02 })
        #expect(days.contains { $0.taste > 0.1 } && days.contains { $0.taste < -0.05 })
        #expect(days.contains { $0.closeness > 0.47 } && days.contains { $0.closeness < 0.43 })
    }

    @Test func paceMovesPauseAndFlightTogether() {
        for (m, d) in everyDay(of: 2027) {
            let t = ZenTemperament.of(year: 2027, month: m, day: d)
            #expect((t.pause - 0.35 >= 0) == (t.flight - 0.55 >= 0))
        }
    }

    @Test func theSameDateIsTheSameMoodAndTheBirthdayIsTheSlowest() {
        #expect(ZenTemperament.of(year: 2026, month: 11, day: 26) == ZenTemperament.of(year: 2026, month: 11, day: 26))
        #expect(ZenTemperament.of(year: 2026, month: 11, day: 26) != ZenTemperament.of(year: 2027, month: 11, day: 26))
        let birthday = ZenTemperament.of(year: 2031, month: 10, day: 5)
        #expect(birthday.pause == ZenTemperament.pauses.upperBound && birthday.flight == ZenTemperament.flights.upperBound)
        #expect(birthday.taste == ZenTemperament.tastes.upperBound)
    }

    @Test func tasteChoosesAmongAreas() {
        let near = (distanceSquared: Float(100), area: Float(10))
        let far = (distanceSquared: Float(140), area: Float(2000))
        // The balanced middle takes the nearest; a broad day the larger area a little farther off.
        let balanced = ZenTemperament.balanced
        #expect(balanced.score(distanceSquared: near.0, area: near.1) < balanced.score(distanceSquared: far.0, area: far.1))
        let broad = ZenTemperament.swayed(pace: 0, closeness: 0, taste: 1)
        #expect(broad.score(distanceSquared: near.0, area: near.1) > broad.score(distanceSquared: far.0, area: far.1))
        // Much farther stays farther.
        #expect(broad.score(distanceSquared: 100, area: 10) < broad.score(distanceSquared: 1000, area: 2000))
    }

    @Test func oddDatesNeverTrap() {
        for (y, m, d) in [(2026, 0, 0), (2026, 13, 40), (2027, 2, 29), (-5, 6, 1), (Int.max, 12, 31), (Int.min, 1, 1)] {
            #expect(isInBands(ZenTemperament.of(year: y, month: m, day: d)))
        }
        #expect(ZenTemperament.balanced.score(distanceSquared: 9, area: 0) == 9)
    }
}
