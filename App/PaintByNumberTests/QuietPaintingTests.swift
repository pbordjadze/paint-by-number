import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The quiet painting screen (`QuietPainting`): when the top bar fades, what keeps it whole, and
/// the bigger buttons and swatches of regular widths. Debug builds define `UNRELEASED`.
@MainActor
struct QuietPaintingTests {
    private func quiet(
        wanted: Bool = true, isStarted: Bool = true, isComplete: Bool = false, isGivingFeedback: Bool = false,
        assistiveTechnology: Bool = false, tipTurn: TipID? = nil
    ) -> Bool {
        QuietPainting.isQuiet(
            wanted: wanted, isStarted: isStarted, isComplete: isComplete, isGivingFeedback: isGivingFeedback,
            assistiveTechnology: assistiveTechnology, tipTurn: tipTurn)
    }

    @Test func aPaintedAreaQuietsTheBar() {
        #expect(QuietPainting.isAvailable)
        #expect(quiet())
        #expect(!quiet(wanted: false))
    }

    @Test func theWholeBarStaysWhenItIsNeeded() {
        #expect(!quiet(isStarted: false), "A painting not begun keeps its bar")
        #expect(!quiet(isComplete: true), "A finished painting keeps its bar")
        #expect(!quiet(isGivingFeedback: true), "Feedback mode has its own bar")
        #expect(!quiet(assistiveTechnology: true), "VoiceOver and Switch Control find every control")
        for tip in QuietPainting.barTips {
            #expect(!quiet(tipTurn: tip), "\(tip) points at a button the quiet bar hides")
        }
        #expect(quiet(tipTurn: .benchTap), "A tip at the palette leaves the bar quiet")
        #expect(quiet(tipTurn: .benchZoom), "A tip on the page leaves the bar quiet")
    }

    @Test func regularWidthsAreAQuarterBigger() {
        #expect(QuietPainting.scale(regularWidth: true) == 1.25)
        #expect(QuietPainting.scale(regularWidth: false) == 1)
        #expect(PaletteMetrics.standard.scaled(by: 1.25).scale == 1.25)
        #expect(PaletteMetrics.standard.scaled(by: 1.25).diameter == 50)
        #expect(PaletteMetrics(dynamicTypeSize: .accessibility5).scaled(by: 1.25).scale == 1.6, "At most 1.6× in all")
        #expect(PaletteMetrics(dynamicTypeSize: .xLarge).scaled(by: 1) == PaletteMetrics(dynamicTypeSize: .xLarge))
    }

    /// A fill wants the bar quiet; the ring's tap (`wantsQuiet = false`) brings it back until the
    /// next fill. Undo leaves it as it is.
    @Test func fillsQuietTheBarUntilTheRingBringsItBack() throws {
        let template = Fixtures.mosaic
        let session = PaintingSession(template: template)
        let chrome = PaintChromeState()
        chrome.observe(session)
        #expect(!chrome.wantsQuiet)
        let color = try #require(template.palette.indices.first { c in
            template.regions.indices.filter { session.colorOf($0) == c }.count >= 2
        })
        let areas = template.regions.indices.filter { session.colorOf($0) == color }
        session.select(color: color)

        session.paint([areas[0]], from: template.labels(ofRegion: areas[0])[0].position, animated: false)
        #expect(chrome.wantsQuiet)
        chrome.wantsQuiet = false
        session.undo()
        #expect(!chrome.wantsQuiet, "Undo doesn't quiet the bar")
        session.paint([areas[1]], from: template.labels(ofRegion: areas[1])[0].position, animated: false)
        #expect(chrome.wantsQuiet)
        chrome.close()
    }
}
