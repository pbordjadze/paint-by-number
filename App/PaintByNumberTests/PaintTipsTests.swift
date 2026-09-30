import Foundation
import Testing
@testable import PaintByNumber

/// Which painting events feed the first-run tips, and the generations behind Show Tips Again.
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
