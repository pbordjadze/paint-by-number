import Foundation

/// What a new painting's preview shows beside the photo in the create flow: the painting as it
/// will look finished (every painter's, since Settings › Preview left on November 17, 2026: a
/// picked picture skips the preview), or its line art: the drawing alone on the canvas
/// sheet's paper, its lines as the canvas draws them, which shows them better while they are
/// tuned (`CompareView`). A way of looking only: it never changes a template.
nonisolated enum PreviewStyle: String, CaseIterable, Identifiable, Sendable {
    case painting, lineArt

    static let `default` = PreviewStyle.painting

    var id: String { rawValue }

    /// The caption of the comparison's layer.
    var name: String {
        switch self {
        case .painting: String(localized: "Painting")
        case .lineArt: String(localized: "Line Art")
        }
    }
}
