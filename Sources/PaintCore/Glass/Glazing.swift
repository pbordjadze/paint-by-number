import Foundation

/// Which glass is in each piece of a Stained Glass window (painting-company row 366): free
/// glazing, any glass in any piece (Paul, November 20, 2026), so the choice is the painter's and
/// lives beside the painting's progress, which still says which pieces are glazed and when
/// (`glazing.bin` beside `progress.bin`). A glass is named by its place in
/// `GlassPalette.offered(for:)`; `none` is a piece not glazed.
///
/// The file is read as hostile input: magic `PBGL`, a format version, the piece count, then one
/// `Int16` a piece. Fields are only ever appended (readers ignore trailing bytes); bump
/// `formatVersion` only when an existing field changes meaning. A glass past what the window
/// offers reads as none, never as another glass.
public struct Glazing: Sendable, Equatable {
    public static let none: Int16 = -1
    public static let magic: UInt32 = 0x4C47_4250 // "PBGL", little-endian
    public static let formatVersion: UInt32 = 1

    public enum CodingError: Error, Equatable {
        case corrupt
        case newerVersion(UInt32)
        /// The file is for a window with another number of pieces.
        case otherWindow
    }

    /// Per piece, its glass's place in the offered glasses, or `none`.
    public var glass: [Int16]

    public init(pieces: Int) { glass = Array(repeating: Self.none, count: max(0, pieces)) }

    public var glazedCount: Int { glass.reduce(0) { $0 + ($1 == Self.none ? 0 : 1) } }

    public func encoded() -> Data {
        var data = Data()
        func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(Self.formatVersion)
        put(UInt32(glass.count))
        for g in glass { put(g) }
        return data
    }

    /// A window's glazing from `data`, for a window of `pieces` pieces that offers `offered`
    /// glasses.
    public init(encoded data: Data, pieces: Int, offered: Int) throws {
        var offset = data.startIndex
        func get<T: BitwiseCopyable>(_: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard size <= data.endIndex - offset else { throw CodingError.corrupt }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset - data.startIndex, as: T.self) }
            offset += size
            return v
        }
        guard try get(UInt32.self) == Self.magic else { throw CodingError.corrupt }
        let version = try get(UInt32.self)
        guard version != 0 else { throw CodingError.corrupt }
        guard version <= Self.formatVersion else { throw CodingError.newerVersion(version) }
        let count = Int(try get(UInt32.self))
        // Checked against the bytes left before anything is allocated.
        guard count <= (data.endIndex - offset) / MemoryLayout<Int16>.size else { throw CodingError.corrupt }
        guard count == pieces else { throw CodingError.otherWindow }
        var glass = [Int16]()
        glass.reserveCapacity(count)
        for _ in 0..<count {
            let g = try get(Int16.self)
            glass.append(g >= 0 && Int(g) < offered ? g : Self.none)
        }
        self.glass = glass
    }
}
