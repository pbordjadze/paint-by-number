#if DEBUG
import CoreGraphics
import Foundation
import PaintCore

/// Demo scenarios owned by the app shell (see `DemoMode`). Each uses a throwaway library
/// seeded deterministically from the bundled pictures (`pictures`): the ones a viewer judges
/// the app by show the curated library, the rest the retired samples.
///
/// - `gallery`, `gallery-dark`: the library's first six pictures (all of them while it holds
///   fewer) painted to various stages, the third a favorite.
/// - `gallery-favorites`, `gallery-favorites-dark`: six retired samples' paintings with two
///   favorites and the Show filter on Favorites.
/// - `gallery-search`, `gallery-search-dark`: the same paintings with "re" typed in the search
///   field (two results).
/// - `gallery-no-favorites-long-text`: the Favorites filter with nothing favorited (its empty state),
///   with every localized string twice as long.
/// - `gallery-empty`: the empty state.
/// - `create`, `create-dark`: the photo picker step of the create flow.
/// - `create-samples`, `create-samples-long-text`: the same step on its Samples pane (iPhone;
///   iPad shows both); the second with every localized string twice as long.
/// - `create-samples-paintings`, `create-samples-photographs`: the Samples pane scrolled to its
///   Paintings or Photographs section.
/// - `create-preview`, `create-preview-dark`: the painting starter generated, comparison at half.
/// - `create-suggested`: the photograph starter on its suggested settings ("Suggested for this
///   photo" chip).
/// - `create-custom`, `create-custom-long-text`: the parrots sample after Detail moved off the
///   suggestion (the chip offers Reset to Suggested); the second with every localized string
///   twice as long.
/// - `create-from-file`: a photo file opened as if shared from another app ("Open in Paint by
///   Numbers"): the create flow on that photo's preview, titled with the file's name. The file is
///   a bundled sample written to the temporary directory at launch (`DemoMode.openFileURL`).
/// - `settings`: the settings sheet over the gallery.
/// - `settings-acknowledgements`: the settings sheet on its Acknowledgements screen.
/// - `settings-advanced`, `settings-advanced-dark`, `settings-advanced-long-text`: Settings ›
///   Advanced at the default settings (a coloring book), previewing The Great Wave (pushed inside
///   the sheet on iPhone, over the whole window on iPad); the last with every localized string
///   twice as long.
/// - `settings-advanced-layered`: the same with Layered lines, previewing the freight train at
///   2×, scrolled to Line Appearance.
/// - `settings-advanced-tuned`: the same with three pipeline multipliers moved, previewing the
///   red fox, scrolled to Pipeline with every effect measured.
/// - `settings-advanced-effects`: the same at the defaults, scrolled to Sounds & Effects with
///   the color finished jingle switched off.
/// - `gallery-open`: a painting opened from its card (zoom transition into `PaintView`).
/// - `gallery-damaged`: a painting whose template file is damaged, opened: the recovery screen.
/// - `gallery-timelapse`: a finished painting's time-lapse being made (progress sheet).
/// - `gallery-long-text`, `gallery-timelapse-long-text`, `settings-long-text`: the retired
///   samples' gallery (with a deletion, so its Undo toast is up), `gallery-timelapse` and
///   `settings` with every localized string twice as long: `ci/screenshots.sh` adds
///   `-NSDoubleLocalizedStrings YES` to scenarios named `*-long-text`, the pseudo-localization that
///   shows where translations (German, Finnish, ...) would truncate or overflow.
enum ShellDemo: Equatable {
    case gallery, galleryFavorites, gallerySearch, galleryNoFavorites, galleryLongText, galleryEmpty, galleryOpen,
         galleryDamaged, galleryTimelapse, galleryTimelapseLongText, create, createSamples, createSamplesPaintings,
         createSamplesPhotographs, createPreview, createSuggested, createCustom, createFromFile, settings,
         settingsLongText, settingsAcknowledgements, settingsAdvanced, settingsAdvancedLayered, settingsAdvancedTuned,
         settingsAdvancedEffects

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
        case "gallery-timelapse-long-text": .galleryTimelapseLongText
        case "create", "create-dark": .create
        case "create-samples", "create-samples-long-text": .createSamples
        case "create-samples-paintings": .createSamplesPaintings
        case "create-samples-photographs": .createSamplesPhotographs
        case "create-preview", "create-preview-dark": .createPreview
        case "create-suggested": .createSuggested
        case "create-custom", "create-custom-long-text": .createCustom
        case "create-from-file": .createFromFile
        case "settings": .settings
        case "settings-long-text": .settingsLongText
        case "settings-acknowledgements": .settingsAcknowledgements
        case "settings-advanced", "settings-advanced-dark", "settings-advanced-long-text": .settingsAdvanced
        case "settings-advanced-layered": .settingsAdvancedLayered
        case "settings-advanced-tuned": .settingsAdvancedTuned
        case "settings-advanced-effects": .settingsAdvancedEffects
        default: nil
        }
    }()

    /// The Show filter starts on Favorites.
    var showsFavoritesOnly: Bool { self == .galleryFavorites || self == .galleryNoFavorites }

    /// Whether the scenario shows the curated library: the ones a viewer judges the app by do,
    /// by position (`Sample.all`, `Sample.starters`), so curating the library needs no edit
    /// here. The rest, and UI tests that name paintings (`-demoRetiredSamples YES`), keep the
    /// retired samples, whose titles and templates never change.
    private var showsLibrary: Bool {
        (self == .gallery || self == .createPreview || self == .createSuggested) && !DemoMode.usesRetiredSamples
    }

    /// The pictures the gallery scenarios paint, by position.
    private var pictures: [Sample] { showsLibrary ? Sample.all : Sample.retired }

    /// The pictures whose paintings are favorites, by position in `pictures` (of the retired
    /// samples: Lighthouse, and Regatta).
    private var favoriteSamples: [String] {
        let positions: [Int] = switch self {
        case .gallery, .gallerySearch: [2]
        case .galleryFavorites: [2, 5]
        default: []
        }
        return positions.filter { $0 < pictures.count }.map { pictures[$0].id }
    }

    /// The search field starts with this text: it finds "Red Barn" and "Regatta".
    var searchText: String? { self == .gallerySearch ? "re" : nil }

    var sharesTimelapse: Bool { self == .galleryTimelapse || self == .galleryTimelapseLongText }

    var opensCreateFlow: Bool {
        self == .create || opensSamples || self == .createPreview || self == .createSuggested || self == .createCustom
    }

    /// The create flow starts on its Samples pane (iPhone; iPad shows both panes).
    var opensSamples: Bool { self == .createSamples || self == .createSamplesPaintings || self == .createSamplesPhotographs }

    /// The Samples pane starts scrolled to this section.
    var samplesSection: Sample.Kind? {
        switch self {
        case .createSamplesPaintings: .painting
        case .createSamplesPhotographs: .photograph
        default: nil
        }
    }

    var opensSettings: Bool {
        self == .settings || self == .settingsLongText || self == .settingsAcknowledgements || opensAdvanced
    }

    var opensAdvanced: Bool {
        self == .settingsAdvanced || self == .settingsAdvancedLayered || self == .settingsAdvancedTuned
            || self == .settingsAdvancedEffects
    }

    /// The library picture Settings › Advanced previews.
    var advancedPicture: String? {
        switch self {
        case .settingsAdvanced, .settingsAdvancedEffects: "great-wave"
        case .settingsAdvancedLayered: "santa-fe-freight"
        case .settingsAdvancedTuned: "red-fox"
        default: nil
        }
    }

    /// The row Settings › Advanced scrolls to once its preview is ready.
    var advancedScrollAnchor: String? {
        switch self {
        case .settingsAdvancedLayered: "advanced-appearance"
        case .settingsAdvancedTuned: "advanced-pipeline"
        case .settingsAdvancedEffects: "advanced-effects"
        default: nil
        }
    }

    /// The zoom the preview moves to once it is ready.
    var advancedZoom: CGFloat? { self == .settingsAdvancedLayered ? 2 : nil }

    var previewSample: Sample? {
        switch self {
        // The library's painting and photograph starters.
        case .createPreview: showsLibrary ? Sample.starters.first : Sample.named("parrots")
        case .createSuggested: showsLibrary ? Sample.starters.last : Sample.named("lighthouse")
        case .createCustom: Sample.named("parrots")
        default: nil
        }
    }

    /// The painter moves Detail once the suggestion is ready, so the settings become custom.
    var movesASlider: Bool { self == .createCustom }

    /// How long `create` and the `create-samples` scenarios give the library picker (and the
    /// sample tiles) to load before they signal readiness: the picker runs out of process and
    /// reports nothing when its grid is up. The value is empirical: raise it if CI's `create`
    /// screenshots show the picker still loading (`*-steps.log` gives each scenario's time to
    /// readiness, launch included).
    static let pickerLoadAllowance: Duration = .seconds(3)

    func prepare(_ library: Library) {
        switch self {
        case .gallery, .galleryFavorites, .gallerySearch, .galleryNoFavorites:
            let favorites = favoriteSamples
            library.seed(galleryItems, completion: { _ in
                for artwork in library.artworks {
                    if let sample = artwork.sampleName, favorites.contains(sample) { library.setFavorite(artwork.id, true) }
                }
                DemoMode.markReady()
            })
        case .galleryLongText:
            library.seed(galleryItems, completion: { _ in
                // The newest deletion keeps its Undo toast up for `Library.undoWindow`, well past the screenshot.
                if let id = library.finished.last?.id { library.delete(id) }
                DemoMode.markReady()
            })
        case .galleryOpen:
            library.seed([Library.SeedItem(sample: pictures[0], painted: 0.42, photoMaxPixelSize: 560)])
        case .galleryDamaged:
            library.seed([Library.SeedItem(sample: pictures[0], painted: 0.42, photoMaxPixelSize: 560)]) { _ in
                // Synchronous on purpose: this runs in the same main-actor job that empties
                // `placeholders`, so the file is damaged before SwiftUI's next update delivers
                // the `onChange` that opens the painting (`AppShellView`).
                guard let id = library.artworks.first?.id else { return }
                try? Data("damaged".utf8).write(to: library.store.url(.template, of: id))
            }
        case .galleryTimelapse, .galleryTimelapseLongText:
            library.seed([Library.SeedItem(sample: pictures[1], painted: 1, photoMaxPixelSize: 560)])
        case .settingsAdvancedLayered:
            register(LineArtSettings(style: .layered), forKey: SettingsKey.lineArt)
        case .settingsAdvancedTuned:
            register(PipelineTuning(smoothing: 1.5, minimumCellSize: 2, accentColors: 0.5), forKey: SettingsKey.pipelineTuning)
        case .settingsAdvancedEffects:
            UserDefaults.standard.register(defaults: [PaintingEffect.colorJingle.key: false])
        case .create, .createSamples, .createSamplesPaintings, .createSamplesPhotographs, .createPreview,
             .createSuggested, .createCustom, .createFromFile, .galleryEmpty, .settings, .settingsLongText,
             .settingsAcknowledgements, .settingsAdvanced:
            break
        }
    }

    /// Registered, not stored: the setting lasts for this launch, so the next scenario on the
    /// same simulator starts from the defaults.
    private func register<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.register(defaults: [key: data])
    }

    /// The first six pictures painted to various stages: four in progress, two finished
    /// (with two pictures, one of each).
    private var galleryItems: [Library.SeedItem] {
        let hour: TimeInterval = 3600
        // By position: the fraction painted, and the hours since it was last painted.
        let stages: [(painted: Double, hours: TimeInterval)] = [(0.42, 1), (1, 5), (0.68, 3), (0.12, 26), (0, 50), (1, 80)]
        return zip(pictures, stages).map { sample, stage in
            Library.SeedItem(sample: sample, painted: stage.painted, age: stage.hours * hour, photoMaxPixelSize: 560)
        }
    }

    /// Scenarios that are complete as soon as the shell appears (the rest signal readiness
    /// once their content has been generated or loaded).
    var isReadyOnAppear: Bool { self == .galleryEmpty || (opensSettings && !opensAdvanced) }
}
#endif
