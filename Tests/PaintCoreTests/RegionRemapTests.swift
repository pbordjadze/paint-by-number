import Testing
@testable import PaintCore

@Suite("Region remap")
struct RegionRemapTests {

    static func map(_ rows: [[UInt32]]) -> RegionMap {
        RegionMap(width: rows[0].count, height: rows.count, storage: rows.flatMap { $0 })
    }

    static func carry(_ order: [UInt32], from old: [[UInt32]], to new: [[UInt32]]) -> [RegionRemap.Carried] {
        let oldMap = map(old), newMap = map(new)
        return RegionRemap.carryOver(
            paintOrder: order, oldMap: oldMap, oldRegionCount: Int(oldMap.storage.max()!) + 1,
            newMap: newMap, newRegionCount: Int(newMap.storage.max()!) + 1)
    }

    static func carried(_ pairs: [(Int, Int)]) -> [RegionRemap.Carried] {
        pairs.map { RegionRemap.Carried(region: $0.0, stroke: $0.1) }
    }

    @Test func identicalMapsKeepPaintOrder() {
        let rows: [[UInt32]] = [[0, 0, 1, 1], [2, 2, 3, 3]]
        #expect(Self.carry([3, 0, 2], from: rows, to: rows) == Self.carried([(3, 0), (0, 1), (2, 2)]))
    }

    @Test func splitRegionsInheritTheParentStroke() {
        let old: [[UInt32]] = [[0, 0, 0, 0, 1, 1]]
        let new: [[UInt32]] = [[0, 0, 1, 1, 2, 2]]
        #expect(Self.carry([0], from: old, to: new) == Self.carried([(0, 0), (1, 0)]))
    }

    @Test func mergedRegionsNeedSixtyPercentPainted() {
        let merged: [[UInt32]] = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]]
        // 6 of 10 cells painted, mostly by the second stroke (old region 0).
        let old: [[UInt32]] = [[0, 0, 0, 0, 1, 1, 2, 2, 2, 2]]
        #expect(Self.carry([1, 0], from: old, to: merged) == Self.carried([(0, 1)]))
        // 5 of 10 is not enough.
        let half: [[UInt32]] = [[0, 0, 0, 0, 0, 1, 1, 1, 1, 1]]
        #expect(Self.carry([0], from: half, to: merged).isEmpty)
        // Equal shares go to the earlier stroke.
        let tie: [[UInt32]] = [[0, 0, 0, 1, 1, 1, 2, 2, 2, 2]]
        #expect(Self.carry([1, 0], from: tie, to: merged) == Self.carried([(0, 0)]))
    }

    @Test func scalesBetweenMapSizes() {
        let old: [[UInt32]] = [[0, 0, 1, 1, 2]]
        let new: [[UInt32]] = [[0, 0, 0, 0, 1, 1, 1, 1, 2, 2]]
        #expect(Self.carry([2], from: old, to: new) == Self.carried([(2, 0)]))
        // And back down: new cell x samples old cell 2x.
        #expect(Self.carry([1, 2], from: new, to: old) == Self.carried([(1, 0), (2, 1)]))
    }

    @Test func ignoresEmptyAndInvalidPaintOrders() {
        let rows: [[UInt32]] = [[0, 1], [2, 3]]
        #expect(Self.carry([], from: rows, to: rows).isEmpty)
        #expect(Self.carry([7, 1, 1], from: rows, to: rows) == Self.carried([(1, 1)]))
    }
}
