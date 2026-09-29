/// Axis-aligned integer pixel bounds (inclusive min, exclusive max).
public struct PixelBounds: Sendable, Hashable, Codable {
    public var minX: Int32
    public var minY: Int32
    public var maxX: Int32
    public var maxY: Int32

    public init(minX: Int32, minY: Int32, maxX: Int32, maxY: Int32) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }

    public static let empty = PixelBounds(minX: .max, minY: .max, maxX: .min, maxY: .min)

    public var isEmpty: Bool { minX >= maxX || minY >= maxY }
    public var width: Int { Int(maxX - minX) }
    public var height: Int { Int(maxY - minY) }

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

/// Result of connected-component labelling.
public struct Components: Sendable {
    /// Component index per pixel, `0..<count`, numbered in raster order of first pixel.
    public var labels: RegionMap
    /// Class value (e.g. palette index) of each component.
    public var classOf: [UInt32]
    /// Pixel count of each component.
    public var area: [Int]
    /// Bounds of each component.
    public var bounds: [PixelBounds]

    public var count: Int { classOf.count }
}

public enum ConnectedComponents {

    /// Labels 4-connected components of equal class value.
    public static func label(_ classes: Grid<UInt32>) -> Components {
        let w = classes.width, h = classes.height, n = w * h
        guard n > 0 else {
            return Components(labels: RegionMap(width: w, height: h, repeating: 0), classOf: [], area: [], bounds: [])
        }
        var provisional = [UInt32](repeating: 0, count: n)
        var parent: [UInt32] = []
        parent.reserveCapacity(n / 16 + 16)

        @inline(__always) func find(_ x: UInt32) -> UInt32 {
            var r = x
            while parent[Int(r)] != r { r = parent[Int(r)] }
            var c = x
            while parent[Int(c)] != r {
                let next = parent[Int(c)]
                parent[Int(c)] = r
                c = next
            }
            return r
        }

        classes.storage.withUnsafeBufferPointer { cls in
            provisional.withUnsafeMutableBufferPointer { lab in
                for y in 0..<h {
                    let row = y * w
                    for x in 0..<w {
                        let i = row + x
                        let c = cls[i]
                        let leftSame = x > 0 && cls[i - 1] == c
                        let upSame = y > 0 && cls[i - w] == c
                        if leftSame && upSame {
                            let a = find(lab[i - 1]), b = find(lab[i - w])
                            if a != b {
                                if a < b { parent[Int(b)] = a } else { parent[Int(a)] = b }
                            }
                            lab[i] = min(a, b)
                        } else if leftSame {
                            lab[i] = lab[i - 1]
                        } else if upSame {
                            lab[i] = lab[i - w]
                        } else {
                            let id = UInt32(parent.count)
                            parent.append(id)
                            lab[i] = id
                        }
                    }
                }
            }
        }

        // Resolve roots and renumber in order of first appearance.
        var finalID = [UInt32](repeating: .max, count: parent.count)
        var classOf: [UInt32] = []
        var area: [Int] = []
        var bounds: [PixelBounds] = []
        classes.storage.withUnsafeBufferPointer { cls in
            provisional.withUnsafeMutableBufferPointer { lab in
                for y in 0..<h {
                    let row = y * w
                    for x in 0..<w {
                        let i = row + x
                        let root = Int(find(lab[i]))
                        var id = finalID[root]
                        if id == .max {
                            id = UInt32(classOf.count)
                            finalID[root] = id
                            classOf.append(cls[i])
                            area.append(0)
                            bounds.append(.empty)
                        }
                        lab[i] = id
                        area[Int(id)] += 1
                        bounds[Int(id)].include(x: x, y: y)
                    }
                }
            }
        }
        return Components(
            labels: RegionMap(width: w, height: h, storage: provisional),
            classOf: classOf, area: area, bounds: bounds
        )
    }
}
