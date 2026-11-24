// Off Apple platforms MakingOf imports FoundationEssentials rather than Foundation (the Android
// port; PaintCore's Portability.swift says why). The one piece of Foundation the show's spec uses
// that FoundationEssentials lacks, made as Foundation makes it; internal, as PaintCore's are.
#if canImport(FoundationEssentials) && !canImport(Darwin)
extension StringProtocol {
    /// Foundation's: the characters of `set` taken off both ends.
    func trimmingCharacters(in set: CharacterSet) -> String {
        let scalars = String(self).unicodeScalars
        guard let first = scalars.firstIndex(where: { !set.contains($0) }),
              let last = scalars.lastIndex(where: { !set.contains($0) }) else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }
}

/// Foundation's `whitespacesAndNewlines`, as CoreFoundation defines it.
struct CharacterSet: Sendable {
    static let whitespacesAndNewlines = CharacterSet()

    /// CoreFoundation's spaces (with the tab and U+200B) and newlines.
    func contains(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0xA0, 0x1680, 0x2000...0x200B, 0x202F, 0x205F, 0x3000: true
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
#endif
