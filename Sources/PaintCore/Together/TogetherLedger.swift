/// When an area's paint was last set, and by whom: a Lamport clock with the painter's id
/// breaking ties, so every device orders any two changes the same way.
public struct TogetherStamp: Sendable, Hashable, Comparable {
    public var clock: UInt64
    public var painter: UInt64

    public init(clock: UInt64, painter: UInt64) {
        self.clock = clock
        self.painter = painter
    }

    /// What a painting already begun before painting together stamps its areas with: below any
    /// stamp a painter makes, so the first real change to an area wins over it.
    public static let seed = TogetherStamp(clock: 0, painter: 0)

    public static func < (a: TogetherStamp, b: TogetherStamp) -> Bool {
        (a.clock, a.painter) < (b.clock, b.painter)
    }
}

/// One area painted or cleared.
public struct TogetherOp: Sendable, Hashable {
    public var region: UInt32
    public var painted: Bool
    public var stamp: TogetherStamp

    public init(region: UInt32, painted: Bool, stamp: TogetherStamp) {
        self.region = region
        self.painted = painted
        self.stamp = stamp
    }

    /// The order two ops for the same area resolve in: the newer stamp, and for the same stamp
    /// (only a malformed peer sends two different ops with one) painted over cleared, so the
    /// result never depends on arrival order.
    func supersedes(_ other: TogetherOp) -> Bool {
        stamp != other.stamp ? stamp > other.stamp : painted && !other.painted
    }
}

/// Which areas of one template are painted, shared by everyone painting it together.
///
/// A last-writer-wins register per area: each change carries a `TogetherStamp`, and an area takes
/// the op with the greatest. Applying any set of ops, in any order and any number of times, leaves
/// every ledger in the same state, so peers converge whatever the network does, and a late joiner
/// catches up from `snapshot()` alone.
public struct TogetherLedger: Sendable, Equatable {
    public let regionCount: Int
    /// This device's painter id (random per session; 0 is the seed's).
    public let painter: UInt64
    /// The Lamport clock: above every stamp this ledger has made or seen.
    public private(set) var clock: UInt64 = 0
    private var stamps: [TogetherStamp?]
    private var painted: [Bool]

    public init(regionCount: Int, painter: UInt64) {
        self.regionCount = max(0, regionCount)
        self.painter = painter
        stamps = Array(repeating: nil, count: self.regionCount)
        painted = Array(repeating: false, count: self.regionCount)
    }

    /// A painting already begun: its painted areas stamped `TogetherStamp.seed`.
    public init(seeding painted: [Bool], painter: UInt64) {
        self.init(regionCount: painted.count, painter: painter)
        for (region, isPainted) in painted.enumerated() where isPainted {
            self.painted[region] = true
            stamps[region] = .seed
        }
    }

    public func isPainted(_ region: Int) -> Bool {
        painted.indices.contains(region) && painted[region]
    }

    /// Who painted an area, while it is painted (0 for a seeded area).
    public func paintedBy(_ region: Int) -> UInt64? {
        guard isPainted(region) else { return nil }
        return stamps[region]?.painter
    }

    /// Paints areas here; returns the ops to send. Areas already painted, or out of range, are
    /// skipped. One clock tick covers the whole call.
    public mutating func paint(_ regions: [Int]) -> [TogetherOp] {
        var ops: [TogetherOp] = []
        var stamp: TogetherStamp?
        for region in regions where painted.indices.contains(region) && !painted[region] {
            if stamp == nil { stamp = tick() }
            let op = TogetherOp(region: UInt32(region), painted: true, stamp: stamp!)
            painted[region] = true
            stamps[region] = op.stamp
            ops.append(op)
        }
        return ops
    }

    /// Clears a painted area here (an undo); returns the op to send.
    public mutating func unpaint(_ region: Int) -> TogetherOp? {
        guard isPainted(region) else { return nil }
        let op = TogetherOp(region: UInt32(region), painted: false, stamp: tick())
        painted[region] = false
        stamps[region] = op.stamp
        return op
    }

    /// Applies a peer's ops. Returns the areas whose paint changed here. Ops for areas out of
    /// range are ignored; older ones lose to what the ledger holds.
    @discardableResult
    public mutating func apply(_ ops: [TogetherOp]) -> (painted: [Int], unpainted: [Int]) {
        var changed: [Int: Bool] = [:]
        var order: [Int] = []
        for op in ops {
            let region = Int(op.region)
            guard region < regionCount else { continue }
            clock = max(clock, op.stamp.clock)
            if let current = stamps[region],
                !op.supersedes(TogetherOp(region: op.region, painted: painted[region], stamp: current))
            {
                continue
            }
            if changed[region] == nil {
                changed[region] = painted[region]
                order.append(region)
            }
            stamps[region] = op.stamp
            painted[region] = op.painted
        }
        var nowPainted: [Int] = []
        var nowUnpainted: [Int] = []
        for region in order where changed[region] != painted[region] {
            if painted[region] { nowPainted.append(region) } else { nowUnpainted.append(region) }
        }
        return (nowPainted, nowUnpainted)
    }

    /// Every area ever stamped, as ops: what a late joiner applies to catch up.
    public func snapshot() -> [TogetherOp] {
        stamps.indices.compactMap { region in
            stamps[region].map { TogetherOp(region: UInt32(region), painted: painted[region], stamp: $0) }
        }
    }

    private mutating func tick() -> TogetherStamp {
        clock &+= 1
        return TogetherStamp(clock: clock, painter: painter)
    }
}
