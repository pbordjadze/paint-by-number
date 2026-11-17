/// Gathers the ops a painter makes and lets them go at most every `interval` seconds, so a fast
/// drag across many areas reaches the peer as a few messages instead of one per area.
public struct TogetherBatcher: Sendable {
    public let interval: Double
    private var pending: [TogetherOp] = []
    private var firstPending: Double?

    public init(interval: Double = 0.05) {
        self.interval = interval
    }

    public var isEmpty: Bool { pending.isEmpty }

    public mutating func add(_ ops: [TogetherOp], at time: Double) {
        guard !ops.isEmpty else { return }
        if firstPending == nil { firstPending = time }
        pending.append(contentsOf: ops)
    }

    /// The ops to send now: everything pending once `interval` has passed since the first of
    /// them (or when forced), one op per area, the newest; otherwise none.
    public mutating func flush(at time: Double, force: Bool = false) -> [TogetherOp] {
        guard let first = firstPending, force || time - first >= interval else { return [] }
        var index: [UInt32: Int] = [:]
        var out: [TogetherOp] = []
        for op in pending {
            if let i = index[op.region] {
                if op.supersedes(out[i]) { out[i] = op }
            } else {
                index[op.region] = out.count
                out.append(op)
            }
        }
        pending.removeAll(keepingCapacity: true)
        firstPending = nil
        return out
    }
}
