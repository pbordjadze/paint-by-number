import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// The hand-off from Start Painting to the painting (`StartHandoff`): the painting's report of its
/// first frame, the fallback when it never comes, the single push, the picture moving again only
/// when the page is elsewhere than expected, and Reduce Motion's choice of no movement.
@MainActor
struct StartHandoffTests {
    private let id = UUID()
    private let template = CGRect(x: 40, y: 120, width: 300, height: 200)

    @Test func theCanvasReportsForThePaintingBeingOpenedAndFollowsALayout() {
        let handoff = StartHandoff()
        #expect(handoff.phase == .idle && !handoff.isRunning)
        #expect(handoff.begin(id))
        #expect(handoff.phase == .opening(id) && handoff.isOpening(id) && handoff.isRunning)

        // Another painting's canvas (one opened from the gallery meanwhile) is not the one.
        handoff.paintingDrew(UUID(), templateRect: template)
        #expect(handoff.phase == .opening(id))

        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .ready(id, template))
        #expect(!handoff.isOpening(id) && !handoff.isAwaiting(id))

        // A layout that moves the template while the flow is on its way is followed...
        let moved = template.offsetBy(dx: 0, dy: -48)
        handoff.paintingDrew(id, templateRect: moved)
        #expect(handoff.phase == .ready(id, moved))
        // ...but only from the painting being opened.
        handoff.paintingDrew(UUID(), templateRect: template)
        #expect(handoff.phase == .ready(id, moved))

        handoff.complete()
        #expect(handoff.phase == .finished(id) && handoff.isFinished)
        // The flow has dissolved: the canvas moving after that changes nothing.
        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .finished(id))
        handoff.reset()
        #expect(handoff.phase == .idle && !handoff.isRunning && !handoff.isFinished)
    }

    @Test func aReportOutsideAHandoffIsIgnored() {
        let handoff = StartHandoff()
        // A painting opened from its card in the gallery draws its first frame with no hand-off.
        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .idle)
        #expect(handoff.begin(id))
        handoff.reset()
        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .idle)
    }

    @Test func aPaintingThatNeverDrawsTimesOutAndStaysOpen() async throws {
        let handoff = StartHandoff(timeout: .milliseconds(40))
        #expect(handoff.begin(id))
        try await waitUntil(timeout: .seconds(10)) { handoff.phase == .timedOut(id) }
        handoff.complete()
        #expect(handoff.isFinished)
        // A canvas that draws after the cover has gone changes nothing.
        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .finished(id))
    }

    /// The making-of plays while the painting opens beneath it: a painting that draws after its
    /// time is up, while the cover is still up, is still handed over to.
    @Test func aLateReportStillCountsWhileTheCoverIsUp() async throws {
        let handoff = StartHandoff(timeout: .milliseconds(40))
        #expect(handoff.begin(id))
        try await waitUntil(timeout: .seconds(10)) { handoff.phase == .timedOut(id) }
        // The painting still opens under the cover, as one being opened does.
        #expect(handoff.isAwaiting(id) && !handoff.isOpening(id) && !handoff.isAwaiting(UUID()))
        handoff.paintingDrew(UUID(), templateRect: template)
        #expect(handoff.phase == .timedOut(id))
        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .ready(id, template))
    }

    /// A canvas a painting is handed over to opens with the color to paint hidden, as the page the
    /// create flow ends on is drawn (`HandoffPage`), and eases it in once the cover is gone; any
    /// other canvas shows it at once.
    @Test func theCanvasHandedOverToEasesItsColorIn() async throws {
        _ = try #require(RenderContext.shared)
        let session = PaintingSession(template: Fixtures.mosaic)
        let opened = CanvasView(session: session)
        #expect(opened.frameUniforms().outline.z == 1)

        let handedOver = CanvasView(session: session)
        handedOver.watchesFirstFrame = true
        #expect(handedOver.frameUniforms().outline.z == 0)
        handedOver.revealSelection()
        try await waitUntil(timeout: .seconds(5)) { handedOver.frameUniforms().outline.z == 1 }
    }

    @Test func aReportCancelsTheFallback() async throws {
        let handoff = StartHandoff(timeout: .milliseconds(60))
        #expect(handoff.begin(id))
        handoff.paintingDrew(id, templateRect: template)
        try await Task.sleep(for: .milliseconds(250))
        #expect(handoff.phase == .ready(id, template))
    }

    @Test func aResetCancelsTheFallback() async throws {
        let handoff = StartHandoff(timeout: .milliseconds(60))
        #expect(handoff.begin(id))
        handoff.reset()
        try await Task.sleep(for: .milliseconds(250))
        #expect(handoff.phase == .idle)
    }

    @Test func theTimeoutOnlyAppliesToAPaintingStillOpening() {
        var logic = StartHandoffLogic()
        var changed = logic.timeOut()
        #expect(!changed)
        changed = logic.begin(id)
        #expect(changed)
        changed = logic.paintingDrew(id, templateRect: template)
        #expect(changed)
        changed = logic.timeOut()
        #expect(!changed)
        #expect(logic.phase == .ready(id, template))
    }

    @Test func theCoverLeavesOnlyAfterAReportOrATimeout() {
        var logic = StartHandoffLogic()
        var changed = logic.complete()
        #expect(!changed)
        changed = logic.begin(id)
        #expect(changed)
        changed = logic.complete()
        #expect(!changed)
        changed = logic.timeOut()
        #expect(changed)
        changed = logic.complete()
        #expect(changed)
        changed = logic.complete()
        #expect(!changed)
        #expect(logic.isFinished)
    }

    @Test func thePaintingIsPushedOnce() {
        let handoff = StartHandoff()
        #expect(handoff.begin(id))
        // A second Start, or a finish that fires twice, does not begin another hand-off.
        #expect(!handoff.begin(id))
        #expect(!handoff.begin(UUID()))

        #expect(StartHandoffLogic.shouldPush(id, onto: []))
        #expect(!StartHandoffLogic.shouldPush(id, onto: [id]))
        #expect(StartHandoffLogic.shouldPush(id, onto: [UUID()]))
    }

    @Test func reduceMotionMovesNothing() {
        let place = CGRect(x: 10, y: 20, width: 300, height: 200)
        // The show's or the preview's picture starts where the preview's was, or comes in at its
        // place.
        #expect(StartHandoffPlan.entry(reduceMotion: false, from: place) == place)
        #expect(StartHandoffPlan.entry(reduceMotion: true, from: place) == nil)
        // Nor does it move to a page the canvas put elsewhere: it fades instead.
        let elsewhere = place.offsetBy(dx: 0, dy: 40)
        #expect(StartHandoffPlan.correction(expected: place, reported: elsewhere, reduceMotion: false) == elsewhere)
        #expect(StartHandoffPlan.correction(expected: place, reported: elsewhere, reduceMotion: true) == nil)
    }

    /// The picture waits where the page was expected; it moves again only when the canvas put the
    /// page more than a point away (the scroll view rounds the camera to the screen).
    @Test func aPageWhereExpectedMovesNothing() {
        let expected = CGRect(x: 16, y: 299.76, width: 370, height: 248.49)
        let rounded = CGRect(x: 16, y: 300, width: 370, height: 248.49)
        #expect(StartHandoffPlan.matches(expected, rounded))
        #expect(StartHandoffPlan.correction(expected: expected, reported: rounded, reduceMotion: false) == nil)
        // CI's canvases reported theirs a safe area too low (October 25); that would move.
        let low = expected.offsetBy(dx: 0, dy: 61.67)
        #expect(!StartHandoffPlan.matches(expected, low))
        #expect(StartHandoffPlan.correction(expected: expected, reported: low, reduceMotion: false) == low)
        // A page of another size is elsewhere too.
        #expect(!StartHandoffPlan.matches(expected, expected.insetBy(dx: 4, dy: 3)))
    }

    @Test func aPictureWithNowhereToGoFades() {
        for unusable in [CGRect.zero, .null, .infinite, CGRect(x: 0, y: 0, width: 0.5, height: 80),
                         CGRect(x: CGFloat.nan, y: 0, width: 40, height: 40)] {
            #expect(StartHandoffPlan.entry(reduceMotion: false, from: unusable) == nil)
            #expect(StartHandoffPlan.correction(expected: template, reported: unusable, reduceMotion: false) == nil)
            #expect(!StartHandoffPlan.matches(unusable, unusable))
        }
        #expect(StartHandoffPlan.entry(reduceMotion: false, from: nil) == nil)
        // Nowhere expected (the flow wasn't laid out): to the canvas's page.
        #expect(StartHandoffPlan.correction(expected: .null, reported: template, reduceMotion: false) == template)
    }

    @Test func aPictureTravelsToItsDestination() {
        let home = CGRect(x: 16, y: 64, width: 370, height: 280)
        let destination = CGRect(x: 30, y: 140, width: 330, height: 250)
        let travel = PictureTravel(home: home, destination: destination)
        let moved = travel.applied(to: home)
        #expect(abs(moved.width - destination.width) < 1e-9)
        #expect(abs(moved.midX - destination.midX) < 1e-9)
        #expect(abs(moved.midY - destination.midY) < 1e-9)
        #expect(abs(travel.scale - 330.0 / 370.0) < 1e-9)

        // Nowhere to go (or no home): it stays.
        #expect(PictureTravel(home: home, destination: nil) == .none)
        #expect(PictureTravel(home: home, destination: .zero) == .none)
        #expect(PictureTravel(home: .zero, destination: destination) == .none)
        #expect(PictureTravel.none.applied(to: home) == home)
        #expect(PictureTravel(home: home, destination: home).applied(to: home) == home)
    }
}
