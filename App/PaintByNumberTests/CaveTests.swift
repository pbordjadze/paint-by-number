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
        let id = try await shelf.add(plan)
        var layer = CavePigmentLayer(plan: plan)
        layer.finishAll()
        layer.stencil(CaveHand.spread(at: CaveWall.handSpot), amount: 1)
        shelf.save(id, progress: layer.progress, pigment: layer.rgba())
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString).appendingPathComponent(CaveShelf.pigmentFile).path) }

        let again = CaveShelf(root: root)
        await again.load()
        #expect(again.paintings.map(\.id) == [id])
        #expect(again.paintings.first?.isComplete == true)
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
