import Foundation
import Testing
@testable import PaintCore

/// Paint Together's core: the ledger two painters converge on, its wire format read as hostile
/// input, the batcher, and two ledgers painting through the loopback hub.
@Suite("Paint Together")
struct TogetherTests {

    private static func shuffled<T>(_ items: [T], _ rng: inout SplitMix64) -> [T] {
        var out = items
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            out.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        return out
    }

    private static func state(_ ledger: TogetherLedger) -> [Bool] {
        (0..<ledger.regionCount).map(ledger.isPainted)
    }

    // MARK: Ledger

    @Test func paintSkipsPaintedAndBumpsClock() {
        var ledger = TogetherLedger(regionCount: 5, painter: 7)
        let first = ledger.paint([1, 2, 2, 9, -1])
        #expect(first.map(\.region) == [1, 2])
        #expect(first.allSatisfy { $0.painted && $0.stamp == TogetherStamp(clock: 1, painter: 7) })
        let second = ledger.paint([1, 3])
        #expect(second.map(\.region) == [3])
        #expect(ledger.clock == 2)
        let repeated = ledger.paint([1])
        #expect(repeated.isEmpty)
        #expect(ledger.clock == 2)
        #expect(ledger.paintedBy(1) == 7)
        #expect(ledger.paintedBy(0) == nil)
    }

    @Test func unpaintClearsOnlyPainted() throws {
        var ledger = TogetherLedger(regionCount: 3, painter: 1)
        let unpainted = ledger.unpaint(0)
        #expect(unpainted == nil)
        _ = ledger.paint([0])
        let clear = ledger.unpaint(0)
        let op = try #require(clear)
        #expect(!op.painted && op.stamp.clock == 2)
        #expect(!ledger.isPainted(0))
        #expect(ledger.paintedBy(0) == nil)
        let outside = ledger.unpaint(7)
        #expect(outside == nil)
    }

    @Test func applyReportsChangesAndAdvancesClock() {
        var ledger = TogetherLedger(regionCount: 4, painter: 1)
        let ops = [
            TogetherOp(region: 0, painted: true, stamp: .init(clock: 5, painter: 2)),
            TogetherOp(region: 1, painted: true, stamp: .init(clock: 6, painter: 2)),
            TogetherOp(region: 1, painted: false, stamp: .init(clock: 7, painter: 2)),
            TogetherOp(region: 99, painted: true, stamp: .init(clock: 50, painter: 2)),
        ]
        let changes = ledger.apply(ops)
        #expect(changes.painted == [0])
        #expect(changes.unpainted.isEmpty)  // region 1 ended where it started
        #expect(ledger.clock == 7)  // the out-of-range op is ignored whole
        // An older op loses.
        let stale = ledger.apply([TogetherOp(region: 0, painted: false, stamp: .init(clock: 4, painter: 9))])
        #expect(stale.unpainted.isEmpty && ledger.isPainted(0))
        // The next local op is newer than anything seen.
        let next = ledger.paint([2])
        #expect(next.first?.stamp.clock == 8)
    }

    @Test func seedingLosesToAnyRealOp() {
        var ledger = TogetherLedger(seeding: [true, false, true], painter: 3)
        #expect(ledger.isPainted(0) && !ledger.isPainted(1) && ledger.isPainted(2))
        #expect(ledger.paintedBy(0) == 0)
        let changes = ledger.apply([TogetherOp(region: 2, painted: false, stamp: .init(clock: 1, painter: 1))])
        #expect(changes.unpainted == [2])
        #expect(ledger.snapshot().count == 2)
    }

    /// Two painters' ops, applied in any order and any number of times, give one state.
    @Test(arguments: [UInt64(1), 2, 3, 42, 1234])
    func convergesUnderShuffleAndDuplicates(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let regions = 40
        var a = TogetherLedger(regionCount: regions, painter: 11)
        var b = TogetherLedger(regionCount: regions, painter: 22)
        var all: [TogetherOp] = []
        for step in 0..<300 {
            let region = Int(rng.next() % UInt64(regions))
            let undo = rng.next() % 3 == 0
            let sync = rng.next() % 5 == 0
            if step % 2 == 0 {
                all += undo ? [a.unpaint(region)].compactMap { $0 } : a.paint([region])
            } else {
                all += undo ? [b.unpaint(region)].compactMap { $0 } : b.paint([region])
            }
            if sync {  // a peer sometimes hears the other mid-session, so clocks interleave
                a.apply(all)
                b.apply(all)
            }
        }
        var duplicated = all
        for _ in 0..<all.count / 2 { duplicated.append(all[Int(rng.next() % UInt64(all.count))]) }
        var results: [[TogetherOp]] = []
        for trial in 0..<4 {
            var fresh = TogetherLedger(regionCount: regions, painter: UInt64(100 + trial))
            fresh.apply(Self.shuffled(duplicated, &rng))
            results.append(fresh.snapshot())
        }
        a.apply(Self.shuffled(all, &rng))
        b.apply(Self.shuffled(all, &rng))
        #expect(a.snapshot() == b.snapshot())
        #expect(results.allSatisfy { $0 == a.snapshot() })
    }

    @Test func concurrentPaintAndUnpaintOfOneAreaConverge() {
        var a = TogetherLedger(regionCount: 2, painter: 1)
        var b = TogetherLedger(regionCount: 2, painter: 2)
        let painted = a.paint([0])
        b.apply(painted)
        // At once: b clears it while a clears it and paints it again.
        let clear = b.unpaint(0)!
        let undo = a.unpaint(0)!
        let repaint = a.paint([0])
        #expect(clear.stamp.clock == undo.stamp.clock)  // concurrent: same clock, painter breaks it
        a.apply([clear])
        b.apply([undo] + repaint)
        #expect(a.snapshot() == b.snapshot())
        #expect(a.isPainted(0) == b.isPainted(0))
        #expect(a.isPainted(0))  // a's repaint came after both clears
    }

    @Test func lateJoinerCatchesUpFromSnapshot() throws {
        var a = TogetherLedger(seeding: [true, false, false, false, true, false], painter: 5)
        _ = a.paint([1, 2])
        _ = a.unpaint(4)
        let encoded = TogetherMessage.chunkedSnapshot(a.snapshot()).map { $0.encoded() }
        var joiner = TogetherLedger(regionCount: 6, painter: 6)
        for data in encoded {
            guard case .snapshot(let ops) = try TogetherMessage(decoding: data, maxRegionCount: 6) else {
                Issue.record("not a snapshot")
                return
            }
            joiner.apply(ops)
        }
        #expect(Self.state(joiner) == Self.state(a))
        #expect(joiner.snapshot() == a.snapshot())
        let next = joiner.paint([3])
        #expect(next.first?.stamp.clock == a.clock + 1)
    }

    // MARK: Wire format

    private static let samples: [TogetherMessage] = [
        .hello(painter: 0xDEAD_BEEF_0123_4567, version: 3),
        .ops(
            [
                TogetherOp(region: 0, painted: true, stamp: .init(clock: 1, painter: 2)),
                TogetherOp(region: 99, painted: false, stamp: .init(clock: .max, painter: .max)),
            ], origin: SIMD2(12.5, -3)),
        .ops([TogetherOp(region: 4, painted: true, stamp: .init(clock: 9, painter: 8))], origin: nil),
        .ops([], origin: nil),
        .snapshot([TogetherOp(region: 7, painted: true, stamp: .init(clock: 3, painter: 4))]),
        .snapshot([]),
        .presence(point: SIMD2(100, 200.25), color: 4),
        .presence(point: nil, color: -1),
        .ripple(point: SIMD2(1, 2)),
        .star(point: SIMD2(-0.5, 1e6)),
        .finish(atClock: 77),
    ]

    @Test func roundTripsEveryCase() throws {
        for message in Self.samples {
            let data = message.encoded()
            #expect(data.prefix(3) == Data([0x50, 0x54, 1]))
            #expect(try TogetherMessage(decoding: data, maxRegionCount: 100) == message)
        }
    }

    @Test func everyTruncationThrows() {
        for message in Self.samples {
            let data = message.encoded()
            for length in 0..<data.count {
                #expect(throws: TogetherMessage.DecodingError.self) {
                    try TogetherMessage(decoding: data.prefix(length), maxRegionCount: 100)
                }
            }
            #expect(throws: TogetherMessage.DecodingError.trailingBytes) {
                try TogetherMessage(decoding: data + [0], maxRegionCount: 100)
            }
        }
    }

    @Test func randomCorruptionNeverTraps() {
        var rng = SplitMix64(seed: 0x70_6765)
        for message in Self.samples {
            let data = [UInt8](message.encoded())
            for _ in 0..<400 {
                var bytes = data
                for _ in 0..<(1 + Int(rng.next() % 4)) {
                    bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next())
                }
                if let decoded = try? TogetherMessage(decoding: Data(bytes), maxRegionCount: 100),
                    case .ops(let ops, _) = decoded
                {
                    #expect(ops.allSatisfy { $0.region < 100 })
                }
            }
        }
        for _ in 0..<2000 {
            let bytes = (0..<Int(rng.next() % 64)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            _ = try? TogetherMessage(decoding: Data(bytes), maxRegionCount: 100)
        }
    }

    @Test func rejectsHostileFields() {
        let op = TogetherOp(region: 50, painted: true, stamp: .init(clock: 1, painter: 1))
        #expect(throws: TogetherMessage.DecodingError.regionOutOfRange) {
            try TogetherMessage(decoding: TogetherMessage.ops([op], origin: nil).encoded(), maxRegionCount: 50)
        }
        #expect(throws: TogetherMessage.DecodingError.regionOutOfRange) {
            try TogetherMessage(decoding: TogetherMessage.snapshot([op]).encoded(), maxRegionCount: 0)
        }
        #expect(throws: TogetherMessage.DecodingError.nonFinite) {
            try TogetherMessage(decoding: TogetherMessage.ripple(point: SIMD2(.nan, 0)).encoded(), maxRegionCount: 1)
        }
        #expect(throws: TogetherMessage.DecodingError.nonFinite) {
            try TogetherMessage(
                decoding: TogetherMessage.presence(point: SIMD2(0, .infinity), color: 0).encoded(), maxRegionCount: 1)
        }
        #expect(throws: TogetherMessage.DecodingError.malformed) {
            try TogetherMessage(decoding: TogetherMessage.presence(point: nil, color: -2).encoded(), maxRegionCount: 1)
        }
        // A count promising more ops than the bytes hold, or more than a message may carry.
        var huge = [UInt8](TogetherMessage.snapshot([]).encoded())
        huge.replaceSubrange(4..<8, with: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: TogetherMessage.DecodingError.tooManyOps) {
            try TogetherMessage(decoding: Data(huge), maxRegionCount: 100)
        }
        huge.replaceSubrange(4..<8, with: [0x10, 0, 0, 0])
        #expect(throws: TogetherMessage.DecodingError.truncated) {
            try TogetherMessage(decoding: Data(huge), maxRegionCount: 100)
        }
        #expect(throws: TogetherMessage.DecodingError.badMagic) {
            try TogetherMessage(decoding: Data([0, 0, 1, 1]), maxRegionCount: 1)
        }
        #expect(throws: TogetherMessage.DecodingError.unsupportedVersion(2)) {
            try TogetherMessage(decoding: Data([0x50, 0x54, 2, 1]), maxRegionCount: 1)
        }
    }

    @Test func unknownKindIsDistinct() {
        #expect(throws: TogetherMessage.DecodingError.unknownKind(200)) {
            try TogetherMessage(decoding: Data([0x50, 0x54, 1, 200, 1, 2, 3]), maxRegionCount: 1)
        }
    }

    @Test func chunksStayUnderTheLimit() throws {
        let ops = (0..<20000).map { TogetherOp(region: UInt32($0), painted: true, stamp: .init(clock: 1, painter: 1)) }
        let messages = TogetherMessage.chunked(ops, origin: SIMD2(1, 1))
        #expect(messages.count == 3)
        var back: [TogetherOp] = []
        for message in messages {
            let data = message.encoded()
            #expect(data.count < 256 * 1024)
            guard case .ops(let part, let origin) = try TogetherMessage(decoding: data, maxRegionCount: 20000) else {
                Issue.record("not ops")
                return
            }
            #expect(origin == SIMD2(1, 1))
            back += part
        }
        #expect(back == ops)
        #expect(TogetherMessage.chunked([], origin: nil).isEmpty)
    }

    // MARK: Batcher

    @Test func batcherWaitsThenFlushesNewestPerArea() {
        var batcher = TogetherBatcher()
        let s = { (c: UInt64) in TogetherStamp(clock: c, painter: 1) }
        let nothing = batcher.flush(at: 0)
        #expect(nothing.isEmpty)
        batcher.add([TogetherOp(region: 1, painted: true, stamp: s(1))], at: 10)
        batcher.add(
            [
                TogetherOp(region: 2, painted: true, stamp: s(2)),
                TogetherOp(region: 1, painted: false, stamp: s(3)),
            ], at: 10.03)
        let tooSoon = batcher.flush(at: 10.04)
        #expect(tooSoon.isEmpty)
        let out = batcher.flush(at: 10.05)
        #expect(out == [TogetherOp(region: 1, painted: false, stamp: s(3)), TogetherOp(region: 2, painted: true, stamp: s(2))])
        #expect(batcher.isEmpty)
        // The window starts again with the next op, and force sends at once.
        batcher.add([TogetherOp(region: 3, painted: true, stamp: s(4))], at: 20)
        let early = batcher.flush(at: 20.01)
        #expect(early.isEmpty)
        let forced = batcher.flush(at: 20.01, force: true)
        #expect(forced.map(\.region) == [3])
        let late = batcher.flush(at: 30, force: true)
        #expect(late.isEmpty)
    }

    // MARK: Two painters through the hub

    @Test(arguments: [LoopbackHub.Mode.inOrder, .scrambled(seed: 9), .scrambled(seed: 31)])
    func twoPaintersConvergeThroughTheHub(mode: LoopbackHub.Mode) async throws {
        let hub = LoopbackHub(mode: mode)
        let (endA, endB) = hub.endpoints
        let regions = 60
        var ledgers = [TogetherLedger(regionCount: regions, painter: 1), TogetherLedger(regionCount: regions, painter: 2)]
        var batchers = [TogetherBatcher(), TogetherBatcher()]
        let ends = [endA, endB]
        var rng = SplitMix64(seed: 5)
        var time = 0.0
        for _ in 0..<200 {
            time += 0.01
            for side in 0..<2 {
                let region = Int(rng.next() % UInt64(regions))
                let ops = rng.next() % 4 == 0 ? [ledgers[side].unpaint(region)].compactMap { $0 } : ledgers[side].paint([region])
                batchers[side].add(ops, at: time)
                let flushed = batchers[side].flush(at: time)
                for message in TogetherMessage.chunked(flushed, origin: SIMD2(1, 2)) {
                    try await ends[side].send(message.encoded(), reliable: true)
                }
                try await ends[side].send(TogetherMessage.presence(point: SIMD2(3, 4), color: 0).encoded(), reliable: false)
                for data in await ends[side].receive() {
                    if case .ops(let ops, _) = try TogetherMessage(decoding: data, maxRegionCount: regions) {
                        ledgers[side].apply(ops)
                    }
                }
            }
        }
        for side in 0..<2 {
            for message in TogetherMessage.chunked(batchers[side].flush(at: time, force: true), origin: nil) {
                try await ends[side].send(message.encoded(), reliable: true)
            }
        }
        for side in 0..<2 {
            for data in await ends[side].receive() {
                if case .ops(let ops, _) = try TogetherMessage(decoding: data, maxRegionCount: regions) {
                    ledgers[side].apply(ops)
                }
            }
        }
        #expect(ledgers[0].snapshot() == ledgers[1].snapshot())
        #expect(Self.state(ledgers[0]) == Self.state(ledgers[1]))
        #expect(ledgers[0].snapshot().count > 10)
    }
}
