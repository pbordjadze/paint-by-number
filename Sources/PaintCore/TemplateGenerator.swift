import Foundation

/// Photo → paint-by-numbers template. The single entry point used by the app and `pbn`.
public struct TemplateGenerator: Sendable {
    public var settings: GenerationSettings

    public init(settings: GenerationSettings = GenerationSettings()) {
        self.settings = settings.normalized
    }

    public struct Output: Sendable {
        public var template: Template
        public var segmentation: Segmentation
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
        let working = clock.measure("resample") { Resample.area(image, width: size.width, height: size.height) }
        try cancel.throwIfCancelled()
        progress?(0.1)

        let segmentation = try clock.measure("segment") {
            try Segmenter.segment(
                working, importance: importance, settings: settings, cancel: cancel, clock: clock,
                progress: { progress?(0.1 + 0.6 * $0) })
        }
        try cancel.throwIfCancelled()
        progress?(0.7)

        let template = try clock.measure("vectorize") {
            try Vectorizer.vectorize(segmentation, settings: settings, cancel: cancel, clock: clock)
        }
        progress?(1)
        return Output(template: template, segmentation: segmentation, timings: clock.timings)
    }
}

/// Records wall-clock timings of pipeline stages. Sub-stages use dotted names
/// ("segment.smooth") so reports can nest them; only top-level names count toward totals.
public final class StageClock: @unchecked Sendable {
    public struct Timing: Sendable, CustomStringConvertible {
        public var name: String
        public var seconds: Double
        public var description: String { "\(name): \(String(format: "%.1f", seconds * 1000)) ms" }
    }

    private let lock = NSLock()
    private var _timings: [Timing] = []

    public init() {}

    public var timings: [Timing] { lock.withLock { _timings } }

    @discardableResult
    public func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let d = clock.now - start
            let seconds = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
            lock.withLock { _timings.append(Timing(name: name, seconds: seconds)) }
        }
        return try body()
    }
}
