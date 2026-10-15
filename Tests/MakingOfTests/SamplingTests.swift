import PaintCore
import Testing
@testable import MakingOf

/// `sample_stops` and `kmeanspp` in `making_of_inputs.py` make the same picks from the same
/// streams, and leave the stream where the Python leaves it (the next double is pinned too): the
/// cases and numbers are in `tools/tests/test_making_of_inputs.py` too.
@Suite struct SamplingTests {
    private func spots(_ s: [Spot]) -> [[Int]] { s.map { [$0.x, $0.y] } }

    /// Weights `(x * 7 + y * 3) % 5`, zero in a fifth of the cells.
    private static func patterned(_ width: Int, _ height: Int) -> [Double] {
        (0..<height).flatMap { y in (0..<width).map { x in Double((x * 7 + y * 3) % 5) } }
    }

    @Test func spotsAreDrawnByWeight() {
        var rng = ShowStreams(seed: 7).stream(.spots, 3)
        let picks = Sampling.sampleStops(weights: Self.patterned(12, 8), width: 12, count: 4, spacing: 3, rng: &rng)
        #expect(spots(picks) == [[9, 0], [6, 7], [3, 4], [11, 7]])
        #expect(rng.nextDouble() == 0.5976137899796332)
        for pick in picks { #expect(Self.patterned(12, 8)[pick.y * 12 + pick.x] > 0, "a spot has weight") }
        var other = ShowStreams(seed: 8).stream(.spots, 3)
        #expect(spots(Sampling.sampleStops(weights: Self.patterned(12, 8), width: 12, count: 4, spacing: 3, rng: &other))
                == [[1, 4], [6, 7], [4, 0], [9, 2]])
    }

    @Test func spotsKeepTheirDistance() {
        var rng = ShowStreams(seed: 7).stream(.spots, 0)
        let picks = Sampling.sampleStops(weights: Array(repeating: 1, count: 40 * 30), width: 40, count: 8, spacing: 6, rng: &rng)
        #expect(picks.count == 8)
        for (i, a) in picks.enumerated() {
            for b in picks[(i + 1)...] { #expect(Double((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)) >= 36) }
        }
    }

    @Test func aPlaneWithoutWeightIsDrawnFromUniformly() {
        var rng = ShowStreams(seed: 7).stream(.spots, 1)
        let picks = Sampling.sampleStops(weights: Array(repeating: 0, count: 24), width: 6, count: 3, spacing: 2, rng: &rng)
        #expect(spots(picks) == [[1, 2], [1, 0], [3, 3]])
        #expect(rng.nextDouble() == 0.13580693283067147)
    }

    @Test func fewerSpotsThanAskedAreWhatThereIs() {
        // one cell with weight: the spacing can never be met twice, nor the draws find a second cell
        var weights = [Double](repeating: 0, count: 30)
        weights[3] = 1e-300
        weights[27] = 5
        var rng = ShowStreams(seed: 7).stream(.spots, 0)
        #expect(spots(Sampling.sampleStops(weights: weights, width: 6, count: 2, spacing: 2, rng: &rng)) == [[3, 4]])
        #expect(rng.nextDouble() == 0.3435327290593786)
        // more spots than cells: every cell, once the spacing has relaxed to nothing
        var crowded = ShowStreams(seed: 7).stream(.homes, 0)
        let all = Sampling.sampleStops(weights: Array(repeating: 1, count: 25), width: 5, count: 30, spacing: 1, rng: &crowded)
        #expect(all.count == 25 && Set(all).count == 25)
        #expect(spots(Array(all.prefix(6))) == [[4, 4], [1, 3], [4, 2], [0, 4], [0, 3], [1, 2]])
        #expect(crowded.nextDouble() == 0.47896738244214165)
    }

    @Test func noSpotsAskedDrawsNothing() {
        var rng = ShowStreams(seed: 7).stream(.homes, 0)
        #expect(Sampling.sampleStops(weights: Array(repeating: 1, count: 25), width: 5, count: 0, spacing: 2, rng: &rng).isEmpty)
        #expect(rng.nextDouble() == 0.7824150874829743)
    }
}

@Suite struct PaintSeedsTests {
    private static let lab: [SIMD3<Double>] = [
        SIMD3(0.1, 0, 0), SIMD3(0.9, 0.1, 0), SIMD3(0.5, -0.3, 0.2), SIMD3(0.52, -0.31, 0.2),
        SIMD3(0.2, 0.4, -0.1), SIMD3(0.95, 0.12, 0.01), SIMD3(0.11, 0.01, 0), SIMD3(0.3, 0.3, 0.3),
    ]

    @Test func seedsSpreadOverTheColors() {
        var rng = ShowStreams(seed: 7).stream(.seeds, 0)
        #expect(PaintSeeds.kmeansPlusPlus(Self.lab, count: 4, rng: &rng) == [3, 5, 0, 7])
        #expect(rng.nextDouble() == 0.24725284440123863)
    }

    @Test func rowsThatAreAlreadySeedsTwinsAreDrawnUniformly() {
        var rng = ShowStreams(seed: 7).stream(.seeds, 0)
        let same = [SIMD3<Double>](repeating: SIMD3(0.4, 0.1, 0.2), count: 5)
        #expect(PaintSeeds.kmeansPlusPlus(same, count: 3, rng: &rng) == [3, 2, 1])
        #expect(rng.nextDouble() == 0.9660511963580937)
    }

    @Test func noMoreSeedsThanRows() {
        var rng = ShowStreams(seed: 7).stream(.seeds, 0)
        #expect(PaintSeeds.kmeansPlusPlus(Array(Self.lab.prefix(3)), count: 6, rng: &rng) == [2, 1, 0])
        #expect(rng.nextDouble() == 0.9660511963580937)
        var empty = ShowStreams(seed: 7).stream(.seeds, 0)
        #expect(PaintSeeds.kmeansPlusPlus([], count: 6, rng: &empty).isEmpty)
        #expect(empty.nextDouble() == 0.5056482214915431)
    }

    @Test func theSmallPicturesPaintsAreItsDistinctColors() throws {
        let small = try SmallShow()
        let paints = try PaintColors(palette: small.pictures.palette)
        #expect(paints.keys == small.expected.paints)
        #expect(paints.keys == paints.keys.sorted() && Set(paints.keys).count == paints.keys.count)
        for (i, c) in small.pictures.palette.data.enumerated() {
            #expect(paints.keys[Int(paints.index.data[i])] == ExactMath.colorKey(c))
        }
        #expect(paints.rgb(0) == SIMD3((paints.keys[0] >> 16 & 255).asByte, (paints.keys[0] >> 8 & 255).asByte, (paints.keys[0] & 255).asByte))
    }

    @Test func theSmallPicturesSeedsReplay() throws {
        let small = try SmallShow()
        let paints = try PaintColors(palette: small.pictures.palette)
        var rng = ShowStreams(seed: SmallShow.seed).stream(.seeds, 0)
        let seeds = PaintSeeds.seeds(
            smoothed: small.pictures.smoothed, paints: paints, rng: &rng,
            start: small.spec.timing.intro + 2 * small.spec.timing.step, dropEvery: small.spec.seeds.dropEvery)
        #expect(seeds == small.expected.paintSeeds)
        #expect(seeds.count == paints.keys.count)
        // each seed is a pixel of the grid, and lands in time order
        #expect(seeds.map(\.time) == seeds.map(\.time).sorted())
        for s in seeds { #expect(s.paint >= 0 && s.paint < paints.keys.count) }
    }
}

private extension UInt32 {
    var asByte: UInt8 { UInt8(self) }
}
