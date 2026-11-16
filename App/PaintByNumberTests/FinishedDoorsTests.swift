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
        #expect(FinishedDoor.shown(changes: true, original: false) == [.another, .change, .paper, .send])
        #expect(FinishedDoor.shown(changes: false, original: false) == [.another, .paper, .send])
    }

    /// The Original (painting-company row 120) is the last door, and only a painting made from a
    /// library picture has it.
    @Test func theOriginalIsTheLastDoorOfALibraryPicture() {
        #expect(FinishedDoor.shown(changes: true, original: true) == [.another, .change, .paper, .send, .original])
        #expect(FinishedDoor.shown(changes: false, original: true) == [.another, .paper, .send, .original])
    }

    /// Five doors: three over two where a row of five would be too small (a phone upright), one
    /// row on an iPad's panel, which is wider for them, and on a phone on its side.
    @Test func fiveDoorsStandThreeOverTwo() throws {
        let phone = try #require(DoorMetrics.fitting(
            count: 5, width: CompletionBar.doorsWidth(count: 5, available: 378), height: 417, dynamicTypeSize: .large))
        #expect(phone.columns == 3 && phone.rows == 2)
        #expect(phone.door.width >= 100)
        #expect(3 * phone.door.width + 2 * DoorMetrics.gap <= 346)
        let wide = CompletionBar.doorsWidth(count: 5, available: 1000)
        let pad = try #require(DoorMetrics.fitting(count: 5, width: wide, height: 600, dynamicTypeSize: .large))
        #expect(pad.columns == 5 && pad.rows == 1)
        #expect(5 * pad.door.width + 4 * DoorMetrics.gap <= wide)
        // As large as a row of four, so each caption keeps its one line.
        let four = try #require(DoorMetrics.fitting(
            count: 4, width: CompletionBar.doorsWidth(count: 4, available: 1000), height: 600, dynamicTypeSize: .large))
        #expect(pad.door == four.door && pad.door.width >= DoorMetrics.roomyRow)
        // A screen between the two, where the panel can't widen all the way, still keeps one row.
        let between = try #require(DoorMetrics.fitting(count: 5, width: 528, height: 600, dynamicTypeSize: .large))
        #expect(between.columns == 5 && between.rows == 1 && between.door.width >= DoorMetrics.snugRow)
        let side = try #require(DoorMetrics.fitting(count: 5, width: 528, height: 140, dynamicTypeSize: .large))
        #expect(side.columns == 5 && side.rows == 1)
    }

    /// An iPhone upright: two by two, the doors as large as the mockups' (about 150 points).
    @Test func aPhoneLaysThemTwoByTwo() throws {
        let doors = try #require(DoorMetrics.fitting(count: 4, width: 346, height: 417, dynamicTypeSize: .large))
        #expect(doors.columns == 2 && doors.rows == 2)
        #expect(doors.door.width >= 140 && doors.door.width <= DoorMetrics.largest)
        #expect(abs(doors.door.height - doors.door.width * DoorMetrics.aspect) < 1)
    }

    /// An iPad's panel (560 points) and a phone on its side: one row.
    @Test func aWidePanelLaysThemInOneRow() throws {
        let pad = try #require(DoorMetrics.fitting(count: 4, width: 528, height: 800, dynamicTypeSize: .large))
        #expect(pad.columns == 4 && pad.rows == 1)
        #expect(pad.door.width >= DoorMetrics.roomyRow)
        let side = try #require(DoorMetrics.fitting(count: 4, width: 528, height: 140, dynamicTypeSize: .large))
        #expect(side.columns == 4 && side.rows == 1)
        #expect(side.door.height + DoorMetrics.labelHeight(.large) + DoorMetrics.labelGap <= 140)
    }

    /// The panel is the bar's width with up to four doors, a door wider with five, and never
    /// wider than the screen leaves it.
    @Test func thePanelWidensForAFifthDoor() {
        for count in 0...4 { #expect(CompletionBar.widestPanel(doors: count) == CompletionBar.panelWidth) }
        #expect(CompletionBar.widestPanel(doors: 5) > CompletionBar.panelWidth + DoorMetrics.roomyRow)
        #expect(CompletionBar.doorsWidth(count: 4, available: 1000) == 528)
        #expect(CompletionBar.doorsWidth(count: 5, available: 378) == 346)
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
}
#endif
