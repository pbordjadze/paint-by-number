/// Axis-aligned integer pixel bounds (inclusive min, exclusive max).
public struct PixelBounds: Sendable, Hashable {
    public var minX: Int32
    public var minY: Int32
    public var maxX: Int32
    public var maxY: Int32

    public init(minX: Int32, minY: Int32, maxX: Int32, maxY: Int32) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    public static let empty = PixelBounds(minX: .max, minY: .max, maxX: .min, maxY: .min)

    public var isEmpty: Bool { minX >= maxX || minY >= maxY }
    /// Negative for `.empty` (computed in Int: the Int32 difference would overflow).
    public var width: Int { Int(maxX) - Int(minX) }
    public var height: Int { Int(maxY) - Int(minY) }

    @inlinable
    public mutating func include(x: Int, y: Int) {
        let xi = Int32(x), yi = Int32(y)
        if xi < minX { minX = xi }
        if yi < minY { minY = yi }
        if xi + 1 > maxX { maxX = xi + 1 }
        if yi + 1 > maxY { maxY = yi + 1 }
    }

    public mutating func formUnion(_ other: PixelBounds) {
        minX = min(minX, other.minX); minY = min(minY, other.minY)
        maxX = max(maxX, other.maxX); maxY = max(maxY, other.maxY)
    }
}
