import Foundation

/// Photo → paint-by-numbers template. The single entry point used by the app and `pbn`.
public struct TemplateGenerator: Sendable {
    /// Stamped into every generated template (`Template.pipelineVersion`). Bump in the same
    /// commit as any change that alters generated output for identical inputs and settings,
    /// so saved paintings record which pipeline drew them.
    public static let pipelineVersion: UInt32 = 1

    public var settings: GenerationSettings

    public init(settings: GenerationSettings = GenerationSettings()) {
        self.settings = settings.normalized
    }

    public struct Output: Sendable {
        public var template: Template
        public var segmentation: Segmentation
        /// What vectorizing had to give up (fallback edges; see `VectorStats`).
        public var vectorStats: VectorStats
        public var timings: [StageClock.Timing]
        public var totalSeconds: Double { timings.filter { !$0.name.contains(".") }.reduce(0) { $0 + $1.seconds } }
    }

    /// Generates a template.
    /// - Parameters:
    ///   - image: Source photo, any size (it is area-resampled to the working size).
    ///   - importance: Optional per-pixel saliency in 0...1 at any resolution (e.g. a
    ///     subject mask from Vision). Important areas receive more colors and detail.
    ///   - cancel: Polled between and within stages.
    ///   - progress: Called with a rough 0...1 completion fraction.
    public func generate(
        from image: RGBAImage,
        importance: Grid<Float>? = nil,
        cancel: CancellationCheck = .task,
        progress: (@Sendable (Float) -> Void)? = nil
    ) throws -> Output {
        let clock = StageClock()
        progress?(0)
        let size = settings.workingSize(sourceWidth: image.width, sourceHeight: image.height)
        let working = try clock.measure("resample") {
            try Resample.area(image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress?(0.1)

        let segmentation = try clock.measure("segment") {
            try Segmenter.segment(
                working, importance: importance, settings: settings, cancel: cancel, clock: clock,
                progress: { progress?(0.1 + 0.6 * $0) })
        }
        try cancel.throwIfCancelled()
        progress?(0.7)

        var vector = try clock.measure("vectorize") {
            try Vectorizer.vectorizeWithStats(segmentation, settings: settings, cancel: cancel, clock: clock)
        }
        vector.template.pipelineVersion = Self.pipelineVersion
        progress?(1)
        return Output(
            template: vector.template, segmentation: segmentation, vectorStats: vector.stats, timings: clock.timings)
    }
}

/// Records wall-clock timings of pipeline stages. Sub-stages use dotted names
/// ("segment.smooth") so reports can nest them; only top-level names count toward totals.
public final class StageClock: @unchecked Sendable {
    public struct Timing: Sendable, CustomStringConvertible {
        public var name: String
        public var seconds: Double
        /// When the stage began, in seconds since the clock was created.
        public var start: Double = 0
        public var description: String { "\(name): \(String(format: "%.1f", seconds * 1000)) ms" }
    }

    private let lock = NSLock()
    private var _timings: [Timing] = []
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init() { origin = clock.now }

    public var timings: [Timing] { lock.withLock { _timings } }

    @discardableResult
    public func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let start = clock.now
        defer {
            @inline(__always) func seconds(_ d: Duration) -> Double {
                Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
            }
            let timing = Timing(name: name, seconds: seconds(clock.now - start), start: seconds(start - origin))
            lock.withLock { _timings.append(timing) }
        }
        return try body()
    }
}
