import CoreGraphics
import Foundation
import PaintCore
import Testing
import Vision
@testable import PaintByNumber

/// The scene map the app builds for the scene method (`SceneMapBuilder`, from `SubjectVision`'s
/// findings): well-formed on the red fox and the same on two runs, empty but well-formed on a
/// photo of nothing, and the pure part, findings into bytes, rects and ordered features. Vision
/// finds no subjects on CI's simulators: the shape is what is checked there, and the fox's scene
/// is attached for a device run to be judged.
struct SceneMapBuilderTests {
    @Test func foxSceneIsWellFormedAndRepeatable() async throws {
        let url = try #require(Bundle.main.url(forResource: "red-fox", withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 1152)
        let image = try #require(PhotoLoader.cgImage(from: photo))
        let scene = await SceneMapBuilder.scene(for: image)
        // Another image of the same photo: its own pass of Vision, not the first one's findings.
        let again = await SceneMapBuilder.scene(for: try #require(PhotoLoader.cgImage(from: photo)))
        #expect(scene == again, "the scene differs between two runs")
        try Self.expectWellFormed(scene, of: image)
        Attachment.record(Data(Self.describe(scene).utf8), named: "fox-scene.txt")
    }

    /// A plain synthetic image: no faces, animals or features, whatever the simulator's Vision
    /// makes of its two bands.
    @Test func aPlainImageMakesAnEmptyScene() async throws {
        let width = 320, height = 240
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.55, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.3, green: 0.55, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 3))
        let image = try #require(context.makeImage())
        let scene = await SceneMapBuilder.scene(for: image)
        try Self.expectWellFormed(scene, of: image)
        #expect(scene.faces.isEmpty && scene.animals.isEmpty && scene.features.isEmpty)
        Attachment.record(Data(Self.describe(scene).utf8), named: "plain-scene.txt")
    }

    /// Findings become bytes (a map of another size counts as none), the hints' rects, and
    /// features normalized, quantized, ordered by position, one quantized to nothing dropped.
    @Test func sceneIsMadeFromTheFindings() throws {
        let size = SubjectImportance.mapSize(width: 400, height: 200)
        let w = size.width, h = size.height
        var foreground = PaintCore.Grid<Float>(width: w, height: h, repeating: 0)
        for y in 0..<h { for x in 0..<(w / 2) { foreground[x, y] = 1 } }
        var found = SubjectVision.Findings(
            saliency: PaintCore.Grid<Float>(width: w, height: h, repeating: 0.5), foreground: foreground)
        found.faces.observations = [VNFaceObservation(boundingBox: CGRect(x: 0.7, y: 0.6, width: 0.1, height: 0.2))]
        found.animals = [CGRect(x: 0.3, y: 0.1, width: 0.1, height: 0.2)]
        let features = SceneMapBuilder.normalized([
            SceneMapBuilder.Found(kind: .mouth, center: SIMD2(300, 150), radius: 20),
            SceneMapBuilder.Found(kind: .eye, center: SIMD2(100, 50), radius: 10),
            SceneMapBuilder.Found(kind: .eye, center: SIMD2(50, 50), radius: 10),
            SceneMapBuilder.Found(kind: .nose, center: SIMD2(10, 10), radius: 0.00001),
        ], width: 400, height: 200)
        let scene = SceneMapBuilder.scene(of: found, width: w, height: h, features: features)

        #expect(scene.width == w && scene.height == h)
        #expect(scene.subject[0] == 255 && scene.subject[w - 1] == 0)
        #expect(scene.saliency.allSatisfy { $0 == 128 })
        let hints = SubjectImportance.hints(faces: [CGRect(x: 0.7, y: 0.6, width: 0.1, height: 0.2)], animals: found.animals)
        #expect(scene.faces == hints.faces && scene.animals == hints.animals)
        #expect(scene.hasSubject)

        #expect(scene.features.map(\.kind) == [.eye, .eye, .mouth])
        let quantum = Float(1 / SceneMapBuilder.quantum)
        func expect(_ feature: SceneMap.Feature, _ x: Float, _ y: Float, _ radius: Float,
                    sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(abs(feature.x - x) <= quantum && abs(feature.y - y) <= quantum && abs(feature.radius - radius) <= quantum,
                    "\(feature)", sourceLocation: sourceLocation)
        }
        expect(scene.features[0], 0.125, 0.25, 0.025)
        expect(scene.features[1], 0.25, 0.25, 0.025)
        expect(scene.features[2], 0.75, 0.75, 0.05)
        #expect(try SceneMap(encodedFile: scene.encodedFile()) == scene)

        let wrong = SceneMapBuilder.scene(
            of: SubjectVision.Findings(saliency: PaintCore.Grid<Float>(width: 3, height: 3, repeating: 1)),
            width: w, height: h, features: [])
        #expect(wrong.saliency.count == w * h && wrong.saliency.allSatisfy { $0 == 0 })
        #expect(!wrong.hasSubject)
    }

    /// Sized by the photo's `mapSize`, every map the size's length, every rect and feature
    /// inside the photo with a positive radius, the features in order, and the same scene back
    /// from its file form.
    static func expectWellFormed(_ scene: SceneMap, of image: CGImage, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let size = SubjectImportance.mapSize(width: image.width, height: image.height)
        #expect(scene.width == size.width && scene.height == size.height, "\(scene.width)×\(scene.height)", sourceLocation: sourceLocation)
        #expect(scene.subject.count == scene.width * scene.height, sourceLocation: sourceLocation)
        #expect(scene.saliency.count == scene.width * scene.height, sourceLocation: sourceLocation)
        for rect in scene.faces + scene.animals {
            #expect(rect.x >= 0 && rect.y >= 0 && rect.width > 0 && rect.height > 0, "\(rect)", sourceLocation: sourceLocation)
            #expect(rect.x + rect.width <= 1.0001 && rect.y + rect.height <= 1.0001, "\(rect)", sourceLocation: sourceLocation)
        }
        for feature in scene.features {
            #expect((0...1).contains(feature.x) && (0...1).contains(feature.y), "\(feature)", sourceLocation: sourceLocation)
            #expect(feature.radius > 0 && feature.radius <= 1, "\(feature)", sourceLocation: sourceLocation)
        }
        let positions = scene.features.map { ($0.y, $0.x) }
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 }, "features out of order", sourceLocation: sourceLocation)
        #expect(try SceneMap(encodedFile: scene.encodedFile()) == scene, sourceLocation: sourceLocation)
    }

    static func describe(_ scene: SceneMap) -> String {
        let subject = Double(scene.subject.filter { $0 >= 128 }.count) / Double(max(scene.subject.count, 1))
        let features = scene.features.map {
            String(format: "%@ (%.3f, %.3f) r %.4f", "\($0.kind)", Double($0.x), Double($0.y), Double($0.radius))
        }
        return """
            \(scene.width)×\(scene.height), subject share \(String(format: "%.3f", subject)), \
            faces \(scene.faces.count), animals \(scene.animals.count), features \(scene.features.count)
            \(features.joined(separator: "\n"))
            """
    }
}
