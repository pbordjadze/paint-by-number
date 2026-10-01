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
        var pace: TimelapsePace = .even
    }

    enum ExportError: Error { case writerSetup, appendFailed }

    /// Frames drawn ahead of the encoder: the GPU renders the next frames while the oldest
    /// one is appended, instead of stalling on every frame.
    static let framesInFlight = 3

    /// Blocks until the frame's pixels are in its buffer; throws if the GPU didn't draw them.
    typealias FrameCompletion = () throws -> Void

    /// Writes an HEVC movie to `url`. Runs on the caller's executor (frames are rendered by the
    /// caller's closure), so call it from a background task for large exports. Cancellation is
    /// checked every frame; it throws `CancellationError`, and like any failure leaves no file.
    /// - Parameters:
    ///   - strokeTimes: when each of the `strokeCount` fills was painted (`PaintProgress.Stroke.time`),
    ///     which `options.pace` of `.asPainted` replays.
    ///   - renderFrame: starts drawing frame `index` showing the first `strokes` fills
    ///     of the log (plus `fraction` 0…1 of the next one, for smooth in-progress fills) into the
    ///     buffer and returns the wait for it. When it is called for frame `i`, every frame up to
    ///     `i − framesInFlight` has completed, so per-frame state can live in a ring of
    ///     `framesInFlight` slots indexed by `i % framesInFlight`.
    static func export(
        strokeCount: Int,
        strokeTimes: [Float] = [],
        options: Options,
        to url: URL,
        progress: (@Sendable (Double) -> Void)? = nil,
        renderFrame: (_ index: Int, _ strokes: Int, _ fraction: Float, _ buffer: CVPixelBuffer) throws -> FrameCompletion
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

        let schedule = TimelapseSchedule(strokeCount: strokeCount, strokeTimes: strokeTimes, options: options)
        let frameCount = schedule.frameCount
        let timescale = CMTimeScale(options.framesPerSecond)
        var pending: [(buffer: CVPixelBuffer, time: CMTime, done: FrameCompletion)] = []
        var appended = 0

        func appendOldest() async throws {
            let frame = pending.removeFirst()
            try frame.done()
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard adaptor.append(frame.buffer, withPresentationTime: frame.time) else {
                throw writer.error ?? ExportError.appendFailed
            }
            appended += 1
            progress?(Double(appended) / Double(frameCount))
        }

        do {
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                // Leaves at most framesInFlight − 1 frames pending, so frame − framesInFlight
                // (the previous user of this frame's slot) has completed.
                while pending.count >= framesInFlight { try await appendOldest() }
                guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerSetup }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw ExportError.appendFailed }
                let (strokes, fraction) = schedule.state(atFrame: frame)
                let done = try renderFrame(frame, strokes, fraction, buffer)
                pending.append((buffer, CMTime(value: CMTimeValue(frame), timescale: timescale), done))
            }
            while !pending.isEmpty { try await appendOldest() }
            input.markAsFinished()
            await writer.finishWriting()
            if writer.status != .completed { throw writer.error ?? ExportError.appendFailed }
        } catch {
            // Let the GPU finish writing into the pending buffers before they are released.
            for frame in pending { try? frame.done() }
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

/// How the strokes are spread over the painting part of the video.
nonisolated enum TimelapsePace: String, Sendable, CaseIterable, Identifiable {
    /// Strokes accelerate in and ease out, whatever the painter's rhythm was.
    case even
    /// The painter's own rhythm, compressed: bursts of painting and the pauses between them.
    case asPainted

    var id: String { rawValue }
}

/// Maps video frames to replay progress: a short hold on the blank template, strokes
/// accelerating in and easing out (so early and final strokes are visible individually while
/// the long middle flies by), then a hold on the finished painting. With `.asPainted` the
/// middle follows the recorded stroke times instead.
nonisolated struct TimelapseSchedule: Sendable {
    /// Real time between two strokes is clamped to this range before the timeline is squeezed
    /// into the video: a longer pause reads as a beat, not a wait, and strokes painted in
    /// the same instant still get their own moment.
    static let gapRange: ClosedRange<Double> = (1.0 / 60)...2

    let strokeCount: Int
    let introFrames: Int
    let paintingFrames: Int
    let outroFrames: Int
    /// `.asPainted` only: the frame (from the start of the painting part) at which each stroke
    /// starts, ascending. Nil for `.even`, and for a log with no usable times.
    private let strokeStarts: [Double]?
    /// How long one stroke takes to spread at most; a longer wait after it is a pause, not a slow fill.
    private let longestFillFrames: Double

    /// `strokeTimes` are the strokes' recorded times (`PaintProgress.Stroke.time`), used by
    /// `.asPainted`. Progress written before times were recorded has all zeros: it replays
    /// `.even`, and so does a log whose times don't match `strokeCount`. The frame count never
    /// depends on the pace.
    init(strokeCount: Int, strokeTimes: [Float] = [], options: TimelapseExporter.Options) {
        self.strokeCount = strokeCount
        let fps = Double(options.framesPerSecond)
        introFrames = Int(options.introSeconds * fps)
        // Very small paintings shouldn't be stretched into a long, slow video.
        let seconds = min(options.paintingSeconds, max(1.5, Double(strokeCount) * 0.12))
        paintingFrames = max(1, Int(seconds * fps))
        outroFrames = Int(options.outroSeconds * fps)
        longestFillFrames = fps / 4
        strokeStarts = options.pace == .asPainted
            ? Self.paintedStarts(strokeTimes, strokeCount: strokeCount, frames: paintingFrames) : nil
    }

    var frameCount: Int { introFrames + paintingFrames + outroFrames }

    /// Completed strokes and the fraction of the next stroke's fill at a frame.
    func state(atFrame frame: Int) -> (strokes: Int, fraction: Float) {
        if frame < introFrames { return (0, 0) }
        let f = frame - introFrames
        if f >= paintingFrames { return (strokeCount, 0) }
        if let strokeStarts { return paintedState(atFrame: f, starts: strokeStarts) }
        let t = Double(f) / Double(paintingFrames)
        // Smoothstep easing of stroke index over time.
        let eased = t * t * (3 - 2 * t)
        let position = eased * Double(strokeCount)
        let whole = min(strokeCount, Int(position))
        return (whole, whole < strokeCount ? Float(position - Double(whole)) : 0)
    }

    /// The stroke in progress at painting frame `f` is the last one that has started; it
    /// spreads until the next one starts, or for `longestFillFrames` when that is further away,
    /// and then the picture holds still until the next stroke.
    private func paintedState(atFrame f: Int, starts: [Double]) -> (strokes: Int, fraction: Float) {
        let position = Double(f)
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= position { low = mid } else { high = mid - 1 }
        }
        let end = low + 1 < starts.count ? starts[low + 1] : Double(paintingFrames)
        let fill = min(end - starts[low], longestFillFrames)
        let progress = (position - starts[low]) / fill
        return progress < 1 ? (low, Float(progress)) : (low + 1, 0)
    }

    /// The start frame of every stroke, with the clamped real gaps between them scaled to fill
    /// `frames` (the last stroke gets the shortest gap). Nil when the times carry no rhythm:
    /// a count that doesn't match, or no span between the first and last (all zero).
    private static func paintedStarts(_ times: [Float], strokeCount: Int, frames: Int) -> [Double]? {
        guard strokeCount > 0, times.count == strokeCount,
              let first = times.first, let last = times.last, last > first
        else { return nil }
        var starts = [Double](repeating: 0, count: strokeCount)
        var elapsed = 0.0
        for k in 1..<strokeCount {
            let gap = Double(times[k] - times[k - 1])
            // A time that isn't a number (a damaged file) counts as no gap at all.
            elapsed += gap.isNaN ? gapRange.lowerBound : min(max(gap, gapRange.lowerBound), gapRange.upperBound)
            starts[k] = elapsed
        }
        let total = elapsed + gapRange.lowerBound
        let scale = Double(frames) / total
        return starts.map { $0 * scale }
    }
}
