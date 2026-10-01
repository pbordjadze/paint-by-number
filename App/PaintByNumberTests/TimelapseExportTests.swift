import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct TimelapseExportTests {
    /// The three stripes, painted red, green, blue in that order.
    private func finishedStripes() -> TimelapseSource {
        var progress = PaintProgress(regionCount: 3)
        for region in 0..<3 { progress.paint(region) }
        return .live(template: Fixtures.stripes(), progress: progress)
    }

    /// The ring of frames in flight drops, duplicates and reorders nothing: the movie has one
    /// sample per scheduled frame, opens on the blank template and ends on the painting.
    @Test func rendersEveryFrameOfTheReplay() async throws {
        let request = TimelapseRequest(title: "Stripes \(UUID().uuidString)", source: finishedStripes())
        let url = try await request.render(longSide: 320)
        defer { ArtworkExporter.removeExport(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))

        let size = CanvasSnapshot.fittedSize(for: Fixtures.stripes(), longSide: 320)
        let schedule = TimelapseSchedule(strokeCount: 3, options: TimelapseExporter.Options(size: size))
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        // Every sample decoded in order: the image generator's seek to the last timestamp
        // returned blank paper on the simulator.
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        var samples = 0
        var first: SIMD3<Int>?, last: SIMD3<Int>?
        while let buffer = output.copyNextSampleBuffer() {
            samples += CMSampleBufferGetNumSamples(buffer)
            guard let image = CMSampleBufferGetImageBuffer(buffer) else { continue }
            // The middle of the first (red) stripe.
            let pixel = Self.rgb(image, x: CVPixelBufferGetWidth(image) / 6, y: CVPixelBufferGetHeight(image) / 2)
            if first == nil { first = pixel }
            last = pixel
        }
        #expect(reader.status == .completed)
        #expect(samples == schedule.frameCount)
        // Paper at the start, paint at the end.
        let paper = try #require(first), red = try #require(last)
        #expect(paper.x > 200 && paper.y > 200 && paper.z > 200, "first frame \(paper)")
        #expect(red.x > 180 && red.y < 90 && red.z < 90, "last frame \(red)")
    }

    @Test func exporterCancellationRemovesThePartialFile() async throws {
        let url = Fixtures.temporaryDirectory().appending(path: "partial.mp4")
        let options = TimelapseExporter.Options(size: CGSize(width: 64, height: 64))
        let task = Task.detached {
            try await TimelapseExporter.export(strokeCount: 3, options: options, to: url) { index, _, _, buffer in
                Self.fill(buffer)
                // Cancels the export's own task, mid-way through the movie.
                if index == 10 { withUnsafeCurrentTask { $0?.cancel() } }
                return {}
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cancellingARenderRemovesItsExportFolder() async throws {
        let template = SyntheticTemplate.make()
        var progress = PaintProgress(regionCount: template.regions.count)
        for region in template.regions.indices { progress.paint(region) }
        let title = "Cancelled \(UUID().uuidString)"
        let request = TimelapseRequest(title: title, source: .live(template: template, progress: progress))
        let (fractions, continuation) = AsyncStream.makeStream(of: Double.self)
        let task = Task.detached {
            defer { continuation.finish() }
            return try await request.render(longSide: 320) { continuation.yield($0) }
        }
        for await fraction in fractions where fraction > 0.05 { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: ArtworkExporter.exportsRoot, includingPropertiesForKeys: nil)) ?? []
        let leftovers = folders.filter {
            FileManager.default.fileExists(atPath: $0.appending(path: "\(title) Time-lapse.mp4").path)
        }
        #expect(leftovers.isEmpty)
    }

    @Test func modelReachesReadyAndFinishSharingDeletesTheMovie() async throws {
        let request = TimelapseRequest(title: "Model \(UUID().uuidString)", source: finishedStripes())
        let model = TimelapseExportModel(request: request)
        await model.run(longSide: 320)
        guard case .ready(let url) = model.phase else {
            Issue.record("expected a ready movie, got \(model.phase)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        await model.finishSharing()
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        // Reached again from the sheet's disappearance: nothing left to do, nothing breaks.
        await model.finishSharing()
        #expect(model.phase == .ready(url))
    }

    /// RGB of a decoded 32BGRA frame at (x, y), origin top-left.
    nonisolated private static func rgb(_ buffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<Int> {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return .zero }
        let pixel = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4).assumingMemoryBound(to: UInt8.self)
        return SIMD3(Int(pixel[2]), Int(pixel[1]), Int(pixel[0]))
    }

    nonisolated private static func fill(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        memset(base, 0x80, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
    }
}
