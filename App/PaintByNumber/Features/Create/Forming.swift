import Foundation

/// The picture forming as one act (painting-company row 293), for a picture picked on the Paint
/// page in SideStore and Debug builds (`UNRELEASED`; the release keeps its passage): the wait
/// shows the painter's photo and nothing else over it, with one status that never changes its
/// words. Once the template to be painted is made (no earlier: a draft's lines are another
/// template's, of a smaller canvas) its lines are drawn in across the photo (`drawIn`), which
/// calms toward the paper under them (`wash`, the first step of its drying) so that the ink
/// reads on any picture. The hand-off's lift waits for the drawing to end (`liftWait`; the
/// painting is saved meanwhile), and the hand-off (`StartHandoffPlan`) carries the washed photo
/// under its lines to where the painting's page will be, the photo drying the rest of the way
/// into the page as the canvas draws it (`HandoffPage`, whose numbers come with it) as it goes
/// (`dries`). No painted picture shows at any point: the color is the painter's to lay.
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

    /// How far the photo calms toward the paper as its lines are drawn: enough for dark ink to
    /// read on a dark or busy picture, the picture still plainly itself.
    static let wash = 0.45
    /// The lines are drawn in across the picture, leading edge to trailing, eased: long enough
    /// to follow, slowed with the hand-off (`-handoffSlowdown`).
    static var drawIn: Double { 1.4 * StartHandoffPlan.glide }
    /// The soft edge of the drawing as it travels, as a share of the picture's width.
    static let feather = 0.18
    /// How long the hand-off's lift still waits, the lines having begun `elapsed` seconds ago:
    /// the rest of the drawing, and nothing once it is done.
    static func liftWait(sinceLines elapsed: Double) -> Double {
        min(max(drawIn - elapsed, 0), drawIn)
    }
    /// The photo dries away under the lines into the page: the hand-off's own `settle`, during
    /// its `glide`, so the passage is no longer than the release's.
    static var dries: Double { StartHandoffPlan.settle }
}
