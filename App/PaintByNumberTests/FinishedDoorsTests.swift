#if UNRELEASED
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import PaintByNumber

/// The doors after Finished (painting-company row 332): which show, how they are laid out in the
/// room the painting screen gives them, and the room the canvas makes for them.
@MainActor
struct FinishedDoorsTests {
    @Test func changeItShowsOnlyWhereEditOpens() {
        #expect(FinishedDoor.shown(changes: true) == [.another, .change, .paper, .send])
        #expect(FinishedDoor.shown(changes: false) == [.another, .paper, .send])
    }

    /// An iPhone upright: two by two, the arches as large as the mockups' (about 150 points).
    @Test func aPhoneLaysThemTwoByTwo() throws {
        let doors = try #require(DoorMetrics.fitting(count: 4, width: 346, height: 417, dynamicTypeSize: .large))
        #expect(doors.columns == 2 && doors.rows == 2)
        #expect(doors.arch.width >= 140 && doors.arch.width <= DoorMetrics.largest)
        #expect(abs(doors.arch.height - doors.arch.width * DoorMetrics.aspect) < 1)
    }

    /// An iPad's panel (560 points) and a phone on its side: one row.
    @Test func aWidePanelLaysThemInOneRow() throws {
        let pad = try #require(DoorMetrics.fitting(count: 4, width: 528, height: 800, dynamicTypeSize: .large))
        #expect(pad.columns == 4 && pad.rows == 1)
        #expect(pad.arch.width >= DoorMetrics.roomyRow)
        let side = try #require(DoorMetrics.fitting(count: 4, width: 528, height: 140, dynamicTypeSize: .large))
        #expect(side.columns == 4 && side.rows == 1)
        #expect(side.arch.height + DoorMetrics.labelHeight(.large) + DoorMetrics.labelGap <= 140)
    }

    @Test func noRoomShowsNoDoors() {
        #expect(DoorMetrics.fitting(count: 4, width: 346, height: 60, dynamicTypeSize: .large) == nil)
        #expect(DoorMetrics.fitting(count: 4, width: 120, height: 400, dynamicTypeSize: .large) == nil)
        #expect(DoorMetrics.fitting(count: 0, width: 346, height: 417, dynamicTypeSize: .large) == nil)
    }

    /// The canvas makes room for the panel as tall as it is laid out, and the bar's height without.
    @Test func theCanvasMakesRoomForThePanel() {
        func inputs(_ height: CGFloat?) -> PaintingLayout.Inputs {
            PaintingLayout.Inputs(
                size: CGSize(width: 402, height: 778), safe: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0),
                regularWidth: false, dynamicTypeSize: .large, rows: .auto, colors: 22, isComplete: true,
                completionHeight: height)
        }
        let bar = PaintingLayout(inputs(nil)).canvasInsets.bottom
        let panel = PaintingLayout(inputs(500)).canvasInsets.bottom
        #expect(abs(panel - bar - (500 - CompletionBar.height)) < 0.01)
    }

    /// Change It and On Paper look through the door at the middle of the picture, close enough to
    /// read its lines, in the door's own proportions and inside the canvas.
    @Test func theGlimpseIsACloseUpInTheDoorsShape() {
        for (w, h) in [(2100, 1500), (1100, 2100), (2000, 300)] {
            let rect = DoorGlimpses.closeUp(of: CGSize(width: w, height: h))
            #expect(abs(rect.height / rect.width - DoorMetrics.aspect) < 0.001)
            #expect(CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: -0.001, dy: -0.001).contains(rect))
            #expect(abs(rect.midX - Double(w) / 2) < 0.001 && abs(rect.midY - Double(h) / 2) < 0.001)
            #expect(rect.width <= Double(min(w, h)) * 0.45 + 0.001)
        }
    }

    @Test func anArchHasARoundTopUntilItFlattens() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 108)
        let round = ArchShape().path(in: rect)
        #expect(!round.contains(CGPoint(x: 2, y: 2)), "The arch's top corner is filled")
        #expect(round.contains(CGPoint(x: 50, y: 2)))
        let flat = ArchShape(roundness: 0, footRadius: 0).path(in: rect)
        #expect(flat.contains(CGPoint(x: 1, y: 1)))
    }
}
#endif
