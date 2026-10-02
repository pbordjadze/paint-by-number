import Foundation

/// Photo → paint-by-numbers template. The single entry point used by the app and `pbn`.
public struct TemplateGenerator: Sendable {
    /// Stamped into every generated template (`Template.pipelineVersion`). Bump in the same
    /// commit as any change that alters generated output for identical inputs and settings,
    /// so saved paintings record which pipeline drew them.
    public static let pipelineVersion: UInt32 = 3

    public var settings: GenerationSettings

    public init(settings: GenerationSettings = GenerationSettings()) {
        self.settings = settings.normalized
    }

    public struct Output: Sendable {
        public var template: Template
        public var segmentation: Segmentation
        /// What vectorizing had to give up (fallback edges; see `VectorStats`).
        public var vectorStats: VectorStats
        /// What layered line art did; nil for classic templates.
        public var lineArtStats: LineArtStats?
        public var timings: [StageClock.Timing]
        public var totalSeconds: Double { timings.filter { !$0.name.contains(".") }.reduce(0) { $0 + $1.seconds } }
    }

    /// Generates a template.
    /// - Parameters:
    ///   - image: Source photo, any size (it is area-resampled to the working size).
    ///   - importance: Optional per-pixel saliency in 0...1 at any resolution (e.g. a
    ///     subject mask from Vision). Important areas receive more colors and detail.
    ///   - lineArt: The edge map (and eyes) layered line art draws from. Ignored by classic
    ///     settings; layered settings without it generate a classic template.
    ///   - cancel: Polled between and within stages.
    ///   - progress: Called with a rough 0...1 completion fraction.
    public func generate(
        from image: RGBAImage,
        importance: Grid<Float>? = nil,
        lineArt: LineArtInput? = nil,
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

        // Layered line art needs its edge map; without one the template is classic.
        let layered = settings.lineArt.style == .layered ? lineArt : nil
        let segmentEnd: Float = layered == nil ? 0.7 : 0.6
        let parameters = SegmentationParameters(settings: settings, width: working.width, height: working.height)
        var (segmentation, weights) = try clock.measure("segment") {
            try Segmenter.segmentWithImportance(
                working, importance: importance, parameters: parameters, cancel: cancel, clock: clock,
                progress: { progress?(0.1 + (segmentEnd - 0.1) * $0) })
        }
        try cancel.throwIfCancelled()
        progress?(segmentEnd)

        var plan: LayeredLines.Plan?
        if let layered {
            let result = try clock.measure("lineArt") {
                try LayeredLines.apply(
                    segmentation, input: layered, importance: weights, settings: settings, cancel: cancel, clock: clock)
            }
            segmentation = result.segmentation
            plan = result
            try cancel.throwIfCancelled()
            progress?(0.7)
        }
        weights = []

        var vector = try clock.measure("vectorize") {
            try Vectorizer.vectorizeWithStats(segmentation, settings: settings, cancel: cancel, clock: clock)
        }
        vector.template.pipelineVersion = Self.pipelineVersion
        if let plan {
            vector.template.lineArt = clock.measure("lineArt.annotate") { LayeredLines.annotate(vector.template, plan: plan) }
        }
        progress?(1)
        return Output(
            template: vector.template, segmentation: segmentation, vectorStats: vector.stats,
            lineArtStats: plan?.stats, timings: clock.timings)
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
