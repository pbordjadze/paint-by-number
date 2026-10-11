import Foundation
import Testing
@testable import FigureRig

@Suite("Frozen version 1 hero")
struct HeroDigestTests {
    @Test func heroDigests() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let specData = try Data(contentsOf: root.appendingPathComponent("factory/specs/baseline.json"))
        let sceneData = try Data(contentsOf: root.appendingPathComponent("factory/scenes/hero.json"))
        let spec = try decoder.decode(FigureSpec.self, from: specData)
        let scene = try decoder.decode(FigureScene.self, from: sceneData)
        let engine = try FigureEngine(spec: spec, scene: scene)
        let frames = (0..<engine.frameCount).map { engine.frame($0) }
        let svg = frames.flatMap { Array(FigureSVG.write($0, scene: scene, background: "../background.png").utf8) }
        func digest<T: Encodable>(_ value: T) throws -> String {
            var data = try encoder.encode(value); data.append(10)
            return FigureSHA256.digest(Array(data))
        }
        // Captured from the unchanged 0.1.1 release CLI: all 280 SVGs, motion and checks.
        let values = [FigureSHA256.digest(svg), try digest(frames.enumerated().map { MotionFrame(frame: $0.offset, time: $0.element.time, actors: $0.element.actors) }), try digest(engine.checks(frames))]
        #expect(values == ["754073c690d116071a3306443b723c5bb6f94d6878aa88a86bce22847b9ed241", "7867b9edf503a66a9efadd2ab701a1811ea9ceef10defc5a13f398a85b870e5a", "45630a0368ffdfe7e9b7ae161039a6fb5b23cce1d9f532a93edb735d9d9dcff9"])
        // 1.0.1 changes only the manifest's engine version for this scene.
        #expect(try digest(engine.manifest(specSHA256: FigureSHA256.digest(Array(specData)),
                                          sceneSHA256: FigureSHA256.digest(Array(sceneData)))) ==
                "66319309cafec9faa901b898815b4dd7a4ce7c624e8bccbd2e2f861cb3c29175")
    }
}
