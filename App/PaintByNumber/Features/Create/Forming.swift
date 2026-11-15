import Foundation
import SwiftUI

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
/// (`dries`): the wash goes on to plain paper under the lines (`paperOpacity`), whose ink never
/// fades. The paper and the ink are the ones the page will have (`sheet`: Settings › Paper).
/// No painted picture shows at any point: the color is the painter's to lay.
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
        Shown(status: !isMade && !hasFailed, lines: isMade && hasLines(reduceMotion: reduceMotion, playsShow: playsShow))
    }

    /// Whether the picture forming has lines at all, on the preview and on the picture that
    /// leaves it: not under Reduce Motion, nor with Settings › The Making-of on, whether or not
    /// a show can be made of this painting.
    static func hasLines(reduceMotion: Bool, playsShow: Bool) -> Bool {
        !reduceMotion && !playsShow
    }

    /// The paper and the ink the painting's page will have, sRGB-encoded: what the photo
    /// washes and dries toward and what its lines are drawn in.
    nonisolated struct Sheet: Equatable, Sendable {
        var paper: SIMD3<Float>
        var ink: SIMD3<Float>
    }

    static func sheet(_ paper: PaperAppearance, interfaceIsDark: Bool) -> Sheet {
        paper.usesDarkPaper(interfaceIsDark: interfaceIsDark)
            ? Sheet(paper: CanvasPalette.darkSheetPaperSRGB, ink: CanvasPalette.darkSheetInkSRGB)
            : Sheet(paper: CanvasPalette.sheetPaperSRGB, ink: CanvasPalette.sheetInkSRGB)
    }

    /// How much paper lies over the departing photo, under its lines: the wash the preview
    /// left (none without lines), and all of it once the photo dries under the page, so that
    /// no photo shows at the page's edge and the ink stays whole.
    static func paperOpacity(hasLines: Bool, dries: Bool) -> Double {
        dries ? 1 : hasLines ? wash : 0
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

#if UNRELEASED
private extension Color {
    init(sheet color: SIMD3<Float>) {
        self.init(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z))
    }
}

/// The paper the painting's page will have (`FormingPlan.sheet`), filling its frame: the
/// forming photo's wash, at the opacity its place gives it.
struct FormingPaper: View {
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color(sheet: FormingPlan.sheet(paperAppearance, interfaceIsDark: colorScheme == .dark).paper))
            .allowsHitTesting(false)
    }
}

/// A template's lines alone over the forming photo, filling `picture` (frame coordinates) as
/// the photo does, in the ink the page will have and as heavy as the canvas draws them at
/// `scale` (`LineArtDrawing.lineWidth`). Equatable: stroked once, whatever moves over or with it.
struct FormingLines: View, Equatable {
    let drawing: LineArtDrawing
    let picture: CGRect
    /// The picture's size relative to the painting fitted on its canvas.
    let scale: CGFloat
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func == (a: FormingLines, b: FormingLines) -> Bool {
        a.drawing.id == b.drawing.id && a.picture == b.picture && a.scale == b.scale
    }

    var body: some View {
        let drawing = drawing, picture = picture, scale = scale, lineWeight = lineWeight
        let ink = Color(sheet: FormingPlan.sheet(paperAppearance, interfaceIsDark: colorScheme == .dark).ink)
        Canvas { context, size in
            let units = drawing.size
            let shown = picture.intersection(CGRect(origin: .zero, size: size))
            guard units.width > 0, units.height > 0, !shown.isNull, !shown.isEmpty else { return }
            // Filled into the picture as the photo is: centred, cropped to it.
            let s = max(picture.width / units.width, picture.height / units.height)
            let origin = CGPoint(x: picture.midX - units.width * s / 2, y: picture.midY - units.height * s / 2)
            let width = drawing.lineWidth(scale: scale, weight: lineWeight)
            let inView = CGRect(
                x: (shown.minX - origin.x) / s, y: (shown.minY - origin.y) / s, width: shown.width / s,
                height: shown.height / s
            ).insetBy(dx: -width / s, dy: -width / s)
            var lines = context
            lines.clip(to: Path(picture))
            lines.translateBy(x: origin.x, y: origin.y)
            lines.scaleBy(x: s, y: s)
            lines.stroke(
                drawing.path(within: inView), with: .color(ink.opacity(drawing.inkOpacity(scale: scale))),
                style: StrokeStyle(lineWidth: width / s, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}
#endif
