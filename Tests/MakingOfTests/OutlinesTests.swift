import PaintCore
import Testing
@testable import MakingOf

/// The stair-stepped outlines, their schedule and the lines drawn at a time against
/// `making_of_reveal.py` (`Fixtures/reveal-small.json`). Everything is exact (`==`): geometry uses
/// only `+ - * /`, `sqrt`, and correctly rounded rounding, in the reference's order. Measured
/// difference to the reference: 0 (each stroke's points are compared by a fingerprint of every
/// coordinate, three strokes in full).
@Suite struct OutlinesTests {
    private let fixture: RevealFixture
    private let schedule: StrokeSchedule

    init() throws {
        fixture = try RevealFixture.load()
        schedule = Self.schedule(fixture, traces: fixture.traces)
    }

    private static func schedule(_ f: RevealFixture, traces: [Trace]) -> StrokeSchedule {
        StrokeSchedule(
            strokes: f.strokes, traces: traces, inkArrival: f.arrival(4), relaxArrival: f.arrival(5), spec: f.spec,
            petHeight: f.inputs.petHeight, streams: f.streams)
    }

    // MARK: staircase

    @Test func aStraightLineSnapsToTheGridAndKeepsItsPairs() {
        let (jagged, smooth) = StrokeSchedule.staircase([Point(0, 0), Point(10, 0)], grid: 5)
        #expect(jagged == [Point(0, 0), Point(5, 0), Point(10, 0)])
        #expect(smooth.count == 3)
        #expect(smooth[0] == Point(0, 0) && abs(smooth[1].x - 10 / 3.0) < 1e-12 && abs(smooth[2].x - 25 / 3.0) < 1e-12)
    }

    @Test func aDiagonalClimbsInSteps() {
        let (jagged, smooth) = StrokeSchedule.staircase([Point(0, 0), Point(20, 20)], grid: 5)
        #expect(jagged.count == smooth.count)
        #expect(jagged.first == Point(0, 0) && jagged.last == Point(20, 20))
        for (a, b) in zip(jagged, jagged.dropFirst()) {
            #expect((a.x == b.x) != (a.y == b.y), "every step moves along one axis, never both nor neither")
        }
        #expect(jagged.allSatisfy { $0.x.truncatingRemainder(dividingBy: 5) == 0 && $0.y.truncatingRemainder(dividingBy: 5) == 0 })
        #expect(zip(smooth, smooth.dropFirst()).allSatisfy { $0.x <= $1.x && $0.y <= $1.y })
        // a corner (across, then down) shares the smooth point of the step it ends: the pair repeats
        #expect(zip(smooth, smooth.dropFirst()).contains { $0 == $1 })
    }

    @Test func halfwayRoundsToEven() {
        // 2.5 and 7.5 sit between grid lines of 5: to even is 0 and 10, to the nearest-away would be 5 and 10
        let (jagged, _) = StrokeSchedule.staircase([Point(2.5, 0), Point(7.5, 0)], grid: 5)
        #expect(jagged.first == Point(0, 0) && jagged.last == Point(10, 0))
    }

    @Test func aLineThatSnapsToOnePointStillHasTwo() {
        let (jagged, smooth) = StrokeSchedule.staircase([Point(1, 1), Point(1.2, 1.1)], grid: 5)
        #expect(jagged == [Point(0, 0), Point(0, 0)])
        #expect(smooth.count == 2)
    }

    @Test func aLineIsResampledEveryOnePointFivePixelsBeforeItSnaps() {
        // 300 px at 1.5 px is 201 samples; a grid finer than the spacing keeps them all
        let (fine, smooth) = StrokeSchedule.staircase([Point(0, 0), Point(300, 0)], grid: 0.01)
        #expect(fine.count == 201 && smooth.count == 201)
        // a grid of 5 merges neighbours that snap to the same place
        let (coarse, _) = StrokeSchedule.staircase([Point(0, 0), Point(300, 0)], grid: 5)
        #expect(coarse.count == 61)
    }

    // MARK: schedule

    @Test func theScheduleMatchesTheReference() {
        let want = fixture.expected.strokes
        #expect(schedule.strokes.count == want.count)
        for (stroke, pin) in zip(schedule.strokes, want) {
            let at = "stroke \(stroke.index)"
            #expect(stroke.walked == pin.walked, "\(at)")
            #expect(stroke.start == pin.t0, "\(at)")
            #expect(stroke.duration == pin.dur, "\(at)")
            #expect(stroke.jagged.count == pin.jagged && stroke.smooth.count == pin.smooth, "\(at)")
            #expect(stroke.length == pin.length, "\(at)")
            #expect(fingerprint(stroke.jagged) == pin.jaggedFingerprint, "\(at)")
            #expect(fingerprint(stroke.smooth) == pin.smoothFingerprint, "\(at)")
            #expect(fingerprint(stroke.relax) == pin.relaxFingerprint, "\(at)")
            #expect(stroke.relax.min() == pin.relaxMin && stroke.relax.max() == pin.relaxMax, "\(at)")
        }
    }

    @Test func threeStrokesMatchPointForPoint() {
        for pin in fixture.expected.strokeDetail {
            let stroke = schedule.strokes[pin.index]
            #expect(stroke.jagged.map { [$0.x, $0.y] } == pin.jagged)
            #expect(stroke.smooth.map { [$0.x, $0.y] } == pin.smooth)
            #expect(stroke.cumulative == pin.cumulative)
            #expect(stroke.relax == pin.relax)
        }
    }

    @Test func linesAreDrawnInTheReferencesOrder() {
        let order = schedule.strokes.indices.sorted { (schedule.strokes[$0].start, $0) < (schedule.strokes[$1].start, $1) }
        #expect(order == fixture.expected.order)
    }

    @Test func walkedLinesKeepTheirTracesAndTheRestStartInsideTheInkStep() {
        let timing = fixture.timing
        let style = ScheduleStyle.standard
        let begins = timing.start(ScheduleTiming.inkStep)
        let ends = begins + timing.step - style.inkEndMargin
        let walked = Dictionary(uniqueKeysWithValues: fixture.traces.map { ($0.stroke, $0) })
        #expect(!walked.isEmpty && walked.count < schedule.strokes.count)
        for stroke in schedule.strokes {
            if let trace = walked[stroke.index] {
                #expect(stroke.walked && stroke.start == trace.start && stroke.duration == trace.duration)
            } else {
                #expect(!stroke.walked)
                #expect(stroke.start >= begins + style.strokeEarliest || stroke.start == max(begins, ends - stroke.duration))
                #expect(stroke.start + stroke.duration <= ends + 1e-12)
                let calm = style.strokeMinTime...(style.strokeMaxTime / timing.pace(style))
                #expect(calm.contains(stroke.duration))
            }
        }
    }

    @Test func aLinesWaitIsItsOwnDrawWhoeverElseIsWalked() {
        // each line's jitter comes from the stream of its index, so walking another line (or
        // none) moves no other line
        let none = Self.schedule(fixture, traces: [])
        let walked = Set(fixture.traces.map(\.stroke))
        #expect(none.strokes.allSatisfy { !$0.walked })
        for stroke in schedule.strokes where !walked.contains(stroke.index) {
            #expect(none.strokes[stroke.index].start == stroke.start)
            #expect(none.strokes[stroke.index].duration == stroke.duration)
        }
    }

    // MARK: lines at a time

    @Test func theLinesAtEachTimeMatchTheReference() {
        for pin in fixture.expected.lines {
            let lines = schedule.lines(at: pin.time)
            #expect(lines.map(\.stroke) == pin.lines.map(\.stroke), "t = \(pin.time)")
            #expect(lines.map(\.points.count) == pin.lines.map(\.points), "t = \(pin.time)")
            #expect(lines.map(\.value) == pin.lines.map(\.value), "t = \(pin.time)")
            #expect(fingerprint(lines.flatMap(\.points)) == pin.fingerprint, "t = \(pin.time)")
        }
    }

    @Test func theFinishedTemplateIsTheSmoothLinesAndTheFirstIsTheStairs() {
        let jagged = schedule.relaxed(at: -.infinity)
        let smooth = schedule.relaxed(at: .infinity)
        #expect(fingerprint(jagged.flatMap(\.points)) == fixture.expected.bounds.jaggedFingerprint)
        #expect(fingerprint(smooth.flatMap(\.points)) == fixture.expected.bounds.smoothFingerprint)
        for (line, stroke) in zip(jagged, schedule.strokes) { #expect(line.points == stroke.jagged) }
        for (line, stroke) in zip(smooth, schedule.strokes) { #expect(line.points == stroke.smooth) }
        #expect(schedule.lines(at: fixture.timing.end + 1) == smooth, "from the end on, the finished template")
    }

    @Test func nothingIsDrawnBeforeTheInkStep() {
        let begins = fixture.timing.start(ScheduleTiming.inkStep)
        #expect(schedule.lines(at: 0).isEmpty && schedule.lines(at: begins - 0.001).isEmpty)
        #expect(schedule.lines(at: -.infinity).isEmpty)
    }

    @Test func theInkStepsLinesOnlyGrowAndDarken() {
        let timing = fixture.timing
        var seen: [Int: InkLine] = [:]
        let stop = timing.start(ScheduleTiming.templateStep)
        var t = timing.start(ScheduleTiming.inkStep)
        while t < stop {
            let lines = schedule.lines(at: t)
            #expect(seen.keys.allSatisfy { key in lines.contains { $0.stroke == key } }, "a line begun stays")
            for line in lines {
                #expect(line.points.count >= 2 && line.value > 0 && line.value <= 1)
                if let earlier = seen[line.stroke] {
                    #expect(Array(line.points.prefix(earlier.points.count)) == earlier.points, "a prefix only extends")
                    #expect(line.points.count >= earlier.points.count && line.value >= earlier.value)
                }
                seen[line.stroke] = line
            }
            t += 1 / 30
        }
        // by the step's end every line is down in full, along its whole outline
        let final = schedule.lines(at: stop - 1e-9)
        #expect(final.map(\.stroke) == Array(schedule.strokes.indices))
        for line in final { #expect(line.points == schedule.strokes[line.stroke].jagged) }
    }

    @Test func aWalkedLineIsInFullInkAndTheRestDarkenFromGrey() {
        let style = ScheduleStyle.standard
        let walked = schedule.strokes.first { $0.walked }!
        let calm = schedule.strokes.first { !$0.walked }!
        let ramp = fixture.spec.outlines.inkRamp
        let early = schedule.inked(at: walked.start + walked.duration / 2)
        #expect(early.first { $0.stroke == walked.index }?.value == 1)
        let begun = schedule.inked(at: calm.start + 0.5 * calm.duration).first { $0.stroke == calm.index }
        let darker = schedule.inked(at: calm.start + calm.duration + ramp + 0.01).first { $0.stroke == calm.index }
        #expect((begun?.value ?? 0) > style.inkGrey && (begun?.value ?? 1) < 1)
        #expect(darker?.value == 1, "at the end of its ramp a line is in full ink, exactly")
    }

    @Test func aTimeIsAnsweredTheSameInAnyOrder() {
        let timing = fixture.timing
        let times = [timing.start(4) + 1.1, timing.start(5) + 0.4, timing.start(4) + 0.2, timing.start(5) + 2.0, timing.start(4) + 1.1]
        let forward = times.map { schedule.lines(at: $0) }
        let backward = times.reversed().map { schedule.lines(at: $0) }.reversed()
        #expect(forward == Array(backward))
        #expect(forward[0] == forward[4])
    }

    @Test func theTemplateStepRelaxesEachPointWhenTheRippleReachesIt() {
        let relaxTime = fixture.spec.outlines.relax
        let ripple = schedule.strokes.flatMap(\.relax)
        let t = (ripple.min()! + ripple.max()!) / 2
        var before = 0, during = 0, after = 0
        for line in schedule.relaxed(at: t) {
            let stroke = schedule.strokes[line.stroke]
            for (i, point) in line.points.enumerated() {
                let m = (t - stroke.relax[i]) / relaxTime
                if m <= 0 {
                    before += 1
                    #expect(point == stroke.jagged[i], "not reached yet: still the stairs")
                } else if m >= 1 {
                    after += 1
                    #expect(point == stroke.smooth[i], "done: exactly the smooth curve")
                } else {
                    during += 1
                    let (a, b) = (stroke.jagged[i], stroke.smooth[i])
                    #expect(point.x >= min(a.x, b.x) && point.x <= max(a.x, b.x) && point.y >= min(a.y, b.y) && point.y <= max(a.y, b.y))
                }
            }
        }
        #expect(before > 0 && after > 0, "midway the ripple has passed some points and not reached others")
        _ = during
    }
}
