// Off Apple platforms PaintCore imports FoundationEssentials rather than Foundation (the Android
// port: Foundation brings ICU's data, 40 MB per ABI, which nothing here reads). These are the few
// pieces of Foundation the pipeline uses that FoundationEssentials lacks, each made as Foundation
// makes it, so Linux and Android give the same bytes as before. Internal, so a module that imports
// Foundation beside PaintCore sees only Foundation's. Apple platforms keep Foundation itself.
#if canImport(FoundationEssentials) && !canImport(Darwin)
import Synchronization

extension String {
    /// Foundation's `String(format:)` for the formats used here (`%f`, `%X`, `%d`, with widths and
    /// precisions): the C library's printf, in the C locale, as Foundation's formatter does them.
    /// Generic so that, where Foundation's is in sight too (a test's `@testable import`), Foundation's
    /// non-generic one is the better match rather than an ambiguous one.
    init(format: some StringProtocol, _ arguments: CVarArg...) {
        let format = String(format)
        let count = withVaList(arguments) { vsnprintf(nil, 0, format, $0) }
        guard count > 0 else {
            self = ""
            return
        }
        var bytes = [CChar](repeating: 0, count: Int(count) + 1)
        _ = bytes.withUnsafeMutableBufferPointer { buffer in
            withVaList(arguments) { vsnprintf(buffer.baseAddress, buffer.count, format, $0) }
        }
        self = String(decoding: bytes.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

extension StringProtocol {
    /// Foundation's, with a plain search: every occurrence of `target`, left to right.
    func replacingOccurrences(of target: String, with replacement: String) -> String {
        String(self).replacing(target, with: replacement)
    }

    /// Foundation's: the pieces between occurrences of `separator`, empty ones kept.
    func components(separatedBy separator: String) -> [String] {
        String(self).split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }

    /// Foundation's: the characters of `set` taken off both ends.
    func trimmingCharacters(in set: CharacterSet) -> String {
        let scalars = String(self).unicodeScalars
        guard let first = scalars.firstIndex(where: { !set.contains($0) }),
              let last = scalars.lastIndex(where: { !set.contains($0) }) else { return "" }
        return String(String.UnicodeScalarView(scalars[first...last]))
    }
}

/// The two of Foundation's character sets used here, as CoreFoundation defines them.
struct CharacterSet: Sendable {
    private let test: @Sendable (Unicode.Scalar) -> Bool

    func contains(_ scalar: Unicode.Scalar) -> Bool { test(scalar) }

    /// Unicode's control and format characters (general categories Cc and Cf).
    static let controlCharacters = CharacterSet { scalar in
        switch scalar.properties.generalCategory {
        case .control, .format: true
        default: false
        }
    }

    /// CoreFoundation's spaces (with the tab and U+200B) and newlines.
    static let whitespacesAndNewlines = CharacterSet { scalar in
        switch scalar.value {
        case 0x20, 0x09, 0xA0, 0x1680, 0x2000...0x200B, 0x202F, 0x205F, 0x3000: true
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}

/// The lock PaintCore's shared state takes, as Foundation's `NSLock` is used (`withLock`); named
/// apart from it, since a test's `@testable import` sees both.
final class Lock: Sendable {
    private let mutex = Mutex(())

    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        try mutex.withLock { _ in try body() }
    }
}
#else
import Foundation

/// Foundation's lock, under the name PaintCore gives the one it makes off Apple platforms.
typealias Lock = NSLock
#endif
