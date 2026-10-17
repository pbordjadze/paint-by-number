import Observation
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
/// - Granted, the tip has the turn until it is closed, used, or its screen goes (`finish`,
///   `leave`), and `turn` is the only tip any view points. One at a time follows.
/// - The invitation takes its turn the same way but is no hint: it counts for none of the limits.
///   Closing it counts as No Thanks.
///
/// A tip that TipKit shows for its own reasons would not be here: every view takes its tip from
/// `turn`, and the tips' rules carry the tips-on parameter besides.
@MainActor
@Observable
final class TipDesk {
    /// The tip whose turn it is: the only one a view may point.
    private(set) var turn: TipID?
    /// Counts the answers to the invitation and the Tips switch; a screen that offers on the
    /// answer (the shelf, after Show Tips) watches it.
    private(set) var answers = 0

    /// Tests and demos that show no tips: nothing is offered.
    @ObservationIgnored var isMuted = false
    /// A screen is over the shelf (the create flow, Settings, a sheet): its tips wait.
    @ObservationIgnored var isCovered = false

    @ObservationIgnored private var pacing: TipPacing
    @ObservationIgnored private var history: TipHistory
    @ObservationIgnored private let store: TipStore
    @ObservationIgnored private let now: () -> Date
    /// The moment being waited out, with the screen it belongs to: when that goes, so does it.
    @ObservationIgnored private var offering: (place: TipPlace, task: Task<Void, Never>)?
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The latest moment the painter did something (a fill, a slider, a screen): the hand has
    /// rested for as long as it was before now.
    @ObservationIgnored private var lastActivity = ContinuousClock.now
    @ObservationIgnored private var places: [TipPlace] = []
    /// The shelf has given a hint on this visit: one a visit, so each waits for a visit of its own.
    @ObservationIgnored private var servedShelf = false
    /// How many views that can point each of `needsAnchor` are on screen.
    @ObservationIgnored private var anchored: [TipID: Int] = [:]
    /// Tips that point at a view the shelf builds only when it is near the screen (a card in the
    /// grid): given a turn only while one is.
    private static let needsAnchor: Set<TipID> = [.shelfHold, .shelfTimeLapse]

    /// How long TipKit gets to find a tip eligible (a donation or a parameter just changed), and
    /// the least a moment waits before it takes the first one that is.
    private static let eligibilityWindow: Duration = .seconds(3)
    private static let settle: Duration = .milliseconds(350)
    /// The longest a moment waits for the hand to rest.
    private static let restWindow: Duration = .seconds(12)
    /// A tip that stays unanswered this long has had its say: its turn lapses.
    private static let lapse: Duration = .seconds(45)
    /// A tip TipKit has retired for being shown keeps its turn this long, which is time to read it.
    private static let shownEnough: Duration = .seconds(15)

    init(store: TipStore = TipStore(), now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
        pacing = store.pacing()
        history = store.history()
        pacing.beginSession(now: now())
    }

    // MARK: What a view asks

    /// The tip of the turn, if it is one of `ids`.
    func tip(among ids: [TipID]) -> (any Tip)? {
        guard let turn, ids.contains(turn) else { return nil }
        return turn.tip
    }

    // MARK: Where the painter is

    /// A screen appears. Going to another screen is something done.
    func enter(_ place: TipPlace) {
        places.removeAll { $0 == place }
        places.append(place)
        if place == .shelf { servedShelf = false }
        noteActivity()
    }

    /// A screen goes. Its tip goes with it, and its moments.
    func leave(_ place: TipPlace) {
        places.removeAll { $0 == place }
        if offering?.place == place { stopOffering() }
        if let turn, turn.place == place { release(turn) }
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
        if first, TipInvitation.isEnabled(in: store.defaults) {
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
        TipMoments.shelf(facts, answer: TipInvitation.answer(in: store.defaults), history: history, now: now())
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
        guard !isMuted, turn == nil else { return }
        if place == .shelf, servedShelf { return }
        // What the limits refuse for good has nothing to wait for; what is only quiet, or lacks
        // something done, may change while the moment waits.
        let wanted = candidates.filter { id in
            isWanted(id) && Self.mayChange(pacing.refusal(for: id, quiet: quiet(), now: now()))
        }
        guard !wanted.isEmpty else { return }
        stopOffering()
        offering = (place, Task { [weak self] in
            await self?.run(wanted, place: place, rest: rest, quiet: quiet)
        })
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

    /// Whether `id` may be offered at all: the invitation until it is answered, hints once tips are on.
    private func isWanted(_ id: TipID) -> Bool {
        let defaults = store.defaults
        return id == .invitation ? TipInvitation.answer(in: defaults) == .unanswered : TipInvitation.isEnabled(in: defaults)
    }

    private func run(
        _ candidates: [TipID], place: TipPlace, rest: Duration, quiet: @escaping @MainActor () -> TipPacing.Quiet
    ) async {
        let clock = ContinuousClock()
        let began = clock.now
        var chosen: TipID?
        while !Task.isCancelled {
            // The rules read the tips-on parameter, which TipKit takes from here only once it has
            // loaded its datastore: say again what it should be until it does.
            let tipsOn = TipInvitation.isEnabled(in: store.defaults)
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
            if chosen == nil, !stillPending { return }
            if clock.now - began >= Self.eligibilityWindow { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let id = chosen, !Task.isCancelled else { return }

        // The hand rests: nothing done for `rest`, however long it takes (within reason).
        while clock.now - lastActivity < rest {
            guard !Task.isCancelled, clock.now - began < Self.restWindow else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled, turn == nil, isInView(place), !(place == .shelf && servedShelf) else { return }
        guard case .available = id.progress else { return }
        guard !Self.needsAnchor.contains(id) || anchored[id, default: 0] > 0 else { return }
        guard pacing.refusal(for: id, quiet: quiet(), now: now()) == nil else { return }
        grant(id)
    }

    private func grant(_ id: TipID) {
        pacing.show(id, now: now())
        store.save(pacing)
        // The question is no hint: Show Tips leads at once to the page that waits.
        if id.place == .shelf, id.isHint { servedShelf = true }
        turn = id
        watching?.cancel()
        watching = Task { [weak self] in await self?.watch(id) }
    }

    /// Follows the tip on screen: closed or used, it is over; unanswered long enough, its turn lapses.
    private func watch(_ id: TipID) async {
        let clock = ContinuousClock()
        let began = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, turn == id else { return }
            let elapsed = clock.now - began
            switch id.progress {
            case .over(.closed):
                // A button of the invitation closes it too: its answer is given a moment later.
                if id == .invitation { try? await Task.sleep(for: .milliseconds(300)) }
                finish(id, closedByPainter: true)
                return
            case .over(.used):
                finish(id, closedByPainter: false)
                return
            case .over(.shownEnough):
                if elapsed > Self.shownEnough {
                    finish(id, closedByPainter: false)
                    return
                }
            case .available, .pending:
                break
            }
            if elapsed > Self.lapse {
                finish(id, closedByPainter: false)
                return
            }
        }
    }

    /// The tip is over. The invitation closed without an answer is No Thanks.
    private func finish(_ id: TipID, closedByPainter: Bool) {
        guard turn == id else { return }
        release(id)
        if id == .invitation, closedByPainter, TipInvitation.answer(in: store.defaults) == .unanswered {
            PaintTips.answerInvitation(showTips: false)
        }
    }

    /// `id` leaves the screen, whatever the reason.
    private func release(_ id: TipID) {
        guard turn == id else { return }
        turn = nil
        watching?.cancel()
        watching = nil
        pacing.hide(id)
        store.save(pacing)
    }

    /// Its thing was used (or its answer given): the tip on screen, if it is this one, goes.
    func stop(_ id: TipID) {
        release(id)
    }

    /// Tips go off: the one on screen goes, and what was about to come.
    func stopAll() {
        stopOffering()
        if let turn { release(turn) }
    }

    // MARK: Answers and starting over

    /// The answer to the invitation, or the Tips switch, changed.
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

/// Points the tip whose turn it is at the view it modifies, a popover on it. Every view takes its
/// tip from `TipDesk.turn`, which gives one tip the turn at a time.
private struct GentleTipModifier: ViewModifier {
    let ids: [TipID]
    var active: Bool
    var arrowEdge: Edge?

    func body(content: Content) -> some View {
        // `isPresented: nil` leaves it to TipKit to show and dismiss the popover by the tip's status
        // (and picks the one overload of `popoverTip` that takes an action).
        content.popoverTip(
            active ? PaintTips.desk.tip(among: ids) : nil, isPresented: nil, arrowEdge: arrowEdge,
            action: { PaintTips.perform($0) })
    }
}

extension View {
    /// A popover tip of whichever of `ids` has the turn, while `active` (a view that stands for
    /// others, like the selected swatch, is active for one). `arrowEdge` is the popover's side of
    /// the view it points at: `.top` hangs it below, `.bottom` above, `.trailing` beside; nil lets
    /// the system choose.
    func gentleTip(_ ids: [TipID], active: Bool = true, arrowEdge: Edge? = nil) -> some View {
        modifier(GentleTipModifier(ids: ids, active: active, arrowEdge: arrowEdge))
    }

    func gentleTip(_ ids: TipID..., active: Bool = true, arrowEdge: Edge? = nil) -> some View {
        gentleTip(ids, active: active, arrowEdge: arrowEdge)
    }
}

/// A tip inline, where a popover has nothing to point at (Ready to Paint on the shelf). The caller
/// shows it only while it is the tip's turn.
struct GentleTipView: View {
    let id: TipID

    var body: some View {
        TipView(PaintTips.desk.tip(among: [id]), isPresented: nil, arrowEdge: nil, action: { PaintTips.perform($0) })
    }
}
