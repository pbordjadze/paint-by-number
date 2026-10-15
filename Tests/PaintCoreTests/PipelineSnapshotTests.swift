import Foundation
import Testing
@testable import PaintCore

@Suite("Pipeline snapshots")
struct PipelineSnapshotTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var snapshots: [PipelineSnapshot] = []
        var values: [PipelineSnapshot] { lock.withLock { snapshots } }
        func receive(_ snapshot: PipelineSnapshot) { lock.withLock { snapshots.append(snapshot) } }
    }

    @Test(arguments: [LineArtSettings.Style.classic, .coloringBook])
    func observationPreservesTemplateAndRepeats(style: LineArtSettings.Style) throws {
        var settings = LineArtTests.settings()
        settings.lineArt.style = style
        let generator = TemplateGenerator(settings: settings)
        let image = LineArtTests.photo()
        let input = LineArtInput(edges: LineArtTests.edges())
        let plain = try generator.generate(from: image, lineArt: input, cancel: .none)
        let first = Recorder(), second = Recorder()
        let observed = try generator.generate(from: image, lineArt: input, cancel: .none, observer: first.receive)
        let repeated = try generator.generate(from: image, lineArt: input, cancel: .none, observer: second.receive)
        #expect(plain.template.encoded() == observed.template.encoded())
        #expect(repeated.template.encoded() == observed.template.encoded())
        #expect(first.values == second.values)
        let stages = PipelineSnapshot.Stage.allCases.filter { style != .classic || $0 != .lineArt }
        #expect(first.values.map(\.stage) == stages)
        expectValid(observed.template)
        for snapshot in first.values {
            switch snapshot.picture {
            case .color(let image):
                #expect(image.colorSpace == plain.template.colorSpace)
                #expect(image.width == plain.template.width && image.height == plain.template.height)
                if snapshot.stage == .palette || snapshot.stage == .simplified {
                    let paints = Set(snapshot.palette.map { $0.hexDigits })
                    for i in 0..<(image.width * image.height) {
                        let rgb = SIMD3<Float>(Float(image.pixels[i * 4]), Float(image.pixels[i * 4 + 1]),
                                               Float(image.pixels[i * 4 + 2])) / 255
                        #expect(paints.contains(PaletteColor(oklab: .zero, rgb: rgb).hexDigits))
                    }
                }
            case .grayscale(let image):
                #expect(image.width == plain.template.width && image.height == plain.template.height)
                #expect(image.storage.contains(0) && image.storage.contains(255))
            }
        }
        let final = try #require(first.values.last)
        guard case .grayscale(let boundaries) = final.picture else { Issue.record("Expected boundaries"); return }
        // The entire canvas frame survives, including the right/bottom coordinates
        // that sit just outside the last pixel centre.
        for x in 0..<boundaries.width {
            #expect(boundaries[x, 0] == 0 && boundaries[x, boundaries.height - 1] == 0)
        }
        for y in 0..<boundaries.height {
            #expect(boundaries[0, y] == 0 && boundaries[boundaries.width - 1, y] == 0)
        }
    }

    @Test func boundsEveryStageWithoutUpscaling() throws {
        // Working size is 1200×48: crosses the cap without a costly large canvas.
        let image = RGBAImage(width: 800, height: 32, fill: SIMD4(60, 120, 180, 255), colorSpace: .displayP3)
        let recorder = Recorder()
        let settings = GenerationSettings(colorCount: 8, detail: 0.5)
        let output = try TemplateGenerator(settings: settings).generate(from: image, cancel: .none, observer: recorder.receive)
        #expect(max(output.template.width, output.template.height) > 1024)
        // A book without an input has no line-art snapshot.
        #expect(recorder.values.map(\.stage) == PipelineSnapshot.Stage.allCases.filter { $0 != .lineArt })
        for snapshot in recorder.values {
            switch snapshot.picture {
            case .color(let picture):
                #expect(picture.width == 1024 && picture.height == 40)
                #expect(picture.colorSpace == .displayP3)
            case .grayscale(let picture):
                #expect(picture.width == 1024 && picture.height == 40)
                if snapshot.stage == .structure { #expect(picture.storage.allSatisfy { $0 == 0 }) }
            }
        }
        #expect(SnapshotPictures.size(width: 50, height: 2000) == (25, 1024))
        #expect(SnapshotPictures.size(width: 1, height: 2000) == (1, 1024))
        #expect(SnapshotPictures.size(width: 128, height: 96) == (128, 96))
        #expect(SnapshotPictures.size(width: 0, height: 0) == (0, 0))
    }

    @Test func smoothedUnscalesChromaAndKeepsPrimaries() throws {
        for space in [RGBColorSpace.sRGB, .displayP3] {
            let image = RGBAImage(width: 1, height: 1, fill: SIMD4(190, 45, 100, 255), colorSpace: space)
            let lab = try WorkingImage.okLab(image, chromaScale: 2.5)
            let snapshot = SnapshotPictures.smoothed(lab, chromaScale: 2.5, space: space)
            guard case .color(let picture) = snapshot.picture else { Issue.record("Expected color"); return }
            #expect(picture == image)
        }
    }

    @Test func observerErrorsStopGeneration() {
        enum Failure: Error { case save }
        let counter = LockedCounter()
        #expect(throws: Failure.self) {
            _ = try TemplateGenerator().generate(from: LineArtTests.photo(), cancel: .none, observer: { _ in
                counter.increment()
                throw Failure.save
            })
        }
        #expect(counter.count == 1)
    }
}
