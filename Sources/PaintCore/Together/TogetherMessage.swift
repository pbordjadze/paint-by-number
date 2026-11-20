import Foundation

/// What painters painting together send each other.
///
/// **Format.** Little-endian:
/// ```
/// UInt16 magic        0x5450 (the bytes "PT")
/// UInt8  version      1
/// UInt8  kind         `Kind`
/// fields of the kind:
///   hello     UInt64 painter, UInt8 version
///   ops       point?, UInt32 count, count × op
///   snapshot  UInt32 count, count × op
///   presence  point?, Int32 color (a paint's index, -1 the hand, -2 nothing in hand)
///   ripple    Float32 x, Float32 y
///   star      Float32 x, Float32 y
///   finish    UInt64 clock
/// point?  UInt8 0 (none) or 1 followed by Float32 x, Float32 y, in canvas units
/// op      UInt32 region, UInt8 painted (0 or 1), UInt64 clock, UInt64 painter
/// ```
/// Nothing may follow the fields. A message comes from a stranger's device: every count is
/// checked against the bytes left and against `maximumOps`, every region against the template's
/// count and every float for finiteness. A kind this reader doesn't know throws `.unknownKind`
/// (a newer peer's message, to be ignored), as distinct from damage.
public enum TogetherMessage: Sendable, Equatable {
    case hello(painter: UInt64, version: UInt8)
    case ops([TogetherOp], origin: SIMD2<Float>?)
    case snapshot([TogetherOp])
    case presence(point: SIMD2<Float>?, color: Int32)
    case ripple(point: SIMD2<Float>)
    case star(point: SIMD2<Float>)
    case finish(atClock: UInt64)

    public static let magic: UInt16 = 0x5450
    public static let formatVersion: UInt8 = 1
    /// Ops in one message: 8192 × 21 bytes stays under SharePlay's 256 KB.
    public static let maximumOps = 8192
    static let opBytes = 21

    enum Kind: UInt8 {
        case hello = 1, ops, snapshot, presence, ripple, star, finish
    }

    public enum DecodingError: Error, Equatable {
        case truncated
        case badMagic
        /// A format version this reader doesn't know.
        case unsupportedVersion(UInt8)
        /// A kind this reader doesn't know: a newer peer's, safe to ignore.
        case unknownKind(UInt8)
        case regionOutOfRange
        case nonFinite
        case tooManyOps
        case malformed
        case trailingBytes
    }

    /// Ops split into messages of at most `maximumOps`, each carrying the origin.
    public static func chunked(_ ops: [TogetherOp], origin: SIMD2<Float>?) -> [TogetherMessage] {
        stride(from: 0, to: ops.count, by: maximumOps).map {
            .ops(Array(ops[$0..<min($0 + maximumOps, ops.count)]), origin: origin)
        }
    }

    /// A snapshot split the same way.
    public static func chunkedSnapshot(_ ops: [TogetherOp]) -> [TogetherMessage] {
        if ops.isEmpty { return [.snapshot([])] }
        return stride(from: 0, to: ops.count, by: maximumOps).map {
            .snapshot(Array(ops[$0..<min($0 + maximumOps, ops.count)]))
        }
    }

    public func encoded() -> Data {
        var w = Writer()
        w.u16(Self.magic)
        w.u8(Self.formatVersion)
        switch self {
        case .hello(let painter, let version):
            w.u8(Kind.hello.rawValue)
            w.u64(painter)
            w.u8(version)
        case .ops(let ops, let origin):
            w.u8(Kind.ops.rawValue)
            w.point(origin)
            w.ops(ops)
        case .snapshot(let ops):
            w.u8(Kind.snapshot.rawValue)
            w.ops(ops)
        case .presence(let point, let color):
            w.u8(Kind.presence.rawValue)
            w.point(point)
            w.u32(UInt32(bitPattern: color))
        case .ripple(let point):
            w.u8(Kind.ripple.rawValue)
            w.f32(point.x)
            w.f32(point.y)
        case .star(let point):
            w.u8(Kind.star.rawValue)
            w.f32(point.x)
            w.f32(point.y)
        case .finish(let clock):
            w.u8(Kind.finish.rawValue)
            w.u64(clock)
        }
        return Data(w.bytes)
    }

    public init(decoding data: Data, maxRegionCount: Int) throws {
        var r = Reader(bytes: [UInt8](data))
        guard try r.u16() == Self.magic else { throw DecodingError.badMagic }
        let version = try r.u8()
        guard version == Self.formatVersion else { throw DecodingError.unsupportedVersion(version) }
        let rawKind = try r.u8()
        guard let kind = Kind(rawValue: rawKind) else { throw DecodingError.unknownKind(rawKind) }
        switch kind {
        case .hello:
            self = .hello(painter: try r.u64(), version: try r.u8())
        case .ops:
            let origin = try r.point()
            self = .ops(try r.ops(maxRegionCount: maxRegionCount), origin: origin)
        case .snapshot:
            self = .snapshot(try r.ops(maxRegionCount: maxRegionCount))
        case .presence:
            let point = try r.point()
            let color = Int32(bitPattern: try r.u32())
            guard color >= -2 else { throw DecodingError.malformed }
            self = .presence(point: point, color: color)
        case .ripple:
            self = .ripple(point: SIMD2(try r.f32(), try r.f32()))
        case .star:
            self = .star(point: SIMD2(try r.f32(), try r.f32()))
        case .finish:
            self = .finish(atClock: try r.u64())
        }
        guard r.remaining == 0 else { throw DecodingError.trailingBytes }
    }
}

private struct Writer {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) } }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }

    mutating func point(_ p: SIMD2<Float>?) {
        guard let p else { return u8(0) }
        u8(1)
        f32(p.x)
        f32(p.y)
    }

    mutating func ops(_ ops: [TogetherOp]) {
        // Callers chunk; an encoder handed more writes what a decoder refuses rather than trapping.
        u32(UInt32(clamping: ops.count))
        bytes.reserveCapacity(bytes.count + ops.count * TogetherMessage.opBytes)
        for op in ops {
            u32(op.region)
            u8(op.painted ? 1 : 0)
            u64(op.stamp.clock)
            u64(op.stamp.painter)
        }
    }
}

private struct Reader {
    typealias Failure = TogetherMessage.DecodingError
    let bytes: [UInt8]
    var offset = 0

    var remaining: Int { bytes.count - offset }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n <= remaining else { throw Failure.truncated }
        defer { offset += n }
        return bytes[offset..<offset + n]
    }

    private mutating func little(_ n: Int) throws -> UInt64 {
        var v: UInt64 = 0
        for (i, b) in try take(n).enumerated() { v |= UInt64(b) << (8 * i) }
        return v
    }

    mutating func u8() throws -> UInt8 { try take(1).first! }
    mutating func u16() throws -> UInt16 { UInt16(try little(2)) }
    mutating func u32() throws -> UInt32 { UInt32(try little(4)) }
    mutating func u64() throws -> UInt64 { try little(8) }

    mutating func f32() throws -> Float {
        let v = Float(bitPattern: try u32())
        guard v.isFinite else { throw Failure.nonFinite }
        return v
    }

    mutating func point() throws -> SIMD2<Float>? {
        switch try u8() {
        case 0: return nil
        case 1: return SIMD2(try f32(), try f32())
        default: throw Failure.malformed
        }
    }

    mutating func ops(maxRegionCount: Int) throws -> [TogetherOp] {
        let count = Int(try u32())
        guard count <= TogetherMessage.maximumOps else { throw Failure.tooManyOps }
        guard count <= remaining / TogetherMessage.opBytes else { throw Failure.truncated }
        var ops: [TogetherOp] = []
        ops.reserveCapacity(count)
        for _ in 0..<count {
            let region = try u32()
            guard Int(region) < maxRegionCount else { throw Failure.regionOutOfRange }
            let painted: Bool
            switch try u8() {
            case 0: painted = false
            case 1: painted = true
            default: throw Failure.malformed
            }
            let clock = try u64()
            let painter = try u64()
            ops.append(TogetherOp(region: region, painted: painted, stamp: TogetherStamp(clock: clock, painter: painter)))
        }
        return ops
    }
}
