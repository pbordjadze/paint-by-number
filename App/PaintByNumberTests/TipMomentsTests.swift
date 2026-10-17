import Foundation
import Testing
@testable import PaintByNumber

/// The Tips switch's value, and which tips each moment may offer.
struct TipMomentsTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static let dayOne = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10)) ?? .distantPast
    private static let dayTwo = dayOne.addingTimeInterval(24 * 3600)

    private func defaults() throws -> (UserDefaults, cleanup: () -> Void) {
        let name = "TipMomentsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: The switch

    /// Tips are on for everyone until they switch them off in Settings: whoever updates from an
    /// earlier build has no value stored, and has them too.
    @Test func tipsAreOnUntilSwitchedOff() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        #expect(TipPreference.isEnabled(in: defaults))
        defaults.set(2, forKey: "tipsGeneration")
        #expect(TipPreference.isEnabled(in: defaults))
    }

    @Test func theSwitchKeepsWhatItWasSetTo() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        TipPreference.record(false, in: defaults)
        #expect(!TipPreference.isEnabled(in: defaults))
        TipPreference.record(true, in: defaults)
        #expect(TipPreference.isEnabled(in: defaults))
        TipPreference.record(false, in: defaults)
        #expect(!TipPreference.isEnabled(in: defaults))
    }

    @Test func forgettingTheSwitchIsTheDefault() throws {
        let (defaults, cleanup) = try defaults()
        defer { cleanup() }
        TipPreference.record(false, in: defaults)
        TipPreference.forget(in: defaults)
        #expect(TipPreference.isEnabled(in: defaults))
    }

    // MARK: The shelf

    private func shelf(_ facts: TipMoments.Shelf, history: TipHistory = TipHistory(), now: Date = dayOne) -> [TipID] {
        TipMoments.shelf(facts, history: history, now: now, calendar: Self.calendar)
    }

    @Test func theShelfSaysNothingBeforeItsPagesAreInView() {
        #expect(shelf(.init(artworks: 0)).isEmpty)
        #expect(shelf(.init(artworks: 1, ready: 1, preparing: true)).isEmpty)
        #expect(shelf(.init(artworks: 2, ready: 2, preparing: true)).isEmpty)
    }

    /// The first visit, with no question asked: the page that waits.
    @Test func theFirstVisitLeadsToThePageThatWaits() {
        #expect(shelf(.init(artworks: 2, started: 0, ready: 2, finished: 0)) == [.shelfStarter])
    }

    @Test func thePageThatWaitsStopsWhenAPaintingIsOpened() {
        var history = TipHistory()
        history.paintingOpened("great-wave")
        #expect(shelf(.init(artworks: 2, started: 0, ready: 2, finished: 0), history: history).isEmpty)
    }

    @Test func thePageThatWaitsStopsWhenAnythingIsPainted() {
        #expect(shelf(.init(artworks: 2, started: 1, ready: 1, finished: 0)) == [.shelfNewPainting])
    }

    @Test func nothingToStartMeansNoPageIsWaiting() {
        #expect(shelf(.init(artworks: 1, started: 0, ready: 0, finished: 0)).isEmpty)
    }

    @Test func holdWaitsForDayTwoAndTwoPaintings() {
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        let two = TipMoments.Shelf(artworks: 2, started: 1, ready: 1, finished: 0)
        #expect(shelf(two, history: history, now: Self.dayOne.addingTimeInterval(3600)) == [.shelfNewPainting])
        #expect(shelf(two, history: history, now: Self.dayTwo) == [.shelfNewPainting, .shelfHold])
        let one = TipMoments.Shelf(artworks: 1, started: 1, ready: 0, finished: 0)
        #expect(shelf(one, history: history, now: Self.dayTwo) == [.shelfNewPainting])
    }

    @Test func finishedPaintingsBringSettingsThenTheTimeLapse() {
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        let finished = TipMoments.Shelf(artworks: 3, started: 1, ready: 0, finished: 2)
        #expect(shelf(finished, history: history, now: Self.dayTwo) == [
            .shelfNewPainting, .shelfHold, .shelfSettings, .shelfTimeLapse,
        ])
        #expect(shelf(finished, history: history, now: Self.dayOne) == [
            .shelfNewPainting, .shelfSettings, .shelfTimeLapse,
        ])
    }

    /// One finished painting and nothing else: Settings and Tips is the first the shelf can say.
    @Test func aLoneFinishedPaintingBringsSettings() {
        let lone = TipMoments.Shelf(artworks: 1, started: 0, ready: 0, finished: 1)
        #expect(shelf(lone) == [.shelfNewPainting, .shelfSettings, .shelfTimeLapse])
    }

    @Test func everyShelfTipTheMomentOffersLivesOnTheShelf() {
        var history = TipHistory()
        history.tipsTurnedOn(at: Self.dayOne)
        let all = TipMoments.Shelf(artworks: 6, started: 2, ready: 2, finished: 2)
        let offered = shelf(all, history: history, now: Self.dayTwo)
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
