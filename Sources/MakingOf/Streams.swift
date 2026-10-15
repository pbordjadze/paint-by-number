import PaintCore

/// What a stream of the show's random draws is for. Each purpose and index (a step, a stroke, a
/// noise grid) has a stream of its own, so a draw count in one, such as a retry while sampling
/// spots, can never shift another. The planner keeps its own `SplitMix64(seed:)` (`CrewPlan`).
public enum ShowStream: UInt64, Sendable {
    case homes = 1, spots, noise, seeds, strokes
}

/// The show's random streams, derived from its seed. `stream` in `making_of_pets.py` is the same,
/// bit for bit; both test suites pin the first draws of each purpose.
public struct ShowStreams: Sendable {
    public let seed: UInt64

    public init(seed: UInt64) { self.seed = seed }

    /// A generator seeded from the first draw of `seed ^ (purpose << 32 | index)`.
    public func stream(_ purpose: ShowStream, _ index: Int) -> SplitMix64 {
        precondition(index >= 0 && index < 1 << 32, "a stream's index fits in 32 bits")
        var mixer = SplitMix64(seed: seed ^ (purpose.rawValue << 32 | UInt64(index)))
        return SplitMix64(seed: mixer.next())
    }
}
