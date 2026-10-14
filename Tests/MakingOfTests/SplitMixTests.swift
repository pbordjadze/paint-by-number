import PaintCore
import Testing
@testable import MakingOf

/// `SplitMix64` in `making_of_pets.py` makes the same draws, bit for bit: the numbers below are in
/// `tools/tests/test_making_of_pets.py` too.
@Suite struct SplitMixDrawsTests {
    @Test func publishedSeedZeroOutputs() {
        var rng = SplitMix64(seed: 0)
        #expect([rng.next(), rng.next(), rng.next()] == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F])
    }

    @Test func firstDoublesOfSeedOne() {
        var rng = SplitMix64(seed: 1)
        let doubles = (0..<5).map { _ in rng.nextDouble() }
        #expect(doubles == [0.5665615751722809, 0.7457817572627011, 0.9710027535867962, 0.4443592170557721, 0.44426470082635805])
    }

    @Test func uniformScalesADouble() {
        var rng = SplitMix64(seed: 1)
        let draws = (0..<3).map { _ in rng.uniform(0.6, 0.95) }
        #expect(draws == [0.7982965513102983, 0.8610236150419454, 0.9398509637553787])
    }

    @Test func boundedDrawsAndChoice() {
        var rng = SplitMix64(seed: 1)
        #expect((0..<8).map { _ in rng.below(10) } == [5, 9, 0, 5, 1, 8, 5, 3])
        rng = SplitMix64(seed: 1)
        let signs: [Int] = (0..<8).map { _ in rng.choice([-1, 1]) }
        #expect(signs == [1, 1, -1, 1, 1, -1, 1, 1])
    }

    @Test func permutationsShuffleFromTheBack() {
        var rng = SplitMix64(seed: 1)
        #expect(rng.permutation(8) == [4, 3, 2, 7, 5, 6, 0, 1])
        rng = SplitMix64(seed: 2)
        #expect(rng.permutation(3) == [2, 0, 1])
        #expect(rng.permutation(1) == [0])
        #expect(rng.permutation(0) == [])
    }
}

/// `numpy.interp`, whose rounding the planner's comparisons follow. The values come from numpy.
@Suite struct InterpTests {
    @Test func linesAndEnds() {
        let xp = [0.0, 10, 20]
        let fp = [0.0, 100, 50]
        #expect([5.0, 15, 25, -1, 10].map { interp($0, xp) { fp[$0] } } == [50, 75, 50, 0, 100])
    }

    @Test func repeatedPointsTakeTheLast() {
        let xp = [0.0, 1, 1, 2]
        let fp = [0.0, 10, 20, 30]
        #expect([1.0, 1.5, 0.3, 2].map { interp($0, xp) { fp[$0] } } == [20, 25, 3, 30])
    }

    @Test func unevenSteps() {
        let xp = [0.0, 0.3, 0.7]
        let fp = [1.0, 2.0, 4.0]
        #expect(interp(0.1, xp) { fp[$0] } == 1.3333333333333335)
        #expect(interp(0.5, xp) { fp[$0] } == 3)
    }
}
