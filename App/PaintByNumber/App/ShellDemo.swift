import Foundation

/// Demo scenarios owned by the app shell (see `DemoMode`). Each uses a throwaway library
/// seeded deterministically from the bundled samples.
///
/// - `gallery`, `gallery-dark`: six paintings at various stages.
/// - `gallery-empty`: the empty state.
/// - `create`, `create-dark`: the photo picker step of the create flow.
/// - `create-preview`, `create-preview-dark`: a sample generated, comparison at half.
/// - `settings`: the settings sheet over the gallery.
enum ShellDemo: Equatable {
    case gallery, galleryEmpty, create, createPreview, settings

    static let current: ShellDemo? = {
        switch DemoMode.scenario {
        case "gallery", "gallery-dark": .gallery
        case "gallery-empty": .galleryEmpty
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
            library.seed([
                .init(sample: Sample.all[0], painted: 0.42, age: 1 * hour),
                .init(sample: Sample.all[2], painted: 0.68, age: 3 * hour),
                .init(sample: Sample.all[3], painted: 0.12, age: 26 * hour),
                .init(sample: Sample.all[4], painted: 0, age: 50 * hour),
                .init(sample: Sample.all[1], painted: 1, age: 5 * hour),
                .init(sample: Sample.all[5], painted: 1, age: 80 * hour),
            ])
        case .create, .createPreview, .galleryEmpty, .settings:
            break
        }
    }
}
