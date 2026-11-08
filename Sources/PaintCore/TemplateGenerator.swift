/// Photo → paint-by-numbers template. The single entry point used by the app and `pbn`.
public struct TemplateGenerator: Sendable {
    /// Stamped into every generated template (`Template.pipelineVersion`). Bump in the same
    /// commit as any change that alters generated output for identical inputs and settings,
    /// so saved paintings record which pipeline drew them.
    public static let pipelineVersion: UInt32 = 13

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
    ///     (`LineArtInput`) a coloring book draws from. Ignored by classic settings; a coloring
    ///     book without it is a classic template over the book's flatter paint. Settings with
    ///     `drawing` read neither it nor `importance`: the image is a drawing on paper, whose
    ///     own ink is the line art (`DrawingGenerator`).
    ///   - cancel: Polled between and within stages.
    ///   - progress: Called with a rough 0...1 completion fraction.
    ///   - observer: Synchronous making-of pictures in stage order, at most 1024 px on
    ///     the long side. Nil skips all snapshot work; observing never changes the template.
    ///   - pinned: The paints to make the template with, in their order, instead of choosing
    ///     them (`Segmenter`): a refined painting's paints when the app makes its base again
    ///     (the app's `TemplateRefinements.pin`), so the painter's color changes find their paints
    ///     and what the change didn't reach keeps its own. The paints keep their bits, kit paint's
    ///     mixing included (they are mixed already; with kit paint the paints are chosen first,
    ///     and kept when they mix to the pinned ones, below); a paint no area takes leaves. Nil or empty
    ///     chooses them, byte for byte as without. A drawing's settings ignore it (its paints
    ///     are its set's).
    public func generate(
        from image: RGBAImage,
        importance: Grid<Float>? = nil,
        lineArt: LineArtInput? = nil,
        cancel: CancellationCheck = .task,
        progress: (@Sendable (Float) -> Void)? = nil,
        observer: PipelineSnapshot.Observer? = nil,
        palette pinned: [PaletteColor]? = nil
    ) throws -> Output {
        let pinned = pinned.flatMap { $0.isEmpty ? nil : $0 }
        if let drawing = settings.drawing {
            return try DrawingGenerator.generate(
                from: image, settings: settings, drawing: drawing, cancel: cancel, progress: progress, observer: observer)
        }
        let clock = StageClock()
        progress?(0)
        let size = settings.workingSize(sourceWidth: image.width, sourceHeight: image.height)
        var working = try clock.measure("resample") {
            try Resample.area(image, width: size.width, height: size.height, cancel: cancel)
        }
        try cancel.throwIfCancelled()
        if let observer { try observer(SnapshotPictures.working(working, cancel: cancel)) }
        progress?(0.1)

        // Line art drawn from an edge map needs it; without one the template is classic.
        let input = settings.lineArt.style.usesEdgeMap ? lineArt : nil
        let segmentEnd: Float = input == nil ? 0.7 : 0.6
        var parameters = SegmentationParameters(settings: settings, width: working.width, height: working.height)
        // By the settings, not the edge map, so Auto's drafts (which have none) are scored on
        // the paint the book gets, and a book whose edge map failed keeps its flatter paint.
        if settings.lineArt.style == .coloringBook { parameters.flattenForColoringBook() }
        if let input { parameters.sizeFaces(byEyes: input.eyes, width: working.width, height: working.height) }
        // The writing's ink is traced and painted out first, so the paint ignores the letters.
        var writing: Writing?
        if let input, settings.lineArt.keepWriting, !input.writing.isEmpty {
            writing = try clock.measure("writing") {
                try Writing.find(
                    in: &working, areas: input.writing, minRadius: parameters.minRadius, cancel: cancel, clock: clock)
            }
            try cancel.throwIfCancelled()
        }
        // The segmentation and the line art cut from it, of the pinned paints when there are,
        // which `centers` (true OKLab, one per pinned paint) stand in for while pixels are assigned.
        func segmented(
            _ pinned: [PaletteColor]?, centers: [SIMD3<Float>]?, observer: PipelineSnapshot.Observer?,
            spanning span: ClosedRange<Float> = 0.1...0.7
        ) throws -> (Segmentation, [Float], LayeredLines.Plan?) {
            // Progress from 0.1 to 0.7, laid on `span`.
            let report = { (f: Float) in progress?(span.lowerBound + (f - 0.1) / 0.6 * (span.upperBound - span.lowerBound)) }
            var (segmentation, weights) = try clock.measure("segment") {
                try Segmenter.segment(
                    working, importance: importance, parameters: parameters, cancel: cancel, clock: clock,
                    progress: { report(0.1 + (segmentEnd - 0.1) * $0) }, observer: observer, pinned: pinned,
                    centers: centers)
            }
            try cancel.throwIfCancelled()
            report(segmentEnd)
            guard let input else { return (segmentation, weights, nil) }
            let result = try clock.measure("lineArt") {
                try LayeredLines.apply(
                    segmentation, input: input, importance: weights, settings: settings, photo: image, writing: writing,
                    cancel: cancel, clock: clock)
            }
            segmentation = result.segmentation
            try cancel.throwIfCancelled()
            if let observer { try observer(SnapshotPictures.lineArt(result)) }
            report(0.7)
            return (segmentation, weights, result)
        }
        // Kit paint's paints are mixed bolder than the regions' colors the segmentation fits, so
        // pinned ones can't be fitted as they are: the paints are chosen first as without a pin,
        // and if they mix to the pinned ones (the same photo and settings: a painting recovered,
        // a draft continued without its kept trail) the template is the one made before, byte
        // for byte. Otherwise each pinned paint is fitted as its color before mixing, by the mix
        // of the paint chosen here nearest it (painting-company row 278).
        let kit = settings.paintMix == .kit
        let twice = kit && pinned != nil
        let buffer = twice && observer != nil ? SnapshotBuffer() : nil
        var (segmentation, weights, plan) = try segmented(
            kit ? nil : pinned, centers: nil, observer: buffer?.observer ?? observer, spanning: twice ? 0.1...0.4 : 0.1...0.7)
        // Which paints are on a face, for kit paint's skin, while the importance is at hand.
        var faces = kit
            ? KitPaint.faces(of: segmentation, importance: weights, eyes: input?.eyes ?? [], photo: working) : nil
        var mixes = kit
        if kit, let pinned {
            let means = segmentation.palette
            let mixed = KitPaint.mix(means, space: segmentation.colorSpace, minDistance: settings.minPaletteDistance, faces: faces)
            if mixed != pinned, !mixed.isEmpty {
                let centers = pinned.map { paint in
                    let j = mixed.indices.min {
                        ColorScience.distance(mixed[$0].oklab, paint.oklab) < ColorScience.distance(mixed[$1].oklab, paint.oklab)
                    }!
                    return paint.oklab - mixed[j].oklab + means[j].oklab
                }
                // The first attempt's canvas-sized maps go before the second's are made.
                weights = []
                segmentation = Segmentation(
                    labels: RegionMap(width: 0, height: 0, repeating: 0), regionColor: [], palette: [],
                    colorSpace: segmentation.colorSpace)
                plan = nil
                (segmentation, weights, plan) = try segmented(pinned, centers: centers, observer: observer, spanning: 0.4...0.7)
                faces = nil
                mixes = false
            } else {
                if let buffer, let observer { for shot in buffer.shots { try observer(shot) } }
                progress?(0.7)
            }
        }
        // Drops the canvas-sized importance map before the vectorizer's own large buffers.
        weights = []

        let keepOut = LabelKeepOut(rects: writing?.keepOut ?? [], lines: plan?.drawnInterior.map(LabelKeepOut.Line.init) ?? [])
        var vector = try clock.measure("vectorize") {
            try Vectorizer.vectorizeWithStats(
                segmentation, settings: settings, keepOut: keepOut, detailRegions: plan?.detailRegions ?? [],
                guides: plan?.guides ?? [], cancel: cancel, clock: clock)
        }
        vector.template.pipelineVersion = Self.pipelineVersion
        // Before the line art's annotation, which reads the paints' lightness (writing on dark paint).
        if mixes {
            vector.template.palette = KitPaint.mix(
                vector.template.palette, space: vector.template.colorSpace, minDistance: settings.minPaletteDistance,
                faces: faces)
            // The output's paints are the template's, so pbn's rasters show what is painted.
            segmentation.palette = vector.template.palette
        }
        if let plan {
            try cancel.throwIfCancelled()
            vector.template.lineArt = try clock.measure("lineArt.annotate") {
                try LayeredLines.annotate(vector.template, plan: plan, cancel: cancel)
            }
        }
        if let observer { try observer(SnapshotPictures.vectorized(vector.template)) }
        progress?(1)
        return Output(
            template: vector.template, segmentation: segmentation, vectorStats: vector.stats,
            lineArtStats: plan?.stats, timings: clock.timings)
    }
}

/// The making-of pictures of an attempt the generator may set aside (kit paint with a pin),
/// passed on only if it's kept. Filled and read on the generating thread alone.
private final class SnapshotBuffer: @unchecked Sendable {
    var shots: [PipelineSnapshot] = []
    var observer: PipelineSnapshot.Observer { { [self] in shots.append($0) } }
}
