import Foundation
import Testing
@testable import PaintByNumber

/// The gentle tips' pacing (design §5): one at a time, three minutes and something done between,
/// at most three a session and five a day, three on the first painting, and silence while the
/// painter's hand or the app's own show is busy. Pure values with an injected clock.
struct TipPacingTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Saturday, October 17, 2026, ten in the morning.
    private static let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10)) ?? .distantPast

    private static func at(_ minutes: Double, from base: Date = start) -> Date { base.addingTimeInterval(minutes * 60) }

    private func refusal(
        _ pacing: TipPacing, _ id: TipID, at minutes: Double, quiet: TipPacing.Quiet = []
    ) -> TipPacing.Refusal? {
        pacing.refusal(for: id, quiet: quiet, now: Self.at(minutes), calendar: Self.calendar)
    }

    private func show(_ pacing: inout TipPacing, _ id: TipID, at minutes: Double) {
        pacing.show(id, now: Self.at(minutes), calendar: Self.calendar)
    }

    /// A hint shown at `minutes`, closed a moment later, and something done after it.
    private func shownAndDone(_ pacing: inout TipPacing, _ id: TipID, at minutes: Double) {
        show(&pacing, id, at: minutes)
        pacing.hide(id)
        pacing.noteActivity(now: Self.at(minutes + 0.5))
    }

    // MARK: One at a time

    @Test func aFreshPacingAdmitsAHint() {
        let pacing = TipPacing()
        for id in TipID.allCases {
            #expect(refusal(pacing, id, at: 0) == nil, "\(id)")
        }
    }

    @Test func oneHintAtATime() {
        var pacing = TipPacing()
        show(&pacing, .shelfStarter, at: 0)
        #expect(refusal(pacing, .shelfNewPainting, at: 10) == .anotherShowing)
        // Even Tap to Paint waits for it.
        #expect(refusal(pacing, .benchTap, at: 10) == .anotherShowing)
    }

    @Test func noHintComesRightAfterAnotherCloses() {
        var pacing = TipPacing()
        show(&pacing, .shelfStarter, at: 0)
        pacing.hide(.shelfStarter)
        pacing.noteActivity(now: Self.at(0.1))
        #expect(refusal(pacing, .newPaintingSamples, at: 0.2) == .tooSoon)
    }

    @Test func hidingAnotherHintLeavesTheOneOnScreen() {
        var pacing = TipPacing()
        show(&pacing, .shelfStarter, at: 0)
        pacing.hide(.drawerWorthALook)
        #expect(refusal(pacing, .shelfNewPainting, at: 10) == .anotherShowing)
    }

    // MARK: The gap, and something done

    @Test func threeMinutesAndSomethingDoneSeparateHints() {
        var pacing = TipPacing()
        show(&pacing, .benchZoom, at: 0)
        pacing.hide(.benchZoom)

        pacing.noteActivity(now: Self.at(1))
        #expect(refusal(pacing, .benchDrag, at: 2.9) == .tooSoon)
        #expect(refusal(pacing, .benchDrag, at: 3) == nil)
    }

    @Test func timeAloneIsNotEnough() {
        var pacing = TipPacing()
        show(&pacing, .benchZoom, at: 0)
        pacing.hide(.benchZoom)
        #expect(refusal(pacing, .benchDrag, at: 20) == .nothingDone)
        pacing.noteActivity(now: Self.at(21))
        #expect(refusal(pacing, .benchDrag, at: 21) == nil)
    }

    @Test func somethingDoneWhileAHintShowsCounts() {
        var pacing = TipPacing()
        show(&pacing, .benchZoom, at: 0)
        // A fill beside the note, say: the painter did something after the hint appeared.
        pacing.noteActivity(now: Self.at(1))
        pacing.hide(.benchZoom)
        #expect(refusal(pacing, .benchDrag, at: 5) == nil)
    }

    @Test func theGapRunsFromTheLastHintShown() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .benchZoom, at: 0)
        shownAndDone(&pacing, .benchDrag, at: 4)
        #expect(refusal(pacing, .benchShowPhoto, at: 6) == .tooSoon)
        #expect(refusal(pacing, .benchShowPhoto, at: 7) == nil)
    }

    @Test func tapToPaintWaitsForNeitherTheGapNorSomethingDone() {
        var pacing = TipPacing()
        show(&pacing, .shelfStarter, at: 0)
        // Opening the painting used the shelf's hint: seconds later the bench says how to paint.
        pacing.hide(.shelfStarter)
        #expect(refusal(pacing, .benchTap, at: 0.2) == nil)
        #expect(refusal(pacing, .benchZoom, at: 0.2) == .tooSoon)
    }

    /// Refine's Draw Your Own Lines says how to use the screen at all, as Tap to Paint does: it comes
    /// as Refine opens, just after the preview's Shape the Lines Yourself.
    @Test func drawYourOwnLinesWaitsForNeitherTheGapNorSomethingDone() {
        var pacing = TipPacing()
        show(&pacing, .newPaintingRefine, at: 0)
        pacing.hide(.newPaintingRefine)
        #expect(refusal(pacing, .refineDraw, at: 0.2) == nil)
        #expect(refusal(pacing, .refineFill, at: 0.2) == .tooSoon)
    }

    // MARK: Sessions and days

    @Test func aSessionHasThreeHints() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        shownAndDone(&pacing, .shelfNewPainting, at: 5)
        shownAndDone(&pacing, .shelfHold, at: 10)
        #expect(refusal(pacing, .shelfSettings, at: 15) == .sessionFull)
    }

    @Test func aBreakStartsANewSession() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        shownAndDone(&pacing, .shelfNewPainting, at: 5)
        shownAndDone(&pacing, .shelfHold, at: 10)
        #expect(refusal(pacing, .shelfSettings, at: 20) == .sessionFull)

        // Away for half an hour: back to a session of its own.
        #expect(refusal(pacing, .shelfSettings, at: 10.5 + TipPacing.sessionBreak / 60) == nil)
        pacing.beginSession(now: Self.at(10.5 + TipPacing.sessionBreak / 60))
        #expect(pacing.shownThisSession == 0)
    }

    @Test func aSessionLastsThroughUse() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        shownAndDone(&pacing, .shelfNewPainting, at: 5)
        shownAndDone(&pacing, .shelfHold, at: 10)
        // Something done every ten minutes keeps it one session, however long.
        for minute in stride(from: 20.0, through: 100, by: 10) { pacing.noteActivity(now: Self.at(minute)) }
        #expect(refusal(pacing, .shelfSettings, at: 105) == .sessionFull)
    }

    @Test func aDayHasFiveHints() {
        var pacing = TipPacing()
        // Each in a session of its own: an hour apart.
        let ids: [TipID] = [.shelfStarter, .shelfNewPainting, .shelfHold, .shelfSettings, .shelfTimeLapse]
        for (i, id) in ids.enumerated() { shownAndDone(&pacing, id, at: Double(i) * 60) }
        #expect(pacing.shownToday == 5)
        #expect(refusal(pacing, .newPaintingSamples, at: 300) == .dayFull)
        // A new day, a new count.
        #expect(refusal(pacing, .newPaintingSamples, at: 24 * 60) == nil)
    }

    @Test func theDayEndsAtTheCalendarsMidnight() throws {
        var pacing = TipPacing()
        let lateEvening = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23, minute: 50)))
        let ids: [TipID] = [.shelfStarter, .shelfNewPainting, .shelfHold, .shelfSettings, .shelfTimeLapse]
        // Five hints, an hour apart, the last at ten to midnight.
        for (i, id) in ids.enumerated() {
            let when = lateEvening.addingTimeInterval(Double(i - 4) * 3600)
            pacing.show(id, now: when, calendar: Self.calendar)
            pacing.hide(id)
            pacing.noteActivity(now: when.addingTimeInterval(30))
        }
        let beforeMidnight = lateEvening.addingTimeInterval(5 * 60)
        #expect(pacing.refusal(for: .benchZoom, quiet: [], now: beforeMidnight, calendar: Self.calendar) == .dayFull)
        let afterMidnight = lateEvening.addingTimeInterval(20 * 60)
        #expect(pacing.refusal(for: .benchZoom, quiet: [], now: afterMidnight, calendar: Self.calendar) == nil)
    }

    @Test func theDayIsTheDeviceCalendarsDay() throws {
        let instant = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23)))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        #expect(TipPacing.dayKey(instant, calendar: Self.calendar) == "2026-10-17")
        #expect(TipPacing.dayKey(instant, calendar: tokyo) == "2026-10-18")
    }

    // MARK: The first painting

    @Test func theFirstPaintingHasTapToPaintAndTwoOthers() {
        var pacing = TipPacing()
        // The shelf spoke before the painting opened.
        shownAndDone(&pacing, .shelfStarter, at: 0)
        pacing.firstPaintingOpened(now: Self.at(1))
        shownAndDone(&pacing, .benchTap, at: 1)
        #expect(pacing.firstPaintingLeft == 2)
        shownAndDone(&pacing, .benchZoom, at: 5)
        shownAndDone(&pacing, .benchDrag, at: 9)
        #expect(pacing.firstPaintingLeft == 0)
        #expect(refusal(pacing, .benchShowPhoto, at: 13) == .firstPaintingFull)
    }

    @Test func theFirstPaintingsLimitReplacesTheSessionsOnThePainting() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        pacing.firstPaintingOpened(now: Self.at(1))
        shownAndDone(&pacing, .benchTap, at: 1)
        // Two hints in the session already. The session's own limit (three) would stop the hint
        // after the next; the first painting's, which counts from its opening, lets two more come.
        #expect(refusal(pacing, .benchZoom, at: 5) == nil)
        shownAndDone(&pacing, .benchZoom, at: 5)
        #expect(pacing.shownThisSession == 3)
        #expect(refusal(pacing, .benchDrag, at: 9) == nil)
    }

    @Test func afterTheFirstPaintingTheSessionsLimitHolds() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        pacing.firstPaintingOpened(now: Self.at(1))
        shownAndDone(&pacing, .benchTap, at: 1)
        shownAndDone(&pacing, .benchZoom, at: 5)
        pacing.paintingClosed()
        // Three shown in this session: that is all of it.
        #expect(pacing.firstPaintingLeft == nil)
        #expect(refusal(pacing, .shelfNewPainting, at: 12) == .sessionFull)
    }

    @Test func withoutAFirstPaintingTheSessionStopsAtThree() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        shownAndDone(&pacing, .benchTap, at: 0.6)
        shownAndDone(&pacing, .benchZoom, at: 5)
        #expect(refusal(pacing, .benchDrag, at: 9) == .sessionFull)
    }

    @Test func theFirstPaintingStillObeysTheDay() {
        var pacing = TipPacing()
        let ids: [TipID] = [.shelfStarter, .shelfNewPainting, .shelfHold, .shelfSettings, .shelfTimeLapse]
        for (i, id) in ids.enumerated() { shownAndDone(&pacing, id, at: Double(i) * 60) }
        pacing.firstPaintingOpened(now: Self.at(301))
        #expect(refusal(pacing, .benchTap, at: 301) == .dayFull)
    }

    @Test func aBreakEndsTheFirstPaintingsLimit() {
        var pacing = TipPacing()
        pacing.firstPaintingOpened(now: Self.at(0))
        shownAndDone(&pacing, .benchTap, at: 0)
        shownAndDone(&pacing, .benchZoom, at: 5)
        shownAndDone(&pacing, .benchDrag, at: 9)
        #expect(refusal(pacing, .benchShowPhoto, at: 13) == .firstPaintingFull)
        // The painting is still open an hour on: the session is a new one.
        #expect(refusal(pacing, .benchShowPhoto, at: 80) == nil)
        pacing.beginSession(now: Self.at(80))
        #expect(pacing.firstPaintingLeft == nil)
    }

    // MARK: Quiet moments

    @Test(arguments: [
        TipPacing.Quiet.handOnPage, .filling, .makingOf, .replay, .shine, .zenDrifting, .feedback,
    ])
    func nothingSpeaksDuringAQuietMoment(_ quiet: TipPacing.Quiet) {
        let pacing = TipPacing()
        for id in TipID.allCases {
            #expect(refusal(pacing, id, at: 0, quiet: quiet) == .quiet, "\(id)")
        }
    }

    @Test func aQuietMomentEndsAndTheHintMayComeAgain() {
        let pacing = TipPacing()
        #expect(refusal(pacing, .benchZoom, at: 0, quiet: [.handOnPage, .filling]) == .quiet)
        #expect(refusal(pacing, .benchZoom, at: 0, quiet: []) == nil)
    }

    @Test func afterAPageIsFinishedOnlyReplaySpeaks() {
        let pacing = TipPacing()
        for id in TipID.allCases {
            let expected: TipPacing.Refusal? = id == .benchReplay ? nil : .replayOnly
            #expect(refusal(pacing, id, at: 0, quiet: .pageFinished) == expected, "\(id)")
        }
    }

    @Test func theShineSilencesEvenReplay() {
        let pacing = TipPacing()
        #expect(refusal(pacing, .benchReplay, at: 0, quiet: [.pageFinished, .shine]) == .quiet)
        #expect(refusal(pacing, .benchReplay, at: 0, quiet: [.pageFinished]) == nil)
    }

    // MARK: Waiting for the next moment

    @Test func askingChangesNothing() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .benchZoom, at: 0)
        let before = pacing
        _ = refusal(pacing, .benchDrag, at: 1)
        _ = refusal(pacing, .benchDrag, at: 1, quiet: .handOnPage)
        #expect(pacing == before)
    }

    @Test func aHintDueWhileAnotherShowsWaitsForItsNextMoment() {
        var pacing = TipPacing()
        show(&pacing, .benchZoom, at: 0)

        // Zoom Out's moment comes while Zoom In is on screen: refused, and not kept.
        #expect(refusal(pacing, .benchDrag, at: 1) == .anotherShowing)
        pacing.hide(.benchZoom)
        pacing.noteActivity(now: Self.at(2))
        // The refusal left no mark: nothing brings it up right after the first closes ...
        #expect(refusal(pacing, .benchShowPhoto, at: 2) == .tooSoon)
        // ... and the next time its moment comes, it is judged afresh.
        #expect(refusal(pacing, .benchDrag, at: 4) == nil)
    }

    @Test func aHintWhoseTurnIsNotYetUpWaitsToo() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .benchZoom, at: 0)
        #expect(refusal(pacing, .benchDrag, at: 1) == .tooSoon)
        #expect(pacing.shownToday == 1)
        #expect(refusal(pacing, .benchDrag, at: 3.5) == nil)
    }

    /// A clock set back (by hand, or by the network's time) puts the last hint in the future: no
    /// reason to wait for it.
    @Test func aClockSetBackIsNoReasonToWait() {
        var pacing = TipPacing()
        shownAndDone(&pacing, .benchZoom, at: 60)
        #expect(refusal(pacing, .benchDrag, at: 61) == .tooSoon)
        #expect(refusal(pacing, .benchDrag, at: 30) == nil)
    }

    // MARK: Keeping state

    /// What an earlier build kept lacks the fields added since: they take their defaults and the
    /// rest is kept, never started over.
    @Test func keptStateWithoutSomeFieldsKeepsTheRest() throws {
        let pacing = try JSONDecoder().decode(TipPacing.self, from: Data(#"{"shownToday":2,"day":"2026-10-17"}"#.utf8))
        #expect(pacing.shownToday == 2)
        #expect(pacing.day == "2026-10-17")
        #expect(pacing.didSomethingSince)
        #expect(pacing.shownThisSession == 0)
        #expect(pacing.lastShown == nil)

        let history = try JSONDecoder().decode(TipHistory.self, from: Data(#"{"hasFilled":true}"#.utf8))
        #expect(history.hasFilled)
        #expect(history.opened.isEmpty)
        #expect(history.tipsOnSince == nil)
    }

    @Test func theStateSurvivesBeingKept() throws {
        var pacing = TipPacing()
        pacing.firstPaintingOpened(now: Self.at(0))
        shownAndDone(&pacing, .benchTap, at: 0)
        show(&pacing, .benchZoom, at: 5)

        let data = try JSONEncoder().encode(pacing)
        var kept = try JSONDecoder().decode(TipPacing.self, from: data)
        // What is on screen is not kept: nothing is showing when the app starts.
        #expect(kept.showing == nil)
        #expect(pacing.showing == .benchZoom)
        pacing.hide(.benchZoom)
        #expect(kept == pacing)
        #expect(kept.shownToday == 2)
        #expect(kept.firstPaintingLeft == 1)
        #expect(kept.lastShown == Self.at(5))
        kept.beginSession(now: Self.at(6))
        #expect(kept.shownThisSession == 2)
    }

    @Test func theStoreKeepsPacingAndHistory() throws {
        let name = "TipPacingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TipStore(defaults: defaults)
        #expect(store.pacing() == TipPacing())
        #expect(store.history() == TipHistory())

        var pacing = TipPacing()
        shownAndDone(&pacing, .shelfStarter, at: 0)
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.start)
        history.filled()
        store.save(pacing)
        store.save(history)
        #expect(store.pacing() == pacing)
        #expect(store.history() == history)

        store.reset()
        #expect(store.pacing() == TipPacing())
        #expect(store.history() == TipHistory())
    }

    @Test func unreadableDataStartsTheTipsFresh() throws {
        let name = "TipPacingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("not json".utf8), forKey: TipStore.pacingKey)
        defaults.set("neither", forKey: TipStore.historyKey)
        let store = TipStore(defaults: defaults)
        #expect(store.pacing() == TipPacing())
        #expect(store.history() == TipHistory())
    }

    // MARK: History

    @Test func dayTwoIsTheDayAfterTipsWereTurnedOn() throws {
        var history = TipHistory()
        #expect(!history.isDayTwoOrLater(now: Self.start, calendar: Self.calendar))
        let lateEvening = try #require(
            Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23, minute: 50)))
        history.tipsTurnedOn(at: lateEvening)
        #expect(!history.isDayTwoOrLater(now: lateEvening.addingTimeInterval(5 * 60), calendar: Self.calendar))
        #expect(history.isDayTwoOrLater(now: lateEvening.addingTimeInterval(20 * 60), calendar: Self.calendar))
        // Turned on again later: day one stays where it was.
        history.tipsTurnedOn(at: lateEvening.addingTimeInterval(3 * 86400))
        #expect(history.tipsOnSince == lateEvening)
    }

    @Test func aDayAfterTheFirstFinish() {
        var history = TipHistory()
        #expect(!history.isADayAfterFirstFinish(now: Self.at(100_000)))
        history.finished(at: Self.start)
        history.finished(at: Self.at(60 * 20))
        #expect(!history.isADayAfterFirstFinish(now: Self.at(24 * 60 - 1)))
        #expect(history.isADayAfterFirstFinish(now: Self.at(24 * 60)))
    }

    @Test func historyKeepsTheFirstThreePaintingsOpened() {
        var history = TipHistory()
        let first = history.paintingOpened("a")
        let again = history.paintingOpened("a")
        let second = history.paintingOpened("b")
        #expect(first)
        #expect(!again && !second)
        #expect(history.openedCount == 2)
        history.paintingOpened("c")
        history.paintingOpened("d")
        #expect(history.opened == ["a", "b", "c"])
        #expect(history.openedCount == TipHistory.openedKept)
    }

    @Test func historyRemembersTheFirstFill() {
        var history = TipHistory()
        #expect(!history.hasFilled)
        history.filled()
        #expect(history.hasFilled)
    }

    // MARK: Ids

    /// The design's 22, and Refine's Draw Your Own Lines (Paul's calmer menus, October 18).
    @Test func thereAreTwentyThreeTips() {
        #expect(TipID.allCases.count == 23)
        #expect(Set(TipID.allCases.map(\.rawValue)).count == 23)
    }

    @Test func theTipsAtNavigationBarButtonsAreTheGearThePlusAndRefine() {
        let bar = TipID.allCases.filter { $0.liesUnderTheBar }
        #expect(Set(bar) == [.shelfSettings, .shelfNewPainting, .newPaintingRefine])
    }

    @Test func theTipsOnThePageAreZoomDragAndPencil() {
        let page = TipID.allCases.filter { $0.liesOnThePage }
        #expect(Set(page) == [.benchZoom, .benchDrag, .benchPencil])
    }

    @Test func theTipsOnCardsAreTheHoldAndTheTimeLapse() {
        let cards = TipID.allCases.filter { $0.hangsFromCard }
        #expect(Set(cards) == [.shelfHold, .shelfTimeLapse])
    }

    @Test func eachHintLivesWhereTheDesignPutsIt() {
        func ids(in place: TipPlace) -> Set<TipID> { Set(TipID.allCases.filter { $0.place == place }) }
        #expect(ids(in: .shelf) == [.shelfStarter, .shelfNewPainting, .shelfHold, .shelfTimeLapse, .shelfSettings])
        #expect(ids(in: .newPainting) == [.newPaintingSamples])
        #expect(ids(in: .preview) == [
            .newPaintingDivider, .newPaintingSuggested, .newPaintingReset, .newPaintingSliders, .newPaintingRefine,
        ])
        #expect(ids(in: .refine) == [.refineDraw, .refineFill])
        #expect(ids(in: .bench) == [
            .benchTap, .benchZoom, .benchFind, .benchDrag, .benchPencil, .benchShowPhoto, .benchReplay, .benchZen,
            .benchFeedback,
        ])
        #expect(ids(in: .drawer) == [.drawerWorthALook])
    }
}
