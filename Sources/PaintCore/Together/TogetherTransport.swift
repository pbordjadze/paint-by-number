import Foundation

/// Carries encoded `TogetherMessage`s to the other painters (the app's SharePlay messenger).
/// Reliable messages arrive, perhaps late; unreliable ones (presence, ripples) may not.
public protocol TogetherTransport: Sendable {
    func send(_ message: Data, reliable: Bool) async throws
}

/// Two endpoints in one process, for tests: what one sends waits in the other's inbox until it
/// calls `receive`. Scrambled, a delivery comes out shuffled, some messages twice and some
/// unreliable ones lost, from a seeded `SplitMix64`, so a run is repeatable.
public actor LoopbackHub {
    public enum Mode: Sendable {
        case inOrder
        case scrambled(seed: UInt64)
    }

    public struct Endpoint: TogetherTransport {
        public let hub: LoopbackHub
        public let side: Int

        public func send(_ message: Data, reliable: Bool) async throws {
            await hub.post(message, reliable: reliable, from: side)
        }

        /// Everything sent to this side since the last call.
        public func receive() async -> [Data] {
            await hub.drain(side)
        }
    }

    private var inboxes: [[(data: Data, reliable: Bool)]] = [[], []]
    private var rng: SplitMix64?

    public init(mode: Mode = .inOrder) {
        if case .scrambled(let seed) = mode { rng = SplitMix64(seed: seed) }
    }

    public nonisolated var endpoints: (Endpoint, Endpoint) {
        (Endpoint(hub: self, side: 0), Endpoint(hub: self, side: 1))
    }

    func post(_ message: Data, reliable: Bool, from side: Int) {
        inboxes[1 - side].append((message, reliable))
    }

    func drain(_ side: Int) -> [Data] {
        let inbox = inboxes[side]
        inboxes[side] = []
        guard var random = rng else { return inbox.map(\.data) }
        var out: [Data] = []
        for message in inbox {
            let roll = random.next() % 4
            if roll == 0 && !message.reliable { continue }
            out.append(message.data)
            if roll == 1 { out.append(message.data) }
        }
        // Fisher-Yates by hand: the standard library's shuffle may change between releases.
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            out.swapAt(i, Int(random.next() % UInt64(i + 1)))
        }
        rng = random
        return out
    }
}
