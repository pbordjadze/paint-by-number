import CoreGraphics
import Foundation
import Testing
@testable import PaintByNumber

/// The hand-off from Start Painting to the painting (`StartHandoff`): the painting's report of its
/// first frame, the fallback when it never comes, the single push, and Reduce Motion's choice of
/// no movement.
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
        #expect(!handoff.isOpening(id))

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
        // A canvas that draws after the cover has been told to go changes nothing.
        handoff.paintingDrew(id, templateRect: template)
        #expect(handoff.phase == .timedOut(id))
        handoff.complete()
        #expect(handoff.isFinished)
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
        #expect(StartHandoffPlan.motion(reduceMotion: false, target: place) == .fly)
        #expect(StartHandoffPlan.motion(reduceMotion: true, target: place) == .crossFade)
        // The show's picture starts where the preview's was, or in its own place.
        #expect(StartHandoffPlan.entry(reduceMotion: false, from: place) == place)
        #expect(StartHandoffPlan.entry(reduceMotion: true, from: place) == nil)
    }

    @Test func aPictureWithNowhereToGoFades() {
        for unusable in [CGRect.zero, .null, .infinite, CGRect(x: 0, y: 0, width: 0.5, height: 80),
                         CGRect(x: CGFloat.nan, y: 0, width: 40, height: 40)] {
            #expect(StartHandoffPlan.motion(reduceMotion: false, target: unusable) == .crossFade)
            #expect(StartHandoffPlan.entry(reduceMotion: false, from: unusable) == nil)
        }
        #expect(StartHandoffPlan.motion(reduceMotion: false, target: nil) == .crossFade)
        #expect(StartHandoffPlan.entry(reduceMotion: false, from: nil) == nil)
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
