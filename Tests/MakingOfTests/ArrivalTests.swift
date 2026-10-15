import PaintCore
import Testing
@testable import MakingOf

/// Arrival fields, region times and the paints' flow against `making_of_reveal.py`
/// (`Fixtures/reveal-small.json`). Everything is exact (`==`): the fields use only `+ - * /` and
/// `sqrt`, which are correctly rounded everywhere, and take the same operations in the same order
/// as the reference. Measured difference to the reference: 0 (a field is checked sample by sample,
/// then by a fingerprint of every pixel).
@Suite struct ArrivalTests {
    private let fixture: RevealFixture

    init() throws { fixture = try RevealFixture.load() }

    @Test func eachStepsFieldMatchesTheReference() {
        for (k, want) in fixture.expected.arrival.enumerated() {
            let field = fixture.arrival(k)
            #expect(samples(field, every: fixture.inputs.sampling) == want.samples, "step \(k)")
            #expect(field.data.max() == want.max && field.data.min() == want.min, "step \(k)")
            #expect(fingerprint(field.data) == want.fingerprint, "step \(k)")
        }
    }

    @Test func aFieldDoesNotDependOnHowItsRowsAreSharedBetweenCores() {
        // the same field by one plain loop: bands follow the core count, the values must not
        let k = 0
        let (w, h) = (fixture.width, fixture.height)
        let style = ScheduleStyle.standard
        let timing = fixture.timing
        let speed = style.arrivalSpeed * Double(w) * timing.pace(style)
        let end = timing.start(k) + timing.step - style.stepMargin
        let noise = StepNoise(step: k, width: w, height: h, streams: fixture.streams)
        var data: [Double] = []
        for y in 0..<h {
            for x in 0..<w {
                var time = Double.infinity
                for v in fixture.visits[k] {
                    let dx = Double(x) - v.x, dy = Double(y) - v.y
                    time = min(time, v.time + (dx * dx + dy * dy).squareRoot() / speed)
                }
                data.append(time + noise[x, y])
            }
        }
        let first = fixture.visits[k].map(\.time).min()!
        let highest = data.max()!
        #expect(highest > end, "step 1 of the fixture is squeezed, so the squeeze is compared too")
        data = data.map { first + ($0 - first) * (end - first) / (highest - first) }
        #expect(firstDifference(fixture.arrival(k).data, data) == nil, "the plain loop and the banded one differ")
    }

    @Test func aFieldNeverArrivesAfterItsStepEndsAndGrowsFromTheVisits() {
        let timing = fixture.timing
        for k in 0..<6 {
            let field = fixture.arrival(k)
            let end = timing.start(k) + timing.step - ScheduleStyle.standard.stepMargin
            let latest = field.data.max()!
            #expect(latest <= end + 1e-12, "step \(k) is done by \(end), not \(latest)")
            #expect(field.data.min()! >= fixture.visits[k].map(\.time).min()!, "step \(k) never precedes its first visit")
        }
    }

    // A pure distance field: no noise, no squeeze.
    private func plain(_ visits: [Visit], width: Int, height: Int, speed: Double = 10, end: Double = 1000) -> Plane<Double> {
        var quiet = ScheduleStyle()
        quiet.coarseNoise = 0
        quiet.fineNoise = 0
        let noise = StepNoise(step: 0, width: width, height: height, streams: ShowStreams(seed: 1), style: quiet)
        return Arrival.field(visits: visits, width: width, height: height, speed: speed, end: end, noise: noise)
    }

    @Test func theChangeSpreadsFromTheEarliestVisitAtItsSpeed() {
        let field = plain([Visit(time: 2, x: 3, y: 4), Visit(time: 2.5, x: 30, y: 4)], width: 40, height: 10)
        #expect(field[3, 4] == 2)
        #expect(field[6, 8] == 2 + 5 / 10.0, "3-4-5 away")
        #expect(field[30, 4] == 2.5)
        #expect(field[34, 4] == 2.5 + 4 / 10.0)
        #expect(field[20, 4] == 2.5 + 10 / 10.0, "10 px from the later visit beats 17 px from the first")
        #expect(field[10, 4] == 2 + 7 / 10.0, "7 px from the first beats 20 from the second")
    }

    @Test func aLateStepIsSqueezedTowardItsFirstVisit() {
        let visits = [Visit(time: 1, x: 0, y: 0)]
        let free = plain(visits, width: 21, height: 1)
        #expect(free[20, 0] == 3)
        let squeezed = plain(visits, width: 21, height: 1, end: 2)
        #expect(squeezed[0, 0] == 1, "the first visit keeps its time")
        #expect(abs(squeezed[20, 0] - 2) < 1e-12, "the last pixel lands on the end")
        #expect(abs(squeezed[10, 0] - 1.5) < 1e-12, "the rest scale evenly")
        // an early step is left alone
        #expect(plain(visits, width: 21, height: 1, end: 5) == free)
    }

    @Test func regionMinimumTakesTheEarliestPixelOfEachRegion() {
        let times = Plane(width: 4, height: 2, data: [5.0, 3, 9, 1, 4, 8, 2, 7])
        let labels = Plane<Int32>(width: 4, height: 2, data: [0, 0, 1, 1, 0, 2, 2, 1])
        #expect(Arrival.regionMinimum(times, labels: labels, count: 4) == [3, 1, 2, .infinity])
    }

    @Test func regionTimesMatchTheReference() {
        let merged = Arrival.regionMinimum(
            fixture.arrival(3), labels: fixture.simplifiedLabels, count: fixture.inputs.simplifiedLabels.count)
        let lift = Arrival.regionMinimum(
            fixture.arrival(4), labels: fixture.simplifiedLabels, count: fixture.inputs.simplifiedLabels.count)
        let clear = Arrival.regionMinimum(
            fixture.arrival(5), labels: fixture.simplifiedLabels, count: fixture.inputs.simplifiedLabels.count)
        #expect(merged == fixture.expected.merged)
        #expect(lift == fixture.expected.lift)
        #expect(clear == fixture.expected.clear)
    }

    private func paintFlow() -> PaintFlow.Result {
        PaintFlow.times(
            seeds: fixture.seeds, paints: fixture.paints, paintCount: fixture.inputs.paints,
            labels: fixture.paletteLabels, labelCount: fixture.inputs.paletteLabels.count,
            following: fixture.arrival(2), timing: fixture.timing)
    }

    @Test func thePaintsFlowMatchesTheReference() {
        let flow = paintFlow()
        #expect(Array(flow.regionTimes.prefix(16)) == fixture.expected.paints.first)
        #expect(fingerprint(flow.regionTimes) == fixture.expected.paints.fingerprint)
        #expect(flow.spread == fixture.expected.paints.spread)
    }

    @Test func eachPaintsLastRegionSetsItsSpread() {
        let flow = paintFlow()
        let paints = fixture.paints, labels = fixture.paletteLabels
        var latest = [Double](repeating: -.infinity, count: fixture.inputs.paints)
        for (paint, label) in zip(paints.data, labels.data) {
            latest[Int(paint)] = max(latest[Int(paint)], flow.regionTimes[Int(label)])
        }
        #expect(flow.spread == latest)
        let step = fixture.timing.start(2) + fixture.timing.step
        #expect(flow.regionTimes.allSatisfy { $0 <= step - ScheduleStyle.standard.stepMargin + 1e-12 })
    }

    // Two paints in a row of four pixels, the first seeded and the second not.
    @Test func aSeededPaintFlowsFromItsSeedAndAnUnseededOneFollowsTheCrew() {
        let timing = ScheduleTiming(intro: 0, step: 2)          // the paints step spans 4...6
        let paints = Plane<Int32>(width: 4, height: 1, data: [0, 0, 1, 1])
        let labels = Plane<Int32>(width: 4, height: 1, data: [0, 0, 1, 1])
        let seed = PaintSeed(time: 4.1, x: 1, y: 0, paint: 0)
        let calm = PaintFlow.times(
            seeds: [seed], paints: paints, paintCount: 2, labels: labels, labelCount: 2,
            following: Plane(width: 4, height: 1, repeating: 5), timing: timing)
        // the seed's own pixel starts 0.25 s after it drops (its neighbours later, a width per 1.3 s)
        #expect(calm.regionTimes[0] == 4.1 + 0.25 + 0 / (4 / 1.3))
        #expect(calm.regionTimes[1] == 5 + 0.3, "the crew's time plus a lag")
        #expect(calm.spread == calm.regionTimes)
        // a crew too late to finish in time squeezes everything between the floor and the step's end
        let late = PaintFlow.times(
            seeds: [seed], paints: paints, paintCount: 2, labels: labels, labelCount: 2,
            following: Plane(width: 4, height: 1, repeating: 7), timing: timing)
        #expect(abs(late.regionTimes[1] - 5.8) < 1e-12, "the latest lands on the end less its margin")
        #expect(late.regionTimes[0] > 4.2 && late.regionTimes[0] < calm.regionTimes[0], "scaled toward the floor")
    }
}
