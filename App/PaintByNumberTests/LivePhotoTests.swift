#if UNRELEASED
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import PaintCore
import Testing
@testable import PaintByNumber

/// The pair Photos joins into one Live Photo: the still and the movie name the same content
/// identifier, and the movie marks its key photo's moment. Adding it to the library needs the
/// painter's leave, so the tests stop before Photos.
@MainActor
struct LivePhotoTests {
    private func finishedStripes() -> TimelapseRequest {
        var progress = PaintProgress(regionCount: 3)
        for region in 0..<3 { progress.paint(region) }
        return TimelapseRequest(title: "Stripes \(UUID().uuidString)", source: .live(template: Fixtures.stripes(), progress: progress))
    }

    @Test func theStillNamesThePair() throws {
        let url = Fixtures.temporaryDirectory().appending(path: "still.jpg")
        let (template, progress) = try finishedStripes().painting()
        let image = try #require(CanvasSnapshot.render(template: template, progress: progress, size: CGSize(width: 120, height: 60)))
        #expect(LivePhoto.writeStill(image, to: url, id: "pair-1"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let maker = try #require(properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any])
        #expect(maker["17"] as? String == "pair-1")
    }

    @Test func theMovieNamesThePairAndMarksItsKeyPhoto() async throws {
        let request = finishedStripes()
        let (template, progress) = try request.painting()
        let replay = Fixtures.temporaryDirectory().appending(path: "replay.mp4")
        try await TimelapseFrameRenderer.export(template: template, progress: progress, to: replay, longSide: 320, pace: .livePhoto)
        let movie = Fixtures.temporaryDirectory().appending(path: "live.mov")
        try await LivePhoto.pair(movie: replay, to: movie, id: "pair-2")

        let asset = AVURLAsset(url: movie)
        let metadata = try await asset.load(.metadata)
        let identifier = metadata.first { $0.identifier == .quickTimeMetadataContentIdentifier }
        #expect(try await identifier?.load(.stringValue) == "pair-2")
        #expect(try await asset.loadTracks(withMediaType: .metadata).count == 1)
        let duration = try await asset.load(.duration).seconds
        // About three seconds, as the camera's Live Photos are.
        #expect(duration > 2.5 && duration < 3.5, "\(duration) s")
        let frames = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await frames.load(.timeRange).duration.seconds > 2.5)
    }
}
#endif
