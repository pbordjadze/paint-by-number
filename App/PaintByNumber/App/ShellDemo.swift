#if DEBUG
import Foundation

/// Demo scenarios owned by the app shell (see `DemoMode`). Each uses a throwaway library
/// seeded deterministically from the bundled samples.
///
/// - `gallery`, `gallery-dark`: six paintings at various stages, one of them a favorite.
/// - `gallery-favorites`, `gallery-favorites-dark`: the same library with two favorites and the Show
///   filter on Favorites.
/// - `gallery-search`, `gallery-search-dark`: the same library with "re" typed in the search field
///   (two results).
/// - `gallery-no-favorites-long-text`: the Favorites filter with nothing favorited (its empty state),
///   with every localized string twice as long.
/// - `gallery-empty`: the empty state.
/// - `create`, `create-dark`: the photo picker step of the create flow.
/// - `create-samples`: the same step on its Samples pane (iPhone; iPad shows both).
/// - `create-preview`, `create-preview-dark`: a sample generated, comparison at half.
/// - `create-from-file`: a photo file opened as if shared from another app ("Open in Paint by
///   Numbers"): the create flow on that photo's preview, titled with the file's name. The file is
///   a bundled sample written to the temporary directory at launch (`DemoMode.openFileURL`).
/// - `settings`: the settings sheet over the gallery.
/// - `settings-acknowledgements`: the settings sheet on its Acknowledgements screen.
/// - `gallery-open`: a painting opened from its card (zoom transition into `PaintView`).
/// - `gallery-damaged`: a painting whose template file is damaged, opened: the recovery screen.
/// - `gallery-timelapse`: a finished painting's time-lapse being made (progress sheet).
/// - `gallery-long-text`, `settings-long-text`: `gallery` (with a deletion, so its Undo toast is up)
///   and `settings` with every localized string twice as long: `ci/screenshots.sh` adds
///   `-NSDoubleLocalizedStrings YES` to scenarios named `*-long-text`, the pseudo-localization that
///   shows where translations (German, Finnish, ...) would truncate or overflow.
enum ShellDemo: Equatable {
    case gallery, galleryFavorites, gallerySearch, galleryNoFavorites, galleryLongText, galleryEmpty, galleryOpen,
         galleryDamaged, galleryTimelapse, create, createSamples, createPreview, createFromFile, settings,
         settingsLongText, settingsAcknowledgements

    static let current: ShellDemo? = {
        switch DemoMode.scenario {
        case "gallery", "gallery-dark": .gallery
        case "gallery-favorites", "gallery-favorites-dark": .galleryFavorites
        case "gallery-search", "gallery-search-dark": .gallerySearch
        case "gallery-no-favorites-long-text": .galleryNoFavorites
        case "gallery-long-text": .galleryLongText
        case "gallery-empty": .galleryEmpty
        case "gallery-open": .galleryOpen
        case "gallery-damaged": .galleryDamaged
        case "gallery-timelapse": .galleryTimelapse
        case "create", "create-dark": .create
        case "create-samples": .createSamples
        case "create-preview", "create-preview-dark": .createPreview
        case "create-from-file": .createFromFile
        case "settings": .settings
        case "settings-long-text": .settingsLongText
        case "settings-acknowledgements": .settingsAcknowledgements
        default: nil
        }
    }()

    /// The Show filter starts on Favorites.
    var showsFavoritesOnly: Bool { self == .galleryFavorites || self == .galleryNoFavorites }

    /// The bundled samples whose paintings are favorites.
    private var favoriteSamples: [String] {
        switch self {
        case .gallery, .gallerySearch: ["lighthouse"]
        case .galleryFavorites: ["lighthouse", "regatta"]
        default: []
        }
    }

    /// The search field starts with this text: it finds "Red Barn" and "Regatta".
    var searchText: String? { self == .gallerySearch ? "re" : nil }

    var opensCreateFlow: Bool { self == .create || self == .createSamples || self == .createPreview }

    var opensSettings: Bool { self == .settings || self == .settingsLongText || self == .settingsAcknowledgements }

    var previewSample: Sample? { self == .createPreview ? Sample.named("parrots") : nil }

    /// How long `create` and `create-samples` give the library picker to load before they
    /// signal readiness: it runs out of process and reports nothing when its grid is up. The
    /// value is empirical: raise it if CI's `create` screenshots show the picker still loading
    /// (`*-steps.log` gives each scenario's time to readiness, launch included).
    static let pickerLoadAllowance: Duration = .seconds(3)

    func prepare(_ library: Library) {
        switch self {
        case .gallery, .galleryFavorites, .gallerySearch, .galleryNoFavorites:
            let favorites = favoriteSamples
            library.seed(Self.galleryItems, completion: { _ in
                for artwork in library.artworks {
                    if let sample = artwork.sampleName, favorites.contains(sample) { library.setFavorite(artwork.id, true) }
                }
                DemoMode.markReady()
            })
        case .galleryLongText:
            library.seed(Self.galleryItems, completion: { _ in
                // The newest deletion keeps its Undo toast up for `Library.undoWindow`, well past the screenshot.
                if let id = library.finished.last?.id { library.delete(id) }
                DemoMode.markReady()
            })
        case .galleryOpen:
            library.seed([Library.SeedItem(sample: Sample.all[0], painted: 0.42, photoMaxPixelSize: 560)])
        case .galleryDamaged:
            library.seed([Library.SeedItem(sample: Sample.all[0], painted: 0.42, photoMaxPixelSize: 560)]) { _ in
                // Synchronous on purpose: this runs in the same main-actor job that empties
                // `placeholders`, so the file is damaged before SwiftUI's next update delivers
                // the `onChange` that opens the painting (`AppShellView`).
                guard let id = library.artworks.first?.id else { return }
                try? Data("damaged".utf8).write(to: library.store.url(.template, of: id))
            }
        case .galleryTimelapse:
            library.seed([Library.SeedItem(sample: Sample.all[1], painted: 1, photoMaxPixelSize: 560)])
        case .create, .createSamples, .createPreview, .createFromFile, .galleryEmpty, .settings, .settingsLongText,
             .settingsAcknowledgements:
            break
        }
    }

    /// Six paintings at various stages: four in progress, two finished.
    private static var galleryItems: [Library.SeedItem] {
        let hour: TimeInterval = 3600
        let items: [(Int, Double, TimeInterval)] = [
            (0, 0.42, 1), (2, 0.68, 3), (3, 0.12, 26), (4, 0, 50), (1, 1, 5), (5, 1, 80),
        ]
        return items.map { sample, painted, hours in
            Library.SeedItem(sample: Sample.all[sample], painted: painted, age: hours * hour, photoMaxPixelSize: 560)
        }
    }

    /// Scenarios that are complete as soon as the shell appears (the rest signal readiness
    /// once their content has been generated or loaded).
    var isReadyOnAppear: Bool { self == .galleryEmpty || opensSettings }
}
#endif
