/// Small, fast, deterministic PRNG (SplitMix64): the pipeline's only random source (palette
/// seeding, Auto's analysis, nickname draws).
///
/// Its constants, `next()` and `nextFloat`'s 24-bit conversion are part of the deterministic
/// output and of the color names saved paintings show, so change them only with a
/// `TemplateGenerator.pipelineVersion` bump, knowing it renames nicknames.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform float in [0, 1).
    public mutating func nextFloat() -> Float {
        Float(next() >> 40) * (1.0 / Float(1 << 24))
    }
}
