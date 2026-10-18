import Foundation
import Testing
@testable import PaintByNumber

/// The desk's bookkeeping: what the painter has done, the Tips switch, starting over. (Giving a tip
/// its turn asks TipKit, which these tests leave alone: `TipPacingTests` covers the limits and
/// `TipMomentsTests` which tips a moment offers.)
@MainActor
struct TipDeskTests {
    /// A clock the test moves, and a suite of its own.
    private final class TestClock {
        var date = Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 10, day: 17, hour: 10)) ?? .distantPast
    }

    private struct Fixture {
        let desk: TipDesk
        let store: TipStore
        let clock: TestClock
        let defaults: UserDefaults
        let suite: String

        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }

    /// A desk on a suite of its own, with the Tips switch as given (on, the default, leaves it unset).
    private func fixture(tipsOn: Bool = true) throws -> Fixture {
        let suite = "TipDeskTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        if !tipsOn { TipPreference.record(false, in: defaults) }
        let store = TipStore(defaults: defaults)
        let clock = TestClock()
        let desk = TipDesk(store: store, now: { clock.date })
        return Fixture(desk: desk, store: store, clock: clock, defaults: defaults, suite: suite)
    }

    @Test func theFirstPaintingOpenedIsTheFirst() throws {
        let f = try fixture()
        defer { f.cleanup() }
        #expect(f.desk.paintingOpened("a"))
        #expect(!f.desk.paintingOpened("a"))
        #expect(!f.desk.paintingOpened("b"))
        #expect(f.desk.openedCount == 2)
        #expect(f.store.history().opened == ["a", "b"])
    }

    @Test func theFirstPaintingGetsItsOwnLimitOnlyWithTipsOn() throws {
        let off = try fixture(tipsOn: false)
        defer { off.cleanup() }
        off.desk.paintingOpened("a")
        #expect(off.store.pacing().firstPaintingLeft == nil)

        let on = try fixture()
        defer { on.cleanup() }
        on.desk.paintingOpened("a")
        #expect(on.store.pacing().firstPaintingLeft == TipPacing.hintsOnFirstPainting)
        on.desk.paintingClosed()
        #expect(on.store.pacing().firstPaintingLeft == nil)
    }

    @Test func fillingIsKeptOnce() throws {
        let f = try fixture()
        defer { f.cleanup() }
        #expect(!f.desk.hasFilled)
        f.desk.filled()
        f.desk.filled()
        #expect(f.desk.hasFilled)
        #expect(f.store.history().hasFilled)
    }

    /// Tips are on from the first launch: day one is the day the desk was first made.
    @Test func theFirstDayBeginsAtTheFirstLaunch() throws {
        let f = try fixture()
        defer { f.cleanup() }
        #expect(f.store.history().tipsOnSince == f.clock.date)
        #expect(!f.desk.isDayTwoOrLater)
        f.clock.date.addTimeInterval(24 * 3600)
        #expect(f.desk.isDayTwoOrLater)
        // A later launch keeps the day tips began.
        let later = TipDesk(store: f.store, now: { f.clock.date })
        #expect(later.isDayTwoOrLater)
    }

    @Test func switchingTipsOffAndOnKeepsTheDayTheyBegan() throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.clock.date.addTimeInterval(24 * 3600)
        f.desk.answered(tipsOn: false)
        f.desk.answered(tipsOn: true)
        #expect(f.desk.answers == 2)
        #expect(f.desk.isDayTwoOrLater)
    }

    @Test func tipsSwitchedOffBeginNoDay() throws {
        let f = try fixture(tipsOn: false)
        defer { f.cleanup() }
        #expect(f.store.history().tipsOnSince == nil)
        f.clock.date.addTimeInterval(5 * 24 * 3600)
        #expect(!f.desk.isDayTwoOrLater)
    }

    @Test func feedbackIsDueOnTheThirdPaintingADayAfterTheFirstFinish() throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.desk.paintingOpened("a")
        f.desk.finished()
        f.desk.paintingOpened("b")
        f.clock.date.addTimeInterval(25 * 3600)
        #expect(!f.desk.feedbackIsDue)
        f.desk.paintingOpened("c")
        #expect(f.desk.feedbackIsDue)
    }

    @Test func feedbackWaitsADayAfterTheFinish() throws {
        let f = try fixture()
        defer { f.cleanup() }
        for painting in ["a", "b", "c"] { f.desk.paintingOpened(painting) }
        f.desk.finished()
        f.clock.date.addTimeInterval(23 * 3600)
        #expect(!f.desk.feedbackIsDue)
        f.clock.date.addTimeInterval(3600)
        #expect(f.desk.feedbackIsDue)
    }

    /// No question is asked: the first visit's candidate is the page that waits.
    @Test func theShelfOffersThePageThatWaitsToANewcomer() throws {
        let f = try fixture()
        defer { f.cleanup() }
        let starters = TipMoments.Shelf(artworks: 2, started: 0, ready: 2, finished: 0)
        #expect(f.desk.shelfCandidates(starters) == [.shelfStarter])
    }

    @Test func startingOverMakesEveryTipFresh() throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.desk.answered(tipsOn: true)
        f.desk.paintingOpened("a")
        f.desk.filled()
        f.desk.finished()
        f.desk.noteActivity()
        f.clock.date.addTimeInterval(3 * 24 * 3600)

        f.desk.startOver()
        #expect(!f.desk.hasFilled)
        #expect(f.desk.openedCount == 0)
        #expect(!f.desk.isDayTwoOrLater)
        #expect(f.store.history().firstFinishedAt == nil)
        #expect(f.store.history().tipsOnSince == f.clock.date)
        #expect(f.store.pacing().firstPaintingLeft == nil)
        #expect(f.store.pacing().shownToday == 0)
    }

    @Test func aMutedDeskOffersNothing() throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.desk.isMuted = true
        f.desk.enter(.shelf)
        // The turn comes later, if at all: what a refused moment leaves is no offering.
        f.desk.offer([.shelfStarter], in: .shelf, rest: .zero)
        #expect(f.desk.offeringPlace == nil)
        f.desk.isMuted = false
        f.desk.offer([.shelfStarter], in: .shelf, rest: .zero)
        #expect(f.desk.offeringPlace == .shelf)
        f.desk.leave(.shelf)
    }

    /// Tips off means none: nothing is offered, though nothing is muted.
    @Test func aDeskWithTipsSwitchedOffOffersNothing() throws {
        let f = try fixture(tipsOn: false)
        defer { f.cleanup() }
        f.desk.enter(.shelf)
        f.desk.offer([.shelfStarter], in: .shelf, rest: .zero)
        #expect(f.desk.offeringPlace == nil)
        #expect(f.desk.turn == nil)
    }

    /// A painting just started opens under the create flow, and the shelf is uncovered as it goes:
    /// the shelf's moment then leaves Tap to Paint's alone.
    @Test func theShelfBehindAPaintingDoesNotCallOffItsMoment() throws {
        let f = try fixture()
        defer { f.cleanup() }
        f.desk.enter(.shelf)
        f.desk.enter(.bench)
        f.desk.offer([.benchTap], in: .bench, rest: .seconds(5))
        #expect(f.desk.offeringPlace == .bench)
        f.desk.offer([.shelfStarter], in: .shelf, rest: .zero)
        #expect(f.desk.offeringPlace == .bench)
        f.desk.leave(.bench)
        f.desk.isCovered = true
        f.desk.offer([.shelfStarter], in: .shelf, rest: .zero)
        #expect(f.desk.offeringPlace == nil)
    }

    @Test func noTipHasTheTurnBeforeOneIsGiven() throws {
        let f = try fixture()
        defer { f.cleanup() }
        #expect(f.desk.turn == nil)
        for id in TipID.allCases { #expect(f.desk.tip(among: [id]) == nil, "\(id)") }
    }
}
