import Foundation
import Testing
@testable import PaintCore

/// The scene map (`SceneMap`): its coding, its chunk in a template, and the scene method's
/// contract (the color method untouched, the scene kept, the same bytes every run).
struct SceneMapTests {
    /// A scene with a disc of subject in the middle, a saliency peak, a face and an eye.
    static func scene(width w: Int = 32, height h: Int = 24) -> SceneMap {
        var subject = [UInt8](repeating: 0, count: w * h)
        var saliency = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let dx = Float(x) - Float(w) / 2, dy = Float(y) - Float(h) / 2
                let d = (dx * dx + dy * dy).squareRoot()
                subject[y * w + x] = d < 8 ? 255 : d < 10 ? UInt8(255 * (10 - d) / 2) : 0
                saliency[y * w + x] = UInt8(max(0, 255 - Int(d * 12)))
            }
        }
        return SceneMap(
            width: w, height: h, subject: subject, saliency: saliency,
            faces: [NormalizedRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4)],
            animals: [NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)],
            features: [SceneMap.Feature(kind: .eye, x: 0.45, y: 0.45, radius: 0.03), SceneMap.Feature(kind: .mouth, x: 0.5, y: 0.6, radius: 0.05)])
    }

    @Test func fileRoundTrip() throws {
        let scene = Self.scene()
        let data = scene.encodedFile()
        #expect(try SceneMap(encodedFile: data) == scene)
        let empty = SceneMap.empty(width: 3, height: 2)
        #expect(try SceneMap(encodedFile: empty.encodedFile()) == empty)
        #expect(!empty.hasSubject)
        #expect(scene.hasSubject)
    }

    @Test func fileTruncationAtEveryOffsetIsRefused() throws {
        let data = Self.scene(width: 6, height: 5).encodedFile()
        for length in 0..<data.count {
            #expect(throws: Template.CodingError.self, "length \(length)") { try SceneMap(encodedFile: data.prefix(length)) }
        }
        #expect(throws: Template.CodingError.self) { try SceneMap(encodedFile: data + Data([0])) }
    }

    @Test func hostileFieldsAreRefused() throws {
        func mutated(_ change: (inout Data) -> Void) -> Data {
            var data = Self.scene(width: 6, height: 5).encodedFile()
            change(&data)
            return data
        }
        // The version byte follows the magic; the width the version.
        #expect(throws: Template.CodingError.self) { try SceneMap(encodedFile: mutated { $0[4] = 7 }) }
        #expect(throws: Template.CodingError.self) { try SceneMap(encodedFile: mutated { $0[5] = 0 }) }
        #expect(throws: Template.CodingError.self) { try SceneMap(encodedFile: mutated { $0[6] = 0xFF; $0[7] = 0xFF }) }
        // A face's x made NaN: the rects follow the two maps (5 + 8 + 2 × 30 bytes in) and a count.
        let faceX = 4 + 1 + 8 + 2 * 30 + 4
        #expect(throws: Template.CodingError.self) {
            try SceneMap(encodedFile: mutated { data in
                withUnsafeBytes(of: Float.nan) { data.replaceSubrange(faceX..<(faceX + 4), with: $0) }
            })
        }
    }

    @Test func templateKeepsItsSceneInAChunk() throws {
        let s = VectorizerTests.blobMap(width: 64, height: 48, colors: 5, cell: 8, noise: 0.01, seed: 3)
        var template = try VectorizerTests.vectorize(s)
        let plain = template.encoded()
        template.scene = Self.scene()
        let data = template.encoded()
        #expect(data.count > plain.count)
        let decoded = try Template(encoded: data)
        #expect(decoded.scene == template.scene)
        #expect(decoded == template)
        // Without a scene the bytes are what they were.
        template.scene = nil
        #expect(template.encoded() == plain)
        #expect(try Template(encoded: plain).scene == nil)
    }

    /// The committed fixture, written by `pbn generate --method scene` from a synthetic photo
    /// (never regenerated), keeps decoding with its scene.
    @Test func sceneFixtureDecodes() throws {
        let template = try Template(encoded: try TestFixtures.data("template-v2-scene.pbnt"))
        expectValid(template)
        let scene = try #require(template.scene)
        #expect(scene.width == 64 && scene.height == 48)
        #expect(scene.faces.count == 1 && scene.features.count == 1 && scene.features[0].kind == .eye)
        #expect(scene.hasSubject)
        #expect(template.encoded() == (try TestFixtures.data("template-v2-scene.pbnt")))
    }

    @Test func settingsMethodDecodesTolerantlyAndEncodesOnlyWhenScene() throws {
        let old = #"{"colorCount":24,"detail":0.5,"smoothness":0.5,"seed":1}"#
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: Data(old.utf8)).method == .color)
        let odd = #"{"colorCount":24,"detail":0.5,"smoothness":0.5,"seed":1,"method":"holographic"}"#
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: Data(odd.utf8)).method == .color)
        let color = try JSONEncoder().encode(GenerationSettings())
        #expect(!String(decoding: color, as: UTF8.self).contains("method"))
        let scene = GenerationSettings(method: .scene)
        let encoded = try JSONEncoder().encode(scene)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""method":"scene""#))
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: encoded) == scene)
    }

    /// The color method ignores a scene map: the template is the same bytes with and without
    /// one, and keeps none.
    @Test func colorMethodIgnoresTheScene() throws {
        let image = TestScenes.scene(width: 160, height: 120)
        let settings = GenerationSettings(colorCount: 10, detail: 0.5)
        let without = try TemplateGenerator(settings: settings).generate(from: image, cancel: .none).template
        let with = try TemplateGenerator(settings: settings).generate(from: image, scene: Self.scene(), cancel: .none).template
        #expect(without.encoded() == with.encoded())
        #expect(with.scene == nil)
    }

    /// The scene method makes a valid template that keeps the scene, the same bytes twice,
    /// its subject and background never one region, and runs without a scene too.
    @Test func sceneMethodKeepsTheSceneAndItsSides() throws {
        let image = TestScenes.scene(width: 160, height: 120)
        let settings = GenerationSettings(colorCount: 10, detail: 0.5, method: .scene)
        let scene = Self.scene()
        let first = try TemplateGenerator(settings: settings).generate(from: image, scene: scene, cancel: .none)
        let again = try TemplateGenerator(settings: settings).generate(from: image, scene: scene, cancel: .none)
        expectValid(first.template)
        #expect(first.template.scene == scene)
        #expect(first.template.encoded() == again.template.encoded())
        TestScenes.checkInvariants(first.segmentation, settings: settings)
        // No region straddles the snapped silhouette by more than the outline smoothing moves
        // it (a few pixels; a crumb with nothing of its colour on its own side may cross), and
        // the silhouette itself runs along a region boundary, give or take those pixels.
        let s = first.segmentation
        let p = SegmentationParameters(settings: settings, width: s.width, height: s.height)
        let working = Resample.area(image, width: s.width, height: s.height)
        let lab = try WorkingImage.okLab(working, chromaScale: p.chromaScale)
        let layers = try SceneLayers.make(
            scene: scene, lab: lab, structure: try StructureMap(lab, radius: p.structureRadius), parameters: p, cancel: .none)
        #expect(layers.hasScene)
        var inside = [Int](repeating: 0, count: s.regionCount), total = [Int](repeating: 0, count: s.regionCount)
        for i in 0..<s.labels.count {
            let r = Int(s.labels.storage[i])
            total[r] += 1
            if layers.isSubject[i] { inside[r] += 1 }
        }
        for r in 0..<s.regionCount where total[r] >= 256 {
            let share = Float(inside[r]) / Float(total[r])
            #expect(share <= 0.15 || share >= 0.85, "region \(r) of \(total[r]) px is \(share) subject")
        }
        let reach = 3
        var steps = 0, boundaries = 0
        for y in 0..<s.height {
            for x in 1..<s.width where layers.isSubject[y * s.width + x] != layers.isSubject[y * s.width + x - 1] {
                steps += 1
                var near = false
                for dy in -reach...reach where !near {
                    let yy = y + dy
                    guard yy >= 0, yy < s.height else { continue }
                    for dx in (-reach - 1)...reach where !near {
                        let xx = x + dx
                        guard xx >= 1, xx < s.width else { continue }
                        if s.labels.storage[yy * s.width + xx] != s.labels.storage[yy * s.width + xx - 1] { near = true }
                    }
                }
                if near { boundaries += 1 }
            }
        }
        #expect(steps > 0 && Float(boundaries) >= 0.9 * Float(steps), "\(boundaries) of \(steps) silhouette steps lie on a region boundary")
        // Without a scene the method still works and keeps none.
        let bare = try TemplateGenerator(settings: settings).generate(from: image, cancel: .none)
        expectValid(bare.template)
        #expect(bare.template.scene == nil)
        TestScenes.checkInvariants(bare.segmentation, settings: settings)
    }

    @Test func parametersCarryTheMethod() {
        let color = SegmentationParameters(settings: GenerationSettings(), width: 100, height: 80)
        let scene = SegmentationParameters(settings: GenerationSettings(method: .scene), width: 100, height: 80)
        #expect(color.method == .color && scene.method == .scene)
        #expect(color.sidePaints == 0 && scene.sidePaints == 0)
        #expect(!RegionSimplifier.acrossSilhouette(1, 7, parameters: color))
        var sided = scene
        sided.sidePaints = 5
        #expect(RegionSimplifier.acrossSilhouette(1, 7, parameters: sided))
        #expect(!RegionSimplifier.acrossSilhouette(6, 7, parameters: sided))
    }
}
