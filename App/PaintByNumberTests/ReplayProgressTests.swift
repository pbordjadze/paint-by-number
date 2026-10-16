import Foundation
import Testing
@testable import PaintByNumber

/// What a replay tells the progress badge: how many areas are on the canvas at each moment.
struct ReplayProgressTests {
    @Test func theLiftTakesTheAreasOffAsItGoes() {
        #expect(ReplayProgress.lifting(total: 100, elapsed: 0, lift: 0.5) == 100)
        #expect(ReplayProgress.lifting(total: 100, elapsed: 0.25, lift: 0.5) == 50)
        #expect(ReplayProgress.lifting(total: 100, elapsed: 0.5, lift: 0.5) == 0)
        #expect(ReplayProgress.lifting(total: 100, elapsed: 3, lift: 0.5) == 0, "past its end")
        #expect(ReplayProgress.lifting(total: 100, elapsed: -1, lift: 0.5) == 100, "before it began")
        #expect(ReplayProgress.lifting(total: 100, elapsed: 0, lift: 0) == 0, "no lift under Reduce Motion: the paint is gone at once")
        let counts = (0...50).map { ReplayProgress.lifting(total: 37, elapsed: Float($0) / 100, lift: 0.5) }
        #expect(counts.first == 37 && counts.last == 0)
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 >= $1 }, "the paint never comes back while it lifts")
    }

    @Test func theAreasComeBackOneEveryStepTheFirstAtOnce() {
        #expect(ReplayProgress.filling(total: 10, elapsed: 0, step: 0.5) == 1)
        #expect(ReplayProgress.filling(total: 10, elapsed: 0.49, step: 0.5) == 1)
        #expect(ReplayProgress.filling(total: 10, elapsed: 0.5, step: 0.5) == 2)
        #expect(ReplayProgress.filling(total: 10, elapsed: 4.5, step: 0.5) == 10)
        #expect(ReplayProgress.filling(total: 10, elapsed: 99, step: 0.5) == 10, "never more than the painting has")
        #expect(ReplayProgress.filling(total: 10, elapsed: -1, step: 0.5) == 0, "before the fills begin")
        #expect(ReplayProgress.filling(total: 0, elapsed: 1, step: 0.5) == 0)
        #expect(ReplayProgress.filling(total: 10, elapsed: 1, step: 0) == 0, "no step, no schedule")
    }
}
