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

/// `stream` in `making_of_pets.py` derives the same generators: these numbers are in
/// `tools/tests/test_making_of_pets.py` too.
@Suite struct ShowStreamsTests {
    @Test func eachPurposeHasItsOwnStream() {
        let streams = ShowStreams(seed: 7)
        let pins: [(ShowStream, Int, [Double])] = [
            (.homes, 0, [0.7824150874829743, 0.024802976027635926, 0.8992068202961797]),
            (.spots, 5, [0.6750960295029587, 0.04260565902968305, 0.2721234946036929]),
            (.noise, 11, [0.07621336553267122, 0.8016695796850121, 0.6890799999388426]),
            (.seeds, 0, [0.5056482214915431, 0.5501754934418699, 0.13723743402324384]),
            (.strokes, 332, [0.9854077396862709, 0.22682682046334635, 0.8518463187733157]),
        ]
        for (purpose, index, doubles) in pins {
            var rng = streams.stream(purpose, index)
            #expect((0..<3).map { _ in rng.nextDouble() } == doubles, "\(purpose) \(index)")
        }
    }
}

@Suite struct PlaneTests {
    @Test func rowMajorFromTheTopLeft() {
        var plane = Plane(width: 3, height: 2, repeating: 0)
        plane[2, 1] = 7
        #expect(plane.data == [0, 0, 0, 0, 0, 7])
        #expect(plane == Plane(width: 3, height: 2, data: [0, 0, 0, 0, 0, 7]))
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
