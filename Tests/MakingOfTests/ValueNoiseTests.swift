import PaintCore
import Testing
@testable import MakingOf

/// The noise grids and fields against `making_of_reveal.py` (`Fixtures/reveal-small.json`), which
/// is exact (`==`): a lattice is `nextDouble()` draws and a field only `+ - *`, so no library
/// rounds differently. Measured difference to the reference: 0.
@Suite struct ValueNoiseTests {
    private let fixture: RevealFixture

    init() throws { fixture = try RevealFixture.load() }

    @Test func latticesAreRowMajorDrawsFromTheNoiseStreams() {
        for (k, want) in fixture.expected.lattices.enumerated() {
            var coarse = fixture.streams.stream(.noise, 2 * k)
            var fine = fixture.streams.stream(.noise, 2 * k + 1)
            let broad = ValueNoise.lattice(cellsX: 18, cellsY: 12, using: &coarse)
            let grain = ValueNoise.lattice(cellsX: 60, cellsY: 40, using: &fine)
            #expect(broad.count == 13 * 19 && grain.count == 41 * 61)
            #expect(Array(broad.prefix(3)) == want.coarse.first, "step \(k) coarse")
            #expect(Array(grain.prefix(3)) == want.fine.first, "step \(k) fine")
            #expect(fingerprint(broad) == want.coarse.fingerprint, "step \(k) coarse")
            #expect(fingerprint(grain) == want.fine.fingerprint, "step \(k) fine")
        }
    }

    @Test func aLatticeDrawsFromItsOwnStreamOnly() {
        var a = fixture.streams.stream(.noise, 3)
        var b = fixture.streams.stream(.noise, 3)
        _ = ValueNoise.lattice(cellsX: 60, cellsY: 40, using: &a)
        let first = b.nextDouble()
        var c = fixture.streams.stream(.noise, 3)
        #expect(first == c.nextDouble())
        var other = fixture.streams.stream(.noise, 2)
        #expect(other.nextDouble() != first, "steps do not share draws")
    }

    @Test func stepNoiseMatchesTheReference() {
        let (w, h) = (fixture.width, fixture.height)
        for (k, want) in fixture.expected.noise.enumerated() {
            let plane = StepNoise(step: k, width: w, height: h, streams: fixture.streams).plane()
            #expect(samples(plane, every: fixture.inputs.sampling) == want.samples, "step \(k)")
            #expect(fingerprint(plane.data) == want.fingerprint, "step \(k)")
        }
    }

    @Test func aFieldPassesThroughTheLatticeAtItsNodes() {
        var rng = SplitMix64(seed: 5)
        let noise = ValueNoise(cellsX: 6, cellsY: 4, width: 24, height: 16, using: &rng)
        // pixels 4 columns and 4 rows apart sit exactly on lattice nodes
        for j in 0...3 {
            for i in 0...5 {
                #expect(noise[4 * i, 4 * j] == noise.lattice[j * 7 + i])
            }
        }
    }

    @Test func aFieldStaysInsideItsLatticeAndEasesInsideACell() {
        var rng = SplitMix64(seed: 9)
        let noise = ValueNoise(cellsX: 18, cellsY: 12, width: 200, height: 130, using: &rng)
        let low = noise.lattice.min()!, high = noise.lattice.max()!
        for y in 0..<130 {
            for x in 0..<200 {
                let v = noise[x, y]
                #expect(v >= low && v <= high)
            }
        }
        // one cell, 0 and 1 down the left and right edges: smoothstep of the way across
        let cell = ValueNoise(lattice: [0, 1, 0, 1], cellsX: 1, cellsY: 1, width: 4, height: 1)
        #expect([0, 1, 2, 3].map { cell[$0, 0] } == [0, 0.15625, 0.5, 0.84375])
    }

    @Test func aFieldIsDeterministicWhateverIsBuiltAround() {
        var a = SplitMix64(seed: 11)
        var b = SplitMix64(seed: 11)
        let one = ValueNoise(cellsX: 5, cellsY: 3, width: 37, height: 29, using: &a)
        let two = ValueNoise(cellsX: 5, cellsY: 3, width: 37, height: 29, using: &b)
        #expect(one.plane() == two.plane())
    }
}
