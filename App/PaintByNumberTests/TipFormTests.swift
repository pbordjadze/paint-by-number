import Foundation
import Testing
@testable import PaintByNumber

/// Which form a tip takes where (`TipForm`; painting-company row 240): on a compact width every tip
/// keeps off what it explains in SideStore and Debug builds, and in the release, on a regular width
/// and at the accessibility text sizes each has the form it always had.
@MainActor
struct TipFormTests {
    /// The form each tip had before there was a choice, tip by tip: a new tip must be given one.
    private static func before(_ id: TipID) -> TipForm {
        switch id {
        case .shelfStarter, .shelfSettings, .shelfNewPainting: .inline
        case .newPaintingRefine, .benchZoom, .benchDrag, .benchPencil: .card
        case .shelfHold, .shelfTimeLapse, .newPaintingSamples, .newPaintingDivider, .newPaintingSuggested,
             .newPaintingReset, .newPaintingSliders, .refineDraw, .refineFill, .benchTap, .benchFind, .benchShowPhoto,
             .benchReplay, .benchZen, .benchFeedback, .drawerWorthALook: .popover
        }
    }

    @Test func everyTipHasItsUsualForm() {
        for id in TipID.allCases {
            #expect(TipForm.usual(id) == Self.before(id), "\(id)")
        }
    }

    /// The build's own answer: SideStore and Debug builds keep every tip off its subject on a
    /// compact width; the release's tips are as they were.
    @Test func aCompactWidthKeepsEveryTipOffItsSubjectOnlyInUnreleasedBuilds() {
        for id in TipID.allCases {
            let compact = TipForm.of(id, isCompact: true, isAccessibilitySize: false)
            #if UNRELEASED
            #expect(compact.keepsOffItsSubject, "\(id) is \(compact)")
            #expect(compact != .popover && compact != .card, "\(id)")
            #else
            #expect(compact == TipForm.usual(id), "\(id) is \(compact)")
            #endif
        }
        #if UNRELEASED
        #expect(EraSeam.tipsKeepOffTheirSubject)
        #else
        #expect(!EraSeam.tipsKeepOffTheirSubject)
        #endif
    }

    /// The rule itself, whatever the build: a popover becomes the small one beside its subject, a
    /// card over the screen moves to its margin, and a card among the content stays.
    @Test func keepingOffTurnsPopoversSmallAndCardsToTheMargin() {
        for id in TipID.allCases {
            let kept = TipForm.of(id, isCompact: true, isAccessibilitySize: false, keepsOff: true)
            switch TipForm.usual(id) {
            case .popover: #expect(kept == .beside, "\(id)")
            case .card: #expect(kept == .margin, "\(id)")
            case .inline: #expect(kept == .inline, "\(id)")
            case .beside, .margin: Issue.record("\(id) is usually \(TipForm.usual(id))")
            }
            #expect(kept.keepsOffItsSubject, "\(id)")
            #expect(TipForm.of(id, isCompact: true, isAccessibilitySize: false, keepsOff: false) == TipForm.usual(id), "\(id)")
        }
    }

    /// A regular width's tips, and a compact one's where the view reads one of the largest text
    /// sizes (a bar that clamps Dynamic Type never does), where a small popover could not hold
    /// its words: unchanged in every build.
    @Test func aRegularWidthAndTheLargestTextKeepTheUsualForm() {
        for id in TipID.allCases {
            for keepsOff in [true, false] {
                #expect(TipForm.of(id, isCompact: false, isAccessibilitySize: false, keepsOff: keepsOff) == TipForm.usual(id), "\(id)")
                #expect(TipForm.of(id, isCompact: false, isAccessibilitySize: true, keepsOff: keepsOff) == TipForm.usual(id), "\(id)")
                #expect(TipForm.of(id, isCompact: true, isAccessibilitySize: true, keepsOff: keepsOff) == TipForm.usual(id), "\(id)")
            }
            #expect(TipForm.of(id, isCompact: false, isAccessibilitySize: false) == TipForm.usual(id), "\(id)")
        }
    }

    @Test func onlyTheFormsOfACompactWidthKeepOff() {
        #expect(TipForm.beside.keepsOffItsSubject && TipForm.margin.keepsOffItsSubject && TipForm.inline.keepsOffItsSubject)
        #expect(!TipForm.popover.keepsOffItsSubject && !TipForm.card.keepsOffItsSubject)
        #expect(TipForm.besideWidth < 320)
    }
}
