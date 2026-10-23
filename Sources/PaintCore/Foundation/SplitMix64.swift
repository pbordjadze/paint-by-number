/// Small, fast, deterministic PRNG (SplitMix64): the pipeline's only random source (palette
/// seeding, Auto's analysis, nickname draws).
///
/// Its constants, `next()` and `nextFloat`'s 24-bit conversion are frozen: they are part of the
/// deterministic output, and of the nickname formats (`ColorNickname`'s v1 and v2 draws), which
/// paintings derive at every load from their artwork id whatever pipeline made them, so no
/// `pipelineVersion` bump would keep their names. A pipeline that needs another generator adds a
/// type of its own.
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
