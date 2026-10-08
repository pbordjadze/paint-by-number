import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// Refine's geometry: the pen's line smoothed and thinned, and the line a tap of the eraser takes.
struct RefineGeometryTests {
    /// A shaky line comes out smooth, from its first point to its last, and thinned to fewer
    /// points; a straight one to its two ends.
    @Test func penLinesAreSmoothedAndThinned() {
        let shaky = (0...40).map { CGPoint(x: CGFloat($0) * 5, y: $0 % 2 == 0 ? 0 : 1.5) }
        let smooth = PenPath.smoothed(shaky, spacing: 2)
        #expect(smooth.first == shaky.first && smooth.last == shaky.last)
        // Away from its ends the wobble is averaged out: no point strays as far as the samples did.
        #expect(smooth.filter { $0.x > 20 && $0.x < 180 }.allSatisfy { $0.y > 0.2 && $0.y < 1.3 })
        let thin = PenPath.simplified(smooth, tolerance: 0.5)
        #expect(thin.count < smooth.count && thin.first == smooth.first && thin.last == smooth.last)
        let straight = (0...20).map { CGPoint(x: CGFloat($0) * 3, y: CGFloat($0) * 2) }
        #expect(PenPath.simplified(PenPath.smoothed(straight, spacing: 2), tolerance: 0.3).count == 2)
        #expect(abs(PenPath.length(straight) - hypot(60, 40)) < 1e-6)
    }

    /// A tap takes the line under it on through every joint where just one other line goes on,
    /// and stops where three lines meet or a line ends; a loop comes back to where it started;
    /// nothing is taken where no line is near.
    @Test func tappedLinesRunFromJunctionToJunction() throws {
        func line(_ points: [SIMD2<Float>]) -> LineArtDrawing.Line { LineArtDrawing.Line(points[...])! }
        // Two lines end to end, meeting two more where three meet; one apart.
        let chains = LineChains(lines: [
            line([SIMD2(0, 0), SIMD2(10, 0)]), line([SIMD2(20, 0), SIMD2(10, 0)]),
            line([SIMD2(20, 0), SIMD2(20, 10)]), line([SIMD2(20, 0), SIMD2(30, 0)]),
            line([SIMD2(0, 20), SIMD2(30, 20)]),
        ])
        let joined = try #require(chains.chain(near: CGPoint(x: 5, y: 1), tolerance: 3))
        #expect(joined == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)])
        let branch = try #require(chains.chain(near: CGPoint(x: 21, y: 6), tolerance: 3))
        #expect(branch == [CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 10)])
        let apart = try #require(chains.chain(near: CGPoint(x: 12, y: 19), tolerance: 3))
        #expect(apart == [CGPoint(x: 0, y: 20), CGPoint(x: 30, y: 20)])
        #expect(chains.chain(near: CGPoint(x: 10, y: 10), tolerance: 3) == nil)

        let loop = LineChains(lines: [
            line([SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10)]), line([SIMD2(10, 10), SIMD2(0, 10), SIMD2(0, 0)]),
        ])
        let ring = try #require(loop.chain(near: CGPoint(x: 5, y: 0.5), tolerance: 2))
        #expect(ring.count == 5 && ring.first == ring.last)
    }
}
