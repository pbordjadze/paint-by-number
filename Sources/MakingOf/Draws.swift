import PaintCore

/// The draws the crew needs from PaintCore's `SplitMix64`, which stays as it is. `SplitMix64` in
/// `making_of_pets.py` has the same ones, bit for bit; both test suites pin the first values of
/// seed 1. Taking `next() % n` for a bounded draw is biased by about n / 2^64: nothing here can
/// tell.
extension SplitMix64 {
    /// A double in [0, 1): the top 53 bits of `next()`.
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    mutating func uniform(_ a: Double, _ b: Double) -> Double {
        a + (b - a) * nextDouble()
    }

    /// An integer in [0, n), for n > 0.
    mutating func below(_ n: Int) -> Int {
        Int(next() % UInt64(n))
    }

    /// 0..<n shuffled (Fisher-Yates, from the back).
    mutating func permutation(_ n: Int) -> [Int] {
        var out = Array(0..<max(n, 0))
        for i in stride(from: n - 1, to: 0, by: -1) {
            out.swapAt(i, below(i + 1))
        }
        return out
    }

    /// One of `items`, which must not be empty.
    mutating func choice<T>(_ items: [T]) -> T {
        items[below(items.count)]
    }
}
