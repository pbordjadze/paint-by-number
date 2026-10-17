import Foundation
import Testing
import TipKit
@testable import PaintByNumber

/// Which painting events feed the gentle tips, the generations behind Show Tips Again, and what each
/// tip is made of: an id of its own, and rules.
@MainActor
struct PaintTipsTests {
    @Test func paintingEventsMapToTipSignals() {
        let cases: [(PaintEvent, Bool, PaintTips.Signal?)] = [
            (.painted(regions: [1], color: 0), false, .tapPainted),
            (.painted(regions: [1, 2], color: 0), true, .strokePainted),
            (.strokeEnded(regions: [1, 2]), false, .strokeEnded),
            (.rejected(region: 3, expectedColor: 1), false, .wrongColor),
            (.rejected(region: 3, expectedColor: 1), true, .wrongColor),
            (.missedSmallArea(region: 4), false, .missedSmallArea),
            (.hintShown(region: 5), false, .hintShown),
        ]
        for (event, isStroking, expected) in cases {
            #expect(PaintTips.signal(for: event, isStroking: isStroking) == expected, "\(event), stroking \(isStroking)")
        }
        for event in [PaintEvent.colorCompleted(0), .artworkCompleted, .undone(region: 1)] {
            for isStroking in [false, true] {
                #expect(PaintTips.signal(for: event, isStroking: isStroking) == nil, "\(event)")
            }
        }
    }

    /// A rule, not an invalidation: the first tip returns on the next fresh painting.
    @Test func paintingProgressGatesTheFirstTip() {
        PaintTips.paintingOpened(hasProgress: true)
        #expect(FirstPaintTip.hasPaint)
        PaintTips.paintingOpened(hasProgress: false)
        #expect(!FirstPaintTip.hasPaint)
    }

    @Test func everyTipHasAnIdOfItsOwn() {
        let ids = TipID.allCases.map { $0.tip.id }
        #expect(Set(ids).count == ids.count)
    }

    /// Whoever closed one of the first version's five bench tips has it closed: their ids carry over.
    @Test func theBenchTipsOfTheFirstVersionKeepTheirIds() {
        let generation = PaintTips.generation()
        #expect(TipID.benchTap.tip.id == "tip.firstPaint.\(generation)")
        #expect(TipID.benchFind.tip.id == "tip.hint.\(generation)")
        #expect(TipID.benchZoom.tip.id == "tip.zoom.\(generation)")
        #expect(TipID.benchDrag.tip.id == "tip.dragPaint.\(generation)")
        #expect(TipID.benchPencil.tip.id == "tip.pencil.\(generation)")
    }

    /// Tips off means none: every tip's rules carry the tips-on parameter. And a tip has no buttons
    /// but its close button: the Tips switch in Settings is the only way to turn them off.
    @Test func everyTipHasRulesAndNoActions() {
        for id in TipID.allCases {
            let tip = id.tip
            #expect(!tip.rules.isEmpty, "\(id) has no rules: tips off must mean none")
            #expect(tip.actions.isEmpty, "\(id)")
        }
    }

    /// A tip of the navigation bar sits in a popover of SwiftUI's own with its `TipView` inside: a
    /// display limit of TipKit's would retire the tip from under that view, so the desk says it once.
    @Test func theTipsOfTheNavigationBarHaveNoDisplayLimit() {
        for id in TipID.allCases where id.hangsFromBar {
            #expect(id.tip.options.isEmpty, "\(id)")
        }
    }

    @Test func showingTipsAgainGivesThemNewIDs() throws {
        let name = "PaintTipsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let before = PaintTips.scoped("tip.dragPaint", defaults: defaults)
        #expect(before == "tip.dragPaint.0")
        PaintTips.bumpGeneration(defaults)
        let after = PaintTips.scoped("tip.dragPaint", defaults: defaults)
        #expect(after == "tip.dragPaint.1")
        #expect(after != before)
    }
}
