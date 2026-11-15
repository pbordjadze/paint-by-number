import Testing
@testable import MakingOf

/// The same case as `RegionTests` in `tools/tests/test_making_of_reveal.py`.
@Suite struct ArrivalTests {
    @Test func regionMinimumTakesTheEarliestPixelOfEachRegion() {
        let times = Plane(width: 4, height: 2, data: [5.0, 3, 9, 1, 4, 8, 2, 7])
        let labels = Plane<Int32>(width: 4, height: 2, data: [0, 0, 1, 1, 0, 2, 2, 1])
        #expect(Arrival.regionMinimum(times, labels: labels, count: 4) == [3, 1, 2, .infinity])
    }
}
