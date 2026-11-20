#if UNRELEASED
import Foundation
import Observation
import PaintCore
import simd

/// What painting together carries besides the fills (painting-company row 350; the design is
/// `factory/pieces/shareplay/` there): where the friend's hand is and the paint it holds, the
/// hand's ripples and stars, and who painted what, for the finale. One per painting session,
/// idle while the painter paints alone. The canvas reports the painter's own touches here and
/// shows the friend (`TogetherCanvas`); `TogetherEngine` sends and receives.
@MainActor @Observable
final class TogetherChannel {
    /// Someone is painting this painting with you.
    private(set) var isTogether = false
    /// The paint the friend holds, for the palette's glow; nil while they hold the hand or
    /// aren't here.
    private(set) var friendColor: Int?
    /// The painter holds the hand instead of a paint: a tap shows the friend a place, a hold
    /// sends a star, and nothing is painted. Picking a paint puts it down.
    var holdsHand = false {
        didSet { if holdsHand != oldValue { reportedColor = nil } }
    }

    /// Where the friend's light is shown.
    @ObservationIgnored weak var canvas: (any TogetherCanvas)?
    /// Hands a message to the friend (the engine's).
    @ObservationIgnored var send: ((TogetherMessage) -> Void)?
    /// The areas the friend painted, as the ledger has them, for the finale's two lights.
    @ObservationIgnored var friendsAreas: () -> Set<Int> = { [] }

    /// The colour a presence message gives the hand.
    nonisolated static let handColor = -1
    /// The colour a presence message gives nothing in hand (a finished color put down): not
    /// the hand, which is a choice to keep company.
    nonisolated static let noPaint = -2
    /// Presence goes out at most this often; the last point always does (`flushPresence`).
    static let presenceInterval: Duration = .milliseconds(50)

    @ObservationIgnored private var pendingPresence: (point: SIMD2<Float>?, color: Int)?
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var reportedColor: Int?
    /// Where the painter's finger last was on the page, for the origin of their fills.
    @ObservationIgnored private(set) var lastTouch: SIMD2<Float>?

    // MARK: The painter's side

    /// The painter's finger or Pencil is at `point` on the page (nil: lifted), holding `color`.
    func touched(_ point: SIMD2<Float>?, color: Int?) {
        if let point { lastTouch = point }
        guard isTogether else { return }
        let held = holdsHand ? Self.handColor : (color ?? Self.noPaint)
        pendingPresence = (point, held)
        reportedColor = held
        guard presenceTask == nil else { return }
        flushPresence()
        // Holds the gate while the finger keeps moving: each interval sends what came in it, and
        // the gate opens only after an interval with nothing to send.
        presenceTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: Self.presenceInterval)
                guard let self, !Task.isCancelled else { return }
                guard flushPresence() else { break }
            }
            self?.presenceTask = nil
        }
    }

    /// The painter picked a paint (or the hand): the friend's palette glows on it, finger or not.
    func held(_ color: Int?) {
        guard isTogether else { return }
        let held = holdsHand ? Self.handColor : (color ?? Self.noPaint)
        guard held != reportedColor else { return }
        reportedColor = held
        // A touch still waiting to go out carries the paint held before: it goes with this one.
        if let pending = pendingPresence {
            pendingPresence = (pending.point, held)
            return
        }
        send?(.presence(point: nil, color: Int32(held)))
    }

    /// Sends the presence waiting, if any; true when it sent one.
    @discardableResult
    private func flushPresence() -> Bool {
        guard let pending = pendingPresence else { return false }
        pendingPresence = nil
        send?(.presence(point: pending.point, color: Int32(pending.color)))
        return true
    }

    /// With the hand, a tap: a ripple at `point` on both screens.
    func ripple(at point: SIMD2<Float>) {
        canvas?.showRipple(at: point, fromFriend: false)
        if isTogether { send?(.ripple(point: point)) }
    }

    /// With the hand, a hold: a star drifts up from `point` into the sky, on both screens.
    func star(at point: SIMD2<Float>) {
        canvas?.showStar(from: point, fromFriend: false)
        if isTogether { send?(.star(point: point)) }
    }

    // MARK: The friend's side

    func friendArrived() {
        guard !isTogether else { return }
        isTogether = true
        canvas?.friendArrived()
    }

    /// The friend left, or (`quietly`) the painter left the painting themselves, which says
    /// nothing.
    func friendLeft(quietly: Bool = false) {
        guard isTogether else { return }
        let heldHand = holdsHand
        isTogether = false
        friendColor = nil
        holdsHand = false
        presenceTask?.cancel()
        presenceTask = nil
        pendingPresence = nil
        reportedColor = nil
        canvas?.friendLeft(heldHand: heldHand, quietly: quietly)
    }

    /// A presence message: the friend's finger at `point` (nil: lifted, or only a change of
    /// paint), holding `color`. A color the painting doesn't have is taken as the hand, but for
    /// `noPaint`.
    func friendMoved(to point: SIMD2<Float>?, color: Int, paletteCount: Int) {
        friendArrived()
        let held = (0..<paletteCount).contains(color) || color == Self.noPaint ? color : Self.handColor
        let paint: Int? = held < 0 ? nil : held
        if friendColor != paint { friendColor = paint }
        canvas?.friendMoved(to: point, color: held)
    }

    func friendRippled(at point: SIMD2<Float>) {
        friendArrived()
        canvas?.showRipple(at: point, fromFriend: true)
    }

    func friendStarred(at point: SIMD2<Float>) {
        friendArrived()
        canvas?.showStar(from: point, fromFriend: true)
    }
}

/// What the canvas shows of painting together.
@MainActor
protocol TogetherCanvas: AnyObject {
    func friendArrived()
    /// The friend went; `heldHand`: the painter was holding the hand, which goes with them.
    /// `quietly`: the painter is leaving the painting, so nothing is announced.
    func friendLeft(heldHand: Bool, quietly: Bool)
    /// The friend's light moves to `point` (nil: their finger lifted, and it rests where it was)
    /// in the paint `color` (`TogetherChannel.handColor`: the hand; `noPaint`: nothing in hand).
    func friendMoved(to point: SIMD2<Float>?, color: Int)
    func showRipple(at point: SIMD2<Float>, fromFriend: Bool)
    func showStar(from point: SIMD2<Float>, fromFriend: Bool)
}
#endif
