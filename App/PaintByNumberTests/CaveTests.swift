#if UNRELEASED
import Foundation
import PaintCore
import Testing
import simd
@testable import PaintByNumber

/// The cave (painting-company row 371): its shader compiles on the device's Metal, a painting
/// kept on the wall comes back with its pigment, and the wall's bays are what the camera stands at.
@MainActor
struct CaveAppTests {
    @Test func theWallsShaderCompiles() throws {
        let context = try CaveRenderContext()
        _ = try CaveRenderer(context: context)
    }

    @Test func aPaintingKeptOnTheWallComesBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CaveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = await Background.run {
            let sample = CaveSample.horse()
            return CavePlan.make(photo: sample.photo, subject: sample.subject, kind: .animal)
        }
        let shelf = CaveShelf(root: root)
        await shelf.load()
        #expect(shelf.paintings.isEmpty)
        let id = try await shelf.add(plan, title: "Horse")
        var layer = CavePigmentLayer(plan: plan)
        layer.finishAll()
        layer.stencil(CaveHand.spread(at: CaveWall.handSpot), amount: 1)
        shelf.save(id, progress: layer.progress, pigment: layer.rgba())
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString).appendingPathComponent(CaveShelf.pigmentFile).path) }

        let again = CaveShelf(root: root)
        await again.load()
        #expect(again.paintings.map(\.id) == [id])
        #expect(again.paintings.first?.isComplete == true)
        #expect(again.paintings.first?.title == "Horse")
        // The gallery's picture: drawn, kept, and the painting can go.
        let picture = await again.picture(of: id)
        #expect(picture?.width == CavePigmentLayer.width)
        let kept = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(id.uuidString).path)
        #expect(kept.filter { $0.hasPrefix("picture-") }.count == 1)
        again.delete(id)
        await again.flush()
        #expect(again.paintings.isEmpty)
        let third = CaveShelf(root: root)
        await third.load()
        #expect(third.paintings.isEmpty)
    }

    /// The frame's card menu renames a painting: its name on the wall at once, and kept.
    @Test func aRenamedPaintingKeepsItsName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CaveTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = await Background.run {
            let sample = CaveSample.horse()
            return CavePlan.make(photo: sample.photo, subject: sample.subject, kind: .animal)
        }
        let shelf = CaveShelf(root: root)
        await shelf.load()
        let id = try await shelf.add(plan, title: "Horse")
        shelf.rename(id, to: "Lascaux")
        #expect(shelf.painting(id)?.title == "Lascaux")
        #expect(shelf.paintings.map(\.shelfItem) == [ModeShelfItem(id: id, title: "Lascaux", isComplete: false)])
        await shelf.flush()
        let again = CaveShelf(root: root)
        await again.load()
        #expect(again.painting(id)?.title == "Lascaux")
    }

    /// The frame's painting screen: one painting's bay, the camera still on it, plain rock round it
    /// and no mouth, its pigments on the ledge until it is finished.
    @Test func onePaintingStandsAloneInTheDark() async {
        let plan = await Background.run {
            let sample = CaveSample.horse()
            return CavePlan.make(photo: sample.photo, subject: sample.subject, kind: .animal)
        }
        let defaults = UserDefaults(suiteName: "CaveTests.\(UUID().uuidString)")!
        let painting = CaveScene.Painting(id: UUID(), plan: plan, progress: CaveProgress(done: Array(repeating: false, count: plan.areaCount)))
        let scene = CaveScene(paintings: [painting], sound: CaveSound(sounds: false, haptics: false), single: true, defaults: defaults)
        scene.layOut(size: SIMD2(390, 844))
        #expect(scene.activeBay == CaveScene.singleBay)
        #expect(scene.hasPigments)
        #expect(!scene.isAtBareRock)
        if case .painting = scene.bay(CaveScene.singleBay)?.content {} else { Issue.record("The painting's bay isn't the painting") }
        #expect(scene.bay(0)?.content == .bare)
        #expect(scene.bay(CaveScene.singleBay + 1)?.content == .bare)
        // An iPhone on its side: plain rock right across, from the wall's start or later.
        scene.layOut(size: SIMD2(844, 390))
        #expect(scene.camera >= 0)
        #expect(scene.wantedBays.allSatisfy { scene.bay($0) != nil })
        let camera = scene.camera
        scene.walk(1)
        for _ in 0..<60 { scene.step(1 / 60) }
        #expect(scene.camera == camera)
        #expect(scene.uniforms(drawable: SIMD2(780, 1688)).mouth.x < -10_000)
        for _ in 0..<600 where !scene.isWaitingForHand { scene.step(1 / 60); _ = scene.blowNextArea() }
        #expect(scene.isWaitingForHand)
        scene.leaveHand()
        for _ in 0..<240 { scene.step(1 / 60) }
        #expect(!scene.hasPigments)
        #expect(scene.paintings.first?.isComplete == true)
    }

    @Test func theWallStartsAtTheMouthAndWalksIn() {
        let defaults = UserDefaults(suiteName: "CaveTests.\(UUID().uuidString)")!
        let scene = CaveScene(paintings: [], sound: CaveSound(sounds: false, haptics: false), defaults: defaults)
        scene.layOut(size: SIMD2(390, 844))
        #expect(scene.isAtMouth)
        #expect(scene.isAtBareRock)
        scene.walk(1)
        for _ in 0..<240 { scene.step(1 / 60) }
        #expect(!scene.isAtMouth)
    }
}
#endif
