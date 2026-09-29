import AVFoundation
import CoreVideo
import Foundation

/// Encodes a replay of a painting session as a short video.
///
/// Renderer-agnostic: the caller draws each frame into the provided pixel buffer (Metal via a
/// CVMetalTextureCache, or CoreGraphics on the buffer's base address). `TimelapseSchedule`
/// decides how many strokes are visible in each frame.
nonisolated enum TimelapseExporter {
    struct Options: Sendable {
        var size: CGSize
        var framesPerSecond: Int = 60
        /// Length of the painting part of the video (excluding intro/outro holds).
        var paintingSeconds: Double = 9
        var introSeconds: Double = 0.6
        var outroSeconds: Double = 1.8
    }

    enum ExportError: Error { case writerSetup, appendFailed, cancelled }

    /// Writes an HEVC movie to `url`. Runs on the caller's executor (frames are rendered by the
    /// caller's closure), so call it from a background task for large exports.
    /// - Parameter renderFrame: draws frame `index` showing the first `strokes` fills of the log
    ///   (plus `fraction` 0…1 of the next one, for smooth in-progress fills) into the buffer.
    static func export(
        strokeCount: Int,
        options: Options,
        to url: URL,
        progress: (@Sendable (Double) -> Void)? = nil,
        renderFrame: (_ index: Int, _ strokes: Int, _ fraction: Float, _ buffer: CVPixelBuffer) throws -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(options.size.width) & ~1, height = Int(options.size.height) & ~1
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: width * height * 8],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw ExportError.writerSetup }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writerSetup }
        writer.startSession(atSourceTime: .zero)

        let schedule = TimelapseSchedule(strokeCount: strokeCount, options: options)
        let timescale = CMTimeScale(options.framesPerSecond)
        for frame in 0..<schedule.frameCount {
            if Task.isCancelled { writer.cancelWriting(); throw ExportError.cancelled }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerSetup }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ExportError.appendFailed }
            let (strokes, fraction) = schedule.state(atFrame: frame)
            try renderFrame(frame, strokes, fraction, buffer)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: timescale)) else {
                throw writer.error ?? ExportError.appendFailed
            }
            progress?(Double(frame + 1) / Double(schedule.frameCount))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError.appendFailed }
    }
}

/// Maps video frames to replay progress: a short hold on the blank template, strokes
/// accelerating in and easing out (so early and final strokes are visible individually while
/// the long middle flies by), then a hold on the finished painting.
nonisolated struct TimelapseSchedule: Sendable {
    let strokeCount: Int
    let introFrames: Int
    let paintingFrames: Int
    let outroFrames: Int

    init(strokeCount: Int, options: TimelapseExporter.Options) {
        self.strokeCount = strokeCount
        let fps = Double(options.framesPerSecond)
        introFrames = Int(options.introSeconds * fps)
        // Very small paintings shouldn't be stretched into a long, slow video.
        let seconds = min(options.paintingSeconds, max(1.5, Double(strokeCount) * 0.12))
        paintingFrames = max(1, Int(seconds * fps))
        outroFrames = Int(options.outroSeconds * fps)
    }

    var frameCount: Int { introFrames + paintingFrames + outroFrames }

    /// Completed strokes and the fraction of the next stroke's fill at a frame.
    func state(atFrame frame: Int) -> (strokes: Int, fraction: Float) {
        if frame < introFrames { return (0, 0) }
        let f = frame - introFrames
        if f >= paintingFrames { return (strokeCount, 0) }
        let t = Double(f) / Double(paintingFrames)
        // Smoothstep easing of stroke index over time.
        let eased = t * t * (3 - 2 * t)
        let position = eased * Double(strokeCount)
        let whole = min(strokeCount, Int(position))
        return (whole, whole < strokeCount ? Float(position - Double(whole)) : 0)
    }
}
