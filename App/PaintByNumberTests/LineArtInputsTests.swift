import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// Files of this test bundle (`HEDFixture.*`, `FaceFixture.jpg`).
private final class TestBundle {
    static func url(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle(for: TestBundle.self).url(forResource: name, withExtension: ext), "\(name).\(ext) isn't in the test bundle")
    }
}

/// The HED model (`EdgeDetector`) against the PyTorch map the layered-lines research would
/// compute, its determinism and its cost.
struct EdgeDetectorTests {
    /// `HEDFixture.pgm` is what `tools/models/convert_hed.py` computes in PyTorch, exactly as the
    /// research did, from `HEDFixture.ppm` (248 × 168, so the model also pads to 256 × 176).
    /// Core ML on the CPU in float32 lands on the same levels but for float rounding.
    @Test func edgeMapMatchesThePyTorchReference() throws {
        let input = try Netpbm.read(Data(contentsOf: TestBundle.url("HEDFixture", "ppm")))
        let reference = try Netpbm.read(Data(contentsOf: TestBundle.url("HEDFixture", "pgm")))
        let map = try EdgeDetector.edgeMap(for: input, cancel: .none)
        #expect(map.width == reference.width && map.height == reference.height)
        let expected = (0..<(reference.width * reference.height)).map { reference.pixels[$0 * 4] }
        let differences = zip(map.values, expected).map { abs(Int($0) - Int($1)) }
        let largest = differences.max() ?? 0
        let differing = differences.filter { $0 > 0 }.count
        let mean = Double(differences.reduce(0, +)) / Double(differences.count)
        Attachment.record(Data("""
            HED fixture \(map.width)×\(map.height): largest difference \(largest) levels, \
            \(differing) of \(differences.count) pixels differ, mean \(mean)
            """.utf8), named: "hed-fixture-comparison.txt")
        #expect(largest <= 2, "Core ML's map is up to \(largest) levels from PyTorch's")
        #expect(Double(differing) <= 0.01 * Double(differences.count), "\(differing) pixels differ from PyTorch's")

        // The CGImage path draws the same sRGB pixels into sRGB: the same map.
        let image = try #require(PhotoLoader.cgImage(from: input))
        let viaImage = try EdgeDetector.edgeMap(for: image)
        #expect(zip(viaImage.values, map.values).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }

    /// A photo at full size: scaled to 1152 px, the same map on every run. Records the time and
    /// the model's input and output, so they can be checked against PyTorch off the device.
    @Test func edgeMapIsIdenticalAcrossRunsAtTheModelsSize() throws {
        let photo = try PhotoLoader.load(url: try #require(Bundle.main.url(forResource: "red-fox", withExtension: "jpg")), maxPixelSize: 2048)
        let image = try #require(PhotoLoader.cgImage(from: photo))
        let clock = ContinuousClock()
        var maps: [EdgeMap] = []
        var times: [Duration] = []
        for _ in 0..<2 {
            let start = clock.now
            maps.append(try EdgeDetector.edgeMap(for: image))
            times.append(clock.now - start)
        }
        #expect(maps[0] == maps[1], "Two runs on the same photo gave different maps")
        #expect(max(maps[0].width, maps[0].height) == EdgeDetector.maximumLongSide)
        #expect(maps[0].width == 1152 && maps[0].height == 768)
        // An outline photo: some pixels are certain edges, most are none.
        #expect(maps[0].values.contains { $0 > 200 })
        #expect(maps[0].values.filter { $0 < 46 }.count > maps[0].values.count / 2)

        let srgb = try PhotoLoader.rgbaImage(from: image, colorSpace: .sRGB)
        let size = EdgeDetector.mapSize(width: srgb.width, height: srgb.height, maxLongSide: EdgeDetector.maximumLongSide)
        let modelInput = Resample.area(srgb, width: size.width, height: size.height)
        Attachment.record(Netpbm.encodePPM(modelInput), named: "red-fox-hed-input.ppm")
        Attachment.record(Netpbm.encodePGM(width: maps[0].width, height: maps[0].height, values: maps[0].values), named: "red-fox-hed-edges.pgm")
        Attachment.record(Data("HED on red-fox at 1152×768, CPU only: \(times[0]) (first, loads the model), \(times[1])".utf8),
                          named: "hed-timings.txt")
    }

    @Test func mapsKeepTheSizeOrFitTheModel() {
        func size(_ width: Int, _ height: Int, _ maxLongSide: Int) -> [Int] {
            let size = EdgeDetector.mapSize(width: width, height: height, maxLongSide: maxLongSide)
            return [size.width, size.height]
        }
        #expect(size(2048, 1365, 1152) == [1152, 768])
        #expect(size(1365, 2048, 1152) == [768, 1152])
        #expect(size(800, 600, 1152) == [800, 600])
        // The model's input bound caps any request.
        #expect(size(4000, 3000, 4000) == [1152, 864])
        #expect(size(4000, 3000, 400) == [400, 300])
    }

    /// NumPy's "reflect": mirrored at the last pixel without repeating it.
    @Test func paddingMirrorsLikeTheResearch() {
        #expect((0..<12).map { EdgeDetector.reflect($0, 5) } == [0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3])
        #expect((0..<4).map { EdgeDetector.reflect($0, 1) } == [0, 0, 0, 0])
        #expect((0..<5).map { EdgeDetector.reflect($0, 2) } == [0, 1, 0, 1, 0])
    }

    @Test func probabilitiesRoundToTheNearestLevel() {
        #expect(EdgeDetector.level(0) == 0 && EdgeDetector.level(1) == 255)
        #expect(EdgeDetector.level(0.5) == 128)
        #expect(EdgeDetector.level(127.4 / 255) == 127 && EdgeDetector.level(127.6 / 255) == 128)
        #expect(EdgeDetector.level(-0.2) == 0 && EdgeDetector.level(1.7) == 255 && EdgeDetector.level(.nan) == 0)
    }
}

/// Eyes from Vision's face landmarks (`EyeFinder`).
struct EyeFinderTests {
    /// `FaceFixture.jpg`: NASA's 1962 portrait of John Glenn (S62-05540, public domain), cropped
    /// to his head, 330 × 360. His eyes are near (0.36, 0.44) and (0.56, 0.43).
    @Test func findsBothEyesOfAFaceWithTheirIrises() throws {
        let image = try #require(ImageCodec.image(at: TestBundle.url("FaceFixture", "jpg")))
        let eyes = EyeFinder.eyes(in: image)
        Attachment.record(Data(eyes.map { "\($0)" }.joined(separator: "\n").utf8), named: "face-fixture-eyes.txt")
        try #require(eyes.count == 4, "Expected two contours and two irises, got \(eyes.count) polygons")
        func centroid(_ polygon: [SIMD2<Float>]) -> SIMD2<Float> { polygon.reduce(.zero, +) / Float(polygon.count) }
        let contours = Array(eyes[0..<2]), irises = Array(eyes[2..<4])
        // Ordered top to bottom, then left to right: both eyes are at about the same height, so
        // which comes first depends on the head's tilt.
        let byX = contours.map(centroid).sorted { $0.x < $1.x }
        #expect(abs(byX[0].x - 0.36) < 0.06 && abs(byX[0].y - 0.44) < 0.06, "left eye at \(byX[0])")
        #expect(abs(byX[1].x - 0.56) < 0.06 && abs(byX[1].y - 0.43) < 0.06, "right eye at \(byX[1])")
        for (contour, iris) in zip(contours, irises) {
            #expect(contour.count >= 3 * EyeFinder.contourSubdivisions)
            let xs = contour.map(\.x), ys = contour.map(\.y)
            let width = xs.max()! - xs.min()!
            #expect(width > 0.06 && width < 0.2, "eye width \(width)")
            // The iris lies within its eye.
            let c = centroid(iris)
            #expect(c.x > xs.min()! && c.x < xs.max()! && c.y > ys.min()! && c.y < ys.max()!)
            for point in iris {
                #expect(point.x >= xs.min()! - 1e-3 && point.x <= xs.max()! + 1e-3)
                #expect(point.y >= ys.min()! - 1e-3 && point.y <= ys.max()! + 1e-3)
            }
        }
        for point in eyes.joined() {
            #expect((0...1).contains(point.x) && (0...1).contains(point.y))
            #expect(point.x * 4096 == (point.x * 4096).rounded() && point.y * 4096 == (point.y * 4096).rounded())
        }
        #expect(EyeFinder.eyes(in: image) == eyes, "Two runs found different eyes")
    }

    @Test func aPictureWithoutFacesHasNoEyes() throws {
        let context = try #require(CGContext(
            data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.55, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        #expect(EyeFinder.eyes(in: try #require(context.makeImage())).isEmpty)
    }

    /// An eye 100 px wide on a 1000-px photo: an almond through Vision's points, an iris
    /// clipped by the lids, and the order and quantization of the output.
    @Test func eyesAreSmoothedAlmondsWithClippedIrises() throws {
        let points: [SIMD2<Double>] = [
            [400, 300], [425, 288], [450, 284], [475, 288], [500, 300], [475, 310], [450, 313], [425, 310],
        ]
        let eye = try #require(EyeFinder.Eye(contour: points, pupil: [450, 298], longSide: 1000))
        // The spline passes through every point.
        #expect(eye.contour.count == points.count * EyeFinder.contourSubdivisions)
        for (i, p) in points.enumerated() { #expect(simdDistance(eye.contour[i * EyeFinder.contourSubdivisions], p) < 1e-9) }
        // Iris radius 20 px around the pupil, cut at the lids (y 284…313).
        let iris = try #require(eye.iris)
        #expect(iris.allSatisfy { simdDistance($0, [450, 298]) <= 20 + 1e-9 })
        #expect(iris.map(\.y).min()! >= 284 - 1e-9 && iris.map(\.y).max()! <= 313 + 1e-9)
        #expect(abs(EyeFinder.area(iris)) < Double.pi * 400)

        // Too small to outline: 10 px on a 1000-px photo.
        if EyeFinder.Eye(contour: points.map { $0 / 10 }, pupil: nil, longSide: 1000) != nil { Issue.record("A 10-px eye was kept") }
        // A closed eye shows no iris.
        let closed = points.map { SIMD2($0.x, 300 + ($0.y - 300) * 0.05) }
        let closedEye = try #require(EyeFinder.Eye(contour: closed, pupil: [450, 300], longSide: 1000))
        #expect(closedEye.iris == nil)

        // Contours top to bottom, then left to right; then the irises in the same order.
        let lower = try #require(EyeFinder.Eye(contour: points.map { $0 + [0, 200] }, pupil: [450, 498], longSide: 1000))
        let left = try #require(EyeFinder.Eye(contour: points.map { $0 - [300, 0] }, pupil: [150, 298], longSide: 1000))
        let polygons = EyeFinder.polygons(of: [lower, eye, left], width: 1000, height: 800)
        #expect(polygons.count == 6)
        let centers = polygons.map { p in p.reduce(SIMD2<Float>.zero, +) / Float(p.count) }
        #expect(centers[0].x < centers[1].x && centers[1].y < centers[2].y)
        #expect(abs(centers[3].x - centers[0].x) < 0.01 && abs(centers[5].y - centers[2].y) < 0.02)
        #expect(polygons.joined().allSatisfy { $0.x * 4096 == ($0.x * 4096).rounded() })
    }

    private func simdDistance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { ((a - b) * (a - b)).sum().squareRoot() }
}

/// `LineArtInputs`: classic settings need nothing, layered ones get the edge map and eyes once
/// per photo, and the create flow and regeneration carry Settings › Advanced into the painting.
@MainActor
struct LineArtInputsTests {
    private static let layered = LineArtSettings(style: .layered, outlineThreshold: 0.7, minimumStrokeLength: 12)
    private static let tuning = PipelineTuning(minimumCellSize: 1.5, colorfulness: 0.8)

    private static func photo(_ name: String = "red-fox") throws -> CGImage {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "jpg"))
        let photo = try PhotoLoader.load(url: url, maxPixelSize: 1600)
        return try #require(PhotoLoader.cgImage(from: photo))
    }

    @Test func classicLineArtNeedsNoInputs() async throws {
        let image = try Self.photo()
        #expect(try await LineArtInputs.make(for: image, settings: LineArtSettings()) == nil)
        #expect(try await LineArtInputs.forGeneration(of: image, settings: LineArtSettings(), cached: false) == nil)
        #expect(try await LineArtInputs.forGeneration(of: nil, settings: Self.layered, cached: false) == nil)
    }

    /// The first request runs the model; the next for the same image comes from the cache.
    @Test func layeredInputsAreComputedOncePerPhoto() async throws {
        let image = try Self.photo()
        let clock = ContinuousClock()
        var start = clock.now
        let first = try #require(try await LineArtInputs.make(for: image, settings: Self.layered))
        let computing = clock.now - start
        #expect(first.edges.width == 1152 && first.edges.height == 768)
        #expect(first.eyes.isEmpty, "A fox has no human face")
        start = clock.now
        let second = try await LineArtInputs.make(for: image, settings: Self.layered)
        let cached = clock.now - start
        #expect(second == first)
        #expect(cached * 5 < computing, "The second request took \(cached), the first \(computing)")
        // The same photo by another instance is another photo to the cache, with the same inputs.
        let again = try await LineArtInputs.compute(for: Self.photo())
        #expect(again == first)
    }

    @Test func aCancelledRequestStopsTheComputation() async throws {
        let image = try Self.photo("hibiscus")
        let request = Task { try await LineArtInputs.make(for: image, settings: Self.layered) }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        // Nothing failed is kept: the next request computes the inputs.
        let input = try await LineArtInputs.make(for: image, settings: Self.layered)
        #expect(input?.edges.width == 1152)
    }

    /// Advanced settings reach every candidate, the chosen settings, the draft and the saved
    /// artwork's meta.json; layered line art computes its inputs once for the photo.
    @Test func createFlowCarriesAdvancedSettingsIntoTheArtwork() async throws {
        let model = CreateModel(paintingLength: .quick, lineArt: Self.layered, tuning: Self.tuning)
        model.load(sample: try #require(Sample.named("red-fox")))
        let draft = try await model.makeDraft()
        let decision = try #require(model.decision)
        #expect(decision.candidates.allSatisfy { $0.settings.lineArt == Self.layered && $0.settings.tuning == Self.tuning })
        #expect(model.settings == decision.settings)
        let input = try #require(model.lineArtInput)
        #expect(max(input.edges.width, input.edges.height) == EdgeDetector.maximumLongSide)
        #expect(draft.settings.lineArt == Self.layered && draft.settings.tuning == Self.tuning)

        let root = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(store: ArtworkStore(root: root))
        let artwork = try await library.create(draft)
        let saved = try library.store.readMeta(artwork.id)
        #expect(saved.settings == draft.settings)
        let json = try String(contentsOf: library.store.url(.meta, of: artwork.id), encoding: .utf8)
        #expect(json.contains("layered"))
    }

    /// Classic settings compute nothing extra and record the default line art and tuning.
    @Test func classicCreateFlowComputesNoInputs() async throws {
        let model = CreateModel(paintingLength: .quick, lineArt: LineArtSettings(), tuning: PipelineTuning())
        model.load(sample: try #require(Sample.named("espresso")))
        let draft = try await model.makeDraft()
        #expect(model.lineArtInput == nil)
        #expect(draft.settings.lineArt == LineArtSettings() && draft.settings.tuning == PipelineTuning())
        #expect(model.decision?.settings == draft.settings)
    }

    /// Regeneration uses the settings it is given, layered ones included, and records them.
    @Test func regenerationRecordsLayeredSettings() async throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(store: ArtworkStore(root: root))
        let first = try await ArtworkFactory.draft(
            sample: try #require(Sample.named("delicate-arch")), settings: GenerationSettings(colorCount: 12, detail: 0),
            photoMaxPixelSize: 640)
        let artwork = try await library.create(first)
        let settings = GenerationSettings(colorCount: 12, detail: 0, lineArt: Self.layered, tuning: Self.tuning)
        let document = try await library.regenerate(artwork: artwork.id, settings: settings)
        #expect(document.template.regions.count > 0)
        #expect(library.artwork(with: artwork.id)?.settings == settings)
        #expect(try library.store.readMeta(artwork.id).settings == settings)
    }
}
