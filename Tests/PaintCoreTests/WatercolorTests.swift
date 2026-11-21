import Foundation
import Testing
@testable import PaintCore

/// Watercolor (painting-company row 373): the sheet, the simulation's guarantees and the tap log.
@Suite struct WatercolorTests {
    static let template: Template = {
        // A classic template of the shared scene: a few dozen areas, small enough to step fast.
        try! TemplateGenerator().generate(from: TestScenes.scene(width: 200, height: 150), cancel: .none).template
    }()

    static func largestRegion(_ t: Template) -> Int {
        t.regions.indices.max { t.regions[$0].area < t.regions[$1].area }!
    }

    static func center(of r: Int, in t: Template) -> SIMD2<Float> {
        t.labels.first { Int($0.region) == r }?.position ?? SIMD2(Float(t.width) / 2, Float(t.height) / 2)
    }

    static func digest(_ sim: WatercolorSim) -> [SIMD4<Float>] {
        (0..<(sim.sheet.width * sim.sheet.height)).map { sim.D[$0] + sim.S[$0] }
    }

    @Test func sheetFollowsTheTemplate() {
        let t = Self.template
        let sheet = WatercolorSheet(template: t, seed: 1)
        #expect(sheet.width == t.width && sheet.height == t.height)  // small templates step at their own size
        #expect(sheet.regionCount == t.regions.count)
        for y in stride(from: 0, to: sheet.height, by: 7) {
            for x in stride(from: 0, to: sheet.width, by: 7) {
                #expect(Int(sheet.labels[y * sheet.width + x]) == Int(t.regionMap[x, y]))
            }
        }
        #expect(sheet.paper.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func theKeyKeepsDarksAndThinsLights() {
        let paper = WatercolorSheet.density(of: WatercolorSheet.paperColor, area: 100)
        #expect(paper.max() < 1e-4)
        let dark = WatercolorSheet.density(of: SIMD3(0.02, 0.02, 0.03), area: 100)
        let light = WatercolorSheet.density(of: SIMD3(0.6, 0.55, 0.4), area: 100)
        let full = -log(SIMD3<Float>(0.6, 0.55, 0.4).x / WatercolorSheet.paperColor.x)
        #expect(light.x < 0.5 * full)  // a thin wash the paper glows through
        #expect(dark.x > 2.5)  // darks keep their weight
        // A big flat area goes thinner than a small one of the same paint.
        #expect(WatercolorSheet.density(of: SIMD3(0.3, 0.3, 0.3), area: 30_000).x
            < WatercolorSheet.density(of: SIMD3(0.3, 0.3, 0.3), area: 500).x)
    }

    @Test func aTapLaysItsAreaAndDries() {
        let t = Self.template
        let sim = WatercolorSim(sheet: WatercolorSheet(template: t, seed: 1))
        let r = Self.largestRegion(t)
        sim.tap(region: r, at: Self.center(of: r, in: t), paint: true)
        #expect(sim.laidCount == 1 && sim.laid[r])
        sim.finish()
        #expect(!sim.isActive)
        let sheet = sim.sheet
        var covered = 0, cells = 0
        for i in 0..<(sheet.width * sheet.height) where sheet.labels[i] == Int32(r) {
            cells += 1
            if sim.D[i].x + sim.D[i].y + sim.D[i].z > 0.01 { covered += 1 }
            #expect(sim.W[i] == 0)
        }
        #expect(covered > cells * 8 / 10)
        // The target solve brings the area's mean to its paint (within the gain's range).
        let target = sim.target(of: r)
        #expect(target.gain.min() >= 0.7 && target.gain.max() <= 1.4)
    }

    @Test func noTapIsWrong() {
        let t = Self.template
        let r = Self.largestRegion(t)
        // Another paint's tap is water alone: nothing laid, nothing to see once dry.
        let water = WatercolorSim(sheet: WatercolorSheet(template: t, seed: 1))
        water.tap(region: r, at: Self.center(of: r, in: t), paint: false)
        water.finish()
        #expect(water.laidCount == 0)
        #expect(Self.digest(water).allSatisfy { $0 == .zero })
        // A second tap of an area laid adds water, never paint: a bloom.
        let sim = WatercolorSim(sheet: WatercolorSheet(template: t, seed: 1))
        sim.tap(region: r, at: Self.center(of: r, in: t), paint: true)
        sim.finish()
        let laid = sim.laidDensity[r]
        sim.tap(region: r, at: Self.center(of: r, in: t) + SIMD2(3, 2), paint: true)
        sim.finish()
        #expect(sim.laidDensity[r] == laid && sim.laidCount == 1)
    }

    @Test func whereYouTapChangesThePainting() {
        let t = Self.template
        let r = Self.largestRegion(t)
        let b = t.regions[r].bounds
        func painted(at p: SIMD2<Float>) -> [SIMD4<Float>] {
            let sim = WatercolorSim(sheet: WatercolorSheet(template: t, seed: 1))
            sim.tap(region: r, at: p, paint: true)
            sim.finish()
            return Self.digest(sim)
        }
        let a = painted(at: SIMD2(Float(b.minX) + 2, Float(b.minY) + 2))
        let c = painted(at: Self.center(of: r, in: t))
        #expect(a != c)
    }

    @Test func aLogReplaysToTheSamePainting() throws {
        let t = Self.template
        let regions = t.regions.indices.sorted { t.regions[$0].area > t.regions[$1].area }.prefix(6)
        let live = WatercolorSim(sheet: WatercolorSheet(template: t, seed: 9))
        var log = WatercolorLog(seed: 9)
        for (n, r) in regions.enumerated() {
            let p = Self.center(of: r, in: t)
            log.taps.append(.init(step: live.step, region: r, x: p.x, y: p.y, paint: n != 2))
            live.tap(region: r, at: p, paint: n != 2)
            for _ in 0..<(n * 7 + 3) { live.advance() }
        }
        live.finish()
        let data = try log.encoded()
        let read = try WatercolorLog(encoded: data, regions: t.regions.count, width: t.width, height: t.height)
        #expect(read == log)
        let again = WatercolorSim(sheet: WatercolorSheet(template: t, seed: read.seed))
        again.replay(read)
        #expect(Self.digest(again) == Self.digest(live))
        #expect(again.laid == live.laid)
    }

    @Test func theCoreCountChangesNothing() {
        let t = Self.template
        func run() -> [SIMD4<Float>] {
            let sim = WatercolorSim(sheet: WatercolorSheet(template: t, seed: 4))
            for r in t.regions.indices.prefix(5) {
                sim.tap(region: r, at: Self.center(of: r, in: t), paint: true)
                for _ in 0..<5 { sim.advance() }
            }
            sim.finish()
            return Self.digest(sim)
        }
        let one = Parallel.withBandCount(1) { run() }
        let many = Parallel.withBandCount(5) { run() }
        #expect(one == many)
    }

    @Test func aLogIsReadAsHostileInput() throws {
        let t = Self.template
        var log = WatercolorLog(seed: 1)
        log.taps = [
            .init(step: 5, region: 0, x: 1, y: 1, paint: true),
            .init(step: 3, region: 0, x: 1, y: 1, paint: true),  // out of order
            .init(step: 6, region: t.regions.count, x: 1, y: 1, paint: true),  // no such area
            .init(step: 8, region: 0, x: Float(t.width) + 10, y: 1, paint: true),
            .init(step: 9, region: 1, x: 2, y: 2, paint: false),
        ]
        let read = try WatercolorLog(encoded: try log.encoded(), regions: t.regions.count, width: t.width, height: t.height)
        #expect(read.taps.map(\.step) == [5, 9])
        var newer = log
        newer.version = WatercolorLog.currentVersion + 1
        #expect(throws: WatercolorLog.CodingError.newerVersion(newer.version)) {
            _ = try WatercolorLog(encoded: try newer.encoded(), regions: t.regions.count, width: t.width, height: t.height)
        }
        #expect(throws: (any Error).self) {
            _ = try WatercolorLog(encoded: Data("{".utf8), regions: 1, width: 1, height: 1)
        }
    }

    @Test func aSnapshotOpensThePaintingAsItWas() throws {
        let t = Self.template
        let sheet = WatercolorSheet(template: t, seed: 2)
        let sim = WatercolorSim(sheet: sheet)
        let r = Self.largestRegion(t)
        sim.tap(region: r, at: Self.center(of: r, in: t), paint: true)
        sim.finish()
        let data = sim.snapshot()
        let opened = WatercolorSim(sheet: sheet)
        try opened.restore(from: data)
        #expect(Self.digest(opened) == Self.digest(sim))
        #expect(opened.laid == sim.laid && opened.laidCount == 1 && opened.step == sim.step)
        #expect(opened.target(of: r).gain == sim.target(of: r).gain)
        // Damaged, truncated or another sheet's: refused, nothing changed.
        let blank = WatercolorSim(sheet: sheet)
        #expect(throws: WatercolorSim.SnapshotError.damaged) { try blank.restore(from: data.prefix(data.count - 3)) }
        var other = data
        other[8] &+= 1
        #expect(throws: WatercolorSim.SnapshotError.otherSheet) { try blank.restore(from: other) }
        var nan = data
        let last = nan.count - 4
        nan.replaceSubrange(last..<(last + 4), with: withUnsafeBytes(of: Float.nan.bitPattern.littleEndian) { Data($0) })
        #expect(throws: WatercolorSim.SnapshotError.damaged) { try blank.restore(from: nan) }
        #expect(blank.laidCount == 0)
        var rng = SplitMix64(seed: 5)
        for _ in 0..<50 {
            var junk = data
            for _ in 0..<8 { junk[Int(rng.next() % UInt64(junk.count))] = UInt8(truncatingIfNeeded: rng.next()) }
            _ = try? WatercolorSim(sheet: sheet).restore(from: junk)
        }
    }
}
