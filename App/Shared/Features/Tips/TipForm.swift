import Foundation

/// The form a tip takes on screen, a pure choice from the tip, the width it has and the text
/// size (`of`), which the views that point tips follow (`gentleTip`, `cardTip`, `barTips`, the
/// painting's page tips) and `TipFormTests` pins for every tip.
///
/// Until painting-company row 240 a tip had one form everywhere (`usual`). On an iPad that left
/// each small beside its subject. On a phone TipKit's popover is as wide as the screen and of
/// clear glass: it lay over the very thing it explained (the comparison, the Pen's options) and
/// was hard to read over a picture. Where the era asks for it (`EraSeam.tipsKeepOffTheirSubject`)
/// a compact width gives every tip a form that keeps off its subject (`keepsOffItsSubject`).
nonisolated enum TipForm: Equatable, Sendable {
    /// A popover at the system's width, in its glass: TipKit's own (`gentleTip`), or the app's
    /// from a card on the shelf (`cardTip`).
    case popover
    /// A card laid over the screen, with no arrow: at the top of the page (`TipDesk.pageTip`) or
    /// of the screen, under its bar (`barTips`).
    case card
    /// A card among the screen's own content, which makes room for it (the gallery's,
    /// `GentleTipView`).
    case inline
    /// A small popover of the app's own beside its subject, pointing at it, no wider than
    /// `besideWidth`, on the card's opaque surface (`TipCard`).
    case beside
    /// A card on the card's opaque surface in the screen's free margin, just under its bar.
    case margin

    /// Whether the tip lies beside what it explains or in room of its own, never over it.
    var keepsOffItsSubject: Bool {
        switch self {
        case .beside, .inline, .margin: true
        case .popover, .card: false
        }
    }

    /// The widest a tip beside its subject grows: its words wrap rather than span a phone.
    static let besideWidth: CGFloat = 280
    /// The width of a tip beside its subject where the room off a picture is short but wide (the
    /// create flow's, between the comparison and the settings): a line or two fewer, so it keeps
    /// off the picture. Still narrower than a phone, unlike TipKit's popover.
    static let besideWideWidth: CGFloat = 340

    /// The form `id` had everywhere until row 240, and has still in the release, on a regular
    /// width and where its view reads an accessibility text size (`of`).
    static func usual(_ id: TipID) -> TipForm {
        if id == .shelfStarter || (id.liesUnderTheBar && id.place == .shelf) { return .inline }
        if id.liesUnderTheBar || id.liesOnThePage { return .card }
        return .popover
    }

    /// The form `id` takes in a view `isCompact` wide: a compact width, whatever the device, so
    /// an iPad's window in Split View or Slide Over keeps its tips off their subjects too. At the
    /// accessibility text sizes a small popover could not hold its words, so a tip keeps its
    /// usual form there. `isAccessibilitySize` is the text size the pointing view reads, which a
    /// bar that clamps Dynamic Type has already clamped (the painting's top bar, `CompletionBar`,
    /// Refine's tool rows, all at `.xxLarge`): a tip anchored inside one is beside its subject at
    /// every text size, and its card, drawn in that environment, is clamped as the bar is.
    static func of(
        _ id: TipID, isCompact: Bool, isAccessibilitySize: Bool, keepsOff: Bool = EraSeam.tipsKeepOffTheirSubject
    ) -> TipForm {
        let form = usual(id)
        guard keepsOff, isCompact, !isAccessibilitySize else { return form }
        switch form {
        // Settings' tip is about two rows, and in a form every side of a row is another row's
        // label: it lies among them (`SettingsView`), under the section's title.
        case .popover where id == .drawerWorthALook: return .inline
        case .popover: return .beside
        case .card: return .margin
        case .inline, .beside, .margin: return form
        }
    }
}
