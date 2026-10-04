import CoreGraphics
import Foundation
import PaintCore

/// Turns photos into ready-to-save artwork drafts, off the main actor.
nonisolated enum ArtworkFactory {
    enum FactoryError: Error, Equatable {
        case missingSample
        /// Neither the stored photo nor the bundled sample an artwork was made from is available.
        case sourceUnavailable
    }

    @concurrent
    static func draft(
        sample: Sample, settings: GenerationSettings = GenerationSettings(),
        paintedFraction: Double? = nil, date: Date = .now,
        photoMaxPixelSize: Int = ArtworkStore.sourceMaxPixelSize
    ) async throws -> ArtworkDraft {
        guard let url = sample.url else { throw FactoryError.missingSample }
        let photo = try PhotoLoader.load(url: url, maxPixelSize: photoMaxPixelSize)
        let image = PhotoLoader.cgImage(from: photo)
        let template = try await self.template(from: photo, image: image, settings: settings, progress: nil)
        var progress: PaintProgress?
        if let paintedFraction {
            var painted = self.progress(painting: paintedFraction, of: template)
            // Plausible painting time for a demo in progress.
            painted.activeSeconds = Double(painted.paintedCount) * 3
            progress = painted
        }
        return ArtworkDraft(
            title: sample.title, template: template, settings: settings, photo: image,
            sampleName: sample.id, progress: progress, date: date)
    }

    /// The template of `photo`, generated the way the create flow does it: subject importance
    /// from Vision (when available) guides colors and detail, and line art (the coloring book by
    /// default) draws from the photo's `LineArtInputs`: the drawing, the contours, the eyes and
    /// the subjects. Polls task cancellation.
    @concurrent
    static func template(
        from photo: RGBAImage, settings: GenerationSettings, progress: (@Sendable (Float) -> Void)?
    ) async throws -> Template {
        try await template(from: photo, image: PhotoLoader.cgImage(from: photo), settings: settings, progress: progress)
    }

    @concurrent
    private static func template(
        from photo: RGBAImage, image: CGImage?, settings: GenerationSettings, progress: (@Sendable (Float) -> Void)?
    ) async throws -> Template {
        let importance = image.flatMap(SubjectImportance.map(for:))
        // Computed for this one template: the photo needn't take a place in the cache.
        let lineArt = try await LineArtInputs.forGeneration(of: image, settings: settings.lineArt, cached: false)
        return try TemplateGenerator(settings: settings)
            .generate(from: photo, importance: importance, lineArt: lineArt, cancel: .task, progress: progress)
            .template
    }

    /// The photo an artwork was made from, as the create flow loaded it: the stored
    /// `source.jpg`, else the bundled sample it came from.
    static func sourcePhoto(of artwork: Artwork, in store: ArtworkStore) throws -> RGBAImage {
        if store.hasSource(artwork.id) {
            return try PhotoLoader.load(url: store.url(.source, of: artwork.id), maxPixelSize: ArtworkStore.sourceMaxPixelSize)
        }
        guard let url = sampleURL(of: artwork) else { throw FactoryError.sourceUnavailable }
        return try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize)
    }

    /// Whether `sourcePhoto(of:in:)` has a photo to regenerate the artwork from.
    static func canRegenerate(_ artwork: Artwork, store: ArtworkStore) -> Bool {
        store.hasSource(artwork.id) || sampleURL(of: artwork) != nil
    }

    private static func sampleURL(of artwork: Artwork) -> URL? {
        artwork.sampleName.flatMap(Sample.named)?.url
    }

    /// Progress with `fraction` of the regions painted the way people paint: color by
    /// color, in palette order.
    static func progress(painting fraction: Double, of t: Template) -> PaintProgress {
        var progress = PaintProgress(regionCount: t.regions.count)
        let target = Int((Double(t.regions.count) * min(max(fraction, 0), 1)).rounded())
        var byColor = [[Int]](repeating: [], count: t.palette.count)
        for (index, region) in t.regions.enumerated() { byColor[Int(region.colorIndex)].append(index) }
        outer: for regions in byColor {
            for region in regions {
                if progress.paintedCount >= target { break outer }
                progress.paint(region)
            }
        }
        return progress
    }
}
