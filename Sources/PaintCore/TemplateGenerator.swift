/// Photo → paint-by-numbers template. The single entry point used by the app and `pbn`.
public struct TemplateGenerator: Sendable {
    /// Stamped into every generated template (`Template.pipelineVersion`). Bump in the same
    /// commit as any change that alters generated output for identical inputs and settings,
    /// so saved paintings record which pipeline drew them.
    public static let pipelineVersion: UInt32 = 7

    public var settings: GenerationSettings

    public init(settings: GenerationSettings = GenerationSettings()) {
        self.settings = settings.normalized
    }

    public struct Output: Sendable {
        public var template: Template
        public var segmentation: Segmentation
        /// What vectorizing had to give up (fallback edges; see `VectorStats`).
        public var vectorStats: VectorStats
        /// What line art drawn from an edge map did; nil for classic templates.
        public var lineArtStats: LineArtStats?
        public var timings: [StageClock.Timing]
        public var totalSeconds: Double { timings.filter { !$0.name.contains(".") }.reduce(0) { $0 + $1.seconds } }
    }

    /// Generates a template.
    /// - Parameters:
    ///   - image: Source photo, any size (it is area-resampled to the working size).
    ///   - importance: Optional per-pixel saliency in 0...1 at any resolution (e.g. a
    ///     subject mask from Vision). Important areas receive more colors and detail.
    ///   - lineArt: The edge map, eyes, subject silhouettes, contour map and writing
    ///     (`LineArtInput`) layered and coloring-book line art draw from.
    ///     Ignored by classic settings; settings that need it generate a classic template
    ///     without it (a coloring book's over its flatter paint).
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
        var working = try clock.measure("resample") {
            try Resample.area(image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        progress?(0.1)

        // Line art drawn from an edge map needs it; without one the template is classic.
        let layered = settings.lineArt.style.usesEdgeMap ? lineArt : nil
        let segmentEnd: Float = layered == nil ? 0.7 : 0.6
        var parameters = SegmentationParameters(settings: settings, width: working.width, height: working.height)
        // By the settings, not the edge map, so Auto's drafts (which have none) are scored on
        // the paint the book gets, and a book whose edge map failed keeps its flatter paint.
        if settings.lineArt.style == .coloringBook { parameters.flattenForColoringBook() }
        // The writing's ink is traced and painted out first, so the paint ignores the letters.
        var writing: Writing?
        if let layered, settings.lineArt.keepWriting, !layered.writing.isEmpty {
            writing = try clock.measure("writing") {
                try Writing.find(
                    in: &working, areas: layered.writing, minRadius: parameters.minRadius, cancel: cancel, clock: clock)
            }
            try cancel.throwIfCancelled()
        }
        var (segmentation, weights) = try clock.measure("segment") {
            try Segmenter.segment(
                working, importance: importance, parameters: parameters, cancel: cancel, clock: clock,
                progress: { progress?(0.1 + (segmentEnd - 0.1) * $0) })
        }
        try cancel.throwIfCancelled()
        progress?(segmentEnd)

        var plan: LayeredLines.Plan?
        if let layered {
            let result = try clock.measure("lineArt") {
                try LayeredLines.apply(
                    segmentation, input: layered, importance: weights, settings: settings, writing: writing, cancel: cancel,
                    clock: clock)
            }
            segmentation = result.segmentation
            plan = result
            try cancel.throwIfCancelled()
            progress?(0.7)
        }
        // Drops the canvas-sized importance map before the vectorizer's own large buffers.
        weights = []

        let keepOut = LabelKeepOut(rects: writing?.keepOut ?? [])
        var vector = try clock.measure("vectorize") {
            try Vectorizer.vectorizeWithStats(segmentation, settings: settings, keepOut: keepOut, cancel: cancel, clock: clock)
        }
        vector.template.pipelineVersion = Self.pipelineVersion
        if let plan {
            try cancel.throwIfCancelled()
            vector.template.lineArt = try clock.measure("lineArt.annotate") {
                try LayeredLines.annotate(vector.template, plan: plan, cancel: cancel)
            }
        }
        progress?(1)
        return Output(
            template: vector.template, segmentation: segmentation, vectorStats: vector.stats,
            lineArtStats: plan?.stats, timings: clock.timings)
    }
}
