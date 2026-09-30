#if DEBUG
import Foundation

/// Demo scenarios owned by the app shell (see `DemoMode`). Each uses a throwaway library
/// seeded deterministically from the bundled samples.
///
/// - `gallery`, `gallery-dark`: six paintings at various stages.
/// - `gallery-empty`: the empty state.
/// - `create`, `create-dark`: the photo picker step of the create flow.
/// - `create-samples`: the same step on its Samples pane (iPhone; iPad shows both).
/// - `create-preview`, `create-preview-dark`: a sample generated, comparison at half.
/// - `settings`: the settings sheet over the gallery.
/// - `settings-acknowledgements`: the settings sheet on its Acknowledgements screen.
/// - `gallery-open`: a painting opened from its card (zoom transition into `PaintView`).
/// - `gallery-damaged`: a painting whose template file is damaged, opened: the recovery screen.
/// - `gallery-timelapse`: a finished painting's time-lapse being made (progress sheet).
enum ShellDemo: Equatable {
    case gallery, galleryEmpty, galleryOpen, galleryDamaged, galleryTimelapse, create, createSamples, createPreview,
         settings, settingsAcknowledgements

    static let current: ShellDemo? = {
        switch DemoMode.scenario {
        case "gallery", "gallery-dark": .gallery
        case "gallery-empty": .galleryEmpty
        case "gallery-open": .galleryOpen
        case "gallery-damaged": .galleryDamaged
        case "gallery-timelapse": .galleryTimelapse
        case "create", "create-dark": .create
        case "create-samples": .createSamples
        case "create-preview", "create-preview-dark": .createPreview
        case "settings": .settings
        case "settings-acknowledgements": .settingsAcknowledgements
        default: nil
        }
    }()

    var opensCreateFlow: Bool { self == .create || self == .createSamples || self == .createPreview }

    var opensSettings: Bool { self == .settings || self == .settingsAcknowledgements }

    var previewSample: Sample? { self == .createPreview ? Sample.named("parrots") : nil }

    /// How long `create` and `create-samples` give the library picker to load before they
    /// signal readiness: it runs out of process and reports nothing when its grid is up. The
    /// value is empirical: raise it if CI's `create` screenshots show the picker still loading
    /// (`*-steps.log` gives each scenario's time to readiness, launch included).
    static let pickerLoadAllowance: Duration = .seconds(3)

    func prepare(_ library: Library) {
        switch self {
        case .gallery:
            let hour: TimeInterval = 3600
            let items: [(Int, Double, TimeInterval)] = [
                (0, 0.42, 1), (2, 0.68, 3), (3, 0.12, 26), (4, 0, 50), (1, 1, 5), (5, 1, 80),
            ]
            library.seed(items.map { sample, painted, hours in
                Library.SeedItem(sample: Sample.all[sample], painted: painted, age: hours * hour, photoMaxPixelSize: 560)
            }, completion: { _ in DemoMode.markReady() })
        case .galleryOpen:
            library.seed([Library.SeedItem(sample: Sample.all[0], painted: 0.42, photoMaxPixelSize: 560)])
        case .galleryDamaged:
            library.seed([Library.SeedItem(sample: Sample.all[0], painted: 0.42, photoMaxPixelSize: 560)]) {
                // Synchronous on purpose: this runs in the same main-actor job that empties
                // `placeholders`, so the file is damaged before SwiftUI's next update delivers
                // the `onChange` that opens the painting (`AppShellView`).
                guard let id = library.artworks.first?.id else { return }
                try? Data("damaged".utf8).write(to: library.store.url(.template, of: id))
            }
        case .galleryTimelapse:
            library.seed([Library.SeedItem(sample: Sample.all[1], painted: 1, photoMaxPixelSize: 560)])
        case .create, .createSamples, .createPreview, .galleryEmpty, .settings, .settingsAcknowledgements:
            break
        }
    }

    /// Scenarios that are complete as soon as the shell appears (the rest signal readiness
    /// once their content has been generated or loaded).
    var isReadyOnAppear: Bool { self == .galleryEmpty || opensSettings }
}
#endif
