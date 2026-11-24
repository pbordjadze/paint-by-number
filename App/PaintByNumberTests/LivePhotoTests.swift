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
        // A real UUID, as `save` names its pairs: ImageIO pads a shorter value to a UUID's length.
        let id = UUID().uuidString
        #expect(LivePhoto.writeStill(image, to: url, id: id))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let maker = try #require(properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any])
        #expect(maker["17"] as? String == id)
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
        // Every frame of the replay, no more and no less.
        let replayed = try await AVURLAsset(url: replay).load(.duration).seconds
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - replayed) < 0.05, "\(duration) s, the replay \(replayed) s")
        let frames = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(abs(try await frames.load(.timeRange).duration.seconds - replayed) < 0.05)
    }

    /// A painting of any size plays in about three seconds, as the camera's Live Photos do
    /// (the three stripes above are a shorter replay: the schedule never stretches a few strokes).
    @Test func aPaintingPlaysInAboutThreeSeconds() {
        let pace = TimelapseFrameRenderer.Pace.livePhoto
        let options = TimelapseExporter.Options(
            size: CGSize(width: 320, height: 240), framesPerSecond: pace.framesPerSecond,
            paintingSeconds: pace.paintingSeconds, introSeconds: pace.introSeconds, outroSeconds: pace.outroSeconds)
        for strokes in [40, 400, 4000] {
            let schedule = TimelapseSchedule(strokeCount: strokes, options: options)
            let seconds = Double(schedule.frameCount) / Double(pace.framesPerSecond)
            #expect(seconds > 2.5 && seconds < 3.5, "\(strokes) strokes: \(seconds) s")
        }
    }
}
#endif
