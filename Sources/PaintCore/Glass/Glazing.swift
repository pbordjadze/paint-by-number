import Foundation

/// Which glass is in each piece of a Stained Glass window (painting-company row 366): free
/// glazing, any glass in any piece (Paul, November 20, 2026), so the choice is the painter's and
/// lives beside the painting's progress, which still says which pieces are glazed and when
/// (`glazing.bin` beside `progress.bin`). A glass is named by its place in the glasses the window
/// offered when it was made (`GlassPalette.offered(for:)`), which the file keeps, so a later
/// change to how glasses are suggested never turns one glass into another; `none` is a piece not
/// glazed.
///
/// The file is read as hostile input: magic `PBGL`, a format version, the piece count, one
/// `Int16` a piece, then the count of glasses offered and each one's OKLab and RGB (six `Float32`),
/// then (from November 22, 2026) the piece count again and a byte a piece, 1 where the painter
/// has framed it (`GlassFraming`); a file without them has its glazed pieces framed.
/// Fields are only ever appended (readers ignore trailing bytes); bump `formatVersion` only when
/// an existing field changes meaning. A glass past what the window offers reads as none, never
/// as another glass.
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
    /// The glasses the window offers, as they were when it was made.
    public let offered: [PaletteColor]
    /// Per piece, whether the painter has led it in (a glazed piece always has).
    public var framed: [Bool]

    public init(pieces: Int, offered: [PaletteColor]) {
        glass = Array(repeating: Self.none, count: max(0, pieces))
        framed = Array(repeating: false, count: max(0, pieces))
        self.offered = offered
    }

    /// Whether piece `r` is leaded: framed, or glazed.
    public func isFramed(_ r: Int) -> Bool { framed[r] || glass[r] != Self.none }

    public var glazedCount: Int { glass.reduce(0) { $0 + ($1 == Self.none ? 0 : 1) } }

    public func encoded() -> Data {
        var data = Data()
        func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(Self.formatVersion)
        put(UInt32(glass.count))
        for g in glass { put(g) }
        put(UInt32(offered.count))
        for c in offered {
            for v in [c.oklab.x, c.oklab.y, c.oklab.z, c.rgb.x, c.rgb.y, c.rgb.z] { put(v) }
        }
        put(UInt32(framed.count))
        for f in framed { put(UInt8(f ? 1 : 0)) }
        return data
    }

    /// A window's glazing from `data`, for a window of `pieces` pieces.
    public init(encoded data: Data, pieces: Int) throws {
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
        for _ in 0..<count { glass.append(try get(Int16.self)) }
        let offeredCount = Int(try get(UInt32.self))
        let colorSize = 6 * MemoryLayout<Float>.size
        guard offeredCount <= (data.endIndex - offset) / colorSize else { throw CodingError.corrupt }
        var offered = [PaletteColor]()
        offered.reserveCapacity(offeredCount)
        for _ in 0..<offeredCount {
            var v = [Float]()
            for _ in 0..<6 {
                let f = try get(Float.self)
                guard f.isFinite else { throw CodingError.corrupt }
                v.append(f)
            }
            offered.append(PaletteColor(oklab: SIMD3(v[0], v[1], v[2]), rgb: SIMD3(v[3], v[4], v[5])))
        }
        self.glass = glass.map { $0 >= 0 && Int($0) < offeredCount ? $0 : Self.none }
        self.offered = offered
        framed = self.glass.map { $0 != Self.none }
        // The frames, when the file has them (a file from before them ends here).
        if data.endIndex - offset >= MemoryLayout<UInt32>.size {
            let framedCount = Int(try get(UInt32.self))
            guard framedCount == count, framedCount <= data.endIndex - offset else { throw CodingError.corrupt }
            framed = try (0..<framedCount).map { _ in try get(UInt8.self) != 0 }
        }
    }
}
