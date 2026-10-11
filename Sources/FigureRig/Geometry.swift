import Foundation

public struct Point: Codable, Sendable, Equatable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    static let zero = Point(0, 0)
    public static func + (a: Self, b: Self) -> Self { Self(a.x + b.x, a.y + b.y) }
    public static func - (a: Self, b: Self) -> Self { Self(a.x - b.x, a.y - b.y) }
    public static func * (a: Self, b: Double) -> Self { Self(a.x * b, a.y * b) }
    var length: Double { hypot(x, y) }
    var unit: Self { length > 1e-12 ? self * (1 / length) : Self(1, 0) }
    var normal: Self { Self(-y, x) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y }
}

struct Vector3: Sendable, Equatable {
    var x: Double, y: Double, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    init(_ p: Point, _ z: Double) { self.init(p.x, p.y, z) }
    var xy: Point { Point(x, y) }
    static func + (a: Self, b: Self) -> Self { Self(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Self, b: Self) -> Self { Self(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Self, b: Double) -> Self { Self(a.x * b, a.y * b, a.z * b) }
    var length: Double { sqrt(dot(self)) }
    var unit: Self { self * (1 / max(length, 1e-12)) }
    func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }
}

func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double { min(high, max(low, value)) }
func cubic(_ t: Double) -> Double { let u = clamp(t); return u * u * (3 - 2 * u) }
func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func mix(_ a: Point, _ b: Point, _ t: Double) -> Point { a + (b - a) * t }
func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
func headingVector(_ heading: Double) -> Point { Point(cos(radians(heading)), sin(radians(heading))) }
func wrapHeading(_ heading: Double) -> Double { let h = heading.truncatingRemainder(dividingBy: 360); return h < 0 ? h + 360 : h }
func headingDelta(_ from: Double, _ to: Double) -> Double { let d = wrapHeading(to - from); return d > 180 ? d - 360 : d }

/// Absolute SVG M/L/C/Q/Z, flattened to a fixed geometric tolerance, then sampled by arc
/// length. Subdivisions never depend on frame rate, sampling order, or processor count.
public struct ArcPath: Sendable {
    public let points: [Point]
    let lengths: [Double]
    public var length: Double { lengths.last ?? 0 }

    public init(_ data: String) throws {
        var parser = PathParser(data)
        points = try parser.parse()
        var cumulative = [0.0]
        for i in 1..<points.count {
            let length = cumulative.last! + (points[i] - points[i - 1]).length
            try FigureLimits.number(length, 0...FigureLimits.pathLength, "path.length")
            cumulative.append(length)
        }
        lengths = cumulative
        guard length > 1e-9 else {
            throw FigureInputError("path: length \(length); expected a nonzero length greater than 1e-9")
        }
    }
    public func sample(_ fraction: Double) -> (point: Point, heading: Double) {
        let distance = clamp(fraction) * length
        var lo = 1, hi = lengths.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if lengths[mid] < distance { lo = mid + 1 } else { hi = mid } }
        let span = lengths[lo] - lengths[lo - 1]
        let tangent = points[lo] - points[lo - 1]
        return (mix(points[lo - 1], points[lo], span > 0 ? (distance - lengths[lo - 1]) / span : 0),
                wrapHeading(atan2(tangent.y, tangent.x) * 180 / .pi))
    }
}

private struct PathParser {
    let bytes: [UInt8]
    var index = 0, points: [Point] = []
    init(_ data: String) { bytes = Array(data.utf8) }
    mutating func skip() { while index < bytes.count && [9, 10, 13, 32, 44].contains(bytes[index]) { index += 1 } }
    mutating func number() throws -> Double {
        skip(); let start = index
        if index < bytes.count && [43, 45].contains(bytes[index]) { index += 1 }
        while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
        if index < bytes.count && bytes[index] == 46 {
            index += 1; while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
        }
        if index < bytes.count && [69, 101].contains(bytes[index]) {
            index += 1; if index < bytes.count && [43, 45].contains(bytes[index]) { index += 1 }
            while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
        }
        guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)), value.isFinite else {
            throw FigureInputError("path: expected a finite coordinate at byte \(start)")
        }
        try FigureLimits.number(value, -FigureLimits.coordinate...FigureLimits.coordinate, "path.coordinate at byte \(start)")
        return value
    }
    mutating func point() throws -> Point { let x = try number(); return Point(x, try number()) }
    mutating func append(_ p: Point) throws {
        if points.last != p {
            guard points.count < FigureLimits.pathPoints else { throw FigureInputError("path.points: expected at most \(FigureLimits.pathPoints) flattened points") }
            points.append(p)
        }
    }
    mutating func curve(_ a: Point, _ b: Point, _ c: Point, _ d: Point, _ depth: Int = 0) throws {
        let chord = d - a
        let deviation = max(abs((b - a).dot(chord.unit.normal)), abs((c - a).dot(chord.unit.normal)))
        let excess = (b - a).length + (c - b).length + (d - c).length - chord.length
        if (deviation <= 0.02 && excess <= 0.02) || depth == 18 { try append(d); return }
        let ab = mix(a, b, 0.5), bc = mix(b, c, 0.5), cd = mix(c, d, 0.5)
        let abc = mix(ab, bc, 0.5), bcd = mix(bc, cd, 0.5), mid = mix(abc, bcd, 0.5)
        try curve(a, ab, abc, mid, depth + 1); try curve(mid, bcd, cd, d, depth + 1)
    }
    mutating func parse() throws -> [Point] {
        var command: UInt8 = 0
        while true {
            skip(); if index == bytes.count { break }
            if (65...90).contains(bytes[index]) || (97...122).contains(bytes[index]) {
                command = bytes[index]; index += 1
                guard [77, 76, 67, 81, 90].contains(command) else { throw FigureInputError("path: expected absolute M L C Q Z at byte \(index - 1)") }
            }
            if command == 77 {
                guard points.isEmpty else { throw FigureInputError("path: expected one continuous subpath") }
                try append(point()); command = 76
            } else if command == 90 {
                guard let first = points.first else { throw FigureInputError("path: Z needs an initial M") }
                try append(first); command = 0
            } else {
                guard let a = points.last else { throw FigureInputError("path: expected initial M") }
                switch command {
                case 76: try append(point())
                case 67: let b = try point(), c = try point(), d = try point(); try curve(a, b, c, d)
                case 81: let b = try point(), d = try point(); try curve(a, a + (b - a) * (2 / 3), d + (b - d) * (2 / 3), d)
                default: throw FigureInputError("path: expected M L C Q Z at byte \(index)")
                }
            }
        }
        // A syntactically valid stationary path reaches ArcPath's length diagnostic.
        guard !points.isEmpty else { throw FigureInputError("path: expected at least one point") }
        return points
    }
}
