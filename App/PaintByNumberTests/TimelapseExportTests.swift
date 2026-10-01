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
        // Every sample decoded in order, so the first and last frames are exactly the movie's.
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

    // MARK: Pace

    private func options(_ pace: TimelapsePace) -> TimelapseExporter.Options {
        var options = TimelapseExporter.Options(size: CGSize(width: 64, height: 64))
        options.pace = pace
        return options
    }

    /// Two bursts of twenty strokes a tenth of a second apart, a long pause between them.
    private var twoBursts: [Float] {
        var times: [Float] = []
        for k in 0..<20 { times.append(Float(k) * 0.1) }
        for k in 0..<20 { times.append(600 + Float(k) * 0.1) }
        return times
    }

    /// The frames of the painting part, as (completed strokes, fraction of the next).
    private func states(_ schedule: TimelapseSchedule) -> [[Float]] {
        (schedule.introFrames..<(schedule.introFrames + schedule.paintingFrames)).map {
            let state = schedule.state(atFrame: $0)
            return [Float(state.strokes), state.fraction]
        }
    }

    /// The most consecutive painting frames showing exactly the same picture and fill.
    private func longestHold(_ schedule: TimelapseSchedule) -> (frames: Int, strokes: Int) {
        var best = (frames: 0, strokes: 0)
        var run = 0
        var previous: [Float]?
        for state in states(schedule) {
            run = state == previous ? run + 1 : 1
            previous = state
            if run > best.frames { best = (run, Int(state[0])) }
        }
        return best
    }

    @Test func asPaintedShowsThePauseBetweenBursts() {
        let strokeTimes = twoBursts
        let painted = TimelapseSchedule(strokeCount: 40, strokeTimes: strokeTimes, options: options(.asPainted))
        let even = TimelapseSchedule(strokeCount: 40, strokeTimes: strokeTimes, options: options(.even))
        // The 600 s pause counts as 2 s of the 5.8 s timeline: about a third of the painting part.
        let hold = longestHold(painted)
        #expect(hold.strokes == 20, "the picture holds after the first burst, not \(hold.strokes) strokes in")
        #expect(hold.frames >= 60, "the pause lasts \(hold.frames) frames")
        #expect(longestHold(even).frames < 5, "the even schedule never stands still")
        // The movie is as long either way.
        #expect(painted.frameCount == even.frameCount)
        #expect(painted.paintingFrames == even.paintingFrames)
        #expect(painted.state(atFrame: painted.introFrames).strokes == 0)
        #expect(painted.state(atFrame: painted.frameCount - 1).strokes == 40)
    }

    @Test func asPaintedNeverGoesBackwardsAndPaintsEveryStroke() {
        let schedule = TimelapseSchedule(strokeCount: 40, strokeTimes: twoBursts, options: options(.asPainted))
        let counts = states(schedule).map { Int($0[0]) }
        #expect(counts == counts.sorted())
        #expect(states(schedule).allSatisfy { $0[1] >= 0 && $0[1] < 1 })
        // Fills spread within a burst (some frame is part-way through a stroke) and each stroke is
        // reached: no stroke is skipped by more than the few that fit in one frame.
        #expect(states(schedule).contains { $0[1] > 0 })
        let steps = zip(counts, counts.dropFirst()).map { $1 - $0 }
        #expect((steps.max() ?? 0) <= 2, "strokes jumped by \(steps.max() ?? 0) in one frame")
    }

    @Test func pausesLongerThanTwoSecondsAreAllTheSameBeat() {
        let short = TimelapseSchedule(strokeCount: 4, strokeTimes: [0, 1, 6, 7], options: options(.asPainted))
        let long = TimelapseSchedule(strokeCount: 4, strokeTimes: [0, 1, 5000, 5001], options: options(.asPainted))
        #expect(states(short) == states(long))
    }

    @Test func timesWithoutARhythmReplayEvenly() {
        let even = states(TimelapseSchedule(strokeCount: 12, options: options(.even)))
        // Progress written before times were recorded.
        let zeros = TimelapseSchedule(strokeCount: 12, strokeTimes: [Float](repeating: 0, count: 12), options: options(.asPainted))
        #expect(states(zeros) == even)
        // Times that don't belong to the log.
        let mismatched = TimelapseSchedule(strokeCount: 12, strokeTimes: [0, 1, 2], options: options(.asPainted))
        #expect(states(mismatched) == even)
        let none = TimelapseSchedule(strokeCount: 12, options: options(.asPainted))
        #expect(states(none) == even)
        // A single stroke has no intervals.
        let single = TimelapseSchedule(strokeCount: 1, strokeTimes: [3], options: options(.asPainted))
        #expect(states(single) == states(TimelapseSchedule(strokeCount: 1, options: options(.even))))
        #expect(zeros.frameCount == TimelapseSchedule(strokeCount: 12, options: options(.even)).frameCount)
    }

    @Test func damagedTimesDontBreakTheSchedule() {
        var times = (0..<10).map { Float($0) }
        times[4] = .nan
        times[6] = 1
        let schedule = TimelapseSchedule(strokeCount: 10, strokeTimes: times, options: options(.asPainted))
        let counts = states(schedule).map { Int($0[0]) }
        #expect(counts == counts.sorted())
        #expect(schedule.state(atFrame: schedule.frameCount - 1).strokes == 10)
    }

    /// A finished painting under both paces makes a movie of the same length.
    @Test func bothPacesMakeMoviesOfTheSameLength() async throws {
        var progress = PaintProgress(regionCount: 3)
        for region in 0..<3 {
            progress.activeSeconds = Double(region) * 40
            progress.paint(region)
        }
        var durations: [CMTime] = []
        for pace in TimelapsePace.allCases {
            let request = TimelapseRequest(
                title: "Pace \(UUID().uuidString)", source: .live(template: Fixtures.stripes(), progress: progress))
            let url = try await request.render(longSide: 160, pace: pace)
            defer { ArtworkExporter.removeExport(at: url) }
            durations.append(try await AVURLAsset(url: url).load(.duration))
        }
        #expect(durations.count == 2 && durations[0] == durations[1], "durations \(durations)")
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
