// CGFloat, CGPoint, CGSize and CGRect off Apple platforms, where PaintCore imports
// FoundationEssentials (Portability.swift), which has none of them: Refine's geometry and Stained
// Glass speak them, as the app does. Made as swift-corelibs-foundation makes them (its
// NSGeometry.swift), whose CGFloat is a Double in a struct; here it is Double itself, the same
// arithmetic. Apple platforms keep CoreGraphics' own.
#if canImport(FoundationEssentials) && !canImport(Darwin)
public typealias CGFloat = Double

public struct CGPoint: Sendable, Hashable {
    public var x: CGFloat
    public var y: CGFloat

    public init() { self.init(x: 0, y: 0) }
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
    public init(x: Int, y: Int) { self.init(x: CGFloat(x), y: CGFloat(y)) }

    public static var zero: CGPoint { CGPoint(x: 0, y: 0) }
}

public struct CGSize: Sendable, Hashable {
    public var width: CGFloat
    public var height: CGFloat

    public init() { self.init(width: 0, height: 0) }
    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
    public init(width: Int, height: Int) { self.init(width: CGFloat(width), height: CGFloat(height)) }

    public static var zero: CGSize { CGSize(width: 0, height: 0) }
}

public struct CGRect: Sendable, Hashable {
    public var origin: CGPoint
    public var size: CGSize

    public init() { self.init(origin: CGPoint(), size: CGSize()) }
    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    public static var zero: CGRect { CGRect(origin: CGPoint(), size: CGSize()) }
    public static let null = CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0)

    public var width: CGFloat { abs(size.width) }
    public var height: CGFloat { abs(size.height) }
    public var minX: CGFloat { origin.x + min(size.width, 0) }
    public var midX: CGFloat { (minX + maxX) * 0.5 }
    public var maxX: CGFloat { origin.x + max(size.width, 0) }
    public var minY: CGFloat { origin.y + min(size.height, 0) }
    public var midY: CGFloat { (minY + maxY) * 0.5 }
    public var maxY: CGFloat { origin.y + max(size.height, 0) }

    public var isNull: Bool { origin.x == .infinity || origin.y == .infinity }
    public var isEmpty: Bool { isNull || size.width == 0 || size.height == 0 }

    public var standardized: CGRect {
        isNull ? .null : CGRect(x: minX, y: minY, width: width, height: height)
    }

    public func contains(_ point: CGPoint) -> Bool {
        if isNull || isEmpty { return false }
        return (minX..<maxX).contains(point.x) && (minY..<maxY).contains(point.y)
    }

    public func insetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        if isNull { return self }
        var rect = standardized
        rect.origin.x += dx
        rect.origin.y += dy
        rect.size.width -= 2 * dx
        rect.size.height -= 2 * dy
        return rect.size.width < 0 || rect.size.height < 0 ? .null : rect
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        if isNull { return self }
        var rect = standardized
        rect.origin.x += dx
        rect.origin.y += dy
        return rect
    }

    public func union(_ other: CGRect) -> CGRect {
        if isNull { return other }
        if other.isNull { return self }
        let a = standardized, b = other.standardized
        let minX = min(a.minX, b.minX), minY = min(a.minY, b.minY)
        let maxX = max(a.maxX, b.maxX), maxY = max(a.maxY, b.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func intersection(_ other: CGRect) -> CGRect {
        if isNull || other.isNull { return .null }
        let a = standardized, b = other.standardized
        let aH = a.minX...a.maxX, aV = a.minY...a.maxY
        let bH = b.minX...b.maxX, bV = b.minY...b.maxY
        if !aH.overlaps(bH) || !aV.overlaps(bV) { return .null }
        let overlapH = aH.clamped(to: bH), overlapV = aV.clamped(to: bV)
        let width = overlapH == aH ? a.width : overlapH == bH ? b.width : overlapH.upperBound - overlapH.lowerBound
        let height = overlapV == aV ? a.height : overlapV == bV ? b.height : overlapV.upperBound - overlapV.lowerBound
        return CGRect(x: overlapH.lowerBound, y: overlapV.lowerBound, width: width, height: height)
    }

    public func intersects(_ other: CGRect) -> Bool { !intersection(other).isNull }
}
#endif
