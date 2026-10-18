import Foundation

/// Where in the app a tip lives. The words are the design's (October 17): the shelf is the gallery,
/// New Painting the create flow's picking of a photo, its preview, Refine, the bench the painting
/// screen and the drawer Settings.
nonisolated enum TipPlace: String, CaseIterable, Codable, Sendable {
    case shelf, newPainting, preview, refine, bench, drawer

    /// How far in front of the others the screen is when several are up at once (the shelf under the
    /// create flow, Settings or a painting; Refine over the preview). Whichever is most in front is
    /// the one whose tips may speak, however the screens' appearing happened to be ordered.
    var depth: Int {
        switch self {
        case .shelf: 0
        case .bench, .drawer: 1
        case .newPainting: 2
        case .preview: 3
        case .refine: 4
        }
    }
}

/// The 23 tips, by the design's ids (22, and Refine's Draw Your Own Lines, which took the place of
/// the line under Refine's tools: Paul's calmer menus, October 18). Pure data: the tips themselves (TipKit) are made from these in
/// `TipID.tip`, and everything that decides when one may appear (`TipPacing`, `TipMoments`) speaks
/// of ids alone.
nonisolated enum TipID: String, CaseIterable, Codable, Sendable {
    case shelfStarter, shelfNewPainting, shelfHold, shelfTimeLapse, shelfSettings
    case newPaintingSamples
    case newPaintingDivider, newPaintingSuggested, newPaintingReset, newPaintingSliders, newPaintingRefine
    case refineDraw, refineFill
    case benchTap, benchZoom, benchFind, benchDrag, benchPencil, benchShowPhoto, benchReplay, benchZen, benchFeedback
    case drawerWorthALook

    /// The tips that hang from a button in a navigation bar (`barTip`: a popover of SwiftUI's own, with
    /// the tip's `TipView` inside).
    var hangsFromBar: Bool {
        switch self {
        case .shelfSettings, .shelfNewPainting, .newPaintingRefine: true
        default: false
        }
    }

    /// The tips that hang from a painting's card on the shelf, in a popover of SwiftUI's own like the
    /// bar's (`cardTip`): TipKit's popover tip never came up on a card (CI, October 17: the turn
    /// given, nothing on screen), where the card's own confirmation dialogs do.
    var hangsFromCard: Bool { self == .shelfHold || self == .shelfTimeLapse }

    /// Tips in a popover of SwiftUI's own. They have no display limit of TipKit's, which would retire
    /// the tip from under its own view: closing, using or leaving it unread (`TipDesk`) says it once.
    var hasOwnPopover: Bool { hangsFromBar || hangsFromCard }

    /// How to use a screen at all, so it waits for neither the gap nor something done
    /// (`TipPacing`): Tap to Paint, and Refine's Draw Your Own Lines.
    var isHowTo: Bool { self == .benchTap || self == .refineDraw }

    var place: TipPlace {
        switch self {
        case .shelfStarter, .shelfNewPainting, .shelfHold, .shelfTimeLapse, .shelfSettings: .shelf
        case .newPaintingSamples: .newPainting
        case .newPaintingDivider, .newPaintingSuggested, .newPaintingReset, .newPaintingSliders, .newPaintingRefine: .preview
        case .refineDraw, .refineFill: .refine
        case .benchTap, .benchZoom, .benchFind, .benchDrag, .benchPencil, .benchShowPhoto, .benchReplay, .benchZen,
             .benchFeedback: .bench
        case .drawerWorthALook: .drawer
        }
    }
}
