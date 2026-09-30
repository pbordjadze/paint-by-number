import Foundation

/// Demo scenarios owned by the app shell (see `DemoMode`). Each uses a throwaway library
/// seeded deterministically from the bundled samples.
///
/// - `gallery`, `gallery-dark`: six paintings at various stages.
/// - `gallery-empty`: the empty state.
/// - `create`, `create-dark`: the photo picker step of the create flow.
/// - `create-preview`, `create-preview-dark`: a sample generated, comparison at half.
/// - `settings`: the settings sheet over the gallery.
/// - `gallery-open`: a painting opened from its card (zoom transition into `PaintView`).
/// - `gallery-timelapse`: a finished painting's time-lapse being made (progress sheet).
enum ShellDemo: Equatable {
    case gallery, galleryEmpty, galleryOpen, galleryTimelapse, create, createPreview, settings

    static let current: ShellDemo? = {
        switch DemoMode.scenario {
        case "gallery", "gallery-dark": .gallery
        case "gallery-empty": .galleryEmpty
        case "gallery-open": .galleryOpen
        case "gallery-timelapse": .galleryTimelapse
        case "create", "create-dark": .create
        case "create-preview", "create-preview-dark": .createPreview
        case "settings": .settings
        default: nil
        }
    }()

    var opensCreateFlow: Bool { self == .create || self == .createPreview }

    var previewSample: Sample? { self == .createPreview ? Sample.named("parrots") : nil }

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
        case .galleryTimelapse:
            library.seed([Library.SeedItem(sample: Sample.all[1], painted: 1, photoMaxPixelSize: 560)])
        case .create, .createPreview, .galleryEmpty, .settings:
            break
        }
    }

    /// Scenarios that are complete as soon as the shell appears (the rest signal readiness
    /// once their content has been generated or loaded).
    var isReadyOnAppear: Bool { self == .create || self == .galleryEmpty || self == .settings }
}
