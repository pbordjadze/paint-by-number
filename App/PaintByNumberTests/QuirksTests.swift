#if UNRELEASED
import CoreGraphics
import SwiftUI
import Testing
@testable import PaintByNumber

/// Row 351's touches that can be checked off the screen: the moon's phases.
@MainActor
struct QuirksTests {
    private let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func lit(_ fraction: Double, _ x: CGFloat, _ y: CGFloat = 50) -> Bool {
        MoonPhase(fraction: fraction).path(in: rect).contains(CGPoint(x: x, y: y))
    }

    /// New, the moon shows nothing; full, the whole disc.
    @Test func aNewMoonIsDarkAndAFullOneWhole() {
        #expect(MoonPhase(fraction: 0).path(in: rect).isEmpty)
        #expect(lit(1, 50) && lit(1, 5) && lit(1, 95))
        #expect(!lit(1, 2, 2), "Past the disc")
    }

    /// A quarter of the way, a crescent on the trailing side; half, the trailing half; three
    /// quarters, everything but a crescent on the leading side.
    @Test func theMoonWaxesFromTheTrailingSide() {
        #expect(lit(0.25, 85) && !lit(0.25, 65) && !lit(0.25, 20))
        #expect(lit(0.5, 60) && lit(0.5, 95) && !lit(0.5, 40))
        #expect(lit(0.75, 30) && lit(0.75, 50) && !lit(0.75, 15))
    }

    /// More painted is never less moon.
    @Test func theLitShareGrowsWithTheFraction() {
        func share(_ fraction: Double) -> Int {
            let path = MoonPhase(fraction: fraction).path(in: rect)
            var count = 0
            for x in stride(from: 0.5, to: 100, by: 1) {
                for y in stride(from: 0.5, to: 100, by: 1) where path.contains(CGPoint(x: x, y: y)) { count += 1 }
            }
            return count
        }
        let shares = [0.1, 0.3, 0.5, 0.7, 0.9].map(share)
        #expect(shares == shares.sorted() && Set(shares).count == shares.count)
        // Half lit is about half the disc (π · 50² / 2).
        #expect(abs(Double(share(0.5)) - .pi * 2500 / 2) < 150)
    }
}
#endif
