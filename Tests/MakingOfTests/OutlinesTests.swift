import PaintCore
import Testing
@testable import MakingOf

/// The stair-stepped outlines and their relaxing, by hand: the same cases as `OutlinesTests` in
/// `tools/tests/test_making_of_reveal.py`. Everything is exact (`==`): geometry uses only `+ - * /`,
/// `sqrt`, and correctly rounded rounding, in the reference's order. The lines of a whole show are
/// compared with the Python's in `FieldShowTests` (`fields-small.json`).
@Suite struct OutlinesTests {
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

    // MARK: relaxing

    /// Two lines as the show keeps them, the ripple reaching the first's points from 10 s on, a tenth
    /// of a second apart, and the second's all at 11 s.
    private func strokes() -> [StrokeSchedule.Stroke] {
        let lines = [[Point(3, 4), Point(40, 22), Point(61, 9)], [Point(10, 30), Point(10, 50)]]
        return lines.enumerated().map { n, points in
            let (jagged, smooth) = StrokeSchedule.staircase(points, grid: 5)
            let relax = jagged.indices.map { n == 0 ? 10 + 0.1 * Double($0) : 11 }
            return StrokeSchedule.Stroke(index: n, start: 0, duration: 1, jagged: jagged, smooth: smooth, relax: relax)
        }
    }

    @Test func theFinishedTemplateIsTheSmoothLinesAndTheFirstIsTheStairs() {
        let strokes = strokes()
        let jagged = StrokeSchedule.relaxed(strokes, at: -.infinity, over: 0.4)
        let smooth = StrokeSchedule.relaxed(strokes, at: .infinity, over: 0.4)
        for (line, stroke) in zip(jagged, strokes) {
            #expect(line.points == stroke.jagged && line.stroke == stroke.index && line.value == 1)
        }
        for (line, stroke) in zip(smooth, strokes) { #expect(line.points == stroke.smooth) }
    }

    @Test func eachPointRelaxesWhenTheRippleReachesIt() {
        let strokes = strokes()
        let lines = StrokeSchedule.relaxed(strokes, at: 10.5, over: 0.4)
        let (first, a) = (lines[0].points, strokes[0])
        #expect(first[0] == a.smooth[0], "reached 0.5 s ago: smooth")
        #expect(first[1] == a.smooth[1], "0.4 s ago: just done, exactly")
        #expect(first[5] == a.jagged[5], "reached now: still the stairs")
        #expect(first.last == a.jagged.last, "not reached yet")
        let m = 0.5 * 0.5 * (3 - 2 * 0.5)               // the third point, half way: eased
        #expect(abs(first[3].x - (a.jagged[3].x * (1 - m) + a.smooth[3].x * m)) < 1e-12)
        #expect(abs(first[3].y - (a.jagged[3].y * (1 - m) + a.smooth[3].y * m)) < 1e-12)
        #expect(lines[1].points == strokes[1].jagged)
    }
}
