import CoreGraphics
import Foundation
import Observation

/// The hand-off from Start Painting to the painting, so that the journey from the create flow's
/// settings to the canvas is one picture moving once (`StartHandoffPlan`).
///
/// `AppShellView` owns one and passes it through the environment (`\.startHandoff`) to the create
/// flow's cover and, through the navigation stack, to the painting. The sequence:
///
/// 1. Start has saved the painting, and the create flow's picture has moved to where the
///    painting's page will be (`PaintingLayout.page`; the making-of show, with Settings › The
///    Making-of on, plays there): the shell `begin`s the hand-off and pushes the painting *under*
///    the cover (its zoom runs unseen). The cover stays up and shows what it showed.
/// 2. The painting loads, and once its canvas has its first frame on screen it reports where its
///    page is, in the window's coordinates (`paintingDrew`: `PaintView.reportTemplate`), and again
///    should a layout move it (a rotation).
/// 3. The create flow, which observes `phase`, waits for the show to be over, its picture having
///    become the page as the canvas draws it (`HandoffPage`), then fades its paper away around the
///    picture, which stays where it is over the canvas's same page, and `complete`s.
/// 4. The shell takes the cover away without a slide (`isFinished`) and `reset`s; the canvas
///    eases in the color to paint (`CanvasController.revealSelection`).
///
/// A painting that has not drawn within `StartHandoffPlan.fallback` (a slow open, an error that
/// shows the recovery screen) `timeOut`s: the cover fades out alone and the painting stays pushed.
/// `StartHandoffLogic` holds the rules without the timer, for the tests.
@Observable
final class StartHandoff {
    private(set) var logic = StartHandoffLogic()
    private let timeout: Duration
    @ObservationIgnored private var fallback: Task<Void, Never>?

    init(timeout: Duration = StartHandoffPlan.fallback) {
        self.timeout = timeout
    }

    var phase: StartHandoffLogic.Phase { logic.phase }
    /// A hand-off is under way or waiting to be taken in: the cover is up for it.
    var isRunning: Bool { logic.isRunning }
    /// The create flow is done with its dissolve: the shell takes the cover away.
    var isFinished: Bool { logic.isFinished }

    func isOpening(_ id: UUID) -> Bool { logic.isOpening(id) }

    /// Start has saved the painting `id`. True when the shell is to push it now; false when a
    /// hand-off is already under way, so a second Start does not push it twice.
    func begin(_ id: UUID) -> Bool {
        guard logic.begin(id) else { return false }
        fallback = Task { [weak self, timeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.timeOut()
        }
        return true
    }

    /// The painting `id` has its first frame on screen, its template at `templateRect` (global
    /// coordinates), or a layout has moved the template since. Ignored unless that painting is the
    /// one being opened, and once the flow has dissolved.
    func paintingDrew(_ id: UUID, templateRect: CGRect) {
        guard logic.paintingDrew(id, templateRect: templateRect) else { return }
        fallback?.cancel()
        fallback = nil
    }

    /// The create flow has dissolved into the painting (or faded out of its way).
    func complete() {
        logic.complete()
    }

    /// The cover is gone, or a new flow replaced the one handing over.
    func reset() {
        fallback?.cancel()
        fallback = nil
        logic.reset()
    }

    private func timeOut() {
        fallback = nil
        logic.timeOut()
    }
}

/// The rules of `StartHandoff`, without its timer.
nonisolated struct StartHandoffLogic: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        case idle
        /// The painting is pushed under the cover and has not drawn yet.
        case opening(UUID)
        /// The painting drew its first frame, its template at the rect (global coordinates).
        case ready(UUID, CGRect)
        /// It did not draw in time: the cover goes alone.
        case timedOut(UUID)
        /// The create flow has dissolved; the cover can go.
        case finished(UUID)
    }

    private(set) var phase = Phase.idle

    var isRunning: Bool { phase != .idle }

    var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    func isOpening(_ id: UUID) -> Bool {
        if case .opening(let current) = phase { return current == id }
        return false
    }

    /// Whether this call began a hand-off: only one runs at a time.
    mutating func begin(_ id: UUID) -> Bool {
        guard phase == .idle else { return false }
        phase = .opening(id)
        return true
    }

    /// Accepted from the painting being opened, and again, with a new rect, while the flow is on
    /// its way (a layout moved the template); a report after the timeout or the flow's end, from
    /// another painting or before any hand-off is ignored.
    @discardableResult
    mutating func paintingDrew(_ id: UUID, templateRect: CGRect) -> Bool {
        switch phase {
        case .opening(let current) where current == id:
            phase = .ready(id, templateRect)
            return true
        case .ready(let current, let rect) where current == id && rect != templateRect:
            phase = .ready(id, templateRect)
            return true
        default:
            return false
        }
    }

    @discardableResult
    mutating func timeOut() -> Bool {
        guard case .opening(let id) = phase else { return false }
        phase = .timedOut(id)
        return true
    }

    /// From a painting that drew, or one that timed out.
    @discardableResult
    mutating func complete() -> Bool {
        switch phase {
        case .ready(let id, _), .timedOut(let id):
            phase = .finished(id)
            return true
        case .idle, .opening, .finished:
            return false
        }
    }

    mutating func reset() {
        phase = .idle
    }

    /// The painting is pushed once: not again if it is on the stack already.
    static func shouldPush(_ id: UUID, onto path: [UUID]) -> Bool {
        !path.contains(id)
    }
}

/// How the hand-off moves and for how long: one move, then still. On Start the create flow's
/// controls fade around the picture (`clear`), the status bar goes (the painting has none), and the
/// picture moves once (`glide`) to where the painting's page will be (`PaintingLayout.page`); the
/// making-of show, when it plays, plays there. The painting opens beneath; once the canvas has
/// drawn, the picture, by then the page as the canvas draws it (`HandoffPage`; the show's last
/// picture `settle`s into it), stays where it is while the paper fades away around it (`reveal`),
/// and the canvas beneath shows the same. Reduce Motion moves nothing: the picture fades in at the
/// page's place instead.
nonisolated enum StartHandoffPlan {
    /// Where the picture starts, `from` being where the preview's picture was (window
    /// coordinates); nil: it fades in at its place.
    static func entry(reduceMotion: Bool, from: CGRect?) -> CGRect? {
        guard !reduceMotion, let from, from.isPlace else { return nil }
        return from
    }

    /// Where the picture moves before the paper fades, should the canvas have put the page
    /// elsewhere than `expected` (`matches`): nil when it is where expected, or under Reduce
    /// Motion (the picture fades out instead).
    static func correction(expected: CGRect, reported: CGRect, reduceMotion: Bool) -> CGRect? {
        guard reported.isPlace, !matches(expected, reported), !reduceMotion else { return nil }
        return reported
    }

    /// Whether two places of the page are the same to the eye: no edge more than a point apart
    /// (the canvas's scroll view rounds its camera to the screen).
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        guard a.isPlace, b.isPlace else { return false }
        return max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.maxX - b.maxX), abs(a.maxY - b.maxY)) <= 1
    }

    /// The flow's controls fade around the picture, which fades in over them (the show's photo,
    /// or the preview's picture whole), before it moves.
    static var clear: Double { 0.25 * timeScale }
    /// The one move: smooth, with no bounce.
    static var glide: Double { 0.5 * timeScale }
    /// How long the status bar's going may take to reach the layout (an iPad's safe area changes).
    static let statusBarSettles = Duration.milliseconds(100)
    /// The show's last picture, or the preview's, becomes the page as the canvas draws it.
    static var settle: Double { 0.5 * timeScale }
    /// The paper and the show's card fade to the painting beneath.
    static var reveal: Double { 0.35 * timeScale }
    /// A correction (`correction`).
    static var correct: Double { 0.35 * timeScale }
    /// How long the painting has to draw its first frame before the cover leaves alone.
    static var fallback: Duration {
        #if DEBUG
        let seconds = UserDefaults.standard.double(forKey: "handoffFallback")
        if seconds > 0 { return .milliseconds(Int(seconds * 1000)) }
        #endif
        return .milliseconds(Int(2500 * timeScale))
    }

    /// Debug launches can slow every duration down (`-handoffSlowdown 4`) so that a burst of
    /// screenshots catches the motion, and set how long the painting has (`-handoffFallback 20`,
    /// in seconds: CI's simulators take several to open one).
    private static var timeScale: Double {
        #if DEBUG
        let scale = UserDefaults.standard.double(forKey: "handoffSlowdown")
        return scale >= 1 ? min(scale, 10) : 1
        #else
        return 1
        #endif
    }
}

extension CGRect {
    /// A rectangle a picture can be put in: finite and at least a point each way.
    nonisolated var isPlace: Bool {
        guard !isNull, !isInfinite, origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite
        else { return false }
        return size.width >= 1 && size.height >= 1
    }
}

/// Carrying a view that fills its container, with a picture drawn at `home` in it, so the picture
/// sits at `destination`: a scale about the container's top-leading corner, then an offset. The
/// picture's width sets the scale and the two centers meet, so a rounding difference in aspect
/// splits between top and bottom.
nonisolated struct PictureTravel: Equatable, Sendable {
    var scale: CGFloat
    var dx: CGFloat
    var dy: CGFloat

    static let none = PictureTravel(scale: 1, dx: 0, dy: 0)

    init(scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        self.scale = scale
        self.dx = dx
        self.dy = dy
    }

    /// No travel for a missing or unusable destination (or home).
    init(home: CGRect, destination: CGRect?) {
        guard let destination, destination.isPlace, home.isPlace else {
            self = .none
            return
        }
        let scale = destination.width / home.width
        self.init(scale: scale, dx: destination.midX - home.midX * scale, dy: destination.midY - home.midY * scale)
    }

    /// Where `rect` of the container ends up.
    func applied(to rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * scale + dx, y: rect.minY * scale + dy, width: rect.width * scale, height: rect.height * scale)
    }
}
