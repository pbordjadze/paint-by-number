// Offline provenance/check tool, never part of a shipped target. Build PaintCore, then:
// swiftc -I <build>/debug/Modules tools/nickname_anchors.swift <build>/debug/PaintCore.build/*.o -o <scratch>/anchors
// <scratch>/anchors > <scratch>/anchors.swift
// Captured on Linux Swift 6.2 for v2. Do not regenerate shipped constants on another libm;
// the tests freeze their exact values and check proximity to the original hex anchors.
import Foundation
import PaintCore

print("extension ColorNicknameV2 {")
print("    // Generated once from v1 on Linux Swift 6.2; tools/nickname_anchors.swift records the recipe.")
print("    // Signed Q16 OKLab, rounded to nearest, ties away from zero; table order is frozen.")
print("    static let anchors: [SIMD3<Int64>] = [")
for entry in ColorNickname.Vocabulary(version: 1).entries {
    let q = [entry.oklab.x, entry.oklab.y, entry.oklab.z].map { Int64((Double($0) * 65536).rounded()) }
    print("        SIMD3(\(q[0]), \(q[1]), \(q[2])), // \(String(format: "%06X", entry.hex))")
}
print("    ]")
print("}")
