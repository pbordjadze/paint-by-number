import PaintCore
import Testing
@testable import MakingOf

/// When each number comes in and which pixels it owns, against `making_of_reveal.py`
/// (`Fixtures/reveal-small.json`), exact (`==`): comparisons and `+ - * /` only. Measured
/// difference to the reference: 0.
@Suite struct NumberScheduleTests {
    private let fixture: RevealFixture

    init() throws { fixture = try RevealFixture.load() }

    private func schedule() -> NumberSchedule {
        let regions = fixture.simplifiedLabels
        let relax = fixture.arrival(5)
        let clear = Arrival.regionMinimum(relax, labels: regions, count: fixture.inputs.simplifiedLabels.count)
        return NumberSchedule(
            numbers: fixture.numbers, clear: clear, regions: regions, relaxArrival: relax,
            visits: fixture.visits[ScheduleTiming.templateStep], timing: fixture.timing, petHeight: fixture.inputs.petHeight)
    }

    @Test func theTimesMatchTheReference() {
        #expect(schedule().times == fixture.expected.numbers)
    }

    @Test func theDiscsMatchTheReference() {
        let want = RevealFixture.plane(fixture.expected.discs.runs, width: fixture.width, height: fixture.height)
        let discs = NumberSchedule.discs(numbers: fixture.numbers, width: fixture.width, height: fixture.height)
        #expect(firstDifference(discs.data, want.data) == nil)
        #expect(Set(discs.data).subtracting([-1]).count <= fixture.numbers.count)
    }

    @Test func everyNumberComesInInsideTheTemplateStepAfterItsAreaClears() {
        let timing = fixture.timing
        let style = ScheduleStyle.standard
        let regions = fixture.simplifiedLabels
        let clear = fixture.expected.clear
        let times = schedule().times
        #expect(times.count == fixture.numbers.count)
        for (number, time) in zip(fixture.numbers, times) {
            let x = min(max(Int(number.x), 0), fixture.width - 1), y = min(max(Int(number.y), 0), fixture.height - 1)
            #expect(time <= timing.end - style.numberEndMargin)
            let cleared = clear[Int(regions[x, y])]
            #expect(time >= min(cleared + style.numberAfterClear, timing.end - style.numberEndMargin))
        }
    }

    // A one-region picture with the template step's field known by hand.
    private func tiny(numbers: [(x: Double, y: Double, size: Double)], visits: [Visit]) -> [Double] {
        let timing = ScheduleTiming(intro: 0, step: 2)           // the template step spans 10...12
        let field = Plane(width: 100, height: 50, repeating: 10.0)
        return NumberSchedule(
            numbers: numbers, clear: [10], regions: Plane(width: 100, height: 50, repeating: 0), relaxArrival: field,
            visits: visits, timing: timing, petHeight: 10).times
    }

    @Test func aNumberNearAWorkingPetComesInJustAfterItsLastVisit() {
        // within 1.6 guardian heights (16 px): the earliest visit there, plus 0.3 s
        let visits = [Visit(time: 10.9, x: 20, y: 20), Visit(time: 10.6, x: 30, y: 20), Visit(time: 10.1, x: 90, y: 40)]
        let times = tiny(numbers: [(x: 25, y: 20, size: 4)], visits: visits)
        #expect(times == [10.6 + 0.3])
    }

    @Test func aNumberFarFromEveryPetWaitsForLateInTheStep() {
        // 0.55 of a step into the template step is 11.1; the field plus 0.45 s is 10.45; clearing 10.05
        let times = tiny(numbers: [(x: 80, y: 10, size: 4)], visits: [Visit(time: 10.2, x: 5, y: 45)])
        #expect(times == [10 + 0.55 * 2])
    }

    @Test func aNumberWaitsForTheOutlinesToRelaxAtIt() {
        let timing = ScheduleTiming(intro: 0, step: 2)
        let field = Plane(width: 100, height: 50, repeating: 11.0)       // the ripple arrives at 11
        let times = NumberSchedule(
            numbers: [(x: 80, y: 10, size: 4)], clear: [10], regions: Plane(width: 100, height: 50, repeating: 0),
            relaxArrival: field, visits: [Visit(time: 10.2, x: 5, y: 45)], timing: timing, petHeight: 10).times
        #expect(times == [11 + 0.45], "after the ripple, though late in the step would be 11.1")
    }

    @Test func noNumberIsLaterThanTheShowsEnd() {
        let timing = ScheduleTiming(intro: 0, step: 2)
        let times = NumberSchedule(
            numbers: [(x: 80, y: 10, size: 4)], clear: [50], regions: Plane(width: 100, height: 50, repeating: 0),
            relaxArrival: Plane(width: 100, height: 50, repeating: 60), visits: [Visit(time: 11, x: 5, y: 45)],
            timing: timing, petHeight: 10).times
        #expect(times == [12 - 0.15])
    }

    @Test func aNumberFadesInOverItsFadeTime() {
        let schedule = NumberSchedule(
            numbers: [(x: 80, y: 10, size: 4)], clear: [10], regions: Plane(width: 100, height: 50, repeating: 0),
            relaxArrival: Plane(width: 100, height: 50, repeating: 10), visits: [Visit(time: 10.2, x: 5, y: 45)],
            timing: ScheduleTiming(intro: 0, step: 2), petHeight: 10)
        let at = schedule.times[0]
        #expect(schedule.alpha(0, at: at - 1) == 0 && schedule.alpha(0, at: at) == 0)
        #expect(abs(schedule.alpha(0, at: at + 0.05) - 0.5) < 1e-9, "halfway through is half in")
        #expect(schedule.alpha(0, at: at + 0.1) == 1 && schedule.alpha(0, at: at + 5) == 1)
    }

    @Test func aDiscIsTheNumbersSizeAtLeastFourPixelsAndTheLaterOneWins() {
        let discs = NumberSchedule.discs(
            numbers: [(x: 10, y: 10, size: 10), (x: 14, y: 10, size: 1), (x: 0, y: 0, size: 2)], width: 40, height: 30)
        #expect(discs[10, 19] == 0 && discs[10, 20] == -1, "the first, size 10, has radius 9: 9 px down is in, 10 is out")
        #expect(discs[1, 10] == 0 && discs[0, 10] == -1)
        #expect(discs[14, 10] == 1 && discs[18, 10] == 1 && discs[19, 10] == 0, "the second is 4 px across, and later")
        #expect(discs[11, 10] == 1 && discs[10, 10] == 1, "where they overlap the later one wins")
        #expect(discs[4, 0] == 2 && discs[5, 0] == -1 && discs[2, 2] == 2 && discs[3, 3] == -1, "the third is cut off by the corner")
        #expect(NumberSchedule.discs(numbers: [], width: 3, height: 3).data == Array(repeating: -1, count: 9))
    }
}
