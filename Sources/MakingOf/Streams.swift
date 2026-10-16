import PaintCore

/// What a stream of the show's random draws is for. Each purpose and index (a step, a stroke, a
/// noise grid) has a stream of its own, so a draw count in one, such as a retry while sampling
/// spots, can never shift another. The planner keeps its own `SplitMix64(seed:)` (`CrewPlan`).
public enum ShowStream: UInt64, Sendable {
    case homes = 1, spots, noise, seeds, strokes
    /// The field show's (`FieldShow`): its purposes run from here on, one for each step and the
    /// last for its noise (`ShowStreams.field(_:)`).
    case fields = 16
}

/// The show's random streams, derived from its seed. `stream` in `making_of_pets.py` is the same,
/// bit for bit; both test suites pin the first draws of each purpose.
public struct ShowStreams: Sendable {
    public let seed: UInt64

    public init(seed: UInt64) { self.seed = seed }

    /// A generator seeded from the first draw of `seed ^ (purpose << 32 | index)`.
    public func stream(_ purpose: ShowStream, _ index: Int) -> SplitMix64 {
        stream(purpose: purpose.rawValue, index)
    }

    /// The field show's stream number `k` (`STREAM_FIELDS + k` in `making_of_fields.py`), index 0.
    func field(_ k: Int) -> SplitMix64 {
        precondition(k >= 0 && k < 1 << 16, "a field stream is one of a few")
        return stream(purpose: ShowStream.fields.rawValue + UInt64(k), 0)
    }

    private func stream(purpose: UInt64, _ index: Int) -> SplitMix64 {
        precondition(index >= 0 && index < 1 << 32, "a stream's index fits in 32 bits")
        var mixer = SplitMix64(seed: seed ^ (purpose << 32 | UInt64(index)))
        return SplitMix64(seed: mixer.next())
    }
}
