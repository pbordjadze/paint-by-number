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

    /// `ledger` is the one this painting had earlier in the session (closed and opened again),
    /// so its stamps go on from where they were and the painter's fills don't lose to older ones.
    init(session: PaintingSession, painter: UInt64, ledger: TogetherLedger? = nil, send: @escaping (Data) -> Void) {
        self.painter = painter
        self.session = session
        self.send = send
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
        case let .ops(ops, origin):
            apply(ops, origin: origin)
        case let .snapshot(ops):
            apply(ops, origin: nil)
        default:
            // Presence, ripples, stars and the shared finish come with the next build.
            break
        }
    }

    func stop() {
        flushing?.cancel()
        flushing = nil
        flush()
    }

    private var now: Double {
        let elapsed = ContinuousClock.now - started
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }

    private func observe(_ event: PaintEvent) {
        guard let session, !session.isApplyingFriend else { return }
        switch event {
        case let .painted(regions, _):
            #if DEBUG
            TourLog.trace("together", "paint\tareas=%@", TogetherEngine.list(regions))
            #endif
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
        #if DEBUG
        TourLog.trace("together", "send\tops=%ld", ops.count)
        #endif
        for message in TogetherMessage.chunked(ops, origin: nil) { send(message.encoded()) }
    }

    #if DEBUG
    /// Areas as the tour log writes them (`tools/together-e2e/summary.py` matches one device's
    /// `paint` with the other's `receive` by them).
    private static func list(_ regions: [Int]) -> String {
        regions.map(String.init).joined(separator: ",")
    }
    #endif

    private func apply(_ ops: [TogetherOp], origin: SIMD2<Float>?) {
        guard let session else { return }
        let changed = ledger.apply(ops)
        guard !changed.painted.isEmpty || !changed.unpainted.isEmpty else { return }
        #if DEBUG
        TourLog.trace("together", "receive\tareas=%@\tunpainted=%ld", TogetherEngine.list(changed.painted), changed.unpainted.count)
        #endif
        let from = origin ?? changed.painted.first.flatMap { session.template.labels(ofRegion: $0).first?.position } ?? .zero
        session.applyFriend(painted: changed.painted, unpainted: changed.unpainted, from: from)
    }
}
