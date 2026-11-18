import Observation
import os
import SwiftUI
import TipKit

/// Gives the tips their turns. TipKit decides when a tip is eligible (its rules: events and the
/// tips-on parameter) and draws it; it has no say in when a tip may appear *now*, so views point
/// only the tip whose turn it is (`gentleTip`, `GentleTipView`) and this desk decides whose that is:
///
/// - A screen reports a moment its tips may come at (`offer`): the shelf appeared, the preview is
///   final, the painter stopped for a minute. The desk waits for TipKit to find one of the tips
///   eligible, and for the painter's hand to rest, then asks `TipPacing`. Refused, the moment is
///   spent: nothing is queued, the tip waits for the next time its moment comes (design §5).
/// - Granted, the tip has the turn until it is closed, used, or its screen goes (`release`,
///   `leave`), and `turn` is the only tip any view points. One at a time follows.
///
/// A tip that TipKit shows for its own reasons would not be here: every view takes its tip from
/// `turn`, and the tips' rules carry the tips-on parameter besides.
@MainActor
@Observable
final class TipDesk {
    /// The tip whose turn it is: the only one a view may point.
    private(set) var turn: TipID?
    /// Counts the changes of the Tips switch; a screen that offers when tips come on (the shelf,
    /// after Show Tips Again) watches it.
    private(set) var answers = 0
    /// Counts the times the shelf came back into view under a screen that went (a painting,
    /// New Painting, Settings): back from a painting the shelf appears before the painting screen
    /// has left, so its own appearance offered nothing. Pacing still judges what it offers.
    private(set) var shelfReturns = 0

    /// Tests and demos that show no tips: nothing is offered.
    @ObservationIgnored var isMuted = false
    /// A screen is over the shelf (the create flow, Settings, a sheet): its tips wait.
    @ObservationIgnored var isCovered = false

    @ObservationIgnored private var pacing: TipPacing
    @ObservationIgnored private var history: TipHistory
    @ObservationIgnored private let store: TipStore
    @ObservationIgnored private let now: () -> Date
    /// The moment being waited out, with the screen it belongs to: when that goes, so does it. It
    /// is over once its task ends, with a turn or without (`number` tells it from the moment that
    /// took its place).
    @ObservationIgnored private var offering: (place: TipPlace, task: Task<Void, Never>, number: Int)?
    @ObservationIgnored private var offers = 0
    /// The screen whose moment is being waited out.
    var offeringPlace: TipPlace? { offering?.place }
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The latest moment the painter did something (a fill, a slider, a screen): the hand has
    /// rested for as long as it was before now.
    @ObservationIgnored private var lastActivity = ContinuousClock.now
    @ObservationIgnored private var places: [TipPlace] = []
    /// The shelf has given a hint on this visit: one a visit, so each waits for a visit of its own.
    @ObservationIgnored private var servedShelf = false
    /// How many views that can point each of `needsAnchor` are on screen (a card mostly in view, a
    /// bar's button in its bar).
    @ObservationIgnored private var anchored: [TipID: Int] = [:]
    /// The tip the app last drew itself where TipKit would have (`TipForm.beside`): TipKit counts
    /// no display of it, so the desk says it once, as it does `TipID.isDrawnByTheApp`'s.
    @ObservationIgnored private var drawnBeside: TipID?
    /// Tips about a view that may not be there: a card the shelf builds only near the screen, a bar
    /// button that goes while the preview is enlarged, a tool's button in a tab that isn't showing.
    /// Given a turn only while one is (`TipAnchor`).
    static let needsAnchor: Set<TipID> = Set(
        TipID.allCases.filter { $0.hangsFromCard || $0.liesUnderTheBar || $0.hidesWithItsTab })

    /// How long TipKit gets to find a tip eligible (a donation or a parameter just changed), and
    /// the least a moment waits before it takes the first one that is. Counted in looks, one each
    /// `poll`, not by the clock alone: a stall of the main actor as a painting opens (seconds,
    /// under load) used the whole window before TipKit had been asked twice, and the first tip
    /// never came (`testTheFirstTipsLeadIntoThePainting`, painting-company row 263). The clock still
    /// bounds it, at `eligibilityLimit`.
    private static let eligibilityWindow: Duration = .seconds(3)
    private static let poll: Duration = .milliseconds(100)
    private static let eligibilityLimit: Duration = .seconds(12)
    private static let settle: Duration = .milliseconds(350)
    /// The longest a moment waits for the hand to rest.
    private static let restWindow: Duration = .seconds(12)
    /// A tip left alone this long has had its say: its turn lapses.
    private static let lapse: Duration = .seconds(45)
    /// A tip TipKit has retired for being shown keeps its turn this long, which is time to read it.
    private static let shownEnough: Duration = .seconds(15)

    init(store: TipStore = TipStore(), now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
        pacing = store.pacing()
        history = store.history()
        pacing.beginSession(now: now())
        // Tips are on from the first launch (and for whoever updates from an earlier build): the
        // first day is today.
        if history.tipsOnSince == nil, TipPreference.isEnabled(in: store.defaults) {
            history.tipsTurnedOn(at: now())
            store.save(history)
        }
    }

    // MARK: What a view asks

    /// The tip of the turn, if it lies on the page (`TipID.liesOnThePage`).
    var pageTip: (any Tip)? {
        guard let turn, turn.liesOnThePage else { return nil }
        return turn.tip
    }

    /// The tip of the turn, if it is one of `ids`.
    func tip(among ids: TipSet) -> (any Tip)? {
        guard let turn, ids.contains(turn) else { return nil }
        return turn.tip
    }

    // MARK: Where the painter is

    /// A screen appears. Going to another screen is something done. A screen it covers keeps
    /// quiet: its tip goes and its moment is called off.
    func enter(_ place: TipPlace) {
        places.removeAll { $0 == place }
        places.append(place)
        if place == .shelf { servedShelf = false }
        if let offering, !isInView(offering.place) { stopOffering() }
        if let turn, !isInView(turn.place) { release(turn) }
        noteActivity()
    }

    /// A screen goes. Its tip goes with it, and its moments.
    func leave(_ place: TipPlace) {
        places.removeAll { $0 == place }
        if offering?.place == place { stopOffering() }
        if let turn, turn.place == place { retire(turn) }
        if place != .shelf, isInView(.shelf) { shelfReturns += 1 }
        noteActivity()
    }

    private func stopOffering() {
        offering?.task.cancel()
        offering = nil
    }

    /// Views that can point `ids` came on screen or went (only the tips that need one count).
    func anchor(_ ids: [TipID], present: Bool) {
        for id in ids where Self.needsAnchor.contains(id) {
            anchored[id] = max(0, anchored[id, default: 0] + (present ? 1 : -1))
        }
    }

    /// A view drew `id` itself, beside its subject (`TipForm.beside`), or is about to: it says so
    /// as the turn reaches it. The tip is then retired when its turn ends, lapsed too, even if
    /// its popover never came up, as the tips the app draws as cards already are
    /// (`TipID.isDrawnByTheApp`).
    func drewBeside(_ id: TipID) {
        drawnBeside = id
    }

    /// The painter did something.
    func noteActivity() {
        lastActivity = ContinuousClock.now
        pacing.noteActivity(now: now())
    }

    /// The app starts or comes to the front.
    func beginSession() {
        pacing.beginSession(now: now())
    }

    // MARK: What the painter has done

    var hasFilled: Bool { history.hasFilled }
    var openedCount: Int { history.openedCount }

    func filled() {
        guard !history.hasFilled else { return }
        history.filled()
        store.save(history)
    }

    func finished() {
        history.finished(at: now())
        store.save(history)
    }

    /// A painting opens. True for the first one the painter has ever opened: its own limit of hints
    /// begins (`TipPacing`).
    @discardableResult
    func paintingOpened(_ id: String) -> Bool {
        let first = history.paintingOpened(id)
        store.save(history)
        if first, TipPreference.isEnabled(in: store.defaults) {
            pacing.firstPaintingOpened(now: now())
            store.save(pacing)
        }
        return first
    }

    func paintingClosed() {
        pacing.paintingClosed()
        store.save(pacing)
    }

    /// Facts the moments of the shelf and the bench are chosen with.
    func shelfCandidates(_ facts: TipMoments.Shelf) -> [TipID] {
        TipMoments.shelf(facts, history: history, now: now())
    }

    var isDayTwoOrLater: Bool { history.isDayTwoOrLater(now: now()) }

    /// Opening the third painting, a day after the first page was finished.
    var feedbackIsDue: Bool {
        history.openedCount >= TipHistory.openedKept && history.isADayAfterFirstFinish(now: now())
    }

    // MARK: Turns

    /// A moment of `place` has come, at which one of `candidates` (in order of preference) may speak.
    /// `rest` is how long the painter's hand must have been still; `quiet` says what is on screen
    /// that keeps hints away, asked again when the turn would be given.
    func offer(
        _ candidates: [TipID], in place: TipPlace, rest: Duration = .milliseconds(900),
        quiet: @escaping @MainActor () -> TipPacing.Quiet = { [] }
    ) {
        guard !isMuted, TipPreference.isEnabled(in: store.defaults) else { return }
        // The shelf's moments come from a gallery that stays in the hierarchy under a painting,
        // whose library changes as it is painted, and from uncovering it, which a painting just
        // started does at once: they must not call off the moment of the screen in front.
        if place == .shelf, !isInView(.shelf) { return }
        // A tip of a screen that is no longer in view is on its way out (screens come and go in no
        // fixed order).
        if let current = turn, !isInView(current.place) { release(current) }
        guard turn == nil else { return }
        if place == .shelf, servedShelf { return }
        // What the limits refuse for good has nothing to wait for; what is only quiet, or lacks
        // something done, may change while the moment waits.
        let wanted = candidates.filter { Self.mayChange(pacing.refusal(for: $0, quiet: quiet(), now: now())) }
        notice("offer in \(place.rawValue): \(Self.names(candidates)), wanted \(Self.names(wanted))")
        guard !wanted.isEmpty else { return }
        stopOffering()
        offers += 1
        let number = offers
        offering = (place, Task { [weak self] in
            await self?.run(wanted, place: place, rest: rest, quiet: quiet)
            self?.offerEnded(number)
        }, number)
    }

    /// A moment's wait is over. One called off has gone already, and another may be in its place.
    private func offerEnded(_ number: Int) {
        if offering?.number == number { offering = nil }
    }

    /// Whether `place` is the screen the painter is on, and nothing covers it.
    private func isInView(_ place: TipPlace) -> Bool {
        places.max(by: { $0.depth < $1.depth }) == place && !(place == .shelf && isCovered)
    }

    /// Whether a refusal can lift within a moment's wait.
    private static func mayChange(_ refusal: TipPacing.Refusal?) -> Bool {
        switch refusal {
        case nil, .quiet?, .nothingDone?: true
        case .anotherShowing?, .replayOnly?, .dayFull?, .sessionFull?, .firstPaintingFull?, .tooSoon?: false
        }
    }

    private func run(
        _ candidates: [TipID], place: TipPlace, rest: Duration, quiet: @escaping @MainActor () -> TipPacing.Quiet
    ) async {
        let clock = ContinuousClock()
        let began = clock.now
        var chosen: TipID?
        var looks = 0
        while !Task.isCancelled {
            looks += 1
            // The rules read the tips-on parameter, which TipKit takes from here only once it has
            // loaded its datastore: say again what it should be until it does.
            let tipsOn = TipPreference.isEnabled(in: store.defaults)
            if TipSwitch.tipsOn != tipsOn { TipSwitch.tipsOn = tipsOn }
            var stillPending = false
            chosen = nil
            for id in candidates {
                switch id.progress {
                case .available: chosen = id
                case .pending: stillPending = true
                case .over: break
                }
                if chosen != nil { break }
            }
            if chosen != nil, clock.now - began >= Self.settle { break }
            if chosen == nil, !stillPending {
                notice("no tip of \(Self.names(candidates)) is eligible: \(Self.statuses(candidates))")
                return
            }
            let waited = clock.now - began
            if (waited >= Self.eligibilityWindow && Self.poll * looks >= Self.eligibilityWindow)
                || waited >= Self.eligibilityLimit { break }
            try? await Task.sleep(for: Self.poll)
        }
        guard let id = chosen, !Task.isCancelled else {
            notice("nothing was eligible in time: \(Self.statuses(candidates))")
            return
        }

        // The hand rests: nothing done for `rest`, however long it takes (within reason, counted
        // from here, so a long wait for TipKit leaves this its own).
        let resting = clock.now
        while clock.now - lastActivity < rest {
            guard !Task.isCancelled, clock.now - resting < Self.restWindow else {
                notice("\(id.rawValue) gave up waiting for the hand to rest")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled, turn == nil, isInView(place), !(place == .shelf && servedShelf) else {
            notice("\(id.rawValue) lost its place: cancelled \(Task.isCancelled), turn \(turn?.rawValue ?? "none"), views \(places.map(\.rawValue)), covered \(isCovered), served \(servedShelf)")
            return
        }
        guard case .available = id.progress else {
            notice("\(id.rawValue) is no longer available: \(Self.statuses([id]))")
            return
        }
        guard !Self.needsAnchor.contains(id) || anchored[id, default: 0] > 0 else {
            notice("\(id.rawValue) has no view to point at")
            return
        }
        if let refusal = pacing.refusal(for: id, quiet: quiet(), now: now()) {
            notice("\(id.rawValue) refused: \(String(describing: refusal))")
            return
        }
        grant(id)
    }

    private func grant(_ id: TipID) {
        pacing.show(id, now: now())
        store.save(pacing)
        if id.place == .shelf { servedShelf = true }
        turn = id
        notice("turn: \(id.rawValue)")
        watching?.cancel()
        watching = Task { [weak self] in await self?.watch(id) }
    }

    /// Follows the tip on screen: closed or used, it is over; left alone long enough, its turn lapses.
    private func watch(_ id: TipID) async {
        let clock = ContinuousClock()
        let began = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, turn == id else { return }
            let elapsed = clock.now - began
            switch id.progress {
            case .over(.closed), .over(.used):
                release(id)
                return
            case .over(.shownEnough):
                if elapsed > Self.shownEnough {
                    release(id)
                    return
                }
            case .available, .pending:
                break
            }
            if elapsed > Self.lapse {
                retire(id)
                return
            }
        }
    }

    private func notice(_ message: String) {
        Log.tips.notice("\(message, privacy: .public)")
    }

    private static func names(_ ids: [TipID]) -> String {
        ids.map(\.rawValue).joined(separator: ", ")
    }

    private static func statuses(_ ids: [TipID]) -> String {
        ids.map { "\($0.rawValue) \(String(describing: $0.tip.status))" }.joined(separator: ", ")
    }

    /// `id` leaves the screen, whatever the reason.
    private func release(_ id: TipID) {
        guard turn == id else { return }
        turn = nil
        notice("turn over: \(id.rawValue)")
        watching?.cancel()
        watching = nil
        pacing.hide(id)
        store.save(pacing)
    }

    /// `id` has had its say, read or not (left alone, or its screen went), and leaves the screen: a tip
    /// the app draws itself has no display limit of TipKit's to say it once.
    private func retire(_ id: TipID) {
        guard turn == id else { return }
        if id.isDrawnByTheApp || drawnBeside == id { id.tip.invalidate(reason: .displayCountExceeded) }
        release(id)
    }

    /// Its thing was used: the tip on screen, if it is this one, goes.
    func stop(_ id: TipID) {
        release(id)
    }

    /// Tips go off: the one on screen goes, and what was about to come.
    func stopAll() {
        stopOffering()
        if let turn { release(turn) }
    }

    #if DEBUG
    /// A `--tip-` demo (`DemoMode.forcedTip`), once its content is on screen: `id` is given its turn
    /// once TipKit finds it eligible, its screen is in view, nothing covers it and it has a view to point at, whatever the moment
    /// and the pacing, so that every tip can be seen where it lives.
    func force(_ id: TipID) {
        Task { [weak self] in
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(120)
            var readySince: ContinuousClock.Instant?
            while clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard turn == nil, isInView(id.place), !Self.needsAnchor.contains(id) || anchored[id, default: 0] > 0,
                      case .available = id.progress else {
                    readySince = nil
                    continue
                }
                // The screen has settled (a push or a sheet has landed) before the popover comes.
                if let readySince, clock.now - readySince >= Self.forcedSettle {
                    notice("forced: \(id.rawValue)")
                    grant(id)
                    return
                }
                if readySince == nil { readySince = clock.now }
            }
            self?.notice("forced \(id.rawValue) never came: \(Self.statuses([id]))")
        }
    }

    private static let forcedSettle: Duration = .seconds(1)
    #endif

    // MARK: The switch and starting over

    /// The Tips switch changed.
    func answered(tipsOn: Bool) {
        if tipsOn { history.tipsTurnedOn(at: now()) }
        store.save(history)
        answers += 1
        if !tipsOn { stopAll() }
    }

    /// Show Tips Again: every tip fresh, and the pacing as for a newcomer.
    func startOver() {
        stopAll()
        pacing = TipPacing()
        pacing.beginSession(now: now())
        history = TipHistory()
        history.tipsTurnedOn(at: now())
        store.reset()
        store.save(history)
        store.save(pacing)
        servedShelf = false
    }
}

/// Points the tip whose turn it is at the view it modifies, a popover on it. Every view takes its tip from `TipDesk.turn`, which gives one tip the turn
/// at a time. The popover is TipKit's, or where the tip's form is `TipForm.beside` (a compact
/// width, painting-company row 240) SwiftUI's own with the tip drawn by the app (`TipCard`):
/// smaller than its subject, beside it, on an opaque surface.
///
/// TipKit's `popoverTip` parses a Regex each time it is called, with a tip or nil (the type name
/// of its `AnyTip`, in TipKitCore's `String.init(type:)`; on a painting with every tip hidden, 25
/// parses in 24 calls, no tip made: `tools/tip_regex_count.py`), so a tip built once and kept
/// would save nothing; this modifier goes on as few views as can point instead: one per place on
/// a screen, never one per swatch (painting-company row 263). Its popover stays attached all the
/// while, presented by its binding turning true: one attached at the turn, its binding true
/// already, never came up. To point at part of a view, modify a view laid over that part: iOS
/// 27.2's `popoverTip` pointed at the whole palette bar handed `.rect(.rect(_:))` for its
/// `attachmentAnchor` (`PaletteBar.TipAnchors`).
private struct GentleTipModifier: ViewModifier {
    let ids: TipSet
    var active: Bool
    var arrowEdge: Edge?
    /// The one form this view points its tips in, where a tip has a place for each
    /// (`TipForm.popover`, `.beside`); nil points in either.
    var only: TipForm?
    /// The popover's side in the small form (`TipForm.beside`), where it differs from
    /// `arrowEdge`: the side that keeps the tip off a picture on a phone (nil: `arrowEdge`).
    var besideEdge: Edge?
    /// The small form at `TipForm.besideWideWidth`, for a tip whose room is short but wide.
    var wide = false
    /// The tip this view pointed last, which TipKit keeps being handed once its turn has gone.
    @State private var pointed: TipID?
    /// The tip this view drew last (`TipCard`), kept under its popover while that goes.
    @State private var drawn: TipID?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize

    func body(content: Content) -> some View {
        // Read here, in the body, so the popover follows the desk's turn. Presented by a binding
        // to it alone, which closing the popover (its ×, a tap outside) sets, ending the turn.
        // Once the view has pointed a tip, TipKit is never handed nil again, only the binding
        // false: iOS 27's TipKit left a presented popover up, its text and all, when its tip went to
        // nil (CI, November 4: Tap to Paint stayed over the swatch after the fill used it, whether
        // the popover was presented by the tip's status or by this binding).
        let turn = active ? PaintTips.desk.turn.flatMap { ids.contains($0) ? $0 : nil } : nil
        let form = turn.map {
            TipForm.of($0, isCompact: sizeClass == .compact, isAccessibilitySize: textSize.isAccessibilitySize)
        }
        let shown = only == nil || only == form ? turn : nil
        // TipKit's popover, or beside its subject the app's own (`TipForm.beside`): both stay
        // attached, so the view under them is one view whatever the width, and one is presented.
        let system = form == .beside ? nil : shown
        let own = form == .beside ? shown : nil
        let isPresented = Binding(get: { system != nil }, set: { if !$0, let system { PaintTips.closed(system) } })
        let ownIsPresented = Binding(get: { own != nil }, set: { if !$0, let own { PaintTips.closed(own) } })
        content
            .popoverTip((system ?? pointed)?.tip, isPresented: isPresented, arrowEdge: arrowEdge)
            // The optional edge goes through as it is (SwiftUI's `Edge?` popover): nil leaves the
            // side to the system here too, as it does TipKit's.
            .popover(isPresented: ownIsPresented, arrowEdge: besideEdge ?? arrowEdge) {
                TipCard(id: own ?? drawn, width: wide ? TipForm.besideWideWidth : TipForm.besideWidth) {
                    ownIsPresented.wrappedValue = false
                }
                .presentationCompactAdaptation(.popover)
            }
            // A tap outside the popover does what it was aimed at and closes the tip.
            .background {
                TipPassthrough(isShown: shown != nil) {
                    isPresented.wrappedValue = false
                    ownIsPresented.wrappedValue = false
                }
            }
            .onChange(of: system, initial: true) { _, now in
                if let now { pointed = now }
            }
            .onChange(of: own, initial: true) { _, now in
                guard let now else { return }
                drawn = now
                PaintTips.desk.drewBeside(now)
            }
            // While this view is on screen it can point its tips (`TipDesk.needsAnchor`).
            .modifier(TipAnchor(ids: ids, isPresent: active))
    }
}

/// A tip as the app draws it beside its subject (`TipForm.beside`; painting-company row 240): its
/// symbol, title and words as TipKit lays them, and a close button, no wider than
/// `TipForm.besideWidth`, on the card's opaque surface, so it reads over a picture in either
/// appearance. The content of a popover of SwiftUI's own; whoever presents it adds
/// `.presentationCompactAdaptation(.popover)` outside any condition, or a phone gets a sheet.
private struct TipCard: View {
    let id: TipID?
    var width: CGFloat = TipForm.besideWidth
    let close: () -> Void

    var body: some View {
        let tip = id?.tip
        HStack(alignment: .top, spacing: 12) {
            if let image = tip?.image {
                image
                    .font(.title)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let title = tip?.title {
                    title
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                }
                if let message = tip?.message {
                    message
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Close", systemImage: "xmark", action: close)
                .buttonStyle(TipCloseStyle())
        }
        .padding(14)
        .frame(minWidth: 220, idealWidth: width, maxWidth: width)
        .fixedSize(horizontal: false, vertical: true)
        .presentationBackground(Theme.surface)
    }
}

/// `TipCard`'s close button: a small round ×, as TipKit's is.
private struct TipCloseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.08), in: Circle())
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// A popover tip of whichever of `ids` has the turn, while `active` (of views that stand in
    /// for one another, like the preview's two places for the sliders, one is active). `arrowEdge` is the popover's side of
    /// the view it points at: `.top` hangs it below, `.bottom` above, `.trailing` beside; nil lets
    /// the system choose.
    /// `only` keeps the view to one of the tip's two forms, where its subject has a place for
    /// each (`TipForm.popover`, TipKit's; `.beside`, the app's small one on a compact width).
    /// `besideEdge` is the small one's side where it is not `arrowEdge`'s, and `wideBeside` draws
    /// it at `TipForm.besideWideWidth`: where the room off the picture is shorter than the narrow
    /// card is tall (painting-company row 240's critic: no tip over a picture on a phone).
    func gentleTip(
        _ ids: TipID..., active: Bool = true, arrowEdge: Edge? = nil, only: TipForm? = nil,
        besideEdge: Edge? = nil, wideBeside: Bool = false
    ) -> some View {
        modifier(GentleTipModifier(
            ids: TipSet(ids), active: active, arrowEdge: arrowEdge, only: only, besideEdge: besideEdge, wide: wideBeside))
    }
}

/// Hangs the tip whose turn it is, if it is one of `ids`, from a card on the shelf. TipKit's
/// popover tip found nothing to anchor to there (CI: the tips on its cards never came up while
/// every other popover tip did), so this is SwiftUI's own popover, which a card does carry, with
/// the tip's `TipView` inside, or on a compact width the small card every tip beside its subject
/// is (`TipCard`). A tap outside the popover closes the tip, as it does TipKit's own.
private struct OwnPopoverTipModifier: ViewModifier {
    let ids: TipSet
    var arrowEdge: Edge
    /// The popover's side in the small form (`TipForm.beside`), where it differs (nil: `arrowEdge`).
    var besideEdge: Edge?
    /// The tip this view drew last (`TipCard`), kept under its popover while that goes.
    @State private var drawn: TipID?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize

    func body(content: Content) -> some View {
        // Read here, in the body, so the popover follows the desk's turn.
        let shown = PaintTips.desk.turn.flatMap { ids.contains($0) ? $0 : nil }
        let isPresented = Binding(get: { shown != nil }, set: { if !$0, let shown { PaintTips.closed(shown) } })
        // On a compact width the small card every tip beside its subject is (`TipForm.beside`).
        let isBeside = (shown ?? drawn).map {
            TipForm.of($0, isCompact: sizeClass == .compact, isAccessibilitySize: textSize.isAccessibilitySize) == .beside
        } ?? false
        content
            .popover(isPresented: isPresented, arrowEdge: isBeside ? besideEdge ?? arrowEdge : arrowEdge) {
                // The adaptation is on the popover's content whatever the turn and the form: inside
                // a condition it never reached the presentation, and a phone got a sheet, blank but
                // for the tip (painting-company row 240).
                ZStack {
                    if isBeside {
                        TipCard(id: shown ?? drawn) { isPresented.wrappedValue = false }
                    } else {
                        TipView(shown?.tip, isPresented: nil, arrowEdge: nil)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 360)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: shown, initial: true) { _, now in
                if let now { drawn = now }
            }
    }
}

/// Tells the desk which of `ids` this view can point at now (`TipDesk.anchor`): while it is on
/// screen and `isPresent`. Its tips change as the screen does (another painting comes first), so it
/// takes back the ones it gave, not the ones it has now; and a screen pushed over it takes them all
/// back until it shows again.
private struct TipAnchor: ViewModifier {
    let ids: TipSet
    let isPresent: Bool
    @State private var isOnScreen = false
    @State private var anchored = TipSet([])

    func body(content: Content) -> some View {
        content
            .onAppear {
                isOnScreen = true
                anchor()
            }
            .onDisappear {
                isOnScreen = false
                anchor()
            }
            .onChange(of: ids) { anchor() }
            .onChange(of: isPresent) { anchor() }
    }

    private func anchor() {
        let now = isOnScreen && isPresent ? ids : TipSet([])
        guard now != anchored else { return }
        PaintTips.desk.anchor(anchored.ids, present: false)
        PaintTips.desk.anchor(now.ids, present: true)
        anchored = now
    }
}

/// A card's tips anchor while it is mostly in view: the grid builds cards beyond the screen's edge
/// too, and a tip would point off the screen.
private struct CardTipAnchor: ViewModifier {
    let ids: TipSet
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.6) { isVisible = $0 }
            .modifier(TipAnchor(ids: ids, isPresent: isVisible))
    }
}

/// Lays the tip whose turn it is, if it is one of `ids`, as a card with no arrow at the top of the
/// view it modifies, just under the navigation bar whose button it is about. A popover from the
/// button grew out of it on iOS 26 and covered it (on iPhone the title too), and nothing could
/// hang one below it (Paul, October 18: a card on the page, as the painting's Zoom, Drag and
/// Pencil are).
private struct BarTipModifier: ViewModifier {
    let ids: TipSet
    var active: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize

    func body(content: Content) -> some View {
        let shown = active ? PaintTips.desk.turn.flatMap { ids.contains($0) ? $0 : nil } : nil
        content.overlay(alignment: .top) {
            ZStack {
                if let shown {
                    card(shown)
                        .frame(maxWidth: Self.width)
                        .padding(.horizontal, Self.margin)
                        .padding(.top, Self.margin)
                        // Laid over the screen, it would come last to VoiceOver.
                        .accessibilitySortPriority(1)
                        .transition(.opacity)
                }
            }
            // A fade, on the card alone: the screen under it changes as it likes.
            .animation(.easeInOut(duration: 0.25), value: shown)
        }
        // While its button is in the bar: hidden, the tip waits for its turn (`TipDesk.needsAnchor`).
        .modifier(TipAnchor(ids: ids, isPresent: active))
    }

    /// The tip's card: in the screen's margin on a compact width (`TipForm.margin`), where it
    /// may reach a picture under it, on the card's opaque surface.
    @ViewBuilder
    private func card(_ id: TipID) -> some View {
        let tip = TipView(id.tip, isPresented: nil, arrowEdge: nil)
        if TipForm.of(id, isCompact: sizeClass == .compact, isAccessibilitySize: textSize.isAccessibilitySize) == .margin {
            tip.tipBackground(Theme.surface)
        } else {
            tip
        }
    }

    private static let width: CGFloat = 420
    private static let margin: CGFloat = 12
}

extension View {
    /// Whichever of `ids` has the turn, as a card at the top of this screen: the tips about a
    /// button of its navigation bar (`TipID.liesUnderTheBar`), while `active` (the button is there).
    func barTips(_ ids: TipID..., active: Bool = true) -> some View {
        modifier(BarTipModifier(ids: TipSet(ids), active: active))
    }

    /// Lets `ids`, the tips about buttons of this screen's navigation bar, have the turn while
    /// `active`, for a screen that lays their card among its own content (`GentleTipView`) instead:
    /// the gallery, atop its pages, while its button is in the bar and that top is in view.
    func barTipsInline(_ ids: TipID..., active: Bool = true) -> some View {
        modifier(TipAnchor(ids: TipSet(ids), isPresent: active))
    }

    /// Whichever of `ids` has the turn, as a popover from this card on the shelf, which anchors them
    /// while it is mostly in view; `besideEdge` is the popover's side in the small form
    /// (`TipForm.beside`) where it is not `arrowEdge`. The card anchors `drawnElsewhere` too, but
    /// draws none of them: the screen lays their card among its content (`GentleTipView`).
    func cardTip(
        _ ids: [TipID], arrowEdge: Edge = .top, besideEdge: Edge? = nil, drawnElsewhere: [TipID] = []
    ) -> some View {
        let drawn = TipSet(ids.filter { !drawnElsewhere.contains($0) })
        return modifier(OwnPopoverTipModifier(ids: drawn, arrowEdge: arrowEdge, besideEdge: besideEdge))
            .modifier(CardTipAnchor(ids: TipSet(ids)))
    }
}

/// A tip inline, where a popover has nothing to point at (Ready to Paint on the shelf, and the
/// gear's and the +'s atop it) or would cover a neighbour (Settings' on a phone, among its rows).
/// The caller shows it only while it is the tip's turn.
struct GentleTipView: View {
    let id: TipID

    var body: some View {
        TipView(PaintTips.desk.tip(among: TipSet([id])), isPresented: nil, arrowEdge: nil)
    }
}
