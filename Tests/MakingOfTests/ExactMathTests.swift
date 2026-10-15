import Foundation
import Testing
@testable import MakingOf

/// `making_of_exact.py` makes the same bits; the numbers below are in
/// `tools/tests/test_making_of_inputs.py` too, which got them from numpy and Python.
@Suite struct ExactMathTests {
    @Test func halvesRoundToEven() {
        #expect([0.5, 1.5, 2.5, 3.5, -0.5, -1.5, 2.4999999999999996, 2.5000000000000004].map(ExactMath.halfEven) == [0, 2, 2, 4, 0, -2, 2, 3])
        // 0.0025 x 1600 x 640 / 1024 is 2.5: a 640 px wide picture's smoothing radius is 2, not 3
        #expect(ExactMath.halfEven(0.0025 * 1600 * 640 / 1024) == 2)
        #expect(ExactMath.halfEven(0.0025 * 1600 * 1024 / 1024) == 4)
    }

    @Test func quantizingRoundsHalvesToEven() {
        let cases: [(Double, Int, Double)] = [
            (0.125, 2, 0.12), (0.135, 2, 0.14), (2.675, 2, 2.68), (1.005, 2, 1.0), (109.12, 2, 109.12),
            (23.04000000000001, 2, 23.04), (0.00005, 4, 0.0), (0.00015, 4, 0.0001), (2.5, 0, 2), (3.5, 0, 4),
            (-0.125, 2, -0.12), (182.8284271247462, 2, 182.83),
        ]
        for (x, decimals, want) in cases {
            #expect(ExactMath.quantize(x, decimals: decimals) == want, "\(x) to \(decimals) places")
        }
    }

    @Test func cubeRootsSettle() {
        let cases: [(Double, Double)] = [
            (0, 0), (1.5e-05, 0.0246621207433047), (0.0003035269835488375, 0.06720461569746485), (0.125, 0.5),
            (0.5, 0.7937005259840998), (1, 1), (0.9999999999999999, 1),
        ]
        for (x, want) in cases { #expect(ExactMath.cbrt(x) == want, "cbrt \(x)") }
    }

    @Test func theCubeRootIsTheLibrarysWithinAFewUlps() {
        // over every linear value a byte can have, times the smallest and the largest matrix weight
        for linear in ExactMath.srgbLinear {
            for weight in [0.0514459929, 0.6806995451, 1] {
                let x = weight * linear
                #expect(abs(ExactMath.cbrt(x) - Foundation.cbrt(x)) <= 4 * Foundation.cbrt(x).ulp, "cbrt of \(x)")
            }
        }
    }

    @Test func oklabInDoubles() {
        let cases: [(UInt8, UInt8, UInt8, SIMD3<Double>)] = [
            (255, 255, 255, SIMD3(0.9999999934735462, 8.095285553011422e-11, 3.727390762708893e-08)),
            (0, 0, 0, SIMD3(0, 0, 0)),
            (128, 64, 32, SIMD3(0.4466302815957851, 0.06950253253477043, 0.07057777610311045)),
            (255, 0, 0, SIMD3(0.6279553606145516, 0.22486306106597398, 0.1258462985307351)),
            (12, 200, 99, SIMD3(0.7293647235901226, -0.16992373324084165, 0.09423908632120026)),
            (1, 1, 1, SIMD3(0.06720461525885703, 5.440366906972471e-12, 2.50497864812127e-09)),
        ]
        for (r, g, b, want) in cases { #expect(ExactMath.oklab(r, g, b) == want, "oklab \(r) \(g) \(b)") }
        let stretched = ExactMath.oklab(128, 64, 32, chroma: 1.6)
        #expect(stretched == SIMD3(0.4466302815957851, 0.06950253253477043 * 1.6, 0.07057777610311045 * 1.6))
    }

    @Test func theTransferTableIsTheTrueCurve() {
        #expect(ExactMath.srgbLinear.count == 256)
        // a literal that lost a digit shows in the sum, which Python added in the same order
        var sum = 0.0
        for v in ExactMath.srgbLinear { sum += v }
        #expect(sum == 79.619452444574)
        let pins: [(Int, Double)] = [
            (1, 0.0003035269835488375), (10, 0.003035269835488375), (100, 0.12743768043564743),
            (128, 0.21586050011389915), (200, 0.5775804404296505), (255, 1.0),
        ]
        for (i, want) in pins { #expect(ExactMath.srgbLinear[i] == want) }
    }

    @Test func boxSumsCountTheEdgeAgain() {
        let plane = Plane<Int>(width: 5, height: 4, data: [1, 0, 0, 2, 0, 0, 3, 1, 0, 0, 0, 0, 0, 5, 1, 4, 0, 1, 0, 2])
        #expect(ExactMath.boxSums(plane, radius: 1).data == [7, 6, 8, 5, 4, 5, 5, 11, 9, 9, 11, 9, 10, 10, 11, 16, 10, 7, 12, 15])
        #expect(ExactMath.boxSums(plane, radius: 2).data == [
            13, 21, 19, 17, 15, 23, 26, 23, 20, 20, 33, 31, 27, 23, 25, 43, 36, 31, 26, 30])
        // a window wider than the plane: every cell sees every row and column, the edges over and over
        #expect(ExactMath.boxSums(plane, radius: 5).data == [
            146, 135, 124, 113, 102, 167, 155, 143, 131, 119, 188, 175, 162, 149, 136, 209, 195, 181, 167, 153])
    }

    @Test func boxSumsOfASinglePixelPlane() {
        #expect(ExactMath.boxSums(Plane<UInt8>(width: 1, height: 1, data: [3]), radius: 2).data == [75])
    }

    @Test func percentilesInterpolateBetweenRanks() {
        #expect(ExactMath.percentile([5, 1, 4, 2, 3], percent: 95) == 4.8)
        #expect(ExactMath.percentile([5, 1, 4, 2, 3], percent: 50) == 3)
        #expect(ExactMath.percentile([7], percent: 95) == 7)
        #expect(ExactMath.percentile(Array(0...20), percent: 95) == 19)
        #expect(ExactMath.percentile(Array(repeating: 0, count: 19) + [100], percent: 95) == 5)
        #expect(ExactMath.percentile([3, 3, 3], percent: 95) == 3)
    }

    @Test func weightedPicksFindTheFirstEntryPastTheValue() {
        let cdf = ExactMath.cumulative([0, 0, 1, 0, 2, 0])
        #expect(cdf == [0, 0, 1, 1, 3, 3])
        let values: [Double] = [-1, 0, 0.5, 1, 2.9999999999999996, 3, 10]
        #expect(values.map { ExactMath.bisectRight(cdf, $0) } == [0, 2, 2, 4, 4, 6, 6])
        // a value strictly inside the total lands on an entry that has weight
        for u in [0.0, 0.25, 0.4999, 0.5, 0.75, 0.9999999999999999] {
            let weights = [0.0, 0, 1, 0, 2, 0]
            #expect(weights[ExactMath.bisectRight(cdf, u * 3)] > 0)
        }
    }

    @Test func sumsRunInOrder() {
        // 0.1 + 0.2 + 0.3 added one after the other, which a pairwise sum may not do
        #expect(ExactMath.cumulative([0.1, 0.2, 0.3]) == [0.1, 0.30000000000000004, 0.6000000000000001])
    }
}
