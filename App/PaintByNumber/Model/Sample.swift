import CoreGraphics
import Foundation
import PaintCore

/// A photo bundled with the app (`Resources/Samples/<id>.jpg`).
nonisolated struct Sample: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    var url: URL? { Bundle.main.url(forResource: id, withExtension: "jpg") }

    static let all: [Sample] = [
        Sample(id: "parrots", title: "Parrots"),
        Sample(id: "hibiscus", title: "Hibiscus"),
        Sample(id: "lighthouse", title: "Lighthouse"),
        Sample(id: "barn", title: "Red Barn"),
        Sample(id: "espresso", title: "Espresso"),
        Sample(id: "regatta", title: "Regatta"),
    ]

    /// Prepared on first launch so the gallery starts with something to paint.
    static let starters = [all[0], all[1]]

    static func named(_ id: String) -> Sample? { all.first { $0.id == id } }
}

/// Turns photos into ready-to-save artwork drafts, off the main actor.
nonisolated enum ArtworkFactory {
    enum FactoryError: Error { case missingSample }

    @concurrent
    static func draft(
        sample: Sample, settings: GenerationSettings = GenerationSettings(),
        paintedFraction: Double? = nil, date: Date = .now,
        photoMaxPixelSize: Int = ArtworkStore.sourceMaxPixelSize
    ) async throws -> ArtworkDraft {
        guard let url = sample.url else { throw FactoryError.missingSample }
        let photo = try PhotoLoader.load(url: url, maxPixelSize: photoMaxPixelSize)
        let image = PhotoLoader.cgImage(from: photo)
        let importance = image.flatMap(SubjectImportance.map(for:))
        let template = try TemplateGenerator(settings: settings).generate(from: photo, importance: importance).template
        var progress: PaintProgress?
        if let paintedFraction {
            var painted = self.progress(painting: paintedFraction, of: template)
            // Plausible painting time for a demo in progress.
            painted.activeSeconds = Double(painted.paintedCount) * 1.3
            progress = painted
        }
        return ArtworkDraft(
            title: sample.title, template: template, settings: settings, photo: image,
            sampleName: sample.id, progress: progress, date: date)
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
