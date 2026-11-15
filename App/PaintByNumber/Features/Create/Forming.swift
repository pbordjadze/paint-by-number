import Foundation

/// The picture forming as one act (painting-company row 293), for a picture picked on the Paint
/// page in SideStore and Debug builds (`UNRELEASED`; the release keeps its passage): the wait
/// shows the painter's photo and nothing else over it, with one status that never changes its
/// words. Once the template to be painted is made its lines arrive over the photo
/// (`linesArrive`, while the painting is saved and the hand-off lifts its picture, so nothing
/// waits for them), and the hand-off (`StartHandoffPlan`) carries the photo under its lines to
/// where the painting's page will be, the photo drying away under them into the page as the
/// canvas draws it (`HandoffPage`, whose numbers come with it) on the way (`dries`). No painted
/// picture shows at any point: the color is the painter's to lay.
///
/// Reduce Motion: no lines arrive and nothing moves; the photo stays where it is and fades as
/// the page fades in at its place (`Passage.crossFade`). With Settings › The Making-of on, no
/// lines arrive either and the show takes the photo as it always has.
nonisolated enum FormingPlan {
    #if UNRELEASED
    static let isOn = true
    #else
    static let isOn = false
    #endif

    /// Whether the preview's wait is the picture forming: a picture picked on the Paint page
    /// (`CreateModel.paintsNow`). A page from scratch has no photo and a drawing is its own
    /// lines already: both keep the wait they had.
    static func forms(paintsNow: Bool, isScratch: Bool, isDrawing: Bool) -> Bool {
        isOn && paintsNow && !isScratch && !isDrawing
    }

    /// What shows over the photo while it forms.
    nonisolated struct Shown: Equatable, Sendable {
        /// The one status, the same words from the photo's opening until the template is made.
        var status: Bool
        /// The template's lines, in the canvas's ink.
        var lines: Bool
    }

    /// `isMade`: the template that will be painted is there (the settings chosen, the full
    /// resolution made). A failure shows its own message in the status's place.
    static func shown(isMade: Bool, hasFailed: Bool, reduceMotion: Bool, playsShow: Bool) -> Shown {
        Shown(status: !isMade && !hasFailed, lines: isMade && !reduceMotion && !playsShow)
    }

    /// How the picture goes from the preview to the painting's page when no show plays.
    nonisolated enum Passage: Equatable, Sendable {
        /// The preview's picture departs and becomes the page (`StartHandoffPlan`): the release,
        /// and every start from the settings.
        case preview
        /// The photo under its lines moves once to the page's place, drying into the page on the way.
        case carried
        /// Reduce Motion: the photo stays where it is and fades as the page fades in at its place.
        case crossFade
    }

    static func passage(forms: Bool, reduceMotion: Bool) -> Passage {
        guard forms else { return .preview }
        return reduceMotion ? .crossFade : .carried
    }

    /// The lines come in over the photo. No longer than the hand-off's `lift` and `clear`
    /// together, which follow the template being made whatever the save takes: by the time the
    /// picture moves they are all there, and nothing waited for them.
    static var linesArrive: Double { 2 * StartHandoffPlan.lift }
    /// The photo dries away under the lines into the page: the hand-off's own `settle`, during
    /// its `glide`, so the passage is no longer than the release's.
    static var dries: Double { StartHandoffPlan.settle }
}
