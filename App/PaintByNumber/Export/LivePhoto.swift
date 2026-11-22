#if UNRELEASED
import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import PaintCore
import Photos
import UniformTypeIdentifiers

/// A finished painting saved to Photos as a Live Photo (painting-company research
/// `2026-11-22-obscure-apple-apis`): its key photo the finished painting, and pressed, the
/// painting painting itself, its replay in about three seconds (`TimelapseFrameRenderer.Pace`).
///
/// Photos pairs a still and a movie as one Live Photo only when both carry the same content
/// identifier (the still in Apple's maker note, key 17; the movie in its QuickTime metadata,
/// with a timed `still-image-time` marking the key photo's moment) and they are added to the
/// library together (`PHAssetCreationRequest`'s `.photo` and `.pairedVideo`). Only Photos sees
/// it: nothing leaves the device.
nonisolated enum LivePhoto {
    enum SaveError: Error { case notAllowed, stillFailed, movieFailed }

    /// The longest side of the still and of the movie.
    static let longSide = 1440

    /// Makes the pair in one export folder, saves it to Photos and removes the folder.
    /// `onProgress` hears the movie's frames, 0…1.
    @concurrent
    static func save(_ request: TimelapseRequest, onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let (template, progress) = try request.painting()
        let title = request.title
        let id = UUID().uuidString
        let replay = try ArtworkExporter.temporaryURL(name: ArtworkExporter.timelapseName(title: title), pathExtension: "mp4")
        defer { ArtworkExporter.removeExport(at: replay) }
        let folder = replay.deletingLastPathComponent()
        let movie = folder.appending(path: "live.mov"), still = folder.appending(path: "live.jpg")

        try await TimelapseFrameRenderer.export(
            template: template, progress: progress, to: replay, longSide: longSide, pace: .livePhoto, onProgress: onProgress)
        try Task.checkCancellation()
        try await pair(movie: replay, to: movie, id: id)
        let size = CanvasSnapshot.fittedSize(for: template, longSide: longSide)
        guard let picture = CanvasSnapshot.render(template: template, progress: progress, size: size, options: .painting),
              writeStill(picture, to: still, id: id)
        else { throw SaveError.stillFailed }
        try Task.checkCancellation()
        try await addToPhotos(still: still, movie: movie)
    }

    /// The finished painting as the key photo, its maker note naming the pair.
    static func writeStill(_ image: CGImage, to url: URL, id: String) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": id],
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// The replay copied, frame for frame, into a QuickTime movie that names the pair and marks
    /// its last moment, the finished painting, as the key photo's.
    static func pair(movie source: URL, to url: URL, id: String) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SaveError.movieFailed }
        let duration = try await asset.load(.duration)
        let hint = try await track.load(.formatDescriptions).first
        let transform = try await track.load(.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let identifier = AVMutableMetadataItem()
        identifier.keySpace = .quickTimeMetadata
        identifier.key = "com.apple.quicktime.content.identifier" as NSString
        identifier.value = id as NSString
        identifier.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [identifier]

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
        video.transform = transform
        video.expectsMediaDataInRealTime = false
        writer.add(video)

        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String,
        ]
        var description: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &description)
        guard let description else { throw SaveError.movieFailed }
        let marks = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: marks)
        writer.add(marks)

        guard reader.startReading(), writer.startWriting() else { throw SaveError.movieFailed }
        writer.startSession(atSourceTime: .zero)

        let keyPhoto = AVMutableMetadataItem()
        keyPhoto.key = "com.apple.quicktime.still-image-time" as NSString
        keyPhoto.keySpace = AVMetadataKeySpace(rawValue: "mdta")
        keyPhoto.value = 0 as NSNumber
        keyPhoto.dataType = kCMMetadataBaseDataType_SInt8 as String
        let frame = CMTime(value: 1, timescale: 30)
        let at = CMTimeMaximum(.zero, CMTimeSubtract(duration, frame))
        guard adaptor.append(AVTimedMetadataGroup(items: [keyPhoto], timeRange: CMTimeRange(start: at, duration: frame)))
        else { throw SaveError.movieFailed }
        marks.markAsFinished()

        while let sample = output.copyNextSampleBuffer() {
            while !video.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? SaveError.movieFailed }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard video.append(sample) else { throw writer.error ?? SaveError.movieFailed }
        }
        guard reader.status == .completed else { throw reader.error ?? SaveError.movieFailed }
        video.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? SaveError.movieFailed }
    }

    /// Adds the pair to the library as one Live Photo, asking for add-only access first.
    static func addToPhotos(still: URL, movie: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: still, options: nil)
            request.addResource(with: .pairedVideo, fileURL: movie, options: nil)
        }
    }
}
#endif
