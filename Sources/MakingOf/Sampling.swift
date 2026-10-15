import PaintCore

/// A pixel of a plane, where a guardian works or a seed lands.
struct Spot: Sendable, Hashable {
    var x: Int
    var y: Int
}

enum Sampling {
    /// Rounds of draws before `sampleStops` settles for fewer spots than it was asked for.
    static let patience = 40
    /// What a round that came up short keeps of the spacing.
    static let relax = 0.85

    /// `count` spots in a plane `width` wide, drawn by `weights` (row-major, non-negative), no two
    /// closer than `spacing`: `sample_stops` in `making_of_inputs.py`, draw for draw.
    ///
    /// Each round takes `count * 30` numbers from `rng`, finds for each the spot whose running
    /// weight first passes `u * total`, and keeps those far enough from the ones kept. A round that
    /// comes up short starts over with the spacing relaxed, and after `patience` rounds the last
    /// round's spots are what there is (always at least one). A plane with no weight is drawn from
    /// as if every cell weighed the same.
    static func sampleStops(weights: [Double], width: Int, count: Int, spacing: Double, rng: inout SplitMix64) -> [Spot] {
        precondition(width > 0 && weights.count % width == 0, "weights fill whole rows")
        guard count > 0, !weights.isEmpty else { return [] }
        var cdf = ExactMath.cumulative(weights)
        var total = cdf[cdf.count - 1]
        if !(total > 0) {
            cdf = (1...cdf.count).map(Double.init)
            total = Double(cdf.count)
        }
        var spacing = spacing
        var picks: [Spot] = []
        for _ in 0..<patience {
            let draws = (0..<count * 30).map { _ in rng.nextDouble() }
            picks = []
            let apart = spacing * spacing
            for u in draws {
                let (y, x) = ExactMath.bisectRight(cdf, u * total).quotientAndRemainder(dividingBy: width)
                if picks.allSatisfy({ Double(($0.x - x) * ($0.x - x) + ($0.y - y) * ($0.y - y)) >= apart }) {
                    picks.append(Spot(x: x, y: y))
                    if picks.count == count { return picks }
                }
            }
            spacing *= relax
        }
        return picks
    }
}
