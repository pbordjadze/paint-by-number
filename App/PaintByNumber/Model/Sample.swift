import CoreGraphics
import Foundation
import os
import PaintCore

/// A picture bundled with the app (`Resources/Samples/<id>.jpg`).
///
/// `Resources/Samples/library.json` is the library: the pictures the Samples pane offers, in
/// their curated order, and where each one comes from (a record per picture, with its license
/// evidence). Creator, year, credit and license are proper names and facts, read from there
/// and shown verbatim in every language. Titles are translated, so they live here instead
/// (`title(of:)`, keyed `sample.<id>` in the string catalog). `SampleLibraryTests` keeps the
/// file, the titles and the bundled JPEGs in step.
nonisolated struct Sample: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Decodable, Sendable {
        case painting, photograph
    }

    /// Who made a picture and the terms it ships under, as its `library.json` record has them.
    struct Provenance: Hashable, Decodable, Sendable {
        let kind: Kind
        let creator: String
        /// As the source dates the work: "1968", "c. 1830–32".
        let year: String
        /// The collection or agency the file comes from.
        let credit: String
        let license: String
    }

    let id: String
    let title: String
    /// Nil only for the retired samples, whose provenance was never recorded.
    let provenance: Provenance?

    init(id: String, title: String, provenance: Provenance? = nil) {
        self.id = id
        self.title = title
        self.provenance = provenance
    }

    var url: URL? { Bundle.main.url(forResource: id, withExtension: "jpg") }

    /// The pictures the Samples pane offers, in the order of `library.json` (which is
    /// authoritative: curating the library reorders the file, not this code).
    static let all: [Sample] = {
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            Log.library.fault("library.json is missing from the bundle")
            return []
        }
        return Sample.listed(in: data)
    }()

    /// The pictures of one kind, in the library's order: a section of the Samples pane.
    static func all(of kind: Kind) -> [Sample] { all.filter { $0.provenance?.kind == kind } }

    /// Prepared on first launch so the gallery starts with something to paint: a painting and
    /// a photograph, the library's best first impression.
    static let starters: [Sample] = ["great-wave", "earthrise"].compactMap { id in Sample.all.first { $0.id == id } }

    /// Any bundled picture, offered or retired: saved paintings name theirs (`Artwork.sampleName`).
    static func named(_ id: String) -> Sample? {
        all.first { $0.id == id } ?? retired.first { $0.id == id }
    }

    /// The pictures a `library.json` lists, in its order, each with its title. A record without
    /// a title, or a file that doesn't decode, lists nothing (and `SampleLibraryTests` fails).
    static func listed(in data: Data) -> [Sample] {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            Log.library.fault("library.json doesn't decode: \(String(describing: error), privacy: .public)")
            return []
        }
        return records.compactMap { record in
            guard let title = title(of: record.id) else {
                Log.library.fault("library.json lists \(record.id, privacy: .public), which has no title")
                return nil
            }
            return Sample(id: record.id, title: title, provenance: record.provenance)
        }
    }

    /// A picture's record in `library.json`. Its other fields (source, license evidence,
    /// checksum, …) are for the people who audit the library.
    private struct Record: Decodable {
        let id: String
        let provenance: Provenance

        private enum CodingKeys: String, CodingKey { case id }

        init(from decoder: any Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
            provenance = try Provenance(from: decoder)
        }
    }

    /// The title of each picture `library.json` lists, translatable. The comment tells
    /// translators which work it is, so a title can follow the work's name in their language.
    private static func title(of id: String) -> String? {
        switch id {
        case "great-wave": String(
            localized: "sample.great-wave", defaultValue: "The Great Wave",
            comment: "Title of a bundled picture: Katsushika Hokusai's woodblock print Under the Wave off Kanagawa, known as The Great Wave. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        case "earthrise": String(
            localized: "sample.earthrise", defaultValue: "Earthrise",
            comment: "Title of a bundled picture: the Apollo 8 photograph of the Earth rising over the Moon's horizon, known as Earthrise. Shown on its sample tile, in Acknowledgements and as its painting's default title")
        default: nil
        }
    }

    /// The six photos the app shipped with before the curated library. Saved paintings name
    /// them and regenerate from them when they have no stored photo, so they stay in the
    /// bundle; their provenance was never recorded, so they are neither offered nor credited.
    /// The quality regression and the benchmark run on them (`tools/regression.py`).
    static let retired: [Sample] = [
        Sample(id: "parrots", title: String(
            localized: "sample.parrots", defaultValue: "Parrots",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "hibiscus", title: String(
            localized: "sample.hibiscus", defaultValue: "Hibiscus",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "lighthouse", title: String(
            localized: "sample.lighthouse", defaultValue: "Lighthouse",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "barn", title: String(
            localized: "sample.barn", defaultValue: "Red Barn",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "espresso", title: String(
            localized: "sample.espresso", defaultValue: "Espresso",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
        Sample(id: "regatta", title: String(
            localized: "sample.regatta", defaultValue: "Regatta",
            comment: "Name of a bundled sample photo, shown as its default painting title")),
    ]
}

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
        let template = try self.template(from: photo, image: image, settings: settings, progress: nil)
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
    /// from Vision (when available) guides colors and detail. Polls task cancellation.
    static func template(
        from photo: RGBAImage, settings: GenerationSettings, progress: (@Sendable (Float) -> Void)?
    ) throws -> Template {
        try template(from: photo, image: PhotoLoader.cgImage(from: photo), settings: settings, progress: progress)
    }

    private static func template(
        from photo: RGBAImage, image: CGImage?, settings: GenerationSettings, progress: (@Sendable (Float) -> Void)?
    ) throws -> Template {
        let importance = image.flatMap(SubjectImportance.map(for:))
        return try TemplateGenerator(settings: settings)
            .generate(from: photo, importance: importance, cancel: .task, progress: progress)
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
