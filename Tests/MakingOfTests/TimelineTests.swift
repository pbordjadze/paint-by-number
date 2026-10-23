import Foundation
import Testing
@testable import MakingOf

/// The same hand-made cases as `TimelineTests` in `tools/tests/test_making_of_fields.py`, and the
/// spec's rules for the cards and the length of the show.
@Suite struct TimelineTests {
    private func timeline(_ edit: (inout ShowSpec) -> Void = { _ in }) throws -> Timeline {
        var spec = try ShowSpec(json: shippedSpecData())
        edit(&spec)
        return Timeline(spec)
    }

    @Test func theShowIsItsIntroItsSixStepsAndItsOutro() throws {
        let spec = try ShowSpec(json: shippedSpecData())
        let timeline = Timeline(spec)
        #expect(timeline.duration == spec.timing.intro + 6 * spec.timing.step + spec.timing.outro)
        // 0.6 + 6 x 2.5 + 3.4 s, as the spec ships
        #expect(abs(timeline.duration - 19) < 1e-12)
        let (intro, step) = (spec.timing.intro, spec.timing.step)
        let boundaries = [0, intro - 0.001, intro, intro + step - 0.001, intro + step, intro + 6 * step - 0.001, intro + 6 * step, timeline.duration, 99]
        #expect(boundaries.map { timeline.stage(at: $0) } == [-1, -1, 0, 0, 1, 5, 6, 6, 6])
        #expect(boundaries.map { timeline.step(at: $0) } == [nil, nil, 0, 0, 1, 5, nil, nil, nil])
    }

    @Test func theStepsFollowTheSpecsTiming() throws {
        let slow = try timeline { $0.timing.step = 4; $0.timing.intro = 1; $0.timing.outro = 2 }
        #expect(slow.duration == 27)
        #expect([0.9, 1, 4.9, 5, 24.9, 25].map { slow.stage(at: $0) } == [-1, 0, 0, 1, 5, 6])
    }

    @Test func aCardLivesInsideItsStep() throws {
        let timeline = try timeline()
        let t = timeline.timing
        for k in 0..<6 {
            let start = t.start(k)
            #expect(timeline.cardFade(step: k, at: start) == 0)
            #expect(abs(timeline.cardFade(step: k, at: start + t.step)) < 1e-12)
            #expect(timeline.cardFade(step: k, at: start + t.step / 2) == 1)
            #expect(timeline.cardFade(step: k, at: start - 0.01) == 0 && timeline.cardFade(step: k, at: start + t.step + 0.01) == 0)
            #expect((0.0..<1).contains(timeline.cardFade(step: k, at: start + 0.05)) && (0.0..<1).contains(timeline.cardFade(step: k, at: start + t.step - 0.05)))
            // never two cards at once
            for j in 0..<6 where j != k {
                for s in stride(from: start, to: start + t.step, by: 0.1) {
                    #expect(timeline.cardFade(step: j, at: s) == 0 || abs(timeline.cardFade(step: j, at: s)) < 1e-12, "card \(j) at \(s), in step \(k)")
                }
            }
        }
    }

    @Test func aBriskerShowFadesFaster() throws {
        for step in [0.75, 1.5, 3.0] {
            let timeline = try timeline { $0.timing.step = step; $0.timing.intro = 0.6 }
            let fade = 0.15 / (1.5 / step).squareRoot()
            #expect(abs(timeline.cardFade(step: 0, at: 0.6 + fade) - 1) < 1e-12)
            #expect(timeline.cardFade(step: 0, at: 0.6 + fade * 0.99) < 1)
        }
    }

    @Test func theCrewFadesOutOverTheLastOfTheShow() throws {
        let timeline = try timeline()
        #expect(timeline.crewFade(at: 18) == 1 && timeline.crewFade(at: 18.7) == 1)
        #expect(abs(timeline.crewFade(at: 18.85) - 0.5) < 1e-12)
        #expect(timeline.crewFade(at: 19) == 0 && timeline.crewFade(at: 25) == 0)
    }

    @Test func theHandoffRunsAsTheStepsEnd() throws {
        let timeline = try timeline()
        let end = timeline.timing.end
        #expect(timeline.handoff(at: end - 1) == 0 && timeline.handoff(at: end) == 0)
        #expect(abs(timeline.handoff(at: end + 0.075) - 0.5) < 1e-12)
        #expect(timeline.handoff(at: end + 0.15) == 1)
    }

    @Test func aRingPopsInSwellsAndGoesWhenItsPaintHasSpread() throws {
        let timeline = try timeline()
        let seed = PaintSeed(time: 6, x: 50, y: 40, paint: 3)
        func ring(_ t: Double, spread: Double = 7) -> SeedRing? { timeline.ring(seed, spread: spread, at: t) }
        #expect(ring(5.99) == nil && ring(6) == nil)
        let rising = try #require(ring(6.022))
        #expect(abs(rising.alpha - 0.3) < 1e-12)      // a tenth of the pop, three times as fast
        let mid = try #require(ring(6.11))
        #expect(mid.x == 50 && mid.y == 40 && mid.alpha == 1)
        #expect(abs(mid.radius - 8.5 * (1 + 0.35 * 0.5)) < 1e-12)       // half way, swollen the most
        let settled = try #require(ring(6.5)), fading = try #require(ring(7.25))
        #expect(settled.radius == 8.5 && settled.alpha == 1)
        // its paint spread at 7: gone 0.1 s and the spec's 0.3 s after
        #expect(ring(7.1)?.alpha == 1 && fading.alpha < 1 && ring(7.4) == nil)
        // every ring is gone before the paints step ends, whichever its paint did
        let end = timeline.timing.start(2) + timeline.timing.step
        let late = try #require(ring(end - 0.2, spread: 99))
        #expect(ring(end, spread: 99) == nil && late.alpha < 1)
    }
}
