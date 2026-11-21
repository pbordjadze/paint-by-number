import Foundation
import Testing
@testable import PaintCore

/// The Cave (painting-company row 371): a painting's plan from a photo and its subject
/// (`CavePlan`, `CaveFigure`), the wall's bays (`CaveBay`), blowing and the hand
/// (`CavePigmentLayer`), and the two files a painting keeps (`cave.plan`, `progress.bin`), read as
/// hostile input. The photo is `CaveSample`'s horse.
@Suite("The Cave")
struct CaveTests {
    static let horse = CaveSample.horse()
    static let plan = CavePlan.make(photo: horse.photo, subject: horse.subject, kind: .animal)

    @Test func anAnimalHasAreasOfEveryPigmentOnItsShapeAlone() {
        let plan = Self.plan
        #expect(plan.kind == .animal)
        #expect(plan.areaCount >= 4)
        #expect(Set(plan.pigments) == Set(CavePigment.allCases))
        for i in 0..<(plan.width * plan.height) {
            #expect((plan.areas[i] > 0) == plan.mask[i])
            if plan.lines[i] { #expect(plan.mask[i]) }
        }
        // Every area is numbered, and none is too small to blow.
        var sizes = [Int](repeating: 0, count: plan.areaCount + 1)
        for a in plan.areas { sizes[Int(a)] += 1 }
        #expect(sizes.dropFirst().allSatisfy { $0 >= CavePlan.minimumArea })
        // It fits in its bay.
        #expect(plan.origin.x >= CaveWall.paintingBox.minX - 1 && plan.origin.x + plan.size.x <= CaveWall.paintingBox.maxX + 1)
        #expect(plan.origin.y >= CaveWall.paintingBox.minY - 1 && plan.origin.y + plan.size.y <= CaveWall.paintingBox.maxY + 1)
    }

    @Test func thePlanIsTheSameEveryTime() {
        let again = CavePlan.make(photo: Self.horse.photo, subject: Self.horse.subject, kind: .animal)
        #expect(again == Self.plan)
    }

    @Test func anythingElseIsAStickFigure() {
        let figure = CavePlan.make(photo: Self.horse.photo, subject: Self.horse.subject, kind: .figure)
        #expect(figure.kind == .figure)
        #expect(figure.pigments == [.yellowOchre, .redOchre])
        #expect(figure.lines.contains(true))
        // No subject at all: a figure too.
        let empty = Grid<Float>(width: 10, height: 10, repeating: 0)
        #expect(CavePlan.make(photo: Self.horse.photo, subject: empty, kind: .animal).kind == .figure)
        #expect(CavePlan.make(photo: Self.horse.photo, subject: nil, kind: .animal).kind == .figure)
    }

    @Test func blowingLandsWhereItBelongs() throws {
        var layer = CavePigmentLayer(plan: Self.plan)
        let a = try #require(layer.nextArea(of: .redOchre))
        let pigment = Self.plan.pigments[a - 1]
        // The wrong pigment over the area barely marks it, and finishes nothing.
        let wrong = CavePigment.allCases.first { $0 != pigment }!
        for p in layer.points(of: a) where Int(p.x + p.y) % 7 == 0 {
            layer.blow(at: p, radius: 10, amount: 0.3, pigment: wrong)
        }
        #expect(!layer.done[a - 1])
        // The right pigment finishes it, and it settles.
        var finished: [Int] = []
        for p in layer.points(of: a) where Int(p.x * 3 + p.y) % 11 == 0 {
            finished += layer.blow(at: p, radius: 10, amount: 0.3, pigment: pigment)
        }
        #expect(finished.contains(a))
        #expect(layer.done[a - 1])
        layer.settle(seconds: 2)
        #expect(!layer.isSettling)
        // Nothing lands on the bare rock round the animal.
        for y in stride(from: 0, to: CavePigmentLayer.height, by: 3) {
            for x in stride(from: 0, to: CavePigmentLayer.width, by: 3) where layer.area(at: SIMD2(Float(x), Float(y))) == nil {
                #expect(layer.coverage[y * CavePigmentLayer.width + x] == 0)
            }
        }
    }

    @Test func theHandIsLeftBareAndTheRockRoundItBlown() {
        var layer = CavePigmentLayer(plan: Self.plan)
        layer.finishAll()
        #expect(layer.isFinished)
        let h = CaveWall.handSpot
        let hand = CaveHand(fingers: [h + SIMD2(-54, 40), h + SIMD2(-30, -18), h + SIMD2(-4, -32), h + SIMD2(22, -22), h + SIMD2(42, 4)],
                            widths: [11, 9, 9, 9, 8])
        layer.stencil(hand, amount: 1)
        let w = CavePigmentLayer.width
        let palm = (Int(h.y) + 50) * w + Int(h.x) - 3
        #expect(layer.coverage[palm] == 0)
        let beside = (Int(h.y) + 50) * w + Int(h.x) + 50
        #expect(layer.coverage[beside] > 0.2)
        #expect(layer.progress.hand == hand)
    }

    @Test func aBayMeetsItsNeighbour() {
        let a = CaveBay.maps(index: 1, content: .bare, tools: .none)
        let b = CaveBay.maps(index: 2, content: .bare, tools: .none)
        let w = CaveWall.mapWidth
        var worst: Float = 0
        for y in stride(from: 0, to: CaveWall.mapHeight, by: 7) {
            worst = max(worst, abs(a.relief[y * w + w - 1] - b.relief[y * w]))
        }
        // One map pixel apart: the rock runs on.
        #expect(worst < 0.02)
        // The mouth lets the daylight in; nowhere else does.
        let mouth = CaveBay.maps(index: 0, content: .mouth, tools: .none)
        let middle = (Int(CaveWall.mouth.y) * 2) * w + Int(CaveWall.mouth.x) * 2
        #expect(mouth.rock[middle * 4 + 3] > 200)
        #expect(!stride(from: 3, to: a.rock.count, by: 4).contains { a.rock[$0] != 0 })
    }

    @Test func aPlanRoundTripsAndRefusesDamage() throws {
        let data = Self.plan.encoded()
        #expect(try CavePlan(encoded: data) == Self.plan)
        for cut in [0, 3, 12, 30, data.count / 2, data.count - 1] {
            #expect(throws: CavePlan.CodingError.corrupt) { try CavePlan(encoded: data.prefix(cut)) }
        }
        var newer = data
        newer.replaceSubrange(4..<8, with: withUnsafeBytes(of: UInt32(9)) { Data($0) })
        #expect(throws: CavePlan.CodingError.newerVersion(9)) { try CavePlan(encoded: newer) }
        var huge = data
        huge.replaceSubrange(9..<13, with: withUnsafeBytes(of: UInt32(1 << 30)) { Data($0) })
        #expect(throws: CavePlan.CodingError.corrupt) { try CavePlan(encoded: huge) }
        // Random damage never traps: it decodes to something or throws.
        var random = SplitMix64(seed: 371)
        for _ in 0..<200 {
            var bad = data
            for _ in 0..<4 { bad[Int(random.next() % UInt64(bad.count))] = UInt8(truncatingIfNeeded: random.next()) }
            _ = try? CavePlan(encoded: bad)
        }
    }

    @Test func progressRoundTripsAndRefusesDamage() throws {
        let hand = CaveHand(fingers: [SIMD2(100, 100), SIMD2(120, 80)], widths: [9, 10])
        let progress = CaveProgress(done: [true, false, true], hand: hand)
        let data = progress.encoded()
        #expect(try CaveProgress(encoded: data, areas: 3) == progress)
        #expect(throws: CaveProgress.CodingError.otherPainting) { try CaveProgress(encoded: data, areas: 4) }
        for cut in [0, 7, 12, 15, data.count - 1] {
            #expect(throws: CaveProgress.CodingError.corrupt) { try CaveProgress(encoded: data.prefix(cut), areas: 3) }
        }
        var newer = data
        newer.replaceSubrange(4..<8, with: withUnsafeBytes(of: UInt32(2)) { Data($0) })
        #expect(throws: CaveProgress.CodingError.newerVersion(2)) { try CaveProgress(encoded: newer, areas: 3) }
        var far = data
        far.replaceSubrange(19..<23, with: withUnsafeBytes(of: Float.nan) { Data($0) })
        #expect(throws: CaveProgress.CodingError.corrupt) { try CaveProgress(encoded: far, areas: 3) }
        // Trailing bytes are a later version's fields.
        #expect(try CaveProgress(encoded: data + Data([1, 2, 3]), areas: 3) == progress)
    }

    @Test func pigmentRestoresFromItsProgressAlone() {
        var layer = CavePigmentLayer(plan: Self.plan)
        layer.finishAll()
        var restored = CavePigmentLayer(plan: Self.plan)
        restored.restore(rgba: nil, progress: layer.progress)
        #expect(restored.isFinished)
        #expect(restored.rgba() == layer.rgba())
        // Pigment of another size is left out, never misread.
        var odd = CavePigmentLayer(plan: Self.plan)
        odd.restore(rgba: [1, 2, 3], progress: CaveProgress(done: Array(repeating: false, count: Self.plan.areaCount)))
        #expect(odd.doneCount == 0)
    }
}
