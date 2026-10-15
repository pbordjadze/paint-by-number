import Foundation
import Testing
@testable import MakingOf
@testable import PaintCore

/// Collects what a generation's observer is handed.
final class InputsSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [PipelineSnapshot] = []

    var values: [PipelineSnapshot] { lock.withLock { snapshots } }

    func receive(_ snapshot: PipelineSnapshot) {
        lock.withLock { snapshots.append(snapshot) }
    }
}

@Suite struct ShowPicturesTests {
    @Test func theDirectoryHoldsTheFivePictures() throws {
        let small = try SmallShow()
        let pictures = small.pictures
        #expect(pictures.width == 216 && pictures.height == 144)
        for plane in [pictures.working, pictures.smoothed, pictures.palette, pictures.simplified] {
            #expect(plane.width == 216 && plane.height == 144 && plane.data.count == 216 * 144)
            #expect(plane.data.allSatisfy { $0.w == 255 })
        }
        #expect(pictures.structure.width == 216 && pictures.structure.height == 144)
        // pixels as the files hold them: a P5 header of 15 bytes, then rows
        let raw = try Data(contentsOf: small.directory.appendingPathComponent("structure.pgm"))
        #expect(raw.prefix(15) == Data("P5\n216 144\n255\n".utf8))
        #expect(pictures.structure[5, 7] == raw[15 + 7 * 216 + 5])
        let color = try Data(contentsOf: small.directory.appendingPathComponent("palette.ppm"))
        #expect(color.prefix(15) == Data("P6\n216 144\n255\n".utf8))
        let at = 15 + (9 * 216 + 31) * 3
        #expect(pictures.palette[31, 9] == SIMD4(color[at], color[at + 1], color[at + 2], 255))
    }

    @Test func aMissingFileIsNamed() throws {
        let small = try SmallShow()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("show-pictures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["working-image.ppm", "structure.pgm", "smoothed.ppm", "palette.ppm"] {
            try FileManager.default.copyItem(at: small.directory.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        #expect(throws: ShowPicturesError.self) { try ShowPictures(directory: folder) }
        do {
            _ = try ShowPictures(directory: folder)
        } catch let error as ShowPicturesError {
            #expect(error.description.contains("simplified.ppm"))
        }
    }

    @Test func picturesOfDifferentSizesAreRefused() throws {
        let small = try SmallShow()
        let p = small.pictures
        let smaller = Plane<SIMD4<UInt8>>(width: 100, height: 60, repeating: SIMD4(0, 0, 0, 255))
        #expect(throws: ShowPicturesError.self) {
            try ShowPictures(working: p.working, structure: p.structure, smoothed: smaller, palette: p.palette, simplified: p.simplified)
        }
        let narrow = Plane<UInt8>(width: 215, height: 144, repeating: 0)
        #expect(throws: ShowPicturesError.self) {
            try ShowPictures(working: p.working, structure: narrow, smoothed: p.smoothed, palette: p.palette, simplified: p.simplified)
        }
        let none = Plane<SIMD4<UInt8>>(width: 0, height: 0, data: [])
        #expect(throws: ShowPicturesError.self) {
            try ShowPictures(working: none, structure: Plane(width: 0, height: 0, data: []), smoothed: none, palette: none, simplified: none)
        }
    }

    /// The pictures as the pipeline's observer hands them over, with the stages the show ignores.
    private func snapshots(of pictures: ShowPictures) -> [PipelineSnapshot] {
        func image(_ plane: Plane<SIMD4<UInt8>>) -> RGBAImage {
            RGBAImage(width: plane.width, height: plane.height, pixels: plane.data.flatMap { [$0.x, $0.y, $0.z, $0.w] })
        }
        let gray = Grid<UInt8>(width: pictures.width, height: pictures.height, storage: pictures.structure.data)
        return [
            PipelineSnapshot(stage: .working, picture: .color(image(pictures.working))),
            PipelineSnapshot(stage: .structure, picture: .grayscale(gray)),
            PipelineSnapshot(stage: .smoothed, picture: .color(image(pictures.smoothed))),
            PipelineSnapshot(stage: .palette, picture: .color(image(pictures.palette))),
            PipelineSnapshot(stage: .simplified, picture: .color(image(pictures.simplified))),
            PipelineSnapshot(stage: .lineArt, picture: .grayscale(gray)),
            PipelineSnapshot(stage: .vectorized, picture: .grayscale(gray)),
        ]
    }

    @Test func snapshotsMakeTheSamePicturesAsFiles() throws {
        let small = try SmallShow()
        let all = snapshots(of: small.pictures)
        #expect(try ShowPictures(snapshots: all) == small.pictures)
        #expect(try ShowPictures(snapshots: all.shuffled()) == small.pictures)
    }

    @Test func aMissingStageIsNamed() throws {
        let small = try SmallShow()
        for stage in [PipelineSnapshot.Stage.working, .structure, .smoothed, .palette, .simplified] {
            let without = snapshots(of: small.pictures).filter { $0.stage != stage }
            do {
                _ = try ShowPictures(snapshots: without)
                Issue.record("pictures without \(stage) were accepted")
            } catch let error as ShowPicturesError {
                #expect(error.description.contains(stage.rawValue))
            }
        }
    }

    @Test func aPictureOfTheWrongKindIsRefused() throws {
        let small = try SmallShow()
        var all = snapshots(of: small.pictures)
        let color = RGBAImage(width: 216, height: 144, fill: SIMD4(1, 2, 3, 255))
        all[1] = PipelineSnapshot(stage: .structure, picture: .color(color))
        #expect(throws: ShowPicturesError.self) { try ShowPictures(snapshots: all) }
        all = snapshots(of: small.pictures)
        all[3] = PipelineSnapshot(stage: .palette, picture: .grayscale(Grid(width: 216, height: 144, repeating: 0)))
        #expect(throws: ShowPicturesError.self) { try ShowPictures(snapshots: all) }
    }

    @Test func theRealPipelinesSnapshotsAreAccepted() throws {
        let recorder = InputsSnapshotRecorder()
        let output = try TemplateGenerator(settings: GenerationSettings(colorCount: 6, detail: 0.5))
            .generate(from: InputsTestPhoto.make(), cancel: .none, observer: recorder.receive)
        let pictures = try ShowPictures(snapshots: recorder.values)
        #expect(pictures.width == output.template.width && pictures.height == output.template.height)
        #expect(pictures.structure.data.contains { $0 > 0 })
        #expect(Set(pictures.palette.data).count <= 6 && Set(pictures.simplified.data).count <= 6)
    }
}

/// A small photo-like scene for the tests that run the real pipeline: sky, ground, discs, a line.
enum InputsTestPhoto {
    static func make(width: Int = 160, height: Int = 100) -> RGBAImage {
        var image = RGBAImage(width: width, height: height, fill: SIMD4(0, 0, 0, 255))
        var rng = SplitMix64(seed: 5)
        let discs: [(x: Double, y: Double, r: Double, c: SIMD3<Double>)] = [
            (0.3, 0.6, 0.18, SIMD3(200, 40, 40)), (0.7, 0.55, 0.12, SIMD3(240, 200, 30)), (0.55, 0.3, 0.07, SIMD3(40, 90, 200)),
        ]
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x) / Double(width), v = Double(y) / Double(height)
                var c: SIMD3<Double> = v < 0.45 ? SIMD3(90 + 100 * v, 140 + 80 * v, 230) : SIMD3(70 + 40 * u, 120, 50 + 30 * v)
                for d in discs {
                    let dx = (u - d.x) * Double(width) / Double(height), dy = v - d.y
                    if dx * dx + dy * dy < d.r * d.r { c = d.c }
                }
                c += SIMD3(rng.nextDouble(), rng.nextDouble(), rng.nextDouble()) * 16 - 8
                image[x, y] = SIMD4(UInt8(min(max(c.x, 0), 255)), UInt8(min(max(c.y, 0), 255)), UInt8(min(max(c.z, 0), 255)), 255)
            }
        }
        return image
    }
}
