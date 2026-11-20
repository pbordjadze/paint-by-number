import Foundation
import PaintCore
import simd

/// Paint Together's two-way sync for one painting session (painting-company row 350): the
/// painter's fills and take-backs go out as `TogetherOp`s, batched so a fast drag sends a
/// message every 50 ms rather than one per area, and the friend's come in and are painted
/// through `PaintingSession.applyFriend`, which none of the single painter's rules answer. Your
/// own taps never wait: the session paints first, and only what the friend sees waits for the
/// network. Who painted an area last wins, by the ledger's stamps, so both devices land on the
/// same painting whatever order the messages arrive in.
///
/// It knows nothing of SharePlay: `send` takes the bytes (`TogetherLink` hands them to a group
/// session's messenger; the tests, to another engine).
@MainActor
final class TogetherEngine {
    let painter: UInt64
    private(set) var ledger: TogetherLedger
    private weak var session: PaintingSession?
    private let send: (Data) -> Void
    private var batcher = TogetherBatcher()
    private var flushing: Task<Void, Never>?
    private let started = ContinuousClock.now
    private let regionCount: Int
    /// Whether this painter started the session: the areas painted before it began are theirs.
    private let isHost: Bool

    /// `ledger` is the one this painting had earlier in the session (closed and opened again),
    /// so its stamps go on from where they were and the painter's fills don't lose to older ones.
    init(
        session: PaintingSession, painter: UInt64, ledger: TogetherLedger? = nil, isHost: Bool = true,
        send: @escaping (Data) -> Void
    ) {
        self.painter = painter
        self.session = session
        self.send = send
        self.isHost = isHost
        regionCount = session.progress.regionCount
        let painted = (0..<session.progress.regionCount).map(session.isPainted)
        if var kept = ledger, kept.regionCount == painted.count, kept.painter == painter {
            // What changed while it was closed (nothing should) goes in as this painter's own.
            let differs = painted.indices.filter { painted[$0] != kept.isPainted($0) }
            _ = kept.paint(differs.filter { painted[$0] })
            for r in differs where !painted[r] { _ = kept.unpaint(r) }
            self.ledger = kept
        } else {
            self.ledger = TogetherLedger(seeding: painted, painter: painter)
        }
        session.onEvent { [weak self] event in self?.observe(event) }
        #if UNRELEASED
        let channel = session.together
        channel.send = { [weak self] message in self?.send(message.encoded()) }
        channel.friendsAreas = { [weak self] in self?.friendsAreas ?? [] }
        #endif
    }

    /// The areas the friend painted: stamped by them, or painted before the session began on the
    /// host's side (`TogetherStamp.seed`) when the friend is the host.
    var friendsAreas: Set<Int> {
        Set((0..<regionCount).filter { region in
            guard let by = ledger.paintedBy(region) else { return false }
            return by == TogetherStamp.seed.painter ? !isHost : by != painter
        })
    }

    /// Says hello: whoever is already there answers with everything painted.
    func start() {
        send(TogetherMessage.hello(painter: painter, version: 1).encoded())
    }

    /// Everything painted, for someone who just arrived.
    func sendSnapshot() {
        flush()
        for message in TogetherMessage.chunkedSnapshot(ledger.snapshot()) { send(message.encoded()) }
    }

    func receive(_ data: Data) {
        guard let message = try? TogetherMessage(decoding: data, maxRegionCount: regionCount) else { return }
        switch message {
        case .hello:
            sendSnapshot()
            arrived()
        case let .ops(ops, origin):
            apply(ops, origin: origin)
            arrived()
        case let .snapshot(ops):
            apply(ops, origin: nil)
            arrived()
        #if UNRELEASED
        case let .presence(point, color):
            guard let session else { return }
            session.together.friendMoved(to: point, color: Int(color), paletteCount: session.paletteCount)
        case let .ripple(point):
            session?.together.friendRippled(at: point)
        case let .star(point):
            session?.together.friendStarred(at: point)
        #endif
        default:
            // The shared finish is each side's own (both see the last area painted), and a newer
            // peer's kinds are skipped.
            break
        }
    }

    /// The friend is here: whatever they sent says so.
    private func arrived() {
        #if UNRELEASED
        session?.together.friendArrived()
        #endif
    }

    /// No one else is in the session any more.
    func friendLeft() {
        #if UNRELEASED
        session?.together.friendLeft()
        #endif
    }

    func stop() {
        flushing?.cancel()
        flushing = nil
        flush()
        friendLeft()
        #if UNRELEASED
        session?.together.send = nil
        #endif
    }

    private var now: Double {
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }

    private func observe(_ event: PaintEvent) {
        guard let session, !session.isApplyingFriend else { return }
        switch event {
        case let .painted(regions, _):
            queue(ledger.paint(regions))
        case let .undone(region):
            if let op = ledger.unpaint(region) { queue([op]) }
        default:
            break
        }
    }

    private func queue(_ ops: [TogetherOp]) {
        guard !ops.isEmpty else { return }
        batcher.add(ops, at: now)
        guard flushing == nil else { return }
        flushing = Task { [weak self] in
            try? await Task.sleep(for: TogetherEngine.batch)
            guard let self, !Task.isCancelled else { return }
            self.flushing = nil
            self.flush()
        }
    }

    /// A drag's fills go out together every this long: fewer messages, and the friend's canvas
    /// draws a handful of areas at a time instead of one per frame.
    static let batch: Duration = .milliseconds(50)

    private func flush() {
        let ops = batcher.flush(at: now, force: true)
        guard !ops.isEmpty else { return }
        for message in TogetherMessage.chunked(ops, origin: origin) { send(message.encoded()) }
    }

    /// Where the friend's copy of these fills spreads from: the painter's finger.
    private var origin: SIMD2<Float>? {
        #if UNRELEASED
        session?.together.lastTouch
        #else
        nil
        #endif
    }

    private func apply(_ ops: [TogetherOp], origin: SIMD2<Float>?) {
        guard let session else { return }
        let changed = ledger.apply(ops)
        guard !changed.painted.isEmpty || !changed.unpainted.isEmpty else { return }
        let from = origin ?? changed.painted.first.flatMap { session.template.labels(ofRegion: $0).first?.position } ?? .zero
        session.applyFriend(painted: changed.painted, unpainted: changed.unpainted, from: from)
    }
}
