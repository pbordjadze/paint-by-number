import Foundation
import Testing
@testable import PaintByNumber

/// The invitation's answer (the Tips switch's value), and which tips each moment may offer.
struct TipInvitationTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static let dayOne = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10)) ?? .distantPast
    private static let dayTwo = dayOne.addingTimeInterval(24 * 3600)

    private func defaults() throws -> (UserDefaults, cleanup: () -> Void) {
        let name = "TipInvitationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: The answer

    @Test func theInvitationIsUnansweredUntilAnswered() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        #expect(TipInvitation.answer(in: defaults) == .unanswered)
        #expect(!TipInvitation.isEnabled(in: defaults))
    }

    @Test func showTipsTurnsTipsOn() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        TipInvitation.record(true, in: defaults)
        #expect(TipInvitation.answer(in: defaults) == .showTips)
        #expect(TipInvitation.isEnabled(in: defaults))
        #expect(defaults.object(forKey: SettingsKey.tipsEnabled) as? Bool == true)
    }

    @Test func noThanksKeepsThemOffAndIsAnAnswer() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        TipInvitation.record(false, in: defaults)
        #expect(TipInvitation.answer(in: defaults) == .noThanks)
        #expect(!TipInvitation.isEnabled(in: defaults))
        // Set, though off: the invitation has been answered.
        #expect(defaults.object(forKey: SettingsKey.tipsEnabled) as? Bool == false)
    }

    @Test func theSettingsSwitchChangesTheAnswerNotTheQuestion() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        TipInvitation.record(false, in: defaults)
        TipInvitation.record(true, in: defaults)
        TipInvitation.record(false, in: defaults)
        #expect(TipInvitation.answer(in: defaults) == .noThanks)
    }

    @Test func forgettingTheAnswerAsksAgain() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        TipInvitation.record(true, in: defaults)
        TipInvitation.forget(in: defaults)
        #expect(TipInvitation.answer(in: defaults) == .unanswered)
    }

    /// Testers who update from an earlier build have no answer yet: they are asked once too.
    @Test func anUpdatingTesterIsAskedOnce() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        defaults.set(2, forKey: "tipsGeneration")
        #expect(TipInvitation.answer(in: defaults) == .unanswered)
        #expect(TipMoments.shelf(
            .init(artworks: 6, started: 3, ready: 1, finished: 2), answer: TipInvitation.answer(in: defaults),
            history: TipHistory(), now: Self.dayOne, calendar: Self.calendar) == [.invitation])
    }

    // MARK: The shelf

    private func shelf(
        _ facts: TipMoments.Shelf, _ answer: TipInvitation.Answer, history: TipHistory = TipHistory(), now: Date = dayOne
    ) -> [TipID] {
        TipMoments.shelf(facts, answer: answer, history: history, now: now, calendar: Self.calendar)
    }

    @Test func theShelfSaysNothingBeforeItsPagesAreInView() {
        #expect(shelf(.init(artworks: 0), .unanswered).isEmpty)
        #expect(shelf(.init(artworks: 1, ready: 1, preparing: true), .unanswered).isEmpty)
        #expect(shelf(.init(artworks: 2, ready: 2, preparing: true), .showTips).isEmpty)
    }

    @Test func theInvitationComesFirstAndOnlyUntilAnswered() {
        let starters = TipMoments.Shelf(artworks: 2, started: 0, ready: 2, finished: 0)
        #expect(shelf(starters, .unanswered) == [.invitation])
        // Never again, whichever the answer.
        #expect(!shelf(starters, .showTips).contains(.invitation))
        #expect(shelf(starters, .noThanks).isEmpty)
    }

    @Test func noThanksMeansNoHintsAtAll() {
        let busy = TipMoments.Shelf(artworks: 6, started: 3, ready: 1, finished: 2)
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        #expect(shelf(busy, .noThanks, history: history, now: Self.dayTwo).isEmpty)
    }

    @Test func showTipsLeadsToThePageThatWaits() {
        #expect(shelf(.init(artworks: 2, started: 0, ready: 2, finished: 0), .showTips) == [.shelfStarter])
    }

    @Test func thePageThatWaitsStopsWhenAPaintingIsOpened() {
        var history = TipHistory()
        history.paintingOpened("great-wave")
        #expect(shelf(.init(artworks: 2, started: 0, ready: 2, finished: 0), .showTips, history: history).isEmpty)
    }

    @Test func thePageThatWaitsStopsWhenAnythingIsPainted() {
        #expect(shelf(.init(artworks: 2, started: 1, ready: 1, finished: 0), .showTips) == [.shelfNewPainting])
    }

    @Test func nothingToStartMeansNoPageIsWaiting() {
        #expect(shelf(.init(artworks: 1, started: 0, ready: 0, finished: 0), .showTips).isEmpty)
    }

    @Test func holdWaitsForDayTwoAndTwoPaintings() {
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        let two = TipMoments.Shelf(artworks: 2, started: 1, ready: 1, finished: 0)
        #expect(shelf(two, .showTips, history: history, now: Self.dayOne.addingTimeInterval(3600)) == [.shelfNewPainting])
        #expect(shelf(two, .showTips, history: history, now: Self.dayTwo) == [.shelfNewPainting, .shelfHold])
        let one = TipMoments.Shelf(artworks: 1, started: 1, ready: 0, finished: 0)
        #expect(shelf(one, .showTips, history: history, now: Self.dayTwo) == [.shelfNewPainting])
    }

    @Test func finishedPaintingsBringSettingsThenTheTimeLapse() {
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        let finished = TipMoments.Shelf(artworks: 3, started: 1, ready: 0, finished: 2)
        #expect(shelf(finished, .showTips, history: history, now: Self.dayTwo) == [
            .shelfNewPainting, .shelfHold, .shelfSettings, .shelfTimeLapse,
        ])
        #expect(shelf(finished, .showTips, history: history, now: Self.dayOne) == [
            .shelfNewPainting, .shelfSettings, .shelfTimeLapse,
        ])
    }

    @Test func everyShelfTipTheMomentOffersLivesOnTheShelf() {
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        let all = TipMoments.Shelf(artworks: 6, started: 2, ready: 2, finished: 2)
        let offered = shelf(all, .showTips, history: history, now: Self.dayTwo)
        let onTheShelf = offered.allSatisfy { $0.place == .shelf }
        #expect(!offered.isEmpty)
        #expect(onTheShelf)
        #expect(Set(offered).count == offered.count)
    }

    // MARK: The preview

    @Test func theDividerComesFirstAndSuggestedWaitsForIt() {
        #expect(TipMoments.preview(dividerIsOver: false, isSuggested: true, canRefine: true) == [
            .newPaintingDivider, .newPaintingSliders, .newPaintingRefine,
        ])
        #expect(TipMoments.preview(dividerIsOver: true, isSuggested: true, canRefine: true) == [
            .newPaintingDivider, .newPaintingSuggested, .newPaintingSliders, .newPaintingRefine,
        ])
    }

    @Test func suggestedSpeaksOnlyOfSettingsThatAreStillTheSuggestion() {
        #expect(!TipMoments.preview(dividerIsOver: true, isSuggested: false, canRefine: true).contains(.newPaintingSuggested))
    }

    @Test func refineIsOfferedOnlyWhereItCanOpen() {
        #expect(!TipMoments.preview(dividerIsOver: true, isSuggested: true, canRefine: false).contains(.newPaintingRefine))
    }

    @Test func everyPreviewTipTheMomentOffersLivesInThePreview() {
        let offered = TipMoments.preview(dividerIsOver: true, isSuggested: true, canRefine: true)
        let inThePreview = offered.allSatisfy { $0.place == .preview }
        #expect(inThePreview)
    }
}
