import Foundation
import Testing
@testable import PaintCore

/// Watercolor's Making Of (painting-company row 373): every area painted once, light to dark,
/// played by the real simulation to a dry, finished painting, the same every time.
@Suite struct WatercolorMakingOfTests {
    static let template = WatercolorTests.template

    @Test func everyAreaOnceLightToDark() {
        let t = Self.template
        let sheet = WatercolorSheet(template: t, seed: 3)
        let plan = WatercolorMakingOf(template: t, sheet: sheet)
        let painted = plan.log.taps.filter(\.paint)
        #expect(painted.map(\.region).sorted() == Array(t.regions.indices))
        // The blooms: water alone, into areas already laid.
        let blooms = plan.log.taps.filter { !$0.paint }
        #expect(blooms.count <= WatercolorMakingOf.blooms)
        for bloom in blooms {
            #expect(painted.contains { $0.region == bloom.region && $0.step < bloom.step })
        }
        #expect(zip(plan.log.taps, plan.log.taps.dropFirst()).allSatisfy { $0.step <= $1.step })
        // The signature paints open it: saturated, a few paints, all down within half a second.
        #expect(plan.signatures.count <= WatercolorMakingOf.signatureCount * WatercolorMakingOf.signatureAreas)
        #expect(Set(plan.signatures.map { t.regions[$0].colorIndex }).count <= WatercolorMakingOf.signatureCount)
        for r in plan.signatures {
            let lab = t.palette[Int(t.regions[r].colorIndex)].oklab
            #expect((lab.y * lab.y + lab.z * lab.z).squareRoot() >= WatercolorMakingOf.signatureChroma)
            #expect(painted.contains { $0.region == r && Float($0.step) * WatercolorSim.dt <= 0.5 + 1e-3 })
        }
        // The darkest areas come after the lightest.
        let darkness = sheet.want.map { ($0.x + $0.y + $0.z) / 3 }
        let n = plan.log.taps.count
        func mean(_ taps: ArraySlice<WatercolorLog.Tap>) -> Float {
            taps.map { darkness[$0.region] }.reduce(0, +) / Float(max(taps.count, 1))
        }
        #expect(mean(painted.prefix(painted.count / 4)) < mean(painted.suffix(painted.count / 4)))
        // Every tap is one the painter's own log would accept.
        let read = try? WatercolorLog(encoded: plan.log.encoded(), regions: t.regions.count, width: t.width, height: t.height)
        #expect(read?.taps.count == n)
    }

    @Test func itPlaysToTheFinishedPaintingAndAgain() {
        let t = Self.template
        func play() -> (WatercolorSim, Int) {
            let sheet = WatercolorSheet(template: t, seed: 5)
            let plan = WatercolorMakingOf(template: t, sheet: sheet)
            let sim = WatercolorSim(sheet: sheet)
            var cursor = 0, frame = 0
            while !plan.isSettled(sim, cursor: cursor), frame < 2000 {
                plan.play(sim, to: plan.step(at: Double(frame) / 30), cursor: &cursor)
                frame += 1
            }
            return (sim, frame)
        }
        let (sim, frames) = play()
        #expect(sim.laidCount == t.regions.count)
        // A short film: well under the ten seconds a painter would sit through.
        #expect(Double(frames) / 30 < 10)
        #expect(WatercolorTests.digest(play().0) == WatercolorTests.digest(sim))
        // What is still damp when it settles dries on to the finished painting.
        sim.finish()
        #expect(!sim.isActive)
    }

    @Test func theClockRunsForwardAndHurriesTheDrying() {
        let t = Self.template
        let plan = WatercolorMakingOf(template: t, sheet: WatercolorSheet(template: t, seed: 1))
        let steps = stride(from: 0.0, to: 12, by: 0.05).map { plan.step(at: $0) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(plan.step(at: 0) < 30)  // the first wash under way at once
        let early = plan.step(at: 1) - plan.step(at: 0)
        let late = plan.step(at: 11) - plan.step(at: 10)
        #expect(late > 3 * early)
        #expect(plan.pencilFade(at: 0) == 0)
        #expect(plan.pencilFade(at: 1000) == 1)
        // The drying front: the whole sheet ahead of it until the last tap, behind it at the end.
        let lastTap = Float(plan.lastTapStep) * WatercolorSim.dt
        #expect(plan.dryingFront(at: 0) == -WatercolorMakingOf.frontWidth)
        #expect(plan.dryingFront(at: lastTap + 1) < plan.dryingFront(at: lastTap + 2))
        #expect(plan.dryingFront(at: 1000) == 1 + WatercolorMakingOf.frontWidth)
    }
}
