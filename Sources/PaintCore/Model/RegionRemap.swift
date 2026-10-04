/// Carries painting progress from one region map onto another, e.g. when a damaged painting
/// is regenerated from its photo: the new template's regions rarely match the old ones
/// exactly (the photo is stored lossily), so progress moves by painted area, not by index.
public enum RegionRemap {
    /// A new region that counts as painted, and the old stroke (an index into `paintOrder`)
    /// that painted most of it.
    public struct Carried: Sendable, Equatable {
        public var region: Int
        public var stroke: Int

        public init(region: Int, stroke: Int) {
            self.region = region; self.stroke = stroke
        }
    }

    /// A new region counts as painted when at least this share (percent) of its area was painted.
    private static let coveragePercent = 60

    /// Painted regions of `newMap`, ordered by the stroke that carried them (ties by region),
    /// so replaying them keeps the old painting order. Maps of different sizes are compared
    /// by scaling new coordinates onto the old grid (nearest cell). Identical maps give back
    /// `paintOrder` itself.
    /// - Parameters:
    ///   - paintOrder: Old regions in the order they were painted; values outside
    ///     `0..<oldRegionCount` are ignored, as are repeats.
    public static func carryOver(
        paintOrder: [UInt32], oldMap: RegionMap, oldRegionCount: Int,
        newMap: RegionMap, newRegionCount: Int
    ) -> [Carried] {
        guard !paintOrder.isEmpty, !oldMap.storage.isEmpty, !newMap.storage.isEmpty, newRegionCount > 0 else { return [] }
        var strokeOf = [Int](repeating: -1, count: oldRegionCount)
        for (stroke, region) in paintOrder.enumerated() where Int(region) < oldRegionCount && strokeOf[Int(region)] < 0 {
            strokeOf[Int(region)] = stroke
        }

        let oldW = oldMap.width, oldH = oldMap.height, newW = newMap.width, newH = newMap.height
        let oldColumn = (0..<newW).map { $0 * oldW / newW }
        var area = [Int](repeating: 0, count: newRegionCount)
        var painted = [Int](repeating: 0, count: newRegionCount)
        // Cells per (new region, stroke), keyed `region << 32 | stroke`.
        var overlap: [UInt64: Int] = [:]
        oldMap.storage.withUnsafeBufferPointer { old in
            newMap.storage.withUnsafeBufferPointer { new in
                // Accumulated per run of cells sharing both the new region and the old stroke,
                // so the dictionary is touched about once per boundary crossing, not per cell.
                var region = -1, stroke = -1, length = 0
                func flush() {
                    guard length > 0, region < newRegionCount else { return }
                    area[region] += length
                    if stroke >= 0 {
                        painted[region] += length
                        overlap[UInt64(region) << 32 | UInt64(stroke), default: 0] += length
                    }
                }
                for y in 0..<newH {
                    let oldRow = (y * oldH / newH) * oldW, newRow = y * newW
                    for x in 0..<newW {
                        let n = Int(new[newRow + x]), o = Int(old[oldRow + oldColumn[x]])
                        let s = o < oldRegionCount ? strokeOf[o] : -1
                        if n == region && s == stroke {
                            length += 1
                        } else {
                            flush()
                            region = n; stroke = s; length = 1
                        }
                    }
                    flush()
                    length = 0
                }
            }
        }

        var bestStroke = [Int](repeating: -1, count: newRegionCount)
        var bestCells = [Int](repeating: 0, count: newRegionCount)
        for (key, cells) in overlap {
            let region = Int(key >> 32), stroke = Int(key & 0xFFFF_FFFF)
            if cells > bestCells[region] || (cells == bestCells[region] && stroke < bestStroke[region]) {
                bestCells[region] = cells; bestStroke[region] = stroke
            }
        }
        var carried: [Carried] = []
        for region in 0..<newRegionCount where painted[region] > 0 && painted[region] * 100 >= area[region] * coveragePercent {
            carried.append(Carried(region: region, stroke: bestStroke[region]))
        }
        return carried.sorted { ($0.stroke, $0.region) < ($1.stroke, $1.region) }
    }
}
