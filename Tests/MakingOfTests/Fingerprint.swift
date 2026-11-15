import Foundation
@testable import MakingOf

/// FNV-1a (64 bit) over the IEEE bytes of `values`, least significant first, as 16 hex digits:
/// `fingerprint` in `making_of_reveal.py`.
func fingerprint(_ values: some Sequence<Double>) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for value in values {
        var bits = value.bitPattern
        for _ in 0..<8 {
            hash = (hash ^ (bits & 0xFF)) &* 0x100_0000_01B3
            bits >>= 8
        }
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - hex.count) + hex
}

func fingerprint(_ points: [Point]) -> String {
    fingerprint(points.flatMap { [$0.x, $0.y] })
}
