/// A flattened curve and which of its points must stay put (junction ends, corners).
struct DenseCurve {
    var points: [SIMD2<Double>] = []
    var pinned: [Bool] = []

    mutating func removeAll() {
        points.removeAll(keepingCapacity: true)
        pinned.removeAll(keepingCapacity: true)
    }

    /// Appends a point, merging it into the previous one when they coincide.
    mutating func append(_ p: SIMD2<Double>, pinned pin: Bool) {
        if let last = points.last, last == p {
            if pin { pinned[pinned.count - 1] = true }
            return
        }
        points.append(p)
        pinned.append(pin)
    }
}
