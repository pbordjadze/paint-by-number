// Off Apple platforms MosaicCore imports FoundationEssentials rather than Foundation (the Android
// port; PaintCore's Portability.swift says why). The pieces of Foundation the stone book uses that
// FoundationEssentials lacks, made as Foundation makes them; internal, as PaintCore's are.
#if canImport(FoundationEssentials) && !canImport(Darwin)
extension String {
    /// Foundation's `String(format:)` for the formats used here (`%f`, `%x`, with widths and
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

    /// Foundation's, with a plain search: every occurrence of `target`, left to right.
    func replacingOccurrences(of target: String, with replacement: String) -> String {
        replacing(target, with: replacement)
    }
}
#endif
